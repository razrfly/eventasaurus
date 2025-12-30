# Local LLM Event Quality Validation

**Issue Reference**: [#2923](https://github.com/razrfly/eventasaurus/issues/2923)
**Status**: Proposal / Brainstorm
**Created**: 2024-12-30

## Overview

This document proposes using a local lightweight LLM to enhance event quality checking during scraping. The approach starts with category suggestions and expands to comprehensive "smell test" validation.

## Problem Statement

Current validation is rule-based:
- Missing required fields (title, date, venue)
- Invalid date formats
- URL validation
- Duplicate detection

**What we can't catch with rules:**
- "Comedy Night at Pizza Hut" categorized as "Food & Drink" instead of "Comedy"
- Event descriptions that don't match the title
- Nonsensical venue/event combinations
- Scraped garbage that passes field validation
- Events with placeholder text still present

## Proposed Solution

### Phase 1: Category Suggestion (Development Only)

Use a local LLM to suggest categories for events, especially those falling into "other" or seeming miscategorized.

**Target Model**: `qwen2.5:0.5b` or `phi3:mini` via Ollama (runs on CPU, <1GB RAM)

### Phase 2: Event Quality Validation

Expand to full "smell test" - semantic validation that catches issues rules can't detect.

---

## Architecture

### Module Structure

```
lib/eventasaurus_discovery/ai/
├── local_llm.ex           # Ollama HTTP client
├── category_suggester.ex  # Category recommendation
├── event_validator.ex     # Smell test validation
└── quality_checker.ex     # Orchestration & reporting
```

### LocalLLM Client

```elixir
defmodule EventasaurusDiscovery.AI.LocalLLM do
  @moduledoc """
  Lightweight Ollama client for local LLM inference.
  Development-only - no production dependencies.
  """

  @default_model "qwen2.5:0.5b"
  @default_timeout 30_000
  @ollama_url "http://localhost:11434"

  def generate(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    body = Jason.encode!(%{
      model: model,
      prompt: prompt,
      stream: false,
      options: %{
        temperature: 0.1,  # Low temperature for consistent outputs
        num_predict: 200   # Limit response length
      }
    })

    case Req.post("#{@ollama_url}/api/generate", body: body, receive_timeout: timeout) do
      {:ok, %{status: 200, body: %{"response" => response}}} ->
        {:ok, String.trim(response)}
      {:ok, %{status: status, body: body}} ->
        {:error, {:ollama_error, status, body}}
      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  def available? do
    case Req.get("#{@ollama_url}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  def models do
    case Req.get("#{@ollama_url}/api/tags", receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        {:ok, Enum.map(models, & &1["name"])}
      _ ->
        {:error, :unavailable}
    end
  end
end
```

### Category Suggester

```elixir
defmodule EventasaurusDiscovery.AI.CategorySuggester do
  @moduledoc """
  Uses local LLM to suggest event categories.
  Helpful for events falling into "other" or potentially miscategorized.
  """

  alias EventasaurusDiscovery.AI.LocalLLM
  alias EventasaurusDiscovery.Categories

  @categories_prompt """
  You are an event categorization assistant. Given an event, suggest the most appropriate category.

  Available categories:
  - music (concerts, festivals, live performances)
  - comedy (standup, improv, comedy shows)
  - theater (plays, musicals, drama)
  - film (movies, screenings, film festivals)
  - sports (games, matches, competitions)
  - food_drink (tastings, food festivals, dining events)
  - arts (exhibitions, galleries, art shows)
  - education (workshops, classes, lectures)
  - nightlife (clubs, parties, DJ events)
  - family (kids events, family-friendly activities)
  - community (meetups, markets, local events)
  - other (only if truly doesn't fit above)

  Respond with ONLY the category name, nothing else.

  Event: %{title}
  Description: %{description}
  Venue: %{venue}

  Category:
  """

  def suggest(event) do
    prompt = format_prompt(event)

    case LocalLLM.generate(prompt) do
      {:ok, response} ->
        category = normalize_category(response)
        confidence = calculate_confidence(event, category)
        {:ok, %{category: category, confidence: confidence, raw_response: response}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def suggest_batch(events, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 2)

    events
    |> Task.async_stream(&suggest/1, max_concurrency: concurrency, timeout: 60_000)
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)
  end

  defp format_prompt(event) do
    @categories_prompt
    |> String.replace("%{title}", event.title || "Unknown")
    |> String.replace("%{description}", truncate(event.description, 500) || "No description")
    |> String.replace("%{venue}", event.venue_name || "Unknown venue")
  end

  defp normalize_category(response) do
    response
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^a-z_]/, "")
  end

  defp calculate_confidence(event, suggested) do
    current = event.category_slug

    cond do
      current == suggested -> :high
      current == "other" -> :medium
      true -> :low
    end
  end

  defp truncate(nil, _), do: nil
  defp truncate(text, max) when byte_size(text) > max do
    String.slice(text, 0, max) <> "..."
  end
  defp truncate(text, _), do: text
end
```

### Event Validator (Smell Test)

```elixir
defmodule EventasaurusDiscovery.AI.EventValidator do
  @moduledoc """
  Semantic validation - catches issues that rule-based validation misses.
  The "smell test" for scraped events.
  """

  alias EventasaurusDiscovery.AI.LocalLLM

  @validation_prompt """
  You are an event data quality checker. Analyze this event and identify any issues.

  Event Details:
  - Title: %{title}
  - Description: %{description}
  - Category: %{category}
  - Venue: %{venue}
  - Date: %{date}
  - Price: %{price}

  Check for these issues:
  1. CATEGORY_MISMATCH: Category doesn't match the event type
  2. VENUE_MISMATCH: Venue seems wrong for this event type
  3. DESCRIPTION_MISMATCH: Description doesn't match the title
  4. PLACEHOLDER_TEXT: Contains placeholder or template text
  5. GARBAGE_DATA: Nonsensical or corrupted data
  6. PRICE_SUSPICIOUS: Price seems unrealistic for event type
  7. DUPLICATE_INDICATORS: Looks like duplicate/test data

  If issues found, respond with: ISSUE: <issue_type> - <brief explanation>
  If no issues, respond with: OK

  Analysis:
  """

  @issue_types ~w(
    category_mismatch
    venue_mismatch
    description_mismatch
    placeholder_text
    garbage_data
    price_suspicious
    duplicate_indicators
  )

  def validate(event) do
    prompt = format_prompt(event)

    case LocalLLM.generate(prompt, timeout: 45_000) do
      {:ok, response} ->
        parse_validation_response(response, event)
      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate_batch(events, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 2)

    events
    |> Task.async_stream(&validate/1, max_concurrency: concurrency, timeout: 90_000)
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, reason}
    end)
  end

  defp format_prompt(event) do
    @validation_prompt
    |> String.replace("%{title}", event.title || "Missing")
    |> String.replace("%{description}", truncate(event.description, 300) || "None")
    |> String.replace("%{category}", event.category || "Uncategorized")
    |> String.replace("%{venue}", event.venue_name || "Unknown")
    |> String.replace("%{date}", format_date(event.start_date))
    |> String.replace("%{price}", format_price(event))
  end

  defp parse_validation_response(response, event) do
    response = String.trim(response)

    cond do
      String.starts_with?(String.upcase(response), "OK") ->
        {:ok, %{status: :valid, issues: [], event_id: event.id}}

      String.contains?(String.upcase(response), "ISSUE:") ->
        issues = extract_issues(response)
        {:ok, %{status: :issues_found, issues: issues, event_id: event.id, raw: response}}

      true ->
        # Uncertain response - flag for review
        {:ok, %{status: :uncertain, issues: [], event_id: event.id, raw: response}}
    end
  end

  defp extract_issues(response) do
    response
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "ISSUE:"))
    |> Enum.map(fn line ->
      case Regex.run(~r/ISSUE:\s*(\w+)\s*-\s*(.+)/i, line) do
        [_, type, explanation] ->
          %{type: normalize_issue_type(type), explanation: String.trim(explanation)}
        _ ->
          %{type: :unknown, explanation: line}
      end
    end)
  end

  defp normalize_issue_type(type) do
    normalized = type |> String.downcase() |> String.replace(" ", "_")
    if normalized in @issue_types, do: String.to_atom(normalized), else: :unknown
  end

  defp truncate(nil, _), do: nil
  defp truncate(text, max) when byte_size(text) > max do
    String.slice(text, 0, max) <> "..."
  end
  defp truncate(text, _), do: text

  defp format_date(nil), do: "Unknown"
  defp format_date(date), do: to_string(date)

  defp format_price(%{price_min: min, price_max: max}) when not is_nil(min) and not is_nil(max) do
    "#{min}-#{max}"
  end
  defp format_price(%{price_min: min}) when not is_nil(min), do: to_string(min)
  defp format_price(_), do: "Unknown"
end
```

### Quality Checker (Orchestration)

```elixir
defmodule EventasaurusDiscovery.AI.QualityChecker do
  @moduledoc """
  Orchestrates AI-based quality checking.
  Development tool for auditing scraped event quality.
  """

  alias EventasaurusDiscovery.AI.{CategorySuggester, EventValidator, LocalLLM}
  alias Eventasaurus.Repo
  import Ecto.Query

  def check_ollama_status do
    if LocalLLM.available?() do
      case LocalLLM.models() do
        {:ok, models} -> {:ok, %{status: :available, models: models}}
        _ -> {:ok, %{status: :available, models: []}}
      end
    else
      {:error, :ollama_unavailable}
    end
  end

  def audit_categories(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    source = Keyword.get(opts, :source, nil)
    only_other = Keyword.get(opts, :only_other, true)

    events = fetch_events_for_audit(limit, source, only_other)

    results = CategorySuggester.suggest_batch(events, concurrency: 2)

    mismatches =
      Enum.zip(events, results)
      |> Enum.filter(fn {event, result} ->
        case result do
          {:ok, %{category: suggested}} ->
            suggested != event.category_slug && suggested != "other"
          _ ->
            false
        end
      end)
      |> Enum.map(fn {event, {:ok, suggestion}} ->
        %{
          event_id: event.id,
          external_id: event.external_id,
          title: event.title,
          current_category: event.category_slug,
          suggested_category: suggestion.category,
          confidence: suggestion.confidence
        }
      end)

    %{
      total_checked: length(events),
      mismatches_found: length(mismatches),
      mismatches: mismatches,
      checked_at: DateTime.utc_now()
    }
  end

  def quality_audit(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    source = Keyword.get(opts, :source, nil)
    days = Keyword.get(opts, :days, 7)

    events = fetch_recent_events(limit, source, days)

    results = EventValidator.validate_batch(events, concurrency: 2)

    issues =
      Enum.zip(events, results)
      |> Enum.filter(fn {_, result} ->
        case result do
          {:ok, %{status: :issues_found}} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn {event, {:ok, validation}} ->
        %{
          event_id: event.id,
          external_id: event.external_id,
          title: event.title,
          source: event.source,
          issues: validation.issues
        }
      end)

    %{
      total_checked: length(events),
      issues_found: length(issues),
      events_with_issues: issues,
      issue_breakdown: count_issue_types(issues),
      checked_at: DateTime.utc_now()
    }
  end

  defp fetch_events_for_audit(limit, source, only_other) do
    query = from e in "events",
      select: %{
        id: e.id,
        external_id: e.external_id,
        title: e.title,
        description: e.description,
        category_slug: e.category_slug,
        venue_name: e.venue_name
      },
      order_by: [desc: e.inserted_at],
      limit: ^limit

    query = if source, do: where(query, [e], e.source == ^source), else: query
    query = if only_other, do: where(query, [e], e.category_slug == "other"), else: query

    Repo.all(query)
  end

  defp fetch_recent_events(limit, source, days) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60)

    query = from e in "events",
      where: e.inserted_at >= ^cutoff,
      select: %{
        id: e.id,
        external_id: e.external_id,
        title: e.title,
        description: e.description,
        category: e.category_slug,
        venue_name: e.venue_name,
        source: e.source,
        start_date: e.start_date,
        price_min: e.price_min,
        price_max: e.price_max
      },
      order_by: [desc: e.inserted_at],
      limit: ^limit

    query = if source, do: where(query, [e], e.source == ^source), else: query

    Repo.all(query)
  end

  defp count_issue_types(events_with_issues) do
    events_with_issues
    |> Enum.flat_map(& &1.issues)
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, issues} -> {type, length(issues)} end)
    |> Map.new()
  end
end
```

---

## Mix Tasks

### Category Audit Task

```elixir
# lib/mix/tasks/ai/suggest_categories.ex
defmodule Mix.Tasks.Ai.SuggestCategories do
  @moduledoc """
  Suggest categories for events using local LLM.

  ## Usage

      mix ai.suggest_categories
      mix ai.suggest_categories --limit 50
      mix ai.suggest_categories --source cinema_city
      mix ai.suggest_categories --all  # Include non-"other" categories
  """
  use Mix.Task

  @shortdoc "Suggest event categories using local LLM"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      switches: [limit: :integer, source: :string, all: :boolean],
      aliases: [l: :limit, s: :source]
    )

    alias EventasaurusDiscovery.AI.QualityChecker

    IO.puts("\n🤖 Checking Ollama status...")

    case QualityChecker.check_ollama_status() do
      {:ok, %{status: :available, models: models}} ->
        IO.puts("✅ Ollama available with models: #{Enum.join(models, ", ")}")
        run_audit(opts)

      {:error, :ollama_unavailable} ->
        IO.puts("❌ Ollama not available. Start it with: ollama serve")
        exit({:shutdown, 1})
    end
  end

  defp run_audit(opts) do
    limit = Keyword.get(opts, :limit, 100)
    source = Keyword.get(opts, :source)
    only_other = not Keyword.get(opts, :all, false)

    IO.puts("\n📊 Running category audit...")
    IO.puts("   Limit: #{limit}")
    IO.puts("   Source: #{source || "all"}")
    IO.puts("   Only 'other' category: #{only_other}\n")

    result = QualityChecker.audit_categories(
      limit: limit,
      source: source,
      only_other: only_other
    )

    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("Category Audit Results")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("Total checked: #{result.total_checked}")
    IO.puts("Mismatches found: #{result.mismatches_found}")
    IO.puts("")

    if result.mismatches_found > 0 do
      IO.puts("Suggested Changes:")
      IO.puts("─────────────────")

      Enum.each(result.mismatches, fn m ->
        IO.puts("")
        IO.puts("  Event: #{m.title}")
        IO.puts("  ID: #{m.external_id}")
        IO.puts("  Current: #{m.current_category} → Suggested: #{m.suggested_category}")
        IO.puts("  Confidence: #{m.confidence}")
      end)
    else
      IO.puts("✅ No category mismatches found!")
    end
  end
end
```

### Quality Check Task

```elixir
# lib/mix/tasks/ai/quality_check.ex
defmodule Mix.Tasks.Ai.QualityCheck do
  @moduledoc """
  Run semantic quality checks on recent events using local LLM.

  ## Usage

      mix ai.quality_check
      mix ai.quality_check --limit 50
      mix ai.quality_check --source week_pl
      mix ai.quality_check --days 3
  """
  use Mix.Task

  @shortdoc "Check event quality using local LLM"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      switches: [limit: :integer, source: :string, days: :integer],
      aliases: [l: :limit, s: :source, d: :days]
    )

    alias EventasaurusDiscovery.AI.QualityChecker

    IO.puts("\n🤖 Checking Ollama status...")

    case QualityChecker.check_ollama_status() do
      {:ok, %{status: :available}} ->
        IO.puts("✅ Ollama available")
        run_quality_check(opts)

      {:error, :ollama_unavailable} ->
        IO.puts("❌ Ollama not available. Start it with: ollama serve")
        exit({:shutdown, 1})
    end
  end

  defp run_quality_check(opts) do
    limit = Keyword.get(opts, :limit, 50)
    source = Keyword.get(opts, :source)
    days = Keyword.get(opts, :days, 7)

    IO.puts("\n🔍 Running quality audit...")
    IO.puts("   Limit: #{limit}")
    IO.puts("   Source: #{source || "all"}")
    IO.puts("   Days: #{days}\n")

    result = QualityChecker.quality_audit(
      limit: limit,
      source: source,
      days: days
    )

    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("Quality Audit Results")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("Total checked: #{result.total_checked}")
    IO.puts("Events with issues: #{result.issues_found}")
    IO.puts("")

    if map_size(result.issue_breakdown) > 0 do
      IO.puts("Issue Breakdown:")
      Enum.each(result.issue_breakdown, fn {type, count} ->
        IO.puts("  #{type}: #{count}")
      end)
      IO.puts("")
    end

    if result.issues_found > 0 do
      IO.puts("Events with Issues:")
      IO.puts("───────────────────")

      Enum.each(result.events_with_issues, fn e ->
        IO.puts("")
        IO.puts("  #{e.title}")
        IO.puts("  Source: #{e.source} | ID: #{e.external_id}")
        Enum.each(e.issues, fn issue ->
          IO.puts("  ⚠️  #{issue.type}: #{issue.explanation}")
        end)
      end)
    else
      IO.puts("✅ No quality issues found!")
    end
  end
end
```

---

## Getting Started

### Prerequisites

1. **Install Ollama**
   ```bash
   # macOS
   brew install ollama

   # Linux
   curl -fsSL https://ollama.com/install.sh | sh
   ```

2. **Pull a lightweight model**
   ```bash
   # Recommended for this use case (~400MB)
   ollama pull qwen2.5:0.5b

   # Alternatives
   ollama pull phi3:mini     # ~2.3GB, higher quality
   ollama pull gemma2:2b     # ~1.6GB, good balance
   ```

3. **Start Ollama server**
   ```bash
   ollama serve
   ```

### First Test

```elixir
# In IEx
iex -S mix

# Check connection
alias EventasaurusDiscovery.AI.LocalLLM
LocalLLM.available?()  # Should return true

# Test generation
LocalLLM.generate("What category is 'Jazz Concert at Blue Note'? Respond with one word.")
# => {:ok, "music"}
```

### Run Audits

```bash
# Check categories for "other" events
mix ai.suggest_categories --limit 20

# Check specific source
mix ai.suggest_categories --source cinema_city --limit 50

# Full quality check
mix ai.quality_check --days 3 --limit 30
```

---

## Resource Considerations

| Model | RAM Usage | Speed | Quality |
|-------|-----------|-------|---------|
| qwen2.5:0.5b | ~500MB | Fast | Good for classification |
| phi3:mini | ~2.5GB | Medium | Better reasoning |
| gemma2:2b | ~1.8GB | Medium | Good balance |
| llama3.2:1b | ~1GB | Fast | Good general purpose |

**Recommendations:**
- Development laptop: `qwen2.5:0.5b` or `llama3.2:1b`
- Dedicated dev server: `phi3:mini` for better quality
- Batch processing: Use concurrency=1-2 to avoid memory pressure

---

## Future Expansion

### Phase 3: Production Integration (Optional)

If quality proves valuable, could integrate into scraper pipeline:

```elixir
# In transformer or post-processing step
defp maybe_validate_event(event, :development) do
  case EventValidator.validate(event) do
    {:ok, %{status: :issues_found, issues: issues}} ->
      Logger.warning("Event quality issues", event_id: event.id, issues: issues)
      # Could add to review queue instead of rejecting
      {:ok, Map.put(event, :needs_review, true)}
    _ ->
      {:ok, event}
  end
end
```

### Phase 4: Enhanced Deduplication

Use semantic similarity for better duplicate detection:

```elixir
defmodule EventasaurusDiscovery.AI.DuplicateDetector do
  def similar?(event1, event2) do
    prompt = """
    Are these two events the same event? Respond YES or NO only.

    Event 1: #{event1.title} at #{event1.venue} on #{event1.date}
    Event 2: #{event2.title} at #{event2.venue} on #{event2.date}
    """

    case LocalLLM.generate(prompt) do
      {:ok, response} -> String.contains?(String.upcase(response), "YES")
      _ -> false
    end
  end
end
```

### Phase 5: Automatic Category Mapping Updates

Suggest additions to `categories.yaml` based on frequent suggestions:

```elixir
def suggest_mapping_updates(days \\ 30) do
  # Aggregate category suggestions over time
  # Identify patterns that could become rules
  # Generate YAML snippets for category_mapper
end
```

---

## Success Metrics

- **Category audit**: Reduce "other" category events by 50%
- **Quality check**: Catch issues before they reach production
- **Developer time**: Surface problems automatically, not manually discovered
- **False positive rate**: Target <10% to maintain trust in tool

---

## Open Questions

1. Should we track LLM suggestions in a database table for analysis?
2. How to handle disagreements between LLM and rule-based categorization?
3. Should there be a "review queue" for flagged events?
4. Model versioning - how to ensure consistent results across updates?
