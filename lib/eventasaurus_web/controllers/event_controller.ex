defmodule EventasaurusWeb.EventController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Venues

  # Internal event view action (for /events/:slug)
  def show(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/dashboard")

      event ->
        # Get the current user (required due to authentication pipeline)
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            # Check if user can manage this event
            if Events.user_can_manage_event?(user, event) do
              # Get registration status for the organizer
              registration_status = Events.get_user_registration_status(event, user)

              # Load venue and organizers for the event
              venue = if event.venue_id, do: Venues.get_venue(event.venue_id), else: nil
              organizers = Events.list_event_organizers(event)

              # Load participants (guests) for the event
              participants = Events.list_event_participants(event)
                            |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})

              conn
              |> assign(:venue, venue)
              |> assign(:organizers, organizers)
              |> assign(:participants, participants)
              |> render(:show, event: event, user: user, registration_status: registration_status)
            else
              conn
              |> put_flash(:error, "You don't have permission to manage this event")
              |> redirect(to: ~p"/dashboard")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "Authentication error")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  # Attendees management (stub for now)
  def attendees(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/")

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              attendees = Events.list_event_participants(event)
              render(conn, :attendees, event: event, attendees: attendees)
            else
              conn
              |> put_flash(:error, "You don't have permission to view attendees")
              |> redirect(to: ~p"/#{event.slug}")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "You must be logged in to view attendees")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  def delete(conn, %{"slug" => slug}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/dashboard")

      event ->
        case ensure_user_struct(conn.assigns.auth_user) do
          {:ok, user} ->
            if Events.user_can_manage_event?(user, event) do
              case Events.delete_event(event) do
                {:ok, _} ->
                  conn
                  |> put_flash(:info, "Event deleted successfully")
                  |> redirect(to: ~p"/dashboard")

                {:error, _} ->
                  conn
                  |> put_flash(:error, "Unable to delete event")
                  |> redirect(to: ~p"/dashboard")
              end
            else
              conn
              |> put_flash(:error, "You don't have permission to delete this event")
              |> redirect(to: ~p"/dashboard")
            end

          {:error, _} ->
            conn
            |> put_flash(:error, "You must be logged in to delete events")
            |> redirect(to: ~p"/auth/login")
        end
    end
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
