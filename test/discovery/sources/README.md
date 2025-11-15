# Discovery Source Testing Guide

## Purpose

This guide explains how to write, organize, and maintain tests for event discovery sources (scrapers). Discovery sources fetch events from external platforms like Bandsintown, Quizmeisters, Sortiraparis, etc.

**Goal:** Ensure scrapers reliably extract and transform event data from various sources.

## Source Test Structure

### Standard Structure

Each source should follow this standard structure:

```
test/discovery/sources/<source_name>/
├── transformer_test.exs       # REQUIRED - Tests data transformation
├── extractors/               # OPTIONAL - For complex scraping
│   ├── venue_extractor_test.exs
│   ├── date_extractor_test.exs
│   └── title_extractor_test.exs
├── helpers/                  # OPTIONAL - Source-specific helpers
│   └── time_parser_test.exs
├── jobs/                     # OPTIONAL - Background job testing
│   └── sync_job_test.exs
└── fixtures/                 # REQUIRED - Test HTML/JSON files
    ├── event_detail.html
    ├── event_list.html
    ├── api_response.json
    └── special_case.html
```

### Minimal Source Structure

At minimum, every source **must have:**

1. **transformer_test.exs** - Tests the main transformation logic
2. **fixtures/** - Sample HTML/JSON from the source

```
test/discovery/sources/bandsintown/
├── transformer_test.exs
└── fixtures/
    └── event_response.json
```

### Complex Source Structure

Complex sources may have additional subdirectories:

```
test/discovery/sources/quizmeisters/
├── transformer_test.exs       # Main transformation logic
├── extractors/               # Individual data extractors
│   ├── venue_extractor_test.exs
│   └── venue_details_extractor_test.exs
├── helpers/                  # Parsing helpers
│   └── time_parser_test.exs
├── jobs/                     # Background jobs
│   └── sync_job_test.exs
└── fixtures/                 # Test data
    ├── detail_page.html
    ├── detail_page_on_break.html
    └── api_response.json
```

## Test Types for Discovery Sources

### 1. Transformer Tests (REQUIRED)

**Purpose:** Test the main transformation logic that converts scraped data into event attributes.

**Location:** `test/discovery/sources/<source>/transformer_test.exs`

**Example:**

```elixir
defmodule EventasaurusDiscovery.Sources.Bandsintown.TransformerTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Sources.Bandsintown.Transformer

  describe "transform/1" do
    test "transforms API event to event attributes" do
      event_data = %{
        "title" => "Concert at Venue",
        "datetime" => "2024-06-15T20:00:00",
        "venue" => %{
          "name" => "Music Hall",
          "city" => "Warsaw",
          "country" => "Poland"
        },
        "description" => "Live music event",
        "url" => "https://bandsintown.com/event/123"
      }

      assert {:ok, attrs} = Transformer.transform(event_data)

      assert attrs.title == "Concert at Venue"
      assert attrs.venue_name == "Music Hall"
      assert attrs.city == "Warsaw"
      assert attrs.source == "bandsintown"
      assert attrs.source_url == "https://bandsintown.com/event/123"
    end

    test "handles missing optional fields" do
      event_data = %{
        "title" => "Concert",
        "datetime" => "2024-06-15T20:00:00",
        "venue" => %{"name" => "Venue"}
        # description missing
      }

      assert {:ok, attrs} = Transformer.transform(event_data)
      assert attrs.description == nil
    end

    test "returns error for invalid data" do
      invalid_data = %{"invalid" => "data"}

      assert {:error, reason} = Transformer.transform(invalid_data)
      assert reason =~ "missing required field"
    end
  end
end
```

### 2. Extractor Tests (OPTIONAL)

**Purpose:** Test individual data extraction logic for complex scraping.

**Location:** `test/discovery/sources/<source>/extractors/`

**Example:**

```elixir
defmodule EventasaurusDiscovery.Sources.Quizmeisters.VenueExtractorTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Sources.Quizmeisters.VenueExtractor

  describe "extract_venue_name/1" do
    test "extracts venue name from detail page" do
      html = read_fixture("detail_page.html")

      assert {:ok, "The Quiz Pub"} = VenueExtractor.extract_venue_name(html)
    end

    test "handles missing venue" do
      html = "<html><body></body></html>"

      assert {:error, :venue_not_found} = VenueExtractor.extract_venue_name(html)
    end
  end

  defp read_fixture(filename) do
    Path.join([__DIR__, "../fixtures", filename])
    |> File.read!()
  end
end
```

### 3. Helper Tests (OPTIONAL)

**Purpose:** Test source-specific parsing utilities.

**Location:** `test/discovery/sources/<source>/helpers/`

**Example:**

```elixir
defmodule EventasaurusDiscovery.Sources.Quizmeisters.TimeParserTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Quizmeisters.TimeParser

  describe "parse_time/1" do
    test "parses 24-hour time format" do
      assert {:ok, ~T[19:30:00]} = TimeParser.parse_time("19:30")
    end

    test "parses 12-hour time format" do
      assert {:ok, ~T[19:30:00]} = TimeParser.parse_time("7:30 PM")
    end

    test "handles Polish time formats" do
      assert {:ok, ~T[20:00:00]} = TimeParser.parse_time("20.00")
    end

    test "returns error for invalid format" do
      assert {:error, _} = TimeParser.parse_time("invalid")
    end
  end
end
```

### 4. Job Tests (OPTIONAL)

**Purpose:** Test background sync jobs.

**Location:** `test/discovery/sources/<source>/jobs/`

**Note:** Tag with `:external_api` if making real API calls.

```elixir
defmodule EventasaurusDiscovery.Sources.Quizmeisters.SyncJobTest do
  use EventasaurusApp.DataCase

  @moduletag :external_api

  alias EventasaurusDiscovery.Sources.Quizmeisters.SyncJob

  describe "perform/1" do
    test "fetches and imports events" do
      assert {:ok, result} = SyncJob.perform(%{})

      assert result.events_imported > 0
      assert result.venues_created >= 0
    end

    test "handles API errors gracefully" do
      # Test with mock/error scenario
      assert {:error, reason} = SyncJob.perform(%{invalid: true})
    end
  end
end
```

## Fixture Management

### Creating Fixtures

**Best Practices:**

1. **Capture Real Data:** Save actual HTML/JSON responses from sources
2. **Minimal Examples:** Keep fixtures focused on what you're testing
3. **Multiple Scenarios:** Create fixtures for edge cases
4. **Update Regularly:** Keep fixtures current with source changes

**Example Fixture Directory:**

```
fixtures/
├── event_detail.html          # Standard event detail page
├── event_detail_sold_out.html # Sold out scenario
├── event_detail_cancelled.html # Cancelled event
├── event_list.html            # List of events
├── api_response.json          # API response
└── special_characters.html    # UTF-8 handling
```

### Reading Fixtures

```elixir
defmodule MySourceTest do
  use EventasaurusApp.DataCase, async: true

  # Helper function to read fixtures
  defp read_fixture(filename) do
    Path.join([__DIR__, "fixtures", filename])
    |> File.read!()
  end

  test "parses event from HTML" do
    html = read_fixture("event_detail.html")
    assert {:ok, event} = Parser.parse(html)
  end
end
```

### Fixture Naming Conventions

```
✅ Good:
- event_detail.html
- event_list_page_1.html
- api_response_success.json
- venue_with_special_chars.html
- date_format_variant_1.html

❌ Bad:
- test1.html
- data.json
- file.html
- response.txt
```

## External API Testing

### Tagging External API Tests

**Always tag tests that make real API calls:**

```elixir
defmodule EventasaurusDiscovery.BandsintownAPITest do
  use EventasaurusApp.DataCase

  @moduletag :external_api  # REQUIRED!

  test "fetches events from API" do
    # Makes real API call
    assert {:ok, events} = BandsintownAPI.fetch_events("Warsaw")
  end
end
```

### Running External API Tests

```bash
# External API tests are excluded by default
mix test

# Run only external API tests
mix test --only external_api

# Run source tests excluding external API
mix test test/discovery/sources/bandsintown/ --exclude external_api
```

### Mocking External APIs

**For unit tests, mock HTTP responses:**

```elixir
test "handles API response" do
  # Use fixture instead of real API call
  response = read_fixture("api_response.json")
  parsed = Jason.decode!(response)

  assert {:ok, events} = Transformer.transform(parsed)
end
```

## Common Testing Patterns

### Testing HTML Parsing

```elixir
test "extracts event title from HTML" do
  html = """
  <html>
    <body>
      <h1 class="event-title">Summer Concert</h1>
    </body>
  </html>
  """

  assert {:ok, "Summer Concert"} = Parser.extract_title(html)
end
```

### Testing Date Parsing

```elixir
describe "parse_date/1" do
  test "parses ISO 8601 format" do
    assert {:ok, ~D[2024-06-15]} = DateParser.parse("2024-06-15")
  end

  test "parses European format" do
    assert {:ok, ~D[2024-06-15]} = DateParser.parse("15.06.2024")
  end

  test "parses relative dates" do
    assert {:ok, date} = DateParser.parse("tomorrow")
    assert date == Date.add(Date.utc_today(), 1)
  end
end
```

### Testing URL Construction

```elixir
test "builds event URL from ID" do
  assert URLBuilder.event_url("123") ==
    "https://example.com/events/123"
end

test "handles special characters in URLs" do
  assert URLBuilder.event_url("event/with/slash") ==
    "https://example.com/events/event%2Fwith%2Fslash"
end
```

### Testing UTF-8 Handling

```elixir
test "handles Polish characters" do
  html = read_fixture("polish_characters.html")

  assert {:ok, attrs} = Parser.parse(html)
  assert attrs.title == "Kraków Quiz Night"
  assert attrs.venue_name == "Café Młodzieżowa"
end

test "handles emoji in descriptions" do
  text = "Concert 🎵 at venue 🎸"

  assert {:ok, attrs} = Parser.parse_description(text)
  assert attrs.description =~ "🎵"
end
```

### Testing Error Handling

```elixir
test "returns error for missing required field" do
  invalid_data = %{"description" => "Event"}
  # title missing

  assert {:error, :missing_title} = Transformer.transform(invalid_data)
end

test "handles network errors" do
  assert {:error, :network_error} = API.fetch_with_error()
end

test "handles rate limiting" do
  assert {:error, :rate_limited} = API.fetch_rate_limited()
end
```

## Integration Testing

### Full Pipeline Tests

**Location:** `test/discovery/integration/`

```elixir
defmodule EventasaurusDiscovery.Integration.BandsintownPipelineTest do
  use EventasaurusApp.DataCase

  @moduletag :integration
  @moduletag :external_api

  test "complete pipeline: fetch -> transform -> import" do
    # Fetch from API
    assert {:ok, raw_events} = BandsintownAPI.fetch_events("Warsaw")

    # Transform
    transformed = Enum.map(raw_events, fn event ->
      {:ok, attrs} = Transformer.transform(event)
      attrs
    end)

    # Import
    assert {:ok, results} = Importer.import_events(transformed)
    assert results.imported_count > 0
  end
end
```

## Source Test Template

### Quick Start Template

When adding a new source, use this template:

```elixir
defmodule EventasaurusDiscovery.Sources.NewSource.TransformerTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Sources.NewSource.Transformer

  describe "transform/1" do
    test "transforms source data to event attributes" do
      # Arrange
      source_data = read_fixture("event_data.json") |> Jason.decode!()

      # Act
      assert {:ok, attrs} = Transformer.transform(source_data)

      # Assert
      assert attrs.title
      assert attrs.start_time
      assert attrs.venue_name
      assert attrs.source == "new_source"
    end

    test "handles missing optional fields" do
      source_data = %{
        "title" => "Event",
        "date" => "2024-06-15"
        # description missing
      }

      assert {:ok, attrs} = Transformer.transform(source_data)
      assert is_nil(attrs.description)
    end

    test "returns error for invalid data" do
      invalid_data = %{}

      assert {:error, _reason} = Transformer.transform(invalid_data)
    end
  end

  defp read_fixture(filename) do
    Path.join([__DIR__, "fixtures", filename])
    |> File.read!()
  end
end
```

## Best Practices

### DO ✅

- **Use fixtures** for HTML/JSON test data
- **Tag external API tests** with `:external_api`
- **Test edge cases** (missing data, special characters, date formats)
- **Keep fixtures minimal** and focused
- **Test error handling** for network/parsing errors
- **Use async tests** when possible
- **Document complex parsing logic** in test names
- **Keep transformers pure** (no side effects)

### DON'T ❌

- **Don't make real API calls in unit tests** (use fixtures)
- **Don't skip `:external_api` tags** (they're excluded by default for good reason)
- **Don't hardcode expected values** (use descriptive assertions)
- **Don't test HTML structure details** (test extracted data)
- **Don't create huge fixtures** (keep them focused)
- **Don't forget UTF-8 test cases** (many sources use non-ASCII)
- **Don't skip error scenarios** (test what happens when source changes)

## Troubleshooting

### Fixture Not Found

**Problem:** `File.read!` raises error

**Solution:**
```elixir
# Ensure correct path
defp read_fixture(filename) do
  # Use __DIR__ for current test file directory
  Path.join([__DIR__, "fixtures", filename])
  |> File.read!()
end
```

### UTF-8 Encoding Issues

**Problem:** Special characters not handled correctly

**Solution:**
```elixir
# Ensure UTF-8 encoding
html = File.read!(path, [:utf8])

# Or when creating fixtures
File.write!(path, content, [:utf8])
```

### External API Tests Timing Out

**Problem:** API tests fail with timeout

**Solution:**
```elixir
# Increase timeout for slow APIs
@moduletag timeout: 60_000  # 60 seconds

test "slow API call" do
  # ...
end
```

### Flaky Parsing Tests

**Problem:** Tests fail intermittently

**Solution:**
```elixir
# Don't depend on dynamic content
❌ Bad:
test "extracts current events" do
  events = fetch_and_parse()
  assert length(events) > 0  # Flaky!
end

✅ Good:
test "parses event from fixture" do
  html = read_fixture("event_list.html")
  assert {:ok, events} = Parser.parse(html)
  assert length(events) == 3  # Deterministic
end
```

## Testing Checklist

When adding tests for a new source:

- [ ] Created `transformer_test.exs`
- [ ] Created `fixtures/` directory
- [ ] Added sample fixtures from real source
- [ ] Tested successful transformation
- [ ] Tested missing optional fields
- [ ] Tested error cases
- [ ] Tested UTF-8/special characters
- [ ] Tested date parsing edge cases
- [ ] Tagged external API tests with `:external_api`
- [ ] Documented special parsing logic
- [ ] Tests run fast (<100ms each)
- [ ] All tests pass

## Examples from Existing Sources

### Simple Source (Bandsintown)

```
test/discovery/sources/bandsintown/
└── transformer_test.exs
```

**Characteristics:**
- Simple API response transformation
- No complex extractors needed
- Tests transformation only

### Complex Source (Quizmeisters)

```
test/discovery/sources/quizmeisters/
├── transformer_test.exs
├── extractors/
│   ├── venue_extractor_test.exs
│   └── venue_details_extractor_test.exs
├── helpers/
│   └── time_parser_test.exs
├── jobs/
│   └── sync_job_test.exs
└── fixtures/
    ├── detail_page.html
    ├── detail_page_on_break.html
    └── api_response.json
```

**Characteristics:**
- Complex HTML scraping
- Multiple extraction steps
- Custom parsing logic
- Background sync jobs

## Related Documentation

- **[test/README.md](../../README.md)** - Main test suite documentation
- **[test/BEST_PRACTICES.md](../../BEST_PRACTICES.md)** - General testing best practices
- **[test/discovery/unit/README.md](../unit/README.md)** - Discovery unit testing (when created)

---

_For questions about discovery source testing, consult the team wiki or ask in #discovery-engineering._
