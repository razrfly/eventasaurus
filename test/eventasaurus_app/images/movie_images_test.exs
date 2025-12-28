defmodule EventasaurusApp.Images.MovieImagesTest do
  @moduledoc """
  Tests for MovieImages module.

  Verifies that movie poster and backdrop URLs are correctly retrieved
  with proper fallback behavior.

  NOTE: In non-production environments (test/dev), MovieImages skips
  cache lookups entirely and returns fallbacks directly. This prevents
  dev/test from querying a cache that doesn't exist and avoids polluting
  production R2 buckets. These tests verify that fallback behavior.
  """
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.CachedImage
  alias EventasaurusApp.Images.MovieImages
  alias EventasaurusDiscovery.Movies.Movie

  setup do
    # Create test movies
    {:ok, movie1} =
      Repo.insert(%Movie{
        title: "Test Movie 1",
        slug: "test-movie-1-#{System.unique_integer([:positive])}",
        tmdb_id: 12345,
        poster_url: "https://tmdb.org/poster1.jpg",
        backdrop_url: "https://tmdb.org/backdrop1.jpg"
      })

    {:ok, movie2} =
      Repo.insert(%Movie{
        title: "Test Movie 2",
        slug: "test-movie-2-#{System.unique_integer([:positive])}",
        tmdb_id: 67890,
        poster_url: "https://tmdb.org/poster2.jpg",
        backdrop_url: "https://tmdb.org/backdrop2.jpg"
      })

    %{movie1: movie1, movie2: movie2}
  end

  describe "get_poster_url/2 (test environment - no cache lookup)" do
    test "returns fallback when no cached image exists", %{movie1: movie} do
      fallback = "https://tmdb.org/fallback.jpg"
      assert MovieImages.get_poster_url(movie.id, fallback) == fallback
    end

    test "returns nil when no cached image and no fallback", %{movie1: movie} do
      assert MovieImages.get_poster_url(movie.id) == nil
    end

    test "returns fallback even when cached image exists (test mode skips cache)", %{
      movie1: movie
    } do
      # In test/dev, cache lookup is skipped - fallback is always returned
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie.id,
          position: 0,
          original_url: "https://tmdb.org/poster.jpg",
          cdn_url: "https://cdn.example.com/poster.jpg",
          r2_key: "images/movie/poster.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      # In non-production, fallback is returned (cache not queried)
      assert MovieImages.get_poster_url(movie.id, "fallback") == "fallback"
    end

    test "returns fallback when image is pending (test mode)", %{movie1: movie} do
      {:ok, _pending} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie.id,
          position: 0,
          original_url: "https://tmdb.org/poster.jpg",
          status: "pending",
          original_source: "tmdb"
        })

      # In test mode, cache not queried - fallback returned
      assert MovieImages.get_poster_url(movie.id, "my_fallback") == "my_fallback"
    end

    test "returns fallback when image is failed (test mode)", %{movie1: movie} do
      {:ok, _failed} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie.id,
          position: 0,
          original_url: "https://tmdb.org/poster.jpg",
          status: "failed",
          last_error: "HTTP 404",
          original_source: "tmdb"
        })

      # In test mode, cache not queried - fallback returned
      assert MovieImages.get_poster_url(movie.id, "my_fallback") == "my_fallback"
    end
  end

  describe "get_backdrop_url/2 (test environment - no cache lookup)" do
    test "returns fallback when no cached image exists", %{movie1: movie} do
      fallback = "https://tmdb.org/backdrop_fallback.jpg"
      assert MovieImages.get_backdrop_url(movie.id, fallback) == fallback
    end

    test "returns fallback even when backdrop is cached (test mode)", %{movie1: movie} do
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie.id,
          position: 1,
          original_url: "https://tmdb.org/backdrop.jpg",
          cdn_url: "https://cdn.example.com/backdrop.jpg",
          r2_key: "images/movie/backdrop.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      # In non-production, fallback is returned
      assert MovieImages.get_backdrop_url(movie.id, "fallback") == "fallback"
    end

    test "poster and backdrop both return fallbacks in test mode", %{movie1: movie} do
      # Cache both poster and backdrop
      {:ok, _poster} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie.id,
          position: 0,
          original_url: "https://tmdb.org/poster.jpg",
          cdn_url: "https://cdn.example.com/poster.jpg",
          r2_key: "images/movie/poster.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      # In test mode, both return fallbacks (cache not queried)
      assert MovieImages.get_poster_url(movie.id, "poster_fallback") == "poster_fallback"
      assert MovieImages.get_backdrop_url(movie.id, "backdrop_fallback") == "backdrop_fallback"
    end
  end

  describe "get_poster_urls/1 (test environment - no cache lookup)" do
    test "returns empty map for empty list" do
      assert MovieImages.get_poster_urls([]) == %{}
    end

    test "returns empty map in test mode (cache not queried)", %{movie1: movie1, movie2: movie2} do
      {:ok, _cached1} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie1.id,
          position: 0,
          original_url: "https://tmdb.org/poster1.jpg",
          cdn_url: "https://cdn.example.com/poster1.jpg",
          r2_key: "images/movie/poster1.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      {:ok, _cached2} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie2.id,
          position: 0,
          original_url: "https://tmdb.org/poster2.jpg",
          cdn_url: "https://cdn.example.com/poster2.jpg",
          r2_key: "images/movie/poster2.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      # In test mode, cache not queried - returns empty map
      urls = MovieImages.get_poster_urls([movie1.id, movie2.id])
      assert urls == %{}
    end
  end

  describe "get_backdrop_urls/1 (test environment - no cache lookup)" do
    test "returns empty map in test mode", %{movie1: movie1} do
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie1.id,
          position: 1,
          original_url: "https://tmdb.org/backdrop1.jpg",
          cdn_url: "https://cdn.example.com/backdrop1.jpg",
          r2_key: "images/movie/backdrop1.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      # In test mode, cache not queried
      urls = MovieImages.get_backdrop_urls([movie1.id])
      assert urls == %{}
    end
  end

  describe "get_poster_urls_with_fallbacks/1 (test environment)" do
    test "returns empty map for empty input" do
      assert MovieImages.get_poster_urls_with_fallbacks(%{}) == %{}
    end

    test "returns fallbacks directly in test mode", %{movie1: movie1, movie2: movie2} do
      # Cache movie1's poster
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie1.id,
          position: 0,
          original_url: "https://tmdb.org/poster1.jpg",
          cdn_url: "https://cdn.example.com/poster1.jpg",
          r2_key: "images/movie/poster1.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      fallbacks = %{
        movie1.id => "https://fallback1.jpg",
        movie2.id => "https://fallback2.jpg"
      }

      urls = MovieImages.get_poster_urls_with_fallbacks(fallbacks)

      # In test mode, fallbacks are returned as-is (no cache lookup)
      assert urls[movie1.id] == "https://fallback1.jpg"
      assert urls[movie2.id] == "https://fallback2.jpg"
    end

    test "preserves nil fallbacks", %{movie1: movie1} do
      fallbacks = %{movie1.id => nil}

      urls = MovieImages.get_poster_urls_with_fallbacks(fallbacks)

      assert urls[movie1.id] == nil
    end
  end

  describe "get_backdrop_urls_with_fallbacks/1 (test environment)" do
    test "returns fallbacks directly in test mode", %{movie1: movie1, movie2: movie2} do
      # Cache movie1's backdrop
      {:ok, _cached} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie1.id,
          position: 1,
          original_url: "https://tmdb.org/backdrop1.jpg",
          cdn_url: "https://cdn.example.com/backdrop1.jpg",
          r2_key: "images/movie/backdrop1.jpg",
          status: "cached",
          original_source: "tmdb"
        })

      fallbacks = %{
        movie1.id => "https://backdrop_fallback1.jpg",
        movie2.id => "https://backdrop_fallback2.jpg"
      }

      urls = MovieImages.get_backdrop_urls_with_fallbacks(fallbacks)

      # In test mode, fallbacks are returned as-is
      assert urls[movie1.id] == "https://backdrop_fallback1.jpg"
      assert urls[movie2.id] == "https://backdrop_fallback2.jpg"
    end
  end
end
