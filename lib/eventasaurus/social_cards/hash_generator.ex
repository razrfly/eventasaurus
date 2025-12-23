defmodule Eventasaurus.SocialCards.HashGenerator do
  @moduledoc """
  Generates cache-busting hashes for social card URLs.

  Creates fingerprints based on all components that affect social card appearance,
  ensuring social media platforms re-fetch cards when content changes.
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

  """
  @spec generate_hash(map(), :event | :poll | :city | :activity) :: String.t()
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

  """
  @spec generate_url_path(map(), :event | :poll | :city | :activity) :: String.t()
  def generate_url_path(data, type \\ :event) when is_map(data) do
    hash = generate_hash(data, type)

    case type do
      :activity ->
        slug =
          case {Map.get(data, :slug), Map.get(data, :id)} do
            {slug, _} when is_binary(slug) and slug != "" -> slug
            {_, id} when not is_nil(id) -> "activity-#{id}"
            _ -> "unknown-activity"
          end

        "/social-cards/activity/#{slug}/#{hash}.png"

      :city ->
        slug =
          case {Map.get(data, :slug), Map.get(data, :id)} do
            {slug, _} when is_binary(slug) and slug != "" -> slug
            {_, id} when not is_nil(id) -> "city-#{id}"
            _ -> "unknown-city"
          end

        "/social-cards/city/#{slug}/#{hash}.png"

      :poll ->
        # Get event slug
        event = Map.get(data, :event)

        event_slug =
          case {Map.get(event, :slug), Map.get(event, :id)} do
            {slug, _} when is_binary(slug) and slug != "" -> slug
            {_, id} when not is_nil(id) -> "event-#{id}"
            _ -> "unknown-event"
          end

        # Get poll number with fallback to ID
        poll_number =
          case Map.get(data, :number) do
            number when is_integer(number) and number > 0 ->
              number

            _ ->
              Map.get(data, :id) ||
                raise ArgumentError, "poll.number not present for social card URL generation"
          end

        "/#{event_slug}/polls/#{poll_number}/social-card-#{hash}.png"

      :event ->
        slug =
          case {Map.get(data, :slug), Map.get(data, :id)} do
            {slug, _} when is_binary(slug) and slug != "" -> slug
            {_, id} when not is_nil(id) -> "event-#{id}"
            _ -> "unknown-event"
          end

        "/#{slug}/social-card-#{hash}.png"
    end
  end

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

  """
  @spec validate_hash(map(), String.t(), :event | :poll | :city | :activity) :: boolean()
  def validate_hash(data, hash, type \\ :event) when is_map(data) and is_binary(hash) do
    generate_hash(data, type) == hash
  end

  # Private helper functions

  defp build_fingerprint(data, type)

  defp build_fingerprint(event, :event) do
    # Ensure we always have a valid slug, even if :id is missing
    slug =
      case {Map.get(event, :slug), Map.get(event, :id)} do
        {slug, _} when is_binary(slug) and slug != "" -> slug
        {_, id} when not is_nil(id) -> "event-#{id}"
        _ -> "unknown-event"
      end

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
    # Ensure we always have a valid slug
    slug =
      case {Map.get(city, :slug), Map.get(city, :id)} do
        {slug, _} when is_binary(slug) and slug != "" -> slug
        {_, id} when not is_nil(id) -> "city-#{id}"
        _ -> "unknown-city"
      end

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
    # Ensure we always have a valid slug
    slug =
      case {Map.get(activity, :slug), Map.get(activity, :id)} do
        {slug, _} when is_binary(slug) and slug != "" -> slug
        {_, id} when not is_nil(id) -> "activity-#{id}"
        _ -> "unknown-activity"
      end

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
