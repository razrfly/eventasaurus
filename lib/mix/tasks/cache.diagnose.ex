defmodule Mix.Tasks.Cache.Diagnose do
  @moduledoc """
  Diagnose city page cache state and identify issues.

  This task helps debug cache-related problems like:
  - Empty cache after deploy (Issue #3376)
  - Cache miss/stale patterns
  - Missing refresh jobs
  - Materialized view data issues

  ## Usage

      # Check all cities
      mix cache.diagnose

      # Check specific city
      mix cache.diagnose --city krakow

      # Include detailed Oban job info
      mix cache.diagnose --jobs

      # Force a cache refresh for a city
      mix cache.diagnose --city krakow --refresh

  ## Output Example

      🔍 City Page Cache Diagnostics
      ================================================================
      Timestamp: 2026-01-23 14:30:00 UTC

      📊 Base Cache Status:
      ┌──────────────┬─────────┬──────────┬─────────────────────┬────────┐
      │ City         │ Status  │ Events   │ Cached At           │ Age    │
      ├──────────────┼─────────┼──────────┼─────────────────────┼────────┤
      │ krakow       │ ✅ HIT  │ 477      │ 2026-01-23 14:15:00 │ 15m    │
      │ warszawa     │ ❌ MISS │ -        │ -                   │ -      │
      │ dublin       │ ⚠️ STALE│ 234      │ 2026-01-23 13:00:00 │ 90m    │
      └──────────────┴─────────┴──────────┴─────────────────────┴────────┘

      📋 Pending Cache Refresh Jobs:
      - krakow: base_refresh (job #12345) scheduled_at: 2026-01-23 14:31:00
      - warszawa: base_refresh (job #12346) running since: 2026-01-23 14:29:00

      📦 Materialized View Status:
      - city_events_mv: 1,234 total rows
      - krakow: 477 events
      - warszawa: 312 events

      💡 Issues Found:
      - warszawa: Base cache MISS with no pending refresh job
      - dublin: Cache is STALE (90m old, threshold: 30m)

      🔧 Recommendations:
      - Run: mix cache.diagnose --city warszawa --refresh
  """

  use Mix.Task
  require Logger
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusWeb.Cache.CityPageCache

  @shortdoc "Diagnose city page cache state and identify issues"

  # Staleness threshold in minutes
  @stale_threshold_minutes 30
  # Default radius for cache checks
  @default_radius_km 50

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [city: :string, jobs: :boolean, refresh: :boolean, verbose: :boolean],
        aliases: [c: :city, j: :jobs, r: :refresh, v: :verbose]
      )

    IO.puts("\n" <> IO.ANSI.cyan() <> "🔍 City Page Cache Diagnostics" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 64))
    IO.puts("Timestamp: #{DateTime.utc_now() |> DateTime.truncate(:second) |> to_string()}")
    IO.puts("")

    # Get cities to check
    cities =
      if opts[:city] do
        case get_city_by_slug(opts[:city]) do
          nil ->
            IO.puts(IO.ANSI.red() <> "❌ City not found: #{opts[:city]}" <> IO.ANSI.reset())
            list_available_cities()
            System.halt(1)

          city ->
            [city]
        end
      else
        get_primary_cities()
      end

    # Show base cache status
    cache_statuses = display_base_cache_status(cities, opts)

    # Show pending jobs if requested
    if opts[:jobs] do
      display_pending_jobs(cities)
    end

    # Show materialized view status
    display_mv_status(cities)

    # Analyze and show issues
    issues = analyze_issues(cache_statuses, cities)
    display_issues(issues)

    # Handle refresh request
    if opts[:refresh] && opts[:city] do
      refresh_city_cache(opts[:city])
    end

    IO.puts("")
  end

  defp display_base_cache_status(cities, opts) do
    IO.puts(IO.ANSI.blue() <> "📊 Base Cache Status:" <> IO.ANSI.reset())
    IO.puts("┌──────────────┬─────────┬──────────┬─────────────────────┬────────┐")
    IO.puts("│ City         │ Status  │ Events   │ Cached At           │ Age    │")
    IO.puts("├──────────────┼─────────┼──────────┼─────────────────────┼────────┤")

    statuses =
      cities
      |> Enum.map(fn city ->
        status = check_cache_status(city.slug)
        display_cache_row(city.slug, status)
        {city.slug, status}
      end)

    IO.puts("└──────────────┴─────────┴──────────┴─────────────────────┴────────┘")

    if opts[:verbose] do
      IO.puts("")
      IO.puts(IO.ANSI.yellow() <> "Cache Details:" <> IO.ANSI.reset())

      statuses
      |> Enum.each(fn {slug, status} ->
        IO.puts("  #{slug}: #{inspect(status, pretty: true, limit: 5)}")
      end)
    end

    IO.puts("")
    statuses
  end

  defp check_cache_status(city_slug) do
    cache_key = CityPageCache.base_cache_key(city_slug, @default_radius_km)

    case Cachex.get(:city_page_cache, cache_key) do
      {:ok, nil} ->
        %{status: :miss, events: nil, cached_at: nil, age_minutes: nil}

      {:ok, cached_value} ->
        event_count = length(Map.get(cached_value, :events, []))
        cached_at = Map.get(cached_value, :cached_at)
        age_minutes = if cached_at, do: DateTime.diff(DateTime.utc_now(), cached_at, :minute)

        status =
          cond do
            is_nil(cached_at) -> :unknown
            age_minutes > @stale_threshold_minutes -> :stale
            true -> :hit
          end

        %{
          status: status,
          events: event_count,
          cached_at: cached_at,
          age_minutes: age_minutes
        }

      {:error, reason} ->
        %{status: :error, error: reason, events: nil, cached_at: nil, age_minutes: nil}
    end
  end

  defp display_cache_row(city_slug, status) do
    city_col = String.pad_trailing(String.slice(city_slug, 0, 12), 12)

    {status_icon, status_text} =
      case status.status do
        :hit -> {IO.ANSI.green() <> "✅" <> IO.ANSI.reset(), "HIT  "}
        :miss -> {IO.ANSI.red() <> "❌" <> IO.ANSI.reset(), "MISS "}
        :stale -> {IO.ANSI.yellow() <> "⚠️ " <> IO.ANSI.reset(), "STALE"}
        :error -> {IO.ANSI.red() <> "💥" <> IO.ANSI.reset(), "ERROR"}
        _ -> {"❓", "UNK  "}
      end

    events_col =
      if status.events,
        do: String.pad_leading(to_string(status.events), 8),
        else: String.pad_leading("-", 8)

    cached_at_col =
      if status.cached_at,
        do:
          String.pad_trailing(
            status.cached_at |> DateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M"),
            19
          ),
        else: String.pad_trailing("-", 19)

    age_col =
      if status.age_minutes,
        do: String.pad_leading("#{status.age_minutes}m", 6),
        else: String.pad_leading("-", 6)

    IO.puts("│ #{city_col} │ #{status_icon} #{status_text}│ #{events_col} │ #{cached_at_col} │ #{age_col} │")
  end

  defp display_pending_jobs(cities) do
    IO.puts(IO.ANSI.magenta() <> "📋 Pending Cache Refresh Jobs:" <> IO.ANSI.reset())

    city_slugs = Enum.map(cities, & &1.slug)

    # Query Oban jobs for cache refresh
    jobs =
      from(j in Oban.Job,
        where: j.worker == "EventasaurusWeb.Jobs.CityPageCacheRefreshJob",
        where: j.state in ["available", "scheduled", "executing", "retryable"],
        order_by: [asc: j.scheduled_at]
      )
      |> Repo.all()
      |> Enum.filter(fn job ->
        city_slug = get_in(job.args, ["city_slug"])
        city_slug in city_slugs
      end)

    if length(jobs) == 0 do
      IO.puts("  (no pending jobs)")
    else
      jobs
      |> Enum.each(fn job ->
        city_slug = get_in(job.args, ["city_slug"])
        job_type = get_in(job.args, ["type"]) || "filter_refresh"
        state = job.state

        time_info =
          case state do
            "executing" ->
              started = job.attempted_at || job.scheduled_at
              "running since: #{format_time(started)}"

            _ ->
              "scheduled_at: #{format_time(job.scheduled_at)}"
          end

        state_icon =
          case state do
            "executing" -> IO.ANSI.green() <> "▶" <> IO.ANSI.reset()
            "scheduled" -> IO.ANSI.yellow() <> "⏳" <> IO.ANSI.reset()
            "available" -> IO.ANSI.blue() <> "⏸" <> IO.ANSI.reset()
            _ -> "?"
          end

        IO.puts("  #{state_icon} #{city_slug}: #{job_type} (job ##{job.id}) #{time_info}")
      end)
    end

    IO.puts("")
  end

  defp display_mv_status(cities) do
    IO.puts(IO.ANSI.green() <> "📦 Materialized View Status:" <> IO.ANSI.reset())

    # Get total row count
    total_count =
      case Repo.query("SELECT COUNT(*) FROM city_events_mv", []) do
        {:ok, %{rows: [[count]]}} -> count
        _ -> "error"
      end

    IO.puts("  - city_events_mv: #{format_number(total_count)} total rows")

    # Get count per city
    cities
    |> Enum.take(10)
    |> Enum.each(fn city ->
      count =
        case Repo.query("SELECT COUNT(*) FROM city_events_mv WHERE city_slug = $1", [city.slug]) do
          {:ok, %{rows: [[c]]}} -> c
          _ -> "error"
        end

      IO.puts("  - #{city.slug}: #{format_number(count)} events")
    end)

    IO.puts("")
  end

  defp analyze_issues(cache_statuses, _cities) do
    # Get pending jobs
    pending_job_cities =
      from(j in Oban.Job,
        where: j.worker == "EventasaurusWeb.Jobs.CityPageCacheRefreshJob",
        where: j.state in ["available", "scheduled", "executing", "retryable"],
        select: fragment("args->>'city_slug'")
      )
      |> Repo.all()
      |> MapSet.new()

    issues =
      cache_statuses
      |> Enum.flat_map(fn {city_slug, status} ->
        city_issues = []

        # Check for MISS with no pending job (Issue #3376)
        city_issues =
          if status.status == :miss && city_slug not in pending_job_cities do
            [
              %{
                city: city_slug,
                severity: :critical,
                message: "Base cache MISS with no pending refresh job"
              }
              | city_issues
            ]
          else
            city_issues
          end

        # Check for STALE cache
        city_issues =
          if status.status == :stale do
            [
              %{
                city: city_slug,
                severity: :warning,
                message:
                  "Cache is STALE (#{status.age_minutes}m old, threshold: #{@stale_threshold_minutes}m)"
              }
              | city_issues
            ]
          else
            city_issues
          end

        # Check for empty cache (0 events)
        city_issues =
          if status.status == :hit && status.events == 0 do
            [
              %{
                city: city_slug,
                severity: :warning,
                message: "Cache exists but has 0 events - data may not be loading"
              }
              | city_issues
            ]
          else
            city_issues
          end

        city_issues
      end)

    issues
  end

  defp display_issues(issues) do
    if length(issues) == 0 do
      IO.puts(IO.ANSI.green() <> "✅ No issues found!" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.yellow() <> "💡 Issues Found:" <> IO.ANSI.reset())

      issues
      |> Enum.each(fn issue ->
        icon =
          case issue.severity do
            :critical -> IO.ANSI.red() <> "❌" <> IO.ANSI.reset()
            :warning -> IO.ANSI.yellow() <> "⚠️ " <> IO.ANSI.reset()
            _ -> "ℹ️ "
          end

        IO.puts("  #{icon} #{issue.city}: #{issue.message}")
      end)

      IO.puts("")
      IO.puts(IO.ANSI.cyan() <> "🔧 Recommendations:" <> IO.ANSI.reset())

      critical_cities =
        issues
        |> Enum.filter(&(&1.severity == :critical))
        |> Enum.map(& &1.city)
        |> Enum.uniq()

      critical_cities
      |> Enum.each(fn city ->
        IO.puts("  - Run: mix cache.diagnose --city #{city} --refresh")
      end)
    end
  end

  defp refresh_city_cache(city_slug) do
    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "🔄 Refreshing cache for #{city_slug}..." <> IO.ANSI.reset())

    case EventasaurusWeb.Jobs.CityPageCacheRefreshJob.enqueue_base(city_slug, @default_radius_km) do
      {:ok, %Oban.Job{id: job_id}} ->
        IO.puts(
          IO.ANSI.green() <> "✅ Enqueued refresh job ##{job_id} for #{city_slug}" <> IO.ANSI.reset()
        )

      {:ok, :duplicate} ->
        IO.puts(
          IO.ANSI.yellow() <>
            "⚠️  Refresh job already queued for #{city_slug}" <> IO.ANSI.reset()
        )

      {:error, reason} ->
        IO.puts(
          IO.ANSI.red() <>
            "❌ Failed to enqueue refresh: #{inspect(reason)}" <> IO.ANSI.reset()
        )
    end
  end

  defp get_city_by_slug(slug) do
    from(c in City, where: c.slug == ^slug)
    |> Repo.one()
  end

  defp get_primary_cities do
    # Get cities that have events in the materialized view
    from(c in City,
      where:
        c.slug in ^[
          "krakow",
          "warszawa",
          "dublin",
          "wroclaw",
          "poznan",
          "gdansk",
          "katowice",
          "lodz",
          "paris"
        ],
      order_by: [asc: c.slug]
    )
    |> Repo.all()
  end

  defp list_available_cities do
    IO.puts("")
    IO.puts("Available cities with events:")

    from(c in City,
      join: subquery in subquery(
        from(e in "city_events_mv",
          select: %{city_slug: e.city_slug},
          distinct: true
        )
      ),
      on: c.slug == subquery.city_slug,
      select: c.slug,
      order_by: [asc: c.slug]
    )
    |> Repo.all()
    |> Enum.each(&IO.puts("  - #{&1}"))
  end

  defp format_time(nil), do: "-"

  defp format_time(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(other), do: to_string(other)
end
