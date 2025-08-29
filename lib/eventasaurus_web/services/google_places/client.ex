defmodule EventasaurusWeb.Services.GooglePlaces.Client do
  @moduledoc """
  HTTP client for Google Places API with rate limiting and caching support.
  Handles all API communication and rate limiting logic.
  """

  require Logger

  @cache_name :google_places_cache
  @rate_limit_key "google_places_rate_limit"
  @rate_limit_window 1000  # 1 second in ms
  @rate_limit_max_requests 10  # Max requests per second
  @timeout 10_000
  @recv_timeout 10_000

  @doc """
  Makes an HTTP GET request to the Google Places API with rate limiting.
  """
  def get(url) do
    with :ok <- check_rate_limit() do
      HTTPoison.get(url, [], timeout: @timeout, recv_timeout: @recv_timeout)
    end
  end

  @doc """
  Makes an HTTP GET request and decodes the JSON response.
  """
  def get_json(url) do
    with :ok <- check_rate_limit(),
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get(url, [], timeout: @timeout, recv_timeout: @recv_timeout),
         {:ok, json} <- Jason.decode(body) do
      {:ok, json}
    else
      {:error, :rate_limited} = error ->
        Logger.warning("Google Places API rate limited")
        error
      
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        {:error, "HTTP #{status_code}"}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP error: #{inspect(reason)}"}
      
      {:error, %Jason.DecodeError{} = error} ->
        {:error, "JSON decode error: #{inspect(error)}"}
      
      error ->
        error
    end
  end

  @doc """
  Checks rate limiting before making API requests.
  """
  def check_rate_limit do
    # Use atomic increment to avoid race conditions
    case Cachex.incr(@cache_name, @rate_limit_key, 1, ttl: @rate_limit_window, initial: 1) do
      {:ok, count} when count <= @rate_limit_max_requests -> 
        :ok
      
      {:ok, _count} -> 
        {:error, :rate_limited}
      
      {:error, _} ->
        # Cache error, allow request but log warning
        Logger.warning("Rate limit cache error, allowing request")
        :ok
    end
  end

  @doc """
  Gets data from cache or fetches it using the provided function.
  """
  def get_cached_or_fetch(cache_key, ttl, fetch_fn) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Not in cache, fetch and cache
        case fetch_fn.() do
          {:ok, data} ->
            Cachex.put(@cache_name, cache_key, data, ttl: ttl)
            {:ok, data}
          error ->
            error
        end

      {:ok, cached_data} ->
        # Found in cache
        {:ok, cached_data}

      {:error, _cache_error} ->
        # Cache error, fetch directly
        fetch_fn.()
    end
  end

  @doc """
  Gets the configured Google Places API key.
  """
  def get_api_key do
    Application.get_env(:eventasaurus, :google_places_api_key) ||
    System.get_env("GOOGLE_MAPS_API_KEY")
  end

  @doc """
  Returns the cache name for external use.
  """
  def cache_name, do: @cache_name
end