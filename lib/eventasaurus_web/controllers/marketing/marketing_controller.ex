defmodule EventasaurusWeb.MarketingController do
  use EventasaurusWeb, :controller

  @spec why_wombie(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def why_wombie(conn, _params) do
    render(conn, :why_wombie, layout: false)
  end

  @spec why_not(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def why_not(conn, _params) do
    render(conn, :why_not, layout: false)
  end

  @spec oatmeal_demo(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def oatmeal_demo(conn, _params) do
    conn
    |> put_root_layout(false)
    |> render(:oatmeal_demo, layout: false)
  end
end
