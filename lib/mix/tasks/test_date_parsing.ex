defmodule Mix.Tasks.Test.DateParsing do
  @moduledoc """
  Test the fixed date parsing logic.
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Sources.Bandsintown.DateParser

  @shortdoc "Test date parsing with various formats"

  def run(_args) do
    Mix.Task.run("app.start")

    test_dates = [
      # Full datetime
      "2025-09-14T16:00:00",
      # Date only
      "2025-09-14",
      # With timezone
      "2024-12-25T23:59:59Z",
      # Nil value
      nil,
      # Empty string
      "",
      # Invalid format
      "invalid-date"
    ]

    Logger.info("🧪 Testing date parsing with various formats...")

    Enum.each(test_dates, fn date_input ->
      result = DateParser.parse_start_date(date_input)
      Logger.info("Input: #{inspect(date_input)} → Result: #{inspect(result)}")
    end)

    # Test with real Bandsintown data
    Logger.info("\n🎵 Testing with real Bandsintown event data...")
    test_real_event_data()
  end

  defp test_real_event_data() do
    # Simulate the data we got from our debug script
    event_data = %{
      "title" => "Tęgie Chłopy @ Ochotnicza Straż Pożarna Ossów",
      "date" => "2025-09-14T16:00:00",
      "end_date" => "2025-09-14"
    }

    starts_at = DateParser.parse_start_date(event_data["date"])
    ends_at = DateParser.parse_end_date(event_data["end_date"])

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
