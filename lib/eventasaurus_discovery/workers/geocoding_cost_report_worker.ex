defmodule EventasaurusDiscovery.Workers.GeocodingCostReportWorker do
  @moduledoc """
  Oban worker for generating monthly geocoding cost reports.

  Runs automatically on the 1st of each month via cron configuration.
  Generates comprehensive report and logs to application logs.

  Can also be triggered manually:

      %{}
      |> EventasaurusDiscovery.Workers.GeocodingCostReportWorker.new()
      |> Oban.insert()

  ## Configuration

  Add to config/config.exs:

      config :eventasaurus_app, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 8 1 * *", EventasaurusDiscovery.Workers.GeocodingCostReportWorker}
           ]}
        ]
  """

  use Oban.Worker,
    queue: :reports,
    max_attempts: 3

  require Logger
  alias EventasaurusDiscovery.Metrics.GeocodingStats

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🔍 Starting monthly geocoding cost report generation...")

    # Get previous month's date for reporting
    previous_month = Date.utc_today() |> Date.add(-1) |> Date.beginning_of_month()

    case generate_report(previous_month) do
      {:ok, report} ->
        Logger.info("""
        📊 Monthly Geocoding Cost Report Generated Successfully

        #{report}
        """)

        {:ok, %{report_generated: true, month: previous_month}}

      {:error, reason} ->
        Logger.error("❌ Failed to generate geocoding cost report: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generate comprehensive geocoding cost report for a given month.

  ## Parameters
  - `date` - Any date within the target month

  ## Returns
  - `{:ok, report_string}` - Formatted report
  - `{:error, reason}` - If generation fails
  """
  def generate_report(date \\ Date.utc_today()) do
    with {:ok, monthly} <- GeocodingStats.monthly_cost(date),
         {:ok, by_provider} <- GeocodingStats.costs_by_provider(),
         {:ok, by_scraper} <- GeocodingStats.costs_by_scraper(),
         {:ok, failed_count} <- GeocodingStats.failed_geocoding_count(),
         {:ok, deferred_count} <- GeocodingStats.deferred_geocoding_count(),
         {:ok, failed_venues} <- GeocodingStats.failed_geocoding_venues(10) do
      # Calculate free vs paid
      free_providers = ["openstreetmap", "city_resolver_offline", "provided", "deferred"]

      free_count =
        by_provider
        |> Enum.filter(fn p -> p.provider in free_providers end)
        |> Enum.map(& &1.count)
        |> Enum.sum()

      paid_count = monthly.count - free_count

      report = """
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      📊 GEOCODING COST REPORT - #{format_month(date)}
      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      ## 💰 COST SUMMARY
      Total Cost:                $#{format_currency(monthly.total_cost)}
      Total Venues Geocoded:     #{monthly.count}
      Free Geocoding:            #{free_count} venues ($0.00)
      Paid Geocoding:            #{paid_count} venues ($#{format_currency(monthly.total_cost)})
      Average Cost per Venue:    $#{format_currency(safe_divide(monthly.total_cost, monthly.count))}

      ## 🗺️ COSTS BY PROVIDER
      #{format_provider_breakdown(by_provider)}

      ## 🔧 COSTS BY SCRAPER
      #{format_scraper_breakdown(by_scraper)}

      ## ⚠️ ISSUES REQUIRING ATTENTION
      Failed Geocoding:          #{failed_count} venues
      Deferred Geocoding:        #{deferred_count} venues
      #{format_failed_venues(failed_venues)}

      ## 📈 PROJECTIONS
      Estimated Monthly Cost:    $#{format_currency(monthly.total_cost)} (current month)
      Estimated Annual Cost:     $#{format_currency(monthly.total_cost * 12)} (if trends continue)

      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      Report generated: #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")}
      """

      {:ok, report}
    end
  end

  # Format month name from date
  defp format_month(date) do
    Calendar.strftime(date, "%B %Y")
  end

  # Format currency with 2 decimal places
  defp format_currency(amount) when is_float(amount) or is_integer(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end

  defp format_currency(_), do: "0.00"

  # Safe division to avoid divide by zero
  defp safe_divide(_, 0), do: 0.0
  defp safe_divide(numerator, denominator), do: numerator / denominator

  # Format provider breakdown table
  defp format_provider_breakdown(providers) do
    providers
    |> Enum.map(fn p ->
      cost_str = format_currency(p.total_cost)
      provider_name = String.pad_trailing(p.provider || "unknown", 25)
      count_str = String.pad_leading("#{p.count}", 5)
      "  #{provider_name} #{count_str} venues  $#{cost_str}"
    end)
    |> Enum.join("\n")
  end

  # Format scraper breakdown table
  defp format_scraper_breakdown(scrapers) do
    scrapers
    |> Enum.map(fn s ->
      cost_str = format_currency(s.total_cost)
      scraper_name = String.pad_trailing(s.scraper || "unknown", 25)
      count_str = String.pad_leading("#{s.count}", 5)
      "  #{scraper_name} #{count_str} venues  $#{cost_str}"
    end)
    |> Enum.join("\n")
  end

  # Format failed venues list
  defp format_failed_venues([]), do: "  (No failed geocoding attempts)"

  defp format_failed_venues(venues) do
    failed_list =
      venues
      |> Enum.take(5)
      |> Enum.map(fn v ->
        "    - ID #{v.id}: #{v.name} (#{v.city}) - Reason: #{v.failure_reason}"
      end)
      |> Enum.join("\n")

    "\n  Recent Failed Venues:\n#{failed_list}"
  end
end
