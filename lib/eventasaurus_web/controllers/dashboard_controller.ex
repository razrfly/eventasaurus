defmodule EventasaurusWeb.DashboardController do
  use EventasaurusWeb, :controller

  @doc """
  Display the user dashboard.
  """
  def index(conn, _params) do
    render(conn, :index)
  end
end
