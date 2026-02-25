defmodule EventasaurusDiscovery.Monitoring.TimeConsistency do
  @moduledoc """
  Checks the core timezone invariant for stored events:
  `starts_at` (UTC) shifted to venue timezone should equal stored occurrence `date` + `time`.

  This catches the most common timezone bug: occurrence times stored as UTC
  instead of local time.

  ## Examples

      {:ok, result} = TimeConsistency.check("cinema-city")
      IO.inspect(result.mismatches)

      {:ok, results} = TimeConsistency.check_all()
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Locations.Country
  alias EventasaurusDiscovery.Helpers.TimezoneMapper
  alias EventasaurusDiscovery.Sources.SourcePatterns
  import Ecto.Query

  @default_hours 168
  @default_limit 500

  @doc """
  Check all events for a source. Returns `{:ok, check_result}`.

  ## Options

    * `:hours` - Lookback window in hours (default: 168)
    * `:limit` - Max events to check (default: 500)
    * `:from_datetime` - Override lookback with specific start time
  """
  def check(source_slug, opts \\ []) do
    hours = Keyword.get(opts, :hours, @default_hours)
    limit = Keyword.get(opts, :limit, @default_limit)

    from_datetime =
      Keyword.get(opts, :from_datetime, DateTime.add(DateTime.utc_now(), -hours, :hour))

    source_slug = normalize_slug(source_slug)
    events = fetch_events(source_slug, from_datetime, limit)

    {checked, skipped} =
      Enum.reduce(events, {[], 0}, fn event, {checks, skip_count} ->
        case check_event(event) do
          {:ok, result} -> {[result | checks], skip_count}
          :skip -> {checks, skip_count + 1}
        end
      end)

    checked = Enum.reverse(checked)
    mismatches = Enum.filter(checked, &(&1.status != :ok))
    timezone = determine_source_timezone(events)

    {:ok,
     %{
       source: source_slug,
       timezone: timezone,
       total_checked: length(checked),
       total_ok: Enum.count(checked, &(&1.status == :ok)),
       total_mismatched: length(mismatches),
       total_skipped: skipped,
       mismatches: mismatches
     }}
  end

  @doc """
  Check all sources. Returns `{:ok, [check_result]}`.
  """
  def check_all(opts \\ []) do
    results =
      SourcePatterns.all_cli_keys()
      |> Enum.map(fn cli_key ->
        source_slug = String.replace(cli_key, "_", "-")
        {:ok, result} = check(source_slug, opts)
        result
      end)

    {:ok, results}
  end

  @doc """
  Fix occurrence times for events with mismatches. Returns `{:ok, fix_result}`.

  For each event with a time mismatch, shifts `starts_at` to the venue's local
  timezone and rewrites ALL date entries' `date` and `time` fields accordingly.

  ## Options

  Same as `check/2` plus:
    * `:dry_run` - If true, report what would change without writing (default: false)
  """
  def fix(source_slug, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    {:ok, check_result} = check(source_slug, opts)

    fixed =
      check_result.mismatches
      |> Enum.map(fn mismatch ->
        fix_event(mismatch.event_id, dry_run)
      end)
      |> Enum.filter(&(&1 != :skip))

    fixed_count = Enum.count(fixed, fn {status, _} -> status == :ok end)
    failed_count = Enum.count(fixed, fn {status, _} -> status == :error end)

    {:ok,
     %{
       source: check_result.source,
       total_mismatched: check_result.total_mismatched,
       fixed: fixed_count,
       failed: failed_count,
       dry_run: dry_run
     }}
  end

  defp fix_event(event_id, dry_run) do
    event =
      from(pe in PublicEvent,
        join: v in Venue,
        on: pe.venue_id == v.id,
        join: c in City,
        on: v.city_id == c.id,
        left_join: co in Country,
        on: c.country_id == co.id,
        where: pe.id == ^event_id,
        preload: [venue: {v, city_ref: {c, country: co}}]
      )
      |> Repo.one()

    if is_nil(event) do
      :skip
    else
      case resolve_timezone(event) do
        nil ->
          :skip

        timezone ->
          corrected_dates = correct_all_dates(event, timezone)

          if dry_run do
            {:ok, :dry_run}
          else
            updated_occurrences = Map.put(event.occurrences, "dates", corrected_dates)

            event
            |> Ecto.Changeset.change(occurrences: updated_occurrences)
            |> Repo.update()
            |> case do
              {:ok, _} -> {:ok, event_id}
              {:error, reason} -> {:error, reason}
            end
          end
      end
    end
  end

  # Correct all date entries by shifting starts_at for each one.
  # For multi-occurrence events, we reconstruct each entry's local time
  # by finding the matching starts_at (from the date entry's external_id)
  # or by using the event's starts_at as the reference.
  defp correct_all_dates(event, timezone) do
    Enum.map(event.occurrences["dates"], fn date_entry ->
      # Try to reconstruct the UTC datetime for this specific entry
      utc_dt = reconstruct_utc_for_entry(date_entry, event)

      case DateTime.shift_zone(utc_dt, timezone) do
        {:ok, local_dt} ->
          local_date = local_dt |> DateTime.to_date() |> Date.to_string()

          local_time =
            local_dt |> DateTime.to_time() |> Time.to_string() |> String.slice(0..4)

          date_entry
          |> Map.put("date", local_date)
          |> Map.put("time", local_time)

        {:error, _} ->
          date_entry
      end
    end)
  end

  # Reconstruct the UTC datetime for a specific date entry.
  # The stored date/time is currently UTC (the bug), so we can parse it directly.
  defp reconstruct_utc_for_entry(date_entry, event) do
    date_str = date_entry["date"]
    time_str = date_entry["time"]

    if date_str && time_str do
      case {Date.from_iso8601(date_str), Time.from_iso8601(time_str <> ":00")} do
        {{:ok, date}, {:ok, time}} ->
          DateTime.new!(date, time, "Etc/UTC")

        _ ->
          event.starts_at
      end
    else
      event.starts_at
    end
  end

  @doc """
  Check a single preloaded event. Returns `{:ok, event_check}` or `:skip`.

  The event must be preloaded with `venue: [city_ref: [country: _]]`.
  """
  def check_event(event) do
    cond do
      is_nil(event.occurrences) ->
        :skip

      is_nil(get_in(event.occurrences, ["dates"])) or event.occurrences["dates"] == [] ->
        :skip

      event.occurrences["type"] == "pattern" ->
        :skip

      is_nil(event.venue) ->
        :skip

      is_nil(event.venue.city_ref) ->
        :skip

      true ->
        case resolve_timezone(event) do
          nil ->
            :skip

          timezone ->
            dates = event.occurrences["dates"]
            do_check(event, timezone, dates)
        end
    end
  end

  # --- Private ---

  # Resolve timezone using fallback chain:
  # 1. city.timezone (precomputed)
  # 2. TimezoneMapper from country code
  # 3. nil (skip)
  defp resolve_timezone(event) do
    city = event.venue.city_ref

    cond do
      is_binary(city.timezone) and city.timezone != "" ->
        city.timezone

      match?(%{country: %{code: code}} when is_binary(code), city) ->
        tz = TimezoneMapper.get_timezone_for_country(city.country.code)
        if tz != "Etc/UTC", do: tz, else: nil

      true ->
        nil
    end
  end

  defp do_check(event, timezone, dates) do
    # For single-occurrence: shift starts_at to local, compare with stored date/time
    # For multi-occurrence: shift starts_at to local, compare with earliest stored date/time
    target_entry =
      if length(dates) == 1 do
        hd(dates)
      else
        Enum.min_by(dates, fn d -> {d["date"] || "", d["time"] || "00:00"} end)
      end

    case DateTime.shift_zone(event.starts_at, timezone) do
      {:ok, local_dt} ->
        expected_date = local_dt |> DateTime.to_date() |> Date.to_string()

        expected_time =
          local_dt |> DateTime.to_time() |> Time.to_string() |> String.slice(0..4)

        occurrence_date = target_entry["date"]
        occurrence_time = target_entry["time"]

        date_match = expected_date == occurrence_date
        time_match = is_nil(occurrence_time) or expected_time == occurrence_time

        status =
          cond do
            date_match and time_match -> :ok
            not date_match and not time_match -> :both_mismatch
            not date_match -> :date_mismatch
            true -> :time_mismatch
          end

        {:ok,
         %{
           event_id: event.id,
           title: event.title,
           starts_at: event.starts_at,
           timezone: timezone,
           expected_date: expected_date,
           expected_time: expected_time,
           occurrence_date: occurrence_date,
           occurrence_time: occurrence_time,
           status: status
         }}

      {:error, _reason} ->
        :skip
    end
  end

  defp fetch_events(source_slug, from_datetime, limit) do
    events = do_fetch_events(source_slug, from_datetime, limit)

    # Fallback: try underscore variant if no events found (handles week_pl edge case)
    if Enum.empty?(events) do
      underscore_slug = String.replace(source_slug, "-", "_")

      if underscore_slug != source_slug do
        do_fetch_events(underscore_slug, from_datetime, limit)
      else
        []
      end
    else
      events
    end
  end

  defp do_fetch_events(source_slug, from_datetime, limit) do
    from(pe in PublicEvent,
      join: v in Venue,
      on: pe.venue_id == v.id,
      join: c in City,
      on: v.city_id == c.id,
      left_join: co in Country,
      on: c.country_id == co.id,
      join: pes in PublicEventSource,
      on: pes.event_id == pe.id,
      join: s in Source,
      on: s.id == pes.source_id,
      where: s.slug == ^source_slug,
      where: pe.starts_at >= ^from_datetime,
      where: not is_nil(pe.occurrences),
      preload: [venue: {v, city_ref: {c, country: co}}],
      distinct: pe.id,
      limit: ^limit,
      order_by: [desc: pe.starts_at]
    )
    |> Repo.replica().all()
  end

  defp normalize_slug(slug) do
    String.replace(slug, "_", "-")
  end

  defp determine_source_timezone(events) do
    events
    |> Enum.find_value(fn event ->
      resolve_timezone(event)
    end)
    |> Kernel.||("unknown")
  end
end
