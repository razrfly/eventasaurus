defmodule EventasaurusWeb.Api.V1.Mobile.VenueController do
  use EventasaurusWeb, :controller

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.PublicEventsEnhanced

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"slug" => slug}) do
    venue =
      from(v in Venue,
        where: v.slug == ^slug,
        preload: [city_ref: :country]
      )
      |> Repo.one()

    case venue do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Venue not found"})

      venue ->
        event_filters = [
          venue_ids: [venue.id],
          start_date: Date.utc_today(),
          language: "en"
        ]

        events =
          PublicEventsEnhanced.list_events(
            Keyword.merge(event_filters, page: 1, page_size: 50)
          )

        total_events = PublicEventsEnhanced.count_events(event_filters)

        cover_image_url =
          case Venue.get_cover_image(venue) do
            {:ok, url, _source} -> url
            _ -> nil
          end

        json(conn, %{
          venue: serialize_venue(venue, cover_image_url, total_events),
          events: Enum.map(events, &serialize_event/1)
        })
    end
  end

  defp serialize_venue(venue, cover_image_url, event_count) do
    {city_name, country} =
      case venue.city_ref do
        %{name: name, country: %{name: country_name}} -> {name, country_name}
        %{name: name} -> {name, nil}
        _ -> {nil, nil}
      end

    %{
      name: venue.name,
      slug: venue.slug,
      address: venue.address,
      lat: venue.latitude,
      lng: venue.longitude,
      city_name: city_name,
      country: country,
      cover_image_url: cover_image_url,
      event_count: event_count
    }
  end

  defp serialize_event(event) do
    %{
      slug: event.slug,
      title: event.display_title || event.title,
      starts_at: event.starts_at,
      ends_at: event.ends_at,
      cover_image_url: event.cover_image_url,
      type: "public",
      venue: serialize_event_venue(event.venue)
    }
  end

  defp serialize_event_venue(nil), do: nil

  defp serialize_event_venue(venue) do
    %{
      name: venue.name,
      slug: venue.slug,
      address: venue.address,
      lat: venue.latitude,
      lng: venue.longitude
    }
  end
end
