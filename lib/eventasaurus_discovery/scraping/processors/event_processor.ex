defmodule EventasaurusDiscovery.Scraping.Processors.EventProcessor do
  @moduledoc """
  Processes event data from various sources.

  Handles:
  - Creating or updating public events
  - Managing event sources with priority
  - Associating events with venues and performers
  - Deduplication based on external_id
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource, PublicEventPerformer}
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusDiscovery.Scraping.Processors.VenueProcessor
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer
  alias EventasaurusDiscovery.Services.CollisionDetector
  alias EventasaurusDiscovery.Services.RecurringEventUpdater
  alias EventasaurusDiscovery.Categories.CategoryExtractor
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Scraping.Processors.EventImageCaching
  alias Eventasaurus.Discovery.OccurrenceValidator
  alias EventasaurusWeb.Utils.TimezoneUtils
  alias EventasaurusDiscovery.Locations.City
  alias Ecto.Multi

  import Ecto.Query
  require Logger

  @doc """
  Marks an event as seen by updating last_seen_at timestamp.
  This MUST be called for every event, even if processing fails.

  Creates a minimal PublicEventSource record if one doesn't exist,
  or updates the last_seen_at timestamp if it does.

  This ensures failed events don't appear stale forever.
  """
  def mark_event_as_seen(external_id, source_id)
      when is_binary(external_id) and external_id != "" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %PublicEventSource{}
    |> PublicEventSource.changeset(%{
      external_id: external_id,
      source_id: source_id,
      last_seen_at: now,
      # Minimal required fields for initial insert
      inserted_at: now,
      updated_at: now
    })
    |> Repo.insert(
      on_conflict: {:replace, [:last_seen_at, :updated_at]},
      conflict_target: [:external_id, :source_id]
    )
  end

  def mark_event_as_seen(nil, _source_id), do: {:ok, :no_external_id}
  def mark_event_as_seen("", _source_id), do: {:ok, :no_external_id}

  @doc """
  Processes event data from a source.
  Creates or updates the event and manages source associations.

  ## Phase 2.3: Atomic Venue+Event Creation

  This function now uses Ecto.Multi to ensure venue and event creation are atomic.
  If event creation fails after venue is created, the entire transaction rolls back,
  preventing orphan venues (venues with no linked events).

  The transaction wraps:
  1. Venue creation/lookup (via VenueProcessor)
  2. Event creation/update
  3. Event source linking
  4. Performer, category, and movie associations

  All succeed together or none persist.
  """
  def process_event(event_data, source_id, source_priority \\ 10) do
    # Data is already cleaned at HTTP client level (single entry point validation)
    with {:ok, normalized} <- normalize_event_data(event_data) do
      # Phase 2.3: Wrap entire venue+event creation in atomic transaction
      # This prevents orphan venues when event creation fails
      process_event_atomically(normalized, source_id, source_priority)
    else
      {:error, reason} = error ->
        Logger.error("Failed to normalize event data: #{inspect(reason)}")
        error
    end
  end

  # Phase 2.3: Atomic venue+event creation using Ecto.Multi
  # Prevents orphan venues by ensuring venue and event are created together
  defp process_event_atomically(normalized, source_id, source_priority) do
    result =
      Multi.new()
      |> Multi.run(:venue, fn _repo, _changes ->
        process_venue(normalized, source_id)
      end)
      |> Multi.run(:event, fn _repo, %{venue: venue} ->
        # Inject venue timezone into normalized data so occurrence times are stored as local time
        timezone = resolve_venue_timezone(venue)
        data = if timezone, do: Map.put(normalized, :venue_timezone, timezone), else: normalized

        # find_or_create_event returns {:ok, event, action} but Ecto.Multi expects {:ok, value}
        # Wrap the result as {:ok, {event, action}} to satisfy Multi callback contract
        case find_or_create_event(data, venue, source_id) do
          {:ok, event, action} -> {:ok, {event, action}}
          {:error, _reason} = error -> error
        end
      end)
      |> Multi.run(:event_source, fn _repo, %{event: {event, action}} ->
        maybe_update_event_source(event, source_id, source_priority, normalized, action)
      end)
      |> Multi.run(:performers, fn _repo, %{event: {event, _action}} ->
        process_performers(event, normalized)
      end)
      |> Multi.run(:categories, fn _repo, %{event: {event, _action}} ->
        process_categories(event, normalized, source_id)
      end)
      |> Multi.run(:movies, fn _repo, %{event: {event, _action}} ->
        process_movies(event, normalized)
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{event: {event, _action}}} ->
        {:ok, Repo.preload(event, [:venue, :performers, :categories, :movies])}

      {:error, step, reason, _changes} ->
        Logger.error("Failed to process event at step #{step}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_update_event_source(event, source_id, source_priority, normalized, _action) do
    # IMPORTANT: Always update event source, even for consolidated events
    # This ensures last_seen_at is updated so freshness checking works correctly
    # Consolidated events still need to track when they were last seen from each source
    update_event_source(event, source_id, source_priority, normalized)
  end

  @doc """
  Finds an existing event by external_id and source.
  """
  def find_existing_event(external_id, source_id) do
    from(pe in PublicEvent,
      join: pes in PublicEventSource,
      on: pes.event_id == pe.id,
      where: pes.external_id == ^external_id and pes.source_id == ^source_id,
      limit: 1
    )
    |> Repo.one()
  end

  defp normalize_event_data(data) do
    normalized = %{
      external_id: data[:external_id] || data["external_id"],
      title: Normalizer.normalize_text(data[:title] || data["title"]),
      title_translations: data[:title_translations] || data["title_translations"],
      description_translations:
        data[:description_translations] || data["description_translations"],
      start_at:
        parse_datetime(
          data[:start_at] || data["start_at"] || data[:starts_at] || data["starts_at"]
        ),
      ends_at: parse_datetime(data[:ends_at] || data["ends_at"]),
      venue_data: data[:venue_data] || data["venue_data"],
      performer_names: data[:performer_names] || data["performer_names"] || [],
      metadata: data[:metadata] || data["metadata"] || %{},
      source_url: data[:source_url] || data["source_url"],
      image_url: extract_primary_image_url(data),
      # Keep old category_id for backward compatibility
      category_id: data[:category_id] || data["category_id"],
      # Add raw data for category extraction
      raw_event_data: data[:raw_event_data] || data["raw_event_data"],
      # Add raw_data for debugging (RA, Bandsintown, Karnet pattern)
      raw_data: data[:raw_data] || data["raw_data"],
      # Karnet category
      category: data[:category] || data["category"],
      # Recurring event pattern (for weekly/monthly events like PubQuiz)
      recurrence_rule: data[:recurrence_rule] || data["recurrence_rule"],
      # Price data - now stored at source level
      min_price: data[:min_price] || data["min_price"],
      max_price: data[:max_price] || data["max_price"],
      currency: data[:currency] || data["currency"],
      is_free: data[:is_free] || data["is_free"],
      # Movie data for movie events (Repertuary, Cinema City)
      movie_id: data[:movie_id] || data["movie_id"],
      movie_data: data[:movie_data] || data["movie_data"],
      # Article data for article-based events (Sortiraparis)
      article_id: data[:article_id] || data["article_id"],
      # Event type for Sortiraparis (one_time, exhibition, recurring)
      event_type: normalize_event_type(data[:event_type] || data["event_type"])
    }

    cond do
      is_nil(normalized.title) ->
        {:error, "Event title is required"}

      is_nil(normalized.start_at) ->
        {:error, "Event start time is required"}

      true ->
        {:ok, normalized}
    end
  end

  defp normalize_event_type(nil), do: nil

  defp normalize_event_type(val) when is_atom(val) do
    if val in [:one_time, :exhibition, :recurring], do: val, else: nil
  end

  defp normalize_event_type(val) when is_binary(val) do
    case String.downcase(String.trim(val)) do
      "one_time" -> :one_time
      "one-time" -> :one_time
      "exhibition" -> :exhibition
      "recurring" -> :recurring
      _ -> nil
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp process_venue(%{venue_data: nil}, _source_id) do
    # Public events from scrapers MUST have venues
    {:error, "Public events must have venue data for proper location tracking"}
  end

  defp process_venue(%{venue_data: venue_data}, source_id) do
    # Get source name to pass as source_scraper for proper tracking
    source = Repo.get(Source, source_id)
    source_name = if source, do: source.name, else: nil

    # Phase 2.3: Use process_venue_in_transaction when called from within Ecto.Multi
    # This allows the outer Multi transaction to control rollback behavior
    VenueProcessor.process_venue_in_transaction(venue_data, "scraper", source_name)
  end

  defp find_or_create_event(data, venue, source_id) do
    slug = Normalizer.create_slug("#{data.title} #{format_date(data.start_at)}")

    Logger.info("""
    🔎 Processing event for collision detection:
    Title: #{data.title}
    External ID: #{data.external_id}
    Source ID: #{source_id}
    Start at: #{data.start_at}
    Venue: #{if venue, do: "#{venue.name} (ID: #{venue.id})", else: "None"}
    Movie ID: #{data[:movie_id] || "None"}
    """)

    # Phase 2.3: When called from within Ecto.Multi transaction, we acquire
    # the advisory lock directly without creating a nested transaction.
    # The advisory lock will be released when the outer Multi transaction commits/rolls back.
    acquire_advisory_lock(venue, data.title)
    do_find_or_create_event(data, venue, source_id, slug)
  end

  # Acquire advisory lock without creating a nested transaction
  # Phase 2.3: This supports atomic venue+event creation via Ecto.Multi
  defp acquire_advisory_lock(venue, title) do
    lock_key = generate_event_lock_key(venue, title)
    Logger.debug("🔒 Acquiring advisory lock for key: #{lock_key}")

    # Acquire transaction-scoped advisory lock
    # This lock is automatically released when the transaction completes
    # Works within Ecto.Multi's outer transaction
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
    Logger.debug("✅ Advisory lock acquired")
  end

  # Generate a stable lock key from venue and normalized title
  # Returns a 64-bit integer for use with PostgreSQL advisory locks
  defp generate_event_lock_key(venue, title) do
    # Normalize title the same way we do for matching
    normalized_title = normalize_for_matching(title)

    # Create lock key from venue_id + normalized_title
    # Use :erlang.phash2 to create a stable 64-bit integer hash
    venue_id = if venue, do: venue.id, else: 0
    :erlang.phash2({venue_id, normalized_title}, 4_294_967_296)
  end

  defp do_find_or_create_event(data, venue, source_id, slug) do
    # First check if we have this event from this source
    existing_from_source = find_existing_event(data.external_id, source_id)

    # Always check for recurring pattern first, regardless of whether event exists
    Logger.info("🔄 Checking for recurring event pattern...")

    recurring_parent =
      find_recurring_parent(
        data.title,
        venue,
        data.external_id,
        source_id,
        data[:movie_id],
        data[:article_id],
        data[:event_type]
      )

    # Check if this is a movie event - movie events have movie_id in the data
    movie_id = data[:movie_id] || data["movie_id"]

    case {existing_from_source, recurring_parent} do
      # No existing event and no recurring parent - check for collision then create new
      {nil, nil} ->
        # CRITICAL FIX: Movie events should NOT use generic collision detection!
        # The collision detector only checks venue + time window, which means different
        # movies at the same cinema within 4 hours would incorrectly be merged.
        # Movie events should ONLY consolidate through find_movie_event_parent which
        # properly matches by movie_id in the event_movies table.
        if movie_id do
          Logger.info(
            "🎬 Movie event (movie_id: #{movie_id}) - skipping collision detection, creating new event"
          )

          result = create_event(data, venue, slug)

          case result do
            {:ok, event} -> {:ok, event, :created}
            error -> error
          end
        else
          Logger.info("📝 No existing event or recurring parent, checking for similar events...")

          case find_similar_event(data.title, data.start_at, venue) do
            nil ->
              Logger.info("✨ Creating new event")
              result = create_event(data, venue, slug)

              case result do
                {:ok, event} -> {:ok, event, :created}
                error -> error
              end

            existing ->
              Logger.info("🔗 Found similar event ##{existing.id} at same time, linking to it")
              {:ok, existing, :linked}
          end
        end

      # Existing event but found a recurring parent - need to consolidate
      {existing, parent} when existing != nil and parent != nil and existing.id != parent.id ->
        Logger.info(
          "🔄 Found recurring parent ##{parent.id} for existing event ##{existing.id}, consolidating..."
        )

        enriched_data = Map.put(data, :source_id, source_id)
        result = consolidate_into_parent(existing, parent, enriched_data)

        case result do
          {:ok, event} -> {:ok, event, :consolidated}
          error -> error
        end

      # Existing event IS the recurring parent - just add occurrence
      {existing, parent} when existing != nil and parent != nil and existing.id == parent.id ->
        Logger.info("📅 Event ##{existing.id} is already the recurring parent, adding occurrence")

        case add_occurrence_to_event(existing, data) do
          {:ok, updated} -> {:ok, updated, :updated}
          error -> error
        end

      # No existing event but found recurring parent - add to it
      {nil, parent} when parent != nil ->
        Logger.info("📅 Found recurring parent ##{parent.id}, adding occurrence")
        enriched_data = Map.put(data, :source_id, source_id)

        with {:ok, updated} <- add_occurrence_to_event(parent, enriched_data),
             {:ok, _source} <- create_occurrence_source_record(parent, enriched_data) do
          {:ok, updated, :consolidated}
        else
          error -> error
        end

      # Existing event, no recurring parent - just update
      {existing, nil} when existing != nil ->
        Logger.info("📌 Found existing event ##{existing.id} from same source, updating")
        result = maybe_update_event(existing, data, venue)

        case result do
          {:ok, event} -> {:ok, event, :updated}
          error -> error
        end
    end
  end

  defp find_similar_event(title, start_at, venue) do
    # Delegate to shared CollisionDetector service
    CollisionDetector.find_similar_event(venue, start_at, title)
  end

  defp create_event(data, venue, slug) do
    # Public events MUST have venues
    unless venue do
      raise ArgumentError,
            "Cannot create public event without venue. All public events require venue for location tracking and collision detection."
    end

    attrs = %{
      title: data.title,
      title_translations: data.title_translations,
      slug: slug,
      venue_id: venue.id,
      city_id: venue.city_id,
      # Note: normalized data uses start_at, schema uses starts_at
      starts_at: data.start_at,
      ends_at: data.ends_at,
      # Remove external_id and metadata from public_events
      # These will be stored only in public_event_sources
      category_id: data.category_id,
      # CRITICAL FIX: Always initialize occurrences for new events
      occurrences: initialize_occurrence_with_source(data)
    }

    %PublicEvent{}
    |> PublicEvent.changeset(attrs)
    |> Repo.insert()
  end

  defp initialize_occurrence_with_source(data) do
    # Get occurrence_type from metadata first, then fall back to detection logic
    occurrence_type = get_occurrence_type(data)

    # Validate the occurrence type using OccurrenceValidator
    case OccurrenceValidator.validate_type(occurrence_type) do
      {:ok, validated_type} ->
        build_occurrence_structure(validated_type, data)

      {:error, reason} ->
        Logger.warning(
          "[EventProcessor] Invalid occurrence type: #{reason}. Defaulting to 'explicit'"
        )

        build_occurrence_structure("explicit", data)
    end
  end

  # Get occurrence_type from metadata or detect from data
  defp get_occurrence_type(data) do
    # DEBUG: Log recurrence_rule presence for Geeks Who Drink debugging
    if data[:recurrence_rule] do
      Logger.debug("""
      ✅ [EventProcessor] Detected recurrence_rule, will use pattern type:
      - recurrence_rule: #{inspect(data.recurrence_rule)}
      """)
    end

    cond do
      # Check event_type first (Sortiraparis uses :exhibition, :recurring, :one_time)
      data.event_type == :exhibition ->
        "exhibition"

      data.event_type == :recurring ->
        "recurring"

      # Check metadata for occurrence_type (Sortiraparis legacy)
      data.metadata && data.metadata["occurrence_type"] ->
        data.metadata["occurrence_type"]

      # Check for recurrence_rule (pattern type)
      data.recurrence_rule ->
        Logger.info("[EventProcessor] Using pattern-type occurrence for recurring event")
        "pattern"

      # Default to explicit for one-time events
      true ->
        Logger.debug("[EventProcessor] No recurrence_rule found, using explicit type")
        "explicit"
    end
  end

  # Build occurrence structure based on validated type
  defp build_occurrence_structure("pattern", data) do
    %{
      "type" => "pattern",
      "pattern" => data.recurrence_rule
    }
  end

  defp build_occurrence_structure("exhibition", data) do
    timezone = extract_timezone(data) || "Etc/UTC"

    date_entry = %{
      "date" => format_date_only(data.start_at, timezone),
      "time" => format_time_only(data.start_at, data),
      "external_id" => data.external_id
    }

    # Add end_date for exhibitions if available
    date_entry =
      if data.ends_at do
        Map.put(date_entry, "end_date", format_date_only(data.ends_at, timezone))
      else
        date_entry
      end

    # Add source_id if available
    date_entry =
      if data[:source_id] || Map.get(data, :source_id) do
        Map.put(date_entry, "source_id", data[:source_id] || Map.get(data, :source_id))
      else
        date_entry
      end

    # Add label from event title
    date_entry =
      if data.title && String.trim(data.title) != "" do
        Map.put(date_entry, "label", data.title)
      else
        date_entry
      end

    %{
      "type" => "exhibition",
      "dates" => [date_entry]
    }
  end

  defp build_occurrence_structure("recurring", data) do
    timezone = extract_timezone(data) || "Etc/UTC"

    date_entry = %{
      "date" => format_date_only(data.start_at, timezone),
      "time" => format_time_only(data.start_at, data),
      "external_id" => data.external_id
    }

    # Add source_id if available
    date_entry =
      if data[:source_id] || Map.get(data, :source_id) do
        Map.put(date_entry, "source_id", data[:source_id] || Map.get(data, :source_id))
      else
        date_entry
      end

    # Add label from event title
    date_entry =
      if data.title && String.trim(data.title) != "" do
        Map.put(date_entry, "label", data.title)
      else
        date_entry
      end

    # Get pattern description from metadata if available
    pattern_description =
      if data.metadata && data.metadata["recurrence_pattern"] do
        data.metadata["recurrence_pattern"]
      else
        "Recurring event"
      end

    %{
      "type" => "recurring",
      "dates" => [date_entry],
      "pattern_description" => pattern_description
    }
  end

  defp build_occurrence_structure("explicit", data) do
    timezone = extract_timezone(data) || "Etc/UTC"

    date_entry = %{
      "date" => format_date_only(data.start_at, timezone),
      "time" => format_time_only(data.start_at, data),
      "external_id" => data.external_id
    }

    # Add source_id if available
    date_entry =
      if data[:source_id] || Map.get(data, :source_id) do
        Map.put(date_entry, "source_id", data[:source_id] || Map.get(data, :source_id))
      else
        date_entry
      end

    # Add label from event title to distinguish ticket types
    date_entry =
      if data.title && String.trim(data.title) != "" do
        Map.put(date_entry, "label", data.title)
      else
        date_entry
      end

    %{
      "type" => "explicit",
      "dates" => [date_entry]
    }
  end

  defp maybe_update_event(event, data, venue) do
    updates = []

    # Only update if we have better data
    # Note: description is now stored in public_event_sources, not public_events

    updates =
      if is_nil(event.venue_id) && venue do
        [{:venue_id, venue.id}, {:city_id, venue.city_id} | updates]
      else
        updates
      end

    updates =
      if is_nil(event.ends_at) && data.ends_at do
        [{:ends_at, data.ends_at} | updates]
      else
        updates
      end

    updates =
      if is_nil(event.category_id) && data.category_id do
        [{:category_id, data.category_id} | updates]
      else
        updates
      end

    # Update title_translations if provided and different from current
    updates =
      if data.title_translations && data.title_translations != event.title_translations do
        merged =
          (event.title_translations || %{})
          |> Map.merge(data.title_translations, fn _k, old, new ->
            if new in [nil, ""], do: old, else: new
          end)

        [{:title_translations, merged} | updates]
      else
        updates
      end

    # Note: metadata is now stored only in public_event_sources, not in public_events

    # Correct occurrence time for this event's matching date entry
    # Re-scraped data carries :venue_timezone — use it to store correct local time
    updates =
      if data.start_at && event.occurrences && event.occurrences["dates"] do
        timezone = extract_timezone(data) || "Etc/UTC"
        corrected_time = format_time_only(data.start_at, data)
        corrected_date = format_date_only(data.start_at, timezone)

        updated_dates =
          Enum.map(event.occurrences["dates"], fn date_entry ->
            if data.external_id not in [nil, ""] and
                 date_entry["external_id"] == data.external_id do
              date_entry
              |> Map.put("date", corrected_date)
              |> Map.put("time", corrected_time)
            else
              date_entry
            end
          end)

        if updated_dates != event.occurrences["dates"] do
          updated_occurrences = Map.put(event.occurrences, "dates", updated_dates)
          [{:occurrences, updated_occurrences} | updates]
        else
          updates
        end
      else
        updates
      end

    # Apply field updates if any
    event_result =
      if Enum.any?(updates) do
        event
        |> PublicEvent.changeset(Map.new(updates))
        |> Repo.update()
      else
        {:ok, event}
      end

    # After updating fields, check if recurring event needs date regeneration
    # This handles the case where pattern-based events have expired dates
    case event_result do
      {:ok, updated_event} ->
        # Regenerate dates if event is expired recurring pattern
        RecurringEventUpdater.maybe_regenerate_dates(updated_event)

      error ->
        error
    end
  end

  defp update_event_source(event, source_id, priority, data) do
    # CRITICAL FIX: Check for existing record by external_id FIRST (like Bandsintown does)
    # This prevents duplicates when scrapers run repeatedly

    # Normalize external_id to avoid empty string collisions
    ext_id =
      case data.external_id do
        nil ->
          nil

        id when is_binary(id) ->
          id = String.trim(id)
          if id == "", do: nil, else: id

        id ->
          id
      end

    existing_by_external =
      if ext_id do
        Repo.get_by(PublicEventSource,
          source_id: source_id,
          external_id: ext_id
        )
      else
        nil
      end

    # Store priority in metadata if provided
    base = data.metadata || %{}

    # DEBUG: Log what data fields we have
    Logger.debug("🔍 Metadata storage - data keys: #{inspect(Map.keys(data))}")
    Logger.debug("🔍 data.raw_data present: #{inspect(Map.has_key?(data, :raw_data))}")

    # CRITICAL FIX: Merge raw_data from transformer for debugging
    # This preserves the complete API/scraping response for analysis
    base =
      if data[:raw_data] || data["raw_data"] do
        raw = data[:raw_data] || data["raw_data"]
        Logger.debug("✅ Storing raw_data in metadata!")
        Map.put(base, "raw_data", raw)
      else
        Logger.debug("❌ No raw_data found in data")
        base
      end

    # Also support raw_event_data pattern (used by Ticketmaster)
    base =
      if data[:raw_event_data] || data["raw_event_data"] do
        raw = data[:raw_event_data] || data["raw_event_data"]
        Map.put(base, "raw_event_data", raw)
      else
        base
      end

    metadata =
      case priority do
        nil -> base
        p -> Map.put(base, "priority", p)
      end

    attrs = %{
      event_id: event.id,
      source_id: source_id,
      # Use normalized ID to avoid empty strings
      external_id: ext_id,
      source_url: data.source_url,
      last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: metadata,
      description_translations: data.description_translations,
      image_url: data.image_url,
      # Add price fields
      min_price: data[:min_price],
      max_price: data[:max_price],
      currency: data[:currency],
      is_free: data[:is_free] || false
    }

    case existing_by_external do
      # Found existing record with same external_id - update it
      %PublicEventSource{} = existing when existing.event_id != event.id ->
        Logger.info("""
        🔄 Updating event source link from event ##{existing.event_id} to ##{event.id}
        External ID: #{ext_id}
        Source ID: #{source_id}
        """)

        # Avoid unique constraint violation on [:event_id, :source_id]
        # Use query with limit since unique constraint was removed to support showtimes
        conflicting_by_event =
          from(pes in PublicEventSource,
            where: pes.event_id == ^event.id and pes.source_id == ^source_id,
            order_by: [desc: pes.last_seen_at],
            limit: 1
          )
          |> Repo.one()

        if conflicting_by_event do
          # Use transaction to atomically delete conflict and move the external record
          Multi.new()
          |> Multi.delete(:delete_conflict, conflicting_by_event)
          |> Multi.update(:move_external, PublicEventSource.changeset(existing, attrs))
          |> Repo.transaction()
          |> case do
            {:ok, %{move_external: moved}} -> {:ok, moved}
            {:error, _step, changeset, _} -> {:error, changeset}
          end
        else
          existing
          |> PublicEventSource.changeset(attrs)
          |> Repo.update()
        end

      # Found existing record already pointing to this event - update all fields
      %PublicEventSource{} = existing when existing.event_id == event.id ->
        Logger.debug("✅ Event source link already exists, updating all fields")

        # Merge translations instead of replacing them
        merged_translations =
          case {existing.description_translations, attrs.description_translations} do
            {nil, new} ->
              new

            {old, nil} ->
              old

            {old, new} when is_map(old) and is_map(new) ->
              Map.merge(old, new, fn _k, old_val, new_val ->
                # If new value is nil or empty, keep old value
                if new_val in [nil, ""], do: old_val, else: new_val
              end)

            {_old, new} ->
              new
          end

        existing
        |> PublicEventSource.changeset(%{
          last_seen_at: attrs.last_seen_at,
          metadata: attrs.metadata,
          image_url: attrs.image_url,
          source_url: attrs.source_url,
          description_translations: merged_translations,
          # Add price fields
          min_price: attrs.min_price,
          max_price: attrs.max_price,
          currency: attrs.currency,
          is_free: attrs.is_free
        })
        |> Repo.update()

      # No existing record by external_id
      nil ->
        # CRITICAL: For showtimes, we need MULTIPLE PublicEventSource records per event
        # Each showtime (different time/date) should be a separate record with unique external_id
        # DO NOT use fallback check by (event_id, source_id) for showtimes
        is_showtime =
          ext_id &&
            (String.starts_with?(ext_id, "cinema_city_showtime_") ||
               String.starts_with?(ext_id, "repertuary_showtime_"))

        if is_showtime do
          # Showtime scenario: Always create new record for unique external_id
          Logger.debug("✨ Creating new showtime source link for event ##{event.id}")

          %PublicEventSource{}
          |> PublicEventSource.changeset(attrs)
          |> Repo.insert()
        else
          # Non-showtime scenario: Check by event_id as fallback (legacy behavior)
          # Use query with limit since unique constraint was removed to support showtimes
          existing_by_event =
            from(pes in PublicEventSource,
              where: pes.event_id == ^event.id and pes.source_id == ^source_id,
              order_by: [desc: pes.last_seen_at],
              limit: 1
            )
            |> Repo.one()

          case existing_by_event do
            # Event already has a link from this source with different external_id
            %PublicEventSource{} = existing ->
              Logger.warning("""
              ⚠️ Event ##{event.id} already linked to source #{source_id} with different external_id
              Old external_id: #{existing.external_id}
              New external_id: #{ext_id}
              Updating to new external_id
              """)

              existing
              |> PublicEventSource.changeset(attrs)
              |> Repo.update()

            # No existing link at all - create new one
            nil ->
              Logger.debug("✨ Creating new event source link for event ##{event.id}")

              %PublicEventSource{}
              |> PublicEventSource.changeset(attrs)
              |> Repo.insert()
          end
        end
    end
    |> maybe_cache_event_image(source_id, data)
  end

  # Phase 2 Event Image Caching: Cache images for enabled sources
  # Uses source-by-source rollout controlled by EventImageCaching module
  # Phase 2.5: Multi-image support for Ticketmaster and Resident Advisor
  defp maybe_cache_event_image({:ok, %PublicEventSource{} = event_source}, source_id, data) do
    # Look up source slug for caching decision
    source_slug =
      case Repo.get(Source, source_id) do
        %Source{slug: slug} when is_binary(slug) -> slug
        _ -> nil
      end

    # Only proceed if image caching is enabled for this source
    if EventImageCaching.enabled?(source_slug) do
      # Get raw data for metadata extraction
      # Check all standard patterns: raw_data, raw_event_data, and _raw_upstream (from metadata)
      metadata = data[:metadata] || data["metadata"] || %{}

      raw_data =
        data[:raw_data] || data["raw_data"] || data[:raw_event_data] || data["raw_event_data"] ||
          metadata["_raw_upstream"] || metadata[:_raw_upstream] ||
          metadata["raw_data"] || metadata[:raw_data] ||
          metadata["raw_event_data"] || metadata[:raw_event_data] ||
          %{}

      # Try multi-image caching first for supported sources
      case maybe_cache_multiple_images(event_source, source_slug, raw_data) do
        {:ok, _results} ->
          # Multi-image caching succeeded or was attempted
          # Return event source with primary image URL (hero or first cached)
          {:ok, event_source}

        :not_supported ->
          # Fall back to single image caching for other sources
          cache_single_image(event_source, source_slug, data, raw_data)
      end
    else
      {:ok, event_source}
    end
  end

  defp maybe_cache_event_image({:error, _} = error, _source_id, _data), do: error

  # Multi-image caching for Ticketmaster and Resident Advisor
  # Returns {:ok, results} if images were cached, :not_supported for other sources
  defp maybe_cache_multiple_images(event_source, "ticketmaster", raw_data) do
    alias EventasaurusDiscovery.Sources.Ticketmaster.Transformer, as: TmTransformer

    # Extract images from raw Ticketmaster data
    images = raw_data["images"] || []

    if length(images) > 0 do
      # Use Ticketmaster transformer to extract prioritized images with types
      image_specs = TmTransformer.extract_prioritized_images(images, 5)

      if length(image_specs) > 0 do
        Logger.info("""
        📷 Multi-image caching for Ticketmaster event source #{event_source.id}:
          Found #{length(images)} raw images, selected #{length(image_specs)} for caching
        """)

        EventImageCaching.cache_event_images(
          image_specs,
          event_source.id,
          "ticketmaster",
          raw_data
        )
      else
        :not_supported
      end
    else
      :not_supported
    end
  end

  defp maybe_cache_multiple_images(event_source, "resident-advisor", raw_data) do
    alias EventasaurusDiscovery.Sources.ResidentAdvisor.Transformer, as: RaTransformer

    # RA stores event data in nested structure, extract it
    event_data = raw_data["event"] || raw_data

    # Use RA transformer to extract all images with types
    image_specs = RaTransformer.extract_all_images(event_data, 5)

    if length(image_specs) > 0 do
      Logger.info("""
      📷 Multi-image caching for Resident Advisor event source #{event_source.id}:
        Found #{length(image_specs)} images for caching
      """)

      EventImageCaching.cache_event_images(
        image_specs,
        event_source.id,
        "resident-advisor",
        raw_data
      )
    else
      :not_supported
    end
  end

  defp maybe_cache_multiple_images(event_source, "week_pl", raw_data) do
    alias EventasaurusDiscovery.Sources.WeekPl.Transformer, as: WeekPlTransformer

    # Week.pl stores restaurant data with imageFiles array
    # raw_data should contain the restaurant map with imageFiles
    image_specs = WeekPlTransformer.extract_all_images(raw_data, 5)

    if length(image_specs) > 0 do
      Logger.info("""
      📷 Multi-image caching for Week.pl event source #{event_source.id}:
        Found #{length(image_specs)} images for caching
      """)

      EventImageCaching.cache_event_images(
        image_specs,
        event_source.id,
        "week_pl",
        raw_data
      )
    else
      :not_supported
    end
  end

  # Other sources don't support multi-image yet
  defp maybe_cache_multiple_images(_event_source, _source_slug, _raw_data) do
    :not_supported
  end

  # Single image caching for sources that don't support multi-image
  defp cache_single_image(event_source, source_slug, data, raw_data) do
    image_url = data[:image_url] || data["image_url"]

    if image_url do
      case EventImageCaching.cache_event_image(
             image_url,
             event_source.id,
             source_slug,
             raw_data
           ) do
        {:cached, cdn_url} ->
          # Image already cached - update the event source with CDN URL
          Logger.info("📷 Using cached CDN URL for event source #{event_source.id}")

          event_source
          |> PublicEventSource.changeset(%{image_url: cdn_url})
          |> Repo.update()

        {:ok, _original_url} ->
          # Image queued for caching - return event source as-is
          {:ok, event_source}

        {:fallback, _url} ->
          # Caching failed - continue with original URL
          {:ok, event_source}
      end
    else
      {:ok, event_source}
    end
  end

  defp process_performers(_event, %{performer_names: []}), do: {:ok, []}

  defp process_performers(event, %{performer_names: names}) do
    performers =
      names
      |> Enum.map(&find_or_create_performer/1)
      # Filter out any nil results from invalid names
      |> Enum.reject(&is_nil/1)

    # Clear existing associations
    from(pep in PublicEventPerformer, where: pep.event_id == ^event.id)
    |> Repo.delete_all()

    # Create new associations
    associations =
      Enum.with_index(performers, 1)
      |> Enum.map(fn {performer, index} ->
        changeset =
          %PublicEventPerformer{}
          |> PublicEventPerformer.changeset(%{
            event_id: event.id,
            performer_id: performer.id,
            metadata: %{
              "billing_order" => index,
              "is_headliner" => index == 1
            }
          })

        # Handle potential conflicts gracefully
        case Repo.insert(changeset) do
          {:ok, association} ->
            association

          {:error, _changeset} ->
            # If it already exists, just return nil - we'll filter these out
            nil
        end
      end)
      # Remove any failed insertions
      |> Enum.reject(&is_nil/1)

    {:ok, associations}
  end

  defp find_or_create_performer(name) do
    # Clean UTF-8 first - performer names from DB may be corrupt
    clean_name = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name)

    # Then normalize the text
    normalized_name = Normalizer.normalize_text(clean_name)

    # Defense-in-depth: ensure UTF-8 validity after normalization
    # External data may arrive with invalid UTF-8 encoding
    normalized_name =
      if normalized_name do
        EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(normalized_name)
      else
        nil
      end

    # Handle nil or empty names
    if is_nil(normalized_name) or normalized_name == "" do
      nil
    else
      # Try to find existing performer by name (case-insensitive)
      # This avoids the slug generation issue entirely
      existing =
        Repo.one(
          from(p in Performer,
            where: fragment("lower(?) = lower(?)", p.name, ^normalized_name),
            limit: 1
          )
        )

      case existing do
        nil -> create_performer(normalized_name)
        performer -> performer
      end
    end
  end

  defp create_performer(name) do
    changeset =
      %Performer{}
      |> Performer.changeset(%{
        name: name
      })

    # Handle race condition where performer might be created between check and insert
    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :slug) do
      {:ok, %Performer{id: id} = performer} when not is_nil(id) ->
        # Successfully inserted new performer
        performer

      {:ok, _} ->
        # Conflict occurred (on_conflict: :nothing) - fetch the existing performer
        # Clean name before slugifying to prevent crashes
        clean_name = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(name)
        slug = Slug.slugify(clean_name)

        case Repo.get_by(Performer, slug: slug) do
          nil ->
            # Slug not found - this shouldn't happen but log and return nil
            Logger.warning("⚠️ Performer conflict but slug not found: #{name}")
            nil

          performer ->
            performer
        end

      {:error, changeset} ->
        # Validation error - log and return nil instead of raising
        # This allows the transaction to continue without this performer
        Logger.warning("⚠️ Failed to create performer '#{name}': #{inspect(changeset.errors)}")

        nil
    end
  end

  defp process_categories(event, data, source_id) do
    # Look up source by ID to get the slug - don't hardcode IDs!
    source_name =
      case Repo.get(Source, source_id) do
        %Source{slug: slug} when is_binary(slug) and slug != "" ->
          String.trim(slug)

        _ ->
          "unknown"
      end

    # Extract and assign categories based on source
    result =
      cond do
        # Ticketmaster event with raw data
        data.raw_event_data && source_name == "ticketmaster" ->
          CategoryExtractor.assign_categories_to_event(
            event.id,
            "ticketmaster",
            data.raw_event_data
          )

        # Bandsintown event with raw data (all are concerts/music events)
        data.raw_event_data && source_name == "bandsintown" ->
          CategoryExtractor.assign_categories_to_event(
            event.id,
            "bandsintown",
            data.raw_event_data
          )

        # Karnet event with raw data
        data.raw_event_data && source_name == "karnet" ->
          CategoryExtractor.assign_categories_to_event(
            event.id,
            "karnet",
            data.raw_event_data
          )

        # Sortiraparis event with raw data
        data.raw_event_data && source_name == "sortiraparis" ->
          CategoryExtractor.assign_categories_to_event(
            event.id,
            "sortiraparis",
            data.raw_event_data
          )

        # Event with category string (works for all sources: Karnet, PubQuiz, Waw4Free, etc.)
        data.category ->
          CategoryExtractor.assign_categories_to_event(
            event.id,
            source_name,
            %{category: data.category, url: data.source_url}
          )

        # Fallback to old category_id if present (backward compatibility)
        data.category_id ->
          # For backward compatibility, assign the old category as primary
          EventasaurusDiscovery.Categories.assign_categories_to_event(
            event.id,
            [data.category_id],
            primary_id: data.category_id,
            source: "migration"
          )

        true ->
          # No category data available - use CategoryExtractor fallback to "Other"
          CategoryExtractor.assign_categories_to_event(
            event.id,
            source_name,
            %{}
          )
      end

    case result do
      {:ok, categories} ->
        Logger.info("Assigned #{length(categories)} categories to event ##{event.id}")
        {:ok, categories}

      {:error, reason} ->
        Logger.warning("Failed to assign categories: #{inspect(reason)}")
        # Don't fail the whole event processing
        {:ok, []}
    end
  end

  # Process movie associations for movie events (e.g., Repertuary)
  defp process_movies(_event, %{movie_id: nil}), do: {:ok, []}
  defp process_movies(_event, data) when not is_map_key(data, :movie_id), do: {:ok, []}

  defp process_movies(event, %{movie_id: movie_id}) when not is_nil(movie_id) do
    # Check if event already has a movie association
    existing_movie_id =
      Repo.one(
        from(em in EventasaurusDiscovery.PublicEvents.EventMovie,
          where: em.event_id == ^event.id,
          select: em.movie_id,
          limit: 1
        )
      )

    cond do
      # No existing association - create it
      is_nil(existing_movie_id) ->
        changeset =
          %EventasaurusDiscovery.PublicEvents.EventMovie{}
          |> EventasaurusDiscovery.PublicEvents.EventMovie.changeset(%{
            event_id: event.id,
            movie_id: movie_id
          })

        case Repo.insert(changeset,
               on_conflict: :nothing,
               conflict_target: [:event_id, :movie_id]
             ) do
          {:ok, association} ->
            Logger.debug("Created movie association for event ##{event.id} -> movie ##{movie_id}")
            {:ok, [association]}

          {:error, reason} ->
            Logger.warning(
              "Failed to create movie association: #{inspect(reason)} (likely duplicate)"
            )

            {:ok, []}
        end

      # Association exists and matches - do nothing
      existing_movie_id == movie_id ->
        Logger.debug(
          "Movie association already exists for event ##{event.id} -> movie ##{movie_id}"
        )

        {:ok, []}

      # Association exists but DIFFERENT movie - this is a bug!
      true ->
        Logger.error(
          "⚠️ Event ##{event.id} already has movie ##{existing_movie_id} but trying to add movie ##{movie_id}! This should not happen."
        )

        # Don't create conflicting association
        {:ok, []}
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end

  # Extract the primary image URL from event data
  # Handles different sources which store images differently
  defp extract_primary_image_url(data) do
    # First check if image_url is directly provided (Bandsintown, Karnet)
    direct_url = data[:image_url] || data["image_url"]

    if direct_url do
      direct_url
    else
      # Check metadata for Ticketmaster images array
      metadata = data[:metadata] || data["metadata"] || %{}

      # Ticketmaster stores images in metadata.ticketmaster_data.images array
      case get_in(metadata, ["ticketmaster_data", "images"]) ||
             get_in(metadata, [:ticketmaster_data, :images]) do
        [%{"url" => url} | _] ->
          url

        [%{url: url} | _] ->
          url

        _ ->
          # Final fallback: check if metadata has image_url directly
          metadata["image_url"] || metadata[:image_url]
      end
    end
  end

  # Recurring event detection and management

  # Title normalization for fuzzy matching
  # PUBLIC: Also used by EventFreshnessChecker for prediction consistency
  def normalize_for_matching(title) do
    title
    |> String.downcase()
    # NEW: Remove date patterns
    |> remove_date_patterns()
    # NEW: Remove episode/series markers
    |> remove_episode_markers()
    # NEW: Remove time patterns
    |> remove_time_patterns()
    |> remove_marketing_suffixes()
    |> normalize_punctuation()
    |> remove_venue_suffix()
    |> collapse_whitespace()
    |> String.trim()
  end

  # NEW: Remove date patterns from titles
  defp remove_date_patterns(title) do
    patterns = [
      # Month day patterns: "Sept 23", "October 15", etc.
      ~r/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(st|nd|rd|th)?\b/i,
      # Numeric date patterns: "10/15", "9-26-2024", etc.
      ~r/\b\d{1,2}[\/-]\d{1,2}([\/-]\d{2,4})?\b/,
      # Day of week patterns: "Monday", "Thursday Night", etc.
      ~r/\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*(night|evening|morning|afternoon)?\b/i,
      # Ordinal dates: "23rd", "1st", "15th"
      ~r/\b\d{1,2}(st|nd|rd|th)\b/i,
      # Year patterns: "2024", "2025"
      ~r/\b20\d{2}\b/
      # Removed written dates pattern - too aggressive, would break band names like "First Aid Kit"
    ]

    Enum.reduce(patterns, title, fn pattern, acc ->
      String.replace(acc, pattern, "")
    end)
  end

  # NEW: Remove episode and series markers
  defp remove_episode_markers(title) do
    patterns = [
      # Episode patterns: "Episode 2", "Ep. 5", etc.
      ~r/\s*(episode|ep\.?)\s*[\d]+/i,
      # Part patterns: "Part III", "Part 2", etc. (includes roman numerals in context)
      ~r/\s*(part|pt\.?)\s*[ivx\d]+/i,
      # Volume patterns: "Vol. 3", "Volume 1", etc.
      ~r/\s*(vol\.?|volume)\s*[\d]+/i,
      # Chapter patterns: "Chapter 4", etc.
      ~r/\s*(chapter|ch\.?)\s*[\d]+/i,
      # Session patterns: "Session 2", etc.
      ~r/\s*(session)\s*[\d]+/i,
      # Week patterns: "Week 1", etc.
      ~r/\s*(week)\s*[\d]+/i,
      # Day patterns: "Day 3", etc.
      ~r/\s*(day)\s*[\d]+/i,
      # Hash number patterns: "#5", "#23", etc.
      ~r/\s*#\d+\b/,
      # Edition patterns: "3rd Edition", "5th Show", etc.
      ~r/\b\d+(st|nd|rd|th)\s+(edition|show|night|performance)\b/i
      # Removed generic Roman numerals - would break band names like "X", "V", etc.
    ]

    Enum.reduce(patterns, title, fn pattern, acc ->
      String.replace(acc, pattern, "")
    end)
  end

  # NEW: Remove time patterns
  defp remove_time_patterns(title) do
    patterns = [
      # 12-hour format: "7pm", "8:30pm", "7:00 PM"
      ~r/\b\d{1,2}(:\d{2})?\s*(am|pm)\b/i,
      # 24-hour format: "19:00", "20:30"
      ~r/\b\d{1,2}:\d{2}\b/,
      # Door times: "doors 8pm", "doors at 7"
      ~r/\bdoors?\s*(at)?\s*\d{1,2}(:\d{2})?\s*(am|pm)?\b/i,
      # Show times: "show at 9", "showtime 8:30"
      ~r/\b(show|showtime)\s*(at)?\s*\d{1,2}(:\d{2})?\s*(am|pm)?\b/i
    ]

    Enum.reduce(patterns, title, fn pattern, acc ->
      String.replace(acc, pattern, "")
    end)
  end

  defp remove_marketing_suffixes(title) do
    # Remove common suffixes that indicate same event
    patterns = [
      ~r/\s*\|\s*(enhanced|vip|premium|experience|exclusive|experiences).*/i,
      ~r/\s*[-–]\s*(enhanced|vip|premium|experience|exclusive|experiences).*/i,
      ~r/\s*\((enhanced|vip|premium|experience|exclusive|experiences)\).*/i
    ]

    Enum.reduce(patterns, title, fn pattern, acc ->
      String.replace(acc, pattern, "")
    end)
  end

  defp normalize_punctuation(title) do
    title
    |> String.replace(":", " ")
    |> String.replace("-", " ")
    |> String.replace("–", " ")
    |> String.replace("/", " ")
    |> String.replace("|", " ")
  end

  defp remove_venue_suffix(title) do
    # Remove @ Venue Name patterns
    String.replace(title, ~r/\s*@\s*.+$/, "")
  end

  defp collapse_whitespace(title) do
    String.replace(title, ~r/\s+/, " ")
  end

  # Modified to accept event_type parameter to handle exhibitions and recurring events
  defp find_recurring_parent(
         title,
         venue,
         external_id,
         source_id,
         movie_id,
         article_id,
         event_type
       ) do
    if venue do
      cond do
        # Skip consolidation for exhibitions and recurring events - they're already properly structured
        event_type in [:exhibition, :recurring] ->
          Logger.debug("⏭️  Skipping consolidation for #{event_type} event type")
          nil

        # Restaurant events (week.pl): exact restaurant_date_id matching at same venue
        # This consolidates all 44 time slots for the same restaurant on the same day
        # Checks metadata.restaurant_date_id pattern
        String.contains?(external_id || "", "week_pl_") ->
          find_restaurant_date_parent(external_id, venue, source_id)

        # Article events (Sortiraparis): exact article_id matching at same venue
        # This consolidates ONE-TIME events from the same article with different dates
        article_id ->
          find_article_event_parent(article_id, venue, external_id, source_id)

        # Movie events (Karnet): exact movie_id matching at same venue
        # This consolidates showtimes for the same movie
        movie_id ->
          find_movie_event_parent(movie_id, venue, external_id, source_id)

        # Other events: fuzzy title matching for recurring events
        # This uses string similarity to find series/recurring events
        true ->
          find_non_movie_recurring_parent(title, venue, external_id, source_id)
      end
    else
      # Without venue, we can't reliably match recurring events
      nil
    end
  end

  # Find existing movie event for the same movie at the same venue
  # This is called BEFORE the movie association is created, so we can't rely on it existing
  # We'll match by movie_id in the event_movies table if it exists, otherwise nil
  defp find_movie_event_parent(movie_id, venue, external_id, source_id) do
    # Strategy: Find any event at this venue that has this movie_id associated
    # Since associations are created AFTER the first event, the first showtime won't have an association
    # Subsequent showtimes for the same movie should find the first event and consolidate
    query =
      from(e in PublicEvent,
        join: em in EventasaurusDiscovery.PublicEvents.EventMovie,
        on: em.event_id == e.id,
        where: em.movie_id == ^movie_id,
        where: e.venue_id == ^venue.id,
        order_by: [asc: e.starts_at],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        # No event with this movie association found
        # This is expected for the first showtime of a movie
        nil

      event ->
        # Found an event with this movie! Verify it's not the exact same external_id
        is_exact_same =
          if external_id && source_id do
            from(s in PublicEventSource,
              where: s.event_id == ^event.id,
              where: s.external_id == ^external_id,
              where: s.source_id == ^source_id,
              select: count(s.id)
            )
            |> Repo.one() > 0
          else
            false
          end

        if is_exact_same do
          nil
        else
          Logger.info(
            "🎬 Found movie parent for movie ##{movie_id} at venue ##{venue.id}: event ##{event.id}"
          )

          event
        end
    end
  end

  # Find existing article-based event (Sortiraparis) at the same venue
  # Similar to movie consolidation but for article-based events
  defp find_article_event_parent(article_id, venue, external_id, source_id) do
    # Strategy: Find events at this venue from same article
    # Match by checking external_id starts with "sortiraparis_{article_id}_"
    pattern = "sortiraparis_#{article_id}_%"

    # Query already filters by source_id, so we don't need to check again
    query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        where: pes.source_id == ^source_id,
        where: pes.external_id != ^external_id,
        where: like(pes.external_id, ^pattern),
        where: e.venue_id == ^venue.id,
        order_by: [asc: e.starts_at],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        Logger.debug("No article parent found for article #{article_id} at venue #{venue.id}")
        nil

      event ->
        Logger.info(
          "📰 Found article parent for article #{article_id} at venue #{venue.id}: event ##{event.id}"
        )

        event
    end
  end

  # Find existing restaurant event for the same restaurant and date (week.pl)
  # Consolidates all time slots for the same restaurant on the same day
  # External ID format: week_pl_{restaurant_id}_{date}_{slot}
  # Consolidation key: {restaurant_id}_{date}
  defp find_restaurant_date_parent(external_id, venue, source_id) do
    # Extract restaurant_date_id from external_id
    # Format: "week_pl_1234_2025-11-20_1140" -> consolidate by "1234_2025-11-20"
    case Regex.run(~r/week_pl_(\d+)_([\d-]+)_\d+/, external_id) do
      [_, restaurant_id, date] ->
        restaurant_date_id = "#{restaurant_id}_#{date}"

        # Find events at same venue with matching restaurant_date_id in metadata
        query =
          from(e in PublicEvent,
            join: pes in PublicEventSource,
            on: pes.event_id == e.id,
            where: pes.source_id == ^source_id,
            where: pes.external_id != ^external_id,
            where: e.venue_id == ^venue.id,
            where: fragment("?->>'restaurant_date_id' = ?", pes.metadata, ^restaurant_date_id),
            order_by: [asc: e.starts_at],
            limit: 1
          )

        case Repo.one(query) do
          nil ->
            Logger.debug(
              "No restaurant parent found for restaurant_date_id #{restaurant_date_id} at venue #{venue.id}"
            )

            nil

          event ->
            Logger.info(
              "🍽️  Found restaurant parent for restaurant_date_id #{restaurant_date_id} at venue #{venue.id}: event ##{event.id}"
            )

            event
        end

      _ ->
        Logger.warning("Could not parse external_id for restaurant consolidation: #{external_id}")
        nil
    end
  end

  # Original fuzzy matching logic for non-movie events
  defp find_non_movie_recurring_parent(title, venue, external_id, source_id) do
    # Get source configuration to check aggregate_on_index setting
    source = Repo.get(Source, source_id)

    # Skip fuzzy matching consolidation for sources with aggregate_on_index: false
    # These sources (like Sortiraparis) want individual event instances, not consolidated occurrences
    if source && source.aggregate_on_index == false do
      Logger.debug("⏭️  Skipping consolidation for non-aggregatable source: #{source.name}")
      nil
    else
      # Continue with fuzzy matching consolidation
      # Ensure UTF-8 validity before any string operations
      # PostgreSQL may have stored corrupt data that crashes jaro_distance
      clean_title = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(title)

      # Normalize the incoming title for matching
      normalized_title = normalize_for_matching(clean_title)

      # Extract series base for better matching
      series_base = extract_series_base(clean_title)

      # Calculate dynamic threshold based on title patterns
      similarity_threshold = calculate_similarity_threshold(clean_title, venue)

      # Step 1: Get all events at the same venue
      same_venue_query =
        from(e in PublicEvent,
          where: e.venue_id == ^venue.id,
          order_by: [asc: e.starts_at]
        )

      same_venue_matches = Repo.all(same_venue_query)

      # Step 2: Find similar venues and get events there too (for cross-venue matching)
      similar_venue_ids =
        from(v in EventasaurusApp.Venues.Venue,
          where: v.city_id == ^venue.city_id,
          where: v.id != ^venue.id,
          where: fragment("similarity(?, ?) > ?", v.name, ^venue.name, 0.7),
          select: v.id
        )
        |> Repo.all()

      similar_venue_matches =
        if length(similar_venue_ids) > 0 do
          from(e in PublicEvent,
            where: e.venue_id in ^similar_venue_ids,
            where: fragment("similarity(?, ?) > ?", e.title, ^title, ^similarity_threshold),
            order_by: [asc: e.starts_at]
          )
          |> Repo.all()
        else
          []
        end

      # Combine all potential matches
      all_potential_matches = same_venue_matches ++ similar_venue_matches

      # Find the best match using fuzzy matching
      # We want to find the BEST parent (earliest date with highest score)
      # Don't exclude events from same source - we WANT to consolidate siblings
      best_match =
        all_potential_matches
        |> Enum.uniq_by(& &1.id)
        |> Enum.map(fn event ->
          # Check if this exact event is the one being processed
          # Only skip if it's the exact same event (same external_id AND source)
          is_exact_same =
            if external_id && source_id do
              from(s in PublicEventSource,
                where: s.event_id == ^event.id,
                where: s.external_id == ^external_id,
                where: s.source_id == ^source_id,
                select: count(s.id)
              )
              |> Repo.one() > 0
            else
              false
            end

          # Calculate match score with multiple strategies
          # Clean event title from database - may contain invalid UTF-8
          clean_event_title = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(event.title)
          normalized_event_title = normalize_for_matching(clean_event_title)
          event_series_base = extract_series_base(clean_event_title)

          # Try multiple matching strategies
          title_score = String.jaro_distance(normalized_title, normalized_event_title)
          series_score = String.jaro_distance(series_base, event_series_base)

          # Use the best score from either strategy
          base_score = max(title_score, series_score)

          # Bonus for same venue
          venue_bonus = if event.venue_id == venue.id, do: 0.05, else: 0.0

          # Bonus for series patterns
          series_bonus =
            if is_series_event?(clean_title) && is_series_event?(clean_event_title),
              do: 0.05,
              else: 0.0

          final_score = base_score + venue_bonus + series_bonus

          # Check if this is a different event from the same source
          # For concert events, don't merge different external IDs from same source
          is_different_from_same_source =
            if external_id && source_id && String.contains?(clean_title, "@") do
              # For concert events, check if it's from same source but different external_id
              from(s in PublicEventSource,
                where: s.event_id == ^event.id,
                where: s.source_id == ^source_id,
                where: s.external_id != ^external_id,
                select: count(s.id)
              )
              |> Repo.one() > 0
            else
              false
            end

          # We want high score matches, but not the exact same event instance
          # For concerts, don't allow same-source siblings with different external_ids
          if is_exact_same || is_different_from_same_source do
            # Skip if it's the exact same event OR a different concert from same source
            {event, 0.0}
          else
            {event, final_score}
          end
        end)
        |> Enum.filter(fn {_, score} -> score >= similarity_threshold end)
        |> Enum.sort_by(fn {event, score} ->
          # Sort by score (desc) then by date (asc) to get best, earliest match
          {-score, event.starts_at}
        end)
        |> List.first()

      case best_match do
        {event, score} ->
          Logger.info(
            "🔍 Found fuzzy match for '#{title}' -> '#{event.title}' (score: #{Float.round(score, 2)}, threshold: #{similarity_threshold})"
          )

          event

        nil ->
          nil
      end
    end
  end

  # NEW: Extract base title for series events
  defp extract_series_base(title) do
    title
    |> String.downcase()
    # Remove all series indicators to get the base event name
    |> String.replace(
      ~r/\s*(#\d+|episode\s+\d+|ep\.\s*\d+|part\s+[ivx\d]+|vol\.?\s*\d+|week\s+\d+|day\s+\d+|session\s+\d+).*$/i,
      ""
    )
    # Remove dates
    |> String.replace(
      ~r/\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}/i,
      ""
    )
    |> String.replace(~r/\b\d{1,2}[\/-]\d{1,2}([\/-]\d{2,4})?\b/, "")
    # Remove time patterns
    |> String.replace(~r/\b\d{1,2}(:\d{2})?\s*(am|pm)\b/i, "")
    |> collapse_whitespace()
    |> String.trim()
  end

  # NEW: Calculate dynamic similarity threshold based on event type
  defp calculate_similarity_threshold(title, venue) do
    cond do
      # Series events with episode/part numbers get lower threshold
      is_series_event?(title) -> 0.70
      # Recurring events (weekly, monthly, etc.) get lower threshold
      is_recurring_event?(title) -> 0.75
      # Concert events (with @ symbol) need very high threshold to avoid merging different artists
      String.contains?(title, "@") -> 0.95
      # Events at same venue get slightly lower threshold (but not for concerts)
      venue != nil -> 0.85
      # Default threshold
      true -> 0.90
    end
  end

  # NEW: Check if title indicates a series event
  defp is_series_event?(title) do
    # Check for series patterns but exclude simple week day names
    String.match?(
      title,
      ~r/(episode|ep\.|part|vol\.|volume|chapter|session|week\s+\d+|day\s+\d+|#\d+|\d+(st|nd|rd|th)\s+(edition|show|night))/i
    )
  end

  # NEW: Check if title indicates a recurring event
  defp is_recurring_event?(title) do
    # More specific pattern for "every" - only match when followed by time periods
    String.match?(
      title,
      ~r/\b(weekly|monthly|daily|annual|yearly|recurring|every\s+(mon(day)?|tue(sday)?|wed(nesday)?|thu(rsday)?|fri(day)?|sat(urday)?|sun(day)?|week|month|year|night|\d{1,2}(st|nd|rd|th)))\b/i
    )
  end

  defp consolidate_into_parent(existing_event, parent_event, data) do
    # Add the existing event's date as an occurrence to the parent
    with {:ok, updated_parent} <- add_occurrence_to_event(parent_event, data),
         # IMPORTANT: Also create a source record for the merged occurrence
         {:ok, _source} <- create_occurrence_source_record(parent_event, data) do
      Logger.info("🔄 Consolidated event ##{existing_event.id} into parent ##{parent_event.id}")
      {:ok, updated_parent}
    else
      error ->
        error
    end
  end

  defp add_occurrence_to_event(parent_event, new_occurrence) do
    # Initialize or get existing occurrences
    current_occurrences = parent_event.occurrences || initialize_occurrences()

    # Check if this is a pattern-type occurrence (recurring events like PubQuiz, Inquizition)
    # Pattern-type events don't store individual dates - they use recurrence rules
    if current_occurrences["type"] == "pattern" do
      # Pattern-type events already have the recurrence rule set
      # No need to add individual occurrences
      # Just update the parent event's dates if needed
      new_start_date =
        if is_nil(parent_event.starts_at) do
          new_occurrence.start_at
        else
          earliest_date([parent_event.starts_at, new_occurrence.start_at])
        end

      new_end_date =
        cond do
          is_nil(parent_event.starts_at) ->
            if parent_event.ends_at,
              do: latest_date([parent_event.ends_at, new_occurrence.start_at]),
              else: nil

          parent_event.ends_at ->
            latest_date([parent_event.ends_at, new_occurrence.start_at, parent_event.starts_at])

          DateTime.compare(new_occurrence.start_at, parent_event.starts_at) == :gt ->
            new_occurrence.start_at

          true ->
            nil
        end

      result =
        parent_event
        |> PublicEvent.changeset(%{
          starts_at: new_start_date,
          ends_at: new_end_date
        })
        |> Repo.update()

      # After updating the pattern-based event, check if dates need regeneration
      # This handles cases where the event was updated with an expired date
      case result do
        {:ok, updated_event} ->
          RecurringEventUpdater.maybe_regenerate_dates(updated_event)

        error ->
          error
      end
    else
      # Explicit-type occurrence - add to dates array
      # Resolve timezone for correct local date/time storage
      timezone =
        extract_timezone(new_occurrence) ||
          resolve_parent_event_timezone(parent_event) ||
          "Etc/UTC"

      # Create new date entry with timezone-aware date
      new_date = %{
        "date" => format_date_only(new_occurrence.start_at, timezone),
        "time" => format_time_only(new_occurrence.start_at, new_occurrence)
      }

      # Add external_id if present
      new_date =
        if new_occurrence.external_id do
          Map.put(new_date, "external_id", new_occurrence.external_id)
        else
          new_date
        end

      # Add source_id if present - this will help with more reliable source lookup
      new_date =
        if new_occurrence[:source_id] || new_occurrence["source_id"] do
          Map.put(
            new_date,
            "source_id",
            new_occurrence[:source_id] || new_occurrence["source_id"]
          )
        else
          new_date
        end

      # CRITICAL FIX: Add label from event title to distinguish ticket types
      # When events like "VIP Experience" and "General Admission" are consolidated,
      # preserve their names so users can see what each time option represents
      new_date =
        if new_occurrence.title && String.trim(new_occurrence.title) != "" do
          Map.put(new_date, "label", new_occurrence.title)
        else
          new_date
        end

      # Update occurrences - ensure dates list exists before updating
      updated_occurrences =
        update_in(
          current_occurrences,
          ["dates"],
          fn dates ->
            # Handle nil dates (shouldn't happen but defensive)
            dates = dates || []

            # Check if this date/time already exists
            if Enum.any?(dates, fn d ->
                 d["date"] == new_date["date"] && d["time"] == new_date["time"]
               end) do
              # Don't add duplicate
              dates
            else
              # Add new occurrence
              dates ++ [new_date]
            end
          end
        )

      # Update the event with new occurrences and adjust start/end dates
      # For recurring events:
      # - starts_at should be the earliest occurrence date/time (typically GA time, not VIP)
      # - ends_at should be the latest occurrence date/time
      # Never allow ends_at < starts_at; guard nil starts_at to avoid crashes.

      # Calculate earliest start time (fixes issue #1343 - wrong main time)
      new_start_date =
        if is_nil(parent_event.starts_at) do
          new_occurrence.start_at
        else
          earliest_date([parent_event.starts_at, new_occurrence.start_at])
        end

      new_end_date =
        cond do
          is_nil(parent_event.starts_at) ->
            if parent_event.ends_at,
              do: latest_date([parent_event.ends_at, new_occurrence.start_at]),
              else: nil

          parent_event.ends_at ->
            latest_date([parent_event.ends_at, new_occurrence.start_at, parent_event.starts_at])

          DateTime.compare(new_occurrence.start_at, parent_event.starts_at) == :gt ->
            new_occurrence.start_at

          true ->
            nil
        end

      parent_event
      |> PublicEvent.changeset(%{
        starts_at: new_start_date,
        occurrences: updated_occurrences,
        ends_at: new_end_date
      })
      |> Repo.update()
    end
  end

  defp initialize_occurrences do
    %{
      "type" => "explicit",
      "dates" => []
    }
  end

  defp format_date_only(%DateTime{} = dt) do
    dt
    |> DateTime.to_date()
    |> Date.to_string()
  end

  defp format_date_only(_), do: nil

  # Timezone-aware version: shift to local timezone before extracting date
  defp format_date_only(%DateTime{} = dt, timezone) when is_binary(timezone) do
    case DateTime.shift_zone(dt, timezone) do
      {:ok, shifted} ->
        shifted |> DateTime.to_date() |> Date.to_string()

      {:error, reason} ->
        Logger.warning("Timezone shift failed for #{timezone}: #{inspect(reason)}, falling back to UTC")
        dt |> DateTime.to_date() |> Date.to_string()
    end
  end

  defp format_date_only(%DateTime{} = dt, _), do: format_date_only(dt)

  # Format time with timezone awareness (2-arity version)
  defp format_time_only(%DateTime{} = dt, event_data)
       when is_map(event_data) or is_nil(event_data) do
    # Extract timezone from event data or use UTC as fallback
    timezone = extract_timezone(event_data) || "Etc/UTC"

    # Convert to local timezone before extracting time
    # This ensures occurrence times show local time, not UTC
    case DateTime.shift_zone(dt, timezone) do
      {:ok, shifted} ->
        shifted
        |> DateTime.to_time()
        |> Time.to_string()
        |> String.slice(0..4)

      {:error, reason} ->
        Logger.warning("Timezone shift failed for #{timezone}: #{inspect(reason)}, falling back to UTC")
        dt
        |> DateTime.to_time()
        |> Time.to_string()
        |> String.slice(0..4)
    end
  end

  # Resolve timezone from a venue's city association
  defp resolve_venue_timezone(nil), do: nil
  defp resolve_venue_timezone(%{city_id: nil}), do: nil

  defp resolve_venue_timezone(%{city_id: _city_id} = venue) do
    venue =
      case venue do
        %{city_ref: %City{}} -> venue
        _ -> Repo.preload(venue, city_ref: :country)
      end

    TimezoneUtils.get_city_timezone(venue.city_ref)
  rescue
    e in Ecto.QueryError ->
      Logger.warning("Failed to resolve venue timezone (query error): #{Exception.message(e)}")
      nil

    e in ArgumentError ->
      Logger.warning("Failed to resolve venue timezone (invalid data): #{Exception.message(e)}")
      nil
  end

  # Resolve timezone from a parent event's venue
  defp resolve_parent_event_timezone(parent_event) do
    case parent_event do
      %{venue_id: venue_id} when not is_nil(venue_id) ->
        venue = Repo.get(EventasaurusApp.Venues.Venue, venue_id)

        if venue do
          resolve_venue_timezone(venue)
        else
          nil
        end

      _ ->
        nil
    end
  end

  # Extract timezone from event data hierarchy
  # Priority: recurrence_rule > venue_timezone > metadata > default
  defp extract_timezone(nil), do: nil

  defp extract_timezone(data) when is_map(data) do
    cond do
      # Priority 1: recurrence_rule timezone (for pattern events)
      data[:recurrence_rule] && data[:recurrence_rule]["timezone"] ->
        data[:recurrence_rule]["timezone"]

      # Priority 2: venue-derived timezone (injected by process_event_atomically)
      is_binary(data[:venue_timezone]) ->
        data[:venue_timezone]

      # Priority 3: metadata timezone (for all events)
      data[:metadata] && data[:metadata]["timezone"] ->
        data[:metadata]["timezone"]

      # Priority 4: metadata timezone (string key fallback)
      data["metadata"] && data["metadata"]["timezone"] ->
        data["metadata"]["timezone"]

      # No timezone found
      true ->
        nil
    end
  end

  defp latest_date(dates) do
    dates
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix(&1, :second), fn -> nil end)
  end

  defp earliest_date(dates) do
    dates
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(&DateTime.to_unix(&1, :second), fn -> nil end)
  end

  defp create_occurrence_source_record(parent_event, occurrence_data) do
    # Create a source record for the occurrence being added
    # This ensures we can track where each occurrence came from
    source_attrs = %{
      event_id: parent_event.id,
      source_id: occurrence_data[:source_id] || occurrence_data["source_id"],
      external_id: occurrence_data.external_id,
      source_url: occurrence_data[:source_url] || occurrence_data["source_url"],
      image_url: occurrence_data[:image_url] || occurrence_data["image_url"],
      description_translations:
        occurrence_data[:description_translations] || occurrence_data["description_translations"],
      # Price fields from source data
      min_price: occurrence_data[:min_price],
      max_price: occurrence_data[:max_price],
      currency: occurrence_data[:currency],
      is_free: occurrence_data[:is_free] || false,
      metadata: %{
        "occurrence" => true,
        "merged_at" => DateTime.utc_now(),
        "original_metadata" => occurrence_data[:metadata] || occurrence_data["metadata"] || %{}
      },
      last_seen_at: DateTime.utc_now()
    }

    %PublicEventSource{}
    |> PublicEventSource.changeset(source_attrs)
    |> Repo.insert(
      on_conflict:
        {:replace, [:last_seen_at, :metadata, :description_translations, :image_url, :source_url]},
      conflict_target: [:external_id, :source_id]
    )
  end
end
