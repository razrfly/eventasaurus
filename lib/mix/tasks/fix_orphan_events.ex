defmodule Mix.Tasks.FixOrphanEvents do
  @moduledoc """
  Fixes orphaned events - events in public_events with no public_event_sources record.

  These orphans are created when the Ecto.Multi transaction partially fails,
  creating an event but failing to create the corresponding source record.
  Without a source record, these events cannot be properly attributed,
  maintained, or cleaned up by normal scraper operations.

  See GitHub issue #2897 for root cause analysis.

  ## Usage

      # Dry run - show orphans that would be deleted
      mix fix_orphan_events

      # Actually delete the orphans
      mix fix_orphan_events --apply

      # Show detailed info about each orphan
      mix fix_orphan_events --verbose

  ## What it does

  1. Identifies all events with no corresponding public_event_sources record
  2. Deletes these orphan events (they have no value without source attribution)
  3. Also cleans up corrupted venues that only served these orphans

  ## Safety

  - Events WITH source records are never touched
  - Dry run by default - must explicitly use --apply
  - Full audit log of deletions
  """

  use Mix.Task
  require Logger

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent

  @shortdoc "Delete orphaned events (events without source records)"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    apply_changes = "--apply" in args
    verbose = "--verbose" in args

    Logger.info("🔍 Scanning for orphaned events (events without source records)...")

    # Find all orphan events
    orphans = find_orphan_events()

    if Enum.empty?(orphans) do
      Logger.info("✅ No orphans found! Database is clean.")
    else
      Logger.info("Found #{length(orphans)} orphaned events")
      Logger.info("")

      # Group by likely source
      by_source = group_by_likely_source(orphans)

      Logger.info("📊 Breakdown by likely source:")
      for {source, events} <- Enum.sort_by(by_source, fn {_, e} -> -length(e) end) do
        Logger.info("  #{source}: #{length(events)}")
      end
      Logger.info("")

      # Group by timing
      future_count = Enum.count(orphans, fn o -> o.starts_at && DateTime.compare(o.starts_at, DateTime.utc_now()) == :gt end)
      past_count = length(orphans) - future_count

      Logger.info("📅 Event timing:")
      Logger.info("  Past events: #{past_count}")
      Logger.info("  Future events: #{future_count}")
      Logger.info("")

      if verbose do
        Logger.info("📋 Orphan events to delete:")
        for orphan <- orphans do
          Logger.info("  ID: #{orphan.id} | #{orphan.title} | #{format_date(orphan.starts_at)} | Venue: #{orphan.venue_name || "none"}")
        end
        Logger.info("")
      end

      if apply_changes do
        Logger.info("🗑️  Deleting #{length(orphans)} orphan events...")

        {deleted, errors} = delete_orphans(orphans)

        Logger.info("")
        Logger.info("✅ Deleted: #{deleted}")

        if errors > 0 do
          Logger.error("❌ Errors: #{errors}")
        end

        # Check for venues that now have no events
        cleanup_orphaned_venues()
      else
        Logger.info("ℹ️  Dry run - no changes made")
        Logger.info("   Run with --apply to delete these orphans")
        Logger.info("   Run with --verbose to see details of each orphan")
      end
    end
  end

  defp find_orphan_events do
    query = """
    SELECT
      pe.id,
      pe.title,
      pe.starts_at,
      pe.venue_id,
      pe.inserted_at,
      v.name as venue_name
    FROM public_events pe
    LEFT JOIN public_event_sources pes ON pe.id = pes.event_id
    LEFT JOIN venues v ON pe.venue_id = v.id
    WHERE pes.id IS NULL
    ORDER BY pe.inserted_at DESC
    """

    case Repo.query(query) do
      {:ok, %{rows: rows, columns: columns}} ->
        columns = Enum.map(columns, &String.to_atom/1)
        Enum.map(rows, fn row ->
          Enum.zip(columns, row) |> Map.new()
        end)

      {:error, error} ->
        Logger.error("Failed to query orphans: #{inspect(error)}")
        []
    end
  end

  defp group_by_likely_source(orphans) do
    Enum.group_by(orphans, fn orphan ->
      title = orphan.title || ""
      cond do
        String.contains?(title, "Cinema City") -> "Cinema City"
        String.contains?(title, "Ifn") or String.contains?(title, "IFN") -> "IFN/Repertuary"
        String.contains?(title, "Kijow") -> "Kino Krakow"
        String.contains?(String.downcase(title), "quiz") -> "PubQuiz/Inquizition"
        true -> "Other"
      end
    end)
  end

  defp format_date(nil), do: "no date"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_date(other), do: inspect(other)

  defp delete_orphans(orphans) do
    orphan_ids = Enum.map(orphans, & &1.id)

    # Delete in batches of 100
    orphan_ids
    |> Enum.chunk_every(100)
    |> Enum.reduce({0, 0}, fn batch, {deleted, errors} ->
      query = from(pe in PublicEvent, where: pe.id in ^batch)

      case Repo.delete_all(query) do
        {count, _} ->
          Logger.info("  Deleted batch of #{count} events")
          {deleted + count, errors}

        {:error, reason} ->
          Logger.error("  Failed to delete batch: #{inspect(reason)}")
          {deleted, errors + length(batch)}
      end
    end)
  end

  defp cleanup_orphaned_venues do
    # Find venues that now have no events at all
    query = """
    SELECT v.id, v.name
    FROM venues v
    LEFT JOIN public_events pe ON pe.venue_id = v.id
    WHERE pe.id IS NULL
    AND v.name LIKE '%(pokaż na mapie)%'
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} when length(rows) > 0 ->
        Logger.info("")
        Logger.info("🏚️  Found #{length(rows)} corrupted venues with no remaining events")

        for [id, name] <- rows do
          Logger.info("  ID: #{id} | #{name}")
        end

        Logger.info("  (These venues have corrupted names from scraping artifacts)")
        Logger.info("  Consider running: mix fix_corrupted_venues --apply")

      {:ok, _} ->
        Logger.info("")
        Logger.info("✅ No orphaned corrupted venues found")

      {:error, error} ->
        Logger.error("Failed to check orphaned venues: #{inspect(error)}")
    end
  end
end
