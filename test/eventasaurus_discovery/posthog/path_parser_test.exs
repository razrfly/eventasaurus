defmodule EventasaurusDiscovery.PostHog.PathParserTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.PostHog.PathParser

  describe "parse/1" do
    test "parses activity/event pages /activities/{slug}" do
      assert {:event, "jazz-concert-krakow"} ==
               PathParser.parse("/activities/jazz-concert-krakow")

      assert {:event, "my-event"} == PathParser.parse("/activities/my-event")
    end

    test "parses direct movie pages /movies/{slug}" do
      assert {:movie, "star-wars"} == PathParser.parse("/movies/star-wars")
      assert {:movie, "nuremberg-1214931"} == PathParser.parse("/movies/nuremberg-1214931")
    end

    test "parses city-scoped movie pages /c/{city}/movies/{slug}" do
      assert {:movie, "avatar-2"} == PathParser.parse("/c/krakow/movies/avatar-2")

      assert {:movie, "nuremberg-1214931"} ==
               PathParser.parse("/c/krakow/movies/nuremberg-1214931")
    end

    test "parses direct venue pages /venues/{slug}" do
      assert {:venue, "opera-krakowska"} == PathParser.parse("/venues/opera-krakowska")
      assert {:venue, "castorama"} == PathParser.parse("/venues/castorama")
    end

    test "parses city-scoped venue pages /c/{city}/venues/{slug}" do
      assert {:venue, "klub-kwadrat"} == PathParser.parse("/c/krakow/venues/klub-kwadrat")
    end

    test "parses performer pages /performers/{slug}" do
      assert {:performer, "coldplay"} == PathParser.parse("/performers/coldplay")
      assert {:performer, "buzzcocks"} == PathParser.parse("/performers/buzzcocks")
    end

    test "returns :skip for listing pages" do
      assert :skip == PathParser.parse("/c/krakow")
      assert :skip == PathParser.parse("/activities")
      assert :skip == PathParser.parse("/movies")
      assert :skip == PathParser.parse("/venues")
      assert :skip == PathParser.parse("/performers")
      assert :skip == PathParser.parse("/")
    end

    test "returns :skip for paths with extra segments" do
      # These don't match our patterns
      assert :skip == PathParser.parse("/activities/slug/extra")
      assert :skip == PathParser.parse("/movies/slug/more")
    end

    test "returns :skip for nil input" do
      assert :skip == PathParser.parse(nil)
    end
  end

  describe "filter_events/1" do
    test "filters to only event paths and extracts slugs" do
      input = [
        {"/activities/event-1", 100},
        {"/activities/event-2", 50},
        {"/movies/movie-1", 75},
        {"/c/krakow", 200},
        {"/venues/venue-1", 30}
      ]

      result = PathParser.filter_events(input)

      assert result == [
               {"event-1", 100},
               {"event-2", 50}
             ]
    end

    test "returns empty list for no event paths" do
      input = [
        {"/movies/movie-1", 75},
        {"/c/krakow", 200}
      ]

      assert [] == PathParser.filter_events(input)
    end
  end

  describe "filter_movies/1" do
    test "filters to only movie paths and extracts slugs" do
      input = [
        {"/activities/event-1", 100},
        {"/movies/movie-1", 75},
        {"/c/krakow/movies/movie-2", 50},
        {"/venues/venue-1", 30}
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
        {"/activities/event-1", 100},
        {"/venues/venue-1", 75},
        {"/c/krakow/venues/venue-2", 50},
        {"/performers/performer-1", 30}
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
        {"/activities/event-1", 100},
        {"/performers/coldplay", 75},
        {"/performers/radiohead", 50},
        {"/venues/venue-1", 30}
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
