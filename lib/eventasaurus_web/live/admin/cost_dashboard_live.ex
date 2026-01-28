defmodule EventasaurusWeb.Admin.CostDashboardLive do
  @moduledoc """
  LiveView dashboard for monitoring external service costs.

  Displays:
  - Month-to-date cost totals with budget status
  - Breakdown by service type (geocoding, scraping, ML)
  - Breakdown by provider
  - Top cost drivers
  - Daily cost trend visualization
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Costs.{CostStats, CostAlerts}

  @refresh_interval :timer.minutes(5)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Schedule periodic refresh
      Process.send_after(self(), :refresh, @refresh_interval)
      {:ok, load_data(assign_defaults(socket))}
    else
      {:ok, assign_defaults(socket)}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("generate_report", _params, socket) do
    alias EventasaurusDiscovery.Costs.Workers.DailyCostSummaryWorker

    case DailyCostSummaryWorker.generate_daily_report() do
      {:ok, report} ->
        {:noreply, assign(socket, :manual_report, format_report(report))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate report: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp assign_defaults(socket) do
    assign(socket,
      loading: true,
      error: nil,
      monthly_total: nil,
      by_service_type: [],
      by_provider: [],
      top_drivers: [],
      daily_costs: [],
      budget_status: nil,
      manual_report: nil,
      page_title: "Cost Dashboard"
    )
  end

  defp load_data(socket) do
    today = Date.utc_today()

    with {:ok, monthly_total} <- CostStats.monthly_total(today),
         {:ok, by_service_type} <- CostStats.costs_by_service_type(today),
         {:ok, by_provider} <- CostStats.costs_by_provider(today),
         {:ok, top_drivers} <- CostStats.top_cost_drivers(10, today),
         {:ok, daily_costs} <- CostStats.daily_costs(Date.beginning_of_month(today), today) do
      budget_status = CostAlerts.current_status(today)
      budget = get_monthly_budget()

      budget_percentage =
        case monthly_total.total_cost do
          nil -> 0.0
          %Decimal{} = d -> Decimal.to_float(d) / budget * 100
          f when is_float(f) -> f / budget * 100
          _ -> 0.0
        end

      assign(socket,
        loading: false,
        error: nil,
        monthly_total: monthly_total,
        by_service_type: by_service_type,
        by_provider: by_provider,
        top_drivers: top_drivers,
        daily_costs: daily_costs,
        budget_status: budget_status,
        budget: budget,
        budget_percentage: budget_percentage
      )
    else
      {:error, reason} ->
        assign(socket,
          loading: false,
          error: "Failed to load cost data: #{inspect(reason)}"
        )
    end
  end

  defp get_monthly_budget do
    Application.get_env(:eventasaurus, :cost_tracking, [])
    |> Keyword.get(:monthly_budget, 200.00)
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

    Report generated: #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")}
    """
  end

  defp format_decimal(nil), do: "0.00"
  defp format_decimal(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()
  defp format_decimal(num) when is_number(num), do: :erlang.float_to_binary(num * 1.0, decimals: 2)

  defp format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end

  defp format_currency(_), do: "0.00"

  defp format_percentage(nil), do: "0.0%"
  defp format_percentage(pct) when is_number(pct), do: "#{:erlang.float_to_binary(pct, decimals: 1)}%"

  # ============================================================================
  # Template Helper Functions
  # ============================================================================

  defp calculate_avg_cost(%{total_cost: nil}), do: "0.00"
  defp calculate_avg_cost(%{total_cost: _, count: 0}), do: "0.00"
  defp calculate_avg_cost(%{total_cost: nil, count: _}), do: "0.00"

  defp calculate_avg_cost(%{total_cost: total, count: count}) when count > 0 do
    case total do
      %Decimal{} = d ->
        d
        |> Decimal.div(count)
        |> Decimal.round(4)
        |> Decimal.to_string()

      f when is_number(f) ->
        :erlang.float_to_binary(f / count, decimals: 4)
    end
  end

  defp calculate_bar_width(nil, _all), do: 0

  defp calculate_bar_width(cost, all_daily) do
    max_cost =
      all_daily
      |> Enum.map(& &1.total_cost)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn
        %Decimal{} = d -> Decimal.to_float(d)
        f when is_number(f) -> f
      end)
      |> Enum.max(fn -> 1 end)

    current =
      case cost do
        %Decimal{} = d -> Decimal.to_float(d)
        f when is_number(f) -> f
        _ -> 0
      end

    if max_cost > 0, do: current / max_cost * 100, else: 0
  end

  # Budget status styling helpers
  defp budget_status_bg(pct) when pct >= 100, do: "bg-red-100"
  defp budget_status_bg(pct) when pct >= 90, do: "bg-red-50"
  defp budget_status_bg(pct) when pct >= 75, do: "bg-yellow-50"
  defp budget_status_bg(pct) when pct >= 50, do: "bg-blue-50"
  defp budget_status_bg(_), do: "bg-green-50"

  defp budget_status_text(pct) when pct >= 100, do: "text-red-800"
  defp budget_status_text(pct) when pct >= 90, do: "text-red-700"
  defp budget_status_text(pct) when pct >= 75, do: "text-yellow-700"
  defp budget_status_text(pct) when pct >= 50, do: "text-blue-700"
  defp budget_status_text(_), do: "text-green-700"

  defp budget_status_subtext(pct) when pct >= 100, do: "text-red-600"
  defp budget_status_subtext(pct) when pct >= 90, do: "text-red-600"
  defp budget_status_subtext(pct) when pct >= 75, do: "text-yellow-600"
  defp budget_status_subtext(pct) when pct >= 50, do: "text-blue-600"
  defp budget_status_subtext(_), do: "text-green-600"

  defp budget_status_icon(pct) when pct >= 100, do: "hero-exclamation-triangle"
  defp budget_status_icon(pct) when pct >= 90, do: "hero-exclamation-triangle"
  defp budget_status_icon(pct) when pct >= 75, do: "hero-exclamation-circle"
  defp budget_status_icon(pct) when pct >= 50, do: "hero-information-circle"
  defp budget_status_icon(_), do: "hero-check-circle"

  defp budget_status_label(pct) when pct >= 100, do: "🚨 Budget Exceeded"
  defp budget_status_label(pct) when pct >= 90, do: "⚠️ Critical - Budget Nearly Exhausted"
  defp budget_status_label(pct) when pct >= 75, do: "⚠️ Warning - 75% of Budget Used"
  defp budget_status_label(pct) when pct >= 50, do: "📊 Moderate - Half of Budget Used"
  defp budget_status_label(_), do: "✅ Healthy - Budget On Track"

  defp budget_progress_color(pct) when pct >= 100, do: "bg-red-600"
  defp budget_progress_color(pct) when pct >= 90, do: "bg-red-500"
  defp budget_progress_color(pct) when pct >= 75, do: "bg-yellow-500"
  defp budget_progress_color(pct) when pct >= 50, do: "bg-blue-500"
  defp budget_progress_color(_), do: "bg-green-500"

  # Service type styling
  defp service_type_badge_class("scraping"), do: "bg-purple-100 text-purple-800"
  defp service_type_badge_class("geocoding"), do: "bg-blue-100 text-blue-800"
  defp service_type_badge_class("ml_inference"), do: "bg-pink-100 text-pink-800"
  defp service_type_badge_class("llm"), do: "bg-indigo-100 text-indigo-800"
  defp service_type_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_service_type("scraping"), do: "Scraping"
  defp format_service_type("geocoding"), do: "Geocoding"
  defp format_service_type("ml_inference"), do: "ML Inference"
  defp format_service_type("llm"), do: "LLM"
  defp format_service_type(other), do: other || "Unknown"

  # Provider styling
  defp provider_badge_class("crawlbase"), do: "bg-orange-100 text-orange-800"
  defp provider_badge_class("zyte"), do: "bg-cyan-100 text-cyan-800"
  defp provider_badge_class("google_places"), do: "bg-blue-100 text-blue-800"
  defp provider_badge_class("google_maps"), do: "bg-green-100 text-green-800"
  defp provider_badge_class("openstreetmap"), do: "bg-lime-100 text-lime-800"
  defp provider_badge_class("huggingface"), do: "bg-yellow-100 text-yellow-800"
  defp provider_badge_class("anthropic"), do: "bg-amber-100 text-amber-800"
  defp provider_badge_class("openai"), do: "bg-emerald-100 text-emerald-800"
  defp provider_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_provider_name("crawlbase"), do: "Crawlbase"
  defp format_provider_name("zyte"), do: "Zyte"
  defp format_provider_name("google_places"), do: "Google Places"
  defp format_provider_name("google_maps"), do: "Google Maps"
  defp format_provider_name("openstreetmap"), do: "OpenStreetMap"
  defp format_provider_name("huggingface"), do: "Hugging Face"
  defp format_provider_name("anthropic"), do: "Anthropic"
  defp format_provider_name("openai"), do: "OpenAI"
  defp format_provider_name(other), do: other || "Unknown"

  # Alert threshold styling
  defp threshold_card_class(threshold, budget_status) do
    sent? = budget_status && threshold in budget_status.alerts_sent

    cond do
      sent? && threshold >= 1.0 -> "border-red-500 bg-red-50"
      sent? && threshold >= 0.9 -> "border-red-400 bg-red-50"
      sent? && threshold >= 0.75 -> "border-yellow-400 bg-yellow-50"
      sent? -> "border-blue-400 bg-blue-50"
      true -> "border-gray-200 bg-white"
    end
  end

  defp threshold_label(1.0), do: "Emergency"
  defp threshold_label(0.9), do: "Critical"
  defp threshold_label(0.75), do: "Warning"
  defp threshold_label(0.5), do: "Info"
  defp threshold_label(_), do: "Custom"
end
