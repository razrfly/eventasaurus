defmodule EventasaurusWeb.EventLive.Show do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Event not found")
         |> redirect(to: ~p"/")}

      event ->
        venue = if event.venue_id, do: Venues.get_venue!(event.venue_id), else: nil

        {:ok,
         socket
         |> assign(:event, event)
         |> assign(:venue, venue)
         |> assign(:page_title, event.title)}
    end
  end
end
