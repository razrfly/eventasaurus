defmodule EventasaurusWeb.EventController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events

  def show(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/")

      event ->
        render(conn, :show, event: event, conn: conn)
    end
  end

  def delete(conn, %{"slug" => slug}) do
    event = Events.get_event_by_slug!(slug)
    user = conn.assigns.current_user

    # Verify user is an organizer for this event
    if Events.user_is_organizer?(event, user) do
      {:ok, _} = Events.delete_event(event)

      conn
      |> put_flash(:info, "Event successfully deleted")
      |> redirect(to: ~p"/dashboard")
    else
      conn
      |> put_flash(:error, "You don't have permission to delete this event")
      |> redirect(to: ~p"/events/#{event.slug}")
    end
  end
end
