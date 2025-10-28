defmodule EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser do
  @moduledoc """
  Shared multilingual date parser for extracting and normalizing dates from non-English content.

  This module orchestrates a three-stage pipeline:

  1. **Extract Date Components** - Use language-specific patterns to extract day, month, year
  2. **Normalize to ISO Format** - Convert language-specific components to YYYY-MM-DD
  3. **Parse & Validate** - Create DateTime structs with timezone conversion

  ## Features

  - **Multi-language support** - English, French, Polish (via language plugins)
  - **Plugin architecture** - Add new languages by implementing `DatePatternProvider` behavior
  - **Unknown occurrence fallback** - Gracefully handles unparseable dates
  - **Date range support** - Handles single dates, date ranges, cross-month ranges
  - **Relative dates** - Supports "today", "tomorrow", "tonight", etc.

  ## Usage

      # Single language (French)
      {:ok, result} = MultilingualDateParser.extract_and_parse(
        "du 19 mars au 7 juillet 2025",
        languages: [:french]
      )
      # => {:ok, %{starts_at: ~U[2025-03-19 00:00:00Z], ends_at: ~U[2025-07-07 23:59:59Z]}}

      # Multiple languages with fallback
      {:ok, result} = MultilingualDateParser.extract_and_parse(
        "From March 19 to July 7, 2025",
        languages: [:french, :english]
      )

      # Polish cinema scraper
      {:ok, result} = MultilingualDateParser.extract_and_parse(
        "od 19 marca do 21 marca 2025",
        languages: [:polish, :english]
      )

      # Unknown occurrence fallback
      {:error, :unsupported_date_format} = MultilingualDateParser.extract_and_parse(
        "sometime in spring",
        languages: [:english]
      )

  ## Architecture

  Language plugins are registered in the `@language_modules` map. Each plugin
  implements the `DatePatternProvider` behavior.

  To add a new language:

  1. Create module in `date_patterns/` (e.g., `date_patterns/polish.ex`)
  2. Implement `DatePatternProvider` behavior
  3. Register in `@language_modules` map
  4. Done! Parser now supports your language

  ## Related Documentation

  - See Issue #1839 for original multilingual vision
  - See Issue #1846 for refactoring plan
  - See `docs/scrapers/SCRAPER_SPECIFICATION.md` for usage guide
  - See `DatePatternProvider` behavior for plugin interface
  """

  require Logger

  # Language plugin modules (add new languages here)
  @language_modules %{
    french: EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.French,
    english: EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.English,
    polish: EventasaurusDiscovery.Sources.Shared.Parsers.DatePatterns.Polish
  }

  @doc """
  Extracts and parses dates from multilingual text.

  Tries each language in order until successful extraction.

  ## Options

  - `:languages` - List of language atoms to try (required). Example: `[:french, :english]`
  - `:timezone` - Timezone for parsing (optional, defaults to "Europe/Paris")

  ## Returns

  - `{:ok, %{starts_at: DateTime.t(), ends_at: DateTime.t() | nil}}` - Success
  - `{:error, :unsupported_date_format}` - No language could parse the date
  - `{:error, :invalid_languages}` - Invalid language specified

  ## Examples

      # Single date
      {:ok, %{starts_at: dt, ends_at: nil}} =
        extract_and_parse("19 mars 2025", languages: [:french])

      # Date range
      {:ok, %{starts_at: start_dt, ends_at: end_dt}} =
        extract_and_parse("du 19 mars au 21 mars 2025", languages: [:french])

      # Multi-language fallback
      {:ok, result} = extract_and_parse(
        "March 19, 2025",
        languages: [:french, :english]  # Tries French first, then English
      )

      # Unparseable date
      {:error, :unsupported_date_format} = extract_and_parse(
        "sometime soon",
        languages: [:english]
      )
  """
  @spec extract_and_parse(String.t(), keyword()) ::
          {:ok, %{starts_at: DateTime.t(), ends_at: DateTime.t() | nil}}
          | {:error, :unsupported_date_format | :invalid_languages}
  def extract_and_parse(text, opts \\ [])

  def extract_and_parse(text, opts) when is_binary(text) and is_list(opts) do
    languages = Keyword.get(opts, :languages, [:english])
    timezone = Keyword.get(opts, :timezone, "Europe/Paris")

    # Validate languages
    case validate_languages(languages) do
      :ok ->
        # Try each language in order
        try_languages(text, languages, timezone)

      {:error, invalid_langs} ->
        Logger.warning("""
        ⚠️ Invalid languages specified: #{inspect(invalid_langs)}
        Available: #{inspect(Map.keys(@language_modules))}
        """)

        {:error, :invalid_languages}
    end
  end

  def extract_and_parse(nil, _opts), do: {:error, :unsupported_date_format}
  def extract_and_parse("", _opts), do: {:error, :unsupported_date_format}

  # Private Functions

  @spec try_languages(String.t(), [atom()], String.t()) ::
          {:ok, %{starts_at: DateTime.t(), ends_at: DateTime.t() | nil}}
          | {:error, :unsupported_date_format}
  defp try_languages(_text, [], _timezone) do
    {:error, :unsupported_date_format}
  end

  defp try_languages(text, [language | rest_languages], timezone) do
    language_module = Map.get(@language_modules, language)

    case extract_with_language(text, language_module, timezone) do
      {:ok, result} ->
        Logger.debug("✅ Successfully parsed date with #{language} parser")
        {:ok, result}

      {:error, _reason} ->
        Logger.debug("Trying next language after #{language} failed")
        try_languages(text, rest_languages, timezone)
    end
  end

  @spec extract_with_language(String.t(), module(), String.t()) ::
          {:ok, %{starts_at: DateTime.t(), ends_at: DateTime.t() | nil}}
          | {:error, atom()}
  defp extract_with_language(text, language_module, timezone) do
    with {:ok, components} <- language_module.extract_components(text),
         {:ok, iso_dates} <- normalize_to_iso(components, language_module),
         {:ok, datetimes} <- parse_and_validate(iso_dates, timezone) do
      {:ok, datetimes}
    end
  end

  @spec validate_languages([atom()]) :: :ok | {:error, [atom()]}
  defp validate_languages(languages) do
    available_languages = Map.keys(@language_modules)

    invalid_languages =
      Enum.reject(languages, fn lang ->
        lang in available_languages
      end)

    case invalid_languages do
      [] -> :ok
      invalid -> {:error, invalid}
    end
  end

  @doc """
  Normalizes extracted date components to ISO format strings.

  Takes a component map from `DatePatternProvider.extract_components/1` and
  converts it to ISO date strings (YYYY-MM-DD).

  ## Component Map Format

  See `DatePatternProvider` for component map specification.

  ## Returns

  - `{:ok, %{starts_at: "YYYY-MM-DD", ends_at: "YYYY-MM-DD" | nil}}`
  - `{:error, :invalid_components}` - Missing required fields
  - `{:error, :invalid_month}` - Month name not recognized

  ## Examples

      # Single date
      normalize_to_iso(%{type: :single, day: 19, month: "mars", year: 2025}, French)
      # => {:ok, %{starts_at: "2025-03-19", ends_at: nil}}

      # Date range
      normalize_to_iso(%{type: :range, start_day: 19, end_day: 21, month: 3, year: 2025}, French)
      # => {:ok, %{starts_at: "2025-03-19", ends_at: "2025-03-21"}}
  """
  @spec normalize_to_iso(map(), module()) ::
          {:ok, %{starts_at: String.t(), ends_at: String.t() | nil}}
          | {:error, :invalid_components | :invalid_month}
  def normalize_to_iso(components, language_module)

  # Single date
  def normalize_to_iso(%{type: :single, day: day, month: month, year: year}, language_module) do
    with {:ok, month_num} <- resolve_month(month, language_module) do
      starts_at = format_iso_date(year, month_num, day)
      {:ok, %{starts_at: starts_at, ends_at: nil}}
    end
  end

  # Date range (same month)
  def normalize_to_iso(
        %{type: :range, start_day: start_day, end_day: end_day, month: month, year: year},
        language_module
      ) do
    with {:ok, month_num} <- resolve_month(month, language_module) do
      starts_at = format_iso_date(year, month_num, start_day)
      ends_at = format_iso_date(year, month_num, end_day)
      {:ok, %{starts_at: starts_at, ends_at: ends_at}}
    end
  end

  # Date range (cross-year) - handles ranges that span year boundaries
  def normalize_to_iso(
        %{
          type: :range,
          start_day: start_day,
          start_month: start_month,
          start_year: start_year,
          end_day: end_day,
          end_month: end_month,
          end_year: end_year
        },
        language_module
      ) do
    with {:ok, start_month_num} <- resolve_month(start_month, language_module),
         {:ok, end_month_num} <- resolve_month(end_month, language_module) do
      starts_at = format_iso_date(start_year, start_month_num, start_day)
      ends_at = format_iso_date(end_year, end_month_num, end_day)
      {:ok, %{starts_at: starts_at, ends_at: ends_at}}
    end
  end

  # Date range (cross-month, same year) - for ranges within same year
  def normalize_to_iso(
        %{
          type: :range,
          start_day: start_day,
          start_month: start_month,
          end_day: end_day,
          end_month: end_month,
          year: year
        },
        language_module
      ) do
    with {:ok, start_month_num} <- resolve_month(start_month, language_module),
         {:ok, end_month_num} <- resolve_month(end_month, language_module) do
      starts_at = format_iso_date(year, start_month_num, start_day)
      ends_at = format_iso_date(year, end_month_num, end_day)
      {:ok, %{starts_at: starts_at, ends_at: ends_at}}
    end
  end

  # Month-only
  def normalize_to_iso(%{type: :month, month: month, year: year}, language_module) do
    with {:ok, month_num} <- resolve_month(month, language_module) do
      starts_at = format_iso_date(year, month_num, 1)
      # Last day of month
      last_day = :calendar.last_day_of_the_month(year, month_num)
      ends_at = format_iso_date(year, month_num, last_day)
      {:ok, %{starts_at: starts_at, ends_at: ends_at}}
    end
  end

  # Relative date
  def normalize_to_iso(%{type: :relative, offset_days: offset_days}, _language_module) do
    today = Date.utc_today()
    target_date = Date.add(today, offset_days)

    starts_at = Date.to_iso8601(target_date)
    {:ok, %{starts_at: starts_at, ends_at: nil}}
  end

  def normalize_to_iso(_components, _language_module) do
    {:error, :invalid_components}
  end

  @spec resolve_month(String.t() | integer(), module()) ::
          {:ok, integer()} | {:error, :invalid_month}
  defp resolve_month(month, _language_module) when is_integer(month) and month in 1..12 do
    {:ok, month}
  end

  defp resolve_month(month_name, language_module) when is_binary(month_name) do
    month_names = language_module.month_names()
    normalized_name = String.downcase(month_name)

    case Map.get(month_names, normalized_name) do
      nil -> {:error, :invalid_month}
      month_num -> {:ok, month_num}
    end
  end

  defp resolve_month(_month, _language_module), do: {:error, :invalid_month}

  @spec format_iso_date(integer(), integer(), integer()) :: String.t()
  defp format_iso_date(year, month, day) do
    year_str = Integer.to_string(year) |> String.pad_leading(4, "0")
    month_str = Integer.to_string(month) |> String.pad_leading(2, "0")
    day_str = Integer.to_string(day) |> String.pad_leading(2, "0")

    "#{year_str}-#{month_str}-#{day_str}"
  end

  @doc """
  Parses ISO date strings to DateTime structs with timezone conversion.

  Takes ISO date strings (YYYY-MM-DD) and converts them to DateTime structs in UTC.

  ## Options

  - `timezone` - Source timezone for the dates (e.g., "Europe/Paris", "Europe/Warsaw")

  ## Returns

  - `{:ok, %{starts_at: DateTime.t(), ends_at: DateTime.t() | nil}}`
  - `{:error, :invalid_date}` - ISO string is not valid

  ## Examples

      parse_and_validate(%{starts_at: "2025-03-19", ends_at: nil}, "Europe/Paris")
      # => {:ok, %{starts_at: ~U[2025-03-19 00:00:00Z], ends_at: nil}}

      parse_and_validate(%{starts_at: "2025-03-19", ends_at: "2025-03-21"}, "Europe/Paris")
      # => {:ok, %{starts_at: ~U[2025-03-19 00:00:00Z], ends_at: ~U[2025-03-21 23:59:59Z]}}
  """
  @spec parse_and_validate(%{starts_at: String.t(), ends_at: String.t() | nil}, String.t()) ::
          {:ok, %{starts_at: DateTime.t(), ends_at: DateTime.t() | nil}}
          | {:error, :invalid_date}
  def parse_and_validate(%{starts_at: starts_at_iso, ends_at: ends_at_iso}, timezone) do
    with {:ok, starts_at} <- parse_iso_to_datetime(starts_at_iso, timezone, :start_of_day),
         {:ok, ends_at} <- parse_optional_end_date(ends_at_iso, timezone) do
      {:ok, %{starts_at: starts_at, ends_at: ends_at}}
    end
  end

  @spec parse_iso_to_datetime(String.t(), String.t(), :start_of_day | :end_of_day) ::
          {:ok, DateTime.t()} | {:error, :invalid_date}
  defp parse_iso_to_datetime(iso_date, timezone, time_of_day) do
    # Parse ISO date string
    case Date.from_iso8601(iso_date) do
      {:ok, date} ->
        # Add time component
        time = if time_of_day == :start_of_day, do: ~T[00:00:00], else: ~T[23:59:59]

        # Create NaiveDateTime
        naive_datetime = NaiveDateTime.new!(date, time)

        # Convert to DateTime with timezone, then to UTC
        case DateTime.from_naive(naive_datetime, timezone) do
          {:ok, datetime} ->
            {:ok, DateTime.shift_zone!(datetime, "Etc/UTC")}

          {:error, _} ->
            # Fallback: treat as UTC directly
            {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
        end

      {:error, _} ->
        {:error, :invalid_date}
    end
  end

  @spec parse_optional_end_date(String.t() | nil, String.t()) ::
          {:ok, DateTime.t() | nil} | {:error, :invalid_date}
  defp parse_optional_end_date(nil, _timezone), do: {:ok, nil}

  defp parse_optional_end_date(ends_at_iso, timezone) do
    parse_iso_to_datetime(ends_at_iso, timezone, :end_of_day)
  end

  @doc """
  Returns list of supported languages.

  ## Example

      MultilingualDateParser.supported_languages()
      # => [:french, :english, :polish]
  """
  @spec supported_languages() :: [atom()]
  def supported_languages do
    Map.keys(@language_modules)
  end
end
