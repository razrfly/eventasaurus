defmodule EventasaurusWeb.EventController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts

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

    # First ensure we have a proper User struct
    case ensure_user_struct(conn.assigns.current_user) do
      {:ok, user} ->
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

      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid user session")
        |> redirect(to: ~p"/dashboard")
    end
  end

  # Ensure we have a proper User struct for the current user
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => supabase_id, "email" => email, "user_metadata" => user_metadata}) do
    # Try to find existing user by Supabase ID
    case Accounts.get_user_by_supabase_id(supabase_id) do
      %Accounts.User{} = user ->
        {:ok, user}
      nil ->
        # Create new user if not found
        name = user_metadata["name"] || email |> String.split("@") |> hd()

        user_params = %{
          email: email,
          name: name,
          supabase_id: supabase_id
        }

        case Accounts.create_user(user_params) do
          {:ok, user} -> {:ok, user}
          {:error, reason} -> {:error, reason}
        end
    end
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
