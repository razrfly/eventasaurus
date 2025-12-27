defmodule EventasaurusWeb.Plugs.ConditionalSessionPlug do
  @moduledoc """
  Marks cacheable routes for CDN caching with client-side auth hydration.

  This plug enables CDN caching by:
  1. Setting appropriate cache control headers via assigns
  2. Marking routes as cacheable for downstream processing
  3. Working with Cloudflare Transform Rules to strip Set-Cookie headers

  ## CDN Caching Strategy

  We cache the SAME HTML for everyone on public pages, regardless of auth state.
  Auth UI is hydrated client-side using Clerk's JavaScript SDK (SignedIn/SignedOut
  components).

  Why we don't differentiate by auth cookies:
  - Cloudflare doesn't vary cache by cookies (unless Enterprise with custom cache keys)
  - Even if we served different headers to authenticated users, they'd still get
    the cached anonymous version
  - The solution is to cache the same page for everyone and let Clerk's client-side
    components hydrate the auth UI after page load

  See: https://github.com/razrfly/eventasaurus/issues/2970

  ## Important: Cookie Stripping at CDN Level

  We do NOT strip cookies at the origin because it breaks LiveView WebSocket
  authentication. Phoenix LiveView requires the session cookie to be present
  during WebSocket connection for `authorize_session` validation.

  Instead, Cloudflare Transform Rules should strip the `Set-Cookie` header
  from cacheable responses. This allows:
  - First request: Session cookie is set, response is not cached
  - Subsequent requests: Browser sends cookie, CDN serves cached response
  - LiveView: WebSocket connects with session cookie, works correctly

  ## Cloudflare Transform Rule Configuration

  Create a Transform Rule in Cloudflare to strip Set-Cookie headers:

      Rule name: Strip Set-Cookie for cacheable pages
      When: (http.host eq "your-domain.com" and starts_with(http.request.uri.path, "/activities"))
      Then: Remove response header "Set-Cookie"

  Repeat for other cacheable route patterns.

  ## How it works

  1. Checks if the request path matches a cacheable route pattern
  2. If cacheable route → mark for caching and set TTL
  3. CacheControlPlug reads these assigns and sets Cache-Control headers
  4. Cloudflare strips Set-Cookie via Transform Rules

  ## Safety

  - Uses an allowlist approach: only explicitly listed patterns can be cached
  - New routes default to NOT cached (must be added to allowlist)

  ## Cacheable Routes

  ### Show Pages (48h TTL)
  Phase 1: Activities show pages
  - /activities/:slug
  - /activities/:slug/:date_slug

  Phase 2: Venues, Performers, Movies show pages
  - /venues/:slug
  - /performers/:slug
  - /movies/:identifier

  ### Index Pages (1h TTL)
  Phase 3: Index/listing pages
  - /activities
  - /movies

  ### Aggregated Content Pages (1h TTL)
  Phase 4: Multi-city aggregated content (only implemented types)
  - /social/:identifier
  - /food/:identifier

  ### City-Prefixed Routes (Phase 2+3 completion)
  Show pages (48h TTL):
  - /c/:city_slug/venues/:venue_slug
  - /c/:city_slug/movies/:movie_slug
  - /c/:city_slug/festivals/:container_slug (and other container types)

  Index pages (1h TTL):
  - /c/:city_slug (city homepage)
  - /c/:city_slug/venues
  - /c/:city_slug/festivals (and other container type indexes)

  City aggregated content (1h TTL) - explicit routes only:
  - /c/:city_slug/social/:identifier
  - /c/:city_slug/food/:identifier
  """

  import Plug.Conn

  alias EventasaurusWeb.Plugs.CacheControlPlug

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    # CDN Caching Strategy: Cache the SAME HTML for everyone on public pages.
    # Auth UI is hydrated client-side using Clerk's JavaScript SDK.
    #
    # We mark cacheable routes with assigns that CacheControlPlug uses to set
    # appropriate Cache-Control headers. Cookie stripping is done at the CDN
    # level (Cloudflare Transform Rules) to avoid breaking LiveView.
    #
    # See: https://github.com/razrfly/eventasaurus/issues/2970
    case route_cache_config(conn.request_path) do
      {:cacheable, ttl} when not is_nil(ttl) ->
        # Mark as cacheable with specific TTL (e.g., index pages with 1h TTL)
        conn
        |> assign(:cacheable_request, true)
        |> assign(:cache_ttl, ttl)

      :cacheable ->
        # Mark as cacheable with default TTL (e.g., show pages with 48h TTL)
        conn
        |> assign(:cacheable_request, true)

      :not_cacheable ->
        conn
    end
  end

  # Returns cache configuration for a route:
  # - {:cacheable, ttl} for index pages (with specific TTL)
  # - :cacheable for show pages (uses default TTL)
  # - :not_cacheable for everything else
  defp route_cache_config(path) do
    cond do
      # Phase 3: Index pages (1h TTL) - includes city-prefixed indexes
      index_page?(path) -> {:cacheable, CacheControlPlug.index_page_ttl()}
      # Phase 4: Aggregated content pages (1h TTL) - includes city aggregated content
      aggregated_content_page?(path) -> {:cacheable, CacheControlPlug.index_page_ttl()}
      # Phase 1 + 2: Show pages (48h TTL - default) - includes city-prefixed shows
      show_page?(path) -> :cacheable
      # Everything else
      true -> :not_cacheable
    end
  end

  # Phase 3: Index page patterns (1h cache)
  defp index_page?(path) do
    patterns = [
      # /activities (index)
      ~r{^/activities$},
      # /movies (index)
      ~r{^/movies$},

      # Phase 3 completion: City-prefixed index pages
      # /c/:city_slug (city homepage)
      ~r{^/c/[^/]+$},
      # /c/:city_slug/venues
      ~r{^/c/[^/]+/venues$},
      # Container type indexes: /c/:city_slug/:container_type
      # festivals, conferences, tours, series, exhibitions, tournaments
      ~r{^/c/[^/]+/festivals$},
      ~r{^/c/[^/]+/conferences$},
      ~r{^/c/[^/]+/tours$},
      ~r{^/c/[^/]+/series$},
      ~r{^/c/[^/]+/exhibitions$},
      ~r{^/c/[^/]+/tournaments$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end

  # Phase 1 + 2: Show page patterns (48h cache)
  defp show_page?(path) do
    patterns = [
      # Phase 1: Activities
      # /activities/:slug
      ~r{^/activities/[^/]+$},
      # /activities/:slug/:date_slug
      ~r{^/activities/[^/]+/[^/]+$},

      # Phase 2: Venues, Performers, Movies (non-city-prefixed)
      # /venues/:slug
      ~r{^/venues/[^/]+$},
      # /performers/:slug
      ~r{^/performers/[^/]+$},
      # /movies/:identifier (TMDB ID or slug-tmdb_id)
      ~r{^/movies/[^/]+$},

      # Phase 2 completion: City-prefixed show pages
      # /c/:city_slug/venues/:venue_slug
      ~r{^/c/[^/]+/venues/[^/]+$},
      # /c/:city_slug/movies/:movie_slug
      ~r{^/c/[^/]+/movies/[^/]+$},
      # Container detail pages: /c/:city_slug/:container_type/:container_slug
      # festivals, conferences, tours, series, exhibitions, tournaments
      ~r{^/c/[^/]+/festivals/[^/]+$},
      ~r{^/c/[^/]+/conferences/[^/]+$},
      ~r{^/c/[^/]+/tours/[^/]+$},
      ~r{^/c/[^/]+/series/[^/]+$},
      ~r{^/c/[^/]+/exhibitions/[^/]+$},
      ~r{^/c/[^/]+/tournaments/[^/]+$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end

  # Phase 4: Aggregated content page patterns (1h cache)
  # These are multi-city aggregated content pages like /social/pubquiz-pl
  # and city-specific aggregated content like /c/warsaw/social/pubquiz-pl
  # Only explicit content types are supported - no catch-all patterns
  defp aggregated_content_page?(path) do
    patterns = [
      # Multi-city aggregated content (non-city-prefixed)
      # Add new content types here as they are implemented
      ~r{^/social/[^/]+$},
      ~r{^/food/[^/]+$},

      # City-specific aggregated content - explicit types only
      # /c/:city_slug/social/:identifier
      ~r{^/c/[^/]+/social/[^/]+$},
      # /c/:city_slug/food/:identifier
      ~r{^/c/[^/]+/food/[^/]+$}
    ]

    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, path) end)
  end
end
