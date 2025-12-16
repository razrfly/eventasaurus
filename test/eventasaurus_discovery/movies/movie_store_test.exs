defmodule EventasaurusDiscovery.Movies.MovieStoreTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Movies.{Movie, MovieStore}

  describe "create_movie/1" do
    test "creates a movie with valid attributes" do
      attrs = %{
        tmdb_id: 550,
        title: "Fight Club",
        original_title: "Fight Club",
        overview: "A ticking-time-bomb insomniac and a slippery soap salesman...",
        poster_url: "https://image.tmdb.org/t/p/w500/poster.jpg",
        backdrop_url: "https://image.tmdb.org/t/p/w1280/backdrop.jpg",
        release_date: ~D[1999-10-15],
        runtime: 139,
        metadata: %{vote_average: 8.4, vote_count: 26000}
      }

      assert {:ok, %Movie{} = movie} = MovieStore.create_movie(attrs)
      assert movie.tmdb_id == 550
      assert movie.title == "Fight Club"
      assert movie.slug =~ "fight-club"
      assert movie.runtime == 139
    end

    test "requires tmdb_id and title" do
      assert {:error, changeset} = MovieStore.create_movie(%{})
      assert "can't be blank" in errors_on(changeset).tmdb_id
      assert "can't be blank" in errors_on(changeset).title
    end

    test "generates unique slug for duplicate titles" do
      attrs = %{tmdb_id: 1, title: "The Matrix"}

      {:ok, movie1} = MovieStore.create_movie(attrs)
      {:ok, movie2} = MovieStore.create_movie(Map.put(attrs, :tmdb_id, 2))

      assert movie1.slug != movie2.slug
      assert movie1.slug =~ "the-matrix"
      assert movie2.slug =~ "the-matrix"
    end

    test "sanitizes UTF-8 in text fields" do
      attrs = %{
        tmdb_id: 999,
        title: "Movie with \xED\xA0\x80 invalid UTF-8",
        overview: "Overview with \xED\xA0\x80 invalid UTF-8"
      }

      assert {:ok, movie} = MovieStore.create_movie(attrs)
      # UTF-8 should be sanitized
      assert is_binary(movie.title)
      assert is_binary(movie.overview)
    end

    test "handles tmdb_id passed as single-element list" do
      # Bug fix: tmdb_id sometimes arrives as [id] instead of id
      # This can happen due to upstream data formatting issues
      attrs = %{
        tmdb_id: [1_280_941],
        title: "The Boy with Pink Pants"
      }

      assert {:ok, %Movie{} = movie} = MovieStore.create_movie(attrs)
      assert movie.tmdb_id == 1_280_941
      assert movie.title == "The Boy with Pink Pants"
      assert movie.slug =~ "the-boy-with-pink-pants"
    end

    test "handles tmdb_id passed as string" do
      attrs = %{
        tmdb_id: "550",
        title: "Fight Club"
      }

      assert {:ok, %Movie{} = movie} = MovieStore.create_movie(attrs)
      assert movie.tmdb_id == 550
      assert movie.title == "Fight Club"
    end

    test "handles tmdb_id passed as string in single-element list" do
      attrs = %{
        tmdb_id: ["550"],
        title: "Fight Club"
      }

      assert {:ok, %Movie{} = movie} = MovieStore.create_movie(attrs)
      assert movie.tmdb_id == 550
      assert movie.title == "Fight Club"
    end
  end

  describe "find_or_create_by_tmdb_id/2" do
    test "creates new movie if it doesn't exist" do
      attrs = %{
        title: "Inception",
        overview: "A thief who steals corporate secrets...",
        runtime: 148
      }

      assert {:ok, %Movie{} = movie} = MovieStore.find_or_create_by_tmdb_id(27205, attrs)
      assert movie.tmdb_id == 27205
      assert movie.title == "Inception"
    end

    test "returns existing movie if tmdb_id already exists" do
      attrs = %{tmdb_id: 550, title: "Fight Club"}
      {:ok, existing_movie} = MovieStore.create_movie(attrs)

      # Try to create with same TMDB ID but different title
      new_attrs = %{title: "Different Title"}
      assert {:ok, found_movie} = MovieStore.find_or_create_by_tmdb_id(550, new_attrs)

      # Should return the existing movie, not create a new one
      assert found_movie.id == existing_movie.id
      assert found_movie.title == "Fight Club"
    end

    test "deduplicates movies by TMDB ID" do
      # Create first movie
      {:ok, _movie1} = MovieStore.find_or_create_by_tmdb_id(100, %{title: "Movie 1"})

      # Count movies before second call
      count_before = length(MovieStore.list_movies())

      # Try to create same movie again
      {:ok, _movie2} = MovieStore.find_or_create_by_tmdb_id(100, %{title: "Movie 1"})

      # Count should be the same
      count_after = length(MovieStore.list_movies())
      assert count_before == count_after
    end
  end

  describe "update_movie/2" do
    test "updates movie attributes" do
      {:ok, movie} = MovieStore.create_movie(%{tmdb_id: 101, title: "Original Title"})

      update_attrs = %{
        title: "Updated Title",
        runtime: 120
      }

      assert {:ok, updated_movie} = MovieStore.update_movie(movie, update_attrs)
      assert updated_movie.id == movie.id
      assert updated_movie.title == "Updated Title"
      assert updated_movie.runtime == 120
    end
  end

  describe "get_movie_by_slug/1" do
    test "returns movie when slug exists" do
      {:ok, movie} = MovieStore.create_movie(%{tmdb_id: 102, title: "Interstellar"})

      found_movie = MovieStore.get_movie_by_slug(movie.slug)
      assert found_movie.id == movie.id
      assert found_movie.title == "Interstellar"
    end

    test "returns nil when slug doesn't exist" do
      assert nil == MovieStore.get_movie_by_slug("nonexistent-slug")
    end
  end

  describe "get_movie_by_tmdb_id/1" do
    test "returns movie when tmdb_id exists" do
      {:ok, movie} = MovieStore.create_movie(%{tmdb_id: 103, title: "The Dark Knight"})

      found_movie = MovieStore.get_movie_by_tmdb_id(103)
      assert found_movie.id == movie.id
      assert found_movie.tmdb_id == 103
    end

    test "returns nil when tmdb_id doesn't exist" do
      assert nil == MovieStore.get_movie_by_tmdb_id(99999)
    end
  end

  describe "list_movies/1" do
    test "returns list of movies with default options" do
      {:ok, _movie1} = MovieStore.create_movie(%{tmdb_id: 1, title: "Movie 1"})
      {:ok, _movie2} = MovieStore.create_movie(%{tmdb_id: 2, title: "Movie 2"})

      movies = MovieStore.list_movies()
      assert length(movies) == 2
    end

    test "respects limit option" do
      for i <- 1..10 do
        MovieStore.create_movie(%{tmdb_id: i, title: "Movie #{i}"})
      end

      movies = MovieStore.list_movies(limit: 5)
      assert length(movies) == 5
    end

    test "respects offset option" do
      {:ok, movie1} = MovieStore.create_movie(%{tmdb_id: 1, title: "Movie 1"})
      {:ok, movie2} = MovieStore.create_movie(%{tmdb_id: 2, title: "Movie 2"})
      {:ok, movie3} = MovieStore.create_movie(%{tmdb_id: 3, title: "Movie 3"})

      # Get movies with offset 1
      movies = MovieStore.list_movies(offset: 1, order_by: :id, order_direction: :asc)
      assert length(movies) == 2
      assert hd(movies).id == movie2.id
    end

    test "orders by specified field and direction" do
      {:ok, _movie1} = MovieStore.create_movie(%{tmdb_id: 1, title: "Zebra Movie"})
      {:ok, _movie2} = MovieStore.create_movie(%{tmdb_id: 2, title: "Alpha Movie"})

      movies = MovieStore.list_movies(order_by: :title, order_direction: :asc)
      assert hd(movies).title == "Alpha Movie"
    end
  end

  describe "delete_movie/1" do
    test "deletes a movie" do
      {:ok, movie} = MovieStore.create_movie(%{tmdb_id: 999, title: "To Be Deleted"})

      assert {:ok, deleted_movie} = MovieStore.delete_movie(movie)
      assert deleted_movie.id == movie.id

      # Verify it's actually deleted
      assert nil == MovieStore.get_movie_by_tmdb_id(999)
    end
  end
end
