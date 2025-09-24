defmodule EventasaurusWeb.Services.TmdbService do
  @moduledoc """
  Service for interacting with The Movie Database (TMDb) API.
  Supports multi-search (movies, TV, people) and detailed data fetching with caching.
  """

  @behaviour EventasaurusWeb.Services.TmdbServiceBehaviour
  use GenServer
  require Logger

  @base_url "https://api.themoviedb.org/3"
  @cache_table :tmdb_cache
  # Cache for 6 hours
  @cache_ttl :timer.hours(6)
  @rate_limit_table :tmdb_rate_limit
  # 1 second window
  @rate_limit_window :timer.seconds(1)
  # Max 40 requests per second (TMDB limit is 50)
  @rate_limit_max_requests 40

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Get cached movie details or fetch from API if not cached.
  This is the recommended way to get movie details for performance.
  """
  @impl EventasaurusWeb.Services.TmdbServiceBehaviour
  def get_cached_movie_details(movie_id) do
    GenServer.call(__MODULE__, {:get_cached_movie_details, movie_id}, 30_000)
  end

  @doc """
  Get detailed movie information including cast, crew, and images.
  This bypasses the cache and always fetches fresh data.
  """
  @impl EventasaurusWeb.Services.TmdbServiceBehaviour
  def get_movie_details(movie_id) do
    with :ok <- check_rate_limit(),
         {:ok, api_key} <- get_api_key() do
      fetch_movie_details(movie_id, api_key)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get detailed TV show information including cast, crew, and images.
  """
  @impl EventasaurusWeb.Services.TmdbServiceBehaviour
  def get_tv_details(tv_id) do
    with :ok <- check_rate_limit(),
         {:ok, api_key} <- get_api_key() do
      fetch_tv_details(tv_id, api_key)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get popular movies from TMDB API with optional page parameter.
  Returns a list of movie maps with basic information.
  """
  @impl EventasaurusWeb.Services.TmdbServiceBehaviour
  def get_popular_movies(page \\ 1) do
    with :ok <- check_rate_limit(),
         {:ok, api_key} <- get_api_key() do
      fetch_popular_movies(page, api_key)
    else
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded, please try again later"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl EventasaurusWeb.Services.TmdbServiceBehaviour
  def search_multi(query, page \\ 1) do
    # Handle nil or empty queries
    if is_nil(query) or String.trim(to_string(query)) == "" do
      {:ok, []}
    else
      api_key = System.get_env("TMDB_API_KEY")

      if is_nil(api_key) or api_key == "" do
        {:error, "TMDB_API_KEY is not set in environment"}
      else
        url =
          "#{@base_url}/search/multi?api_key=#{api_key}&query=#{URI.encode(query)}&page=#{page}"

        headers = [
          {"Accept", "application/json"}
        ]

        require Logger

        Logger.debug(
          "TMDB search URL: #{@base_url}/search/multi?query=#{URI.encode(query)}&page=#{page}"
        )

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
            Logger.debug("TMDB response: #{code}")

            case code do
              200 ->
                case Jason.decode(body) do
                  {:ok, %{"results" => results}} ->
                    {:ok, Enum.map(results, &format_result/1)}

                  {:ok, _invalid_format} ->
                    {:error, "Invalid TMDb response format"}

                  {:error, decode_error} ->
                    Logger.error("Failed to decode TMDb response: #{inspect(decode_error)}")
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

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @impl true
  def init(_state) do
    # Initialize cache and rate limit tables
    :ets.new(@cache_table, [:named_table, :public, :set])
    :ets.new(@rate_limit_table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_cached_movie_details, movie_id}, _from, state) do
    result =
      case get_from_cache(movie_id) do
        {:ok, cached_data} ->
          {:ok, cached_data}

        {:error, :not_found} ->
          fetch_and_cache_movie_details(movie_id)
      end

    {:reply, result, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_api_key do
    case System.get_env("TMDB_API_KEY") do
      nil -> {:error, "TMDB_API_KEY is not set in environment"}
      "" -> {:error, "TMDB_API_KEY is not set in environment"}
      key -> {:ok, key}
    end
  end

  defp check_rate_limit do
    current_time = System.monotonic_time(:millisecond)
    window_start = current_time - @rate_limit_window

    # Clean old entries
    :ets.select_delete(@rate_limit_table, [{{:"$1", :"$2"}, [{:<, :"$2", window_start}], [true]}])

    # Count current requests in window
    count = :ets.info(@rate_limit_table, :size)

    if count < @rate_limit_max_requests do
      :ets.insert(@rate_limit_table, {make_ref(), current_time})
      :ok
    else
      {:error, :rate_limited}
    end
  end

  defp get_from_cache(movie_id) do
    cache_key = "movie_#{movie_id}"

    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, data, timestamp}] ->
        if cache_valid?(timestamp) do
          {:ok, data}
        else
          :ets.delete(@cache_table, cache_key)
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp put_in_cache(movie_id, data) do
    cache_key = "movie_#{movie_id}"
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(@cache_table, {cache_key, data, timestamp})
  end

  defp cache_valid?(timestamp) do
    current_time = System.monotonic_time(:millisecond)
    current_time - timestamp < @cache_ttl
  end

  defp fetch_and_cache_movie_details(movie_id) do
    case get_movie_details(movie_id) do
      {:ok, movie_data} ->
        put_in_cache(movie_id, movie_data)
        {:ok, movie_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_popular_movies(page, api_key) do
    url = "#{@base_url}/movie/popular?api_key=#{api_key}&page=#{page}&language=en-US"
    headers = [{"Accept", "application/json"}]

    Logger.debug(
      "TMDB popular movies URL: #{@base_url}/movie/popular?page=#{page}&language=en-US"
    )

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => movies}} ->
            formatted_movies = Enum.map(movies, &format_popular_movie/1)
            {:ok, formatted_movies}

          {:error, decode_error} ->
            Logger.error(
              "Failed to decode TMDB popular movies response: #{inspect(decode_error)}"
            )

            {:error, "Failed to decode popular movies data"}
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("TMDB popular movies error: #{code} - #{body}")
        {:error, "TMDB API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("TMDB popular movies HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp format_popular_movie(movie_data) do
    %{
      tmdb_id: movie_data["id"],
      title: movie_data["title"],
      overview: movie_data["overview"],
      release_date: movie_data["release_date"],
      poster_path: movie_data["poster_path"],
      backdrop_path: movie_data["backdrop_path"],
      vote_average: movie_data["vote_average"],
      vote_count: movie_data["vote_count"],
      popularity: movie_data["popularity"],
      genre_ids: movie_data["genre_ids"] || [],
      adult: movie_data["adult"],
      original_language: movie_data["original_language"],
      original_title: movie_data["original_title"]
    }
  end

  defp fetch_movie_details(movie_id, api_key) do
    # Fetch movie details with cast, crew, and images in parallel
    append_to_response = "credits,images,videos,external_ids"

    url =
      "#{@base_url}/movie/#{movie_id}?api_key=#{api_key}&append_to_response=#{append_to_response}&include_image_language=en,null"

    headers = [{"Accept", "application/json"}]

    Logger.debug(
      "TMDB movie details URL: #{@base_url}/movie/#{movie_id}?append_to_response=#{append_to_response}&include_image_language=en,null"
    )

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, movie_data} ->
            {:ok, format_detailed_movie_data(movie_data)}

          {:error, decode_error} ->
            Logger.error("Failed to decode TMDB movie response: #{inspect(decode_error)}")
            {:error, "Failed to decode movie data"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Movie not found"}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("TMDB movie details error: #{code} - #{body}")
        {:error, "TMDB API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("TMDB movie details HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp fetch_tv_details(tv_id, api_key) do
    # Fetch TV show details with cast, crew, and images
    append_to_response = "credits,images,videos,external_ids"

    url =
      "#{@base_url}/tv/#{tv_id}?api_key=#{api_key}&append_to_response=#{append_to_response}&include_image_language=en,null"

    headers = [{"Accept", "application/json"}]

    Logger.debug(
      "TMDB TV details URL: #{@base_url}/tv/#{tv_id}?append_to_response=#{append_to_response}&include_image_language=en,null"
    )

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, tv_data} ->
            {:ok, format_detailed_tv_data(tv_data)}

          {:error, decode_error} ->
            Logger.error("Failed to decode TMDB TV response: #{inspect(decode_error)}")
            {:error, "Failed to decode TV data"}
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "TV show not found"}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("TMDB TV details error: #{code} - #{body}")
        {:error, "TMDB API error: #{code}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("TMDB TV details HTTP error: #{inspect(reason)}")
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp format_detailed_movie_data(movie_data) do
    %{
      source: "tmdb",
      type: "movie",
      tmdb_id: movie_data["id"],
      title: movie_data["title"],
      tagline: movie_data["tagline"],
      overview: movie_data["overview"],
      release_date: movie_data["release_date"],
      runtime: movie_data["runtime"],
      genres: Enum.map(movie_data["genres"] || [], & &1["name"]),
      poster_path: movie_data["poster_path"],
      backdrop_path: movie_data["backdrop_path"],
      vote_average: movie_data["vote_average"],
      vote_count: movie_data["vote_count"],
      budget: movie_data["budget"],
      revenue: movie_data["revenue"],
      status: movie_data["status"],
      original_language: movie_data["original_language"],
      production_companies: format_production_companies(movie_data["production_companies"]),
      production_countries: format_production_countries(movie_data["production_countries"]),
      spoken_languages: format_spoken_languages(movie_data["spoken_languages"]),
      director: extract_director(movie_data["credits"]),
      cast: format_cast(movie_data["credits"]["cast"]),
      crew: format_crew(movie_data["credits"]["crew"]),
      images: format_images(movie_data["images"]),
      videos: format_videos(movie_data["videos"]),
      external_links:
        format_external_links(
          movie_data["external_ids"],
          movie_data["homepage"],
          movie_data["id"],
          "movie"
        ),
      popularity: movie_data["popularity"],
      adult: movie_data["adult"]
    }
  end

  defp format_detailed_tv_data(tv_data) do
    %{
      source: "tmdb",
      type: "tv",
      tmdb_id: tv_data["id"],
      name: tv_data["name"],
      overview: tv_data["overview"],
      first_air_date: tv_data["first_air_date"],
      last_air_date: tv_data["last_air_date"],
      number_of_seasons: tv_data["number_of_seasons"],
      number_of_episodes: tv_data["number_of_episodes"],
      episode_run_time: tv_data["episode_run_time"],
      genres: Enum.map(tv_data["genres"] || [], & &1["name"]),
      poster_path: tv_data["poster_path"],
      backdrop_path: tv_data["backdrop_path"],
      vote_average: tv_data["vote_average"],
      vote_count: tv_data["vote_count"],
      status: tv_data["status"],
      networks: format_networks(tv_data["networks"]),
      production_companies: format_production_companies(tv_data["production_companies"]),
      cast: format_cast(tv_data["credits"]["cast"]),
      crew: format_crew(tv_data["credits"]["crew"]),
      images: format_images(tv_data["images"]),
      videos: format_videos(tv_data["videos"]),
      external_links:
        format_external_links(tv_data["external_ids"], tv_data["homepage"], tv_data["id"], "tv"),
      popularity: tv_data["popularity"]
    }
  end

  # Helper functions for formatting rich data
  defp extract_director(%{"crew" => crew}) when is_list(crew) do
    case Enum.find(crew, &(&1["job"] == "Director")) do
      nil ->
        nil

      director ->
        %{
          name: director["name"],
          profile_path: director["profile_path"],
          tmdb_id: director["id"]
        }
    end
  end

  defp extract_director(_), do: nil

  defp format_cast(cast) when is_list(cast) do
    cast
    # Limit to top 10 cast members
    |> Enum.take(10)
    |> Enum.map(fn member ->
      %{
        name: member["name"],
        character: member["character"],
        profile_path: member["profile_path"],
        tmdb_id: member["id"],
        order: member["order"]
      }
    end)
  end

  defp format_cast(_), do: []

  defp format_crew(crew) when is_list(crew) do
    # Focus on key crew roles
    key_jobs = ["Director", "Producer", "Executive Producer", "Screenplay", "Writer"]

    crew
    |> Enum.filter(&(&1["job"] in key_jobs))
    |> Enum.map(fn member ->
      %{
        name: member["name"],
        job: member["job"],
        department: member["department"],
        profile_path: member["profile_path"],
        tmdb_id: member["id"]
      }
    end)
  end

  defp format_crew(_), do: []

  defp format_production_companies(companies) when is_list(companies) do
    Enum.map(companies, fn company ->
      %{
        name: company["name"],
        logo_path: company["logo_path"],
        origin_country: company["origin_country"],
        tmdb_id: company["id"]
      }
    end)
  end

  defp format_production_companies(_), do: []

  defp format_production_countries(countries) when is_list(countries) do
    Enum.map(countries, & &1["name"])
  end

  defp format_production_countries(_), do: []

  defp format_spoken_languages(languages) when is_list(languages) do
    Enum.map(languages, & &1["english_name"])
  end

  defp format_spoken_languages(_), do: []

  defp format_networks(networks) when is_list(networks) do
    Enum.map(networks, fn network ->
      %{
        name: network["name"],
        logo_path: network["logo_path"],
        origin_country: network["origin_country"],
        tmdb_id: network["id"]
      }
    end)
  end

  defp format_networks(_), do: []

  defp format_images(%{"backdrops" => backdrops, "posters" => posters}) do
    %{
      backdrops: format_image_list(backdrops),
      posters: format_image_list(posters)
    }
  end

  defp format_images(_), do: %{backdrops: [], posters: []}

  defp format_image_list(images) when is_list(images) do
    images
    # Limit to 5 images per type
    |> Enum.take(5)
    |> Enum.map(fn image ->
      %{
        file_path: image["file_path"],
        width: image["width"],
        height: image["height"],
        aspect_ratio: image["aspect_ratio"],
        vote_average: image["vote_average"]
      }
    end)
  end

  defp format_image_list(_), do: []

  defp format_videos(%{"results" => videos}) when is_list(videos) do
    videos
    |> Enum.filter(&(&1["site"] == "YouTube" && &1["type"] in ["Trailer", "Teaser", "Clip"]))
    # Limit to 3 videos
    |> Enum.take(3)
    |> Enum.map(fn video ->
      %{
        key: video["key"],
        name: video["name"],
        type: video["type"],
        site: video["site"],
        size: video["size"],
        official: video["official"]
      }
    end)
  end

  defp format_videos(_), do: []

  defp format_external_links(external_ids, homepage, tmdb_id, type) do
    links = %{
      tmdb_url: "https://www.themoviedb.org/#{type}/#{tmdb_id}",
      homepage: homepage
    }

    # Add external links if available
    links =
      if external_ids["imdb_id"],
        do: Map.put(links, :imdb_url, "https://www.imdb.com/title/#{external_ids["imdb_id"]}"),
        else: links

    links =
      if external_ids["facebook_id"],
        do:
          Map.put(links, :facebook_url, "https://www.facebook.com/#{external_ids["facebook_id"]}"),
        else: links

    links =
      if external_ids["twitter_id"],
        do: Map.put(links, :twitter_url, "https://twitter.com/#{external_ids["twitter_id"]}"),
        else: links

    links =
      if external_ids["instagram_id"],
        do:
          Map.put(
            links,
            :instagram_url,
            "https://www.instagram.com/#{external_ids["instagram_id"]}"
          ),
        else: links

    links
  end
end
