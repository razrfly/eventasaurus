defmodule EventasaurusWeb.Services.TmdbService do
  @moduledoc """
  Service for interacting with The Movie Database (TMDb) API.
  Supports multi-search (movies, TV, people).
  """

  @behaviour EventasaurusWeb.Services.TmdbServiceBehaviour

  @base_url "https://api.themoviedb.org/3"

  def search_multi(query, page \\ 1) do
    # Handle nil or empty queries
    if is_nil(query) or String.trim(to_string(query)) == "" do
      {:ok, []}
    else
      api_key = System.get_env("TMDB_API_KEY")
      if is_nil(api_key) or api_key == "" do
        {:error, "TMDB_API_KEY is not set in environment"}
      else
        url = "#{@base_url}/search/multi?api_key=#{api_key}&query=#{URI.encode(query)}&page=#{page}"
        headers = [
          {"Accept", "application/json"}
        ]
        require Logger
        Logger.debug("TMDB search URL: #{url}")
        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
            Logger.debug("TMDB response: #{code}")
            case code do
              200 ->
                case Jason.decode(body) do
                  {:ok, %{"results" => results}} ->
                    {:ok, Enum.map(results, &format_result/1)}
                  {:error, _} ->
                    {:error, "Failed to decode TMDb response"}
                end
              _ ->
                {:error, "TMDb error: #{code} - #{body}"}
            end
          {:error, reason} ->
            Logger.error("TMDB HTTP error: #{inspect(reason)}")
            {:error, reason}
        end
      end
    end
  end

  defp format_result(%{"media_type" => "movie"} = item) do
    %{
      type: :movie,
      id: item["id"],
      title: item["title"],
      overview: item["overview"],
      poster_path: item["poster_path"],
      release_date: item["release_date"]
    }
  end
  defp format_result(%{"media_type" => "tv"} = item) do
    %{
      type: :tv,
      id: item["id"],
      name: item["name"],
      overview: item["overview"],
      poster_path: item["poster_path"],
      first_air_date: item["first_air_date"]
    }
  end
  defp format_result(%{"media_type" => "person"} = item) do
    %{
      type: :person,
      id: item["id"],
      name: item["name"],
      profile_path: item["profile_path"],
      known_for: item["known_for"]
    }
  end
  defp format_result(%{"media_type" => "collection"} = item) do
    %{
      type: :collection,
      id: item["id"],
      name: item["name"] || item["title"],
      overview: item["overview"],
      poster_path: item["poster_path"],
      backdrop_path: item["backdrop_path"]
    }
  end
  # Fallback for unknown media types - ensure we always have a type field
  defp format_result(item) do
    Map.put(item, :type, :unknown)
  end
end
