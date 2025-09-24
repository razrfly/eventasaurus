defmodule EventasaurusWeb.Services.GooglePlaces.Geocoding do
  @moduledoc """
  Handles Google Geocoding API for searching regions and countries.
  Used for administrative area searches at various levels.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Client
  require Logger

  @base_url "https://maps.googleapis.com/maps/api/geocode/json"

  @doc """
  Searches for regions or countries using the Geocoding API.
  """
  def search(query, options \\ %{}) do
    api_key = Client.get_api_key()

    if api_key do
      url = build_url(query, api_key, options)

      case Client.get_json(url) do
        {:ok, %{"results" => results, "status" => "OK"}} ->
          filtered_results = filter_by_type(results, options[:type])
          {:ok, filtered_results}

        {:ok, %{"results" => [], "status" => "ZERO_RESULTS"}} ->
          {:ok, []}

        {:ok, %{"status" => status, "error_message" => message}} ->
          Logger.error("Google Geocoding API error: #{status} - #{message}")
          {:error, "API error: #{status}"}

        {:ok, %{"status" => status}} ->
          Logger.error("Google Geocoding API returned status: #{status}")
          {:error, "API returned status: #{status}"}

        {:error, reason} ->
          Logger.error("Google Geocoding failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, "No API key configured"}
    end
  end

  defp build_url(query, api_key, options) do
    params =
      %{
        address: query,
        key: api_key
      }
      |> maybe_put(:region, Map.get(options, :region))
      |> maybe_put(:language, Map.get(options, :language))
      |> maybe_put(:components, Map.get(options, :components))

    "#{@base_url}?#{URI.encode_query(params)}"
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp filter_by_type(results, type) when type in ["region", "country"] do
    type_filters =
      case type do
        "region" -> ["administrative_area_level_1", "administrative_area_level_2"]
        "country" -> ["country"]
      end

    Enum.filter(results, fn result ->
      types = Map.get(result, "types", [])
      Enum.any?(type_filters, &(&1 in types))
    end)
  end

  defp filter_by_type(results, _), do: results
end
