# PostgreSQL UTF-8 Boundary Protection Strategy

## Executive Summary

**The Problem**: Ticketmaster's production API returns JSON with corrupt UTF-8 sequences (e.g., `0xe2 0x20 0x46` instead of proper en-dash `0xe2 0x80 0x93`). PostgreSQL rejects these sequences when storing data in JSONB columns, causing Oban job failures and event processing errors.

**The Failed Approach**: Issue #1336's "Option A" (single boundary validation at HTTP entry) failed because PostgreSQL enforces UTF-8 at MULTIPLE boundaries, not just data insertion.

**The Solution**: Implement "PostgreSQL Boundary Protection" - validate and fix UTF-8 at every point where data touches PostgreSQL.

## The Real Problem

### What We Thought
- UTF-8 validation was redundant
- We could validate once at HTTP entry and trust data internally
- Performance would improve with fewer validations

### What Actually Happens
1. **Ticketmaster API** returns JSON with bytes that parse as valid JSON but contain invalid UTF-8
2. **Jason.decode** creates Elixir strings from these bytes (strings are now corrupt in memory)
3. **Oban.insert** tries to store these strings in PostgreSQL JSONB columns
4. **PostgreSQL** rejects with: `invalid byte sequence for encoding UTF8: 0xe2 0x20 0x46`
5. **Jobs fail repeatedly** because the corrupt data is already stored in Oban's args

### Why Option A Failed

**Critical Insight**: PostgreSQL enforces UTF-8 at EVERY text operation:
- Storing Oban job args (JSONB)
- Inserting events/venues (text columns)
- Running similarity queries (text parameters)
- Executing full-text searches
- Any operation involving text

**The Misconception**: We thought of this as an "HTTP boundary" problem. It's actually a "PostgreSQL boundary" problem.

## PostgreSQL Boundaries in Our System

### 1. Oban Job Storage
```elixir
# When we do this:
EventProcessorJob.new(%{event_data: data}) |> Oban.insert()
# PostgreSQL validates UTF-8 in the JSONB column
```

### 2. Model Persistence
```elixir
# When we insert events/venues:
%PublicEvent{} |> changeset(attrs) |> Repo.insert()
# PostgreSQL validates UTF-8 in all text columns
```

### 3. Similarity Queries
```elixir
# When we run similarity checks:
from(e in Event, where: fragment("similarity(?, ?) > 0.7", e.title, ^title))
# PostgreSQL validates UTF-8 in the query parameter
```

### 4. Text Search
```elixir
# When we search:
from(e in Event, where: fragment("? @@ plainto_tsquery(?)", e.search_vector, ^query))
# PostgreSQL validates UTF-8 in the search query
```

## The Correct Solution

### Core Principle
**"Validate at PostgreSQL Boundaries, Not HTTP Boundaries"**

Every point where data enters PostgreSQL needs UTF-8 validation. This isn't redundancy - it's protecting different PostgreSQL operations.

### Implementation Strategy

#### 1. Enhanced UTF8 Module
```elixir
defmodule EventasaurusDiscovery.Utils.UTF8 do
  # Fast path: check if already valid
  def ensure_valid_utf8(string) when is_binary(string) do
    if String.valid?(string) do
      string  # No work needed - fast return
    else
      fix_corrupt_utf8(string)  # Only fix when needed
    end
  end

  # Aggressive fix for known Ticketmaster corruption patterns
  defp fix_corrupt_utf8(binary) do
    binary
    |> fix_known_patterns()     # Fix specific byte sequences
    |> ensure_valid_general()    # General UTF-8 cleanup
  end

  defp fix_known_patterns(binary) do
    binary
    # Ticketmaster en-dash corruption
    |> :binary.replace(<<0xe2, 0x20, 0x46>>, " - F")
    |> :binary.replace(<<0xe2, 0x20>>, " - ")
    # Add more patterns as discovered
  end
end
```

#### 2. Validation Points

##### HTTP Clients (After JSON Decode)
```elixir
# In Ticketmaster.Client
case Jason.decode(response_body) do
  {:ok, data} ->
    # Fix UTF-8 immediately after decode
    clean_data = UTF8.validate_map_strings(data)
    {:ok, clean_data}
end
```

##### Oban Job Creation
```elixir
# In SyncJob when scheduling EventProcessorJobs
clean_event = UTF8.validate_map_strings(event)
EventProcessorJob.new(%{event_data: clean_event})
|> Oban.insert()
```

##### Oban Job Execution
```elixir
# In EventProcessorJob.perform
def perform(%{args: args}) do
  # Clean potentially corrupt data from DB
  clean_args = UTF8.validate_map_strings(args)
  # Process with clean data
end
```

##### Model Changesets
```elixir
# In PublicEvent and Venue changesets
defp sanitize_utf8(changeset) do
  changeset
  |> update_change(:title, &UTF8.ensure_valid_utf8/1)
  |> update_change(:description, &UTF8.ensure_valid_utf8/1)
end
```

##### Query Parameters
```elixir
# Before similarity queries
clean_title = UTF8.ensure_valid_utf8(title)
from(e in Event, where: fragment("similarity(?, ?) > ?", e.title, ^clean_title, 0.7))
```

