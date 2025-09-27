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
  alias EventasaurusDiscovery.Categories.CategoryExtractor
  alias Ecto.Multi

  import Ecto.Query
  require Logger

  @doc """
  Processes event data from a source.
  Creates or updates the event and manages source associations.
  """
  def process_event(event_data, source_id, source_priority \\ 10) do
    # Universal UTF-8 protection for all scrapers
    # Ensures event data from any scraper is properly sanitized before processing
    clean_event_data = EventasaurusDiscovery.Utils.UTF8.validate_map_strings(event_data)

    with {:ok, normalized} <- normalize_event_data(clean_event_data),
         {:ok, venue} <- process_venue(normalized),
         {:ok, event, action} <- find_or_create_event(normalized, venue, source_id),
         {:ok, _source} <-
           maybe_update_event_source(event, source_id, source_priority, normalized, action),
         {:ok, _performers} <- process_performers(event, normalized),
         {:ok, _categories} <- process_categories(event, normalized, source_id) do
      {:ok, Repo.preload(event, [:venue, :performers, :categories])}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process event: #{inspect(reason)}")
        error
    end
  end

  defp maybe_update_event_source(event, source_id, source_priority, normalized, action) do
    case action do
      :consolidated ->
        # Don't update source for consolidated events
        {:ok, :skipped}

      _ ->
        update_event_source(event, source_id, source_priority, normalized)
    end
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
      start_at: parse_datetime(data[:start_at] || data["start_at"] || data[:starts_at] || data["starts_at"]),
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
      # Karnet category
      category: data[:category] || data["category"],
      # Price data - now stored at source level
      min_price: data[:min_price] || data["min_price"],
      max_price: data[:max_price] || data["max_price"],
      currency: data[:currency] || data["currency"],
      is_free: data[:is_free] || data["is_free"]
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

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp process_venue(%{venue_data: nil}) do
    # Public events from scrapers MUST have venues
    {:error, "Public events must have venue data for proper location tracking"}
  end

  defp process_venue(%{venue_data: venue_data}) do
    VenueProcessor.process_venue(venue_data)
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
    """)

    # First check if we have this event from this source
    existing_from_source = find_existing_event(data.external_id, source_id)

    # Always check for recurring pattern first, regardless of whether event exists
    Logger.info("🔄 Checking for recurring event pattern...")
    recurring_parent = find_recurring_parent(data.title, venue, data.external_id, source_id)

    case {existing_from_source, recurring_parent} do
      # No existing event and no recurring parent - check for collision then create new
      {nil, nil} ->
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
      raise ArgumentError, "Cannot create public event without venue. All public events require venue for location tracking and collision detection."
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
    date_entry = %{
      "date" => format_date_only(data.start_at),
      "time" => format_time_only(data.start_at),
      "external_id" => data.external_id
    }

    # Add source_id if available
    date_entry =
      if data[:source_id] || Map.get(data, :source_id) do
        Map.put(date_entry, "source_id", data[:source_id] || Map.get(data, :source_id))
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

    if Enum.any?(updates) do
      event
      |> PublicEvent.changeset(Map.new(updates))
      |> Repo.update()
    else
      {:ok, event}
    end
  end

  defp update_event_source(event, source_id, priority, data) do
    # CRITICAL FIX: Check for existing record by external_id FIRST (like Bandsintown does)
    # This prevents duplicates when scrapers run repeatedly

    # Normalize external_id to avoid empty string collisions
    ext_id =
      case data.external_id do
        nil -> nil
        id when is_binary(id) ->
          id = String.trim(id)
          if id == "", do: nil, else: id
        id -> id
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
    metadata =
      case priority do
        nil -> base
        p -> Map.put(base, "priority", p)
      end

    attrs = %{
      event_id: event.id,
      source_id: source_id,
      external_id: ext_id,  # Use normalized ID to avoid empty strings
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
        conflicting_by_event =
          Repo.get_by(PublicEventSource, event_id: event.id, source_id: source_id)

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
            {nil, new} -> new
            {old, nil} -> old
            {old, new} when is_map(old) and is_map(new) ->
              Map.merge(old, new, fn _k, old_val, new_val ->
                # If new value is nil or empty, keep old value
                if new_val in [nil, ""], do: old_val, else: new_val
              end)
            {_old, new} -> new
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

      # No existing record by external_id, check by event_id as fallback
      nil ->
        existing_by_event =
          Repo.get_by(PublicEventSource,
            event_id: event.id,
            source_id: source_id
          )

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

  defp process_performers(_event, %{performer_names: []}), do: {:ok, []}

  defp process_performers(event, %{performer_names: names}) do
    performers =
      Enum.map(names, fn name ->
        find_or_create_performer(name)
      end)

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
    normalized_name = Normalizer.normalize_text(name)
    # Use Slug library to generate the same slug as the changeset
    slug = Slug.slugify(normalized_name)

    # Use slug-based lookup for better consistency
    case Repo.get_by(Performer, slug: slug) do
      nil -> create_performer(normalized_name)
      performer -> performer
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
        # Use Slug library to generate the same slug as the changeset
        slug = Slug.slugify(name)
        Repo.get_by!(Performer, slug: slug)

      {:error, changeset} ->
        # Actual validation error - let it bubble up
        raise "Failed to create performer: #{inspect(changeset.errors)}"
    end
  end

  defp process_categories(event, data, source_id) do
    # Determine source name from source_id
    # FIXED: Corrected source ID mapping based on actual database IDs
    source_name =
      case source_id do
        # ID 1 is Bandsintown (was wrongly "ticketmaster")
        1 -> "bandsintown"
        # ID 2 is Ticketmaster (was wrongly "karnet")
        2 -> "ticketmaster"
        # ID 3 is StubHub (not currently used)
        3 -> "stubhub"
        # ID 4 is Karnet (was wrongly ID 2)
        4 -> "karnet"
        _ -> "unknown"
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

        # Karnet event with category (backward compatibility)
        data.category && source_name == "karnet" ->
          CategoryExtractor.assign_categories_to_event(
            event.id,
            "karnet",
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
  defp normalize_for_matching(title) do
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

  defp find_recurring_parent(title, venue, external_id, source_id) do
    if venue do
      # Ensure title is valid UTF-8 before processing
      safe_title = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(title)

      # Normalize the incoming title for matching
      normalized_title = normalize_for_matching(safe_title)

      # Extract series base for better matching
      series_base = extract_series_base(safe_title)

      # Calculate dynamic threshold based on title patterns
      similarity_threshold = calculate_similarity_threshold(safe_title, venue)

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
            where: fragment("similarity(?, ?) > ?", e.title, ^safe_title, ^similarity_threshold),
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
          # Ensure event title is valid UTF-8 before processing
          safe_event_title = EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(event.title)
          normalized_event_title = normalize_for_matching(safe_event_title)
          event_series_base = extract_series_base(safe_event_title)

          # Try multiple matching strategies
          title_score = String.jaro_distance(normalized_title, normalized_event_title)
          series_score = String.jaro_distance(series_base, event_series_base)

          # Use the best score from either strategy
          base_score = max(title_score, series_score)

          # Bonus for same venue
          venue_bonus = if event.venue_id == venue.id, do: 0.05, else: 0.0

          # Bonus for series patterns
          series_bonus =
            if is_series_event?(title) && is_series_event?(event.title), do: 0.05, else: 0.0

          final_score = base_score + venue_bonus + series_bonus

          # We want high score matches, but not the exact same event instance
          # Allow same-source siblings to match (different external_id)
          if is_exact_same do
            # Skip only if it's the EXACT same event instance
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
    else
      # Without venue, we can't reliably match recurring events
      nil
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
      # Events at same venue get slightly lower threshold
      venue != nil -> 0.80
      # Default threshold
      true -> 0.85
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

    # Create new date entry
    new_date = %{
      "date" => format_date_only(new_occurrence.start_at),
      "time" => format_time_only(new_occurrence.start_at)
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
        Map.put(new_date, "source_id", new_occurrence[:source_id] || new_occurrence["source_id"])
      else
        new_date
      end

    # Update occurrences
    updated_occurrences =
      update_in(
        current_occurrences,
        ["dates"],
        fn dates ->
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

    # Update the event with new occurrences and adjust end date
    new_end_date = latest_date([parent_event.ends_at, new_occurrence.start_at])

    parent_event
    |> PublicEvent.changeset(%{
      occurrences: updated_occurrences,
      ends_at: new_end_date
    })
    |> Repo.update()
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

  defp format_time_only(%DateTime{} = dt) do
    dt
    |> DateTime.to_time()
    |> Time.to_string()
    # HH:MM format
    |> String.slice(0..4)
  end

  defp format_time_only(_), do: nil

  defp latest_date(dates) do
    dates
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&DateTime.to_unix(&1, :second), fn -> nil end)
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
      conflict_target: [:event_id, :source_id]
    )
  end
end
