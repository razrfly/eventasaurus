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

  alias Eventasaurus.CDN

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
    base_url = EventasaurusWeb.Layouts.get_base_url()

    %{
      "@context" => "https://schema.org",
      "@type" => "ItemList",
      "name" => "Movies Now Showing",
      "description" => build_description(movies),
      "url" => "#{base_url}/movies",
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

    total_cities =
      movies
      |> Enum.map(& &1.city_count)
      |> Enum.max(fn -> 0 end)

    "Discover #{total_movies} #{pluralize("movie", total_movies)} now showing in cinemas. " <>
      "#{total_screenings} screenings available across #{total_cities} #{pluralize("city", total_cities)}."
  end

  defp pluralize(word, 1), do: word
  defp pluralize("city", _), do: "cities"
  defp pluralize(word, _), do: word <> "s"

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
    base_url = EventasaurusWeb.Layouts.get_base_url()

    movie_schema =
      %{
        "@type" => "Movie",
        "name" => movie.title,
        "url" => "#{base_url}/movies/#{movie.slug}",
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
        "#{base_desc}. #{screening_count} screenings in #{city_count} #{pluralize("city", city_count)}."

      screening_count > 0 ->
        "#{base_desc}. #{screening_count} screenings available."

      true ->
        "#{base_desc}. Now showing in cinemas."
    end
  end

  # Add movie poster/image
  # Uses poster_url field directly (stored in DB), falling back to metadata paths
  defp add_image(schema, movie) do
    image_url =
      cond do
        # Direct poster_url field (stored in DB from TMDB)
        movie.poster_url && movie.poster_url != "" ->
          movie.poster_url

        # TMDb poster path in metadata (fallback)
        movie.metadata && movie.metadata["poster_path"] ->
          "https://image.tmdb.org/t/p/w500#{movie.metadata["poster_path"]}"

        # OMDb poster (if available in metadata)
        movie.metadata && is_binary(movie.metadata["Poster"]) && movie.metadata["Poster"] != "N/A" ->
          movie.metadata["Poster"]

        # No image available - don't include image field (Google requires real images)
        true ->
          nil
      end

    if image_url do
      # Wrap with CDN for CloudFlare caching
      Map.put(schema, "image", CDN.url(image_url))
    else
      schema
    end
  end

  # Add metadata from TMDb or OMDb if available
  defp add_metadata(schema, movie) do
    schema
    |> add_tmdb_metadata(movie.tmdb_metadata)
    |> add_omdb_metadata(movie.metadata)
  end

  # Add metadata from TMDb API
  defp add_tmdb_metadata(schema, nil), do: schema

  defp add_tmdb_metadata(schema, tmdb_metadata) do
    schema
    |> maybe_add("datePublished", tmdb_metadata["release_date"])
    |> maybe_add("dateCreated", tmdb_metadata["release_date"])
    |> maybe_add("genre", extract_genres(tmdb_metadata["genres"]))
    |> maybe_add("director", extract_directors(tmdb_metadata["credits"]))
    |> maybe_add("actor", extract_actors(tmdb_metadata["credits"]))
    |> maybe_add("duration", format_duration(tmdb_metadata["runtime"]))
    |> maybe_add("aggregateRating", build_tmdb_rating(tmdb_metadata))
  end

  # Add metadata from OMDb API (only if not already present from TMDb)
  defp add_omdb_metadata(schema, nil), do: schema

  defp add_omdb_metadata(schema, omdb_metadata) do
    schema
    |> maybe_add_if_missing("datePublished", omdb_metadata["Released"])
    |> maybe_add_if_missing("dateCreated", omdb_metadata["Released"])
    |> maybe_add_if_missing("genre", parse_omdb_genres(omdb_metadata["Genre"]))
    |> maybe_add_if_missing("director", build_person(omdb_metadata["Director"]))
    |> maybe_add_if_missing("actor", parse_omdb_actors(omdb_metadata["Actors"]))
    |> maybe_add_if_missing("duration", format_omdb_runtime(omdb_metadata["Runtime"]))
    |> maybe_add_if_missing("aggregateRating", build_omdb_rating(omdb_metadata))
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

  # Extract genre names from TMDb genres array
  defp extract_genres(nil), do: nil
  defp extract_genres([]), do: nil

  defp extract_genres(genres) when is_list(genres) do
    Enum.map(genres, fn genre -> genre["name"] end)
  end

  # Extract directors from TMDb credits
  defp extract_directors(nil), do: nil

  defp extract_directors(credits) do
    case get_in(credits, ["crew"]) do
      nil ->
        nil

      crew ->
        directors =
          crew
          |> Enum.filter(fn person -> person["job"] == "Director" end)
          |> Enum.map(fn person ->
            %{
              "@type" => "Person",
              "name" => person["name"]
            }
          end)

        case directors do
          [] -> nil
          [single] -> single
          multiple -> multiple
        end
    end
  end

  # Extract actors from TMDb credits
  defp extract_actors(nil), do: nil

  defp extract_actors(credits) do
    case get_in(credits, ["cast"]) do
      nil ->
        nil

      cast ->
        actors =
          cast
          |> Enum.take(10)
          |> Enum.map(fn person ->
            %{
              "@type" => "Person",
              "name" => person["name"]
            }
          end)

        case actors do
          [] -> nil
          list -> list
        end
    end
  end

  # Parse OMDb actors string
  defp parse_omdb_actors(nil), do: nil
  defp parse_omdb_actors("N/A"), do: nil

  defp parse_omdb_actors(actors_string) when is_binary(actors_string) do
    actors_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(10)
    |> Enum.map(&build_person/1)
  end

  # Build Person schema
  defp build_person(nil), do: nil
  defp build_person("N/A"), do: nil

  defp build_person(name) when is_binary(name) do
    %{
      "@type" => "Person",
      "name" => name
    }
  end

  # Format runtime in ISO 8601 duration format
  defp format_duration(nil), do: nil

  defp format_duration(runtime) when is_integer(runtime) and runtime > 0 do
    hours = div(runtime, 60)
    minutes = rem(runtime, 60)

    cond do
      hours > 0 and minutes > 0 -> "PT#{hours}H#{minutes}M"
      hours > 0 -> "PT#{hours}H"
      minutes > 0 -> "PT#{minutes}M"
      true -> nil
    end
  end

  defp format_duration(_), do: nil

  # Build TMDb aggregate rating
  defp build_tmdb_rating(nil), do: nil

  defp build_tmdb_rating(metadata) do
    vote_average = metadata["vote_average"]
    vote_count = metadata["vote_count"]

    if vote_average && vote_count && vote_count > 0 do
      %{
        "@type" => "AggregateRating",
        "ratingValue" => vote_average,
        "ratingCount" => vote_count,
        "bestRating" => 10,
        "worstRating" => 0
      }
    else
      nil
    end
  end

  # Parse OMDb genre string
  defp parse_omdb_genres(nil), do: nil
  defp parse_omdb_genres("N/A"), do: nil

  defp parse_omdb_genres(genre_string) when is_binary(genre_string) do
    genre_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Format OMDb runtime
  defp format_omdb_runtime(nil), do: nil
  defp format_omdb_runtime("N/A"), do: nil

  defp format_omdb_runtime(runtime_string) when is_binary(runtime_string) do
    case Integer.parse(runtime_string) do
      {minutes, _} -> format_duration(minutes)
      :error -> nil
    end
  end

  # Build OMDb aggregate rating
  defp build_omdb_rating(nil), do: nil

  defp build_omdb_rating(metadata) do
    imdb_rating = metadata["imdbRating"]
    imdb_votes = metadata["imdbVotes"]

    with rating when is_binary(rating) and rating != "N/A" <- imdb_rating,
         votes when is_binary(votes) and votes != "N/A" <- imdb_votes,
         {rating_float, _} <- Float.parse(rating),
         votes_clean = String.replace(votes, ",", ""),
         {votes_int, _} <- Integer.parse(votes_clean) do
      %{
        "@type" => "AggregateRating",
        "ratingValue" => rating_float,
        "ratingCount" => votes_int,
        "bestRating" => 10,
        "worstRating" => 1
      }
    else
      _ -> nil
    end
  end

  # Helper to conditionally add a field if value is not nil
  defp maybe_add(schema, _key, nil), do: schema
  defp maybe_add(schema, _key, []), do: schema
  defp maybe_add(schema, key, value), do: Map.put(schema, key, value)

  # Helper to conditionally add a field only if it doesn't already exist
  defp maybe_add_if_missing(schema, _key, nil), do: schema
  defp maybe_add_if_missing(schema, _key, []), do: schema
  defp maybe_add_if_missing(schema, _key, "N/A"), do: schema

  defp maybe_add_if_missing(schema, key, value) do
    if Map.has_key?(schema, key) do
      schema
    else
      Map.put(schema, key, value)
    end
  end
end
