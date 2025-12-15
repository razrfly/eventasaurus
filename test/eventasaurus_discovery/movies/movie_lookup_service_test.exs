defmodule EventasaurusDiscovery.Movies.MovieLookupServiceTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Movies.MovieLookupService
  alias EventasaurusDiscovery.Movies.Providers.{TmdbProvider, OmdbProvider}

  describe "lookup/2" do
    test "returns error when no title provided" do
      assert {:error, :no_results} = MovieLookupService.lookup(%{})
    end

    test "returns error when only empty title provided" do
      assert {:error, :no_results} = MovieLookupService.lookup(%{title: ""})
    end

    test "can skip cache with option" do
      query = %{title: "NonexistentMovie12345"}
      # Should work without error even with skip_cache
      assert {:error, _} = MovieLookupService.lookup(query, skip_cache: true)
    end
  end

  describe "search_all/2" do
    test "returns empty list when no results from any provider" do
      query = %{title: "CompletelyFakeMovieThatDoesNotExist12345xyz"}
      assert {:error, :no_results} = MovieLookupService.search_all(query)
    end
  end

  describe "cache management" do
    test "init_cache creates the ETS table" do
      # Clear if exists
      if :ets.whereis(:movie_lookup_cache) != :undefined do
        :ets.delete(:movie_lookup_cache)
      end

      assert :ok = MovieLookupService.init_cache()
      assert :ets.whereis(:movie_lookup_cache) != :undefined
    end

    test "clear_cache removes all entries" do
      MovieLookupService.init_cache()
      MovieLookupService.clear_cache()

      stats = MovieLookupService.cache_stats()
      assert stats.size == 0
    end

    test "cache_stats returns size and memory" do
      MovieLookupService.init_cache()
      stats = MovieLookupService.cache_stats()

      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory)
    end
  end

  describe "TmdbProvider" do
    test "name returns :tmdb" do
      assert TmdbProvider.name() == :tmdb
    end

    test "priority returns 10" do
      assert TmdbProvider.priority() == 10
    end

    test "supports English and Polish languages" do
      assert TmdbProvider.supports_language?("en")
      assert TmdbProvider.supports_language?("pl")
    end

    test "does not claim support for unknown languages" do
      refute TmdbProvider.supports_language?("zz")
    end
  end

  describe "OmdbProvider" do
    test "name returns :omdb" do
      assert OmdbProvider.name() == :omdb
    end

    test "priority returns 20" do
      assert OmdbProvider.priority() == 20
    end

    test "supports English language" do
      assert OmdbProvider.supports_language?("en")
    end

    test "does not support Polish language" do
      refute OmdbProvider.supports_language?("pl")
    end
  end
end
