defmodule EventasaurusWeb.Dev.Test404Controller do
  @moduledoc """
  Development-only controller for testing plug-level 404 rendering.

  This demonstrates the "weird 404" behavior where render(:"404") is called
  directly from a plug without the full app layout context that LiveView provides.

  This is the same rendering approach used by ValidateCity plug when a city is not found.
  """
  use EventasaurusWeb, :controller

  def test_plug_404(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(html: EventasaurusWeb.ErrorHTML)
    |> render(:"404")
  end
end
