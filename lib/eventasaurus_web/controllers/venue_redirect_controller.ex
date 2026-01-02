defmodule EventasaurusWeb.VenueRedirectController do
  @moduledoc """
  Handles 301 permanent redirects from deprecated city-scoped venue routes
  to the new flat venue routes.

  Issue #3143: Simplify venue routes to match activities pattern

  Old routes (deprecated):
  - /c/:city_slug/venues/:venue_slug → /venues/:venue_slug
  - /c/:city_slug/venues → /venues

  These redirects ensure backward compatibility and preserve SEO value
  while transitioning to the simpler URL structure.
  """
  use EventasaurusWeb, :controller

  @doc """
  Redirects city-scoped venue show page to flat venue URL.
  /c/:city_slug/venues/:venue_slug → /venues/:venue_slug (301)
  """
  def redirect_venue_show(conn, %{"venue_slug" => venue_slug}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/venues/#{venue_slug}")
  end

  @doc """
  Redirects city-scoped venues index to flat venues URL.
  /c/:city_slug/venues → /venues (301)

  Note: We could add ?city=:city_slug as a filter parameter if we implement
  city filtering on the venues index page.
  """
  def redirect_venues_index(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/venues")
  end
end
