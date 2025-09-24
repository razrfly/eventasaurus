defmodule Eventasaurus.Services.SocialCardHash do
  @moduledoc """
  Generates unique hashes for social card filenames to enable cache invalidation.

  The hash is based on event data that affects the visual output, ensuring
  that when an event's image or title changes, a new URL is generated,
  forcing social platforms like Facebook to invalidate their cache.
  """

  @doc """
  Generates a short hash for cache busting based on event data.

  Uses SHA-256 hash of image_url + updated_at timestamp to create a unique
  identifier that changes when the event's visual content changes.

  ## Parameters

    * `event` - The event struct containing image_url and updated_at

  ## Returns

    * 16-character lowercase hex string

  ## Examples

      iex> event = %{image_url: "https://example.com/image.jpg", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.Services.SocialCardHash.generate_hash(event)
      "a1b2c3d4e5f6789a"

  """
  @spec generate_hash(map()) :: String.t()
  def generate_hash(%{image_url: image_url, updated_at: updated_at}) do
    hash_input = "#{image_url || ""}#{updated_at}"

    :crypto.hash(:sha256, hash_input)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  def generate_hash(%{image_url: image_url}) do
    # Fallback for events without updated_at timestamp
    hash_input = "#{image_url || ""}#{DateTime.utc_now()}"

    :crypto.hash(:sha256, hash_input)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  def generate_hash(_event) do
    # Fallback for events with missing required fields
    hash_input = "#{DateTime.utc_now()}"

    :crypto.hash(:sha256, hash_input)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @doc """
  Generates a complete filename for the social card PNG.

  ## Parameters

    * `event_id` - The event ID
    * `event` - The event struct for hash generation

  ## Returns

    * String filename in format "{event_id}-{hash}.png"

  ## Examples

      iex> event = %{image_url: "https://example.com/image.jpg", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.Services.SocialCardHash.generate_filename("123", event)
      "123-a1b2c3d4e5f6789a.png"

  """
  @spec generate_filename(String.t(), map()) :: String.t()
  def generate_filename(event_id, event) do
    hash = generate_hash(event)
    "#{event_id}-#{hash}.png"
  end

  @doc """
  Generates a complete file path for temporary social card files.

  ## Parameters

    * `event_id` - The event ID
    * `event` - The event struct for hash generation
    * `extension` - File extension ("svg" or "png")

  ## Returns

    * String file path in temp directory

  """
  @spec generate_temp_path(String.t(), map(), String.t()) :: String.t()
  def generate_temp_path(event_id, event, extension \\ "png") do
    ext =
      extension
      |> to_string()
      |> String.downcase()
      |> case do
        "png" -> "png"
        "svg" -> "svg"
        _ -> "png"
      end

    hash = generate_hash(event)
    sanitized_event_id = sanitize_segment(event_id)

    System.tmp_dir!()
    |> Path.join("eventasaurus_#{sanitized_event_id}_#{hash}.#{ext}")
  end

  defp sanitize_segment(seg) do
    seg
    |> to_string()
    |> String.replace(~r{[/\\]}, "_")
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    |> String.slice(0, 128)
  end
end
