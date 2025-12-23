defmodule Eventasaurus.SocialCards.HashGenerator do
  @moduledoc """
  Generates cache-busting hashes for social card URLs.

  Creates fingerprints based on all components that affect social card appearance,
  ensuring social media platforms re-fetch cards when content changes.

  ## Supported Types

  - `:event` - Event social cards
  - `:poll` - Poll social cards (requires parent event)
  - `:city` - City page social cards
  - `:activity` - Public event/activity social cards
  - `:source_aggregation` - Source aggregation page social cards
  - `:venue` - Venue page social cards
  - `:performer` - Performer page social cards

  ## Hash Generation

  Hashes are 8-character SHA256 fingerprints based on all content that affects
  card appearance. When any hash input changes, the URL changes, causing social
  media platforms to re-fetch the card image.
  """

  @social_card_version "v2.0.0"

  @doc """
  Generates a cache-busting hash for a social card based on event, poll, or city data.

  For events, the hash includes:
  - Event slug (unique identifier)
  - Event title
  - Event description
  - Cover image URL
  - Event updated_at timestamp
  - Any theme/styling data

  For polls, the hash includes:
  - Poll ID (unique identifier)
  - Poll title
  - Poll type
  - Poll phase/status
  - Parent event theme
  - Poll options (IDs, titles, timestamps)
  - Poll updated_at timestamp

  For cities, the hash includes:
  - City slug (unique identifier)
  - City name
  - Stats (events_count, venues_count, categories_count)
  - City updated_at timestamp

  For activities (public events), the hash includes:
  - Activity slug (unique identifier)
  - Activity title
  - Cover image URL
  - Venue name
  - City name
  - First occurrence date
  - Activity updated_at timestamp

  For source aggregations, the hash includes:
  - City slug
  - Content type
  - Identifier (source slug)
  - Total event count
  - Location count (venues or events based on scope)
  - Hero image URL

  For venues, the hash includes:
  - Venue slug (unique identifier)
  - Venue name
  - City slug
  - Address
  - Event count (upcoming events)
  - Cover image URL
  - Venue updated_at timestamp

  For performers, the hash includes:
  - Performer slug (unique identifier)
  - Performer name
  - Event count (upcoming events)
  - Image URL
  - Performer updated_at timestamp

  Returns a short hash suitable for URLs.

  ## Examples

      iex> event = %{slug: "my-unique-event", title: "My Event", cover_image_url: "https://example.com/img.jpg", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(event)
      "a1b2c3d4"

      iex> poll = %{id: 1, title: "Movie Poll", poll_type: "movie", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(poll, :poll)
      "c3d4e5f6"

      iex> city = %{slug: "warsaw", name: "Warsaw", stats: %{events_count: 127, venues_count: 45, categories_count: 12}}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(city, :city)
      "b2c3d4e5"

      iex> activity = %{slug: "my-activity", title: "My Activity", venue: %{name: "Venue"}, updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(activity, :activity)
      "d4e5f6a7"

      iex> aggregation = %{city: %{slug: "krakow"}, content_type: "SocialEvent", identifier: "pubquiz-pl", total_event_count: 15, location_count: 8}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(aggregation, :source_aggregation)
      "e5f6a7b8"

      iex> venue = %{slug: "klub-jazz", name: "Jazz Club", city_ref: %{slug: "krakow"}, event_count: 12}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(venue, :venue)
      "f6a7b8c9"

      iex> performer = %{slug: "john-doe", name: "John Doe", event_count: 5, image_url: "https://example.com/john.jpg"}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(performer, :performer)
      "a7b8c9d0"

  """
  @spec generate_hash(
          map(),
          :event | :poll | :city | :activity | :source_aggregation | :venue | :performer
        ) :: String.t()
  def generate_hash(data, type \\ :event) when is_map(data) do
    data
    |> build_fingerprint(type)
    |> Jason.encode!(pretty: false, sort_keys: true)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  @doc """
  Generates a cache-busting URL path for a social card.

  Format for events: /{slug}/social-card-{hash}.png
  Format for polls: /{event_slug}/polls/{poll_number}/social-card-{hash}.png
  Format for cities: /social-cards/city/{slug}/{hash}.png
  Format for activities: /social-cards/activity/{slug}/{hash}.png

  ## Examples

      iex> event = %{slug: "my-awesome-event", title: "My Event", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(event)
      "/my-awesome-event/social-card-a1b2c3d4.png"

      iex> poll = %{number: 1, title: "Movie Poll", event: %{slug: "my-event"}}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(poll, :poll)
      "/my-event/polls/1/social-card-c3d4e5f6.png"

      iex> city = %{slug: "warsaw", name: "Warsaw", stats: %{events_count: 127}}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(city, :city)
      "/social-cards/city/warsaw/a1b2c3d4.png"

      iex> activity = %{slug: "my-activity", title: "My Activity", venue: %{name: "Venue"}}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(activity, :activity)
      "/social-cards/activity/my-activity/d4e5f6a7.png"

      iex> aggregation = %{city: %{slug: "krakow"}, content_type: "SocialEvent", identifier: "pubquiz-pl"}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(aggregation, :source_aggregation)
      "/social-cards/source/krakow/social/pubquiz-pl/e5f6a7b8.png"

      iex> venue = %{slug: "klub-jazz", city_ref: %{slug: "krakow"}, name: "Jazz Club"}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(venue, :venue)
      "/social-cards/venue/krakow/klub-jazz/f6a7b8c9.png"

      iex> performer = %{slug: "john-doe", name: "John Doe", event_count: 5}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(performer, :performer)
      "/social-cards/performer/john-doe/a7b8c9d0.png"

  """
  @spec generate_url_path(
          map(),
          :event | :poll | :city | :activity | :source_aggregation | :venue | :performer
        ) :: String.t()
  def generate_url_path(data, type \\ :event) when is_map(data) do
    hash = generate_hash(data, type)

    case type do
      :activity ->
        slug = extract_slug(data, :slug, :id, "activity")
        "/social-cards/activity/#{slug}/#{hash}.png"

      :city ->
        slug = extract_slug(data, :slug, :id, "city")
        "/social-cards/city/#{slug}/#{hash}.png"

      :poll ->
        event = Map.get(data, :event)
        event_slug = extract_slug(event, :slug, :id, "event")
        poll_number = extract_slug(data, :number, :id, "poll")
        "/#{event_slug}/polls/#{poll_number}/social-card-#{hash}.png"

      :event ->
        slug = extract_slug(data, :slug, :id, "event")
        "/#{slug}/social-card-#{hash}.png"

      :source_aggregation ->
        city_slug = extract_city_slug(data, :city)
        content_type = Map.get(data, :content_type, "")
        content_type_slug = content_type_to_slug(content_type)
        identifier = Map.get(data, :identifier, "unknown-source")
        "/social-cards/source/#{city_slug}/#{content_type_slug}/#{identifier}/#{hash}.png"

      :venue ->
        city_slug = extract_city_slug(data, :city_ref)
        venue_slug = extract_slug(data, :slug, :id, "venue")
        "/social-cards/venue/#{city_slug}/#{venue_slug}/#{hash}.png"

      :performer ->
        performer_slug = extract_slug(data, :slug, :id, "performer")
        "/social-cards/performer/#{performer_slug}/#{hash}.png"
    end
  end

  # Convert schema.org content type to URL slug
  defp content_type_to_slug("SocialEvent"), do: "social"
  defp content_type_to_slug("FoodEvent"), do: "food"
  defp content_type_to_slug("Festival"), do: "festival"
  defp content_type_to_slug("MusicEvent"), do: "music"
  defp content_type_to_slug("ScreeningEvent"), do: "movies"
  defp content_type_to_slug("ComedyEvent"), do: "comedy"
  defp content_type_to_slug("TheaterEvent"), do: "theater"
  defp content_type_to_slug("SportsEvent"), do: "sports"
  defp content_type_to_slug("DanceEvent"), do: "dance"
  defp content_type_to_slug("EducationEvent"), do: "classes"
  defp content_type_to_slug(_), do: "happenings"

  @doc """
  Extracts hash from a social card URL path.
  Returns nil if URL doesn't match expected pattern.

  Supports multiple patterns:
  - Event: /slug/social-card-hash.png
  - Poll: /slug/polls/number/social-card-hash.png
  - City: /social-cards/city/slug/hash.png
  - Activity: /social-cards/activity/slug/hash.png

  ## Examples

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/my-event/social-card-a1b2c3d4.png")
      "a1b2c3d4"

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/my-event/polls/1/social-card-a1b2c3d4.png")
      "a1b2c3d4"

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/social-cards/city/warsaw/a1b2c3d4.png")
      "a1b2c3d4"

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/social-cards/activity/my-activity/d4e5f6a7.png")
      "d4e5f6a7"

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/social-cards/venue/krakow/klub-jazz/f6a7b8c9.png")
      "f6a7b8c9"

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/social-cards/performer/john-doe/a7b8c9d0.png")
      "a7b8c9d0"

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/invalid/path")
      nil

  """
  @spec extract_hash_from_path(String.t()) :: String.t() | nil
  def extract_hash_from_path(path) when is_binary(path) do
    cond do
      # Poll pattern: /event-slug/polls/number/social-card-hash.png
      match = Regex.run(~r/\/[^\/]+\/polls\/\d+\/social-card-([a-f0-9]{8})(?:\.png)?$/, path) ->
        [_full_match, hash] = match
        hash

      # Activity pattern: /social-cards/activity/slug/hash.png
      match = Regex.run(~r/\/social-cards\/activity\/[^\/]+\/([a-f0-9]{8})(?:\.png)?$/, path) ->
        [_full_match, hash] = match
        hash

      # City pattern: /social-cards/city/slug/hash.png
      match = Regex.run(~r/\/social-cards\/city\/[^\/]+\/([a-f0-9]{8})(?:\.png)?$/, path) ->
        [_full_match, hash] = match
        hash

      # Venue pattern: /social-cards/venue/city-slug/venue-slug/hash.png
      match = Regex.run(~r/\/social-cards\/venue\/[^\/]+\/[^\/]+\/([a-f0-9]{8})(?:\.png)?$/, path) ->
        [_full_match, hash] = match
        hash

      # Performer pattern: /social-cards/performer/slug/hash.png
      match = Regex.run(~r/\/social-cards\/performer\/[^\/]+\/([a-f0-9]{8})(?:\.png)?$/, path) ->
        [_full_match, hash] = match
        hash

      # Event pattern: /slug/social-card-hash.png
      match = Regex.run(~r/\/[^\/]+\/social-card-([a-f0-9]{8})(?:\.png)?$/, path) ->
        [_full_match, hash] = match
        hash

      true ->
        nil
    end
  end

  @doc """
  Validates that a given hash matches the current event, poll, city, or activity data.
  Returns true if hash is current, false if stale.

  ## Examples

      iex> event = %{slug: "my-unique-event", updated_at: ~N[2023-01-01 12:00:00]}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(event)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(event, hash)
      true

      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(event, "invalid")
      false

      iex> poll = %{id: 1, title: "Movie Poll", updated_at: ~N[2023-01-01 12:00:00]}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(poll, :poll)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(poll, hash, :poll)
      true

      iex> city = %{slug: "warsaw", name: "Warsaw", stats: %{events_count: 127}}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(city, :city)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(city, hash, :city)
      true

      iex> activity = %{slug: "my-activity", title: "My Activity"}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(activity, :activity)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(activity, hash, :activity)
      true

      iex> aggregation = %{city: %{slug: "krakow"}, content_type: "SocialEvent", identifier: "pubquiz-pl"}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(aggregation, :source_aggregation)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(aggregation, hash, :source_aggregation)
      true

      iex> venue = %{slug: "klub-jazz", name: "Jazz Club", city_ref: %{slug: "krakow"}}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(venue, :venue)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(venue, hash, :venue)
      true

      iex> performer = %{slug: "john-doe", name: "John Doe", event_count: 5}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(performer, :performer)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(performer, hash, :performer)
      true

  """
  @spec validate_hash(
          map(),
          String.t(),
          :event | :poll | :city | :activity | :source_aggregation | :venue | :performer
        ) :: boolean()
  def validate_hash(data, hash, type \\ :event) when is_map(data) and is_binary(hash) do
    generate_hash(data, type) == hash
  end

  # ===========================================================================
  # Private Helper Functions
  # ===========================================================================

  # Extracts a slug from data with fallback to ID-based slug
  # Used consistently across fingerprint building and URL generation
  @spec extract_slug(map(), atom(), atom(), String.t()) :: String.t()
  defp extract_slug(data, slug_key, id_key, fallback_prefix) do
    slug_value = Map.get(data, slug_key)
    id_value = if id_key, do: Map.get(data, id_key), else: nil

    case {slug_value, id_value} do
      {slug, _} when is_binary(slug) and slug != "" -> slug
      {number, _} when is_integer(number) and number > 0 -> to_string(number)
      {_, id} when not is_nil(id) -> "#{fallback_prefix}-#{id}"
      _ -> "unknown-#{fallback_prefix}"
    end
  end

  # Extracts city slug from a nested city reference
  defp extract_city_slug(data, city_key) do
    city = Map.get(data, city_key, %{})
    extract_slug(city, :slug, :id, "city")
  end

  defp build_fingerprint(data, type)

  defp build_fingerprint(event, :event) do
    slug = extract_slug(event, :slug, :id, "event")

    %{
      type: :event,
      slug: slug,
      title: Map.get(event, :title, ""),
      description: Map.get(event, :description, ""),
      cover_image_url: Map.get(event, :cover_image_url, ""),
      theme: Map.get(event, :theme, :minimal),
      theme_customizations: Map.get(event, :theme_customizations, %{}),
      updated_at: format_timestamp(Map.get(event, :updated_at)),
      version: @social_card_version
    }
  end

  defp build_fingerprint(poll, :poll) do
    # Ensure we always have a valid poll ID
    poll_id =
      case Map.get(poll, :id) do
        id when not is_nil(id) -> id
        _ -> "unknown-poll"
      end

    # Get parent event for theme (if available)
    event = Map.get(poll, :event)

    theme =
      if event && is_map(event) do
        Map.get(event, :theme, :minimal)
      else
        :minimal
      end

    # Build option fingerprint to ensure cache busts when options change
    # This is critical since social cards display poll options
    options_fingerprint = build_options_fingerprint(Map.get(poll, :poll_options, []))

    %{
      type: :poll,
      poll_id: poll_id,
      title: Map.get(poll, :title, ""),
      poll_type: Map.get(poll, :poll_type, "custom"),
      phase: Map.get(poll, :phase, "list_building"),
      theme: theme,
      updated_at: format_timestamp(Map.get(poll, :updated_at)),
      options: options_fingerprint,
      version: @social_card_version
    }
  end

  defp build_fingerprint(city, :city) do
    slug = extract_slug(city, :slug, :id, "city")

    # Get stats from the city map
    stats = Map.get(city, :stats, %{})

    %{
      type: :city,
      slug: slug,
      name: Map.get(city, :name, ""),
      events_count: Map.get(stats, :events_count, 0),
      venues_count: Map.get(stats, :venues_count, 0),
      categories_count: Map.get(stats, :categories_count, 0),
      updated_at: format_timestamp(Map.get(city, :updated_at)),
      version: @social_card_version
    }
  end

  defp build_fingerprint(activity, :activity) do
    slug = extract_slug(activity, :slug, :id, "activity")

    # Extract venue and city info for fingerprint
    venue = Map.get(activity, :venue)
    venue_name = if venue, do: Map.get(venue, :name, ""), else: ""

    city_name =
      if venue do
        city_ref = Map.get(venue, :city_ref)
        if city_ref, do: Map.get(city_ref, :name, ""), else: ""
      else
        ""
      end

    # Get first occurrence date for fingerprint
    occurrence_list = Map.get(activity, :occurrence_list) || []
    first_occurrence = List.first(occurrence_list)

    first_occurrence_date =
      case first_occurrence do
        %{datetime: dt} when not is_nil(dt) -> DateTime.to_iso8601(dt)
        %{date: d} when not is_nil(d) -> Date.to_iso8601(d)
        _ -> ""
      end

    %{
      type: :activity,
      slug: slug,
      title: Map.get(activity, :title, ""),
      cover_image_url: Map.get(activity, :cover_image_url, ""),
      venue_name: venue_name,
      city_name: city_name,
      first_occurrence_date: first_occurrence_date,
      updated_at: format_timestamp(Map.get(activity, :updated_at)),
      version: @social_card_version
    }
  end

  defp build_fingerprint(aggregation, :source_aggregation) do
    # Extract city info using helper
    city_slug = extract_city_slug(aggregation, :city)
    city = Map.get(aggregation, :city, %{})
    city_name = Map.get(city, :name, "")

    # Extract source info
    identifier = Map.get(aggregation, :identifier, "")
    source_name = Map.get(aggregation, :source_name, "")
    content_type = Map.get(aggregation, :content_type, "")

    # Get counts for cache busting when events change
    total_event_count = Map.get(aggregation, :total_event_count, 0)
    location_count = Map.get(aggregation, :location_count, 0)

    # Hero image affects card appearance
    hero_image = Map.get(aggregation, :hero_image, "")

    %{
      type: :source_aggregation,
      city_slug: city_slug,
      city_name: city_name,
      identifier: identifier,
      source_name: source_name,
      content_type: content_type,
      total_event_count: total_event_count,
      location_count: location_count,
      hero_image: hero_image,
      version: @social_card_version
    }
  end

  defp build_fingerprint(venue, :venue) do
    city_slug = extract_city_slug(venue, :city_ref)
    venue_slug = extract_slug(venue, :slug, :id, "venue")

    %{
      type: :venue,
      slug: venue_slug,
      name: Map.get(venue, :name, ""),
      city_slug: city_slug,
      address: Map.get(venue, :address, ""),
      event_count: Map.get(venue, :event_count, 0),
      cover_image_url: Map.get(venue, :cover_image_url, ""),
      updated_at: format_timestamp(Map.get(venue, :updated_at)),
      version: @social_card_version
    }
  end

  defp build_fingerprint(performer, :performer) do
    performer_slug = extract_slug(performer, :slug, :id, "performer")

    %{
      type: :performer,
      slug: performer_slug,
      name: Map.get(performer, :name, ""),
      event_count: Map.get(performer, :event_count, 0),
      image_url: Map.get(performer, :image_url, ""),
      updated_at: format_timestamp(Map.get(performer, :updated_at)),
      version: @social_card_version
    }
  end

  # Creates a stable fingerprint of poll options for cache busting
  # Includes option IDs, titles, and updated_at timestamps
  # Options are sorted by ID to ensure consistent ordering
  defp build_options_fingerprint([]), do: []

  defp build_options_fingerprint(options) when is_list(options) do
    options
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn option ->
      %{
        id: option.id,
        title: Map.get(option, :title, ""),
        updated_at: format_timestamp(Map.get(option, :updated_at))
      }
    end)
  end

  defp build_options_fingerprint(_), do: []

  defp format_timestamp(nil), do: ""
  defp format_timestamp(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(_), do: ""
end
