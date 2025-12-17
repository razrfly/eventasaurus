defmodule EventasaurusWeb.JsonLd.MoviesIndexSchemaTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.JsonLd.MoviesIndexSchema

  # Create test movie data
  defp build_movie(attrs \\ %{}) do
    defaults = %{
      id: 1,
      title: "Test Movie",
      slug: "test-movie-12345",
      poster_url: "https://image.tmdb.org/t/p/w500/test-poster.jpg",
      tmdb_metadata: %{
        "poster_path" => "/test-poster.jpg",
        "release_date" => "2024-01-15",
        "genres" => [%{"name" => "Action"}, %{"name" => "Drama"}],
        "runtime" => 120,
        "vote_average" => 7.5,
        "vote_count" => 1000
      },
      metadata: nil
    }

    struct = Map.merge(defaults, attrs)
    # Convert to struct-like map with atom keys
    struct
  end

  defp build_movie_info(movie, attrs \\ %{}) do
    defaults = %{
      movie: movie,
      city_count: 3,
      screening_count: 50,
      next_screening: ~D[2024-01-20]
    }

    Map.merge(defaults, attrs)
  end

  describe "generate/2" do
    test "returns valid JSON string" do
      movie = build_movie()
      movies = [build_movie_info(movie)]

      result = MoviesIndexSchema.generate(movies)

      assert is_binary(result)
      assert {:ok, _} = Jason.decode(result)
    end

    test "includes @context and @type" do
      movie = build_movie()
      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "ItemList"
    end
  end

  describe "build_movies_index_schema/2" do
    test "includes list name and description" do
      movie = build_movie()
      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)

      assert schema["name"] == "Movies Now Showing"
      assert is_binary(schema["description"])
      assert String.contains?(schema["description"], "now showing")
    end

    test "includes correct numberOfItems" do
      movies =
        1..5
        |> Enum.map(fn i ->
          movie = build_movie(%{id: i, title: "Movie #{i}", slug: "movie-#{i}"})
          build_movie_info(movie)
        end)

      schema = MoviesIndexSchema.build_movies_index_schema(movies)

      assert schema["numberOfItems"] == 5
    end

    test "respects max_items option" do
      movies =
        1..10
        |> Enum.map(fn i ->
          movie = build_movie(%{id: i, title: "Movie #{i}", slug: "movie-#{i}"})
          build_movie_info(movie)
        end)

      schema = MoviesIndexSchema.build_movies_index_schema(movies, max_items: 3)

      assert schema["numberOfItems"] == 3
      assert length(schema["itemListElement"]) == 3
    end

    test "includes URL to movies index page" do
      movies = [build_movie_info(build_movie())]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)

      assert String.ends_with?(schema["url"], "/movies")
    end
  end

  describe "itemListElement (movie carousel)" do
    test "each item is a ListItem with correct position" do
      movies =
        1..3
        |> Enum.map(fn i ->
          movie = build_movie(%{id: i, title: "Movie #{i}", slug: "movie-#{i}"})
          build_movie_info(movie)
        end)

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      items = schema["itemListElement"]

      assert length(items) == 3

      Enum.each(Enum.with_index(items, 1), fn {item, expected_position} ->
        assert item["@type"] == "ListItem"
        assert item["position"] == expected_position
      end)
    end

    test "each item contains a Movie schema" do
      movie = build_movie(%{title: "Inception"})
      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["@type"] == "Movie"
      assert item["item"]["name"] == "Inception"
    end

    test "movie includes URL" do
      movie = build_movie(%{slug: "inception-12345"})
      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert String.ends_with?(item["item"]["url"], "/movies/inception-12345")
    end

    test "movie includes image from poster_url" do
      movie = build_movie(%{poster_url: "https://image.tmdb.org/t/p/w500/abc123.jpg"})
      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      # Should include the poster URL (possibly CDN-wrapped)
      assert item["item"]["image"] != nil
      assert String.contains?(item["item"]["image"], "abc123.jpg")
    end

    test "movie includes description with city and screening counts" do
      movie = build_movie(%{title: "Test Movie"})
      movies = [build_movie_info(movie, %{city_count: 5, screening_count: 100})]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert String.contains?(item["item"]["description"], "100 screenings")
      assert String.contains?(item["item"]["description"], "5 cities")
    end
  end

  describe "movie metadata" do
    test "includes datePublished from TMDb" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "release_date" => "2024-03-15",
            "poster_path" => "/test.jpg"
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["datePublished"] == "2024-03-15"
    end

    test "includes dateCreated from TMDb (Google optional field)" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "release_date" => "2024-03-15",
            "poster_path" => "/test.jpg"
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["dateCreated"] == "2024-03-15"
    end

    test "includes director from TMDb credits" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "poster_path" => "/test.jpg",
            "credits" => %{
              "crew" => [
                %{"job" => "Director", "name" => "Christopher Nolan"},
                %{"job" => "Producer", "name" => "Emma Thomas"}
              ]
            }
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["director"]["@type"] == "Person"
      assert item["item"]["director"]["name"] == "Christopher Nolan"
    end

    test "includes multiple directors as array" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "poster_path" => "/test.jpg",
            "credits" => %{
              "crew" => [
                %{"job" => "Director", "name" => "The Russo Brothers"},
                %{"job" => "Director", "name" => "Anthony Russo"}
              ]
            }
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert is_list(item["item"]["director"])
      assert length(item["item"]["director"]) == 2
    end

    test "includes actor from TMDb credits" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "poster_path" => "/test.jpg",
            "credits" => %{
              "cast" => [
                %{"name" => "Leonardo DiCaprio"},
                %{"name" => "Marion Cotillard"}
              ]
            }
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert is_list(item["item"]["actor"])
      assert Enum.at(item["item"]["actor"], 0)["@type"] == "Person"
      assert Enum.at(item["item"]["actor"], 0)["name"] == "Leonardo DiCaprio"
    end

    test "includes genre from TMDb" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "genres" => [%{"name" => "Sci-Fi"}, %{"name" => "Thriller"}],
            "poster_path" => "/test.jpg"
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["genre"] == ["Sci-Fi", "Thriller"]
    end

    test "includes duration in ISO 8601 format" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "runtime" => 142,
            "poster_path" => "/test.jpg"
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["duration"] == "PT2H22M"
    end

    test "includes aggregateRating from TMDb" do
      movie =
        build_movie(%{
          tmdb_metadata: %{
            "vote_average" => 8.2,
            "vote_count" => 5000,
            "poster_path" => "/test.jpg"
          }
        })

      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["aggregateRating"]["@type"] == "AggregateRating"
      assert item["item"]["aggregateRating"]["ratingValue"] == 8.2
      assert item["item"]["aggregateRating"]["ratingCount"] == 5000
    end
  end

  describe "potentialAction (next screening)" do
    test "includes WatchAction with next screening date" do
      movie = build_movie()
      movies = [build_movie_info(movie, %{next_screening: ~D[2024-02-15]})]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["potentialAction"]["@type"] == "WatchAction"
      assert item["item"]["potentialAction"]["startTime"] == "2024-02-15"
    end

    test "omits potentialAction when next_screening is nil" do
      movie = build_movie()
      movies = [build_movie_info(movie, %{next_screening: nil})]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      refute Map.has_key?(item["item"], "potentialAction")
    end
  end

  describe "edge cases" do
    test "handles empty movie list" do
      schema = MoviesIndexSchema.build_movies_index_schema([])

      assert schema["@type"] == "ItemList"
      assert schema["numberOfItems"] == 0
      assert schema["itemListElement"] == []
    end

    test "handles movie with no metadata" do
      movie = build_movie(%{poster_url: nil, tmdb_metadata: nil, metadata: nil})
      movies = [build_movie_info(movie)]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      assert item["item"]["@type"] == "Movie"
      assert item["item"]["name"] == "Test Movie"
      # No image, rating, etc. when no metadata
      refute Map.has_key?(item["item"], "image")
      refute Map.has_key?(item["item"], "aggregateRating")
    end

    test "handles movie with zero screening count" do
      movie = build_movie()
      movies = [build_movie_info(movie, %{screening_count: 0, city_count: 0})]

      schema = MoviesIndexSchema.build_movies_index_schema(movies)
      [item] = schema["itemListElement"]

      # Should still generate valid schema
      assert item["item"]["@type"] == "Movie"
      assert String.contains?(item["item"]["description"], "Now showing")
    end
  end
end
