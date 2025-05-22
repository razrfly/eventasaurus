defmodule EventasaurusWeb.PublicEventController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues

  # List of reserved slugs that should not be treated as event slugs
  @reserved_slugs ~w(login register logout dashboard help pricing privacy terms contact)

  # Public event view action (for /:slug)
  def show(conn, %{"slug" => slug}) do
    # First check if this is a reserved slug that should be handled by other controllers
    if slug in @reserved_slugs do
      conn
      |> put_flash(:error, "No event found with that name")
      |> redirect(to: ~p"/")
    else
      case Events.get_event_by_slug(slug) do
        nil ->
          conn
          |> put_flash(:error, "Event not found")
          |> redirect(to: ~p"/")

        event ->
          # Load venue and organizers for the event
          venue = if event.venue_id, do: Venues.get_venue(event.venue_id), else: nil
          organizers = Events.list_event_organizers(event)

          conn
          |> put_root_layout({EventasaurusWeb.Layouts, :public_root})
          |> put_layout(html: {EventasaurusWeb.Layouts, :public})
          |> put_open_graph_meta(event)
          |> assign(:venue, venue)
          |> assign(:organizers, organizers)
          |> render(:show, event: event, conn: conn)
      end
    end
  end

  # Helper to set Open Graph meta tags for sharing
  defp put_open_graph_meta(conn, event) do
    # Use direct slug format for sharing as per spec
    url = EventasaurusWeb.Endpoint.url() <> "/#{event.slug}"

    og_meta = %{
      title: event.title,
      description: event.tagline || "Join this event on Eventasaurus",
      url: url,
      image: event.cover_image_url
    }

    assign(conn, :og_meta, og_meta)
  end
end
