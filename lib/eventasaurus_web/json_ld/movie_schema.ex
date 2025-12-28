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

  alias EventasaurusWeb.JsonLd.Helpers
  alias EventasaurusApp.Images.MovieImages

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
        "#{total_screenings} screenings available in #{city_count} #{Helpers.pluralize("city", city_count)}."
    else
      "Watch #{movie.title}. Find showtimes near you."
    end
  end

  # Build generic URL for the movie page
  # Note: movie.slug already contains the TMDB ID in format "title-tmdb_id"
  defp build_generic_url(movie) do
    Helpers.build_url("/movies/#{movie.slug}")
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
    Helpers.build_url("/c/#{city.slug}/movies/#{movie.slug}")
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
      "#{total_showtimes} showtimes available at #{venue_count} #{Helpers.pluralize("cinema", venue_count)}."
  end

  # Build canonical URL for the movie page
  defp build_canonical_url(movie, city) do
    Helpers.build_url("/c/#{city.slug}/movies/#{movie.slug}")
  end

  # Add movie poster/image
  # Uses poster_url field directly (stored in DB), falling back to metadata paths
  defp add_image(schema, movie) do
    case get_movie_image_url(movie) do
      nil -> schema
      image_url -> Helpers.maybe_add(schema, "image", Helpers.cdn_url(image_url))
    end
  end

  # Add metadata from TMDb if available
  # Also adds dateCreated from movie.release_date if not already present from metadata
  defp add_metadata(schema, movie) do
    schema
    |> add_tmdb_metadata(movie.tmdb_metadata)
    |> maybe_add_date_from_movie(movie)
  end

  # Add datePublished and dateCreated from movie.release_date if not already present
  # This handles cases where tmdb_metadata and metadata don't have release dates
  defp maybe_add_date_from_movie(schema, %{release_date: release_date})
       when not is_nil(release_date) do
    date_string = Date.to_iso8601(release_date)

    schema
    |> Helpers.maybe_add_if_missing("datePublished", date_string)
    |> Helpers.maybe_add_if_missing("dateCreated", date_string)
  end

  defp maybe_add_date_from_movie(schema, _movie), do: schema

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
          "#{info.count} #{Helpers.pluralize("showtime", info.count)} available. #{info.date_range}",
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
      "address" => Helpers.build_postal_address(venue, city)
    }
    |> Helpers.add_geo_coordinates(venue)
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

  # Build workPresented Movie reference with required/recommended fields
  # Google validates ALL Movie objects including nested references, so we need:
  # - image (required)
  # - dateCreated (optional but recommended)
  # - director (optional but recommended)
  defp build_work_presented(movie) do
    base = %{
      "@type" => "Movie",
      "name" => movie.title
    }

    # Add image URL if available (required by Google for Movie type)
    image_url = get_movie_image_url(movie)

    base =
      if image_url do
        Helpers.maybe_add(base, "image", Helpers.cdn_url(image_url))
      else
        base
      end

    # Add dateCreated from release_date (Google optional field)
    base =
      if movie.release_date do
        Map.put(base, "dateCreated", Date.to_iso8601(movie.release_date))
      else
        base
      end

    # Add director from tmdb_metadata if available
    base =
      if movie.tmdb_metadata do
        director = Helpers.extract_directors(movie.tmdb_metadata["credits"])
        Helpers.maybe_add(base, "director", director)
      else
        base
      end

    base
  end

  # Get the movie image URL from available sources
  # Shared logic used by add_image, maybe_add_screening_image, and build_work_presented
  # Uses cached R2 URL when available, falling back to original TMDB URL
  defp get_movie_image_url(movie) do
    # Try cached poster URL first (with original as fallback)
    cached_url =
      if is_integer(movie.id) do
        MovieImages.get_poster_url(movie.id, movie.poster_url)
      else
        movie.poster_url
      end

    cond do
      # Cached or direct poster_url
      is_binary(cached_url) && cached_url != "" ->
        cached_url

      # TMDb poster path in metadata (fallback)
      movie.metadata && is_binary(movie.metadata["poster_path"]) &&
          movie.metadata["poster_path"] != "" ->
        "https://image.tmdb.org/t/p/w500#{movie.metadata["poster_path"]}"

      true ->
        nil
    end
  end

  # Add movie image to screening event
  defp maybe_add_screening_image(schema, movie) do
    case get_movie_image_url(movie) do
      nil -> schema
      image_url -> Helpers.maybe_add(schema, "image", Helpers.cdn_url(image_url))
    end
  end

  # Build venue URL
  defp build_venue_url(venue, city) do
    Helpers.build_url("/c/#{city.slug}/venues/#{venue.slug}")
  end

  # Build activity URL for screening
  defp build_activity_url(slug) do
    Helpers.build_url("/activities/#{slug}")
  end
end
