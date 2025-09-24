defmodule EventasaurusWeb.Services.MusicBrainzRichDataProvider do
  @moduledoc """
  MusicBrainz rich data provider for music track search.

  This is a simplified provider that works with the frontend JavaScript
  MusicBrainz API integration. It focuses on tracks/recordings only and
  provides a clean interface that delegates actual search operations
  to the client-side code for better rate limiting and user experience.
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour

  require Logger

  # ============================================================================
  # Provider Behaviour Implementation
  # ============================================================================

  @impl true
  def provider_id, do: :musicbrainz

  @impl true
  def provider_name, do: "MusicBrainz"

  @impl true
  def supported_types, do: [:track]

  @impl true
  def search(query, options \\ %{}) do
    Logger.info("MusicBrainz backend search for: \"#{query}\"")

    case perform_musicbrainz_search(query, options) do
      {:ok, results} ->
        Logger.info("MusicBrainz search returned #{length(results)} results")
        {:ok, results}

      {:error, reason} ->
        Logger.error("MusicBrainz search failed: #{inspect(reason)}")
        {:ok, []}
    end
  end

  @impl true
  def get_details(id, type, _options \\ %{}) do
    case type do
      :track ->
        # For now, return minimal details since actual details fetching
        # is handled client-side. In the future, this could be enhanced
        # to fetch additional server-side data if needed.
        {:ok, create_placeholder_track_details(id)}

      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def get_cached_details(id, type, options \\ %{}) do
    # Since we're not maintaining server-side cache for this provider,
    # we delegate to get_details
    get_details(id, type, options)
  end

  @impl true
  def validate_config do
    # MusicBrainz doesn't require an API key and search is handled client-side,
    # so this is always valid
    :ok
  end

  @impl true
  def config_schema do
    %{
      # No configuration required since the actual API calls
      # are made from the frontend using the musicbrainz-api package
      frontend_search: %{
        type: :boolean,
        required: false,
        default: true,
        description: "Uses frontend JavaScript for search (always true for this provider)"
      },
      user_agent: %{
        type: :string,
        required: false,
        default: "Eventasaurus/1.0.0 ( https://eventasaurus.com )",
        description: "User-Agent header for MusicBrainz requests (configured in frontend)"
      }
    }
  end

  @impl true
  def normalize_data(raw_data, type) do
    case type do
      :track ->
        {:ok, normalize_track_data(raw_data)}

      _ ->
        {:error, "Unsupported content type for normalization: #{type}"}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp perform_musicbrainz_search(query, options) do
    # MusicBrainz API endpoint
    base_url = "https://musicbrainz.org/ws/2/recording"
    sanitized = sanitize_query(query)
    search_query = "recording:\"#{sanitized}\""

    # Build request URL with proper parameters
    url =
      "#{base_url}?" <>
        URI.encode_query(%{
          "query" => search_query,
          "limit" => to_string(Map.get(options, :limit, 8)),
          "fmt" => "json",
          "inc" => "artist-credits+releases"
        })

    headers = [
      {"User-Agent", "Eventasaurus/1.0.0 ( https://eventasaurus.com )"},
      {"Accept", "application/json"}
    ]

    case HTTPoison.get(url, headers, timeout: 10_000, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"recordings" => recordings}} ->
            results = Enum.map(recordings, &format_musicbrainz_result/1)
            {:ok, results}

          {:ok, _} ->
            {:ok, []}

          {:error, _} ->
            {:error, "Failed to parse MusicBrainz response"}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "MusicBrainz API returned status #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{reason}"}
    end
  end

  defp format_musicbrainz_result(recording) do
    # Extract artist info
    artist_credits = recording["artist-credit"] || []

    artists =
      Enum.map(artist_credits, fn credit ->
        credit["artist"]["name"] || "Unknown Artist"
      end)

    artist_name = Enum.join(artists, " & ")

    # Extract release info if available
    releases = recording["releases"] || []

    release_title =
      case releases do
        [first_release | _] -> first_release["title"]
        [] -> nil
      end

    # Format title and description
    title = recording["title"] || "Unknown Track"

    description =
      case {artist_name, release_title} do
        {artist, nil} -> "by #{artist}"
        {artist, release} -> "by #{artist} (#{release})"
      end

    %{
      id: recording["id"],
      type: :track,
      title: title,
      description: description,
      image_url: nil,
      metadata: %{
        musicbrainz_id: recording["id"],
        artist: artist_name,
        release: release_title,
        score: recording["score"] || 0,
        length: recording["length"]
      },
      external_urls: %{
        musicbrainz: "https://musicbrainz.org/recording/#{recording["id"]}"
      }
    }
  end

  defp create_placeholder_track_details(id) do
    %{
      id: id,
      type: :track,
      title: "Music Track",
      description: "Track details available via frontend search",
      image_url: nil,
      metadata: %{
        musicbrainz_id: id,
        media_type: "recording",
        frontend_managed: true
      },
      images: [],
      external_urls: %{
        musicbrainz: "https://musicbrainz.org/recording/#{id}"
      },
      # Not applicable to music tracks
      cast: [],
      # Not applicable to music tracks
      crew: [],
      media: %{
        audio_features: %{}
      },
      additional_data: %{
        note:
          "Track search and details are handled by frontend JavaScript using musicbrainz-api package"
      }
    }
  end

  defp normalize_track_data(raw_data) do
    # Normalize frontend-provided track data into our standard format
    %{
      id: get_nested_value(raw_data, ["id"]),
      type: :track,
      title: get_nested_value(raw_data, ["title"]),
      description: get_nested_value(raw_data, ["description"]),
      image_url: get_nested_value(raw_data, ["image_url"]),
      metadata: get_nested_value(raw_data, ["metadata"], %{}),
      images: get_nested_value(raw_data, ["images"], []),
      external_urls: %{
        musicbrainz: "https://musicbrainz.org/recording/#{get_nested_value(raw_data, ["id"])}"
      },
      # Not applicable to music tracks
      cast: [],
      # Not applicable to music tracks
      crew: [],
      media: %{
        audio_features: get_nested_value(raw_data, ["metadata", "audio_features"], %{})
      },
      additional_data: get_nested_value(raw_data, ["additional_data"], %{})
    }
  end

  defp get_nested_value(map, keys, default \\ nil) do
    Enum.reduce(keys, map, fn key, acc ->
      if is_map(acc) && Map.has_key?(acc, key) do
        Map.get(acc, key)
      else
        default
      end
    end)
  end

  defp sanitize_query(query) when is_binary(query) do
    query |> String.replace("\"", "\\\"") |> String.trim()
  end

  defp sanitize_query(other), do: to_string(other)
end
