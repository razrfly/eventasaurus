defmodule Mix.Tasks.Debug.DateExtraction do
  @moduledoc """
  Debug task to examine Bandsintown HTML structure for date extraction.
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Sources.Bandsintown.{Client, DetailExtractor}

  @shortdoc "Debug date extraction from Bandsintown event pages"

  def run(_args) do
    Mix.Task.run("app.start")

    # Test URL from our database
    test_url =
      "https://www.bandsintown.com/e/107352926-tegie-chlopy-at-ochotnicza-straz-pozarna-ossow?came_from=257&utm_medium=web&utm_source=home&utm_campaign=event"

    Logger.info("🔍 Testing date extraction from: #{test_url}")

    case Client.fetch_event_page(test_url) do
      {:ok, html} ->
        Logger.info("✅ Successfully fetched HTML (#{byte_size(html)} bytes)")

        # Test current date extraction
        current_date = DetailExtractor.extract_event_details(html, test_url)
        Logger.info("📅 Current date extraction result: #{inspect(current_date)}")

        # Look for various date patterns in the HTML
        analyze_html_for_dates(html)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch page: #{inspect(reason)}")
    end
  end

  defp analyze_html_for_dates(html) do
    Logger.info("🔍 Analyzing HTML for date patterns...")

    # Parse HTML
    document = Floki.parse_document!(html)

    # Look for various date selectors
    date_selectors = [
      {"time[datetime]", "datetime"},
      {"[data-testid*='date']", "text"},
      {".event-date", "text"},
      {".date", "text"},
      {"time", "text"},
      {"script[type='application/ld+json']", "json"}
    ]

    Enum.each(date_selectors, fn {selector, type} ->
      Logger.info("🔍 Checking selector: #{selector}")

      case type do
        "datetime" ->
          dates =
            Floki.find(document, selector)
            |> Floki.attribute("datetime")

          Logger.info("   Found datetime attributes: #{inspect(dates)}")

        "text" ->
          dates =
            Floki.find(document, selector)
            |> Floki.text()

          if dates != "" do
            Logger.info("   Found text content: #{inspect(dates)}")
          end

        "json" ->
          json_scripts =
            Floki.find(document, selector)
            |> Enum.map(&Floki.text/1)

          Enum.with_index(json_scripts, 1)
          |> Enum.each(fn {json_text, idx} ->
            Logger.info("   JSON-LD Script ##{idx}:")

            case Jason.decode(json_text) do
              {:ok, json_data} ->
                # Look for date fields
                date_fields = find_date_fields(json_data)

                if length(date_fields) > 0 do
                  Logger.info("     Date fields found: #{inspect(date_fields)}")
                else
                  Logger.info("     No obvious date fields")
                end

              {:error, _} ->
                Logger.info("     Invalid JSON")
            end
          end)
      end
    end)
  end

  defp find_date_fields(data) when is_map(data) do
    data
    |> Enum.flat_map(fn {key, value} ->
      cond do
        # Key suggests it's a date
        String.contains?(String.downcase(key), "date") or
            String.contains?(String.downcase(key), "time") ->
          [{key, value}]

        # Value looks like a date/time
        is_binary(value) and
            (String.contains?(value, "T") or
               Regex.match?(~r/\d{4}-\d{2}-\d{2}/, value) or
               Regex.match?(~r/\d{1,2}\/\d{1,2}\/\d{4}/, value)) ->
          [{key, value}]

        # Recursively check nested maps/lists
        is_map(value) ->
          find_date_fields(value)

        is_list(value) ->
          Enum.flat_map(value, &find_date_fields/1)

        true ->
          []
      end
    end)
  end

  defp find_date_fields(data) when is_list(data) do
    Enum.flat_map(data, &find_date_fields/1)
  end

  defp find_date_fields(_), do: []
end
