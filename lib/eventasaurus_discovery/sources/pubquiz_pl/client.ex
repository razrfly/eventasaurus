defmodule EventasaurusDiscovery.Sources.Pubquiz.Client do
  @moduledoc """
  HTTP client for PubQuiz.pl website.

  Handles all HTTP requests to pubquiz.pl with proper error handling
  and rate limiting. Retries are handled at the Oban job level
  (max_attempts: 3 in each job module).
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Pubquiz.Config

  @doc """
  Fetches the main index page containing city list.
  """
  def fetch_index do
    fetch_page(Config.base_url())
  end

  @doc """
  Fetches a specific page by URL.
  """
  def fetch_page(url) do
    Logger.debug("Fetching PubQuiz page: #{url}")

    case HTTPoison.get(url, Config.headers(),
           follow_redirect: true,
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        Logger.warning("PubQuiz page not found: #{url}")
        {:error, :not_found}

      {:ok, %{status_code: status}} ->
        Logger.error("PubQuiz request failed. URL: #{url}, Status: #{status}")
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("PubQuiz HTTP error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches city page containing venue listings.
  """
  def fetch_city_page(city_url) do
    fetch_page(city_url)
  end

  @doc """
  Fetches venue detail page.
  """
  def fetch_venue_page(venue_url) do
    fetch_page(venue_url)
  end
end
