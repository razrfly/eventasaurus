defmodule EventasaurusWeb.Plugs.ConditionalSessionPlug do
  @moduledoc """
  Conditionally skips session initialization for cacheable routes with anonymous users.

  This plug enables CDN caching by preventing Set-Cookie headers on public pages
  for users who are not logged in.

  ## How it works

  1. Checks if the request path matches a cacheable route pattern
  2. Checks if the user has an auth cookie (`__session` from Clerk)
  3. If cacheable route AND no auth cookie → skip session (page can be cached)
  4. Otherwise → normal session handling

  ## Safety

  - Uses an allowlist approach: only explicitly listed patterns can be cached
  - Any route with `__session` cookie is never cached
  - New routes default to NOT cached (must be added to allowlist)

  ## Phase 1: Activities show pages only
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if cacheable_route?(conn.request_path) and not has_auth_cookie?(conn) do
      conn
      |> assign(:skip_session, true)
      |> assign(:cacheable_request, true)
    else
      conn
    end
  end

  # Phase 1: Only activities show pages
  # Add more patterns in future phases
  defp cacheable_route?(path) do
    patterns = [
      # /activities/:slug
      ~r{^/activities/[^/]+$},
      # /activities/:slug/:date_slug
      ~r{^/activities/[^/]+/[^/]+$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end

  defp has_auth_cookie?(conn) do
    # Fetch cookies if not already fetched
    conn = fetch_cookies(conn)
    cookie = conn.cookies["__session"]
    cookie != nil and cookie != ""
  end
end
