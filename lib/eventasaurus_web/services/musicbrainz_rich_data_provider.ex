defmodule EventasaurusWeb.Services.MusicBrainzRichDataProvider do
  @moduledoc """
  MusicBrainz provider for rich data integration.

  Implements the RichDataProviderBehaviour for music data including
  tracks, artists, albums, and playlists. Wraps the MusicBrainzService
  with the standardized provider interface.
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour

  alias EventasaurusWeb.Services.MusicBrainzService
  require Logger

  # ============================================================================
  # Provider Behaviour Implementation
  # ============================================================================

  @impl true
  def provider_id, do: :musicbrainz

  @impl true
  def provider_name, do: "MusicBrainz"

  @impl true
  def supported_types, do: [:track, :artist, :album, :playlist]

  @impl true
  def search(query, options \\ %{}) do
    page = Map.get(options, :page, 1)
    content_type = Map.get(options, :content_type)

    # Map content_type to MusicBrainz entity types
    entity = case content_type do
      :track -> :recording
      :artist -> :artist
      :album -> :release_group
      :playlist -> :release_group  # Use release_group for playlist-like searches
      _ -> :recording  # Default to recordings (tracks)
    end

    case MusicBrainzService.search_multi(query, entity, page) do
      {:ok, results} ->
        normalized_results = 
          results
          |> Enum.map(&normalize_search_result/1)
          |> deduplicate_tracks()
          |> Enum.take(8)  # Limit to 8 unique results
        {:ok, normalized_results}
      {:error, reason} ->
        Logger.error("MusicBrainz search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_details(id, type, _options \\ %{}) do
    case type do
      :track ->
        case MusicBrainzService.get_recording_details(id) do
          {:ok, recording_data} ->
            {:ok, normalize_recording_details(recording_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :artist ->
        case MusicBrainzService.get_artist_details(id) do
          {:ok, artist_data} ->
            {:ok, normalize_artist_details(artist_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :album ->
        case MusicBrainzService.get_release_group_details(id) do
          {:ok, release_group_data} ->
            {:ok, normalize_release_group_details(release_group_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :playlist ->
        # For now, treat playlists as release groups
        # In the future, this could be enhanced with custom playlist logic
        case MusicBrainzService.get_release_group_details(id) do
          {:ok, release_group_data} ->
            {:ok, normalize_release_group_details(release_group_data)}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def get_cached_details(id, type, _options \\ %{}) do
    case type do
      :track ->
        case MusicBrainzService.get_cached_recording_details(id) do
          {:ok, recording_data} ->
            {:ok, normalize_recording_details(recording_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :artist ->
        case MusicBrainzService.get_cached_artist_details(id) do
          {:ok, artist_data} ->
            {:ok, normalize_artist_details(artist_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :album ->
        case MusicBrainzService.get_cached_release_group_details(id) do
          {:ok, release_group_data} ->
            {:ok, normalize_release_group_details(release_group_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :playlist ->
        # For now, treat playlists as release groups
        case MusicBrainzService.get_cached_release_group_details(id) do
          {:ok, release_group_data} ->
            {:ok, normalize_release_group_details(release_group_data)}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def validate_config do
    # MusicBrainz doesn't require an API key, so always valid
    :ok
  end

  @impl true
  def config_schema do
    %{
      base_url: %{
        type: :string,
        required: false,
        default: "https://musicbrainz.org/ws/2",
        description: "MusicBrainz API base URL"
      },
      user_agent: %{
        type: :string,
        required: false,
        default: "Eventasaurus/0.1.0 ( https://eventasaurus.com )",
        description: "User-Agent header for MusicBrainz requests"
      },
      rate_limit: %{
        type: :integer,
        required: false,
        default: 1,
        description: "Maximum requests per second (MusicBrainz enforces 1/sec)"
      },
      cache_ttl: %{
        type: :integer,
        required: false,
        default: 21600, # 6 hours in seconds
        description: "Cache time-to-live in seconds"
      }
    }
  end

  # ============================================================================
  # Private Functions - Data Normalization
  # ============================================================================

  defp normalize_search_result(%{type: :recording} = result) do
    # Extract primary artist name from artist_credit
    primary_artist = extract_primary_artist_name(result.artist_credit)

    %{
      id: result.id,
      type: :track,
      title: result.title,
      description: build_track_description(primary_artist, result.releases),
      image_url: nil, # MusicBrainz doesn't provide cover art directly
      images: [],
      metadata: %{
        musicbrainz_id: result.id,
        length: result.length,
        disambiguation: result.disambiguation,
        artist_credit: result.artist_credit,
        releases: result.releases,
        score: result.score,
        media_type: "recording"
      }
    }
  end

  defp normalize_search_result(%{type: :artist} = result) do
    %{
      id: result.id,
      type: :artist,
      title: result.name,
      description: build_artist_description(result),
      image_url: nil, # MusicBrainz doesn't provide artist images directly
      images: [],
      metadata: %{
        musicbrainz_id: result.id,
        name: result.name,
        sort_name: result.sort_name,
        disambiguation: result.disambiguation,
        country: result.country,
        type_name: result.type_name,
        score: result.score,
        media_type: "artist"
      }
    }
  end

  defp normalize_search_result(%{type: :release_group} = result) do
    # Extract primary artist name from artist_credit
    primary_artist = extract_primary_artist_name(result.artist_credit)

    %{
      id: result.id,
      type: :album,
      title: result.title,
      description: build_album_description(primary_artist, result),
      image_url: nil, # MusicBrainz doesn't provide cover art directly
      images: [],
      metadata: %{
        musicbrainz_id: result.id,
        title: result.title,
        first_release_date: result.first_release_date,
        primary_type: result.primary_type,
        secondary_types: result.secondary_types,
        disambiguation: result.disambiguation,
        artist_credit: result.artist_credit,
        score: result.score,
        media_type: "release_group"
      }
    }
  end

  defp normalize_search_result(result) do
    # Fallback for unknown types
    %{
      id: Map.get(result, :id),
      type: Map.get(result, :type, :unknown),
      title: Map.get(result, :title) || Map.get(result, :name) || "Unknown",
      description: Map.get(result, :disambiguation) || "",
      image_url: nil,
      images: [],
      metadata: %{
        musicbrainz_id: Map.get(result, :id),
        media_type: Map.get(result, :type, "unknown")
      }
    }
  end

  defp normalize_recording_details(recording_data) do
    primary_artist = extract_primary_artist_name(recording_data.artist_credit)

    %{
      id: recording_data.musicbrainz_id,
      type: :track,
      title: recording_data.title,
      description: build_track_description(primary_artist, recording_data.releases),
      image_url: nil,
      metadata: %{
        musicbrainz_id: recording_data.musicbrainz_id,
        title: recording_data.title,
        length: recording_data.length,
        disambiguation: recording_data.disambiguation,
        artist_credit: recording_data.artist_credit,
        releases: recording_data.releases,
        isrcs: recording_data.isrcs,
        duration_ms: recording_data.length,
        duration_formatted: format_duration(recording_data.length)
      },
      images: [],
      external_urls: recording_data.external_links,
      cast: [], # Not applicable to recordings
      crew: [], # Not applicable to recordings
      media: %{
        audio_features: %{
          duration_ms: recording_data.length,
          isrcs: recording_data.isrcs
        }
      },
      additional_data: %{
        releases: recording_data.releases,
        isrcs: recording_data.isrcs
      }
    }
  end

  defp normalize_artist_details(artist_data) do
    %{
      id: artist_data.musicbrainz_id,
      type: :artist,
      title: artist_data.name,
      description: build_detailed_artist_description(artist_data),
      image_url: nil,
      metadata: %{
        musicbrainz_id: artist_data.musicbrainz_id,
        name: artist_data.name,
        sort_name: artist_data.sort_name,
        disambiguation: artist_data.disambiguation,
        type_name: artist_data.type_name,
        gender: artist_data.gender,
        country: artist_data.country,
        begin_area: artist_data.begin_area,
        end_area: artist_data.end_area,
        life_span: artist_data.life_span
      },
      images: [],
      external_urls: artist_data.external_links,
      cast: [], # Not applicable to artists
      crew: [], # Not applicable to artists
      media: %{
        discography: %{
          release_groups: artist_data.release_groups,
          releases: artist_data.releases,
          recordings: artist_data.recordings
        }
      },
      additional_data: %{
        releases: artist_data.releases,
        release_groups: artist_data.release_groups,
        recordings: artist_data.recordings,
        life_span: artist_data.life_span,
        areas: %{
          begin: artist_data.begin_area,
          end: artist_data.end_area
        }
      }
    }
  end

  defp normalize_release_group_details(release_group_data) do
    primary_artist = extract_primary_artist_name(release_group_data.artist_credit)

    %{
      id: release_group_data.musicbrainz_id,
      type: :album,
      title: release_group_data.title,
      description: build_detailed_album_description(primary_artist, release_group_data),
      image_url: nil,
      metadata: %{
        musicbrainz_id: release_group_data.musicbrainz_id,
        title: release_group_data.title,
        first_release_date: release_group_data.first_release_date,
        primary_type: release_group_data.primary_type,
        secondary_types: release_group_data.secondary_types,
        disambiguation: release_group_data.disambiguation,
        artist_credit: release_group_data.artist_credit,
        release_count: length(release_group_data.releases || [])
      },
      images: [],
      external_urls: release_group_data.external_links,
      cast: [], # Not applicable to release groups
      crew: [], # Not applicable to release groups
      media: %{
        releases: release_group_data.releases
      },
      additional_data: %{
        releases: release_group_data.releases,
        primary_type: release_group_data.primary_type,
        secondary_types: release_group_data.secondary_types
      }
    }
  end

  # Helper functions for building descriptions and extracting data

  defp extract_primary_artist_name([]), do: "Unknown Artist"
  defp extract_primary_artist_name([%{artist: %{name: name}} | _]), do: name
  defp extract_primary_artist_name([%{name: name} | _]), do: name
  defp extract_primary_artist_name(_), do: "Unknown Artist"

  defp build_track_description(artist_name, releases) when is_list(releases) do
    case releases do
      [%{title: release_title} | _] ->
        "#{artist_name} - #{release_title}"
      [] ->
        "#{artist_name}"
      _ ->
        "#{artist_name}"
    end
  end

  defp build_track_description(artist_name, _), do: artist_name

  defp build_artist_description(result) do
    parts = []

    parts = if result.type_name do
      [result.type_name | parts]
    else
      parts
    end

    parts = if result.country do
      [result.country | parts]
    else
      parts
    end

    parts = if result.disambiguation do
      [result.disambiguation | parts]
    else
      parts
    end

    case parts do
      [] -> ""
      _ -> Enum.join(parts, " • ")
    end
  end

  defp build_album_description(artist_name, result) do
    parts = [artist_name]

    parts = if result.primary_type do
      parts ++ [result.primary_type]
    else
      parts
    end

    parts = if result.first_release_date do
      year = result.first_release_date |> String.split("-") |> List.first()
      parts ++ ["(#{year})"]
    else
      parts
    end

    Enum.join(parts, " • ")
  end

  defp build_detailed_artist_description(artist_data) do
    parts = []

    parts = if artist_data.type_name do
      [artist_data.type_name | parts]
    else
      parts
    end

    # Add life span information
    parts = case artist_data.life_span do
      %{begin: begin_date, end: end_date} when not is_nil(begin_date) ->
        if end_date do
          ["(#{begin_date} - #{end_date})" | parts]
        else
          ["(#{begin_date} - )" | parts]
        end
      _ ->
        parts
    end

    parts = if artist_data.country do
      [artist_data.country | parts]
    else
      parts
    end

    parts = if artist_data.disambiguation do
      [artist_data.disambiguation | parts]
    else
      parts
    end

    case parts do
      [] -> ""
      _ -> Enum.join(Enum.reverse(parts), " • ")
    end
  end

  defp build_detailed_album_description(artist_name, release_group_data) do
    parts = [artist_name]

    parts = if release_group_data.primary_type do
      parts ++ [release_group_data.primary_type]
    else
      parts
    end

    parts = if not Enum.empty?(release_group_data.secondary_types || []) do
      secondary_str = Enum.join(release_group_data.secondary_types, ", ")
      parts ++ [secondary_str]
    else
      parts
    end

    parts = if release_group_data.first_release_date do
      year = release_group_data.first_release_date |> String.split("-") |> List.first()
      parts ++ ["(#{year})"]
    else
      parts
    end

    release_count = length(release_group_data.releases || [])
    parts = if release_count > 1 do
      parts ++ ["#{release_count} releases"]
    else
      parts
    end

    Enum.join(parts, " • ")
  end

  defp format_duration(nil), do: nil
  defp format_duration(milliseconds) when is_integer(milliseconds) do
    seconds = div(milliseconds, 1000)
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
  end
  defp format_duration(_), do: nil

  # Deduplication function to reduce multiple releases of the same song
  defp deduplicate_tracks(results) do
    results
    |> Enum.group_by(&get_track_key/1)
    |> Enum.map(fn {_key, tracks} ->
      # Keep the track with highest score or most recent if scores are equal
      Enum.max_by(tracks, &get_track_priority/1)
    end)
    |> Enum.sort_by(&get_track_priority/1, :desc)
  end

  defp get_track_key(%{type: :track, title: title, metadata: metadata}) do
    primary_artist = extract_primary_artist_name(metadata.artist_credit || [])
    # Create a normalized key for grouping duplicates
    normalized_title = String.downcase(String.trim(title))
    normalized_artist = String.downcase(String.trim(primary_artist))
    {normalized_title, normalized_artist}
  end

  defp get_track_key(_), do: :unknown

  defp get_track_priority(%{metadata: metadata}) do
    score = Map.get(metadata, :score, 0)
    # Prefer higher scores, and as a tiebreaker prefer recordings with more release info
    release_count = length(Map.get(metadata, :releases, []))
    {score, release_count}
  end

  defp get_track_priority(_), do: {0, 0}
end