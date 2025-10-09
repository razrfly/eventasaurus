defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Extractors.NonceExtractor do
  @moduledoc """
  Extracts WordPress nonce from the Geeks Who Drink venues page.

  The nonce (number used once) is required for authenticating requests
  to the WordPress AJAX API endpoint. It's embedded in the page HTML
  as a JavaScript variable: gwdNonce: "abc123..."

  ## Example
      iex> NonceExtractor.fetch_nonce()
      {:ok, "abc123def456..."}
  """

  require Logger
  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.{Config, Client}

  @doc """
  Fetches and extracts the nonce from the venues page.

  ## Returns
  - `{:ok, nonce}` - Successfully extracted nonce string
  - `{:error, reason}` - Failed to fetch page or extract nonce
  """
  def fetch_nonce do
    Logger.info("🔍 Fetching nonce from Geeks Who Drink venues page...")

    case Client.fetch_page(Config.venues_url()) do
      {:ok, %{body: body}} ->
        extract_nonce_from_html(body)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch venues page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Extracts nonce from HTML body using regex.

  The nonce appears in the page as: gwdNonce: "abc123..."

  ## Parameters
  - `html` - Raw HTML body from venues page

  ## Returns
  - `{:ok, nonce}` - Successfully extracted nonce
  - `{:error, :nonce_not_found}` - Nonce pattern not found in HTML
  """
  def extract_nonce_from_html(html) when is_binary(html) do
    case Regex.run(~r/gwdNonce["']?\s*:\s*["']([^"']+)["']/, html) do
      [_, nonce] ->
        Logger.info("✅ Successfully extracted nonce: #{String.slice(nonce, 0..10)}...")
        {:ok, nonce}

      nil ->
        Logger.error("❌ Could not find nonce in page content")
        Logger.debug("HTML length: #{String.length(html)} bytes")
        {:error, :nonce_not_found}
    end
  end

  def extract_nonce_from_html(_), do: {:error, :invalid_html}
end
