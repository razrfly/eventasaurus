defmodule EventasaurusDiscovery.Movies.OmdbService do
  @moduledoc """
  Service for interacting with the OMDb (Open Movie Database) API.

  OMDb provides movie data including IMDB IDs, which can be used to bridge
  to TMDB when direct TMDB search fails. This is particularly useful for:

  - Polish titles that map better to IMDB
  - Older/classic films with better OMDb coverage
  - Cross-referencing movie identities via IMDB ID

  ## Configuration

  Requires `OMDB_API_KEY` environment variable to be set.

  ## Usage

      # Search for a movie by title
      OmdbService.search("Gladiator", year: 2000)
      #=> {:ok, [%{title: "Gladiator", imdb_id: "tt0172495", ...}]}

      # Get detailed movie info by IMDB ID
      OmdbService.get_by_imdb_id("tt0172495")
      #=> {:ok, %{title: "Gladiator", year: 2000, imdb_id: "tt0172495", ...}}

      # Search with Polish title
      OmdbService.search("Księżniczka Mononoke")
      #=> {:ok, [%{title: "Princess Mononoke", imdb_id: "tt0119698", ...}]}
  """

  require Logger

  @base_url "https://www.omdbapi.com"
  @timeout 15_000
  @recv_timeout 15_000

  @doc """
  Search for movies by title.

  ## Options

  - `:year` - Filter by release year (optional)
  - `:type` - Filter by type: "movie", "series", "episode" (default: "movie")
  - `:page` - Page number for paginated results (default: 1)

  ## Examples

      iex> OmdbService.search("Gladiator")
      {:ok, [%{title: "Gladiator", year: "2000", imdb_id: "tt0172495", ...}]}

      iex> OmdbService.search("Gladiator", year: 2000)
      {:ok, [%{title: "Gladiator", year: "2000", imdb_id: "tt0172495", ...}]}
  """
  def search(title, opts \\ []) do
    with {:ok, api_key} <- get_api_key() do
      year = Keyword.get(opts, :year)
      type = Keyword.get(opts, :type, "movie")
      page = Keyword.get(opts, :page, 1)

      params = %{
        apikey: api_key,
        s: title,
        type: type,
        page: page
      }

      # Add year if provided
      params = if year, do: Map.put(params, :y, year), else: params

      url = build_url(params)

      case make_request(url) do
        {:ok, %{"Search" => results, "totalResults" => total}} ->
          formatted = Enum.map(results, &format_search_result/1)
          {:ok, %{results: formatted, total_results: String.to_integer(total)}}

        {:ok, %{"Response" => "False", "Error" => error}} ->
          handle_omdb_error(error)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get detailed movie information by IMDB ID.

  ## Examples

      iex> OmdbService.get_by_imdb_id("tt0172495")
      {:ok, %{
        title: "Gladiator",
        year: 2000,
        imdb_id: "tt0172495",
        runtime: 155,
        director: "Ridley Scott",
        ...
      }}
  """
  def get_by_imdb_id(imdb_id) when is_binary(imdb_id) do
    with {:ok, api_key} <- get_api_key() do
      params = %{
        apikey: api_key,
        i: imdb_id,
        plot: "full"
      }

      url = build_url(params)

      case make_request(url) do
        {:ok, %{"Response" => "True"} = data} ->
          {:ok, format_detailed_result(data)}

        {:ok, %{"Response" => "False", "Error" => error}} ->
          handle_omdb_error(error)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get detailed movie information by title and optionally year.

  This is useful when you have a title but not an IMDB ID.

  ## Examples

      iex> OmdbService.get_by_title("Gladiator", year: 2000)
      {:ok, %{title: "Gladiator", year: 2000, imdb_id: "tt0172495", ...}}
  """
  def get_by_title(title, opts \\ []) do
    with {:ok, api_key} <- get_api_key() do
      year = Keyword.get(opts, :year)
      type = Keyword.get(opts, :type, "movie")

      params = %{
        apikey: api_key,
        t: title,
        type: type,
        plot: "full"
      }

      # Add year if provided
      params = if year, do: Map.put(params, :y, year), else: params

      url = build_url(params)

      case make_request(url) do
        {:ok, %{"Response" => "True"} = data} ->
          {:ok, format_detailed_result(data)}

        {:ok, %{"Response" => "False", "Error" => error}} ->
          handle_omdb_error(error)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private functions

  defp get_api_key do
    case System.get_env("OMDB_API_KEY") do
      nil -> {:error, :no_api_key}
      "" -> {:error, :no_api_key}
      key -> {:ok, key}
    end
  end

  defp build_url(params) do
    query = URI.encode_query(params)
    "#{@base_url}/?#{query}"
  end

  defp make_request(url) do
    headers = [{"Accept", "application/json"}]

    Logger.debug("OMDb request URL: #{String.replace(url, ~r/apikey=[^&]+/, "apikey=***")}")

    case HTTPoison.get(url, headers, timeout: @timeout, recv_timeout: @recv_timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :decode_error}
        end

      {:ok, %HTTPoison.Response{status_code: 401}} ->
        {:error, :invalid_api_key}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("OMDb API error: HTTP #{status}")
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("OMDb HTTP error: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  defp format_search_result(result) do
    %{
      title: result["Title"],
      year: result["Year"],
      imdb_id: result["imdbID"],
      type: result["Type"],
      poster_url: format_poster_url(result["Poster"])
    }
  end

  defp format_detailed_result(data) do
    %{
      title: data["Title"],
      year: parse_year(data["Year"]),
      imdb_id: data["imdbID"],
      type: data["Type"],
      rated: data["Rated"],
      released: data["Released"],
      runtime: parse_runtime(data["Runtime"]),
      genres: parse_list(data["Genre"]),
      director: data["Director"],
      writers: parse_list(data["Writer"]),
      actors: parse_list(data["Actors"]),
      plot: data["Plot"],
      language: parse_list(data["Language"]),
      country: parse_list(data["Country"]),
      awards: data["Awards"],
      poster_url: format_poster_url(data["Poster"]),
      ratings: format_ratings(data["Ratings"]),
      metascore: parse_int(data["Metascore"]),
      imdb_rating: parse_float(data["imdbRating"]),
      imdb_votes: parse_votes(data["imdbVotes"]),
      dvd: data["DVD"],
      box_office: data["BoxOffice"],
      production: data["Production"],
      website: data["Website"]
    }
  end

  defp format_poster_url("N/A"), do: nil
  defp format_poster_url(nil), do: nil
  defp format_poster_url(url), do: url

  defp parse_year(nil), do: nil
  defp parse_year("N/A"), do: nil

  defp parse_year(year) when is_binary(year) do
    # Handle range years like "2020-2023" or "2020–2023" (en-dash) or single years "2020"
    case String.split(year, ~r/[–-]/) do
      [single] -> parse_int(single)
      [start | _] -> parse_int(start)
    end
  end

  defp parse_runtime(nil), do: nil
  defp parse_runtime("N/A"), do: nil

  defp parse_runtime(runtime) when is_binary(runtime) do
    case Regex.run(~r/(\d+)/, runtime) do
      [_, minutes] -> String.to_integer(minutes)
      _ -> nil
    end
  end

  defp parse_list(nil), do: []
  defp parse_list("N/A"), do: []

  defp parse_list(str) when is_binary(str) do
    str
    |> String.split(", ")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_int(nil), do: nil
  defp parse_int("N/A"), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float("N/A"), do: nil

  defp parse_float(str) when is_binary(str) do
    case Float.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_votes(nil), do: nil
  defp parse_votes("N/A"), do: nil

  defp parse_votes(votes) when is_binary(votes) do
    votes
    |> String.replace(",", "")
    |> parse_int()
  end

  defp format_ratings(nil), do: []

  defp format_ratings(ratings) when is_list(ratings) do
    Enum.map(ratings, fn rating ->
      %{
        source: rating["Source"],
        value: rating["Value"]
      }
    end)
  end

  defp handle_omdb_error("Movie not found!"), do: {:error, :not_found}
  defp handle_omdb_error("Incorrect IMDb ID."), do: {:error, :invalid_imdb_id}
  defp handle_omdb_error("Invalid API key!"), do: {:error, :invalid_api_key}
  defp handle_omdb_error("Request limit reached!"), do: {:error, :rate_limited}
  defp handle_omdb_error(error), do: {:error, {:omdb_error, error}}
end