### Why This Isn't Redundant

Each validation protects a DIFFERENT PostgreSQL operation:
1. **HTTP Client**: Prevents corrupt data from entering our system
2. **Job Creation**: Prevents Oban insert failures
3. **Job Execution**: Handles already-corrupt jobs in DB
4. **Model Changesets**: Prevents event/venue insert failures
5. **Query Parameters**: Prevents query execution failures

Remove any one, and that specific PostgreSQL operation can fail.

## Performance Optimization

### 1. Fast-Path Validation
```elixir
# Check validity first (fast), only fix if needed (slower)
if String.valid?(string), do: string, else: fix_corrupt_utf8(string)
```

### 2. Caching Within Request
```elixir
# Use process dictionary for request-level caching
def ensure_valid_cached(string) do
  cache_key = :erlang.phash2(string)
  case Process.get({:utf8_cache, cache_key}) do
    nil ->
      clean = ensure_valid_utf8(string)
      Process.put({:utf8_cache, cache_key}, clean)
      clean
    cached ->
      cached
  end
end
```

### 3. Batch Validation
```elixir
# Validate entire maps/lists in one pass
def validate_map_strings(map) when is_map(map) do
  # Single traversal, fix all strings
end
```

## Migration Path

### Option 1: Fix Forward (Recommended)
1. Keep current codebase
2. Add aggressive UTF-8 fixing to Utils.UTF8 module
3. Ensure validation at all PostgreSQL boundaries
4. Deploy and monitor

### Option 2: Revert and Enhance
1. Revert to commit `0bb97859` (working UTF-8 implementation)
2. Add aggressive pattern fixing to UTF8 module
3. Add validation after JSON decode in HTTP clients
4. Add validation at Oban job creation

### Option 3: Hybrid Approach
1. Cherry-pick working validations from `0bb97859`
2. Keep current HTTP client improvements
3. Add PostgreSQL boundary validations
4. Add aggressive pattern fixing

## Testing Strategy

### 1. Create Corruption Test Cases
```elixir
# test/utf8_corruption_test.exs
@corruptions [
  # Ticketmaster en-dash pattern
  <<0xe2, 0x20, 0x46>>,
  # Other known patterns
  <<0xe2, 0x20>>,
  # Truncated sequences
  <<0xe2>>,
]

test "handles all known corruption patterns" do
  for corruption <- @corruptions do
    assert String.valid?(UTF8.ensure_valid_utf8(corruption))
  end
end
```

### 2. PostgreSQL Boundary Tests
```elixir
test "Oban job creation with corrupt data" do
  corrupt_data = %{title: <<0xe2, 0x20, 0x46>>}
  assert {:ok, _job} = EventProcessorJob.new(%{data: corrupt_data}) |> Oban.insert()
end

test "Model insertion with corrupt data" do
  assert {:ok, _event} = %PublicEvent{} |> changeset(%{title: <<0xe2, 0x20, 0x46>>}) |> Repo.insert()
end

test "Similarity query with corrupt parameter" do
  corrupt_title = <<0xe2, 0x20, 0x46>>
  assert [] = Repo.all(from e in Event, where: fragment("similarity(?, ?) > 0.7", e.title, ^corrupt_title))
end
```

### 3. Integration Tests
```elixir
test "full pipeline with Ticketmaster corruption" do
  # Mock Ticketmaster response with corrupt UTF-8
  # Verify entire pipeline handles it correctly
end
```

## Monitoring & Observability

### 1. Add UTF-8 Telemetry
```elixir
def ensure_valid_utf8(string) do
  if String.valid?(string) do
    :telemetry.execute([:utf8, :valid], %{count: 1})
    string
  else
    :telemetry.execute([:utf8, :fixed], %{count: 1})
    Logger.info("UTF-8 corruption fixed", pattern: detect_pattern(string))
    fix_corrupt_utf8(string)
  end
end
```

### 2. Track PostgreSQL Rejections
```elixir
rescue
  Postgrex.Error ->
    :telemetry.execute([:postgresql, :utf8_rejection], %{count: 1})
    Logger.error("PostgreSQL UTF-8 rejection", data: inspect(data))
```

## Success Criteria

1. **Zero PostgreSQL UTF-8 rejections** in production logs
2. **All Oban jobs execute successfully** without encoding errors
3. **Performance impact < 5ms** per request
4. **No corrupt data** in database

## Recommendations

### Immediate Actions
1. **Deploy UTF-8 fixes** with aggressive pattern matching for known corruptions
2. **Add validation** at all PostgreSQL boundaries
3. **Monitor** PostgreSQL rejection errors

### Long-term Actions
1. **Work with Ticketmaster** to fix UTF-8 encoding at source
2. **Build corruption pattern library** from production data
3. **Consider binary storage** for raw API responses (store original, process cleaned)

## Conclusion

The "piecemeal" approach was correct. What seemed like redundancy was actually necessary protection at each PostgreSQL boundary. The issue isn't architectural elegance - it's PostgreSQL's strict UTF-8 enforcement.

**The rule is simple**: Any data that will touch PostgreSQL must be valid UTF-8. Validate at every PostgreSQL boundary, not just HTTP boundaries.