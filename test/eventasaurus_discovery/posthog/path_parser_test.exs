defmodule EventasaurusDiscovery.PostHog.PathParserTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.PostHog.PathParser

  describe "parse/1" do
    test "parses direct event pages /e/{slug}" do
      assert {:event, "jazz-concert-krakow"} == PathParser.parse("/e/jazz-concert-krakow")
      assert {:event, "my-event"} == PathParser.parse("/e/my-event")
    end

    test "parses city-scoped event pages /c/{city}/e/{slug}" do
      assert {:event, "jazz-concert"} == PathParser.parse("/c/krakow/e/jazz-concert")
      assert {:event, "summer-fest"} == PathParser.parse("/c/warszawa/e/summer-fest")
    end

    test "parses direct movie pages /m/{slug}" do
      assert {:movie, "star-wars"} == PathParser.parse("/m/star-wars")
    end

    test "parses city-scoped movie pages /c/{city}/m/{slug}" do
      assert {:movie, "avatar-2"} == PathParser.parse("/c/krakow/m/avatar-2")
    end

    test "parses venue pages /v/{slug}" do
      assert {:venue, "opera-krakowska"} == PathParser.parse("/v/opera-krakowska")
    end

    test "parses performer pages /p/{slug}" do
      assert {:performer, "coldplay"} == PathParser.parse("/p/coldplay")
    end

    test "returns :skip for listing pages" do
      assert :skip == PathParser.parse("/c/krakow")
      assert :skip == PathParser.parse("/activities")
      assert :skip == PathParser.parse("/")
    end

    test "returns :skip for paths with extra segments" do
      # These don't match our patterns
      assert :skip == PathParser.parse("/e/slug/extra")
      assert :skip == PathParser.parse("/c/city/e/slug/more")
    end

    test "returns :skip for nil input" do
      assert :skip == PathParser.parse(nil)
    end
  end

  describe "filter_events/1" do
    test "filters to only event paths and extracts slugs" do
      input = [
        {"/e/event-1", 100},
        {"/c/krakow/e/event-2", 50},
        {"/m/movie-1", 75},
        {"/c/krakow", 200},
        {"/v/venue-1", 30}
      ]

      result = PathParser.filter_events(input)

      assert result == [
               {"event-1", 100},
               {"event-2", 50}
             ]
    end

    test "returns empty list for no event paths" do
      input = [
        {"/m/movie-1", 75},
        {"/c/krakow", 200}
      ]

      assert [] == PathParser.filter_events(input)
    end
  end

  describe "filter_movies/1" do
    test "filters to only movie paths and extracts slugs" do
      input = [
        {"/e/event-1", 100},
        {"/m/movie-1", 75},
        {"/c/krakow/m/movie-2", 50},
        {"/v/venue-1", 30}
      ]

      result = PathParser.filter_movies(input)

      assert result == [
               {"movie-1", 75},
               {"movie-2", 50}
             ]
    end
  end

  describe "filter_venues/1" do
    test "filters to only venue paths and extracts slugs" do
      input = [
        {"/e/event-1", 100},
        {"/v/venue-1", 75},
        {"/v/venue-2", 50},
        {"/p/performer-1", 30}
      ]

      result = PathParser.filter_venues(input)

      assert result == [
               {"venue-1", 75},
               {"venue-2", 50}
             ]
    end
  end

  describe "filter_performers/1" do
    test "filters to only performer paths and extracts slugs" do
      input = [
        {"/e/event-1", 100},
        {"/p/coldplay", 75},
        {"/p/radiohead", 50},
        {"/v/venue-1", 30}
      ]

      result = PathParser.filter_performers(input)

      assert result == [
               {"coldplay", 75},
               {"radiohead", 50}
             ]
    end
  end

  describe "aggregate_by_slug/1" do
    test "aggregates view counts for duplicate slugs" do
      input = [
        {"event-1", 100},
        {"event-2", 50},
        {"event-1", 25}
      ]

      result = PathParser.aggregate_by_slug(input)

      assert result == %{
               "event-1" => 125,
               "event-2" => 50
             }
    end

    test "handles single entries" do
      input = [{"event-1", 100}]
      assert %{"event-1" => 100} == PathParser.aggregate_by_slug(input)
    end

    test "returns empty map for empty input" do
      assert %{} == PathParser.aggregate_by_slug([])
    end
  end
end
