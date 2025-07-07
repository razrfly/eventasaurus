defmodule EventasaurusWeb.Services.SpotifyRichDataProvider do
  @moduledoc """
  Spotify provider for rich data integration.

  An example implementation of RichDataProviderBehaviour for music data.
  This demonstrates how to extend the system with additional providers.

  ## Configuration

  Requires SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET environment variables.
  See: https://developer.spotify.com/documentation/web-api/

  ## Supported Content Types

  - `:music` - Albums, tracks, playlists
  - `:artist` - Artists and bands
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour

  require Logger

  # Note: This is a skeleton implementation for demonstration.
  # A full implementation would include proper HTTP client setup,
  # authentication token management, and comprehensive API integration.

  # ============================================================================
  # Provider Behaviour Implementation
  # ============================================================================

  @impl true
  def provider_id, do: :spotify

  @impl true
  def provider_name, do: "Spotify"

  @impl true
  def supported_types, do: [:music, :artist]

  @impl true
  def search(query, options \\ %{}) do
    # Skeleton implementation - would integrate with Spotify Web API
    Logger.info("Spotify search for: #{query} with options: #{inspect(options)}")

    # Mock response for demonstration
    mock_results = [
      %{
        id: "4uLU6hMCjMI75M1A2tKUQC",
        type: :music,
        title: "Example Album",
        description: "An example music album from Spotify",
        images: [
          %{url: "https://i.scdn.co/image/example", type: :cover, size: "640x640"}
        ],
        metadata: %{
          spotify_id: "4uLU6hMCjMI75M1A2tKUQC",
          album_type: "album",
          artists: ["Example Artist"],
          release_date: "2023-01-01"
        }
      }
    ]

    {:ok, mock_results}
  end

  @impl true
  def get_details(id, type, options \\ %{}) do
    # Skeleton implementation - would fetch detailed data from Spotify API
    Logger.info("Spotify get_details for: #{id} (#{type}) with options: #{inspect(options)}")

    case type do
      :music ->
        mock_album_details(id)
      :artist ->
        mock_artist_details(id)
      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def get_cached_details(id, type, options \\ %{}) do
    # For this example, no caching - fall back to regular details
    # A full implementation would include ETS or other caching mechanism
    get_details(id, type, options)
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

  # ============================================================================
  # Private Functions - Mock Data
  # ============================================================================

  defp mock_album_details(album_id) do
    details = %{
      id: album_id,
      type: :music,
      title: "Example Album Title",
      description: "A comprehensive album with rich metadata from Spotify",
      metadata: %{
        spotify_id: album_id,
        album_type: "album",
        total_tracks: 12,
        release_date: "2023-01-01",
        release_date_precision: "day",
        artists: [
          %{id: "artist123", name: "Example Artist", type: "artist"}
        ],
        genres: ["pop", "electronic"],
        label: "Example Records",
        popularity: 85,
        available_markets: ["US", "CA", "GB"],
        copyrights: [
          %{text: "2023 Example Records", type: "C"}
        ]
      },
      images: [
        %{url: "https://i.scdn.co/image/640x640", type: :cover, size: "640x640", width: 640, height: 640},
        %{url: "https://i.scdn.co/image/300x300", type: :cover, size: "300x300", width: 300, height: 300},
        %{url: "https://i.scdn.co/image/64x64", type: :cover, size: "64x64", width: 64, height: 64}
      ],
      external_urls: %{
        spotify: "https://open.spotify.com/album/#{album_id}"
      },
      cast: [], # Not applicable for music
      crew: [
        %{name: "Producer Name", job: "Producer", department: "Production"},
        %{name: "Engineer Name", job: "Audio Engineer", department: "Sound"}
      ],
      media: %{
        tracks: [
          %{
            id: "track1",
            name: "Track 1 Title",
            duration_ms: 180000,
            track_number: 1,
            explicit: false,
            preview_url: "https://p.scdn.co/mp3-preview/example"
          },
          %{
            id: "track2",
            name: "Track 2 Title",
            duration_ms: 210000,
            track_number: 2,
            explicit: false,
            preview_url: nil
          }
        ],
        audio_features: %{
          danceability: 0.735,
          energy: 0.578,
          valence: 0.624,
          tempo: 120.0
        }
      },
      additional_data: %{
        related_albums: [],
        top_tracks: [],
        similar_artists: []
      }
    }

    {:ok, details}
  end

  defp mock_artist_details(artist_id) do
    details = %{
      id: artist_id,
      type: :artist,
      title: "Example Artist Name",
      description: "A popular music artist with comprehensive metadata",
      metadata: %{
        spotify_id: artist_id,
        followers: 1250000,
        genres: ["pop", "electronic", "indie"],
        popularity: 78,
        artist_type: "artist"
      },
      images: [
        %{url: "https://i.scdn.co/image/artist640", type: :photo, size: "640x640", width: 640, height: 640},
        %{url: "https://i.scdn.co/image/artist320", type: :photo, size: "320x320", width: 320, height: 320},
        %{url: "https://i.scdn.co/image/artist160", type: :photo, size: "160x160", width: 160, height: 160}
      ],
      external_urls: %{
        spotify: "https://open.spotify.com/artist/#{artist_id}"
      },
      cast: [], # Not applicable for artists
      crew: [], # Not applicable for artists
      media: %{
        top_tracks: [
          %{
            id: "track123",
            name: "Popular Song",
            popularity: 89,
            preview_url: "https://p.scdn.co/mp3-preview/popular"
          }
        ],
        albums: [
          %{
            id: "album123",
            name: "Latest Album",
            release_date: "2023-01-01",
            total_tracks: 12
          }
        ]
      },
      additional_data: %{
        related_artists: [
          %{id: "related1", name: "Similar Artist 1"},
          %{id: "related2", name: "Similar Artist 2"}
        ],
        appears_on: [],
        compilations: []
      }
    }

    {:ok, details}
  end
end
