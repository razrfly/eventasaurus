defmodule EventasaurusWeb.Services.MovieConfig do
  @moduledoc """
  Centralized configuration management for TMDB and movie-related services.
  Provides unified access to API keys, URLs, timeouts, and other configuration.
  """

  require Logger

  @doc """
  Validates TMDB configuration at application startup.
  Raises an error if critical configuration is missing.
  """
  def validate_config! do
    case get_api_key() do
      {:ok, _} -> :ok
      {:error, reason} -> raise "TMDB Configuration Error: #{reason}"
    end
  end

  @doc """
  Gets the TMDB API key with validation.
  Returns {:ok, key} or {:error, reason}.
  """
  def get_api_key do
    case System.get_env("TMDB_API_KEY") do
      nil -> {:error, "TMDB_API_KEY environment variable is not set"}
      "" -> {:error, "TMDB_API_KEY environment variable is empty"}
      key -> {:ok, key}
    end
  end

  @doc """
  Gets the TMDB API key or raises if not available.
  Use this when you need the key and want to fail fast.
  """
  def get_api_key! do
    case get_api_key() do
      {:ok, key} -> key
      {:error, reason} -> raise "TMDB API Key Error: #{reason}"
    end
  end

  @doc """
  Gets the TMDB API base URL.
  """
  def get_api_base_url do
    "https://api.themoviedb.org/3"
  end

  @doc """
  Gets the TMDB image base URL.
  """
  def get_image_base_url do
    "https://image.tmdb.org/t/p"
  end

  @doc """
  Gets request timeout configuration for TMDB API calls.
  Returns a keyword list with timeout values in milliseconds.
  """
  def get_timeout_config do
    [
      # 30 seconds for connection timeout
      timeout: 30_000,
      # 30 seconds for response timeout
      recv_timeout: 30_000
    ]
  end

  @doc """
  Gets rate limiting configuration for TMDB API.
  Returns max requests per second (stays under TMDB's 50 req/s limit).
  """
  def get_rate_limit_config do
    %{
      # Below TMDB's 50 req/s limit
      max_requests_per_second: 40,
      window_seconds: 1
    }
  end

  @doc """
  Gets cache configuration for TMDB data.
  Returns TTL in milliseconds.
  """
  def get_cache_config do
    %{
      # 6 hours
      ttl_milliseconds: :timer.hours(6),
      table_name: :tmdb_cache
    }
  end

  @doc """
  Builds a full TMDB image URL from a path and size.
  """
  def build_image_url(path, size \\ "w500")
  def build_image_url(nil, _size), do: nil
  def build_image_url("", _size), do: nil

  def build_image_url(path, size) when is_binary(path) and is_binary(size) do
    # Validate that path starts with "/" and contains only safe characters
    if String.match?(path, ~r{^/[a-zA-Z0-9._-]+\.(jpg|jpeg|png|webp)$}i) do
      "#{get_image_base_url()}/#{size}#{path}"
    else
      Logger.warning("Invalid TMDB image path format: #{inspect(path)}")
      nil
    end
  end

  def build_image_url(_, _), do: nil

  @doc """
  Builds a full TMDB API URL from an endpoint path.
  """
  def build_api_url(endpoint_path) when is_binary(endpoint_path) do
    normalized_path =
      if String.starts_with?(endpoint_path, "/") do
        endpoint_path
      else
        "/#{endpoint_path}"
      end

    "#{get_api_base_url()}#{normalized_path}"
  end

  @doc """
  Gets HTTP headers for TMDB API requests.
  """
  def get_api_headers do
    [{"Accept", "application/json"}]
  end

  @doc """
  Logs configuration status (for debugging and startup verification).
  """
  def log_config_status do
    case get_api_key() do
      {:ok, key} ->
        masked_key = String.slice(key, 0, 8) <> "***"

        Logger.info(
          "TMDB Configuration: API key present (#{masked_key}), base URL: #{get_api_base_url()}"
        )

      {:error, reason} ->
        Logger.error("TMDB Configuration: #{reason}")
    end

    Logger.info(
      "TMDB Configuration: Rate limit #{get_rate_limit_config().max_requests_per_second} req/s, cache TTL #{div(get_cache_config().ttl_milliseconds, 60_000)} minutes"
    )

    :ok
  end
end
