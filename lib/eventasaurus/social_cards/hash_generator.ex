defmodule Eventasaurus.SocialCards.HashGenerator do
  @moduledoc """
  Generates cache-busting hashes for social card URLs.

  Creates fingerprints based on all components that affect social card appearance,
  ensuring social media platforms re-fetch cards when content changes.
  """

  @social_card_version "v1.0.0"

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
    event
    |> build_fingerprint()
    |> Jason.encode!(pretty: false, sort_keys: true)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
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
    # Use the same robust slug generation logic
    slug = case {Map.get(event, :slug), Map.get(event, :id)} do
      {slug, _} when is_binary(slug) and slug != "" -> slug
      {_, id} when not is_nil(id) -> "event-#{id}"
      _ -> "unknown-event-#{System.unique_integer([:positive])}"
    end

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
    case Regex.run(~r/\/events\/[^\/]+\/social-card-([a-f0-9]{8})(?:\.png)?$/, path) do
      [_full_match, hash] -> hash
      _ -> nil
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

  defp build_fingerprint(event) do
    # Ensure we always have a valid slug, even if :id is missing
    slug = case {Map.get(event, :slug), Map.get(event, :id)} do
      {slug, _} when is_binary(slug) and slug != "" -> slug
      {_, id} when not is_nil(id) -> "event-#{id}"
      _ -> "unknown-event-#{System.unique_integer([:positive])}"
    end

    %{
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

  defp format_timestamp(nil), do: ""
  defp format_timestamp(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(_), do: ""
end
