defmodule Mix.Tasks.Test.DateParsing do
  @moduledoc """
  Test the fixed date parsing logic.
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.EventDetailJob

  @shortdoc "Test date parsing with various formats"

  def run(_args) do
    Mix.Task.run("app.start")

    test_dates = [
      "2025-09-14T16:00:00",      # Full datetime
      "2025-09-14",               # Date only
      "2024-12-25T23:59:59Z",     # With timezone
      nil,                        # Nil value
      "",                         # Empty string
      "invalid-date"              # Invalid format
    ]

    Logger.info("🧪 Testing date parsing with various formats...")

    Enum.each(test_dates, fn date_input ->
      result = test_parse_date(date_input)
      Logger.info("Input: #{inspect(date_input)} → Result: #{inspect(result)}")
    end)

    # Test with real Bandsintown data
    Logger.info("\n🎵 Testing with real Bandsintown event data...")
    test_real_event_data()
  end

  defp test_parse_date(date_input) do
    # Access the private function via a test module
    # We'll simulate the function logic here since we can't access private functions
    cond do
      is_nil(date_input) or date_input == "" ->
        nil

      is_binary(date_input) and String.contains?(date_input, "T") ->
        # Try with timezone first
        case DateTime.from_iso8601(date_input) do
          {:ok, datetime, _} ->
            datetime
          _ ->
            # If no timezone, assume UTC and add Z
            case DateTime.from_iso8601(date_input <> "Z") do
              {:ok, datetime, _} -> datetime
              _ ->
                # Last resort: parse as NaiveDateTime and convert to UTC
                case NaiveDateTime.from_iso8601(date_input) do
                  {:ok, naive_dt} -> DateTime.from_naive!(naive_dt, "Etc/UTC")
                  _ -> nil
                end
            end
        end

      is_binary(date_input) and Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, date_input) ->
        case Date.from_iso8601(date_input) do
          {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          _ -> nil
        end

      is_binary(date_input) ->
        EventasaurusDiscovery.Scraping.Helpers.DateParser.parse_datetime(date_input)

      true ->
        nil
    end
  rescue
    e ->
      {:error, e}
  end

  defp test_real_event_data() do
    # Simulate the data we got from our debug script
    event_data = %{
      "title" => "Tęgie Chłopy @ Ochotnicza Straż Pożarna Ossów",
      "date" => "2025-09-14T16:00:00",
      "end_date" => "2025-09-14"
    }

    starts_at = test_parse_date(event_data["date"])
    ends_at = test_parse_date(event_data["end_date"])

    Logger.info("Event: #{event_data["title"]}")
    Logger.info("  Start: #{event_data["date"]} → #{inspect(starts_at)}")
    Logger.info("  End: #{event_data["end_date"]} → #{inspect(ends_at)}")

    # Test validation
    if is_nil(starts_at) do
      Logger.error("❌ This event would be REJECTED - missing start date")
    else
      Logger.info("✅ This event would be ACCEPTED - has valid start date")
    end
  end
end