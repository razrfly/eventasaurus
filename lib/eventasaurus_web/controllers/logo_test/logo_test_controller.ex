defmodule EventasaurusWeb.LogoTestController do
  use EventasaurusWeb, :controller

  def index(conn, _params) do
    render(conn, :index, layout: false)
  end
end
