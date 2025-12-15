defmodule EventasaurusDiscovery.Movies.Providers.ImdbProviderTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Movies.Providers.ImdbProvider

  describe "name/0" do
    test "returns :imdb" do
      assert ImdbProvider.name() == :imdb
    end
  end

  describe "priority/0" do
    test "returns 30 (tertiary provider)" do
      assert ImdbProvider.priority() == 30
    end
  end

  describe "supports_language?/1" do
    test "supports English" do
      assert ImdbProvider.supports_language?("en")
    end

    test "supports Polish via AKA data" do
      assert ImdbProvider.supports_language?("pl")
    end

    test "does not claim support for unsupported languages" do
      refute ImdbProvider.supports_language?("zz")
      refute ImdbProvider.supports_language?("jp")
    end
  end

  describe "confidence_score/2" do
    test "calculates higher confidence for exact title match with year" do
      result = %{
        title: "Seven Samurai",
        original_title: "Shichinin no samurai",
        release_date: "1954-04-26",
        imdb_title: "Seven Samurai",
        imdb_year: 1954,
        bridge_source: :imdb_web
      }

      query = %{
        polish_title: "Siedmiu samurajów",
        original_title: "Seven Samurai",
        year: 1954
      }

      score = ImdbProvider.confidence_score(result, query)

      # Should be high confidence due to:
      # - Good title match (original_title matches)
      # - Exact year match
      # - Bridge bonus
      assert score > 0.7
    end

    test "calculates lower confidence for partial match" do
      result = %{
        title: "Wild Things",
        release_date: "1998-03-20",
        bridge_source: :imdb_web
      }

      query = %{
        polish_title: "Dziki",
        year: 2020
      }

      score = ImdbProvider.confidence_score(result, query)

      # Should be lower due to:
      # - Poor title match
      # - Year mismatch
      assert score < 0.6
    end

    test "includes bridge bonus for IMDB web bridged results" do
      result_with_bridge = %{
        title: "Test Movie",
        release_date: "2020-01-01",
        bridge_source: :imdb_web
      }

      result_without_bridge = %{
        title: "Test Movie",
        release_date: "2020-01-01"
      }

      query = %{title: "Test Movie", year: 2020}

      score_with = ImdbProvider.confidence_score(result_with_bridge, query)
      score_without = ImdbProvider.confidence_score(result_without_bridge, query)

      # Bridge bonus should increase score
      assert score_with > score_without
    end
  end

  describe "search/2" do
    @tag :integration
    @tag :external
    test "returns empty list when Zyte is not configured" do
      # When Zyte is not available, provider should gracefully return empty
      unless EventasaurusDiscovery.Http.Adapters.Zyte.available?() do
        result = ImdbProvider.search(%{polish_title: "Siedmiu samurajów"})
        assert {:ok, []} = result
      end
    end
  end

  describe "get_details/1" do
    @tag :integration
    @tag :external
    test "returns error for invalid IMDB ID without Zyte" do
      # This test verifies the bridge attempt fails gracefully
      result = ImdbProvider.get_details("tt0000000")

      # Should fail since the IMDB ID doesn't exist in TMDB
      assert {:error, _reason} = result
    end
  end

  describe "provider behavior compliance" do
    test "implements all required callbacks" do
      # Verify module implements the Provider behaviour
      behaviours = ImdbProvider.__info__(:attributes)[:behaviour] || []
      assert EventasaurusDiscovery.Movies.Provider in behaviours
    end

    test "has lower priority than TmdbProvider and OmdbProvider" do
      alias EventasaurusDiscovery.Movies.Providers.{TmdbProvider, OmdbProvider}

      assert ImdbProvider.priority() > TmdbProvider.priority()
      assert ImdbProvider.priority() > OmdbProvider.priority()
    end
  end
end
