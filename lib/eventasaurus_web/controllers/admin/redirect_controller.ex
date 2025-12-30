defmodule EventasaurusWeb.Admin.RedirectController do
  @moduledoc """
  Handles redirects from deprecated admin routes to their replacements.

  Issue #3048 Phase 3: Deprecation & Cleanup
  """
  use EventasaurusWeb, :controller

  @doc """
  Redirects deprecated /admin/scraper-logs and /admin/error-trends
  to the unified /admin/monitoring dashboard.
  """
  def to_monitoring(conn, _params) do
    conn
    |> put_flash(:info, "This page has moved to the unified Monitoring Dashboard")
    |> redirect(to: ~p"/admin/monitoring")
  end
end
