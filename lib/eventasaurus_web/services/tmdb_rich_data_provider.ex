defmodule EventasaurusWeb.Services.TmdbRichDataProvider do
  @moduledoc """
  TMDB (The Movie Database) provider for rich data integration.

  Implements the RichDataProviderBehaviour for movie and TV show data.
  Wraps the existing TmdbService with the standardized provider interface.
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour

  alias EventasaurusWeb.Services.TmdbService
  require Logger

  # ============================================================================
  # Provider Behaviour Implementation
  # ============================================================================

  @impl true
  def provider_id, do: :tmdb

  @impl true
  def provider_name, do: "The Movie Database"

  @impl true
  def supported_types, do: [:movie, :tv]

  @impl true
  def search(query, options \\ %{}) do
    page = Map.get(options, :page, 1)
    content_type = Map.get(options, :content_type)

    case TmdbService.search_multi(query, page) do
      {:ok, results} ->
        # Filter by content_type if specified
        filtered_results = case content_type do
          :movie -> Enum.filter(results, &(&1.type == :movie))
          :tv -> Enum.filter(results, &(&1.type == :tv))
          _ -> results
        end

        normalized_results = Enum.map(filtered_results, &normalize_search_result/1)
        {:ok, normalized_results}
      {:error, reason} ->
        Logger.error("TMDB search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_details(id, type, _options \\ %{}) do
    case type do
      :movie ->
        case TmdbService.get_movie_details(id) do
          {:ok, movie_data} ->
            {:ok, normalize_movie_details(movie_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :tv ->
        case TmdbService.get_tv_details(id) do
          {:ok, tv_data} ->
            {:ok, normalize_tv_details(tv_data)}
          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def get_cached_details(id, type, options \\ %{}) do
    case type do
      :movie ->
        case TmdbService.get_cached_movie_details(id) do
          {:ok, movie_data} ->
            {:ok, normalize_movie_details(movie_data)}
          {:error, reason} ->
            {:error, reason}
        end

      :tv ->
        # TV shows don't have caching yet in TmdbService, fall back to regular details
        get_details(id, type, options)

      _ ->
        {:error, "Unsupported content type: #{type}"}
    end
  end

  @impl true
  def validate_config do
    case System.get_env("TMDB_API_KEY") do
      nil -> {:error, "TMDB_API_KEY environment variable is not set"}
      "" -> {:error, "TMDB_API_KEY environment variable is empty"}
      _key -> :ok
    end
  end

  @impl true
  def config_schema do
    %{
      api_key: %{
        type: :string,
        required: true,
        description: "TMDB API key from https://www.themoviedb.org/settings/api"
      },
      base_url: %{
        type: :string,
        required: false,
        default: "https://api.themoviedb.org/3",
        description: "TMDB API base URL"
      },
      rate_limit: %{
        type: :integer,
        required: false,
        default: 40,
        description: "Maximum requests per second"
      },
      cache_ttl: %{
        type: :integer,
        required: false,
        default: 21600, # 6 hours in seconds
        description: "Cache time-to-live in seconds"
      }
    }
  end

  # ============================================================================
  # Private Functions - Data Normalization
  # ============================================================================

  defp normalize_search_result(%{type: :movie} = result) do
    %{
      id: result.id,
      type: :movie,
      title: result.title,
      description: result.overview || "",
      images: build_images_list(result.poster_path, nil),
      metadata: %{
        release_date: result.release_date,
        tmdb_id: result.id,
        media_type: "movie"
      }
    }
  end

  defp normalize_search_result(%{type: :tv} = result) do
    %{
      id: result.id,
      type: :tv,
      title: result.name,
      description: result.overview || "",
      images: build_images_list(result.poster_path, nil),
      metadata: %{
        first_air_date: result.first_air_date,
        tmdb_id: result.id,
        media_type: "tv"
      }
    }
  end

  defp normalize_search_result(%{type: :person} = result) do
    %{
      id: result.id,
      type: :person,
      title: result.name,
      description: "",
      images: build_images_list(result.profile_path, nil),
      metadata: %{
        known_for: result.known_for,
        tmdb_id: result.id,
        media_type: "person"
      }
    }
  end

  defp normalize_search_result(result) do
    # Fallback for unknown types
    %{
      id: Map.get(result, :id),
      type: Map.get(result, :type, :unknown),
      title: Map.get(result, :title) || Map.get(result, :name) || "Unknown",
      description: Map.get(result, :overview) || "",
      images: [],
      metadata: %{
        tmdb_id: Map.get(result, :id),
        media_type: Map.get(result, :type, "unknown")
      }
    }
  end

  defp normalize_movie_details(movie_data) do
    %{
      id: movie_data.tmdb_id,
      type: :movie,
      title: movie_data.title,
      description: movie_data.overview || "",
      metadata: %{
        tmdb_id: movie_data.tmdb_id,
        release_date: movie_data.release_date,
        runtime: Map.get(movie_data, :runtime),
        genres: Map.get(movie_data, :genres, []),
        original_language: Map.get(movie_data, :original_language),
        original_title: Map.get(movie_data, :original_title, movie_data.title),
        tagline: Map.get(movie_data, :tagline),
        vote_average: Map.get(movie_data, :vote_average, 0),
        vote_count: Map.get(movie_data, :vote_count, 0),
        popularity: Map.get(movie_data, :popularity, 0),
        budget: Map.get(movie_data, :budget, 0),
        revenue: Map.get(movie_data, :revenue, 0),
        status: Map.get(movie_data, :status),
        production_companies: Map.get(movie_data, :production_companies, []),
        production_countries: Map.get(movie_data, :production_countries, []),
        spoken_languages: Map.get(movie_data, :spoken_languages, []),
        imdb_id: Map.get(movie_data, :imdb_id)
      },
      images: normalize_images(movie_data.images),
      external_urls: build_external_urls(movie_data),
      cast: Map.get(movie_data, :cast, []),
      crew: Map.get(movie_data, :crew, []),
      media: %{
        videos: Map.get(movie_data, :videos, []),
        images: Map.get(movie_data, :images, %{})
      },
      additional_data: %{
        keywords: Map.get(movie_data, :keywords, []),
        recommendations: Map.get(movie_data, :recommendations, []),
        similar: Map.get(movie_data, :similar, []),
        belongs_to_collection: Map.get(movie_data, :belongs_to_collection)
      }
    }
  end

  defp normalize_tv_details(tv_data) do
    %{
      id: tv_data.tmdb_id,
      type: :tv,
      title: tv_data.name,
      description: tv_data.overview || "",
      metadata: %{
        tmdb_id: tv_data.tmdb_id,
        first_air_date: Map.get(tv_data, :first_air_date),
        last_air_date: Map.get(tv_data, :last_air_date),
        number_of_episodes: Map.get(tv_data, :number_of_episodes, 0),
        number_of_seasons: Map.get(tv_data, :number_of_seasons, 0),
        genres: Map.get(tv_data, :genres, []),
        original_language: Map.get(tv_data, :original_language),
        original_name: Map.get(tv_data, :original_name, tv_data.name),
        tagline: Map.get(tv_data, :tagline),
        vote_average: Map.get(tv_data, :vote_average, 0),
        vote_count: Map.get(tv_data, :vote_count, 0),
        popularity: Map.get(tv_data, :popularity, 0),
        status: Map.get(tv_data, :status),
        type: Map.get(tv_data, :type),
        networks: Map.get(tv_data, :networks, []),
        production_companies: Map.get(tv_data, :production_companies, []),
        production_countries: Map.get(tv_data, :production_countries, []),
        spoken_languages: Map.get(tv_data, :spoken_languages, []),
        seasons: Map.get(tv_data, :seasons, []),
        episode_run_time: Map.get(tv_data, :episode_run_time, [])
      },
      images: normalize_images(tv_data.images),
      external_urls: build_external_urls(tv_data),
      cast: Map.get(tv_data, :cast, []),
      crew: Map.get(tv_data, :crew, []),
      media: %{
        videos: Map.get(tv_data, :videos, []),
        images: Map.get(tv_data, :images, %{})
      },
      additional_data: %{
        keywords: Map.get(tv_data, :keywords, []),
        recommendations: Map.get(tv_data, :recommendations, []),
        similar: Map.get(tv_data, :similar, []),
        created_by: Map.get(tv_data, :created_by, [])
      }
    }
  end

  defp normalize_images(images) when is_map(images) do
    poster_images = build_image_variants(images["posters"] || [], :poster)
    backdrop_images = build_image_variants(images["backdrops"] || [], :backdrop)
    poster_images ++ backdrop_images
  end

  defp normalize_images(_), do: []

  defp build_image_variants(image_list, type) when is_list(image_list) do
    Enum.map(image_list, fn image ->
      %{
        url: tmdb_image_url(image["file_path"]),
        type: type,
        size: "original",
        width: image["width"],
        height: image["height"],
        aspect_ratio: image["aspect_ratio"],
        language: image["iso_639_1"],
        vote_average: image["vote_average"],
        vote_count: image["vote_count"]
      }
    end)
  end

  defp build_image_variants(_, _), do: []

  defp build_images_list(poster_path, backdrop_path) do
    images = []

    images = if poster_path do
      [%{
        url: tmdb_image_url(poster_path),
        type: :poster,
        size: "w500"
      } | images]
    else
      images
    end

    images = if backdrop_path do
      [%{
        url: tmdb_image_url(backdrop_path),
        type: :backdrop,
        size: "w1280"
      } | images]
    else
      images
    end

    images
  end

  defp build_external_urls(data) do
    urls = %{
      tmdb: build_tmdb_url(data)
    }

    # Add IMDB URL if available
    urls = if Map.get(data, :imdb_id) do
      Map.put(urls, :imdb, "https://www.imdb.com/title/#{data.imdb_id}")
    else
      urls
    end

    # Add other external IDs if available
    case Map.get(data, :external_ids) do
      %{} = external_ids ->
        urls
        |> maybe_add_external_url(:facebook, external_ids["facebook_id"], "https://www.facebook.com/")
        |> maybe_add_external_url(:twitter, external_ids["twitter_id"], "https://twitter.com/")
        |> maybe_add_external_url(:instagram, external_ids["instagram_id"], "https://www.instagram.com/")
      _ ->
        urls
    end
  end

  defp build_tmdb_url(%{tmdb_id: id, type: :movie}), do: "https://www.themoviedb.org/movie/#{id}"
  defp build_tmdb_url(%{tmdb_id: id, type: :tv}), do: "https://www.themoviedb.org/tv/#{id}"
  defp build_tmdb_url(%{tmdb_id: id, name: _}), do: "https://www.themoviedb.org/tv/#{id}"
  defp build_tmdb_url(%{tmdb_id: id}), do: "https://www.themoviedb.org/movie/#{id}"

  defp maybe_add_external_url(urls, _key, nil, _base_url), do: urls
  defp maybe_add_external_url(urls, _key, "", _base_url), do: urls
  defp maybe_add_external_url(urls, key, id, base_url) do
    Map.put(urls, key, "#{base_url}#{id}")
  end

  defp tmdb_image_url(nil), do: nil
  defp tmdb_image_url(""), do: nil
  defp tmdb_image_url(path) when is_binary(path) do
    "https://image.tmdb.org/t/p/original#{path}"
  end
end
