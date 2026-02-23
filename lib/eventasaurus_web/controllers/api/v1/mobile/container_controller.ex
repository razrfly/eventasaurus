defmodule EventasaurusWeb.Api.V1.Mobile.ContainerController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.PublicEvents.PublicEventContainers
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusWeb.Helpers.SourceAttribution

  def show(conn, %{"slug" => slug}) do
    case PublicEventContainers.get_container_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Container not found"})

      container ->
        events = PublicEventContainers.get_container_events(container)

        json(conn, %{
          container: serialize_container(container, events),
          events: Enum.map(events, &serialize_public_event/1)
        })
    end
  end

  defp serialize_container(container, events) do
    cover_image_url =
      case events do
        [first | _] -> PublicEventsEnhanced.get_cover_image_url(first)
        _ -> nil
      end

    %{
      title: container.title,
      slug: container.slug,
      container_type: to_string(container.container_type),
      description: container.description,
      start_date: container.start_date,
      end_date: container.end_date,
      cover_image_url: cover_image_url,
      source_url: SourceAttribution.get_container_source_url(container),
      event_count: length(events)
    }
  end

  defp serialize_public_event(event) do
    %{
      slug: event.slug,
      title: event.display_title || event.title,
      starts_at: event.starts_at,
      ends_at: event.ends_at,
      cover_image_url: PublicEventsEnhanced.get_cover_image_url(event),
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
