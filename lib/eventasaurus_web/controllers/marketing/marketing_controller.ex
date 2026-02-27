defmodule EventasaurusWeb.MarketingController do
  use EventasaurusWeb, :controller

  @spec why_wombie(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def why_wombie(conn, _params) do
    conn |> put_root_layout(false) |> render(:why_wombie, layout: false)
  end

  @spec why_not(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def why_not(conn, _params) do
    conn |> put_root_layout(false) |> render(:why_not, layout: false)
  end

  @spec oatmeal_demo(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def oatmeal_demo(conn, _params) do
    conn
    |> put_root_layout(false)
    |> render(:oatmeal_demo, layout: false)
  end

  @spec homepage(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def homepage(conn, _params) do
    conn |> put_root_layout(false) |> render(:homepage, layout: false)
  end

  @spec about(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def about(conn, _params) do
    conn |> put_root_layout(false) |> render(:about, layout: false)
  end

  @spec how_it_works(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def how_it_works(conn, _params) do
    conn |> put_root_layout(false) |> render(:how_it_works, layout: false)
  end

  @spec pricing(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def pricing(conn, _params) do
    conn |> put_root_layout(false) |> render(:pricing, layout: false)
  end

  @spec privacy_policy(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def privacy_policy(conn, _params) do
    conn |> put_root_layout(false) |> render(:privacy_policy, layout: false)
  end

  @spec terms(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def terms(conn, _params) do
    conn |> put_root_layout(false) |> render(:terms, layout: false)
  end

  @spec manifesto(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def manifesto(conn, _params) do
    conn |> put_root_layout(false) |> render(:manifesto, layout: false)
  end

  @spec problem(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def problem(conn, _params) do
    conn |> put_root_layout(false) |> render(:problem, layout: false)
  end

  @spec homepage_v2(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def homepage_v2(conn, _params) do
    conn |> put_root_layout(false) |> render(:homepage_v2, layout: false)
  end

  @spec why_wombie_v2(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def why_wombie_v2(conn, _params) do
    conn |> put_root_layout(false) |> render(:why_wombie_v2, layout: false)
  end
end
