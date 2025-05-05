defmodule EventasaurusWeb.EventController do
  use EventasaurusWeb, :controller
  alias EventasaurusApp.Events

  def show(conn, %{"id" => id}) do
    case Events.get_event(id) do
      nil ->
        conn
        |> put_flash(:error, "Event not found")
        |> redirect(to: ~p"/")

      event ->
        render(conn, :show, event: event)
    end
  end
end
