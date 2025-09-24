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
end
