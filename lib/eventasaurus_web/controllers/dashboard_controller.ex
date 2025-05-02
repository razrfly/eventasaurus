defmodule EventasaurusWeb.DashboardController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events

  @doc """
  Display the user dashboard.
  """
  def index(conn, _params) do
    current_user = conn.assigns.current_user
    events = Events.get_events_for_user(current_user)
    render(conn, :index, events: events)
  end
end
