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

    city_events_base_query()
    |> having([c, v, pe], count(pe.id) >= ^min_events)
    |> limit(^limit)
    |> select([c, v, pe], %{
      id: c.id,
      name: c.name,
      slug: c.slug,
      unsplash_gallery: c.unsplash_gallery,
      event_count: count(pe.id)
    })
    |> repo().all()
  end

  @doc """
  Lists top cities by number of upcoming events, with full city structs
  including country association preloaded.

  Returns City structs with an `:event_count` virtual field injected.

  ## Options
    * `:min_events` - Minimum number of events required (default: 5)
    * `:limit` - Maximum number of cities to return (default: 10)
  """
  @spec list_popular_cities(keyword()) :: [map()]
  def list_popular_cities(opts \\ []) do
    min_events = Keyword.get(opts, :min_events, 5)
    limit = Keyword.get(opts, :limit, 10)

    results =
      city_events_base_query()
      |> where([c, v, pe], not is_nil(c.latitude) and not is_nil(c.longitude))
      |> having([c, v, pe], count(pe.id) >= ^min_events)
      |> limit(^limit)
      |> select([c, v, pe], {c, count(pe.id)})
      |> repo().all()

    {cities, counts} = Enum.unzip(results)
    preloaded = repo().preload(cities, :country)

    Enum.zip(preloaded, counts)
    |> Enum.map(fn {city, event_count} ->
      Map.put(city, :event_count, event_count)
    end)
  end

  defp city_events_base_query do
    from(c in City,
      join: v in Venue,
      on: v.city_id == c.id,
      join: pe in PublicEvent,
      on: pe.venue_id == v.id,
      where: pe.starts_at > ^NaiveDateTime.utc_now(),
      group_by: c.id,
      order_by: [desc: count(pe.id)]
    )
  end
end
