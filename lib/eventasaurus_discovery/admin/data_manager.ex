defmodule EventasaurusDiscovery.Admin.DataManager do
  @moduledoc """
  Manages data clearing operations for public events and related data.
  Provides safe, transaction-wrapped deletion with cascade handling.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource, PublicEventPerformer}
  alias EventasaurusDiscovery.Categories.PublicEventCategory
  import Ecto.Query
  require Logger

  @doc """
  Clears all public event data and related records.
  Options:
    - clear_oban_jobs: boolean - Also clear related Oban jobs (default: false)
  Returns {:ok, count} with the number of events deleted, or {:error, reason}.
  """
  def clear_all_public_events(opts \\ []) do
    clear_oban_jobs = Keyword.get(opts, :clear_oban_jobs, false)
    Logger.info("Starting clear of all public event data (clear_oban_jobs: #{clear_oban_jobs})")

    Repo.transaction(fn ->
      # Count events before deletion (unused but kept for potential future use)
      _count = Repo.aggregate(PublicEvent, :count, :id)

      # Delete in correct order to respect foreign key constraints
      # 1. Delete junction tables first
      Repo.delete_all(PublicEventPerformer)
      Repo.delete_all(PublicEventCategory)
      Repo.delete_all(PublicEventSource)

      # 2. Delete main events table
      {deleted_count, _} = Repo.delete_all(PublicEvent)

      # 3. Optionally clean up orphaned categories (only if not used by user events)
      clean_orphaned_categories()

      # 4. Optionally clean up sources (only if not used elsewhere)
      clean_orphaned_sources()

      # 5. Optionally clear related Oban jobs
      oban_count = if clear_oban_jobs do
        clear_discovery_oban_jobs()
      else
        0
      end

      Logger.info("Successfully cleared #{deleted_count} public events#{if oban_count > 0, do: " and #{oban_count} Oban jobs", else: ""}")
      deleted_count
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} ->
        Logger.error("Failed to clear public events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears public events by source.
  """
  def clear_by_source(source_name) when is_binary(source_name) do
    Logger.info("Starting clear of public events from source: #{source_name}")

    Repo.transaction(fn ->
      # Get all event IDs for this source
      event_ids =
        from(pes in PublicEventSource,
          where: pes.source == ^source_name,
          select: pes.public_event_id
        )
        |> Repo.all()
        |> Enum.uniq()

      if Enum.empty?(event_ids) do
        0
      else
        # Delete related records
        from(pep in PublicEventPerformer, where: pep.public_event_id in ^event_ids)
        |> Repo.delete_all()

        from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
        |> Repo.delete_all()

        from(pes in PublicEventSource, where: pes.public_event_id in ^event_ids)
        |> Repo.delete_all()

        # Delete events
        {deleted_count, _} =
          from(pe in PublicEvent, where: pe.id in ^event_ids)
          |> Repo.delete_all()

        Logger.info("Successfully cleared #{deleted_count} events from source: #{source_name}")
        deleted_count
      end
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} ->
        Logger.error("Failed to clear events by source: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears public events by city.
  """
  def clear_by_city(city_id) when is_integer(city_id) do
    Logger.info("Starting clear of public events for city_id: #{city_id}")

    Repo.transaction(fn ->
      # Get all event IDs for this city (through venues)
      event_ids =
        from(pe in PublicEvent,
          join: v in EventasaurusApp.Venues.Venue, on: v.id == pe.venue_id,
          where: v.city_id == ^city_id,
          select: pe.id
        )
        |> Repo.all()

      if Enum.empty?(event_ids) do
        0
      else
        # Delete related records
        from(pep in PublicEventPerformer, where: pep.public_event_id in ^event_ids)
        |> Repo.delete_all()

        from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
        |> Repo.delete_all()

        from(pes in PublicEventSource, where: pes.public_event_id in ^event_ids)
        |> Repo.delete_all()

        # Delete events
        {deleted_count, _} =
          from(pe in PublicEvent, where: pe.id in ^event_ids)
          |> Repo.delete_all()

        Logger.info("Successfully cleared #{deleted_count} events for city_id: #{city_id}")
        deleted_count
      end
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} ->
        Logger.error("Failed to clear events by city: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears public events by date range.
  """
  def clear_by_date_range(start_date, end_date) do
    Logger.info("Starting clear of public events from #{start_date} to #{end_date}")

    Repo.transaction(fn ->
      # Get all event IDs in date range
      event_ids =
        from(pe in PublicEvent,
          where: pe.start_datetime >= ^start_date and pe.start_datetime <= ^end_date,
          select: pe.id
        )
        |> Repo.all()

      if Enum.empty?(event_ids) do
        0
      else
        # Delete related records
        from(pep in PublicEventPerformer, where: pep.public_event_id in ^event_ids)
        |> Repo.delete_all()

        from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
        |> Repo.delete_all()

        from(pes in PublicEventSource, where: pes.public_event_id in ^event_ids)
        |> Repo.delete_all()

        # Delete events
        {deleted_count, _} =
          from(pe in PublicEvent, where: pe.id in ^event_ids)
          |> Repo.delete_all()

        Logger.info("Successfully cleared #{deleted_count} events in date range")
        deleted_count
      end
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      {:error, reason} ->
        Logger.error("Failed to clear events by date range: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp clear_discovery_oban_jobs do
    # Clear all completed discovery-related Oban jobs to allow re-importing
    {count, _} = Repo.delete_all(
      from j in "oban_jobs",
        where: j.worker in [
          "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
          "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
          "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
          "EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Jobs.EventDetailJob",
          "EventasaurusDiscovery.Scraping.Scrapers.Ticketmaster.Jobs.EventDetailJob",
          "EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob",
          "EventasaurusDiscovery.Admin.DiscoverySyncJob"
        ] and j.state in ["completed", "discarded", "cancelled"]
    )

    Logger.info("Cleared #{count} completed discovery Oban jobs")
    count
  end

  defp clean_orphaned_categories do
    # Only delete categories that are:
    # 1. Not referenced by any public events
    # 2. Not referenced by any user events (if such a table exists)
    # 3. Marked as discovery-specific (if we add such a flag)

    # For now, we'll be conservative and not delete categories automatically
    # This can be expanded later based on requirements
    :ok
  end

  defp clean_orphaned_sources do
    # Only delete sources that are not referenced by any public events
    # For now, we keep all sources as they're configuration data
    :ok
  end

  @doc """
  Gets statistics about data that would be cleared.
  Useful for showing confirmation dialogs.
  """
  def get_clear_statistics(target) do
    case target do
      "all" ->
        %{
          events: Repo.aggregate(PublicEvent, :count, :id),
          sources: Repo.aggregate(PublicEventSource, :count, :id),
          categories: Repo.aggregate(PublicEventCategory, :count, :id),
          performers: Repo.aggregate(PublicEventPerformer, :count, :id)
        }

      "source:" <> source ->
        event_ids =
          from(pes in PublicEventSource,
            where: pes.source == ^source,
            select: pes.public_event_id
          )
          |> Repo.all()
          |> Enum.uniq()

        %{
          events: length(event_ids),
          source: source
        }

      "city:" <> city_id_str ->
        city_id = String.to_integer(city_id_str)

        %{
          events: Repo.aggregate(
            from(pe in PublicEvent,
              join: v in EventasaurusApp.Venues.Venue, on: v.id == pe.venue_id,
              where: v.city_id == ^city_id),
            :count,
            :id
          ),
          city_id: city_id
        }

      _ ->
        %{events: 0}
    end
  end
end