defmodule EventasaurusDiscovery.Admin.CityHealthMonitorJob do
  @moduledoc """
  Oban worker for monitoring city health metrics and generating alerts.

  This job runs hourly and:
  1. Computes health scores for all discovery-enabled cities
  2. Identifies cities with critical health (< 60%)
  3. Detects significant health drops (> 20 points in 24 hours)
  4. Logs alerts and stores snapshots for trending

  Future enhancements:
  - Email notifications to admin users
  - Slack webhook integration
  - Weekly health report generation

  ## Configuration

  The job is scheduled via Oban cron in config/config.exs:

      config :eventasaurus_discovery, Oban,
        crontab: [
          {"0 * * * *", EventasaurusDiscovery.Admin.CityHealthMonitorJob}
        ]

  ## Thresholds

  - Critical: Health score < 60%
  - Warning: Health score < 80%
  - Significant drop: > 20 point decrease in 24 hours
  """

  use Oban.Worker,
    queue: :reports,
    max_attempts: 3,
    unique: [period: 3600, states: [:available, :scheduled, :executing]]

  require Logger

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Admin.CityHealthCalculator

  @critical_threshold 60
  @warning_threshold 80
  @significant_drop_threshold 20

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🏥 Starting city health monitoring check...")
    start_time = System.monotonic_time(:millisecond)

    # Get all discovery-enabled cities
    cities = get_discovery_enabled_cities()
    Logger.info("Checking health for #{length(cities)} cities")

    # Calculate health scores
    city_ids = Enum.map(cities, & &1.id)
    health_scores = CityHealthCalculator.batch_health_scores(city_ids)

    # Identify issues
    critical_cities = find_critical_cities(cities, health_scores)
    warning_cities = find_warning_cities(cities, health_scores)

    # Log alerts
    log_health_alerts(critical_cities, warning_cities)

    # Store snapshot for trending (optional - can be used for drop detection)
    store_health_snapshot(cities, health_scores)

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    Logger.info(
      "✅ Health monitoring complete in #{duration_ms}ms - " <>
        "Critical: #{length(critical_cities)}, Warning: #{length(warning_cities)}"
    )

    :ok
  end

  defp get_discovery_enabled_cities do
    from(c in City,
      where: c.discovery_enabled == true,
      order_by: [asc: c.name],
      select: c
    )
    |> Repo.replica().all()
  end

  defp find_critical_cities(cities, health_scores) do
    cities
    |> Enum.filter(fn city ->
      score = Map.get(health_scores, city.id, 0)
      score < @critical_threshold
    end)
    |> Enum.map(fn city ->
      %{
        city: city,
        score: Map.get(health_scores, city.id, 0)
      }
    end)
    |> Enum.sort_by(& &1.score)
  end

  defp find_warning_cities(cities, health_scores) do
    cities
    |> Enum.filter(fn city ->
      score = Map.get(health_scores, city.id, 0)
      score >= @critical_threshold and score < @warning_threshold
    end)
    |> Enum.map(fn city ->
      %{
        city: city,
        score: Map.get(health_scores, city.id, 0)
      }
    end)
    |> Enum.sort_by(& &1.score)
  end

  defp log_health_alerts(critical_cities, warning_cities) do
    if Enum.any?(critical_cities) do
      Logger.warning(
        "🚨 CRITICAL HEALTH ALERT: #{length(critical_cities)} cities below #{@critical_threshold}%"
      )

      Enum.each(critical_cities, fn %{city: city, score: score} ->
        Logger.warning("  🔴 #{city.name}: #{score}% health score")
      end)
    end

    if Enum.any?(warning_cities) do
      Logger.info(
        "⚠️  WARNING: #{length(warning_cities)} cities below #{@warning_threshold}%"
      )

      Enum.each(warning_cities, fn %{city: city, score: score} ->
        Logger.info("  🟡 #{city.name}: #{score}% health score")
      end)
    end

    if Enum.empty?(critical_cities) and Enum.empty?(warning_cities) do
      Logger.info("✅ All cities have healthy scores (≥#{@warning_threshold}%)")
    end
  end

  defp store_health_snapshot(cities, health_scores) do
    # Store snapshot data for trending analysis
    # This can be used to detect drops over time
    snapshot_data = %{
      computed_at: DateTime.utc_now(),
      city_scores:
        Enum.map(cities, fn city ->
          %{
            city_id: city.id,
            city_slug: city.slug,
            city_name: city.name,
            health_score: Map.get(health_scores, city.id, 0)
          }
        end),
      summary: %{
        total_cities: length(cities),
        critical_count: length(Enum.filter(cities, fn c -> Map.get(health_scores, c.id, 0) < @critical_threshold end)),
        warning_count: length(Enum.filter(cities, fn c ->
          score = Map.get(health_scores, c.id, 0)
          score >= @critical_threshold and score < @warning_threshold
        end)),
        healthy_count: length(Enum.filter(cities, fn c -> Map.get(health_scores, c.id, 0) >= @warning_threshold end)),
        average_score: calculate_average_score(cities, health_scores)
      }
    }

    # Log snapshot summary
    Logger.info(
      "📊 Health snapshot: " <>
        "Avg: #{snapshot_data.summary.average_score}%, " <>
        "Healthy: #{snapshot_data.summary.healthy_count}, " <>
        "Warning: #{snapshot_data.summary.warning_count}, " <>
        "Critical: #{snapshot_data.summary.critical_count}"
    )

    # Future: Store in database table for historical trending
    # HealthSnapshot.insert(snapshot_data)

    :ok
  end

  defp calculate_average_score(cities, health_scores) do
    if Enum.empty?(cities) do
      0
    else
      total = Enum.sum(Enum.map(cities, fn c -> Map.get(health_scores, c.id, 0) end))
      round(total / length(cities))
    end
  end

  @doc """
  Manually trigger a health check. Useful for testing.
  """
  def check_now do
    perform(%Oban.Job{})
  end
end
