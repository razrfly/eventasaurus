defmodule EventasaurusWeb.Services.SpotifyService do
  @moduledoc """
  Service for interacting with the Spotify Web API.
  Supports track search and detailed data fetching with caching and authentication.
  """

  use GenServer
  require Logger

  @base_url "https://api.spotify.com/v1"
  @auth_url "https://accounts.spotify.com/api/token"
  @cache_table :spotify_cache
  # Cache for 1 hour
  @cache_ttl :timer.hours(1)
  @rate_limit_table :spotify_rate_limit
  # 1 second window
  @rate_limit_window :timer.seconds(1)
  # Spotify allows 100 requests per second
  @rate_limit_max_requests 100

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{access_token: nil, expires_at: nil}, name: __MODULE__)
  end

  @doc """
  Search for tracks on Spotify.
  Returns a list of track maps with basic information.
  """
  def search_tracks(query, limit \\ 20) when is_binary(query) and limit > 0 do
    GenServer.call(__MODULE__, {:search_tracks, query, limit}, 30_000)
  end

  @doc """
  Get detailed track information including audio features.
  """
  def get_track_details(track_id) when is_binary(track_id) do
    GenServer.call(__MODULE__, {:get_track_details, track_id}, 30_000)
  end

  @doc """
  Get cached track details or fetch from API if not cached.
  This is the recommended way to get track details for performance.
  """
  def get_cached_track_details(track_id) when is_binary(track_id) do
    GenServer.call(__MODULE__, {:get_cached_track_details, track_id}, 30_000)
  end

  @doc """
  Get multiple tracks at once (more efficient than individual calls).
  """
  def get_tracks(track_ids) when is_list(track_ids) do
    GenServer.call(__MODULE__, {:get_tracks, track_ids}, 30_000)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(state) do
    # Initialize ETS tables for caching and rate limiting
    :ets.new(@cache_table, [:named_table, :public, :set])
    :ets.new(@rate_limit_table, [:named_table, :public, :set])

    Logger.info("SpotifyService started")
    {:ok, state}
  end

  @impl true
  def handle_call({:search_tracks, query, limit}, _from, state) do
    case ensure_valid_token(state) do
      {:ok, new_state} ->
        result = search_tracks_impl(query, limit, new_state.access_token)
        {:reply, result, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_track_details, track_id}, _from, state) do
    case ensure_valid_token(state) do
      {:ok, new_state} ->
        result = get_track_details_impl(track_id, new_state.access_token)
        {:reply, result, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_cached_track_details, track_id}, _from, state) do
    # Check cache first
    case get_cached_data(track_id) do
      {:hit, cached_data} ->
        {:reply, {:ok, cached_data}, state}

      :miss ->
        # Not in cache, fetch from API
        case ensure_valid_token(state) do
          {:ok, new_state} ->
            case get_track_details_impl(track_id, new_state.access_token) do
              {:ok, track_data} ->
                # Cache the successful result
                cache_data(track_id, track_data)
                {:reply, {:ok, track_data}, new_state}

              {:error, _} = error ->
                {:reply, error, new_state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_tracks, track_ids}, _from, state) do
    case ensure_valid_token(state) do
      {:ok, new_state} ->
        result = get_tracks_impl(track_ids, new_state.access_token)
        {:reply, result, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ============================================================================
  # Private Implementation Functions
  # ============================================================================

  defp ensure_valid_token(%{access_token: nil} = state) do
    get_access_token()
    |> case do
      {:ok, token, expires_at} ->
        {:ok, %{state | access_token: token, expires_at: expires_at}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_valid_token(%{expires_at: expires_at} = state) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
      {:ok, state}
    else
      # Token expired, get new one
      get_access_token()
      |> case do
        {:ok, token, new_expires_at} ->
          {:ok, %{state | access_token: token, expires_at: new_expires_at}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp get_access_token do
    client_id = System.get_env("SPOTIFY_CLIENT_ID")
    client_secret = System.get_env("SPOTIFY_CLIENT_SECRET")

    if is_nil(client_id) or is_nil(client_secret) do
      {:error, "Spotify credentials not configured"}
    else
      credentials = Base.encode64("#{client_id}:#{client_secret}")

      headers = [
        {"Authorization", "Basic #{credentials}"},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

      body = "grant_type=client_credentials"

      case HTTPoison.post(@auth_url, body, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"access_token" => token, "expires_in" => expires_in}} ->
              expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)
              Logger.debug("Spotify access token obtained, expires at #{expires_at}")
              {:ok, token, expires_at}

            {:error, _} ->
              {:error, "Failed to parse Spotify auth response"}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          Logger.error("Spotify auth failed: #{status} - #{body}")
          {:error, "Spotify authentication failed"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Spotify auth request failed: #{inspect(reason)}")
          {:error, "Network error during Spotify authentication"}
      end
    end
  end

  defp search_tracks_impl(query, limit, access_token) do
    with :ok <- check_rate_limit() do
      url =
        "#{@base_url}/search?" <>
          URI.encode_query(%{
            "q" => query,
            "type" => "track",
            "limit" => limit
          })

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Accept", "application/json"}
      ]

      case HTTPoison.get(url, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"tracks" => %{"items" => tracks}}} ->
              formatted_tracks = Enum.map(tracks, &format_search_result/1)
              {:ok, formatted_tracks}

            {:error, _} ->
              {:error, "Failed to parse Spotify search response"}
          end

        {:ok, %HTTPoison.Response{status_code: 401}} ->
          {:error, "Spotify authentication failed"}

        {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
          Logger.error("Spotify search failed: #{status} - #{body}")
          {:error, "Spotify search failed"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Spotify search request failed: #{inspect(reason)}")
          {:error, "Network error during Spotify search"}
      end
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}
    end
  end

  defp get_track_details_impl(track_id, access_token) do
    with :ok <- check_rate_limit() do
      # Get basic track info
      track_url = "#{@base_url}/tracks/#{track_id}"

      # Get audio features
      features_url = "#{@base_url}/audio-features/#{track_id}"

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Accept", "application/json"}
      ]

      # Fetch both in parallel for better performance
      track_task = Task.async(fn -> HTTPoison.get(track_url, headers) end)
      features_task = Task.async(fn -> HTTPoison.get(features_url, headers) end)

      with {:ok, %HTTPoison.Response{status_code: 200, body: track_body}} <-
             Task.await(track_task),
           {:ok, %HTTPoison.Response{status_code: 200, body: features_body}} <-
             Task.await(features_task),
           {:ok, track_data} <- Jason.decode(track_body),
           {:ok, features_data} <- Jason.decode(features_body) do
        detailed_track = format_detailed_result(track_data, features_data)
        {:ok, detailed_track}
      else
        {:ok, %HTTPoison.Response{status_code: 401}} ->
          {:error, "Spotify authentication failed"}

        {:ok, %HTTPoison.Response{status_code: 404}} ->
          {:error, "Track not found"}

        {:ok, %HTTPoison.Response{status_code: status}} ->
          {:error, "Spotify API error: #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "Network error: #{inspect(reason)}"}

        {:error, _} ->
          {:error, "Failed to parse Spotify response"}
      end
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}
    end
  end

  defp get_tracks_impl(track_ids, access_token) when length(track_ids) <= 50 do
    with :ok <- check_rate_limit() do
      ids_param = Enum.join(track_ids, ",")
      url = "#{@base_url}/tracks?ids=#{ids_param}"

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Accept", "application/json"}
      ]

      case HTTPoison.get(url, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"tracks" => tracks}} ->
              formatted_tracks = Enum.map(tracks, &format_search_result/1)
              {:ok, formatted_tracks}

            {:error, _} ->
              {:error, "Failed to parse Spotify response"}
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          {:error, "Spotify API error: #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}
    end
  end

  defp get_tracks_impl(track_ids, access_token) when length(track_ids) > 50 do
    # Split into chunks of 50 (Spotify's limit)
    track_ids
    |> Enum.chunk_every(50)
    |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
      case get_tracks_impl(chunk, access_token) do
        {:ok, tracks} -> {:cont, {:ok, acc ++ tracks}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp format_search_result(track) do
    artists = track["artists"] || []
    artist_names = Enum.map(artists, & &1["name"])
    primary_artist = List.first(artist_names) || "Unknown Artist"

    album = track["album"] || %{}
    images = album["images"] || []

    # Get the medium-sized image (usually 300x300)
    image_url =
      case images do
        [_large, medium, _small] -> medium["url"]
        [_large, small] -> small["url"]
        [single] -> single["url"]
        [] -> nil
      end

    %{
      type: :track,
      id: track["id"],
      title: track["name"],
      artist: primary_artist,
      artists: artist_names,
      album: album["name"],
      popularity: track["popularity"],
      preview_url: track["preview_url"],
      duration_ms: track["duration_ms"],
      duration_formatted: format_duration(track["duration_ms"]),
      explicit: track["explicit"],
      image_url: image_url,
      external_url: get_in(track, ["external_urls", "spotify"])
    }
  end

  defp format_detailed_result(track_data, features_data) do
    basic = format_search_result(track_data)
    album = track_data["album"] || %{}

    Map.merge(basic, %{
      album_release_date: album["release_date"],
      album_type: album["album_type"],
      images: album["images"] || [],
      audio_features: %{
        danceability: features_data["danceability"],
        energy: features_data["energy"],
        key: features_data["key"],
        loudness: features_data["loudness"],
        mode: features_data["mode"],
        speechiness: features_data["speechiness"],
        acousticness: features_data["acousticness"],
        instrumentalness: features_data["instrumentalness"],
        liveness: features_data["liveness"],
        valence: features_data["valence"],
        tempo: features_data["tempo"],
        time_signature: features_data["time_signature"]
      },
      available_markets: track_data["available_markets"] || [],
      disc_number: track_data["disc_number"],
      track_number: track_data["track_number"]
    })
  end

  defp check_rate_limit do
    now = :erlang.system_time(:millisecond)
    window_start = now - @rate_limit_window

    # Clean old entries
    # Clean up old rate limit entries
    :ets.select_delete(@rate_limit_table, [{{:"$1", :"$2"}, [{:<, :"$2", window_start}], [true]}])

    # Count current requests in window
    current_requests = :ets.info(@rate_limit_table, :size)

    if current_requests >= @rate_limit_max_requests do
      {:error, :rate_limited}
    else
      # Add current request
      :ets.insert(@rate_limit_table, {{:request, now}})
      :ok
    end
  end

  defp get_cached_data(key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, data, expires_at}] ->
        if :erlang.system_time(:millisecond) < expires_at do
          {:hit, data}
        else
          :ets.delete(@cache_table, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp cache_data(key, data) do
    expires_at = :erlang.system_time(:millisecond) + @cache_ttl
    :ets.insert(@cache_table, {key, data, expires_at})
    :ok
  end

  # Format duration from milliseconds to MM:SS format
  defp format_duration(nil), do: nil

  defp format_duration(milliseconds) when is_integer(milliseconds) do
    seconds = div(milliseconds, 1000)
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    "#{minutes}:#{String.pad_leading(Integer.to_string(remaining_seconds), 2, "0")}"
  end

  defp format_duration(_), do: nil
end
