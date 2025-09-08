defmodule EventasaurusWeb.Services.SpotifyRichDataProvider do
  @moduledoc """
  Spotify provider for rich data integration.

  Implements the RichDataProviderBehaviour for music track data.
  Wraps the SpotifyService with the standardized provider interface.

  ## Configuration

  Requires SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET environment variables.
  See: https://developer.spotify.com/documentation/web-api/

  ## Supported Content Types

  - `:track` - Music tracks with full metadata and audio features
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour

  alias EventasaurusWeb.Services.SpotifyService
  require Logger

  # ============================================================================
  # Provider Behaviour Implementation
  # ============================================================================

  @impl true
  def provider_id, do: :spotify

  @impl true
  def provider_name, do: "Spotify"

  @impl true
  def supported_types, do: [:track]

  @impl true
  def search(query, options \\ %{}) do
    limit = Map.get(options, :limit, 20)
    content_type = Map.get(options, :content_type)

    # Only search if content_type is track or not specified
    case content_type do
      :track -> perform_search(query, limit)
      nil -> perform_search(query, limit)
      _ -> {:ok, []} # Don't search for other types
    end
  end

  defp perform_search(query, limit) do
    case SpotifyService.search_tracks(query, limit) do
      {:ok, tracks} ->
        normalized_results = Enum.map(tracks, &normalize_search_result/1)
        {:ok, normalized_results}
        
      {:error, reason} ->
        Logger.error("Spotify search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_details(id, type, options \\ %{}) do
    case type do
      :track ->
        case SpotifyService.get_track_details(id) do
          {:ok, track_data} ->
            {:ok, normalize_track_details(track_data)}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def get_cached_details(id, type, options \\ %{}) do
    case type do
      :track ->
        case SpotifyService.get_cached_track_details(id) do
          {:ok, track_data} ->
            {:ok, normalize_track_details(track_data)}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def validate_config do
    client_id = System.get_env("SPOTIFY_CLIENT_ID")
    client_secret = System.get_env("SPOTIFY_CLIENT_SECRET")

    cond do
      is_nil(client_id) or client_id == "" ->
        {:error, "SPOTIFY_CLIENT_ID environment variable is not set"}
      is_nil(client_secret) or client_secret == "" ->
        {:error, "SPOTIFY_CLIENT_SECRET environment variable is not set"}
      true ->
        :ok
    end
  end

  @impl true
  def config_schema do
    %{
      client_id: %{
        type: :string,
        required: true,
        description: "Spotify Client ID from https://developer.spotify.com/dashboard/applications"
      },
      client_secret: %{
        type: :string,
        required: true,
        description: "Spotify Client Secret from your Spotify app dashboard"
      },
      base_url: %{
        type: :string,
        required: false,
        default: "https://api.spotify.com/v1",
        description: "Spotify Web API base URL"
      },
      rate_limit: %{
        type: :integer,
        required: false,
        default: 100,
        description: "Maximum requests per minute"
      },
      cache_ttl: %{
        type: :integer,
        required: false,
        default: 3600, # 1 hour in seconds
        description: "Cache time-to-live in seconds"
      }
    }
  end

  @impl true
  def normalize_data(raw_data, type) do
    case type do
      :track ->
        {:ok, normalize_track_details(raw_data)}
      _ ->
        {:error, "Unsupported content type for normalization: #{type}"}
    end
  end

  # ============================================================================
  # Private Functions - Data Normalization
  # ============================================================================

  defp normalize_search_result(track) do
    artists = track[:artists] || []
    primary_artist = List.first(artists) || "Unknown Artist"
    
    # Format description like "Artist - Album"
    description = case track[:album] do
      nil -> primary_artist
      album -> "#{primary_artist} - #{album}"
    end

    %{
      id: track[:id],
      type: :track,
      title: track[:title],
      description: description,
      image_url: track[:image_url],
      external_urls: %{
        spotify: track[:external_url]
      },
      metadata: %{
        spotify_id: track[:id],
        artist: primary_artist,
        artists: artists,
        album: track[:album],
        duration_ms: track[:duration_ms],
        duration_formatted: track[:duration_formatted],
        popularity: track[:popularity],
        explicit: track[:explicit],
        preview_url: track[:preview_url]
      },
      images: build_images_from_url(track[:image_url])
    }
  end

  defp normalize_track_details(track_data) do
    artists = track_data[:artists] || []
    primary_artist = List.first(artists) || "Unknown Artist"
    
    description = case track_data[:album] do
      nil -> primary_artist
      album -> "#{primary_artist} - #{album}"
    end

    # Get the best image from available images
    images = track_data[:images] || []
    image_url = get_best_image_url(images)

    %{
      id: track_data[:id],
      type: :track,
      title: track_data[:title],
      description: description,
      image_url: image_url,
      metadata: %{
        spotify_id: track_data[:id],
        artist: primary_artist,
        artists: artists,
        album: track_data[:album],
        album_release_date: track_data[:album_release_date],
        album_type: track_data[:album_type],
        duration_ms: track_data[:duration_ms],
        popularity: track_data[:popularity],
        explicit: track_data[:explicit],
        preview_url: track_data[:preview_url],
        disc_number: track_data[:disc_number],
        track_number: track_data[:track_number],
        available_markets: track_data[:available_markets] || []
      },
      images: normalize_images(images),
      external_urls: %{
        spotify: track_data[:external_url]
      },
      cast: [], # Not applicable to music tracks
      crew: [], # Could include producers, writers in the future
      media: %{
        audio_features: track_data[:audio_features] || %{},
        duration_formatted: format_duration(track_data[:duration_ms]),
        preview: %{
          url: track_data[:preview_url],
          available: !is_nil(track_data[:preview_url])
        }
      },
      additional_data: %{
        spotify_track_data: track_data,
        audio_analysis_available: !is_nil(track_data[:audio_features])
      }
    }
  end

  defp normalize_images(images) when is_list(images) do
    Enum.map(images, fn image ->
      %{
        url: image["url"],
        type: :cover,
        width: image["width"],
        height: image["height"],
        size: "#{image["width"]}x#{image["height"]}"
      }
    end)
  end
  defp normalize_images(_), do: []

  defp build_images_from_url(nil), do: []
  defp build_images_from_url(image_url) do
    [%{url: image_url, type: :cover, size: "unknown"}]
  end

  defp get_best_image_url([]), do: nil
  defp get_best_image_url([image | _rest]) when is_map(image) do
    image["url"]
  end
  defp get_best_image_url(_), do: nil

  defp format_duration(nil), do: nil
  defp format_duration(ms) when is_integer(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    
    "#{minutes}:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
  end
  defp format_duration(_), do: nil
end
