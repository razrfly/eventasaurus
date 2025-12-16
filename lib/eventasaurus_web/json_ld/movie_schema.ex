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
  Generates JSON-LD structured data for a generic movie page (no specific city).

  ## Parameters
    - movie: Movie struct with metadata
    - cities_with_screenings: List of city screening info maps with:
      - city: City struct
      - screening_count: Number of screenings
      - venue_count: Number of venues
      - next_date: Next available screening date

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">
  """
  def generate_generic(movie, cities_with_screenings) do
    movie
    |> build_generic_movie_schema(cities_with_screenings)
    |> Jason.encode!()
  end

  @doc """
  Builds the generic movie schema map (without JSON encoding).
  """
  def build_generic_movie_schema(movie, cities_with_screenings) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Movie",
      "name" => movie.title,
      "description" => generate_generic_description(movie, cities_with_screenings),
      "url" => build_generic_url(movie)
    }
    |> add_image(movie)
    |> add_metadata(movie)
    |> add_city_offers(movie, cities_with_screenings)
  end

  # Generate SEO-friendly description for generic page
  defp generate_generic_description(movie, cities_with_screenings) do
    city_count = length(cities_with_screenings)

    total_screenings =
      cities_with_screenings
      |> Enum.map(& &1.screening_count)
      |> Enum.sum()

    if city_count > 0 do
      "Watch #{movie.title}. " <>
        "#{total_screenings} screenings available in #{city_count} #{pluralize("city", city_count)}."
    else
      "Watch #{movie.title}. Find showtimes near you."
    end
  end

  # Build generic URL for the movie page
  # Note: movie.slug already contains the TMDB ID in format "title-tmdb_id"
  defp build_generic_url(movie) do
    base_url = EventasaurusWeb.Layouts.get_base_url()
    "#{base_url}/movies/#{movie.slug}"
  end

  # Add city offers for generic movie page
  defp add_city_offers(schema, movie, cities_with_screenings) do
    if length(cities_with_screenings) > 0 do
      offers =
        cities_with_screenings
        |> Enum.map(fn city_info ->
          %{
            "@type" => "Offer",
            "url" => build_city_movie_url(movie, city_info.city),
            "areaServed" => %{
              "@type" => "City",
              "name" => city_info.city.name
            },
            "description" =>
              "#{city_info.screening_count} screenings at #{city_info.venue_count} venues"
          }
        end)

      Map.put(schema, "offers", offers)
    else
      schema
    end
  end

  defp build_city_movie_url(movie, city) do
    base_url = EventasaurusWeb.Layouts.get_base_url()
    "#{base_url}/c/#{city.slug}/movies/#{movie.slug}"
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
  defp pluralize("city", _), do: "cities"
  defp pluralize(word, _), do: word <> "s"

  # Build canonical URL for the movie page
  defp build_canonical_url(movie, city) do
    base_url = EventasaurusWeb.Layouts.get_base_url()
    "#{base_url}/c/#{city.slug}/movies/#{movie.slug}"
  end

  # Add movie poster/image
  # Uses poster_url field directly (stored in DB), falling back to metadata paths
  defp add_image(schema, movie) do
    case get_movie_image_url(movie) do
      nil -> schema
      image_url -> Map.put(schema, "image", CDN.url(image_url))
    end
  end

  # Add metadata from TMDb or OMDb if available
  # Also adds dateCreated from movie.release_date if not already present from metadata
  defp add_metadata(schema, movie) do
    schema
    |> add_tmdb_metadata(movie.tmdb_metadata)
    |> add_omdb_metadata(movie.metadata)
    |> maybe_add_date_from_movie(movie)
  end

  # Add datePublished and dateCreated from movie.release_date if not already present
  # This handles cases where tmdb_metadata and metadata don't have release dates
  defp maybe_add_date_from_movie(schema, %{release_date: release_date})
       when not is_nil(release_date) do
    date_string = Date.to_iso8601(release_date)

    schema
    |> maybe_add_if_missing("datePublished", date_string)
    |> maybe_add_if_missing("dateCreated", date_string)
  end

  defp maybe_add_date_from_movie(schema, _movie), do: schema

  # Add metadata from TMDb API
  defp add_tmdb_metadata(schema, nil), do: schema

  defp add_tmdb_metadata(schema, tmdb_metadata) do
    schema
    |> maybe_add(
      "datePublished",
      tmdb_metadata["release_date"]
    )
    |> maybe_add(
      "dateCreated",
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
      "dateCreated",
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

  # Add screening events for this movie as an ItemList of ScreeningEvents
  # This creates a carousel-friendly structure for Google rich results
  defp add_screening_events(schema, movie, city, venues_with_info) do
    if length(venues_with_info) > 0 do
      screening_list = %{
        "@type" => "ItemList",
        "name" => "Screenings of #{movie.title} in #{city.name}",
        "numberOfItems" => length(venues_with_info),
        "itemListElement" =>
          venues_with_info
          |> Enum.with_index(1)
          |> Enum.map(fn {{venue, info}, position} ->
            build_screening_event_item(venue, info, movie, city, position)
          end)
      }

      Map.put(schema, "subjectOf", screening_list)
    else
      schema
    end
  end

  # Build a ScreeningEvent list item for a venue
  # Each item represents the screening series at a specific cinema
  defp build_screening_event_item(venue, info, movie, city, position) do
    # Build the ScreeningEvent
    screening_event =
      %{
        "@type" => "ScreeningEvent",
        "name" => "#{movie.title} at #{venue.name}",
        "url" => build_activity_url(info.slug),
        "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
        "eventStatus" => "https://schema.org/EventScheduled",
        "description" =>
          "#{info.count} #{pluralize("showtime", info.count)} available. #{info.date_range}",
        "location" => build_movie_theater_location(venue, city),
        "workPresented" => build_work_presented(movie)
      }
      |> maybe_add_first_start_date(info)
      |> maybe_add_screening_formats(info)
      |> maybe_add_screening_image(movie)

    %{
      "@type" => "ListItem",
      "position" => position,
      "item" => screening_event
    }
  end

  # Build MovieTheater location for screening events
  defp build_movie_theater_location(venue, city) do
    location_type =
      if venue.venue_type == "cinema" do
        "MovieTheater"
      else
        "Place"
      end

    %{
      "@type" => location_type,
      "@id" => build_venue_url(venue, city),
      "name" => venue.name,
      "address" => build_postal_address(venue, city)
    }
    |> maybe_add_geo(venue)
  end

  # Add geo coordinates if available
  defp maybe_add_geo(location, venue) do
    if venue.latitude && venue.longitude do
      Map.put(location, "geo", %{
        "@type" => "GeoCoordinates",
        "latitude" => venue.latitude,
        "longitude" => venue.longitude
      })
    else
      location
    end
  end

  # Add startDate from the first available date
  defp maybe_add_first_start_date(schema, %{dates: [first_date | _]}) do
    Map.put(schema, "startDate", Date.to_iso8601(first_date))
  end

  defp maybe_add_first_start_date(schema, _), do: schema

  # Add videoFormat from screening formats
  defp maybe_add_screening_formats(schema, %{formats: formats}) when is_list(formats) do
    case formats do
      [] -> schema
      [single] -> Map.put(schema, "videoFormat", single)
      multiple -> Map.put(schema, "videoFormat", multiple)
    end
  end

  defp maybe_add_screening_formats(schema, _), do: schema

  # Build workPresented Movie reference with required image field
  # Google requires image field on all Movie objects, including nested references
  defp build_work_presented(movie) do
    base = %{
      "@type" => "Movie",
      "name" => movie.title
    }

    # Add image URL if available (required by Google for Movie type)
    image_url = get_movie_image_url(movie)

    if image_url do
      Map.put(base, "image", CDN.url(image_url))
    else
      base
    end
  end

  # Get the movie image URL from available sources
  # Shared logic used by add_image, maybe_add_screening_image, and build_work_presented
  defp get_movie_image_url(movie) do
    cond do
      # Direct poster_url field (stored in DB from TMDB)
      movie.poster_url && movie.poster_url != "" ->
        movie.poster_url

      # TMDb poster path in metadata (fallback)
      movie.metadata && movie.metadata["poster_path"] ->
        "https://image.tmdb.org/t/p/w500#{movie.metadata["poster_path"]}"

      # OMDb poster (if available in metadata)
      movie.metadata && is_binary(movie.metadata["Poster"]) &&
          movie.metadata["Poster"] != "N/A" ->
        movie.metadata["Poster"]

      true ->
        nil
    end
  end

  # Add movie image to screening event
  defp maybe_add_screening_image(schema, movie) do
    case get_movie_image_url(movie) do
      nil -> schema
      image_url -> Map.put(schema, "image", CDN.url(image_url))
    end
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
