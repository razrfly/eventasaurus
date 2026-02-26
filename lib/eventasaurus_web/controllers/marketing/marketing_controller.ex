defmodule EventasaurusWeb.MarketingController do
  use EventasaurusWeb, :controller

  def why_wombie(conn, _params) do
    render(conn, :why_wombie, layout: false)
  end
end
