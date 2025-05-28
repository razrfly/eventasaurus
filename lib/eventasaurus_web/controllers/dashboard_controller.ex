defmodule EventasaurusWeb.DashboardController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Accounts

  @doc """
  Display the user dashboard.
  """
  def index(conn, _params) do
    # Get the processed user from auth_user
    user = case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} -> user
      {:error, _} -> nil
    end

    events = if user, do: EventasaurusApp.Events.list_events_by_user(user), else: []
    now = DateTime.utc_now()
    upcoming_events =
      events
      |> Enum.filter(&(&1.start_at && DateTime.compare(&1.start_at, now) != :lt))
      |> Enum.sort_by(& &1.start_at)
    past_events =
      events
      |> Enum.filter(&(&1.start_at && DateTime.compare(&1.start_at, now) == :lt))
      |> Enum.sort_by(& &1.start_at, :desc)

    render(conn, :index,
      user: user,
      events: events,
      upcoming_events: upcoming_events,
      past_events: past_events
    )
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
