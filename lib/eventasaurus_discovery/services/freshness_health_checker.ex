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

  # Use read replica for all read operations in this module
  defp repo, do: Repo.replica()

  @doc """
  Check freshness health for a source using Oban job execution metrics.

  This is the CORRECT way to monitor freshness checking effectiveness.
  It compares actual job execution rate vs expected rate based on Oban history.

  Returns a map with:
  - `total_events` - Total events in system for this source
  - `detail_jobs_executed` - Detail jobs run in lookback period
  - `expected_jobs` - Expected jobs if freshness checking works (15-30% rate)
  - `execution_multiplier` - How many times more jobs ran than expected
  - `processing_rate` - Percentage of events processed per run
  - `lookback_days` - Days of history analyzed
  - `threshold_hours` - Configured threshold for this source
  - `status` - Health status atom
  - `diagnosis` - Human-readable diagnosis string
  """
  def check_health(source_id) when is_integer(source_id) do
    check_health_by_execution_rate(source_id)
  end

  @doc """
  Check freshness health by analyzing actual Oban job execution rate.

  This is simpler and more reliable than simulating IndexJob behavior.
  Works universally for all scrapers by comparing job counts vs event counts.
  """
  def check_health_by_execution_rate(source_id) when is_integer(source_id) do
    threshold_hours = EventFreshnessChecker.get_threshold_for_source(source_id)
    lookback_days = 7

    # Count all events for this source
    total_events =
      repo().one(
        from(pes in PublicEventSource,
          where: pes.source_id == ^source_id,
          select: count(pes.id)
        )
      ) || 0

    # Handle empty sources
    if total_events == 0 do
      %{
        total_events: 0,
        detail_jobs_executed: 0,
        expected_jobs: 0,
        execution_multiplier: 0.0,
        processing_rate: 0.0,
        lookback_days: lookback_days,
        threshold_hours: threshold_hours,
        status: :no_data,
        diagnosis: "No events in system yet - cannot assess freshness checking effectiveness"
      }
    else
      # Count detail jobs executed in last week from Oban
      detail_jobs = count_detail_jobs_for_source(source_id, lookback_days)

      # Calculate metrics with division by zero guards
      runs_in_period =
        if is_number(threshold_hours) and threshold_hours > 0 do
          lookback_days * 24 / threshold_hours
        else
          0
        end

      jobs_per_run = if runs_in_period > 0, do: detail_jobs / runs_in_period, else: 0.0
      processing_rate = if total_events > 0, do: jobs_per_run / total_events, else: 0.0

      # Expected: 15-30% processing rate per run (average 25%)
      expected_jobs = total_events * runs_in_period * 0.25
      execution_multiplier = if expected_jobs > 0, do: detail_jobs / expected_jobs, else: 0.0

      status = calculate_execution_status(processing_rate, total_events)

      %{
        total_events: total_events,
        detail_jobs_executed: detail_jobs,
        expected_jobs: round(expected_jobs),
        execution_multiplier: execution_multiplier,
        processing_rate: processing_rate,
        runs_in_period: runs_in_period,
        lookback_days: lookback_days,
        threshold_hours: threshold_hours,
        status: status,
        diagnosis:
          diagnose_execution_rate(
            processing_rate,
            execution_multiplier,
            detail_jobs,
            total_events
          )
      }
    end
  end

  # Count detail jobs executed for a source in the last N days
  defp count_detail_jobs_for_source(source_id, lookback_days) do
    cutoff = DateTime.add(DateTime.utc_now(), -lookback_days * 24 * 3600, :second)

    # Query oban_jobs for detail jobs with this source_id
    # Matches: VenueDetailJob, EventDetailJob, etc.
    # Use completed_at to measure jobs actually executed in the window
    repo().one(
      from(j in "oban_jobs",
        where: fragment("? ->> 'source_id' = ?", j.args, ^to_string(source_id)),
        where: fragment("? LIKE '%DetailJob'", j.worker),
        where: j.state == "completed",
        where: j.completed_at > ^cutoff,
        select: count(j.id)
      )
    ) || 0
  end

  @doc """
  Calculate health status based on processing rate.

  Processing rate is the percentage of events processed per scraper run.
  - <40% = healthy (most events skipped)
  - 40-70% = degraded (some events skipped)
  - 70-95% = warning (few events skipped)
  - 95%+ = broken (no events skipped)
  """
  def calculate_execution_status(processing_rate, total_events) do
    cond do
      total_events == 0 ->
        :no_data

      processing_rate < 0.40 ->
        :healthy

      processing_rate < 0.70 ->
        :degraded

      processing_rate < 0.95 ->
        :warning

      true ->
        :broken
    end
  end

  # Legacy function for backwards compatibility
  @doc false
  def calculate_status(skip_rate, total) do
    calculate_execution_status(1.0 - skip_rate, total)
  end

  @doc """
  Generate human-readable diagnosis based on execution rate metrics.
  """
  def diagnose_execution_rate(processing_rate, execution_multiplier, detail_jobs, total_events) do
    cond do
      total_events == 0 ->
        "No events in system yet"

      processing_rate < 0.40 ->
        "✅ HEALTHY: Processing #{Float.round(processing_rate * 100, 1)}% of events per run (#{detail_jobs} jobs for #{total_events} events). Freshness checking working correctly."

      processing_rate < 0.70 ->
        "⚡ DEGRADED: Processing #{Float.round(processing_rate * 100, 1)}% of events per run (#{detail_jobs} jobs for #{total_events} events). Expected <40% per run."

      processing_rate < 0.95 ->
        """
        ⚠️ WARNING: Processing #{Float.round(processing_rate * 100, 1)}% of events per run (#{detail_jobs} jobs for #{total_events} events).
        Freshness checking is mostly broken. Expected <40% per run.
        """

      true ->
        """
        🔴 BROKEN: Processing #{Float.round(processing_rate * 100, 1)}% of events per run (#{detail_jobs} jobs for #{total_events} events).
        Running #{Float.round(execution_multiplier, 1)}x more jobs than expected.

        Possible causes:
        • External ID format mismatch between IndexJob and Transformer
        • last_seen_at not being updated by EventProcessor
        • EventFreshnessChecker not being called in IndexJob
        """
    end
  end

  # Legacy diagnosis function
  @doc false
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
      repo().all(
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
