defmodule EventasaurusWeb.Api.V1.Mobile.SourceController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.Sources.SourceStore
  alias EventasaurusDiscovery.PublicEventsEnhanced

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

        json(conn, %{
          source: serialize_source(source),
          events: Enum.map(events, &serialize_public_event/1)
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

  defp serialize_source(source) do
    %{
      name: source.name,
      slug: source.slug,
      logo_url: source.logo_url,
      website_url: source.website_url
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
      name: venue.name,
      address: venue.address,
      lat: venue.latitude,
      lng: venue.longitude
    }
  end
end
