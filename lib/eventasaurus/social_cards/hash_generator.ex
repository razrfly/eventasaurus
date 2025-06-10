defmodule Eventasaurus.SocialCards.HashGenerator do
  @moduledoc """
  Generates cache-busting hashes for social card URLs.

  Creates fingerprints based on all components that affect social card appearance,
  ensuring social media platforms re-fetch cards when content changes.
  """

  @doc """
  Generates a cache-busting hash for a social card based on event data.

  The hash includes:
  - Event slug (unique identifier)
  - Event title
  - Event description
  - Cover image URL
  - Event updated_at timestamp
  - Any theme/styling data

  Returns a short hash suitable for URLs.

  ## Examples

      iex> event = %{slug: "my-unique-event", title: "My Event", cover_image_url: "https://example.com/img.jpg", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_hash(event)
      "a1b2c3d4"

  """
  @spec generate_hash(map()) :: String.t()
  def generate_hash(event) when is_map(event) do
    # Create a deterministic fingerprint of all social card components
    fingerprint_data = %{
      slug: Map.get(event, :slug, "event-#{Map.get(event, :id)}"),  # Use unique slug as primary identifier
      title: Map.get(event, :title, ""),
      description: Map.get(event, :description, ""),
      cover_image_url: Map.get(event, :cover_image_url, ""),
      updated_at: format_timestamp(Map.get(event, :updated_at)),
      # Include system version to force refresh when code changes
      version: social_card_version()
    }

    # Convert to deterministic string and hash
    fingerprint_data
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)  # Use first 8 characters for URL friendliness
  end

    @doc """
  Generates a cache-busting URL path for a social card.

  Format: /events/{slug}/social-card-{hash}.png

  ## Examples

      iex> event = %{slug: "my-awesome-event", title: "My Event", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.SocialCards.HashGenerator.generate_url_path(event)
      "/events/my-awesome-event/social-card-a1b2c3d4.png"

  """
  @spec generate_url_path(map()) :: String.t()
  def generate_url_path(event) when is_map(event) do
    slug = Map.get(event, :slug, "event-#{Map.get(event, :id)}")
    hash = generate_hash(event)
    "/events/#{slug}/social-card-#{hash}.png"
  end

  @doc """
  Extracts hash from a social card URL path.
  Returns nil if URL doesn't match expected pattern.

  ## Examples

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/events/my-event/social-card-a1b2c3d4.png")
      "a1b2c3d4"

      iex> Eventasaurus.SocialCards.HashGenerator.extract_hash_from_path("/invalid/path")
      nil

  """
  @spec extract_hash_from_path(String.t()) :: String.t() | nil
  def extract_hash_from_path(path) when is_binary(path) do
    # Handle standard format first
    case Regex.run(~r/\/events\/[^\/]+\/social-card-([a-f0-9]{8})\.png$/, path) do
      [_full_match, hash] -> hash
      _ ->
        # Try wildcard format where everything after social-card- is captured
        case Regex.run(~r/\/events\/[^\/]+\/social-card-(.+)$/, path) do
          [_full_match, hash_with_ext] ->
            # Remove .png extension if present
            hash = String.replace_suffix(hash_with_ext, ".png", "")

            # Validate hash format
            if byte_size(hash) == 8 and Regex.match?(~r/^[a-f0-9]{8}$/, hash) do
              hash
            else
              nil
            end
          _ -> nil
        end
    end
  end

  @doc """
  Validates that a given hash matches the current event data.
  Returns true if hash is current, false if stale.

  ## Examples

      iex> event = %{slug: "my-unique-event", updated_at: ~N[2023-01-01 12:00:00]}
      iex> hash = Eventasaurus.SocialCards.HashGenerator.generate_hash(event)
      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(event, hash)
      true

      iex> Eventasaurus.SocialCards.HashGenerator.validate_hash(event, "invalid")
      false

  """
  @spec validate_hash(map(), String.t()) :: boolean()
  def validate_hash(event, hash) when is_map(event) and is_binary(hash) do
    generate_hash(event) == hash
  end

  # Private helper functions

  # Format timestamp for consistent hashing
  defp format_timestamp(nil), do: ""
  defp format_timestamp(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(_), do: ""

  # Version string to force refresh when social card generation logic changes
  defp social_card_version do
    # This should be updated when social card template or logic changes
    "v1.0.0"
  end
end
