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
  defp maybe_add_location(schema, venue), do: Map.put(schema, "location", build_location(venue))

  # Build schema.org Place object for venue location
  defp build_location(venue) do
    %{
      "@type" => "Place",
      "name" => venue.name,
      "address" => build_postal_address(venue)
    }
    |> add_geo_coordinates(venue)
  end

  # Build schema.org PostalAddress
  defp build_postal_address(venue) do
    address = %{
      "@type" => "PostalAddress",
      "streetAddress" => venue.address || ""
    }

    # Add city information if available
    address =
      if venue.city_ref && venue.city_ref.name do
        Map.put(address, "addressLocality", venue.city_ref.name)
      else
        address
      end

    # Add country code if available
    address =
      if venue.city_ref && venue.city_ref.country do
        Map.put(address, "addressCountry", venue.city_ref.country.code || "US")
      else
        address
      end

    address
  end

  # Add geo coordinates to location if available
  defp add_geo_coordinates(location, venue) do
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

    # Add performers if available
    parts =
      if event.performers && event.performers != [] do
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
    has_performers = event.performers && event.performers != []

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
  defp collect_images(event) do
    []
    |> add_event_images(event)
    |> add_movie_posters(event)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  # Extract images from event sources
  defp add_event_images(images, event) do
    if event.sources && event.sources != [] do
      # Get images from all sources, prioritizing by source priority and recency
      source_images =
        event.sources
        |> Enum.sort_by(fn source ->
          priority = get_in(source.metadata, ["priority"]) || 10
          # Newer timestamps first (negative for descending sort)
          ts =
            if source.last_seen_at,
              do: -DateTime.to_unix(source.last_seen_at, :second),
              else: 9_223_372_036_854_775_807

          {priority, ts}
        end)
        |> Enum.flat_map(fn source ->
          [
            # Check direct image_url field
            source.image_url,
            # Check metadata for images
            extract_image_from_metadata(source.metadata)
          ]
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

  # Add movie posters for ScreeningEvent
  defp add_movie_posters(images, event) do
    if event.movies && event.movies != [] do
      movie_images =
        event.movies
        |> Enum.map(fn movie ->
          # TODO: Extract poster URL from movie metadata when available
          # For now, return nil to filter out
          nil
        end)
        |> Enum.reject(&is_nil/1)

      images ++ movie_images
    else
      images
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

  # Add performer information
  defp add_performers(schema, event) do
    if event.performers && event.performers != [] do
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
  defp determine_performer_type(performer) do
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

      work = %{
        "@type" => "Movie",
        "name" => movie.title
      }

      # TODO: Add director, actors, genre when available in movie metadata
      # work = maybe_add_movie_director(work, movie)
      # work = maybe_add_movie_actors(work, movie)

      Map.put(schema, "workPresented", work)
    else
      schema
    end
  end
end
