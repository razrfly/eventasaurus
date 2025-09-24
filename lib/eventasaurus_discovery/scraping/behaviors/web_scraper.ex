defmodule EventasaurusDiscovery.Scraping.Behaviors.WebScraper do
  @moduledoc """
  Behavior for implementing web scraping functionality.

  This behavior defines the contract for modules that perform
  HTTP requests and HTML parsing for event data extraction.
  """

  @type scrape_options :: %{
          timeout: integer(),
          follow_redirects: boolean(),
          max_retries: integer(),
          user_agent: String.t()
        }

  @type scrape_result :: %{
          status_code: integer(),
          body: String.t(),
          headers: list({String.t(), String.t()}),
          url: String.t()
        }

  @doc """
  Performs an HTTP GET request with the specified options.
  """
  @callback fetch(url :: String.t(), options :: scrape_options()) ::
              {:ok, scrape_result()} | {:error, term()}

  @doc """
  Performs an HTTP POST request with the specified body and options.
  """
  @callback post(url :: String.t(), body :: term(), options :: scrape_options()) ::
              {:ok, scrape_result()} | {:error, term()}

  @doc """
  Extracts structured data from HTML content.
  """
  @callback extract_data(html :: String.t(), selectors :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Extracts all links from HTML content matching specified patterns.
  """
  @callback extract_links(html :: String.t(), pattern :: Regex.t() | nil) ::
              {:ok, list(String.t())} | {:error, term()}

  @doc """
  Cleans and normalizes extracted text.
  """
  @callback normalize_text(text :: String.t()) :: String.t()

  @doc """
  Validates that a response indicates success.
  """
  @callback validate_response(response :: scrape_result()) ::
              :ok | {:error, String.t()}

  @optional_callbacks post: 3, extract_links: 2
end
