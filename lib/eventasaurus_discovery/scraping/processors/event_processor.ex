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

  import Ecto.Query
  require Logger

  @doc """
  Processes event data from a source.
  Creates or updates the event and manages source associations.
  """
  def process_event(event_data, source_id, source_priority \\ 10) do
    with {:ok, normalized} <- normalize_event_data(event_data),
         {:ok, venue} <- process_venue(normalized),
         {:ok, event} <- find_or_create_event(normalized, venue, source_id),
         {:ok, _source} <- update_event_source(event, source_id, source_priority, normalized),
         {:ok, _performers} <- process_performers(event, normalized),
         {:ok, _categories} <- process_categories(event, normalized, source_id) do
      {:ok, Repo.preload(event, [:venue, :performers, :categories])}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process event: #{inspect(reason)}")
        error
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
      description: data[:description] || data["description"],
      start_at: parse_datetime(data[:start_at] || data["start_at"]),
      ends_at: parse_datetime(data[:ends_at] || data["ends_at"]),
      venue_data: data[:venue_data] || data["venue_data"],
      performer_names: data[:performer_names] || data["performer_names"] || [],
      metadata: data[:metadata] || data["metadata"] || %{},
      source_url: data[:source_url] || data["source_url"],
      # Keep old category_id for backward compatibility
      category_id: data[:category_id] || data["category_id"],
      # Add raw data for category extraction
      raw_event_data: data[:raw_event_data] || data["raw_event_data"],
      # Karnet category
      category: data[:category] || data["category"]
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

  defp process_venue(%{venue_data: nil}), do: {:ok, nil}
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
    case find_existing_event(data.external_id, source_id) do
      nil ->
        Logger.info("📝 No existing event found from source #{source_id}, checking for similar events...")
        # Check if we have this event from another source (by slug/title/time)
        case find_similar_event(data.title, data.start_at, venue) do
          nil ->
            Logger.info("✨ No similar events found, creating new event")
            create_event(data, venue, slug)
          existing ->
            Logger.info("🔗 Found similar event ##{existing.id}, linking to it")
            {:ok, existing}
        end

      existing ->
        Logger.info("📌 Found existing event ##{existing.id} from same source, updating if needed")
        maybe_update_event(existing, data, venue)
    end
  end


  defp find_similar_event(title, start_at, venue) do
    # Delegate to shared CollisionDetector service
    CollisionDetector.find_similar_event(venue, start_at, title)
  end


  defp create_event(data, venue, slug) do
    city_id = if venue, do: venue.city_id, else: nil

    attrs = %{
      title: data.title,
      slug: slug,
      description: data.description,
      venue_id: if(venue, do: venue.id, else: nil),
      city_id: city_id,
      starts_at: data.start_at,  # Note: normalized data uses start_at, schema uses starts_at
      ends_at: data.ends_at,
      # Remove external_id and metadata from public_events
      # These will be stored only in public_event_sources
      category_id: data.category_id
    }

    %PublicEvent{}
    |> PublicEvent.changeset(attrs)
    |> Repo.insert()
  end

  defp maybe_update_event(event, data, venue) do
    updates = []

    # Only update if we have better data
    updates = if is_nil(event.description) && data.description do
      [{:description, data.description} | updates]
    else
      updates
    end

    updates = if is_nil(event.venue_id) && venue do
      [{:venue_id, venue.id}, {:city_id, venue.city_id} | updates]
    else
      updates
    end

    updates = if is_nil(event.ends_at) && data.ends_at do
      [{:ends_at, data.ends_at} | updates]
    else
      updates
    end

    updates = if is_nil(event.category_id) && data.category_id do
      [{:category_id, data.category_id} | updates]
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
    # Find or create the event source record
    event_source = Repo.get_by(PublicEventSource,
      event_id: event.id,
      source_id: source_id
    ) || %PublicEventSource{}

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
      external_id: data.external_id,
      source_url: data.source_url,
      last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: metadata
    }

    event_source
    |> PublicEventSource.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp process_performers(_event, %{performer_names: []}), do: {:ok, []}
  defp process_performers(event, %{performer_names: names}) do
    performers = Enum.map(names, fn name ->
      find_or_create_performer(name)
    end)

    # Clear existing associations
    from(pep in PublicEventPerformer, where: pep.event_id == ^event.id)
    |> Repo.delete_all()

    # Create new associations
    associations = Enum.with_index(performers, 1) |> Enum.map(fn {performer, index} ->
      changeset = %PublicEventPerformer{}
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
        {:ok, association} -> association
        {:error, _changeset} ->
          # If it already exists, just return nil - we'll filter these out
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)  # Remove any failed insertions

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
    changeset = %Performer{}
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

  defp process_categories(_event, %{raw_event_data: nil, category: nil}, _source_id), do: {:ok, []}
  defp process_categories(event, data, source_id) do
    # Determine source name from source_id
    # FIXED: Corrected source ID mapping based on actual database IDs
    source_name = case source_id do
      1 -> "bandsintown"   # ID 1 is Bandsintown (was wrongly "ticketmaster")
      2 -> "ticketmaster"  # ID 2 is Ticketmaster (was wrongly "karnet")
      3 -> "stubhub"       # ID 3 is StubHub (not currently used)
      4 -> "karnet"        # ID 4 is Karnet (was wrongly ID 2)
      _ -> "unknown"
    end

    # Extract and assign categories based on source
    result = cond do
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
        {:ok, []}
    end

    case result do
      {:ok, categories} ->
        Logger.info("Assigned #{length(categories)} categories to event ##{event.id}")
        {:ok, categories}
      {:error, reason} ->
        Logger.warning("Failed to assign categories: #{inspect(reason)}")
        {:ok, []}  # Don't fail the whole event processing
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d")
  end
end