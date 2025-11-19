defmodule EventasaurusDiscovery.FeaturedEvents do
  @moduledoc """
  Context module for featured and upcoming events discovery.
  """
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource

  @doc """
  Lists featured events (primarily recurring events with high occurrence counts).

  ## Options
    * `:limit` - Maximum number of events to return (default: 10)
  """
  def list_featured_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(pe in PublicEvent,
      join: v in Venue, on: pe.venue_id == v.id,
      join: c in City, on: v.city_id == c.id,
      left_join: cat in Category, on: pe.category_id == cat.id,
      where: pe.starts_at > ^NaiveDateTime.utc_now(),
      where: not is_nil(pe.occurrences),
      where: fragment("jsonb_typeof(?->'dates') = 'array'", pe.occurrences),
      where: fragment("jsonb_array_length(?->'dates') > 1", pe.occurrences),
      order_by: [desc: fragment("jsonb_array_length(?->'dates')", pe.occurrences), asc: pe.starts_at],
      limit: ^limit,
      select: %{
        id: pe.id,
        title: pe.title,
        slug: pe.slug,
        occurrences: pe.occurrences,
        city_name: c.name,
        city_slug: c.slug,
        category_name: cat.name,
        venue_name: v.name,
        occurrence_count: fragment("jsonb_array_length(?->'dates')", pe.occurrences),
        cover_image_url: fragment("(SELECT image_url FROM public_event_sources WHERE event_id = ? LIMIT 1)", pe.id)
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists diverse upcoming events using window functions to ensure variety.
  Limits to top 3 events per category and per city to ensure diversity.

  ## Options
    * `:limit` - Maximum number of events to return (default: 30)
    * `:exclude_ids` - List of event IDs to exclude (e.g. already featured)
  """
  def list_diverse_upcoming_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    # First, get the ranked events with image URLs
    inner_query =
      from(pe in PublicEvent,
        join: v in Venue, on: pe.venue_id == v.id,
        join: c in City, on: v.city_id == c.id,
        left_join: cat in Category, on: pe.category_id == cat.id,
        left_join: pes in PublicEventSource, on: pes.event_id == pe.id,
        where: pe.starts_at > ^NaiveDateTime.utc_now(),
        where: pe.starts_at < fragment("NOW() + INTERVAL '60 days'"),
        where: pe.id not in ^exclude_ids,
        select: %{
          id: pe.id,
          cover_image_url: pes.image_url,
          cat_rank: over(row_number(), partition_by: cat.id, order_by: pe.starts_at),
          city_rank: over(row_number(), partition_by: c.id, order_by: pe.starts_at)
        }
      )

    # Get the filtered event IDs
    ranked_events =
      from(q in subquery(inner_query),
        where: q.cat_rank <= 3 and q.city_rank <= 3,
        where: not is_nil(q.cover_image_url),
        order_by: q.id,
        limit: ^limit
      )
      |> Repo.all()

    # Now fetch the full events with associations and populate cover_image_url
    event_ids = Enum.map(ranked_events, & &1.id)
    image_map = Map.new(ranked_events, &{&1.id, &1.cover_image_url})

    from(pe in PublicEvent,
      where: pe.id in ^event_ids,
      preload: [:venue, :categories, :sources]
    )
    |> Repo.all()
    |> Enum.map(fn event ->
      Map.put(event, :cover_image_url, Map.get(image_map, event.id))
    end)
    |> Enum.sort_by(& &1.starts_at, NaiveDateTime)
  end
end
