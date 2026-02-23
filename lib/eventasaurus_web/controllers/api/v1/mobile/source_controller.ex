defmodule EventasaurusWeb.Api.V1.Mobile.SourceController do
  use EventasaurusWeb, :controller

  import Ecto.Query

  alias EventasaurusDiscovery.Sources.SourceStore
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusApp.Repo

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"slug" => slug} = params) do
    case SourceStore.get_source_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Source not found"})

      source ->
        opts =
          [source_slug: slug, page: 1, page_size: 50, language: "en"]
          |> maybe_add_city(params)

        events = PublicEventsEnhanced.list_events(opts)

        count_opts =
          case opts[:city_id] do
            nil -> []
            city_id -> [city_id: city_id]
          end

        total_count = PublicEventsEnhanced.count_events_by_source(slug, count_opts)
        available_cities = get_available_cities(slug)

        json(conn, %{
          source: serialize_source(source, total_count),
          events: Enum.map(events, &serialize_public_event/1),
          available_cities: available_cities
        })
    end
  end

  defp maybe_add_city(opts, %{"city_id" => city_id}) when is_binary(city_id) do
    case Integer.parse(city_id) do
      {id, ""} -> Keyword.put(opts, :city_id, id)
      _ -> opts
    end
  end

  defp maybe_add_city(opts, _), do: opts

  defp get_available_cities(source_slug) do
    from(c in EventasaurusDiscovery.Locations.City,
      join: v in EventasaurusApp.Venues.Venue,
      on: v.city_id == c.id,
      join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
      on: pe.venue_id == v.id,
      join: pes in "public_event_sources",
      on: pes.event_id == pe.id,
      join: s in "sources",
      on: s.id == pes.source_id,
      where: s.slug == ^source_slug,
      distinct: c.id,
      select: %{id: c.id, name: c.name, slug: c.slug},
      order_by: [asc: c.id]
    )
    |> Repo.all()
    |> Enum.sort_by(& &1.name)
  end

  defp serialize_source(source, event_count) do
    %{
      name: source.name,
      slug: source.slug,
      logo_url: source.logo_url,
      website_url: source.website_url,
      event_count: event_count,
      domains: source.domains
    }
  end

  defp serialize_public_event(event) do
    %{
      slug: event.slug,
      title: event.display_title || event.title,
      starts_at: event.starts_at,
      ends_at: event.ends_at,
      cover_image_url: event.cover_image_url,
      type: "public",
      venue: serialize_venue(event.venue)
    }
  end

  defp serialize_venue(nil), do: nil

  defp serialize_venue(venue) do
    %{
      name: venue.name || "Unknown Venue",
      slug: venue.slug,
      address: venue.address,
      lat: venue.latitude,
      lng: venue.longitude
    }
  end
end
