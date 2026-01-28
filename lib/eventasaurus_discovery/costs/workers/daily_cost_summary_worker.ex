defmodule EventasaurusDiscovery.Costs.Workers.DailyCostSummaryWorker do
  @moduledoc """
  Oban worker for generating daily external service cost summaries.

  Runs automatically daily via cron configuration to:
  - Generate comprehensive cost reports across all external services
  - Check budget thresholds and trigger alerts
  - Log cost trends and anomalies

  Can also be triggered manually:

      %{}
      |> EventasaurusDiscovery.Costs.Workers.DailyCostSummaryWorker.new()
      |> Oban.insert()

  ## Configuration

  Add to config/runtime.exs crontab:

      {"0 6 * * *", EventasaurusDiscovery.Costs.Workers.DailyCostSummaryWorker}

  ## Budget Alerts

  The worker checks against configurable budget thresholds and logs warnings
  when usage exceeds configured limits. Default monthly budget is $200.

  Configure in config/config.exs:

      config :eventasaurus, :cost_tracking,
        monthly_budget: 200.00,
        alert_thresholds: [0.50, 0.75, 0.90, 1.0]
  """

  use Oban.Worker,
    queue: :reports,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Costs.CostStats
  alias EventasaurusDiscovery.Costs.CostAlerts

  @default_monthly_budget 200.00
  @default_alert_thresholds [0.50, 0.75, 0.90, 1.0]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Allow specifying a date for reports (useful for testing/backfill)
    date =
      case Map.get(args, "date") do
        nil -> Date.utc_today()
        date_string -> Date.from_iso8601!(date_string)
      end

    Logger.info("📊 Starting daily external service cost summary for #{date}...")

    with {:ok, report} <- generate_daily_report(date),
         :ok <- check_budget_alerts(date),
         :ok <- log_report(report) do
      {:ok, %{report_generated: true, date: date}}
    else
      {:error, reason} ->
        Logger.error("❌ Failed to generate daily cost summary: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generate a comprehensive daily cost report.

  ## Parameters
  - `date` - Any date within the target month for MTD calculations

  ## Returns
  - `{:ok, report_map}` - Report data as a map
  - `{:error, reason}` - If generation fails
  """
  def generate_daily_report(date \\ Date.utc_today()) do
    yesterday = Date.add(date, -1)

    with {:ok, monthly_total} <- CostStats.monthly_total(date),
         {:ok, by_service_type} <- CostStats.costs_by_service_type(date),
         {:ok, by_provider} <- CostStats.costs_by_provider(date),
         {:ok, daily_costs} <- CostStats.daily_costs(Date.beginning_of_month(date), date),
         {:ok, top_drivers} <- CostStats.top_cost_drivers(10, date) do
      # Calculate yesterday's costs
      yesterday_cost =
        daily_costs
        |> Enum.find(fn d -> d.date == yesterday end)
        |> case do
          nil -> Decimal.new("0.00")
          day -> day.total_cost || Decimal.new("0.00")
        end

      # Calculate 7-day trend
      week_costs =
        daily_costs
        |> Enum.filter(fn d ->
          Date.diff(date, d.date) <= 7 and Date.diff(date, d.date) >= 0
        end)

      week_total =
        week_costs
        |> Enum.map(& &1.total_cost)
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

      week_avg =
        if length(week_costs) > 0 do
          Decimal.div(week_total, Decimal.new(length(week_costs)))
        else
          Decimal.new("0")
        end

      report = %{
        date: date,
        month: format_month(date),
        monthly_total: monthly_total.total_cost || Decimal.new("0.00"),
        monthly_count: monthly_total.count,
        yesterday_cost: yesterday_cost,
        week_total: week_total,
        week_avg: week_avg,
        by_service_type: by_service_type,
        by_provider: by_provider,
        top_drivers: top_drivers,
        budget: get_monthly_budget(),
        budget_percentage: calculate_budget_percentage(monthly_total.total_cost)
      }

      {:ok, report}
    end
  end

  @doc """
  Check budget thresholds and trigger alerts if needed.
  """
  def check_budget_alerts(date \\ Date.utc_today()) do
    case CostStats.monthly_total(date) do
      {:ok, %{total_cost: total_cost}} when not is_nil(total_cost) ->
        CostAlerts.check_and_alert(total_cost, date)

      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not check budget alerts: #{inspect(reason)}")
        :ok
    end
  end

  # ============================================================================
  # Report Formatting
  # ============================================================================

  defp log_report(report) do
    formatted = format_report(report)

    Logger.info("""
    📊 Daily External Service Cost Summary
    #{formatted}
    """)

    :ok
  end

  defp format_report(report) do
    """
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    📊 EXTERNAL SERVICE COSTS - #{report.month}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    ## 💰 COST SUMMARY
    Month-to-Date:             $#{format_decimal(report.monthly_total)}
    Yesterday:                 $#{format_decimal(report.yesterday_cost)}
    7-Day Total:               $#{format_decimal(report.week_total)}
    7-Day Average:             $#{format_decimal(report.week_avg)}/day
    Total Operations:          #{report.monthly_count}

    ## 📊 BUDGET STATUS
    Monthly Budget:            $#{format_currency(report.budget)}
    Current Usage:             #{format_percentage(report.budget_percentage)}
    #{budget_bar(report.budget_percentage)}

    ## 🔧 BY SERVICE TYPE
    #{format_service_type_breakdown(report.by_service_type)}

    ## 🏢 BY PROVIDER
    #{format_provider_breakdown(report.by_provider)}

    ## 🔥 TOP COST DRIVERS
    #{format_top_drivers(report.top_drivers)}

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Report generated: #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")}
    """
  end

  defp format_service_type_breakdown(services) when is_list(services) do
    if Enum.empty?(services) do
      "  (No service costs recorded this month)"
    else
      services
      |> Enum.map(fn s ->
        service_type = String.pad_trailing(s.service_type || "unknown", 20)
        count = String.pad_leading("#{s.count}", 6)
        cost = format_decimal(s.total_cost)
        "  #{service_type} #{count} ops  $#{cost}"
      end)
      |> Enum.join("\n")
    end
  end

  defp format_provider_breakdown(providers) when is_list(providers) do
    if Enum.empty?(providers) do
      "  (No provider costs recorded this month)"
    else
      providers
      |> Enum.map(fn p ->
        provider = String.pad_trailing(p.provider || "unknown", 20)
        count = String.pad_leading("#{p.count}", 6)
        cost = format_decimal(p.total_cost)
        "  #{provider} #{count} ops  $#{cost}"
      end)
      |> Enum.join("\n")
    end
  end

  defp format_top_drivers(drivers) when is_list(drivers) do
    if Enum.empty?(drivers) do
      "  (No cost drivers recorded this month)"
    else
      drivers
      |> Enum.with_index(1)
      |> Enum.map(fn {d, i} ->
        provider = String.pad_trailing(d.provider || "unknown", 15)
        operation = String.pad_trailing(d.operation || "default", 15)
        count = String.pad_leading("#{d.count}", 6)
        cost = format_decimal(d.total_cost)
        "  #{i}. #{provider} #{operation} #{count} ops  $#{cost}"
      end)
      |> Enum.join("\n")
    end
  end

  defp budget_bar(percentage) when is_number(percentage) do
    filled = round(percentage / 5)
    empty = 20 - filled

    bar =
      String.duplicate("█", min(filled, 20)) <>
        String.duplicate("░", max(empty, 0))

    status =
      cond do
        percentage >= 100 -> "🚨 OVER BUDGET"
        percentage >= 90 -> "⚠️  CRITICAL"
        percentage >= 75 -> "⚠️  WARNING"
        percentage >= 50 -> "📊 MODERATE"
        true -> "✅ HEALTHY"
      end

    "  [#{bar}] #{status}"
  end

  defp budget_bar(_), do: "  [░░░░░░░░░░░░░░░░░░░░] ✅ HEALTHY"

  # ============================================================================
  # Helpers
  # ============================================================================

  defp format_month(date) do
    Calendar.strftime(date, "%B %Y")
  end

  defp format_decimal(nil), do: "0.00"
  defp format_decimal(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()

  defp format_decimal(num) when is_number(num),
    do: :erlang.float_to_binary(num * 1.0, decimals: 2)

  defp format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end

  defp format_currency(_), do: "0.00"

  defp format_percentage(nil), do: "0.0%"

  defp format_percentage(pct) when is_number(pct),
    do: "#{:erlang.float_to_binary(pct, decimals: 1)}%"

  defp get_monthly_budget do
    Application.get_env(:eventasaurus, :cost_tracking, [])
    |> Keyword.get(:monthly_budget, @default_monthly_budget)
  end

  defp calculate_budget_percentage(nil), do: 0.0

  defp calculate_budget_percentage(%Decimal{} = total) do
    budget = get_monthly_budget()

    if budget > 0 do
      total
      |> Decimal.to_float()
      |> Kernel./(budget)
      |> Kernel.*(100)
    else
      0.0
    end
  end

  defp calculate_budget_percentage(_), do: 0.0

  @doc """
  Get the configured alert thresholds.
  """
  def alert_thresholds do
    Application.get_env(:eventasaurus, :cost_tracking, [])
    |> Keyword.get(:alert_thresholds, @default_alert_thresholds)
  end
end
