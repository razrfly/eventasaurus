defmodule EventasaurusWeb.MarketingController do
  use EventasaurusWeb, :controller

  @spec why_wombie(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def why_wombie(conn, _params) do
    render(conn, :why_wombie, layout: false)
  end

  def why_not(conn, _params) do
    render(conn, :why_not, layout: false)
  end

  def oatmeal_demo(conn, _params) do
    render(conn, :oatmeal_demo, layout: false)
  end
end
