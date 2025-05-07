defmodule EventasaurusWeb.DashboardController do
  use EventasaurusWeb, :controller

  @doc """
  Display the user dashboard.
  """
  def index(conn, _params) do
    user = conn.assigns[:current_user]
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
    render(conn, :index, events: events, upcoming_events: upcoming_events, past_events: past_events)
  end
end
