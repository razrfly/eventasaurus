defmodule EventasaurusDiscovery.Services.FreshnessHealthChecker do
  @moduledoc """
  Monitors EventFreshnessChecker effectiveness by analyzing database state.

  Calculates expected skip rate based on last_seen_at timestamps vs. threshold.
  If freshness checking works correctly, most events should be "fresh" (within threshold).

  ## Usage

      iex> FreshnessHealthChecker.check_health(source_id)
      %{
        total_events: 1234,
        fresh_events: 856,
        stale_events: 378,
        expected_skip_rate: 0.694,
        threshold_hours: 168,
        status: :healthy,
        diagnosis: "✅ HEALTHY: 69.4% of events are fresh and being skipped."
      }

  ## Status Levels

  - `:healthy` - 70%+ fresh events (working correctly)
  - `:degraded` - 30-70% fresh events (partially working)
  - `:warning` - 5-30% fresh events (mostly broken)
  - `:broken` - 0-5% fresh events (completely broken)
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Services.EventFreshnessChecker

  @doc """
  Check freshness health for a source.

  Returns a map with:
  - `total_events` - Total events in system for this source
  - `fresh_events` - Events with last_seen_at within threshold
  - `stale_events` - Events with last_seen_at outside threshold
  - `expected_skip_rate` - Percentage that should be skipped (0.0-1.0)
  - `threshold_hours` - Configured threshold for this source
  - `status` - Health status atom
  - `diagnosis` - Human-readable diagnosis string
  """
  def check_health(source_id) when is_integer(source_id) do
    threshold_hours = EventFreshnessChecker.get_threshold_for_source(source_id)
    threshold_ago = DateTime.add(DateTime.utc_now(), -threshold_hours, :hour)

    # Count all events for this source
    total =
      Repo.one(
        from(pes in PublicEventSource,
          where: pes.source_id == ^source_id,
          select: count(pes.id)
        )
      ) || 0

    # Count fresh events (last_seen_at within threshold)
    fresh =
      Repo.one(
        from(pes in PublicEventSource,
          where: pes.source_id == ^source_id,
          where: pes.last_seen_at > ^threshold_ago,
          select: count(pes.id)
        )
      ) || 0

    stale = total - fresh
    expected_skip_rate = if total > 0, do: fresh / total, else: 0.0

    status = calculate_status(expected_skip_rate, total)

    %{
      total_events: total,
      fresh_events: fresh,
      stale_events: stale,
      expected_skip_rate: expected_skip_rate,
      threshold_hours: threshold_hours,
      status: status,
      diagnosis: diagnose_issue(expected_skip_rate, total, fresh)
    }
  end

  @doc """
  Calculate health status based on skip rate and total events.
  """
  def calculate_status(skip_rate, total) do
    cond do
      total == 0 ->
        :no_data

      skip_rate >= 0.70 ->
        :healthy

      skip_rate >= 0.30 ->
        :degraded

      skip_rate >= 0.05 ->
        :warning

      true ->
        :broken
    end
  end

  @doc """
  Generate human-readable diagnosis based on freshness metrics.
  """
  def diagnose_issue(skip_rate, total, fresh) do
    cond do
      total == 0 ->
        "No events in system yet"

      skip_rate < 0.05 ->
        """
        🔴 CRITICAL: Only #{fresh}/#{total} events are fresh. Possible causes:
          • External IDs don't match between index and transformer
          • last_seen_at not being updated by EventProcessor
          • All events legitimately older than threshold (unlikely)
        """

      skip_rate < 0.30 ->
        "⚠️ WARNING: Only #{Float.round(skip_rate * 100, 1)}% fresh. Freshness checking may be partially broken."

      skip_rate < 0.70 ->
        "⚡ DEGRADED: #{Float.round(skip_rate * 100, 1)}% fresh. Lower than expected (70-85%)."

      true ->
        "✅ HEALTHY: #{Float.round(skip_rate * 100, 1)}% of events are fresh and being skipped."
    end
  end

  @doc """
  Check health for all sources and return summary.
  """
  def check_all_sources do
    sources =
      Repo.all(
        from(s in EventasaurusDiscovery.Sources.Source,
          select: %{id: s.id, slug: s.slug, name: s.name}
        )
      )

    Enum.map(sources, fn source ->
      health = check_health(source.id)

      Map.merge(source, health)
    end)
  end

  @doc """
  Get sources with broken freshness checking.
  """
  def get_broken_sources do
    check_all_sources()
    |> Enum.filter(fn source -> source.status == :broken end)
  end
end
