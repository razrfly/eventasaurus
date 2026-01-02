defmodule EventasaurusWeb.EventsRedirectController do
  @moduledoc """
  Handles 301 permanent redirect from deprecated /events route to /activities.

  Issue #3147: Remove /events route and redirect to /activities

  The /events route was a legacy page showing user-created public events (48 events)
  that required authentication. This created poor UX as marketing CTAs linked to it,
  bouncing visitors to login.

  The /activities page provides a rich public discovery experience with 14,278+
  scraped events, city browsing, categories, and featured content.

  This redirect ensures backward compatibility for any existing links/bookmarks.
  """
  use EventasaurusWeb, :controller

  @doc """
  Redirects /events to /activities (301 permanent redirect).
  """
  def redirect_to_activities(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/activities")
  end
end
