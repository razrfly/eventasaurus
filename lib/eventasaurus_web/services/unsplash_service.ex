defmodule EventasaurusWeb.Services.UnsplashService do
  @moduledoc """
  Service for interacting with the Unsplash API.
  """

  @doc """
  Search for photos on Unsplash.
  Returns a list of photos that match the search query.
  """
  def search_photos(query, page \\ 1, per_page \\ 20) do
    case get("/search/photos", %{query: query, page: page, per_page: per_page}) do
      {:ok, %{"results" => results}} ->
        processed_results =
          results
          |> Enum.map(fn photo ->
            %{
              id: photo["id"],
              description: photo["description"] || photo["alt_description"] || "Unsplash photo",
              urls: %{
                raw: photo["urls"]["raw"],
                full: photo["urls"]["full"],
                regular: photo["urls"]["regular"],
                small: photo["urls"]["small"],
                thumb: photo["urls"]["thumb"]
              },
              user: %{
                name: photo["user"]["name"],
                username: photo["user"]["username"],
                profile_url: photo["user"]["links"]["html"]
              },
              download_location: photo["links"]["download_location"]
            }
          end)

        {:ok, processed_results}

      {:ok, response} ->
        {:error, "Unexpected response format: #{inspect(response)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Triggers a download event for the given photo ID.
  This is required by Unsplash API terms whenever a photo is downloaded or used.
  """
  def track_download(download_location) do
    case get(download_location, %{}) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  defp get(path, params) do
    url = build_url(path, params)

    headers = [
      {"Authorization", "Client-ID #{access_key()}"},
      {"Accept-Version", "v1"}
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, "Unsplash API error: #{code}, #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  defp build_url(path, params) do
    base_url = "https://api.unsplash.com"

    # Remove the leading slash if present
    path = if String.starts_with?(path, "/"), do: String.slice(path, 1..-1//1), else: path

    # Build the query string
    query_string =
      params
      |> Enum.map(fn {key, value} -> "#{key}=#{URI.encode_www_form(to_string(value))}" end)
      |> Enum.join("&")

    # Combine base URL, path and query string
    if query_string != "", do: "#{base_url}/#{path}?#{query_string}", else: "#{base_url}/#{path}"
  end

  defp access_key do
    System.get_env("UNSPLASH_ACCESS_KEY") || raise "UNSPLASH_ACCESS_KEY is not set in environment variables"
  end
end
