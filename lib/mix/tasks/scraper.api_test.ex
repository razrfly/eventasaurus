defmodule Mix.Tasks.Scraper.ApiTest do
  @moduledoc """
  Test the pagination API directly.

  ## Usage

      mix scraper.api_test
  """

  use Mix.Task
  require Logger

  @shortdoc "Test pagination API directly"

  def run(_args) do
    # Start the application
    Mix.Task.run("app.start")

    Logger.info("🔍 Testing Bandsintown pagination API...")

    url = "https://www.bandsintown.com/all-dates/fetch-next/upcomingEvents?page=2&longitude=19.9325&latitude=50.07262"

    headers = [
      {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"},
      {"Accept", "application/json, text/javascript, */*; q=0.01"},
      {"Accept-Language", "en-US,en;q=0.5"},
      {"Accept-Encoding", "gzip"},
      {"X-Requested-With", "XMLHttpRequest"},
      {"Referer", "https://www.bandsintown.com/c/krakow-poland"},
      {"DNT", "1"},
      {"Connection", "keep-alive"}
    ]

    options = [
      timeout: 30_000,
      recv_timeout: 30_000,
      follow_redirect: true,
      max_redirect: 3
    ]

    case HTTPoison.get(url, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: response_headers}} ->
        Logger.info("✅ Successfully fetched API response")

        # Check if response is gzipped and decompress if needed
        body =
          if is_gzipped?(response_headers) do
            case :zlib.gunzip(body) do
              decompressed when is_binary(decompressed) ->
                Logger.info("📦 Decompressed gzipped response")
                decompressed
              _ ->
                Logger.info("📦 Failed to decompress, using original body")
                body
            end
          else
            body
          end

        # Save to file for inspection
        filename = "tmp/api_response_page2.json"
        File.write!(filename, body)
        Logger.info("💾 Saved response to #{filename}")

        # Try to parse as JSON
        case Jason.decode(body) do
          {:ok, json_data} ->
            Logger.info("✅ Valid JSON response")
            Logger.info("🔑 Top-level keys: #{inspect(Map.keys(json_data))}")

            # Inspect structure
            case json_data do
              %{"html" => html} ->
                Logger.info("📄 Response contains HTML field")
                Logger.info("📏 HTML size: #{String.length(html)} chars")

                # Save HTML for inspection
                File.write!("tmp/api_response_page2.html", html)
                Logger.info("💾 Saved HTML to tmp/api_response_page2.html")

                # Try to parse and count events
                case Floki.parse_document(html) do
                  {:ok, document} ->
                    # Look for event-related elements
                    events = Floki.find(document, "[class*='EventCard'], [data-testid*='event'], a[href*='/e/']")
                    Logger.info("🎵 Found #{length(events)} event elements")
                  {:error, _} ->
                    Logger.error("❌ Failed to parse HTML")
                end

              %{"events" => events} when is_list(events) ->
                Logger.info("📋 Response contains #{length(events)} events")
                if length(events) > 0 do
                  Logger.info("Sample event: #{inspect(List.first(events), pretty: true)}")
                end

              _ ->
                Logger.info("📊 Response structure: #{inspect(json_data, pretty: true, limit: 2000)}")
            end

          {:error, _} ->
            Logger.info("❌ Not JSON - might be HTML")
            Logger.info("📄 Response type: #{String.slice(body, 0, 100)}")
        end

      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("❌ HTTP #{status_code}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Failed to fetch: #{inspect(reason)}")
    end
  end

  defp is_gzipped?(headers) do
    Enum.any?(headers, fn
      {"content-encoding", value} -> String.contains?(String.downcase(value), "gzip")
      {"Content-Encoding", value} -> String.contains?(String.downcase(value), "gzip")
      _ -> false
    end)
  end
end