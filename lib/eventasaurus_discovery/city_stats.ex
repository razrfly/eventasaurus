defmodule EventasaurusDiscovery.CityStats do
  @moduledoc """
  Context module for city statistics and discovery queries.
  """
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue

  # Use read replica for all read operations in this module
  defp repo, do: Repo.replica()

  @doc """
  Lists top cities by number of upcoming events.

  ## Options
    * `:min_events` - Minimum number of events required (default: 10)
    * `:limit` - Maximum number of cities to return (default: 12)
  """
  def list_top_cities_by_events(opts \\ []) do
    min_events = Keyword.get(opts, :min_events, 10)
    limit = Keyword.get(opts, :limit, 12)

    from(c in City,
      join: v in Venue,
      on: v.city_id == c.id,
      join: pe in PublicEvent,
      on: pe.venue_id == v.id,
      where: pe.starts_at > ^NaiveDateTime.utc_now(),
      group_by: c.id,
      having: count(pe.id) >= ^min_events,
      order_by: [desc: count(pe.id)],
      limit: ^limit,
      select: %{
        id: c.id,
        name: c.name,
        slug: c.slug,
        unsplash_gallery: c.unsplash_gallery,
        event_count: count(pe.id)
      }
    )
    |> repo().all()
  end

  @doc """
  Lists top cities by number of upcoming events, with full city structs
  including country association preloaded.

  ## Options
    * `:min_events` - Minimum number of events required (default: 5)
    * `:limit` - Maximum number of cities to return (default: 10)
  """
  @spec list_popular_cities(keyword()) :: [%{city: City.t(), event_count: integer()}]
  def list_popular_cities(opts \\ []) do
    min_events = Keyword.get(opts, :min_events, 5)
    limit = Keyword.get(opts, :limit, 10)

    from(c in City,
      join: v in Venue,
      on: v.city_id == c.id,
      join: pe in PublicEvent,
      on: pe.venue_id == v.id,
      where: pe.starts_at > ^NaiveDateTime.utc_now(),
      where: not is_nil(c.latitude) and not is_nil(c.longitude),
      group_by: c.id,
      having: count(pe.id) >= ^min_events,
      order_by: [desc: count(pe.id)],
      limit: ^limit,
      select: {c, count(pe.id)}
    )
    |> repo().all()
    |> Enum.map(fn {city, event_count} ->
      city
      |> repo().preload(:country)
      |> Map.put(:event_count, event_count)
    end)
  end
end
