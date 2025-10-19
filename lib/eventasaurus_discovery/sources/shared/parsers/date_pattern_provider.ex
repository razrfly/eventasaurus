defmodule EventasaurusDiscovery.Sources.Shared.Parsers.DatePatternProvider do
  @moduledoc """
  Behavior for language-specific date pattern providers.

  Each language module (English, French, Polish, etc.) implements this behavior
  to provide:
  - Month names in the target language
  - Regex patterns for extracting date components
  - Logic to parse extracted components into structured data

  This enables a plugin architecture where new languages can be added by creating
  a single module that implements these three callbacks.

  ## Example Implementation

      defmodule EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.French do
        @behaviour EventasaurusDiscovery.Sources.Shared.Parsers.DatePatternProvider

        @impl true
        def month_names do
          %{
            "janvier" => 1, "février" => 2, "mars" => 3,
            # ... rest of months
          }
        end

        @impl true
        def patterns do
          [
            ~r/du\\s+(\\d{1,2})\\s+(\\w+)\\s+au\\s+(\\d{1,2})\\s+(\\w+)\\s+(\\d{4})/i,
            # ... more patterns
          ]
        end

        @impl true
        def extract_components(text) do
          # Pattern matching logic
          {:ok, %{type: :range, start_day: 19, ...}}
        end
      end

  ## Architecture

  The multilingual date parser uses a three-stage pipeline:

  1. **Extract Date Components** (this behavior)
     - Use language-specific regex patterns
     - Extract day, month, year from raw text
     - Return structured component map

  2. **Normalize to ISO Format** (MultilingualDateParser)
     - Convert month names to numbers using month_names()
     - Build YYYY-MM-DD strings
     - Handle date ranges, multi-day events

  3. **Parse & Validate** (MultilingualDateParser)
     - Convert ISO strings to DateTime structs
     - Validate with Timex/NaiveDateTime
     - Apply timezone conversion (UTC)

  ## Component Map Format

  The `extract_components/1` callback should return a map with these keys:

      # Single date
      %{
        type: :single,
        day: 19,
        month: 3,      # Or month name string: "mars"
        year: 2025
      }

      # Date range (same month)
      %{
        type: :range,
        start_day: 19,
        end_day: 21,
        month: 3,      # Or month name string: "mars"
        year: 2025
      }

      # Date range (cross-month)
      %{
        type: :range,
        start_day: 19,
        start_month: 3,
        end_day: 7,
        end_month: 7,
        year: 2025
      }

      # Month-only (all events in a month)
      %{
        type: :month,
        month: 3,
        year: 2025
      }

      # Relative date
      %{
        type: :relative,
        offset_days: 0,  # 0 = today, 1 = tomorrow, -1 = yesterday
        time: "20:00"    # Optional time
      }

  ## Related Documentation

  - See Issue #1839 for original multilingual vision
  - See Issue #1846 for refactoring plan
  - See `docs/scrapers/SCRAPER_SPECIFICATION.md` for usage guide
  """

  @doc """
  Returns a map of month names to their numeric representation (1-12).

  Keys should be lowercase for case-insensitive matching.
  Should include both full names and common abbreviations.

  ## Example

      %{
        "january" => 1, "jan" => 1,
        "february" => 2, "feb" => 2,
        # ...
      }
  """
  @callback month_names() :: %{String.t() => integer()}

  @doc """
  Returns a list of compiled regex patterns for extracting dates.

  Patterns should be ordered from most specific to least specific.
  More complex patterns (e.g., cross-month ranges) should come before
  simpler patterns (e.g., single dates).

  ## Pattern Guidelines

  - Use capture groups for extracting components
  - Make patterns case-insensitive with `/i` flag
  - Use non-capturing groups `(?:...)` for optional elements
  - Test patterns with language-specific text

  ## Example

      [
        # Date range: "du 19 mars au 21 mars 2025"
        ~r/du\\s+(\\d{1,2})\\s+(\\w+)\\s+au\\s+(\\d{1,2})\\s+(\\w+)\\s+(\\d{4})/i,

        # Single date: "19 mars 2025"
        ~r/(\\d{1,2})\\s+(\\w+)\\s+(\\d{4})/i
      ]
  """
  @callback patterns() :: [Regex.t()]

  @doc """
  Extracts date components from text using language-specific patterns.

  Should try each pattern from `patterns()` in order until a match is found.
  Should validate extracted month names against `month_names()`.

  ## Returns

  - `{:ok, component_map}` - Successfully extracted components
  - `{:error, :no_match}` - No pattern matched the text
  - `{:error, :invalid_month}` - Month name not in `month_names()`

  ## Example

      extract_components("du 19 mars au 21 mars 2025")
      # => {:ok, %{type: :range, start_day: 19, end_day: 21, month: "mars", year: 2025}}
  """
  @callback extract_components(text :: String.t()) ::
              {:ok, map()} | {:error, :no_match | :invalid_month}
end
