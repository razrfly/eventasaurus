defmodule EventasaurusWeb.Plugs.ConditionalSessionPlugTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EventasaurusWeb.Plugs.ConditionalSessionPlug
  alias EventasaurusWeb.Plugs.CacheControlPlug

  describe "Phase 1: cacheable activities show pages (48h TTL)" do
    test "marks /activities/:slug as cacheable without custom TTL" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      # Show pages use default TTL (no :cache_ttl assign)
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "marks /activities/:slug/:date_slug as cacheable" do
      conn =
        :get
        |> conn("/activities/summer-festival/2025-01-15")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "handles slug with special characters" do
      conn =
        :get
        |> conn("/activities/my-awesome-event-123")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end
  end

  describe "Phase 2: cacheable venues routes (48h TTL)" do
    test "marks /venues/:slug as cacheable" do
      conn =
        :get
        |> conn("/venues/awesome-venue")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "handles venue slug with special characters" do
      conn =
        :get
        |> conn("/venues/the-jazz-club-123")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end
  end

  describe "Phase 2: cacheable performers routes (48h TTL)" do
    test "marks /performers/:slug as cacheable" do
      conn =
        :get
        |> conn("/performers/john-doe")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "handles performer slug with special characters" do
      conn =
        :get
        |> conn("/performers/the-rolling-stones-123")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end
  end

  describe "Phase 2: cacheable movies show routes (48h TTL)" do
    test "marks /movies/:identifier with TMDB ID as cacheable" do
      conn =
        :get
        |> conn("/movies/157336")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "marks /movies/:identifier with slug-tmdb_id as cacheable" do
      conn =
        :get
        |> conn("/movies/interstellar-157336")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end
  end

  describe "Phase 3: cacheable index pages (1h TTL)" do
    test "marks /activities index as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/activities")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      # Index pages get specific TTL
      assert conn.assigns[:cache_ttl] == CacheControlPlug.index_page_ttl()
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /movies index as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/movies")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == CacheControlPlug.index_page_ttl()
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "does not mark /activities index as cacheable when authenticated" do
      conn =
        :get
        |> conn("/activities")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark /movies index as cacheable when authenticated" do
      conn =
        :get
        |> conn("/movies")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "Phase 4: cacheable aggregated content pages (1h TTL)" do
    test "marks /social/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/social/pubquiz-pl")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == CacheControlPlug.index_page_ttl()
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /food/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/food/street-food-festival")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /music/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/music/jazz-nights")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /happenings/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/happenings/city-festival")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /comedy/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/comedy/standup-night")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /dance/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/dance/salsa-social")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /classes/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/classes/yoga-workshop")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /festivals/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/festivals/summer-fest")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /sports/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/sports/marathon-2025")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /theater/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/theater/hamlet-production")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "does not mark aggregated content as cacheable when authenticated" do
      conn =
        :get
        |> conn("/social/pubquiz-pl")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark nested aggregated content paths as cacheable" do
      # Only /:content_type/:identifier is cacheable, not deeper paths
      conn =
        :get
        |> conn("/social/pubquiz-pl/extra")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "City-prefixed show pages (48h TTL)" do
    test "marks /c/:city_slug/venues/:venue_slug as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/venues/palladium")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      # Show pages use default TTL (no :cache_ttl assign)
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "marks /c/:city_slug/movies/:movie_slug as cacheable" do
      conn =
        :get
        |> conn("/c/krakow/movies/interstellar-157336")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "marks /c/:city_slug/festivals/:container_slug as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/festivals/summer-fest-2025")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "marks /c/:city_slug/conferences/:container_slug as cacheable" do
      conn =
        :get
        |> conn("/c/krakow/conferences/tech-summit")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      refute Map.has_key?(conn.assigns, :cache_ttl)
    end

    test "marks /c/:city_slug/tours/:container_slug as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/tours/city-walking-tour")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "marks /c/:city_slug/series/:container_slug as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/series/weekly-comedy")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "marks /c/:city_slug/exhibitions/:container_slug as cacheable" do
      conn =
        :get
        |> conn("/c/krakow/exhibitions/modern-art")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "marks /c/:city_slug/tournaments/:container_slug as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/tournaments/chess-championship")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "does not mark city show page as cacheable when authenticated" do
      conn =
        :get
        |> conn("/c/warsaw/venues/palladium")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "City-prefixed index pages (1h TTL)" do
    test "marks /c/:city_slug (city homepage) as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/warsaw")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == CacheControlPlug.index_page_ttl()
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/events as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/krakow/events")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/venues as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/warsaw/venues")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/festivals as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/warsaw/festivals")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/conferences as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/krakow/conferences")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/tours as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/warsaw/tours")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/series as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/krakow/series")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/exhibitions as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/warsaw/exhibitions")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/tournaments as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/krakow/tournaments")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "does not mark city index page as cacheable when authenticated" do
      conn =
        :get
        |> conn("/c/warsaw")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "City aggregated content pages (1h TTL)" do
    test "marks /c/:city_slug/:content_type/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/warsaw/trivia/pubquiz-pl")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == CacheControlPlug.index_page_ttl()
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/social/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/krakow/social/networking-event")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "marks /c/:city_slug/food/:identifier as cacheable with 1h TTL" do
      conn =
        :get
        |> conn("/c/warsaw/food/street-food-fest")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
      assert conn.assigns[:cache_ttl] == 3600
    end

    test "does not mark city aggregated content as cacheable when authenticated" do
      conn =
        :get
        |> conn("/c/warsaw/trivia/pubquiz-pl")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "Non-cacheable city routes" do
    test "does not mark /c/:city_slug/search as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/search")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark /c/:city_slug/events/today as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/events/today")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark /c/:city_slug/events/weekend as cacheable" do
      conn =
        :get
        |> conn("/c/krakow/events/weekend")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark /c/:city_slug/events/week as cacheable" do
      conn =
        :get
        |> conn("/c/warsaw/events/week")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "non-cacheable routes without auth cookie" do
    test "does not mark / as cacheable" do
      conn =
        :get
        |> conn("/")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark nested paths beyond two segments as cacheable" do
      conn =
        :get
        |> conn("/activities/slug/date/extra")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark admin routes as cacheable" do
      conn =
        :get
        |> conn("/admin/dashboard")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "authenticated users (has __session cookie)" do
    test "does not mark cacheable route as cacheable when authenticated" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end

    test "does not mark date-based route as cacheable when authenticated" do
      conn =
        :get
        |> conn("/activities/summer-festival/2025-01-15")
        |> put_req_cookie("__session", "valid-session-token")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end

  describe "edge cases" do
    test "empty __session cookie is treated as anonymous" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "other cookies without __session are treated as anonymous" do
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("other_cookie", "some-value")
        |> ConditionalSessionPlug.call([])

      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "whitespace-only __session cookie in test is normalized to empty" do
      # Note: Plug.Test normalizes whitespace-only cookies to empty strings
      # In production, whitespace would be preserved and treated as authenticated
      # This test documents the test infrastructure behavior
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "   ")
        |> ConditionalSessionPlug.call([])

      # Test infrastructure normalizes "   " to "", so treated as anonymous
      assert conn.assigns[:readonly_session] == true
      assert conn.assigns[:cacheable_request] == true
    end

    test "real token is treated as authenticated" do
      # Any real token value prevents caching
      conn =
        :get
        |> conn("/activities/summer-festival")
        |> put_req_cookie("__session", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
        |> ConditionalSessionPlug.call([])

      refute conn.assigns[:readonly_session]
      refute conn.assigns[:cacheable_request]
    end
  end
end
