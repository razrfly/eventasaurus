defmodule EventasaurusDiscovery.PublicEvents do
  @moduledoc """
  Context module for PublicEvents with optimized discovery queries.

  Provides high-performance query functions for event discovery
  by geographic location with efficient joins and preloading.

  Following domain-driven design principles, this module maintains
  separation from the main Events context while supporting future
  geographic feature expansion.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusApp.Venues.Venue

  @doc """
  Returns upcoming events for a specific city.

  Optimized with composite indexes for city-based queries.
  Includes venue and location details with efficient preloading.

  ## Options
    * `:limit` - Maximum number of events to return (default: 50)
    * `:offset` - Number of events to skip (default: 0)
    * `:preload` - Additional associations to preload (default: [:venue, :performers, :categories])
    * `:order_by` - How to order results (default: :starts_at)

  ## Examples

      iex> PublicEvents.by_city("San Francisco")
      [%PublicEvent{title: "Concert at The Fillmore", ...}]

      iex> PublicEvents.by_city("London", limit: 10)
      [%PublicEvent{...}]
  """
  def by_city(city_name, opts \\ []) when is_binary(city_name) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    preload_opts = Keyword.get(opts, :preload, [:venue, :performers, :categories])

    now = DateTime.utc_now()

    from(pe in PublicEvent,
      join: v in Venue,
      on: pe.venue_id == v.id,
      join: c in City,
      on: v.city_id == c.id,
      where:
        ilike(c.name, ^"%#{city_name}%") and
          ((not is_nil(pe.ends_at) and pe.ends_at > ^now) or
             (is_nil(pe.ends_at) and pe.starts_at > ^now)),
      order_by: [asc: pe.starts_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
    |> Repo.preload(preload_opts ++ [venue: [city_ref: :country]])
  end

  @doc """
  Returns upcoming events for a specific country.

  Optimized with composite indexes for country-based queries.
  Includes venue and location details with efficient preloading.

  ## Options
    * `:limit` - Maximum number of events to return (default: 100)
    * `:offset` - Number of events to skip (default: 0)
    * `:preload` - Additional associations to preload (default: [:venue, :performers, :categories])
    * `:order_by` - How to order results (default: :starts_at)

  ## Examples

      iex> PublicEvents.by_country("United States")
      [%PublicEvent{title: "Music Festival", ...}]

      iex> PublicEvents.by_country("UK", limit: 25)
      [%PublicEvent{...}]
  """
  def by_country(country_name, opts \\ []) when is_binary(country_name) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    preload_opts = Keyword.get(opts, :preload, [:venue, :performers, :categories])

    now = DateTime.utc_now()

    from(pe in PublicEvent,
      join: v in Venue,
      on: pe.venue_id == v.id,
      join: c in City,
      on: v.city_id == c.id,
      join: country in Country,
      on: c.country_id == country.id,
      where:
        ilike(country.name, ^"%#{country_name}%") and
          ((not is_nil(pe.ends_at) and pe.ends_at > ^now) or
             (is_nil(pe.ends_at) and pe.starts_at > ^now)),
      order_by: [asc: pe.starts_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
    |> Repo.preload(preload_opts ++ [venue: [city_ref: :country]])
  end

  @doc """
  Returns all upcoming events with optimized performance.

  Uses read-optimized query strategies to reduce complex joins
  and efficiently load associated data.

  ## Options
    * `:limit` - Maximum number of events to return (default: 100)
    * `:offset` - Number of events to skip (default: 0)
    * `:preload` - Additional associations to preload (default: [:venue, :performers, :categories])
    * `:order_by` - How to order results (default: :starts_at)

  ## Examples

      iex> PublicEvents.upcoming()
      [%PublicEvent{...}]

      iex> PublicEvents.upcoming(limit: 20)
      [%PublicEvent{...}]
  """
  def upcoming(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    preload_opts = Keyword.get(opts, :preload, [:venue, :performers, :categories])

    now = DateTime.utc_now()

    from(pe in PublicEvent,
      where:
        (not is_nil(pe.ends_at) and pe.ends_at > ^now) or
          (is_nil(pe.ends_at) and pe.starts_at > ^now),
      order_by: [asc: pe.starts_at],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
    |> Repo.preload(preload_opts ++ [venue: [city_ref: :country]])
  end

  @doc """
  Returns events by venue ID with optimized queries.

  Useful for venue-specific event listings with location context.

  ## Options
    * `:upcoming_only` - Only return upcoming events (default: true)
    * `:limit` - Maximum number of events to return (default: 50)
    * `:offset` - Number of events to skip (default: 0)
    * `:preload` - Additional associations to preload (default: [:performers, :categories])

  ## Examples

      iex> PublicEvents.by_venue(123)
      [%PublicEvent{...}]
  """
  def by_venue(venue_id, opts \\ []) when is_integer(venue_id) do
    upcoming_only = Keyword.get(opts, :upcoming_only, true)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    preload_opts = Keyword.get(opts, :preload, [:performers, :categories])

    now = DateTime.utc_now()

    query =
      from(pe in PublicEvent,
        where: pe.venue_id == ^venue_id,
        order_by: [asc: pe.starts_at],
        limit: ^limit,
        offset: ^offset
      )

    query =
      if upcoming_only do
        where(
          query,
          [pe],
          (not is_nil(pe.ends_at) and pe.ends_at > ^now) or
            (is_nil(pe.ends_at) and pe.starts_at > ^now)
        )
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(preload_opts ++ [venue: [city_ref: :country]])
  end

  @doc """
  Returns events in a specific geographic radius.

  Uses PostGIS functions for efficient geographic queries.
  Requires venues to have latitude/longitude coordinates.

  ## Options
    * `:limit` - Maximum number of events to return (default: 50)
    * `:upcoming_only` - Only return upcoming events (default: true)
    * `:radius_miles` - Search radius in miles (default: 25)
  """
  def by_location(lat, lng, opts \\ []) when is_number(lat) and is_number(lng) do
    limit = Keyword.get(opts, :limit, 50)
    upcoming_only = Keyword.get(opts, :upcoming_only, true)
    radius_miles = Keyword.get(opts, :radius_miles, 25)

    # Convert miles to meters (PostGIS uses meters)
    radius_meters = radius_miles * 1609.34

    now = DateTime.utc_now()

    query =
      from(pe in PublicEvent,
        join: v in Venue,
        on: pe.venue_id == v.id,
        where: not is_nil(v.latitude) and not is_nil(v.longitude),
        where:
          fragment(
            "ST_DWithin(geography(ST_SetSRID(ST_MakePoint(?, ?), 4326)), geography(ST_SetSRID(ST_MakePoint(?, ?), 4326)), ?)",
            ^lng,
            ^lat,
            v.longitude,
            v.latitude,
            ^radius_meters
          ),
        order_by: [asc: pe.starts_at],
        limit: ^limit
      )

    query =
      if upcoming_only do
        where(
          query,
          [pe],
          (not is_nil(pe.ends_at) and pe.ends_at > ^now) or
            (is_nil(pe.ends_at) and pe.starts_at > ^now)
        )
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload([:venue, :performers, :categories, venue: [city_ref: :country]])
  end

  @doc """
  Get a single public event by ID with optimized preloading.

  ## Examples

      iex> PublicEvents.get(123)
      %PublicEvent{...}

      iex> PublicEvents.get(999)
      nil
  """
  def get(id) when is_integer(id) do
    PublicEvent
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      event ->
        Repo.preload(event, [:venue, :performers, :categories, venue: [city_ref: :country]])
    end
  end

  @doc """
  Get a single public event by slug with optimized preloading.

  ## Examples

      iex> PublicEvents.get_by_slug("concert-at-fillmore-123")
      %PublicEvent{...}
  """
  def get_by_slug(slug) when is_binary(slug) do
    PublicEvent
    |> Repo.get_by(slug: slug)
    |> case do
      nil ->
        nil

      event ->
        Repo.preload(event, [:venue, :performers, :categories, venue: [city_ref: :country]])
    end
  end

  @doc """
  Search events by title with optimized text matching.

  Uses PostgreSQL's text search capabilities for efficient
  title-based event discovery.

  ## Options
    * `:limit` - Maximum number of events to return (default: 25)
    * `:upcoming_only` - Only return upcoming events (default: true)
  """
  def search(query_string, opts \\ []) when is_binary(query_string) do
    limit = Keyword.get(opts, :limit, 25)
    upcoming_only = Keyword.get(opts, :upcoming_only, true)

    now = DateTime.utc_now()

    query =
      from(pe in PublicEvent,
        where: ilike(pe.title, ^"%#{query_string}%"),
        order_by: [asc: pe.starts_at],
        limit: ^limit
      )

    query =
      if upcoming_only do
        where(
          query,
          [pe],
          (not is_nil(pe.ends_at) and pe.ends_at > ^now) or
            (is_nil(pe.ends_at) and pe.starts_at > ^now)
        )
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload([:venue, :performers, :categories, venue: [city_ref: :country]])
  end

  @doc """
  Returns events that belong to any of the specified categories.

  Supports filtering by category slug or ID with efficient joins.

  ## Options
    * `:limit` - Maximum number of events to return (default: 50)
    * `:offset` - Number of events to skip (default: 0)
    * `:upcoming_only` - Only return upcoming events (default: true)
    * `:preload` - Additional associations to preload (default: [:venue, :performers, :categories])

  ## Examples

      iex> PublicEvents.by_categories(["concerts", "festivals"])
      [%PublicEvent{title: "Music Festival", ...}]

      iex> PublicEvents.by_categories([1, 2], limit: 10)
      [%PublicEvent{...}]
  """
  def get_public_event!(id) do
    from(pe in PublicEvent,
      where: pe.id == ^id,
      preload: [:categories, :venue]
    )
    |> Repo.one!()
  end

  @doc """
  Get recent events.
  """
  def recent_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(pe in PublicEvent,
      where:
        (not is_nil(pe.ends_at) and pe.ends_at > ^DateTime.utc_now()) or
          (is_nil(pe.ends_at) and pe.starts_at > ^DateTime.utc_now()),
      order_by: [asc: pe.starts_at],
      limit: ^limit,
      preload: [:categories, :venue]
    )
    |> Repo.all()
  end

  def by_categories(category_slugs_or_ids, opts \\ []) when is_list(category_slugs_or_ids) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    upcoming_only = Keyword.get(opts, :upcoming_only, true)
    preload_opts = Keyword.get(opts, :preload, [:venue, :performers, :categories])

    now = DateTime.utc_now()

    # Build base query with category filter
    query =
      from(pe in PublicEvent,
        join: pec in "public_event_categories",
        on: pec.event_id == pe.id,
        join: c in EventasaurusDiscovery.Categories.Category,
        on: c.id == pec.category_id,
        where: c.is_active == true,
        distinct: true,
        order_by: [asc: pe.starts_at],
        limit: ^limit,
        offset: ^offset
      )

    # Handle both slugs and IDs
    query =
      if Enum.all?(category_slugs_or_ids, &is_integer/1) do
        where(query, [pe, pec, c], c.id in ^category_slugs_or_ids)
      else
        # Convert to strings if needed
        slugs = Enum.map(category_slugs_or_ids, &to_string/1)
        where(query, [pe, pec, c], c.slug in ^slugs)
      end

    # Apply upcoming filter
    query =
      if upcoming_only do
        where(
          query,
          [pe],
          (not is_nil(pe.ends_at) and pe.ends_at > ^now) or
            (is_nil(pe.ends_at) and pe.starts_at > ^now)
        )
      else
        query
      end

    query
    |> Repo.all()
    |> Repo.preload(preload_opts)
  end

  @doc """
  Gets the primary category for an event.
  Returns nil if no primary category is set.
  """
  def get_primary_category(%PublicEvent{} = event) do
    event = Repo.preload(event, :categories)

    # Find primary category from the join table
    primary =
      from(pec in "public_event_categories",
        join: c in EventasaurusDiscovery.Categories.Category,
        on: c.id == pec.category_id,
        where: pec.event_id == ^event.id and pec.is_primary == true,
        select: c,
        limit: 1
      )
      |> Repo.one()

    primary || List.first(event.categories)
  end

  # Language-aware helper functions for Phase III

  @doc """
  Gets the title for an event in the preferred language with fallback.

  ## Options
    * `:language` - Preferred language code (default: "en")
    * `:fallback` - Fallback language code (default: opposite of preferred)

  ## Examples

      iex> PublicEvents.get_title(event, language: "pl")
      "Koncert w Teatrze"

      iex> PublicEvents.get_title(event, language: "fr", fallback: "en")
      "Concert at Theater"  # Falls back to English if French not available
  """
  def get_title(%PublicEvent{} = event, opts \\ []) do
    preferred = Keyword.get(opts, :language, "en")
    fallback = Keyword.get(opts, :fallback, if(preferred == "en", do: "pl", else: "en"))

    case event.title_translations do
      %{^preferred => title} when is_binary(title) and title != "" -> title
      %{^fallback => title} when is_binary(title) and title != "" -> title
      # Final fallback to original title field
      _ -> event.title
    end
  end

  @doc """
  Gets the description for an event in the preferred language with fallback.

  Loads description from the event's sources if not already preloaded.

  ## Options
    * `:language` - Preferred language code (default: "en")
    * `:fallback` - Fallback language code (default: opposite of preferred)
    * `:source_priority` - Which source to prefer if multiple sources have descriptions

  ## Examples

      iex> PublicEvents.get_description(event, language: "pl")
      "Opis wydarzenia w języku polskim"

      iex> PublicEvents.get_description(event, language: "en")
      "Event description in English"
  """
  def get_description(%PublicEvent{} = event, opts \\ []) do
    preferred = Keyword.get(opts, :language, "en")
    fallback = Keyword.get(opts, :fallback, if(preferred == "en", do: "pl", else: "en"))

    # Preload sources if not already loaded
    event =
      if Ecto.assoc_loaded?(event.sources) do
        event
      else
        Repo.preload(event, [:sources])
      end

    # Find description from sources
    description =
      event.sources
      |> Enum.find_value(fn source ->
        case source.description_translations do
          %{^preferred => desc} when is_binary(desc) and desc != "" -> desc
          _ -> nil
        end
      end)

    # Try fallback language if preferred not found
    description ||
      event.sources
      |> Enum.find_value(fn source ->
        case source.description_translations do
          %{^fallback => desc} when is_binary(desc) and desc != "" -> desc
          _ -> nil
        end
      end)
  end

  @doc """
  Gets available languages for an event's title.

  ## Examples

      iex> PublicEvents.get_title_languages(event)
      ["pl", "en"]
  """
  def get_title_languages(%PublicEvent{title_translations: nil}), do: []

  def get_title_languages(%PublicEvent{title_translations: translations}) do
    Map.keys(translations)
  end

  @doc """
  Gets available languages for an event's descriptions across all sources.

  ## Examples

      iex> PublicEvents.get_description_languages(event)
      ["pl", "en"]
  """
  def get_description_languages(%PublicEvent{} = event) do
    # Preload sources if not already loaded
    event =
      if Ecto.assoc_loaded?(event.sources) do
        event
      else
        Repo.preload(event, [:sources])
      end

    event.sources
    |> Enum.flat_map(fn source ->
      case source.description_translations do
        nil -> []
        translations when is_map(translations) -> Map.keys(translations)
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc """
  Checks if an event has content in a specific language.

  ## Examples

      iex> PublicEvents.has_language?(event, "pl")
      true

      iex> PublicEvents.has_language?(event, "fr")
      false
  """
  def has_language?(%PublicEvent{} = event, language) when is_binary(language) do
    title_langs = get_title_languages(event)
    desc_langs = get_description_languages(event)

    language in title_langs || language in desc_langs
  end

  @doc """
  Get nearby activities for a given event based on venue location.

  Returns a randomized selection of upcoming events within the specified radius,
  excluding the current event.

  ## Options
    * `:radius_km` - Search radius in kilometers (default: 25)
    * `:pool_size` - Number of events to fetch before randomizing (default: 12)
    * `:display_count` - Number of events to return after randomization (default: 4)
    * `:language` - Language code for translations (default: "en")

  ## Examples

      iex> PublicEvents.get_nearby_activities(current_event)
      [%PublicEvent{...}, ...]

      iex> PublicEvents.get_nearby_activities(current_event, radius_km: 50, display_count: 3)
      [%PublicEvent{...}, ...]
  """
  def get_nearby_activities(%PublicEvent{} = current_event, opts \\ []) do
    radius_km = Keyword.get(opts, :radius_km, 25)
    pool_size = Keyword.get(opts, :pool_size, 12)
    display_count = Keyword.get(opts, :display_count, 4)
    language = Keyword.get(opts, :language, "en")

    current_event = Repo.preload(current_event, [:venue])

    case current_event.venue do
      %Venue{latitude: nil} ->
        []

      %Venue{longitude: nil} ->
        []

      %Venue{latitude: lat, longitude: lng} ->
        lat_f = if match?(%Decimal{}, lat), do: Decimal.to_float(lat), else: lat
        lng_f = if match?(%Decimal{}, lng), do: Decimal.to_float(lng), else: lng

        nearby =
          EventasaurusDiscovery.PublicEventsEnhanced.list_events(
            center_lat: lat_f,
            center_lng: lng_f,
            radius_km: radius_km,
            page_size: pool_size + 1,
            show_past: false,
            language: language
          )

        nearby
        |> Enum.reject(&(&1.id == current_event.id))
        |> Enum.reject(&is_nil(&1.slug))
        |> Enum.shuffle()
        |> Enum.take(display_count)
        |> Repo.preload([:venue, :categories, :performers, :movies, sources: :source])

      _ ->
        []
    end
  end

  @doc """
  Get nearby activities with fallback strategies.

  If no nearby events are found within the initial radius, progressively
  expands the search radius. Falls back to popular upcoming events if
  still no results.

  ## Options
    * `:initial_radius` - Starting radius in km (default: 25)
    * `:max_radius` - Maximum radius to try in km (default: 100)
    * `:display_count` - Number of events to return (default: 4)
    * `:language` - Language code for translations (default: "en")
  """
  def get_nearby_activities_with_fallback(%PublicEvent{} = current_event, opts \\ []) do
    initial_radius = Keyword.get(opts, :initial_radius, 25)
    max_radius = Keyword.get(opts, :max_radius, 100)
    display_count = Keyword.get(opts, :display_count, 4)
    language = Keyword.get(opts, :language, "en")

    # Try initial radius
    nearby =
      get_nearby_activities(current_event,
        radius_km: initial_radius,
        display_count: display_count,
        language: language
      )

    cond do
      # Found enough events
      length(nearby) >= display_count ->
        nearby

      # Try expanded radius
      initial_radius < max_radius ->
        expanded =
          get_nearby_activities(current_event,
            radius_km: max_radius,
            display_count: display_count,
            language: language
          )

        if length(expanded) > length(nearby) do
          expanded
        else
          # Fall back to popular upcoming events in same category
          get_fallback_events(current_event, display_count, language)
        end

      # Use fallback
      true ->
        get_fallback_events(current_event, display_count, language)
    end
  end

  defp get_fallback_events(%PublicEvent{} = current_event, display_count, language) do
    # Get category IDs from current event
    category_ids = Enum.map(current_event.categories || [], & &1.id)

    # Get upcoming events from same categories or just popular upcoming events
    opts =
      if length(category_ids) > 0 do
        [categories: category_ids, page_size: display_count * 2, language: language]
      else
        [page_size: display_count * 2, language: language]
      end

    EventasaurusDiscovery.PublicEventsEnhanced.list_events(opts)
    |> Enum.reject(&(&1.id == current_event.id))
    |> Enum.reject(&is_nil(&1.slug))
    |> Enum.shuffle()
    |> Enum.take(display_count)
    |> Repo.preload([:venue, :categories, :performers, sources: :source])
  end

  @doc """
  Get occurrence type distribution statistics.

  Returns a map with counts for each occurrence type stored in event_sources.metadata JSONB.

  ## Examples

      iex> get_occurrence_type_stats()
      %{
        "one_time" => 150,
        "exhibition" => 25,
        "unknown" => 12,
        total: 187
      }
  """
  def get_occurrence_type_stats do
    alias EventasaurusDiscovery.PublicEvents.PublicEventSource

    # Query occurrence_type from JSONB metadata field
    results =
      from(es in PublicEventSource,
        select: {fragment("? ->> 'occurrence_type'", es.metadata), count(es.id)},
        group_by: fragment("? ->> 'occurrence_type'", es.metadata)
      )
      |> Repo.all()

    # Convert to map with string keys
    stats_map = Enum.into(results, %{})

    # Add total count
    total = Enum.reduce(stats_map, 0, fn {_type, count}, acc -> acc + count end)

    Map.put(stats_map, :total, total)
  end

  @doc """
  Get freshness statistics for unknown occurrence type events.

  Returns counts of fresh vs stale unknown events based on last_seen_at timestamp.

  ## Options
    * `:freshness_days` - Number of days to consider "fresh" (default: 7)

  ## Examples

      iex> get_unknown_event_freshness_stats()
      %{
        total_unknown: 15,
        fresh: 12,
        stale: 3,
        freshness_threshold: ~U[2025-10-12 10:00:00Z]
      }
  """
  def get_unknown_event_freshness_stats(opts \\ []) do
    alias EventasaurusDiscovery.PublicEvents.PublicEventSource

    freshness_days = Keyword.get(opts, :freshness_days, 7)
    current_time = DateTime.utc_now()
    freshness_threshold = DateTime.add(current_time, -freshness_days, :day)

    # Count total unknown events
    total_unknown =
      from(es in PublicEventSource,
        where: fragment("? ->> 'occurrence_type'", es.metadata) == "unknown",
        select: count(es.id)
      )
      |> Repo.one()

    # Count fresh unknown events (seen within threshold)
    fresh =
      from(es in PublicEventSource,
        where:
          fragment("? ->> 'occurrence_type'", es.metadata) == "unknown" and
            es.last_seen_at >= ^freshness_threshold,
        select: count(es.id)
      )
      |> Repo.one()

    # Calculate stale count
    stale = total_unknown - fresh

    %{
      total_unknown: total_unknown,
      fresh: fresh,
      stale: stale,
      freshness_threshold: freshness_threshold,
      freshness_days: freshness_days
    }
  end

  @doc """
  Get detailed list of unknown occurrence events with freshness status.

  Returns list of events with unknown occurrence_type, including freshness indicators.

  ## Options
    * `:freshness_days` - Number of days to consider "fresh" (default: 7)
    * `:only_stale` - If true, only return stale events (default: false)
    * `:limit` - Maximum events to return (default: 100)

  ## Examples

      iex> list_unknown_occurrence_events(only_stale: true)
      [
        %{
          event_id: 123,
          title: "Biennale Multitude",
          external_id: "sortiraparis_329086",
          last_seen_at: ~U[2025-10-10 08:00:00Z],
          is_fresh: false,
          days_since_seen: 9
        }
      ]
  """
  def list_unknown_occurrence_events(opts \\ []) do
    alias EventasaurusDiscovery.PublicEvents.PublicEventSource

    freshness_days = Keyword.get(opts, :freshness_days, 7)
    only_stale = Keyword.get(opts, :only_stale, false)
    limit = Keyword.get(opts, :limit, 100)

    current_time = DateTime.utc_now()
    freshness_threshold = DateTime.add(current_time, -freshness_days, :day)

    query =
      from(es in PublicEventSource,
        join: pe in PublicEvent,
        on: es.event_id == pe.id,
        where: fragment("? ->> 'occurrence_type'", es.metadata) == "unknown",
        select: %{
          event_id: es.event_id,
          external_id: es.external_id,
          title: pe.title,
          starts_at: pe.starts_at,
          last_seen_at: es.last_seen_at,
          original_date_string: fragment("? ->> 'original_date_string'", es.metadata)
        },
        order_by: [desc: es.last_seen_at],
        limit: ^limit
      )

    # Filter by freshness if only_stale requested
    query =
      if only_stale do
        from(q in query,
          where: q.last_seen_at < ^freshness_threshold
        )
      else
        query
      end

    results = Repo.all(query)

    # Add freshness indicators
    Enum.map(results, fn event ->
      days_since_seen =
        if event.last_seen_at do
          DateTime.diff(current_time, event.last_seen_at, :day)
        else
          nil
        end

      is_fresh = days_since_seen && days_since_seen <= freshness_days

      Map.merge(event, %{
        is_fresh: is_fresh,
        days_since_seen: days_since_seen
      })
    end)
  end
end
