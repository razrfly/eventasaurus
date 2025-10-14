defmodule Eventasaurus.SocialCards.PollHashGenerator do
  @moduledoc """
  Generates cache-busting hashes for poll social card URLs.

  Creates fingerprints based on all components that affect poll social card appearance,
  ensuring social media platforms re-fetch cards when content changes.
  """

  @social_card_version "v2.0.0"

  @doc """
  Generates a cache-busting hash for a poll social card based on poll data.

  The hash includes:
  - Poll ID (unique identifier)
  - Poll title
  - Poll type
  - Poll phase/status
  - Parent event theme
  - Poll updated_at timestamp

  Returns a short hash suitable for URLs.

  ## Examples

      iex> poll = %{id: 1, title: "Movie Poll", poll_type: "movie", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.PollHashGenerator.generate_hash(poll)
      "a1b2c3d4"

  """
  @spec generate_hash(map()) :: String.t()
  def generate_hash(poll) when is_map(poll) do
    poll
    |> build_fingerprint()
    |> Jason.encode!(pretty: false, sort_keys: true)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  @doc """
  Generates a cache-busting URL path for a poll social card.

  Format: /:event_slug/polls/:poll_number/social-card-{hash}.png

  ## Examples

      iex> poll = %{number: 1, title: "Movie Poll", updated_at: ~N[2023-01-01 12:00:00]}
      iex> event = %{slug: "my-event"}
      iex> Eventasaurus.SocialCards.PollHashGenerator.generate_url_path(poll, event)
      "/my-event/polls/1/social-card-a1b2c3d4.png"

  """
  @spec generate_url_path(map(), map()) :: String.t()
  def generate_url_path(poll, event) when is_map(poll) and is_map(event) do
    # Get event slug
    event_slug =
      case {Map.get(event, :slug), Map.get(event, :id)} do
        {slug, _} when is_binary(slug) and slug != "" -> slug
        {_, id} when not is_nil(id) -> "event-#{id}"
        _ -> "unknown-event"
      end

    # Get poll number (use ID as fallback for backwards compatibility during migration)
    poll_number = Map.get(poll, :number) || Map.get(poll, :id)

    hash = generate_hash(poll)
    "/#{event_slug}/polls/#{poll_number}/social-card-#{hash}.png"
  end

  @doc """
  Extracts hash from a poll social card URL path.
  Returns nil if URL doesn't match expected pattern.

  ## Examples

      iex> Eventasaurus.SocialCards.PollHashGenerator.extract_hash_from_path("/my-event/polls/1/social-card-a1b2c3d4.png")
      "a1b2c3d4"

      iex> Eventasaurus.SocialCards.PollHashGenerator.extract_hash_from_path("/invalid/path")
      nil

  """
  @spec extract_hash_from_path(String.t()) :: String.t() | nil
  def extract_hash_from_path(path) when is_binary(path) do
    case Regex.run(~r/\/[^\/]+\/polls\/\d+\/social-card-([a-f0-9]{8})(?:\.png)?$/, path) do
      [_full_match, hash] -> hash
      _ -> nil
    end
  end

  @doc """
  Validates that a given hash matches the current poll data.
  Returns true if hash is current, false if stale.

  ## Examples

      iex> poll = %{id: 1, title: "Movie Poll", updated_at: ~N[2023-01-01 12:00:00]}
      iex> hash = Eventasaurus.SocialCards.PollHashGenerator.generate_hash(poll)
      iex> Eventasaurus.SocialCards.PollHashGenerator.validate_hash(poll, hash)
      true

      iex> Eventasaurus.SocialCards.PollHashGenerator.validate_hash(poll, "invalid")
      false

  """
  @spec validate_hash(map(), String.t()) :: boolean()
  def validate_hash(poll, hash) when is_map(poll) and is_binary(hash) do
    generate_hash(poll) == hash
  end

  # Private helper functions

  defp build_fingerprint(poll) do
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
