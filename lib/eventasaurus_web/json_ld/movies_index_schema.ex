defmodule EventasaurusWeb.JsonLd.MoviesIndexSchema do
  @moduledoc """
  Generates JSON-LD structured data for the movies index page (carousel of now-showing movies).

  This module creates an ItemList schema for the movies listing page, enabling
  Google's carousel rich results for movie searches.

  ## Schema.org Types
  - ItemList: https://schema.org/ItemList
  - ListItem: https://schema.org/ListItem
  - Movie: https://schema.org/Movie

  ## References
  - Google Carousel Rich Results: https://developers.google.com/search/docs/appearance/structured-data/carousel
  - Schema.org Movie: https://schema.org/Movie
  """

  alias EventasaurusWeb.JsonLd.Helpers
  alias EventasaurusApp.Images.MovieImages

  @doc """
  Generates JSON-LD structured data for the movies index page.

  ## Parameters
    - movies: List of movie info maps from MovieStats.list_now_showing_movies/1
      Each map contains: %{movie: movie, city_count: n, screening_count: n, next_screening: date}
    - opts: Optional configuration
      - :max_items - Maximum number of movies to include (default: 20)

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> MoviesIndexSchema.generate(now_showing_movies)
      "{\"@context\":\"https://schema.org\",\"@type\":\"ItemList\",...}"
  """
  def generate(movies, opts \\ []) do
    movies
    |> build_movies_index_schema(opts)
    |> Jason.encode!()
  end

  @doc """
  Builds the movies index schema map (without JSON encoding).
  Useful for testing or combining with other schemas.
  """
  def build_movies_index_schema(movies, opts \\ []) do
    max_items = Keyword.get(opts, :max_items, 20)
    limited_movies = Enum.take(movies, max_items)

    %{
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => "Movies Now Showing",
      "description" => build_description(movies),
      "url" => Helpers.build_url("/movies"),
      "numberOfItems" => length(limited_movies),
      "itemListElement" =>
        limited_movies
        |> Enum.with_index(1)
        |> Enum.map(fn {movie_info, position} ->
          build_movie_list_item(movie_info, position)
        end)
    }
  end

  # Build SEO-friendly description for the page
  defp build_description(movies) do
    total_movies = length(movies)

    total_screenings =
      movies
      |> Enum.map(& &1.screening_count)
      |> Enum.sum()

    # Use max city_count as an approximation since we don't have unique city data
    # This represents "up to N cities" rather than exact unique count
    max_cities =
      movies
      |> Enum.map(& &1.city_count)
      |> Enum.max(fn -> 0 end)

    "Discover #{total_movies} #{Helpers.pluralize("movie", total_movies)} now showing in cinemas. " <>
      "#{total_screenings} screenings available across up to #{max_cities} #{Helpers.pluralize("city", max_cities)}."
  end

  # Build a ListItem for a movie in the carousel
  defp build_movie_list_item(
         %{
           movie: movie,
           city_count: city_count,
           screening_count: screening_count,
           next_screening: next_screening
         },
         position
       ) do
    movie_schema =
      %{
        "@type" => "Movie",
        "name" => movie.title,
        "url" => Helpers.build_url("/movies/#{movie.slug}"),
        "description" => build_movie_description(movie, city_count, screening_count)
      }
      |> add_image(movie)
      |> add_metadata(movie)
      |> maybe_add_next_screening(next_screening)

    %{
      "@type" => "ListItem",
      "position" => position,
      "item" => movie_schema
    }
  end

  # Build description for individual movie in the list
  defp build_movie_description(movie, city_count, screening_count) do
    base_desc = movie.title

    cond do
      screening_count > 0 and city_count > 0 ->
        "#{base_desc}. #{screening_count} screenings in #{city_count} #{Helpers.pluralize("city", city_count)}."

      screening_count > 0 ->
        "#{base_desc}. #{screening_count} screenings available."

      true ->
        "#{base_desc}. Now showing in cinemas."
    end
  end

  # Add movie poster/image
  # Uses cached R2 URL when available, falling back to original TMDB URL
  defp add_image(schema, movie) do
    # Try cached poster URL first (with original as fallback)
    cached_url =
      if is_integer(movie.id) do
        MovieImages.get_poster_url(movie.id, movie.poster_url)
      else
        movie.poster_url
      end

    image_url =
      cond do
        # Cached or direct poster_url
        is_binary(cached_url) && cached_url != "" ->
          cached_url

        # TMDb poster path in metadata (fallback)
        movie.metadata && is_binary(movie.metadata["poster_path"]) &&
            movie.metadata["poster_path"] != "" ->
          "https://image.tmdb.org/t/p/w500#{movie.metadata["poster_path"]}"

        # No image available - don't include image field (Google requires real images)
        true ->
          nil
      end

    Helpers.maybe_add(schema, "image", Helpers.cdn_url(image_url))
  end

  # Add metadata from TMDb if available
  defp add_metadata(schema, movie) do
    add_tmdb_metadata(schema, movie.tmdb_metadata)
  end

  # Add metadata from TMDb API
  defp add_tmdb_metadata(schema, nil), do: schema

  defp add_tmdb_metadata(schema, tmdb_metadata) do
    schema
    |> Helpers.maybe_add("datePublished", tmdb_metadata["release_date"])
    |> Helpers.maybe_add("dateCreated", tmdb_metadata["release_date"])
    |> Helpers.maybe_add("genre", Helpers.extract_genres(tmdb_metadata["genres"]))
    |> Helpers.maybe_add("director", Helpers.extract_directors(tmdb_metadata["credits"]))
    |> Helpers.maybe_add("actor", Helpers.extract_actors(tmdb_metadata["credits"]))
    |> Helpers.maybe_add("duration", Helpers.format_iso_duration(tmdb_metadata["runtime"]))
    |> Helpers.maybe_add("aggregateRating", Helpers.build_aggregate_rating(tmdb_metadata))
  end

  # Add next screening date as potentialAction
  defp maybe_add_next_screening(schema, nil), do: schema

  defp maybe_add_next_screening(schema, next_screening) do
    Map.put(schema, "potentialAction", %{
      "@type" => "WatchAction",
      "target" => schema["url"],
      "startTime" => format_date(next_screening)
    })
  end

  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
  defp format_date(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_date(_), do: nil
end
