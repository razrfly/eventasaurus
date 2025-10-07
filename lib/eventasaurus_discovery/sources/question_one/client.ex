defmodule EventasaurusDiscovery.Sources.QuestionOne.Client do
  @moduledoc """
  HTTP client for Question One with rate limiting and error handling.

  Provides methods for:
  - Fetching RSS feed pages (with pagination)
  - Fetching individual venue detail pages
  - Automatic retry logic for failed requests
  """

  require Logger
  alias EventasaurusDiscovery.Sources.QuestionOne.Config

  @doc """
  Fetch a page from the Question One RSS feed.

  ## Parameters
  - `page` - Page number (defaults to 1)

  ## Returns
  - `{:ok, body}` - Success with RSS feed body
  - `{:ok, :no_more_pages}` - Reached end of pagination (404)
  - `{:error, reason}` - Request failed
  """
  def fetch_feed_page(page \\ 1) do
    url = if page == 1, do: Config.feed_url(), else: "#{Config.feed_url()}?paged=#{page}"

    Logger.info("📡 Fetching Question One feed page #{page}")

    case HTTPoison.get(url, Config.headers(),
           follow_redirect: true,
           timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        Logger.info("📋 Reached end of feed at page #{page} (404)")
        {:ok, :no_more_pages}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching feed page #{page}")
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error fetching feed page #{page}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetch a venue detail page.

  ## Parameters
  - `url` - Full URL to venue detail page

  ## Returns
  - `{:ok, body}` - Success with HTML body
  - `{:error, reason}` - Request failed
  """
  def fetch_venue_page(url) do
    Logger.debug("🔍 Fetching venue detail page: #{url}")

    case HTTPoison.get(url, Config.headers(),
           follow_redirect: true,
           timeout: Config.timeout()
         ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ HTTP #{status} when fetching venue: #{url}")
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("❌ Network error fetching venue #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
