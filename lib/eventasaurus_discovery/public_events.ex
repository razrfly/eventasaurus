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
    * `:preload` - Additional associations to preload (default: [:venue, :performers, :category])
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
    preload_opts = Keyword.get(opts, :preload, [:venue, :performers, :category])

    now = DateTime.utc_now()

    from(pe in PublicEvent,
      join: v in Venue, on: pe.venue_id == v.id,
      join: c in City, on: v.city_id == c.id,
      where: ilike(c.name, ^"%#{city_name}%") and pe.starts_at > ^now,
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
    * `:preload` - Additional associations to preload (default: [:venue, :performers, :category])
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
    preload_opts = Keyword.get(opts, :preload, [:venue, :performers, :category])

    now = DateTime.utc_now()

    from(pe in PublicEvent,
      join: v in Venue, on: pe.venue_id == v.id,
      join: c in City, on: v.city_id == c.id,
      join: country in Country, on: c.country_id == country.id,
      where: ilike(country.name, ^"%#{country_name}%") and pe.starts_at > ^now,
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
    * `:preload` - Additional associations to preload (default: [:venue, :performers, :category])
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
    preload_opts = Keyword.get(opts, :preload, [:venue, :performers, :category])

    now = DateTime.utc_now()

    from(pe in PublicEvent,
      where: pe.starts_at > ^now,
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
    * `:preload` - Additional associations to preload (default: [:performers, :category])

  ## Examples

      iex> PublicEvents.by_venue(123)
      [%PublicEvent{...}]
  """
  def by_venue(venue_id, opts \\ []) when is_integer(venue_id) do
    upcoming_only = Keyword.get(opts, :upcoming_only, true)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    preload_opts = Keyword.get(opts, :preload, [:performers, :category])

    now = DateTime.utc_now()

    query = from(pe in PublicEvent,
      where: pe.venue_id == ^venue_id,
      order_by: [asc: pe.starts_at],
      limit: ^limit,
      offset: ^offset
    )

    query = if upcoming_only do
      where(query, [pe], pe.starts_at > ^now)
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

    query = from(pe in PublicEvent,
      join: v in Venue, on: pe.venue_id == v.id,
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      where: fragment("ST_DWithin(ST_MakePoint(?, ?), ST_MakePoint(?, ?), ?)",
        ^lng, ^lat, v.longitude, v.latitude, ^radius_meters),
      order_by: [asc: pe.starts_at],
      limit: ^limit
    )

    query = if upcoming_only do
      where(query, [pe], pe.starts_at > ^now)
    else
      query
    end

    query
    |> Repo.all()
    |> Repo.preload([:venue, :performers, :category, venue: [city_ref: :country]])
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
      nil -> nil
      event -> Repo.preload(event, [:venue, :performers, :category, venue: [city_ref: :country]])
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
      nil -> nil
      event -> Repo.preload(event, [:venue, :performers, :category, venue: [city_ref: :country]])
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

    query = from(pe in PublicEvent,
      where: ilike(pe.title, ^"%#{query_string}%"),
      order_by: [asc: pe.starts_at],
      limit: ^limit
    )

    query = if upcoming_only do
      where(query, [pe], pe.starts_at > ^now)
    else
      query
    end

    query
    |> Repo.all()
    |> Repo.preload([:venue, :performers, :category, venue: [city_ref: :country]])
  end
end