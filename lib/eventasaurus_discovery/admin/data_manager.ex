defmodule EventasaurusDiscovery.Admin.DataManager do
  @moduledoc """
  Manages data clearing operations for public events and related data.
  Provides safe, transaction-wrapped deletion with cascade handling.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource, PublicEventPerformer}
  alias EventasaurusDiscovery.PublicEvents.{PublicEventContainer, PublicEventContainerMembership}
  alias EventasaurusDiscovery.Categories.PublicEventCategory
  alias EventasaurusDiscovery.Sources.Source
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

      # 5. Clean up orphaned containers (containers with no events)
      container_count = clean_orphaned_containers()

      # 6. Optionally clear related Oban jobs
      oban_count =
        if clear_oban_jobs do
          clear_discovery_oban_jobs()
        else
          0
        end

      Logger.info(
        "Successfully cleared #{deleted_count} public events#{if container_count > 0, do: ", #{container_count} containers", else: ""}#{if oban_count > 0, do: ", and #{oban_count} Oban jobs", else: ""}"
      )

      deleted_count
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to clear public events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears public events by source.

  For events that have ONLY this source, deletes the entire event and related records.
  For events that have multiple sources, only removes the source association.
  """
  def clear_by_source(source_name) when is_binary(source_name) do
    Logger.info("Starting clear of public events from source: #{source_name}")

    Repo.transaction(fn ->
      # First, get the source ID from the source name
      source = Repo.get_by(Source, name: source_name)

      if is_nil(source) do
        Logger.warning("Source not found: #{source_name}")
        0
      else
        # Get all event IDs for this source
        all_event_ids =
          from(pes in PublicEventSource,
            where: pes.source_id == ^source.id,
            select: pes.event_id
          )
          |> Repo.all()
          |> Enum.uniq()

        if Enum.empty?(all_event_ids) do
          0
        else
          # Find events that have ONLY this source (should be fully deleted)
          # These are events where the only source entry is for this source
          single_source_event_ids =
            from(pes in PublicEventSource,
              where: pes.event_id in ^all_event_ids,
              group_by: pes.event_id,
              having: count(pes.id) == 1,
              select: pes.event_id
            )
            |> Repo.all()

          # Events with multiple sources - only remove the source link
          multi_source_event_ids = all_event_ids -- single_source_event_ids

          # For multi-source events, just remove the source association
          {unlinked_count, _} =
            from(pes in PublicEventSource,
              where: pes.event_id in ^multi_source_event_ids and pes.source_id == ^source.id
            )
            |> Repo.delete_all()

          # For single-source events, delete everything
          # IMPORTANT: Delete events FIRST - the ON DELETE CASCADE foreign keys
          # will automatically delete related records (sources, performers, categories)
          # This avoids the prevent_last_source_deletion trigger blocking us
          deleted_count =
            if Enum.empty?(single_source_event_ids) do
              0
            else
              # Delete related records that don't have CASCADE (performers, categories)
              from(pep in PublicEventPerformer, where: pep.event_id in ^single_source_event_ids)
              |> Repo.delete_all()

              from(pec in PublicEventCategory, where: pec.event_id in ^single_source_event_ids)
              |> Repo.delete_all()

              # Delete events FIRST - ON DELETE CASCADE handles public_event_sources
              {count, _} =
                from(pe in PublicEvent, where: pe.id in ^single_source_event_ids)
                |> Repo.delete_all()

              count
            end

          # Clean up orphaned containers from this source
          container_count = clean_orphaned_containers_by_source(source.id)

          Logger.info(
            "Successfully cleared #{deleted_count} events, unlinked #{unlinked_count} multi-source events#{if container_count > 0, do: ", cleaned #{container_count} containers", else: ""} from source: #{source_name}"
          )

          deleted_count + unlinked_count
        end
      end
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to clear events by source: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears future public events by source (preserves historical events).
  """
  def clear_future_by_source(source_name) when is_binary(source_name) do
    now = DateTime.utc_now()

    Logger.info(
      "Starting clear of future public events from source: #{source_name} from #{now} onwards"
    )

    Repo.transaction(fn ->
      # First, get the source ID from the source name
      source = Repo.get_by(Source, name: source_name)

      if is_nil(source) do
        Logger.warning("Source not found: #{source_name}")
        0
      else
        # Get all future event IDs for this source
        event_ids =
          from(pes in PublicEventSource,
            join: pe in PublicEvent,
            on: pe.id == pes.event_id,
            where: pes.source_id == ^source.id and pe.starts_at >= ^now,
            select: pes.event_id
          )
          |> Repo.all()
          |> Enum.uniq()

        if Enum.empty?(event_ids) do
          0
        else
          # Delete related records (performers, categories)
          from(pep in PublicEventPerformer, where: pep.event_id in ^event_ids)
          |> Repo.delete_all()

          from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
          |> Repo.delete_all()

          # Delete events FIRST - ON DELETE CASCADE handles public_event_sources
          # This avoids the prevent_last_source_deletion trigger blocking us
          {deleted_count, _} =
            from(pe in PublicEvent, where: pe.id in ^event_ids)
            |> Repo.delete_all()

          # Clean up orphaned containers from this source
          container_count = clean_orphaned_containers_by_source(source.id)

          Logger.info(
            "Successfully cleared #{deleted_count} future events#{if container_count > 0, do: " and #{container_count} containers", else: ""} from source: #{source_name}"
          )

          deleted_count
        end
      end
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to clear future events by source: #{inspect(reason)}")
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
          join: v in EventasaurusApp.Venues.Venue,
          on: v.id == pe.venue_id,
          where: v.city_id == ^city_id,
          select: pe.id
        )
        |> Repo.all()

      if Enum.empty?(event_ids) do
        0
      else
        # Delete related records (performers, categories)
        from(pep in PublicEventPerformer, where: pep.event_id in ^event_ids)
        |> Repo.delete_all()

        from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
        |> Repo.delete_all()

        # Delete events FIRST - ON DELETE CASCADE handles public_event_sources
        # This avoids the prevent_last_source_deletion trigger blocking us
        {deleted_count, _} =
          from(pe in PublicEvent, where: pe.id in ^event_ids)
          |> Repo.delete_all()

        # Clean up orphaned containers
        container_count = clean_orphaned_containers()

        Logger.info(
          "Successfully cleared #{deleted_count} events#{if container_count > 0, do: " and #{container_count} containers", else: ""} for city_id: #{city_id}"
        )

        deleted_count
      end
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

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
        # Delete related records (performers, categories)
        from(pep in PublicEventPerformer, where: pep.event_id in ^event_ids)
        |> Repo.delete_all()

        from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
        |> Repo.delete_all()

        # Delete events FIRST - ON DELETE CASCADE handles public_event_sources
        # This avoids the prevent_last_source_deletion trigger blocking us
        {deleted_count, _} =
          from(pe in PublicEvent, where: pe.id in ^event_ids)
          |> Repo.delete_all()

        Logger.info("Successfully cleared #{deleted_count} events in date range")
        deleted_count
      end
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to clear events by date range: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears all future public events (events starting from now onwards).
  Preserves historical events that have already occurred.
  Options:
    - clear_oban_jobs: boolean - Also clear related Oban jobs (default: false)
  Returns {:ok, count} with the number of events deleted, or {:error, reason}.
  """
  def clear_future_public_events(opts \\ []) do
    clear_oban_jobs = Keyword.get(opts, :clear_oban_jobs, false)
    now = DateTime.utc_now()

    Logger.info(
      "Starting clear of future public event data from #{now} onwards (clear_oban_jobs: #{clear_oban_jobs})"
    )

    Repo.transaction(fn ->
      # Get all future event IDs
      event_ids =
        from(pe in PublicEvent,
          where: pe.starts_at >= ^now,
          select: pe.id
        )
        |> Repo.all()

      if Enum.empty?(event_ids) do
        0
      else
        # Delete related records (performers, categories)
        from(pep in PublicEventPerformer, where: pep.event_id in ^event_ids)
        |> Repo.delete_all()

        from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
        |> Repo.delete_all()

        # Delete events FIRST - ON DELETE CASCADE handles public_event_sources
        # This avoids the prevent_last_source_deletion trigger blocking us
        {deleted_count, _} =
          from(pe in PublicEvent, where: pe.id in ^event_ids)
          |> Repo.delete_all()

        # Clean up orphaned containers
        container_count = clean_orphaned_containers()

        # Optionally clear related Oban jobs
        oban_count =
          if clear_oban_jobs do
            clear_discovery_oban_jobs()
          else
            0
          end

        Logger.info(
          "Successfully cleared #{deleted_count} future public events#{if container_count > 0, do: ", #{container_count} containers", else: ""}#{if oban_count > 0, do: ", and #{oban_count} Oban jobs", else: ""}"
        )

        deleted_count
      end
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to clear future public events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Clears future public events by city (preserves historical events).
  """
  def clear_future_by_city(city_id) when is_integer(city_id) do
    now = DateTime.utc_now()

    Logger.info(
      "Starting clear of future public events for city_id: #{city_id} from #{now} onwards"
    )

    Repo.transaction(fn ->
      # Get all future event IDs for this city
      event_ids =
        from(pe in PublicEvent,
          join: v in EventasaurusApp.Venues.Venue,
          on: v.id == pe.venue_id,
          where: v.city_id == ^city_id and pe.starts_at >= ^now,
          select: pe.id
        )
        |> Repo.all()

      if Enum.empty?(event_ids) do
        0
      else
        # Delete related records (performers, categories)
        from(pep in PublicEventPerformer, where: pep.event_id in ^event_ids)
        |> Repo.delete_all()

        from(pec in PublicEventCategory, where: pec.event_id in ^event_ids)
        |> Repo.delete_all()

        # Delete events FIRST - ON DELETE CASCADE handles public_event_sources
        # This avoids the prevent_last_source_deletion trigger blocking us
        {deleted_count, _} =
          from(pe in PublicEvent, where: pe.id in ^event_ids)
          |> Repo.delete_all()

        # Clean up orphaned containers
        container_count = clean_orphaned_containers()

        Logger.info(
          "Successfully cleared #{deleted_count} future events#{if container_count > 0, do: " and #{container_count} containers", else: ""} for city_id: #{city_id}"
        )

        deleted_count
      end
    end)
    |> case do
      {:ok, count} ->
        {:ok, count}

      {:error, reason} ->
        Logger.error("Failed to clear future events by city: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp clear_discovery_oban_jobs do
    # Clear all discovery-related Oban jobs to allow re-importing
    # Include ALL states to ensure jobs can be re-queued in production
    {count, _} =
      Repo.delete_all(
        from(j in Oban.Job,
          where:
            j.worker in [
              "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob",
              "EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob",
              "EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob",
              "EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob",
              "EventasaurusDiscovery.Scraping.Scrapers.Ticketmaster.Jobs.EventDetailJob",
              "EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob",
              "EventasaurusDiscovery.Admin.DiscoverySyncJob"
            ] and
              j.state in [
                "completed",
                "discarded",
                "cancelled",
                "retryable",
                "scheduled",
                "available",
                "executing"
              ]
        )
      )

    Logger.info("Cleared #{count} discovery Oban jobs (all states)")
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

  defp clean_orphaned_containers do
    # Query for containers with no remaining memberships
    orphaned_container_ids =
      from(c in PublicEventContainer,
        left_join: m in PublicEventContainerMembership,
        on: m.container_id == c.id,
        group_by: c.id,
        having: count(m.id) == 0,
        select: c.id
      )
      |> Repo.all()

    if Enum.empty?(orphaned_container_ids) do
      0
    else
      {deleted_count, _} =
        from(c in PublicEventContainer, where: c.id in ^orphaned_container_ids)
        |> Repo.delete_all()

      Logger.info("Cleaned up #{deleted_count} orphaned containers")
      deleted_count
    end
  end

  defp clean_orphaned_containers_by_source(source_id) do
    # Query for containers from this source with no remaining memberships
    orphaned_container_ids =
      from(c in PublicEventContainer,
        left_join: m in PublicEventContainerMembership,
        on: m.container_id == c.id,
        where: c.source_id == ^source_id,
        group_by: c.id,
        having: count(m.id) == 0,
        select: c.id
      )
      |> Repo.all()

    if Enum.empty?(orphaned_container_ids) do
      0
    else
      {deleted_count, _} =
        from(c in PublicEventContainer, where: c.id in ^orphaned_container_ids)
        |> Repo.delete_all()

      Logger.info("Cleaned up #{deleted_count} orphaned containers from source_id: #{source_id}")

      deleted_count
    end
  end

  defp count_orphaned_containers do
    from(c in PublicEventContainer,
      left_join: m in PublicEventContainerMembership,
      on: m.container_id == c.id,
      where: is_nil(m.id)
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_orphaned_containers_by_source(source_id) do
    from(c in PublicEventContainer,
      left_join: m in PublicEventContainerMembership,
      on: m.container_id == c.id,
      where: c.source_id == ^source_id,
      where: is_nil(m.id)
    )
    |> Repo.aggregate(:count, :id)
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
          performers: Repo.aggregate(PublicEventPerformer, :count, :id),
          containers: count_orphaned_containers()
        }

      "source:" <> source ->
        source_record = Repo.get_by(Source, name: source)

        event_ids =
          from(pes in PublicEventSource,
            where: pes.source == ^source,
            select: pes.event_id
          )
          |> Repo.all()
          |> Enum.uniq()

        container_count =
          if source_record do
            count_orphaned_containers_by_source(source_record.id)
          else
            0
          end

        %{
          events: length(event_ids),
          source: source,
          containers: container_count
        }

      "city:" <> city_id_str ->
        city_id = String.to_integer(city_id_str)

        %{
          events:
            Repo.aggregate(
              from(pe in PublicEvent,
                join: v in EventasaurusApp.Venues.Venue,
                on: v.id == pe.venue_id,
                where: v.city_id == ^city_id
              ),
              :count,
              :id
            ),
          city_id: city_id,
          containers: count_orphaned_containers()
        }

      _ ->
        %{events: 0, containers: 0}
    end
  end
end
