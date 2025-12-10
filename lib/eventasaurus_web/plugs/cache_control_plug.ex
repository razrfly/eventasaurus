defmodule EventasaurusWeb.Plugs.CacheControlPlug do
  @moduledoc """
  Sets cache control headers to prevent CDN/browser caching of auth-aware pages.

  ## Problem Solved

  Pages that render authentication-dependent content (navigation showing user name
  vs Sign In button) must not be cached by CDNs or browsers. Without proper cache
  headers, the following happens:

  1. First visitor (unauthenticated) loads a public page
  2. CDN caches the response with unauthenticated navigation HTML
  3. Subsequent authenticated users receive the cached unauthenticated HTML
  4. Client-side Clerk SDK confirms auth, but server-rendered HTML is wrong

  ## Solution

  This plug sets two critical headers:

  - `Cache-Control: private, no-cache, no-store, must-revalidate` - Prevents CDN
    caching and forces browser to revalidate on every request
  - `Vary: Cookie` - Tells caches that response varies based on Cookie header,
    so different users get different cached versions

  ## Usage

  Add to any pipeline that serves pages with auth-dependent content:

      pipeline :browser do
        plug EventasaurusWeb.Plugs.CacheControlPlug
        # ... other plugs
      end

  ## References

  - GitHub Issue: https://github.com/razrfly/eventasaurus/issues/2625
  - HTTP Caching: https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "private, no-cache, no-store, must-revalidate")
    |> put_resp_header("vary", merge_vary_header(conn, "Cookie"))
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
  end

  # Merge "Cookie" with any existing Vary header values
  defp merge_vary_header(conn, new_value) do
    case get_resp_header(conn, "vary") do
      [] ->
        new_value

      [existing] ->
        existing_values =
          existing
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> MapSet.new()

        if MapSet.member?(existing_values, new_value) do
          existing
        else
          "#{existing}, #{new_value}"
        end

      _multiple ->
        # Multiple Vary headers - just append
        new_value
    end
  end
end
