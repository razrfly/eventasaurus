defmodule EventasaurusWeb.Services.MusicBrainzService do
  @moduledoc """
  Service for interacting with the MusicBrainz API.
  Supports searching and detailed data fetching for artists, recordings, releases, and release groups with caching.
  
  Follows the same patterns as TmdbService for consistency.
  """

  @behaviour EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  use GenServer
  require Logger

  @base_url "https://musicbrainz.org/ws/2"
  @cache_table :musicbrainz_cache
  @cache_ttl :timer.hours(6) # Cache for 6 hours (same as TMDB)
  @rate_limit_table :musicbrainz_rate_limit
  @rate_limit_window :timer.seconds(1) # 1 second window
  @rate_limit_max_requests 1 # Max 1 request per second (MusicBrainz requirement)
  @user_agent "Eventasaurus/0.1.0 ( https://eventasaurus.com )"

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Search for music content across different entity types.
  
  ## Parameters
  
  - `query`: Search term
  - `entity`: Entity type (:artist, :recording, :release, :release_group)
  - `page`: Page number (optional, defaults to 1)
  
  ## Examples
  
      iex> MusicBrainzService.search_multi("Beatles", :artist)
      {:ok, [%{type: :artist, id: "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d", name: "The Beatles", ...}]}
      
      iex> MusicBrainzService.search_multi("Yesterday", :recording)
      {:ok, [%{type: :recording, id: "...", title: "Yesterday", artist: "The Beatles", ...}]}
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def search_multi(query, entity, page \\ 1) do
    # Handle nil or empty queries
    if is_nil(query) or String.trim(to_string(query)) == "" do
      {:ok, []}
    else
      with :ok <- check_rate_limit() do
        fetch_search_results(query, entity, page)
      else
        {:error, :rate_limited} ->
          {:error, "Rate limit exceeded, please try again later"}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get cached artist details or fetch from API if not cached.
  This is the recommended way to get artist details for performance.
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_cached_artist_details(artist_id) do
    GenServer.call(__MODULE__, {:get_cached_artist_details, artist_id}, 30_000)
  end

  @doc """
  Get detailed artist information including releases and recordings.
  This bypasses the cache and always fetches fresh data.
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_artist_details(artist_id) do
    with :ok <- check_rate_limit() do
      fetch_artist_details(artist_id)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get cached recording details or fetch from API if not cached.
  This is the recommended way to get recording details for performance.
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_cached_recording_details(recording_id) do
    GenServer.call(__MODULE__, {:get_cached_recording_details, recording_id}, 30_000)
  end

  @doc """
  Get detailed recording information including artist and release data.
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_recording_details(recording_id) do
    with :ok <- check_rate_limit() do
      fetch_recording_details(recording_id)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get cached release details or fetch from API if not cached.
  This is the recommended way to get release details for performance.
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_cached_release_details(release_id) do
    GenServer.call(__MODULE__, {:get_cached_release_details, release_id}, 30_000)
  end

  @doc """
  Get detailed release information including track listing and artist data.
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_release_details(release_id) do
    with :ok <- check_rate_limit() do
      fetch_release_details(release_id)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get cached release group details or fetch from API if not cached.
  This is the recommended way to get release group details for performance.
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_cached_release_group_details(release_group_id) do
    GenServer.call(__MODULE__, {:get_cached_release_group_details, release_group_id}, 30_000)
  end

  @doc """
  Get detailed release group information (album-level data).
  """
  @impl EventasaurusWeb.Services.MusicBrainzServiceBehaviour
  def get_release_group_details(release_group_id) do
    with :ok <- check_rate_limit() do
      fetch_release_group_details(release_group_id)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @impl true
  def init(_state) do
    # Initialize cache and rate limit tables
    :ets.new(@cache_table, [:named_table, :public, :set])
    :ets.new(@rate_limit_table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_cached_artist_details, artist_id}, _from, state) do
    result = case get_from_cache("artist_#{artist_id}") do
      {:ok, cached_data} ->
        {:ok, cached_data}
      {:error, :not_found} ->
        fetch_and_cache_artist_details(artist_id)
    end
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_cached_recording_details, recording_id}, _from, state) do
    result = case get_from_cache("recording_#{recording_id}") do
      {:ok, cached_data} ->
        {:ok, cached_data}
      {:error, :not_found} ->
        fetch_and_cache_recording_details(recording_id)
    end
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_cached_release_details, release_id}, _from, state) do
    result = case get_from_cache("release_#{release_id}") do
      {:ok, cached_data} ->
        {:ok, cached_data}
      {:error, :not_found} ->
        fetch_and_cache_release_details(release_id)
    end
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_cached_release_group_details, release_group_id}, _from, state) do
    result = case get_from_cache("release_group_#{release_group_id}") do
      {:ok, cached_data} ->
        {:ok, cached_data}
      {:error, :not_found} ->
        fetch_and_cache_release_group_details(release_group_id)
    end
    {:reply, result, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp check_rate_limit do
    current_time = System.monotonic_time(:millisecond)
    window_start = current_time - @rate_limit_window

    # Clean old entries
    :ets.select_delete(@rate_limit_table, [{{:"$1", :"$2"}, [{:<, :"$2", window_start}], [true]}])

    # Count current requests in window
    count = :ets.info(@rate_limit_table, :size)

    if count < @rate_limit_max_requests do
      :ets.insert(@rate_limit_table, {make_ref(), current_time})
      :ok
    else
      {:error, :rate_limited}
    end
  end

  defp get_from_cache(cache_key) do
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, data, timestamp}] ->
        if cache_valid?(timestamp) do
          {:ok, data}
        else
          :ets.delete(@cache_table, cache_key)
          {:error, :not_found}
        end
      [] ->
        {:error, :not_found}
    end
  end

  defp put_in_cache(cache_key, data) do
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(@cache_table, {cache_key, data, timestamp})
  end

  defp cache_valid?(timestamp) do
    current_time = System.monotonic_time(:millisecond)
    (current_time - timestamp) < @cache_ttl
  end

  defp get_headers do
    [
      {"Accept", "application/json"},
      {"User-Agent", @user_agent}
    ]
  end

  defp fetch_search_results(query, entity, page) do
    entity_str = Atom.to_string(entity)
    # MusicBrainz uses 'release-group' in URLs but :release_group as atom
    entity_url = if entity == :release_group, do: "release-group", else: entity_str
    
    offset = (page - 1) * 25 # MusicBrainz default limit is 25
    url = "#{@base_url}/#{entity_url}?query=#{URI.encode(query)}&fmt=json&limit=25&offset=#{offset}"
    
    Logger.debug("MusicBrainz search URL: #{@base_url}/#{entity_url}?query=#{URI.encode(query)}&fmt=json&limit=25&offset=#{offset}")

    case HTTPoison.get(url, get_headers(), timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response_data} ->
            Logger.debug("MusicBrainz raw response keys: #{inspect(Map.keys(response_data))}")
            results = extract_search_results(response_data, entity)
            Logger.debug("Extracted #{length(results)} results for entity #{entity}")
            formatted_results = Enum.map(results, &format_search_result(&1, entity))
            Logger.debug("Formatted #{length(formatted_results)} results")
            {:ok, formatted_results}
          {:error, decode_error} ->
            Logger.error("Failed to decode MusicBrainz search response: #{inspect(decode_error)}")
            {:error, "Failed to decode search results"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("MusicBrainz search error: #{code} - #{body}")
        {:error, "MusicBrainz API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("MusicBrainz search HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp extract_search_results(response_data, :artist), do: Map.get(response_data, "artists", [])
  defp extract_search_results(response_data, :recording), do: Map.get(response_data, "recordings", [])
  defp extract_search_results(response_data, :release), do: Map.get(response_data, "releases", [])
  defp extract_search_results(response_data, :release_group), do: Map.get(response_data, "release-groups", [])

  defp format_search_result(result, :artist) do
    %{
      type: :artist,
      id: result["id"],
      name: result["name"],
      sort_name: result["sort-name"],
      disambiguation: result["disambiguation"],
      country: result["country"],
      type_name: result["type"],
      score: result["score"]
    }
  end

  defp format_search_result(result, :recording) do
    %{
      type: :recording,
      id: result["id"],
      title: result["title"],
      length: result["length"],
      disambiguation: result["disambiguation"],
      artist_credit: format_artist_credit(result["artist-credit"]),
      releases: format_recording_releases(result["releases"]),
      score: result["score"]
    }
  end

  defp format_search_result(result, :release) do
    %{
      type: :release,
      id: result["id"],
      title: result["title"],
      date: result["date"],
      country: result["country"],
      barcode: result["barcode"],
      disambiguation: result["disambiguation"],
      artist_credit: format_artist_credit(result["artist-credit"]),
      release_group: format_release_group_ref(result["release-group"]),
      score: result["score"]
    }
  end

  defp format_search_result(result, :release_group) do
    %{
      type: :release_group,
      id: result["id"],
      title: result["title"],
      first_release_date: result["first-release-date"],
      primary_type: result["primary-type"],
      secondary_types: result["secondary-types"] || [],
      disambiguation: result["disambiguation"],
      artist_credit: format_artist_credit(result["artist-credit"]),
      score: result["score"]
    }
  end

  defp format_artist_credit(nil), do: []
  defp format_artist_credit(artist_credit) when is_list(artist_credit) do
    Enum.map(artist_credit, fn credit ->
      %{
        name: credit["name"],
        artist: %{
          id: credit["artist"]["id"],
          name: credit["artist"]["name"],
          sort_name: credit["artist"]["sort-name"]
        }
      }
    end)
  end

  defp format_recording_releases(nil), do: []
  defp format_recording_releases(releases) when is_list(releases) do
    releases
    |> Enum.take(3) # Limit to 3 releases per recording
    |> Enum.map(fn release ->
      %{
        id: release["id"],
        title: release["title"],
        date: release["date"]
      }
    end)
  end

  defp format_release_group_ref(nil), do: nil
  defp format_release_group_ref(release_group) do
    %{
      id: release_group["id"],
      title: release_group["title"],
      primary_type: release_group["primary-type"]
    }
  end

  defp fetch_and_cache_artist_details(artist_id) do
    case get_artist_details(artist_id) do
      {:ok, artist_data} ->
        put_in_cache("artist_#{artist_id}", artist_data)
        {:ok, artist_data}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_and_cache_recording_details(recording_id) do
    case get_recording_details(recording_id) do
      {:ok, recording_data} ->
        put_in_cache("recording_#{recording_id}", recording_data)
        {:ok, recording_data}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_and_cache_release_details(release_id) do
    case get_release_details(release_id) do
      {:ok, release_data} ->
        put_in_cache("release_#{release_id}", release_data)
        {:ok, release_data}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_and_cache_release_group_details(release_group_id) do
    case get_release_group_details(release_group_id) do
      {:ok, release_group_data} ->
        put_in_cache("release_group_#{release_group_id}", release_group_data)
        {:ok, release_group_data}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_artist_details(artist_id) do
    # Include releases and recordings in the response
    inc = "releases+recordings+release-groups"
    url = "#{@base_url}/artist/#{artist_id}?fmt=json&inc=#{inc}"

    Logger.debug("MusicBrainz artist details URL: #{@base_url}/artist/#{artist_id}?fmt=json&inc=#{inc}")

    case HTTPoison.get(url, get_headers(), timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, artist_data} ->
            {:ok, format_detailed_artist_data(artist_data)}
          {:error, decode_error} ->
            Logger.error("Failed to decode MusicBrainz artist response: #{inspect(decode_error)}")
            {:error, "Failed to decode artist data"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Artist not found"}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("MusicBrainz artist details error: #{code} - #{body}")
        {:error, "MusicBrainz API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("MusicBrainz artist details HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_recording_details(recording_id) do
    # Include releases, artist credits, and ISRCs
    inc = "releases+artist-credits+isrcs"
    url = "#{@base_url}/recording/#{recording_id}?fmt=json&inc=#{inc}"

    Logger.debug("MusicBrainz recording details URL: #{@base_url}/recording/#{recording_id}?fmt=json&inc=#{inc}")

    case HTTPoison.get(url, get_headers(), timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, recording_data} ->
            {:ok, format_detailed_recording_data(recording_data)}
          {:error, decode_error} ->
            Logger.error("Failed to decode MusicBrainz recording response: #{inspect(decode_error)}")
            {:error, "Failed to decode recording data"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Recording not found"}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("MusicBrainz recording details error: #{code} - #{body}")
        {:error, "MusicBrainz API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("MusicBrainz recording details HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_release_details(release_id) do
    # Include recordings, artist credits, and labels
    inc = "recordings+artist-credits+labels"
    url = "#{@base_url}/release/#{release_id}?fmt=json&inc=#{inc}"

    Logger.debug("MusicBrainz release details URL: #{@base_url}/release/#{release_id}?fmt=json&inc=#{inc}")

    case HTTPoison.get(url, get_headers(), timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, release_data} ->
            {:ok, format_detailed_release_data(release_data)}
          {:error, decode_error} ->
            Logger.error("Failed to decode MusicBrainz release response: #{inspect(decode_error)}")
            {:error, "Failed to decode release data"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Release not found"}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("MusicBrainz release details error: #{code} - #{body}")
        {:error, "MusicBrainz API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("MusicBrainz release details HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_release_group_details(release_group_id) do
    # Include releases and artist credits
    inc = "releases+artist-credits"
    url = "#{@base_url}/release-group/#{release_group_id}?fmt=json&inc=#{inc}"

    Logger.debug("MusicBrainz release group details URL: #{@base_url}/release-group/#{release_group_id}?fmt=json&inc=#{inc}")

    case HTTPoison.get(url, get_headers(), timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, release_group_data} ->
            {:ok, format_detailed_release_group_data(release_group_data)}
          {:error, decode_error} ->
            Logger.error("Failed to decode MusicBrainz release group response: #{inspect(decode_error)}")
            {:error, "Failed to decode release group data"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Release group not found"}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("MusicBrainz release group details error: #{code} - #{body}")
        {:error, "MusicBrainz API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("MusicBrainz release group details HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  # Helper functions for formatting detailed data

  defp format_detailed_artist_data(artist_data) do
    %{
      source: "musicbrainz",
      type: "artist",
      musicbrainz_id: artist_data["id"],
      name: artist_data["name"],
      sort_name: artist_data["sort-name"],
      disambiguation: artist_data["disambiguation"],
      type_name: artist_data["type"],
      gender: artist_data["gender"],
      country: artist_data["country"],
      begin_area: format_area(artist_data["begin-area"]),
      end_area: format_area(artist_data["end-area"]),
      life_span: format_life_span(artist_data["life-span"]),
      releases: format_releases_summary(artist_data["releases"]),
      release_groups: format_release_groups_summary(artist_data["release-groups"]),
      recordings: format_recordings_summary(artist_data["recordings"]),
      external_links: format_external_links(artist_data["id"], "artist")
    }
  end

  defp format_detailed_recording_data(recording_data) do
    %{
      source: "musicbrainz",
      type: "recording",
      musicbrainz_id: recording_data["id"],
      title: recording_data["title"],
      length: recording_data["length"],
      disambiguation: recording_data["disambiguation"],
      artist_credit: format_artist_credit(recording_data["artist-credit"]),
      releases: format_recording_releases(recording_data["releases"]),
      isrcs: recording_data["isrcs"] || [],
      external_links: format_external_links(recording_data["id"], "recording")
    }
  end

  defp format_detailed_release_data(release_data) do
    %{
      source: "musicbrainz",
      type: "release",
      musicbrainz_id: release_data["id"],
      title: release_data["title"],
      date: release_data["date"],
      country: release_data["country"],
      status: release_data["status"],
      barcode: release_data["barcode"],
      disambiguation: release_data["disambiguation"],
      artist_credit: format_artist_credit(release_data["artist-credit"]),
      release_group: format_release_group_ref(release_data["release-group"]),
      label_info: format_label_info(release_data["label-info"]),
      media: format_media(release_data["media"]),
      external_links: format_external_links(release_data["id"], "release")
    }
  end

  defp format_detailed_release_group_data(release_group_data) do
    %{
      source: "musicbrainz",
      type: "release_group",
      musicbrainz_id: release_group_data["id"],
      title: release_group_data["title"],
      first_release_date: release_group_data["first-release-date"],
      primary_type: release_group_data["primary-type"],
      secondary_types: release_group_data["secondary-types"] || [],
      disambiguation: release_group_data["disambiguation"],
      artist_credit: format_artist_credit(release_group_data["artist-credit"]),
      releases: format_releases_summary(release_group_data["releases"]),
      external_links: format_external_links(release_group_data["id"], "release-group")
    }
  end

  defp format_area(nil), do: nil
  defp format_area(area) do
    %{
      id: area["id"],
      name: area["name"],
      sort_name: area["sort-name"]
    }
  end

  defp format_life_span(nil), do: nil
  defp format_life_span(life_span) do
    %{
      begin: life_span["begin"],
      end: life_span["end"],
      ended: life_span["ended"]
    }
  end

  defp format_releases_summary(nil), do: []
  defp format_releases_summary(releases) when is_list(releases) do
    releases
    |> Enum.take(10) # Limit to 10 releases
    |> Enum.map(fn release ->
      %{
        id: release["id"],
        title: release["title"],
        date: release["date"],
        country: release["country"]
      }
    end)
  end

  defp format_release_groups_summary(nil), do: []
  defp format_release_groups_summary(release_groups) when is_list(release_groups) do
    release_groups
    |> Enum.take(10) # Limit to 10 release groups
    |> Enum.map(fn rg ->
      %{
        id: rg["id"],
        title: rg["title"],
        first_release_date: rg["first-release-date"],
        primary_type: rg["primary-type"]
      }
    end)
  end

  defp format_recordings_summary(nil), do: []
  defp format_recordings_summary(recordings) when is_list(recordings) do
    recordings
    |> Enum.take(10) # Limit to 10 recordings
    |> Enum.map(fn recording ->
      %{
        id: recording["id"],
        title: recording["title"],
        length: recording["length"]
      }
    end)
  end

  defp format_label_info(nil), do: []
  defp format_label_info(label_info) when is_list(label_info) do
    Enum.map(label_info, fn info ->
      %{
        catalog_number: info["catalog-number"],
        label: %{
          id: info["label"]["id"],
          name: info["label"]["name"]
        }
      }
    end)
  end

  defp format_media(nil), do: []
  defp format_media(media) when is_list(media) do
    Enum.map(media, fn medium ->
      %{
        position: medium["position"],
        title: medium["title"],
        format: medium["format"],
        track_count: medium["track-count"],
        tracks: format_tracks(medium["tracks"])
      }
    end)
  end

  defp format_tracks(nil), do: []
  defp format_tracks(tracks) when is_list(tracks) do
    tracks
    |> Enum.take(20) # Limit to 20 tracks per medium
    |> Enum.map(fn track ->
      %{
        id: track["id"],
        position: track["position"],
        title: track["title"],
        length: track["length"],
        recording: %{
          id: track["recording"]["id"],
          title: track["recording"]["title"]
        }
      }
    end)
  end

  defp format_external_links(musicbrainz_id, entity_type) do
    %{
      musicbrainz_url: "https://musicbrainz.org/#{entity_type}/#{musicbrainz_id}"
    }
  end
end