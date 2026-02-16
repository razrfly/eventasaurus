defmodule EventasaurusWeb.JsonLd.PublicEventSchema do
  @moduledoc """
  Generates JSON-LD structured data for public events according to schema.org and Google guidelines.

  This module converts public event data into properly formatted structured data
  for better SEO and Google rich results.

  ## Schema.org Event Types

  Supports all 21 schema.org Event subtypes:
  - MusicEvent, TheaterEvent, ComedyEvent, DanceEvent, SportsEvent
  - ScreeningEvent, FoodEvent, BusinessEvent, EducationEvent
  - ExhibitionEvent, Festival, LiteraryEvent, SocialEvent
  - VisualArtsEvent, ChildrensEvent, and more

  ## References
  - Schema.org Event: https://schema.org/Event
  - Google Event Rich Results: https://developers.google.com/search/docs/appearance/structured-data/event
  """

  require Logger
  alias Eventasaurus.CDN
  alias EventasaurusApp.Images.{EventSourceImages, MovieImages}
  alias EventasaurusWeb.Helpers.SourceAttribution
  alias EventasaurusWeb.JsonLd.Helpers

  @doc """
  Generates JSON-LD structured data for a public event.

  ## Parameters
    - event: PublicEvent struct with preloaded associations:
      - :venue (with :city_ref)
      - :categories
      - :performers
      - :movies
      - :sources (with :source)

  ## Returns
    - JSON-LD string ready to be included in <script type="application/ld+json">

  ## Example
      iex> event = Repo.get(PublicEvent, 1) |> Repo.preload([:venue, :categories, :performers, :movies, sources: :source])
      iex> EventasaurusWeb.JsonLd.PublicEventSchema.generate(event)
      "{\"@context\":\"https://schema.org\",\"@type\":\"MusicEvent\",...}"
  """
  def generate(event) do
    event
    |> build_event_schema()
    |> Jason.encode!()
  end

  @doc """
  Generates JSON-LD for multiple ScreeningEvents when occurrences are provided.

  For movie screenings with multiple showtimes, Google recommends adding a separate
  Event element for each performance. This function generates an array of ScreeningEvents,
  one per occurrence/showtime.

  ## Parameters
    - event: PublicEvent struct with preloaded associations
    - occurrences: List of occurrence maps with :datetime, :label, :external_id

  ## Returns
    - JSON-LD string with array of ScreeningEvents (if multiple)
    - Single ScreeningEvent JSON-LD (if one occurrence)
    - Falls back to regular generate/1 (if no occurrences)
  """
  def generate_with_occurrences(event, nil), do: generate(event)
  def generate_with_occurrences(event, []), do: generate(event)

  def generate_with_occurrences(event, occurrences) when is_list(occurrences) do
    # Only generate multiple schemas for ScreeningEvents (movies)
    if determine_event_type(event) == "ScreeningEvent" do
      schemas =
        occurrences
        |> Enum.map(fn occurrence ->
          build_screening_event_for_occurrence(event, occurrence)
        end)

      # Return array if multiple, single object if one
      case schemas do
        [single] -> Jason.encode!(single)
        multiple -> Jason.encode!(multiple)
      end
    else
      # Non-movie events: just use regular single schema
      generate(event)
    end
  end

  # Build a ScreeningEvent schema for a specific occurrence
  defp build_screening_event_for_occurrence(event, occurrence) do
    %{
      "@context" => "https://schema.org",
      "@type" => "ScreeningEvent",
      "name" => get_event_name(event),
      "startDate" => DateTime.to_iso8601(occurrence.datetime),
      "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
      "eventStatus" => "https://schema.org/EventScheduled"
    }
    |> maybe_add_location(event.venue)
    |> add_description(event)
    |> add_images(event)
    |> add_offers(event)
    |> add_organizer(event)
    |> add_work_presented(event)
    |> maybe_add_video_format_from_occurrence(occurrence)
  end

  # Add videoFormat from occurrence label (e.g., "3D", "IMAX", "Dolby")
  defp maybe_add_video_format_from_occurrence(schema, %{label: label}) when is_binary(label) do
    format = extract_video_format_from_label(label)

    if format do
      Map.put(schema, "videoFormat", format)
    else
      schema
    end
  end

  defp maybe_add_video_format_from_occurrence(schema, _), do: schema

  # Extract video format from occurrence label string
  # Common labels: "3D", "IMAX", "4DX", "Dolby Atmos", "2D", etc.
  defp extract_video_format_from_label(label) when is_binary(label) do
    label_upper = String.upcase(label)

    formats =
      []
      |> maybe_append(String.contains?(label_upper, "3D"), "3D")
      |> maybe_append(String.contains?(label_upper, "IMAX"), "IMAX")
      |> maybe_append(String.contains?(label_upper, "4DX"), "4DX")
      |> maybe_append(String.contains?(label_upper, "DOLBY"), "Dolby")

    case formats do
      [] -> nil
      [single] -> single
      multiple -> multiple
    end
  end

  defp extract_video_format_from_label(_), do: nil

  @doc """
  Builds the event schema map (without JSON encoding).
  Useful for testing or combining with other schemas.
  """
  def build_event_schema(event) do
    %{
      "@context" => "https://schema.org",
      "@type" => determine_event_type(event),
      "name" => get_event_name(event),
      "startDate" => DateTime.to_iso8601(event.starts_at),
      "eventAttendanceMode" => "https://schema.org/OfflineEventAttendanceMode",
      "eventStatus" => "https://schema.org/EventScheduled"
    }
    |> maybe_add_location(event.venue)
    |> add_end_date(event.ends_at)
    |> add_description(event)
    |> add_images(event)
    |> add_offers(event)
    |> add_performers(event)
    |> add_organizer(event)
    |> add_work_presented(event)
  end

  # Determine the appropriate schema.org Event type
  defp determine_event_type(event) do
    cond do
      # Use primary category if available
      has_primary_category?(event) ->
        get_primary_category_schema_type(event)

      # Fall back to first category
      has_categories?(event) ->
        get_first_category_schema_type(event)

      # Fall back to source domain
      has_sources?(event) ->
        get_source_schema_type(event)

      # Ultimate fallback
      true ->
        "Event"
    end
  end

  defp has_primary_category?(event) do
    event.primary_category_id && event.categories != []
  end

  defp get_primary_category_schema_type(event) do
    event.categories
    |> Enum.find(&(&1.id == event.primary_category_id))
    |> case do
      nil -> "Event"
      category -> category.schema_type || "Event"
    end
  end

  defp has_categories?(event) do
    event.categories && event.categories != []
  end

  defp get_first_category_schema_type(event) do
    event.categories
    |> List.first()
    |> case do
      nil -> "Event"
      category -> category.schema_type || "Event"
    end
  end

  defp has_sources?(event) do
    event.sources && event.sources != []
  end

  defp get_source_schema_type(event) do
    event.sources
    |> List.first()
    |> case do
      nil ->
        "Event"

      source ->
        source_domains =
          get_in(source, [Access.key(:source), Access.key(:domains)]) || ["general"]

        domain_to_schema_type(List.first(source_domains))
    end
  end

  @doc """
  Maps source domain to schema.org Event type.

  ## Examples
      iex> EventasaurusWeb.JsonLd.PublicEventSchema.domain_to_schema_type("music")
      "MusicEvent"

      iex> EventasaurusWeb.JsonLd.PublicEventSchema.domain_to_schema_type("unknown")
      "Event"
  """
  def domain_to_schema_type(domain) when is_binary(domain) do
    case domain do
      "music" -> "MusicEvent"
      "concert" -> "MusicEvent"
      "sports" -> "SportsEvent"
      "theater" -> "TheaterEvent"
      "comedy" -> "ComedyEvent"
      "dance" -> "DanceEvent"
      "food" -> "FoodEvent"
      "business" -> "BusinessEvent"
      "education" -> "EducationEvent"
      "exhibition" -> "ExhibitionEvent"
      "festival" -> "Festival"
      "literary" -> "LiteraryEvent"
      "screening" -> "ScreeningEvent"
      "movies" -> "ScreeningEvent"
      "cinema" -> "ScreeningEvent"
      "social" -> "SocialEvent"
      "visual-arts" -> "VisualArtsEvent"
      "trivia" -> "SocialEvent"
      "cultural" -> "Event"
      "general" -> "Event"
      _ -> "Event"
    end
  end

  def domain_to_schema_type(_), do: "Event"

  # Get event name, preferring English translation if available
  defp get_event_name(event) do
    cond do
      event.title && event.title != "" ->
        event.title

      event.title_translations && is_map(event.title_translations) ->
        event.title_translations["en"] || event.title || "Event"

      true ->
        "Event"
    end
  end

  # Add location to schema if venue exists
  defp maybe_add_location(schema, nil), do: schema

  defp maybe_add_location(schema, venue) do
    event_type = schema["@type"]
    Map.put(schema, "location", build_location(venue, event_type))
  end

  # Build schema.org Place or MovieTheater object for venue location
  # Use MovieTheater for ScreeningEvents (cinema venues)
  defp build_location(venue, "ScreeningEvent") do
    %{
      "@type" => "MovieTheater",
      "name" => venue.name,
      "address" => Helpers.build_postal_address(venue, venue.city_ref)
    }
    |> Helpers.add_geo_coordinates(venue)
  end

  defp build_location(venue, _event_type) do
    %{
      "@type" => "Place",
      "name" => venue.name,
      "address" => Helpers.build_postal_address(venue, venue.city_ref)
    }
    |> Helpers.add_geo_coordinates(venue)
  end

  # Add end date if available
  defp add_end_date(schema, nil), do: schema

  defp add_end_date(schema, ends_at) do
    Map.put(schema, "endDate", DateTime.to_iso8601(ends_at))
  end

  # Add description from event sources
  defp add_description(schema, event) do
    description = get_event_description(event)

    # Use source description if available, otherwise generate fallback
    final_description =
      if description && description != "" do
        description
      else
        generate_fallback_description(event)
      end

    if final_description && final_description != "" do
      Map.put(schema, "description", String.slice(final_description, 0, 5000))
    else
      schema
    end
  end

  # Get event description from sources
  defp get_event_description(event) do
    cond do
      event.sources && event.sources != [] ->
        source = List.first(event.sources)

        cond do
          source.description_translations && is_map(source.description_translations) ->
            source.description_translations["en"] || ""

          true ->
            ""
        end

      true ->
        ""
    end
  end

  # Generate a fallback description when no source description is available
  # Uses performers, venue, and event type to create a meaningful description
  defp generate_fallback_description(event) do
    parts = []

    # Add performers if available (guard against NotLoaded association)
    parts =
      if has_loaded_performers?(event) do
        performer_names = Enum.map(event.performers, & &1.name)
        performer_text = format_list(performer_names)
        parts ++ [performer_text]
      else
        parts
      end

    # Add event type from category
    parts =
      if event.categories && event.categories != [] do
        category = List.first(event.categories)
        event_type = category.name || "event"
        parts ++ [event_type]
      else
        parts ++ ["event"]
      end

    # Add venue information
    parts =
      if event.venue do
        venue_parts = []

        venue_parts =
          if event.venue.name do
            venue_parts ++ ["at #{event.venue.name}"]
          else
            venue_parts
          end

        venue_parts =
          if event.venue.city_ref && event.venue.city_ref.name do
            venue_parts ++ ["in #{event.venue.city_ref.name}"]
          else
            venue_parts
          end

        parts ++ venue_parts
      else
        parts
      end

    # Construct the description
    # Check if we have performers (first element will be a string from format_list)
    has_performers = has_loaded_performers?(event)

    case {has_performers, parts} do
      {true, [performers, event_type | venue_info]} ->
        # With performers: "Artist Name performing music event at Venue in City"
        venue_text = Enum.join(venue_info, " ")

        if venue_text != "" do
          "#{performers} performing #{event_type} #{venue_text}."
        else
          "#{performers} performing #{event_type}."
        end

      {false, [event_type | venue_info]} ->
        # Without performers: "Music event at Venue in City"
        venue_text = Enum.join(venue_info, " ")

        if venue_text != "" do
          "#{String.capitalize(event_type)} #{venue_text}."
        else
          String.capitalize(event_type) <> "."
        end

      _ ->
        # Fallback for unexpected patterns
        nil
    end
  end

  # Format a list of items with proper grammar (e.g., "A, B, and C")
  defp format_list([]), do: nil
  defp format_list([single]), do: single

  defp format_list([first, second]) do
    "#{first} and #{second}"
  end

  defp format_list(items) when length(items) > 2 do
    {last, rest} = List.pop_at(items, -1)
    Enum.join(rest, ", ") <> ", and #{last}"
  end

  # Add images from event, venue, and movies
  defp add_images(schema, event) do
    images = collect_images(event)

    if Enum.any?(images) do
      Map.put(schema, "image", images)
    else
      # Add a placeholder image with event name
      event_name = URI.encode(get_event_name(event))
      Map.put(schema, "image", ["https://placehold.co/1200x630/4ECDC4/FFFFFF?text=#{event_name}"])
    end
  end

  # Collect all available images for the event
  # JSON-LD images should be high quality for rich snippets
  @json_ld_image_opts [width: 1200, height: 630, quality: 85, fit: "cover"]

  defp collect_images(event) do
    []
    |> add_event_images(event)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.take(5)
    # Wrap all images with Cloudflare CDN with proper transformation parameters
    |> Enum.map(&CDN.url(&1, @json_ld_image_opts))
  end

  # Extract images from event sources
  # Uses EventSourceImages for cached R2 URLs when available
  defp add_event_images(images, event) do
    if event.sources && event.sources != [] do
      # Get images from all sources, prioritizing by source priority and recency
      # Deduplicate sources first to avoid duplicate images from multiple showtimes
      deduplicated_sources =
        event.sources
        |> SourceAttribution.deduplicate_sources()
        |> Enum.sort_by(fn source ->
          priority = get_in(source.metadata, ["priority"]) || 10
          # Newer timestamps first (negative for descending sort)
          ts =
            if source.last_seen_at,
              do: -DateTime.to_unix(source.last_seen_at, :second),
              else: 9_223_372_036_854_775_807

          {priority, ts}
        end)

      # Build fallback map for batch lookup: %{source_id => original_image_url}
      source_fallbacks =
        deduplicated_sources
        |> Enum.filter(&(&1.id && &1.image_url))
        |> Map.new(fn source -> {source.id, source.image_url} end)

      # Batch lookup cached URLs with fallbacks to original URLs
      cached_urls = EventSourceImages.get_urls_with_fallbacks(source_fallbacks)

      source_images =
        deduplicated_sources
        |> Enum.flat_map(fn source ->
          # Use cached URL if available, otherwise try metadata
          cached_url = if source.id, do: Map.get(cached_urls, source.id), else: nil
          metadata_image = extract_image_from_metadata(source.metadata)

          [cached_url, metadata_image]
        end)
        |> Enum.reject(&is_nil/1)

      images ++ source_images
    else
      images
    end
  end

  # Extract image URL from source metadata
  defp extract_image_from_metadata(nil), do: nil

  defp extract_image_from_metadata(metadata) do
    cond do
      # Resident Advisor stores in raw_data -> event -> flyerFront
      flyer = get_in(metadata, ["raw_data", "event", "flyerFront"]) ->
        flyer

      # Bandsintown stores in images array
      is_list(metadata["images"]) and length(metadata["images"]) > 0 ->
        List.first(metadata["images"])["url"]

      # Ticketmaster stores in images array with different structure
      is_list(get_in(metadata, ["event", "images"])) and
          length(get_in(metadata, ["event", "images"])) > 0 ->
        # Get the largest image
        metadata
        |> get_in(["event", "images"])
        |> Enum.sort_by(fn img -> img["width"] || 0 end, :desc)
        |> List.first()
        |> Map.get("url")

      # Direct image_url in metadata
      url = metadata["image_url"] ->
        url

      true ->
        nil
    end
  end

  # Add pricing/ticket information
  defp add_offers(schema, event) do
    if event.sources && event.sources != [] do
      source = List.first(event.sources)
      build_offer(schema, source)
    else
      schema
    end
  end

  defp build_offer(schema, source) do
    cond do
      # Free event
      source.is_free == true ->
        offer = %{
          "@type" => "Offer",
          "price" => 0,
          "priceCurrency" => source.currency || "USD",
          "availability" => "https://schema.org/InStock"
        }

        offer = maybe_add_offer_url(offer, source)
        Map.put(schema, "offers", offer)

      # Paid event with price
      source.min_price && Decimal.gt?(source.min_price, Decimal.new(0)) ->
        min_price_float = Decimal.to_float(source.min_price)

        offer = %{
          "@type" => "Offer",
          "price" => min_price_float,
          "priceCurrency" => source.currency || "USD",
          "availability" => "https://schema.org/InStock",
          "validFrom" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Add price range if max price is different
        offer =
          if source.max_price && Decimal.gt?(source.max_price, source.min_price) do
            max_price_float = Decimal.to_float(source.max_price)

            Map.put(offer, "priceSpecification", %{
              "@type" => "PriceSpecification",
              "minPrice" => min_price_float,
              "maxPrice" => max_price_float,
              "priceCurrency" => source.currency || "USD"
            })
          else
            offer
          end

        offer = maybe_add_offer_url(offer, source)
        Map.put(schema, "offers", offer)

      # Has source URL but no price
      source.source_url ->
        offer = %{
          "@type" => "Offer",
          "url" => source.source_url,
          "availability" => "https://schema.org/InStock"
        }

        Map.put(schema, "offers", offer)

      # No pricing information available
      true ->
        schema
    end
  end

  defp maybe_add_offer_url(offer, source) do
    cond do
      source.source_url && source.source_url != "" ->
        Map.put(offer, "url", source.source_url)

      source.source && source.source.website_url ->
        Map.put(offer, "url", source.source.website_url)

      true ->
        offer
    end
  end

  # Check if performers association is loaded and non-empty
  defp has_loaded_performers?(event) do
    Ecto.assoc_loaded?(event.performers) && event.performers != []
  end

  # Add performer information
  defp add_performers(schema, event) do
    if has_loaded_performers?(event) do
      performers =
        event.performers
        |> Enum.map(fn performer ->
          %{
            "@type" => determine_performer_type(performer),
            "name" => performer.name
          }
        end)

      # Use single performer if only one, array if multiple
      performer_value = if length(performers) == 1, do: List.first(performers), else: performers

      Map.put(schema, "performer", performer_value)
    else
      schema
    end
  end

  # Determine if performer is a Person or MusicGroup/Organization
  defp determine_performer_type(_performer) do
    # TODO: Add performer type field to distinguish between person/group
    # For now, default to PerformingGroup which works for both
    "PerformingGroup"
  end

  # Add organizer from source
  defp add_organizer(schema, event) do
    if event.sources && event.sources != [] do
      source = List.first(event.sources)

      if source.source do
        organizer = %{
          "@type" => "Organization",
          "name" => source.source.name
        }

        organizer =
          if source.source.website_url do
            Map.put(organizer, "url", source.source.website_url)
          else
            organizer
          end

        Map.put(schema, "organizer", organizer)
      else
        schema
      end
    else
      schema
    end
  end

  # Add workPresented for ScreeningEvent (movies)
  defp add_work_presented(schema, event) do
    if schema["@type"] == "ScreeningEvent" && event.movies && event.movies != [] do
      movie = List.first(event.movies)

      work =
        %{
          "@type" => "Movie",
          "name" => movie.title
        }
        |> maybe_add_movie_image(movie)
        |> maybe_add_movie_date_created(movie)
        |> maybe_add_movie_metadata(movie)
        |> maybe_add_movie_same_as(movie)

      schema
      |> Map.put("workPresented", work)
      |> maybe_add_video_format(event)
      |> maybe_add_in_language(event)
    else
      schema
    end
  end

  # Add movie poster image (required by Google)
  # Uses cached R2 URL when available, falling back to original TMDB URL
  defp maybe_add_movie_image(work, movie) do
    # Get cached URLs with fallback to original
    poster_url =
      if is_integer(movie.id) do
        MovieImages.get_poster_url(movie.id, movie.poster_url)
      else
        movie.poster_url
      end

    backdrop_url =
      if is_integer(movie.id) do
        MovieImages.get_backdrop_url(movie.id, movie.backdrop_url)
      else
        movie.backdrop_url
      end

    cond do
      # Use poster_url from movie if available
      poster_url && poster_url != "" ->
        Map.put(work, "image", CDN.url(poster_url))

      # Fallback to backdrop if no poster
      backdrop_url && backdrop_url != "" ->
        Map.put(work, "image", CDN.url(backdrop_url))

      true ->
        work
    end
  end

  # Add dateCreated from movie release_date (Google optional field)
  defp maybe_add_movie_date_created(work, movie) do
    cond do
      # Use release_date if available
      movie.release_date ->
        Map.put(work, "dateCreated", Date.to_iso8601(movie.release_date))

      true ->
        work
    end
  end

  # Add rich movie metadata from TMDb/OMDb when available
  defp maybe_add_movie_metadata(work, movie) do
    work
    |> maybe_add_from_tmdb(movie.tmdb_metadata)
    |> maybe_add_from_omdb(movie.metadata)
  end

  # Add metadata from TMDb
  defp maybe_add_from_tmdb(work, nil), do: work

  defp maybe_add_from_tmdb(work, tmdb) do
    work
    |> Helpers.maybe_add("datePublished", tmdb["release_date"])
    |> Helpers.maybe_add("genre", Helpers.extract_genres(tmdb["genres"]))
    |> Helpers.maybe_add("director", Helpers.extract_directors(tmdb["credits"]))
    |> Helpers.maybe_add("actor", Helpers.extract_actors(tmdb["credits"]))
    |> Helpers.maybe_add("duration", Helpers.format_iso_duration(tmdb["runtime"]))
    |> Helpers.maybe_add("aggregateRating", Helpers.build_aggregate_rating(tmdb))
  end

  # Add metadata from OMDb (only if not already present from TMDb)
  defp maybe_add_from_omdb(work, nil), do: work

  defp maybe_add_from_omdb(work, omdb) do
    work
    |> Helpers.maybe_add_if_missing("datePublished", omdb["Released"])
    |> Helpers.maybe_add_if_missing("genre", parse_comma_list(omdb["Genre"]))
    |> Helpers.maybe_add_if_missing("director", build_person_schema(omdb["Director"]))
    |> Helpers.maybe_add_if_missing("actor", build_actors_from_string(omdb["Actors"]))
    |> Helpers.maybe_add_if_missing("duration", format_omdb_duration(omdb["Runtime"]))
    |> Helpers.maybe_add_if_missing("aggregateRating", build_omdb_aggregate_rating(omdb))
  end

  # Add sameAs URLs - primarily cinegraph.org, plus IMDb for cross-reference
  defp maybe_add_movie_same_as(work, movie) do
    same_as = []

    # Add cinegraph.org URL (our canonical movie reference)
    same_as =
      if movie.slug && movie.slug != "" do
        same_as ++ ["https://cinegraph.org/movies/#{movie.slug}"]
      else
        same_as
      end

    # Add IMDb URL from OMDb metadata for additional cross-reference
    same_as =
      case get_in(movie.metadata || %{}, ["imdbID"]) do
        id when is_binary(id) and id != "" and id != "N/A" ->
          same_as ++ ["https://www.imdb.com/title/#{id}/"]

        _ ->
          same_as
      end

    case same_as do
      [] -> work
      urls -> Map.put(work, "sameAs", urls)
    end
  end

  # Add videoFormat from event source metadata (IMAX, 3D, 4DX)
  defp maybe_add_video_format(schema, event) do
    format_info = get_format_info_from_sources(event)

    video_formats =
      []
      |> maybe_append(get_in(format_info, ["is_3d"]) || get_in(format_info, [:is_3d]), "3D")
      |> maybe_append(get_in(format_info, ["is_imax"]) || get_in(format_info, [:is_imax]), "IMAX")
      |> maybe_append(get_in(format_info, ["is_4dx"]) || get_in(format_info, [:is_4dx]), "4DX")

    case video_formats do
      [] -> schema
      [single] -> Map.put(schema, "videoFormat", single)
      multiple -> Map.put(schema, "videoFormat", multiple)
    end
  end

  # Add inLanguage from event source metadata
  defp maybe_add_in_language(schema, event) do
    language_info = get_language_info_from_sources(event)

    # Try to get the original language or dubbed language
    language =
      cond do
        lang =
            get_in(language_info, ["original_language"]) ||
              get_in(language_info, [:original_language]) ->
          lang

        lang =
            get_in(language_info, ["dubbed_language"]) ||
              get_in(language_info, [:dubbed_language]) ->
          lang

        true ->
          nil
      end

    if language && language != "" do
      Map.put(schema, "inLanguage", language)
    else
      schema
    end
  end

  # Extract format_info from event sources metadata
  defp get_format_info_from_sources(event) do
    if event.sources && event.sources != [] do
      event.sources
      |> Enum.find_value(%{}, fn source ->
        format_info = get_in(source.metadata || %{}, ["format_info"])
        if format_info && format_info != %{}, do: format_info, else: nil
      end)
    else
      %{}
    end
  end

  # Extract language_info from event sources metadata
  defp get_language_info_from_sources(event) do
    if event.sources && event.sources != [] do
      event.sources
      |> Enum.find_value(%{}, fn source ->
        language_info = get_in(source.metadata || %{}, ["language_info"])
        if language_info && language_info != %{}, do: language_info, else: nil
      end)
    else
      %{}
    end
  end

  # Helper to format OMDb runtime ("142 min")
  defp format_omdb_duration(nil), do: nil
  defp format_omdb_duration("N/A"), do: nil

  defp format_omdb_duration(runtime_string) when is_binary(runtime_string) do
    case Integer.parse(runtime_string) do
      {minutes, _} -> Helpers.format_iso_duration(minutes)
      :error -> nil
    end
  end

  # Build OMDb aggregate rating
  defp build_omdb_aggregate_rating(nil), do: nil

  defp build_omdb_aggregate_rating(metadata) do
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

  # Parse comma-separated string (for OMDb genre, actors)
  defp parse_comma_list(nil), do: nil
  defp parse_comma_list("N/A"), do: nil

  defp parse_comma_list(string) when is_binary(string) do
    parts =
      string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> nil
      list -> list
    end
  end

  # Build Person schema from name
  defp build_person_schema(nil), do: nil
  defp build_person_schema("N/A"), do: nil

  defp build_person_schema(name) when is_binary(name) do
    %{"@type" => "Person", "name" => name}
  end

  # Build actors list from comma-separated string
  defp build_actors_from_string(nil), do: nil
  defp build_actors_from_string("N/A"), do: nil

  defp build_actors_from_string(actors_string) when is_binary(actors_string) do
    actors =
      actors_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(10)
      |> Enum.map(&build_person_schema/1)

    case actors do
      [] -> nil
      list -> list
    end
  end

  # Helper to conditionally append to list
  defp maybe_append(list, true, value), do: list ++ [value]
  defp maybe_append(list, _, _), do: list
end
