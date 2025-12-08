defmodule EventasaurusWeb.JsonLd.MovieSchema do
  @moduledoc """
  Generates JSON-LD structured data for movie aggregation pages according to schema.org.

  This module creates rich Movie markup that includes the movie information and
  a list of screening venues. This helps Google show rich results for movie searches.

  ## Schema.org Types
  - Movie: https://schema.org/Movie
  - ScreeningEvent: https://schema.org/ScreeningEvent
  - ItemList: https://schema.org/ItemList

  ## References
  - Google Movie Rich Results: https://developers.google.com/search/docs/appearance/structured-data/movie
  - Schema.org Movie: https://schema.org/Movie
  """

  require Logger
  alias Eventasaurus.CDN

  @doc """
  Generates JSON-LD structured data for a movie aggregation page.

  ## Parameters
    - movie: Movie struct with metadata
    - city: City struct
    - venues_with_info: List of {venue, info} tuples where info contains:
      - count: Number of showtimes
      - slug: Event slug
      - date_range: String representation of date range
      - formats: List of formats (IMAX, 3D, etc.)

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> MovieSchema.generate(movie, city, venues_with_info)
      "{\"@context\":\"https://schema.org\",\"@type\":\"Movie\",...}"
  """
  def generate(movie, city, venues_with_info) do
    movie
    |> build_movie_schema(city, venues_with_info)
    |> Jason.encode!()
  end

  @doc """
  Builds the movie schema map (without JSON encoding).
  Useful for testing or combining with other schemas.
  """
  def build_movie_schema(movie, city, venues_with_info) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Movie",
      "name" => movie.title,
      "description" => generate_description(movie, city, venues_with_info),
      "url" => build_canonical_url(movie, city)
    }
    |> add_image(movie)
    |> add_metadata(movie)
    |> add_screening_events(movie, city, venues_with_info)
  end

  # Generate SEO-friendly description
  defp generate_description(movie, city, venues_with_info) do
    venue_count = length(venues_with_info)

    total_showtimes =
      venues_with_info
      |> Enum.map(fn {_venue, info} -> info.count end)
      |> Enum.sum()

    "Watch #{movie.title} in #{city.name}. " <>
      "#{total_showtimes} showtimes available at #{venue_count} #{pluralize("cinema", venue_count)}."
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: word <> "s"

  # Build canonical URL for the movie page
  defp build_canonical_url(movie, city) do
    base_url = EventasaurusWeb.Layouts.get_base_url()
    "#{base_url}/c/#{city.slug}/movies/#{movie.slug}"
  end

  # Add movie poster/image
  defp add_image(schema, movie) do
    image_url =
      cond do
        # TMDb poster path (if available in metadata)
        movie.tmdb_metadata && movie.tmdb_metadata["poster_path"] ->
          "https://image.tmdb.org/t/p/w500#{movie.tmdb_metadata["poster_path"]}"

        # OMDb poster (if available in metadata) - check capitalized key and not N/A
        movie.metadata && is_binary(movie.metadata["Poster"]) && movie.metadata["Poster"] != "N/A" ->
          movie.metadata["Poster"]

        # Fallback to placeholder
        true ->
          movie_name_encoded = URI.encode(movie.title)
          "https://placehold.co/500x750/4ECDC4/FFFFFF?text=#{movie_name_encoded}"
      end

    # Wrap with CDN
    cdn_url = CDN.url(image_url)

    Map.put(schema, "image", cdn_url)
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
    |> maybe_add(
      "datePublished",
      tmdb_metadata["release_date"]
    )
    |> maybe_add(
      "genre",
      extract_genres(tmdb_metadata["genres"])
    )
    |> maybe_add(
      "director",
      extract_directors(tmdb_metadata["credits"])
    )
    |> maybe_add(
      "actor",
      extract_actors(tmdb_metadata["credits"])
    )
    |> maybe_add(
      "duration",
      format_duration(tmdb_metadata["runtime"])
    )
    |> maybe_add(
      "aggregateRating",
      build_tmdb_rating(tmdb_metadata)
    )
  end

  # Add metadata from OMDb API (only if not already present from TMDb)
  defp add_omdb_metadata(schema, nil), do: schema

  defp add_omdb_metadata(schema, omdb_metadata) do
    schema
    |> maybe_add_if_missing(
      "datePublished",
      omdb_metadata["Released"]
    )
    |> maybe_add_if_missing(
      "genre",
      parse_omdb_genres(omdb_metadata["Genre"])
    )
    |> maybe_add_if_missing(
      "director",
      build_person(omdb_metadata["Director"])
    )
    |> maybe_add_if_missing(
      "actor",
      parse_omdb_actors(omdb_metadata["Actors"])
    )
    |> maybe_add_if_missing(
      "duration",
      format_omdb_runtime(omdb_metadata["Runtime"])
    )
    |> maybe_add_if_missing(
      "aggregateRating",
      build_omdb_rating(omdb_metadata)
    )
  end

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

  # Format runtime in ISO 8601 duration format (e.g., "PT2H30M")
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

  # Parse OMDb genre string ("Action, Adventure, Sci-Fi")
  defp parse_omdb_genres(nil), do: nil
  defp parse_omdb_genres("N/A"), do: nil

  defp parse_omdb_genres(genre_string) when is_binary(genre_string) do
    genre_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
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

  # Format OMDb runtime ("142 min")
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
         # Parse votes (remove commas: "123,456" -> "123456")
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

  # Add screening events for this movie
  defp add_screening_events(schema, movie, city, venues_with_info) do
    # If we have screenings, add them as an ItemList
    if length(venues_with_info) > 0 do
      screening_list = %{
        "@type" => "ItemList",
        "name" => "Screenings of #{movie.title} in #{city.name}",
        "numberOfItems" => length(venues_with_info),
        "itemListElement" =>
          venues_with_info
          |> Enum.with_index(1)
          |> Enum.map(fn {{venue, info}, position} ->
            build_screening_list_item(venue, info, movie, city, position)
          end)
      }

      Map.put(schema, "potentialAction", screening_list)
    else
      schema
    end
  end

  # Build a list item for a screening venue
  defp build_screening_list_item(venue, info, _movie, city, position) do
    %{
      "@type" => "ListItem",
      "position" => position,
      "item" => %{
        "@type" => "Place",
        "@id" => build_venue_url(venue, city),
        "name" => venue.name,
        "address" => build_postal_address(venue, city),
        "url" => build_activity_url(info.slug),
        "description" => "#{info.count} #{pluralize("showtime", info.count)} available"
      }
    }
  end

  # Build venue URL
  defp build_venue_url(venue, city) do
    base_url = EventasaurusWeb.Layouts.get_base_url()
    "#{base_url}/c/#{city.slug}/venues/#{venue.slug}"
  end

  # Build activity URL for screening
  defp build_activity_url(slug) do
    base_url = EventasaurusWeb.Layouts.get_base_url()
    "#{base_url}/activities/#{slug}"
  end

  # Build PostalAddress schema
  defp build_postal_address(venue, city) do
    country_code = (city.country && city.country.code) || Map.get(city, :country_code) || "US"

    %{
      "@type" => "PostalAddress",
      "streetAddress" => venue.address || "",
      "addressLocality" => city.name,
      "addressCountry" => country_code
    }
  end

  # Helper to conditionally add a field if value is not nil
  defp maybe_add(schema, _key, nil), do: schema
  defp maybe_add(schema, _key, []), do: schema
  defp maybe_add(schema, key, value), do: Map.put(schema, key, value)

  # Helper to conditionally add a field only if it doesn't already exist
  # Used for OMDb metadata to avoid overwriting TMDb metadata
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
