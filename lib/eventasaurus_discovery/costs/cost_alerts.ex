defmodule EventasaurusDiscovery.Costs.CostAlerts do
  @moduledoc """
  Budget threshold monitoring and alerting for external service costs.

  Monitors cost usage against configurable budget limits and triggers
  alerts when thresholds are exceeded. Uses ETS for tracking which
  alerts have been sent to avoid duplicate notifications.

  ## Alert Levels

  - **50%**: Informational - Half of budget consumed
  - **75%**: Warning - Three-quarters of budget consumed
  - **90%**: Critical - Near budget exhaustion
  - **100%**: Emergency - Budget exceeded

  ## Configuration

  Configure in config/config.exs:

      config :eventasaurus, :cost_tracking,
        monthly_budget: 200.00,
        alert_thresholds: [0.50, 0.75, 0.90, 1.0],
        alert_channels: [:logger]  # Future: [:logger, :slack, :email]

  ## Usage

      alias EventasaurusDiscovery.Costs.CostAlerts

      # Check and send alerts if thresholds exceeded
      CostAlerts.check_and_alert(Decimal.new("150.00"), ~D[2025-01-15])

      # Reset alerts for a new month
      CostAlerts.reset_alerts_for_month(~D[2025-02-01])

      # Get current alert status
      CostAlerts.current_status(~D[2025-01-15])

  ## Extending with New Channels

  To add Slack or email notifications, implement the `send_alert/3` function
  for additional channels and add them to the `:alert_channels` config.
  """

  use GenServer
  require Logger

  @table_name :cost_alerts_tracker
  @default_monthly_budget 200.00
  @default_alert_thresholds [0.50, 0.75, 0.90, 1.0]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Start the cost alerts tracker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check current costs against budget and send alerts if thresholds exceeded.

  ## Parameters
  - `current_cost` - Current month-to-date cost (Decimal or float)
  - `date` - Date for determining which month we're checking

  ## Returns
  - `:ok` - Always returns ok (alerts are fire-and-forget)

  ## Examples

      iex> CostAlerts.check_and_alert(Decimal.new("100.00"), ~D[2025-01-15])
      :ok
  """
  @spec check_and_alert(Decimal.t() | float(), Date.t()) :: :ok
  def check_and_alert(current_cost, date \\ Date.utc_today()) do
    ensure_started()

    cost_float =
      case current_cost do
        %Decimal{} = d -> Decimal.to_float(d)
        f when is_float(f) -> f
        i when is_integer(i) -> i * 1.0
        nil -> 0.0
      end

    budget = get_monthly_budget()
    percentage = if budget > 0, do: cost_float / budget * 100, else: 0.0
    month_key = month_key(date)

    # Check each threshold
    get_alert_thresholds()
    |> Enum.each(fn threshold ->
      threshold_pct = threshold * 100

      if percentage >= threshold_pct and not alert_sent?(month_key, threshold) do
        send_alert(threshold, cost_float, budget, date)
        mark_alert_sent(month_key, threshold)
      end
    end)

    :ok
  end

  @doc """
  Get current alert status for a month.

  Returns a map with budget status and which alerts have been sent.

  ## Examples

      iex> CostAlerts.current_status(~D[2025-01-15])
      %{
        month: "2025-01",
        budget: 200.00,
        alerts_sent: [0.5, 0.75],
        next_threshold: 0.90
      }
  """
  @spec current_status(Date.t()) :: map()
  def current_status(date \\ Date.utc_today()) do
    ensure_started()

    month_key = month_key(date)
    sent_alerts = get_sent_alerts(month_key)

    next_threshold =
      get_alert_thresholds()
      |> Enum.reject(&(&1 in sent_alerts))
      |> List.first()

    %{
      month: month_key,
      budget: get_monthly_budget(),
      alerts_sent: sent_alerts,
      next_threshold: next_threshold
    }
  end

  @doc """
  Reset alerts for a new month.

  Call this when starting a new billing period to clear the alert history.
  """
  @spec reset_alerts_for_month(Date.t()) :: :ok
  def reset_alerts_for_month(date) do
    ensure_started()

    month_key = month_key(date)
    :ets.delete(@table_name, month_key)

    Logger.info("🔄 Cost alerts reset for #{month_key}")
    :ok
  end

  @doc """
  Manually trigger an alert for testing purposes.
  """
  @spec test_alert(float(), Date.t()) :: :ok
  def test_alert(threshold \\ 0.50, date \\ Date.utc_today()) do
    budget = get_monthly_budget()
    cost = budget * threshold

    Logger.info("🧪 Testing cost alert at #{threshold * 100}% threshold")
    send_alert(threshold, cost, budget, date)
    :ok
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS table for tracking sent alerts
    :ets.new(@table_name, [:set, :public, :named_table])
    {:ok, %{}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        # Start under the application supervisor if not running
        # For now, just create the ETS table directly
        unless :ets.whereis(@table_name) != :undefined do
          :ets.new(@table_name, [:set, :public, :named_table])
        end

      _pid ->
        :ok
    end
  end

  defp month_key(date) do
    Calendar.strftime(date, "%Y-%m")
  end

  defp alert_sent?(month_key, threshold) do
    case :ets.lookup(@table_name, month_key) do
      [{^month_key, sent_thresholds}] -> threshold in sent_thresholds
      [] -> false
    end
  rescue
    ArgumentError -> false
  end

  defp get_sent_alerts(month_key) do
    case :ets.lookup(@table_name, month_key) do
      [{^month_key, sent_thresholds}] -> sent_thresholds
      [] -> []
    end
  rescue
    ArgumentError -> []
  end

  defp mark_alert_sent(month_key, threshold) do
    current = get_sent_alerts(month_key)
    :ets.insert(@table_name, {month_key, [threshold | current] |> Enum.uniq()})
  rescue
    ArgumentError -> :ok
  end

  defp send_alert(threshold, current_cost, budget, date) do
    percentage = threshold * 100
    month = Calendar.strftime(date, "%B %Y")

    {level, emoji, severity} = alert_level(threshold)

    message = """
    #{emoji} COST ALERT: #{severity}

    External service costs have reached #{format_percentage(percentage)} of the monthly budget.

    Month:           #{month}
    Current Cost:    $#{format_currency(current_cost)}
    Monthly Budget:  $#{format_currency(budget)}
    Usage:           #{format_percentage(current_cost / budget * 100)}

    #{alert_recommendation(threshold)}
    """

    # Send to configured channels
    get_alert_channels()
    |> Enum.each(fn channel ->
      send_to_channel(channel, level, message, %{
        threshold: threshold,
        current_cost: current_cost,
        budget: budget,
        month: month
      })
    end)
  end

  defp alert_level(threshold) when threshold >= 1.0, do: {:error, "🚨", "BUDGET EXCEEDED"}
  defp alert_level(threshold) when threshold >= 0.90, do: {:warning, "⚠️", "CRITICAL - 90% of budget consumed"}
  defp alert_level(threshold) when threshold >= 0.75, do: {:warning, "⚠️", "WARNING - 75% of budget consumed"}
  defp alert_level(_threshold), do: {:info, "📊", "INFO - 50% of budget consumed"}

  defp alert_recommendation(threshold) when threshold >= 1.0 do
    """
    ⚡ IMMEDIATE ACTION REQUIRED:
    - Review recent cost spikes in the admin dashboard
    - Consider pausing non-critical scrapers
    - Increase monthly budget if usage is justified
    """
  end

  defp alert_recommendation(threshold) when threshold >= 0.90 do
    """
    📋 RECOMMENDED ACTIONS:
    - Monitor daily cost trends closely
    - Review top cost drivers for optimization opportunities
    - Plan for budget adjustment if trend continues
    """
  end

  defp alert_recommendation(threshold) when threshold >= 0.75 do
    """
    📋 SUGGESTED ACTIONS:
    - Check if usage aligns with expected scraper activity
    - Review any unusual cost spikes
    """
  end

  defp alert_recommendation(_threshold) do
    """
    ℹ️ This is an informational alert. Budget usage is healthy.
    """
  end

  defp send_to_channel(:logger, level, message, _metadata) do
    case level do
      :error -> Logger.error(message)
      :warning -> Logger.warning(message)
      :info -> Logger.info(message)
    end
  end

  # Future: Add Slack integration
  # defp send_to_channel(:slack, _level, message, metadata) do
  #   # Send to Slack webhook
  # end

  # Future: Add email integration
  # defp send_to_channel(:email, _level, message, metadata) do
  #   # Send to admin email
  # end

  defp send_to_channel(channel, _level, _message, _metadata) do
    Logger.warning("Unknown alert channel: #{channel}")
  end

  defp format_currency(amount) when is_number(amount) do
    :erlang.float_to_binary(amount * 1.0, decimals: 2)
  end

  defp format_currency(_), do: "0.00"

  defp format_percentage(pct) when is_number(pct) do
    "#{:erlang.float_to_binary(pct * 1.0, decimals: 1)}%"
  end

  defp format_percentage(_), do: "0.0%"

  # ============================================================================
  # Configuration Helpers
  # ============================================================================

  defp get_monthly_budget do
    Application.get_env(:eventasaurus, :cost_tracking, [])
    |> Keyword.get(:monthly_budget, @default_monthly_budget)
  end

  defp get_alert_thresholds do
    Application.get_env(:eventasaurus, :cost_tracking, [])
    |> Keyword.get(:alert_thresholds, @default_alert_thresholds)
  end

  defp get_alert_channels do
    Application.get_env(:eventasaurus, :cost_tracking, [])
    |> Keyword.get(:alert_channels, [:logger])
  end
end
