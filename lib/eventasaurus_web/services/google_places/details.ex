defmodule EventasaurusWeb.Services.GooglePlaces.Details do
  @moduledoc """
  Handles Google Places Details API for fetching comprehensive place information.
  Includes ratings, reviews, photos, and other metadata.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Client
  require Logger

  @base_url "https://maps.googleapis.com/maps/api/place/details/json"
  # 1 hour in ms
  @details_cache_ttl 3_600_000

  @doc """
  Fetches detailed information about a specific place.
  """
  def fetch(place_id, opts \\ []) do
    # Include options in cache key to avoid collisions
    photos? = Keyword.get(opts, :include_photos, true)
    reviews? = Keyword.get(opts, :include_reviews, true)
    cache_key = "place_details:#{place_id}:p=#{photos?}:r=#{reviews?}"

    Client.get_cached_or_fetch(cache_key, @details_cache_ttl, fn ->
      fetch_from_api(place_id, opts)
    end)
  end

  @doc """
  Fetches place details directly from the API without caching.
  """
  def fetch_from_api(place_id, opts \\ []) do
    api_key = Client.get_api_key()

    if api_key do
      url = build_url(place_id, api_key, opts)

      case Client.get_json(url) do
        {:ok, %{"result" => result, "status" => "OK"}} ->
          {:ok, result}

        {:ok, %{"status" => "NOT_FOUND"}} ->
          {:error, :not_found}

        {:ok, %{"status" => status, "error_message" => message}} ->
          Logger.error("Google Places Details API error: #{status} - #{message}")
          {:error, "API error: #{status}"}

        {:ok, %{"status" => status}} ->
          Logger.error("Google Places Details API returned status: #{status}")
          {:error, "API returned status: #{status}"}

        {:error, reason} ->
          Logger.error("Google Places Details fetch failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, "No API key configured"}
    end
  end

  @doc """
  Builds the list of fields to request based on options.
  """
  def get_fields_for_request(opts) do
    base_fields = [
      "name",
      "formatted_address",
      "rating",
      "user_ratings_total",
      "price_level",
      "types",
      "business_status",
      "opening_hours",
      "formatted_phone_number",
      "website",
      "geometry",
      "place_id",
      "vicinity"
    ]

    additional_fields =
      if Keyword.get(opts, :include_photos, true), do: ["photos"], else: []

    review_fields =
      if Keyword.get(opts, :include_reviews, true), do: ["reviews"], else: []

    (base_fields ++ additional_fields ++ review_fields)
    |> Enum.join(",")
  end

  defp build_url(place_id, api_key, opts) do
    fields = get_fields_for_request(opts)

    params = %{
      place_id: place_id,
      fields: fields,
      key: api_key
    }

    "#{@base_url}?#{URI.encode_query(params)}"
  end
end
