defmodule EventasaurusApp.Images.MovieImagesTest do
  @moduledoc """
  Tests for MovieImages module.

  Verifies that movie poster and backdrop URLs are correctly retrieved
  from the cached_images table with proper fallback behavior.
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

  describe "get_poster_url/2" do
    test "returns fallback when no cached image exists", %{movie1: movie} do
      fallback = "https://tmdb.org/fallback.jpg"
      assert MovieImages.get_poster_url(movie.id, fallback) == fallback
    end

    test "returns nil when no cached image and no fallback", %{movie1: movie} do
      assert MovieImages.get_poster_url(movie.id) == nil
    end

    test "returns CDN URL when poster is cached", %{movie1: movie} do
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

      assert MovieImages.get_poster_url(movie.id, "fallback") ==
               "https://cdn.example.com/poster.jpg"
    end

    test "returns original_url when image is pending", %{movie1: movie} do
      # When a cached_image record exists (even pending), ImageCacheService
      # returns its original_url as the fallback, not nil
      {:ok, _pending} =
        Repo.insert(%CachedImage{
          entity_type: "movie",
          entity_id: movie.id,
          position: 0,
          original_url: "https://tmdb.org/poster.jpg",
          status: "pending",
          original_source: "tmdb"
        })

      # Returns the original_url from the cache record, not our fallback param
      assert MovieImages.get_poster_url(movie.id, "ignored_fallback") ==
               "https://tmdb.org/poster.jpg"
    end

    test "returns original_url when image is failed", %{movie1: movie} do
      # When a cached_image record exists (even failed), ImageCacheService
      # returns its original_url as the fallback
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

      # Returns the original_url from the cache record
      assert MovieImages.get_poster_url(movie.id, "ignored_fallback") ==
               "https://tmdb.org/poster.jpg"
    end
  end

  describe "get_backdrop_url/2" do
    test "returns fallback when no cached image exists", %{movie1: movie} do
      fallback = "https://tmdb.org/backdrop_fallback.jpg"
      assert MovieImages.get_backdrop_url(movie.id, fallback) == fallback
    end

    test "returns CDN URL when backdrop is cached", %{movie1: movie} do
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

      assert MovieImages.get_backdrop_url(movie.id, "fallback") ==
               "https://cdn.example.com/backdrop.jpg"
    end

    test "distinguishes poster (position 0) from backdrop (position 1)", %{movie1: movie} do
      # Cache only the poster at position 0
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

      # Poster should return cached URL
      assert MovieImages.get_poster_url(movie.id, "poster_fallback") ==
               "https://cdn.example.com/poster.jpg"

      # Backdrop should return fallback (not cached)
      assert MovieImages.get_backdrop_url(movie.id, "backdrop_fallback") == "backdrop_fallback"
    end
  end

  describe "get_poster_urls/1" do
    test "returns empty map for empty list" do
      assert MovieImages.get_poster_urls([]) == %{}
    end

    test "returns map of movie_id => cdn_url", %{movie1: movie1, movie2: movie2} do
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

      urls = MovieImages.get_poster_urls([movie1.id, movie2.id])

      assert urls[movie1.id] == "https://cdn.example.com/poster1.jpg"
      assert urls[movie2.id] == "https://cdn.example.com/poster2.jpg"
    end

    test "excludes movies without cached images", %{movie1: movie1, movie2: movie2} do
      # Only cache movie1's poster
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

      urls = MovieImages.get_poster_urls([movie1.id, movie2.id])

      assert Map.has_key?(urls, movie1.id)
      refute Map.has_key?(urls, movie2.id)
    end
  end

  describe "get_backdrop_urls/1" do
    test "returns map of movie_id => backdrop cdn_url", %{movie1: movie1} do
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

      urls = MovieImages.get_backdrop_urls([movie1.id])

      assert urls[movie1.id] == "https://cdn.example.com/backdrop1.jpg"
    end
  end

  describe "get_poster_urls_with_fallbacks/1" do
    test "returns empty map for empty input" do
      assert MovieImages.get_poster_urls_with_fallbacks(%{}) == %{}
    end

    test "uses cached URL when available, fallback otherwise", %{movie1: movie1, movie2: movie2} do
      # Only cache movie1's poster
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

      # movie1 uses cached URL
      assert urls[movie1.id] == "https://cdn.example.com/poster1.jpg"
      # movie2 uses fallback
      assert urls[movie2.id] == "https://fallback2.jpg"
    end

    test "preserves nil fallbacks", %{movie1: movie1} do
      fallbacks = %{movie1.id => nil}

      urls = MovieImages.get_poster_urls_with_fallbacks(fallbacks)

      assert urls[movie1.id] == nil
    end
  end

  describe "get_backdrop_urls_with_fallbacks/1" do
    test "uses cached URL when available, fallback otherwise", %{movie1: movie1, movie2: movie2} do
      # Only cache movie1's backdrop
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

      # movie1 uses cached URL
      assert urls[movie1.id] == "https://cdn.example.com/backdrop1.jpg"
      # movie2 uses fallback
      assert urls[movie2.id] == "https://backdrop_fallback2.jpg"
    end
  end
end
