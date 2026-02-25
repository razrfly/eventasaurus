defmodule Mix.Tasks.Audit.TimeConsistency do
  @moduledoc """
  Audit time consistency between starts_at (UTC) and stored occurrences.

  Checks the core invariant: `starts_at` (UTC) shifted to venue timezone
  should equal the stored occurrence `date` + `time`. Catches the most
  common timezone bug where times get stored as UTC instead of local time.

  ## Usage

      # Check all sources (last 7 days)
      mix audit.time_consistency

      # Check specific source
      mix audit.time_consistency --source cinema_city

      # Custom lookback window
      mix audit.time_consistency --source cinema_city --hours 48

      # Verbose: show all events, not just mismatches
      mix audit.time_consistency --source cinema_city --verbose

      # Scrape mode: run a scrape then check the results
      mix audit.time_consistency --source cinema_city --scrape --limit 20

      # Fix mode: correct mismatched occurrence times in-place
      mix audit.time_consistency --source cinema_city --fix
      mix audit.time_consistency --fix   # fix all sources

  ## Options

      -s, --source   Specific source to check (CLI key, e.g. cinema_city)
      -h, --hours    Lookback window in hours (default: 168 = 7 days)
      -v, --verbose  Show all events including OK ones
      -l, --limit    Max events to check (default: 500) / scrape (default: 20)
      --scrape       Run a scrape first, then check results (requires --source)
      --fix          Fix mismatched occurrence times in the database
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Monitoring.TimeConsistency
  alias EventasaurusDiscovery.Sources.SourcePatterns
  alias EventasaurusDiscovery.Sources.SourceRegistry
  alias EventasaurusDiscovery.Sources.Source

  @shortdoc "Audit time consistency for event occurrences"

  @spec run([String.t()]) :: any()
  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          source: :string,
          hours: :integer,
          verbose: :boolean,
          scrape: :boolean,
          limit: :integer,
          fix: :boolean
        ],
        aliases: [s: :source, h: :hours, v: :verbose, l: :limit]
      )

    source = opts[:source]
    hours = opts[:hours] || 168
    verbose = opts[:verbose] || false
    scrape = opts[:scrape] || false
    fix = opts[:fix] || false
    limit = opts[:limit]

    # Validate source if provided
    if source && !SourcePatterns.valid_source?(source) do
      IO.puts(IO.ANSI.red() <> "Unknown source: #{source}" <> IO.ANSI.reset())
      SourcePatterns.print_available_sources()
      System.halt(1)
    end

    cond do
      fix -> run_fix_mode(source, hours, limit || 500)
      scrape -> run_scrape_mode(source, hours, verbose, limit || 20)
      true -> run_db_mode(source, hours, verbose, limit || 500)
    end
  end

  # ── Mode 1: DB Audit ──────────────────────────────────────────────────

  defp run_db_mode(source, hours, verbose, limit) do
    print_header(hours)

    sources_to_check =
      if source do
        [source]
      else
        SourcePatterns.all_cli_keys()
      end

    results =
      Enum.map(sources_to_check, fn source_key ->
        source_slug = String.replace(source_key, "_", "-")
        {:ok, result} = TimeConsistency.check(source_slug, hours: hours, limit: limit)
        display_source_result(source_key, result, verbose)
        result
      end)

    display_summary(results)

    total_mismatched = results |> Enum.map(& &1.total_mismatched) |> Enum.sum()
    if total_mismatched > 0, do: System.halt(1)
  end

  # ── Mode 3: Fix mismatched times ─────────────────────────────────────

  defp run_fix_mode(source, hours, limit) do
    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "Time Consistency Fix" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("=", 50) <> IO.ANSI.reset())
    IO.puts("")

    sources_to_fix =
      if source do
        [source]
      else
        SourcePatterns.all_cli_keys()
      end

    total_fixed = 0
    total_failed = 0

    {total_fixed, total_failed} =
      Enum.reduce(sources_to_fix, {total_fixed, total_failed}, fn source_key, {fixed, failed} ->
        source_slug = String.replace(source_key, "_", "-")
        display_name = SourcePatterns.get_display_name(source_key)

        {:ok, fix_result} = TimeConsistency.fix(source_slug, hours: hours, limit: limit)

        if fix_result.total_mismatched > 0 do
          IO.puts(
            "  #{display_name}: fixed #{fix_result.fixed}/#{fix_result.total_mismatched}" <>
              if(fix_result.failed > 0, do: " (#{fix_result.failed} failed)", else: "")
          )
        end

        {fixed + fix_result.fixed, failed + fix_result.failed}
      end)

    IO.puts("")

    cond do
      total_failed > 0 and total_fixed > 0 ->
        IO.puts(
          IO.ANSI.yellow() <>
            "Fixed #{total_fixed} events, but #{total_failed} failed" <>
            IO.ANSI.reset()
        )

        IO.puts("")
        System.halt(1)

      total_failed > 0 ->
        IO.puts(
          IO.ANSI.red() <>
            "Failed to fix #{total_failed} mismatches" <>
            IO.ANSI.reset()
        )

        IO.puts("")
        System.halt(1)

      total_fixed > 0 ->
        IO.puts(
          IO.ANSI.green() <>
            "Fixed #{total_fixed} events" <>
            IO.ANSI.reset()
        )

      true ->
        IO.puts("No mismatches to fix")
    end

    IO.puts("")
  end

  # ── Mode 2: Scrape-then-check ─────────────────────────────────────────

  defp run_scrape_mode(nil, _hours, _verbose, _limit) do
    IO.puts(IO.ANSI.red() <> "--scrape requires --source" <> IO.ANSI.reset())
    System.halt(1)
  end

  defp run_scrape_mode(source, _hours, verbose, limit) do
    source_slug = String.replace(source, "_", "-")
    display_name = SourcePatterns.get_display_name(source)

    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "Time Consistency Audit (Scrape Mode)" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("=", 50) <> IO.ANSI.reset())
    IO.puts("Source: #{display_name}")
    IO.puts("Limit: #{limit} events")
    IO.puts("")

    pre_scrape_time = DateTime.utc_now()

    case SourceRegistry.get_sync_job(source_slug) do
      {:ok, job_module} ->
        IO.puts("Running #{inspect(job_module)}...")

        job = %Oban.Job{id: 0, args: %{"limit" => limit}}

        case job_module.perform(job) do
          {:ok, _} ->
            IO.puts(IO.ANSI.green() <> "Scrape completed" <> IO.ANSI.reset())

          {:error, reason} ->
            IO.puts(IO.ANSI.red() <> "Scrape failed: #{inspect(reason)}" <> IO.ANSI.reset())

            System.halt(1)
        end

        # Wait for child jobs to complete
        IO.puts("Waiting for child jobs to complete...")
        wait_for_child_jobs(source_slug)

        # Check the freshly scraped events
        IO.puts("")
        print_header(nil)

        {:ok, result} =
          TimeConsistency.check(source_slug, from_datetime: pre_scrape_time, limit: limit)

        display_source_result(source, result, verbose)
        display_summary([result])

        if result.total_mismatched > 0, do: System.halt(1)

      {:error, :not_found} ->
        # Try underscore variant (week_pl edge case)
        case SourceRegistry.get_sync_job(source) do
          {:ok, job_module} ->
            run_scrape_with_module(job_module, source, pre_scrape_time, verbose, limit)

          {:error, :not_found} ->
            IO.puts(IO.ANSI.red() <> "No sync job found for #{source_slug}" <> IO.ANSI.reset())

            System.halt(1)
        end
    end
  end

  defp run_scrape_with_module(job_module, source, pre_scrape_time, verbose, limit) do
    source_slug = String.replace(source, "_", "-")
    IO.puts("Running #{inspect(job_module)}...")

    job = %Oban.Job{id: 0, args: %{"limit" => limit}}

    case job_module.perform(job) do
      {:ok, _} ->
        IO.puts(IO.ANSI.green() <> "Scrape completed" <> IO.ANSI.reset())

      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "Scrape failed: #{inspect(reason)}" <> IO.ANSI.reset())
        System.halt(1)
    end

    IO.puts("Waiting for child jobs to complete...")
    wait_for_child_jobs(source_slug)

    IO.puts("")
    print_header(nil)

    {:ok, result} =
      TimeConsistency.check(source_slug, from_datetime: pre_scrape_time, limit: limit)

    display_source_result(source, result, verbose)
    display_summary([result])

    if result.total_mismatched > 0, do: System.halt(1)
  end

  # ── Job Polling ────────────────────────────────────────────────────────

  defp wait_for_child_jobs(source_slug) do
    module_name = Source.slug_to_module_name(source_slug)
    worker_pattern = "EventasaurusDiscovery.Sources.#{module_name}.Jobs.%"

    poll_jobs(worker_pattern, System.monotonic_time(:millisecond), 300_000)
  end

  defp poll_jobs(worker_pattern, start_time, timeout) do
    import Ecto.Query

    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > timeout do
      IO.puts("")

      IO.puts(IO.ANSI.yellow() <> "Timed out waiting for child jobs (5min)" <> IO.ANSI.reset())
    else
      pending_count =
        from(j in Oban.Job,
          where: like(j.worker, ^worker_pattern),
          where: j.state in ["available", "executing", "scheduled", "retryable"],
          select: count(j.id)
        )
        |> EventasaurusApp.Repo.one()

      if pending_count > 0 do
        IO.write(".")
        Process.sleep(2_000)
        poll_jobs(worker_pattern, start_time, timeout)
      else
        IO.puts(" done!")
      end
    end
  end

  # ── Display ────────────────────────────────────────────────────────────

  defp print_header(hours) do
    IO.puts("")
    IO.puts(IO.ANSI.cyan() <> "Time Consistency Audit" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.cyan() <> String.duplicate("=", 50) <> IO.ANSI.reset())

    if hours do
      IO.puts("Period: Last #{hours} hours")
    else
      IO.puts("Period: Freshly scraped events")
    end

    IO.puts("")
  end

  defp display_source_result(source_key, result, verbose) do
    display_name = SourcePatterns.get_display_name(source_key)

    IO.puts(IO.ANSI.blue() <> "#{display_name} (#{result.timezone})" <> IO.ANSI.reset())

    IO.puts(String.duplicate("-", 50))

    IO.puts(
      "  Checked: #{result.total_checked} | OK: #{result.total_ok} | " <>
        "Mismatched: #{result.total_mismatched} | Skipped: #{result.total_skipped}"
    )

    if result.total_checked == 0 and result.total_skipped == 0 do
      IO.puts(IO.ANSI.yellow() <> "  No events found for this source" <> IO.ANSI.reset())
    end

    # Show mismatches
    Enum.each(result.mismatches, fn m ->
      IO.puts("")

      IO.puts(
        IO.ANSI.red() <>
          "  #{status_icon(m.status)} ##{m.event_id} #{truncate(m.title, 40)}" <>
          IO.ANSI.reset()
      )

      IO.puts("     starts_at (UTC): #{format_datetime(m.starts_at)}")
      IO.puts("     Expected local:  #{m.expected_date} #{m.expected_time}")

      stored_time = m.occurrence_time || "(no time)"

      IO.puts(
        "     Stored:          #{m.occurrence_date} #{stored_time}" <>
          mismatch_hint(m)
      )
    end)

    # In verbose mode, show OK events too
    if verbose and result.total_ok > 0 do
      IO.puts("")
      IO.puts(IO.ANSI.faint() <> "  OK events:" <> IO.ANSI.reset())
      # We don't have OK events in the result (only mismatches), so note that
      IO.puts(
        IO.ANSI.faint() <>
          "  #{result.total_ok} events passed consistency check" <> IO.ANSI.reset()
      )
    end

    if result.total_mismatched == 0 and result.total_checked > 0 do
      IO.puts(IO.ANSI.green() <> "  All times consistent" <> IO.ANSI.reset())
    end

    IO.puts("")
  end

  defp display_summary(results) do
    IO.puts(IO.ANSI.cyan() <> String.duplicate("=", 50) <> IO.ANSI.reset())
    IO.puts("Summary:")

    total_sources = length(results)
    total_events = results |> Enum.map(& &1.total_checked) |> Enum.sum()
    total_mismatches = results |> Enum.map(& &1.total_mismatched) |> Enum.sum()

    mismatch_pct =
      if total_events > 0 do
        Float.round(total_mismatches / total_events * 100, 1)
      else
        0.0
      end

    IO.puts(
      "  Sources: #{total_sources} | Events: #{total_events} | " <>
        "Mismatches: #{total_mismatches} (#{mismatch_pct}%)"
    )

    # Show per-source issues
    problem_sources =
      results
      |> Enum.filter(&(&1.total_mismatched > 0))
      |> Enum.sort_by(& &1.total_mismatched, :desc)

    if length(problem_sources) > 0 do
      IO.puts("")

      IO.puts(
        IO.ANSI.yellow() <>
          "  Issues:" <> IO.ANSI.reset()
      )

      Enum.each(problem_sources, fn r ->
        pct =
          if r.total_checked > 0 do
            Float.round(r.total_mismatched / r.total_checked * 100, 1)
          else
            0.0
          end

        IO.puts("    #{r.source}: #{r.total_mismatched} mismatches (#{pct}%)")
      end)
    else
      if total_events > 0 do
        IO.puts(IO.ANSI.green() <> "  All times consistent!" <> IO.ANSI.reset())
      end
    end

    IO.puts("")
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp status_icon(:time_mismatch), do: "TIME"
  defp status_icon(:date_mismatch), do: "DATE"
  defp status_icon(:both_mismatch), do: "BOTH"
  defp status_icon(_), do: "??"

  defp mismatch_hint(%{status: :time_mismatch}), do: "  <- UTC stored as local!"
  defp mismatch_hint(%{status: :date_mismatch}), do: "  <- date shifted by timezone"
  defp mismatch_hint(%{status: :both_mismatch}), do: "  <- UTC stored as local!"
  defp mismatch_hint(_), do: ""

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%SZ")
  end

  defp truncate(nil, _max), do: "(no title)"

  defp truncate(str, max) when byte_size(str) <= max, do: str

  defp truncate(str, max) do
    String.slice(str, 0, max - 3) <> "..."
  end
end
