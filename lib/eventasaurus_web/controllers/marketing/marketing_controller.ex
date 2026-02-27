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

  @spec homepage(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def homepage(conn, _params) do
    render(conn, :homepage, layout: false)
  end

  @spec about(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def about(conn, _params) do
    render(conn, :about, layout: false)
  end

  @spec how_it_works(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def how_it_works(conn, _params) do
    render(conn, :how_it_works, layout: false)
  end

  @spec pricing(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def pricing(conn, _params) do
    render(conn, :pricing, layout: false)
  end

  @spec privacy_policy(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def privacy_policy(conn, _params), do: render(conn, :privacy_policy, layout: false)

  @spec terms(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def terms(conn, _params), do: render(conn, :terms, layout: false)
end
