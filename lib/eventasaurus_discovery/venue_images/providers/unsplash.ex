defmodule EventasaurusDiscovery.VenueImages.Providers.Unsplash do
  @moduledoc """
  Unsplash API fallback image provider.

  **Free Tier**: 50 requests/hour
  **Rate Limit**: 50 requests/hour (free)
  **Quality**: 7/10 (stock photos, not venue-specific)
  **Coverage**: Global stock photography

  ## API Documentation
  https://unsplash.com/documentation

  ## Configuration

  Requires `UNSPLASH_ACCESS_KEY` environment variable.

  Sign up at: https://unsplash.com/developers

  ## Important Notes

  - **Fallback provider** with lowest priority (99)
  - Returns stock photos based on venue name/location keywords
  - NOT venue-specific images (unlike Google Places, Foursquare)
  - Use only when other providers have no images
  - Must include attribution per Unsplash API terms

  ## Capabilities

  - **Images**: Search API for keyword-based stock photos
  - **Geocoding**: Not supported
  - **Reviews**: Not supported
  - **Hours**: Not supported

  ## Response Format

  Returns standardized image results with attribution.
  """

  @behaviour EventasaurusDiscovery.Geocoding.MultiProvider

  require Logger

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def name, do: "unsplash"

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def capabilities do
    %{
      "geocoding" => false,
      "images" => true,
      "reviews" => false,
      "hours" => false
    }
  end

  # Images Implementation

  @impl EventasaurusDiscovery.Geocoding.MultiProvider
  def get_images(search_query) when is_binary(search_query) do
    access_key = get_access_key()

    if is_nil(access_key) do
      Logger.error("❌ UNSPLASH_ACCESS_KEY not configured")
      {:error, :api_key_missing}
    else
      Logger.debug("📸 Unsplash search request: #{search_query}")
      search_photos(search_query, access_key)
    end
  end

  def get_images(_), do: {:error, :invalid_search_query}

  defp search_photos(query, access_key) do
    url = "https://api.unsplash.com/search/photos"

    headers = [
      {"Authorization", "Client-ID #{access_key}"},
      {"Accept", "application/json"}
    ]

    params = [
      query: query,
      per_page: 5,
      orientation: "landscape"
    ]

    case HTTPoison.get(url, headers, params: params, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_photos_response(body)

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        Logger.error("❌ Unsplash authentication failed (invalid access key)")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        Logger.error("❌ Unsplash forbidden (check API limits or permissions)")
        {:error, :api_error}

      {:ok, %HTTPoison.Response{status_code: 429}} ->
        Logger.warning("⚠️ Unsplash rate limited")
        {:error, :rate_limited}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("❌ Unsplash HTTP error: #{status}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        Logger.warning("⏱️ Unsplash request timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("❌ Unsplash request failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp parse_photos_response(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => results}} when is_list(results) and length(results) > 0 ->
        images =
          Enum.map(results, fn photo ->
            # Extract URLs (prefer regular, fallback to small)
            urls = Map.get(photo, "urls", %{})
            url = Map.get(urls, "regular") || Map.get(urls, "small")

            # Extract dimensions
            width = Map.get(photo, "width")
            height = Map.get(photo, "height")

            # Extract photographer attribution
            user = Map.get(photo, "user", %{})
            photographer_name = Map.get(user, "name", "Unknown")
            photographer_url = get_in(user, ["links", "html"])

            # Construct attribution string per Unsplash API guidelines
            attribution = "Photo by #{photographer_name} on Unsplash"
            photo_link = get_in(photo, ["links", "html"])

            %{
              url: url,
              width: width,
              height: height,
              attribution: attribution,
              source_url: photo_link || photographer_url
            }
          end)
          |> Enum.reject(fn img -> is_nil(img.url) end)

        if Enum.empty?(images) do
          {:error, :no_images}
        else
          {:ok, images}
        end

      {:ok, %{"results" => []}} ->
        Logger.debug("📸 Unsplash: no results found")
        {:error, :no_images}

      {:ok, other} ->
        Logger.error("❌ Unsplash: unexpected response format: #{inspect(other)}")
        {:error, :invalid_response}

      {:error, reason} ->
        Logger.error("❌ Unsplash: JSON decode error: #{inspect(reason)}")
        {:error, :invalid_response}
    end
  end

  defp get_access_key do
    System.get_env("UNSPLASH_ACCESS_KEY")
  end
end
