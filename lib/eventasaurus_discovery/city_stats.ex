defmodule EventasaurusDiscovery.CityStats do
  @moduledoc """
  Context module for city statistics and discovery queries.
  """
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue

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
      join: v in Venue, on: v.city_id == c.id,
      join: pe in PublicEvent, on: pe.venue_id == v.id,
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
    |> Repo.all()
  end
end
