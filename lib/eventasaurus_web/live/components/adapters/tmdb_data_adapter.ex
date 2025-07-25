defmodule EventasaurusWeb.Live.Components.Adapters.TmdbDataAdapter do
  @moduledoc """
  Data adapter for TMDB (The Movie Database) content.

  Normalizes TMDB movie and TV show data into the standardized format
  for use with generic rich content display components.
  """

  @behaviour EventasaurusWeb.Live.Components.RichDataAdapterBehaviour

  alias EventasaurusWeb.Utils.MovieUtils

  @impl true
  def adapt(raw_data) when is_map(raw_data) do
    %{
      id: get_tmdb_id(raw_data),
      type: get_content_type(raw_data),
      title: get_title(raw_data),
      description: get_description(raw_data),
      primary_image: get_primary_image(raw_data),
      secondary_image: get_secondary_image(raw_data),
      rating: get_rating_info(raw_data),
      year: get_year(raw_data),
      status: get_status(raw_data),
      categories: get_categories(raw_data),
      tags: get_tags(raw_data),
      external_urls: get_external_urls(raw_data),
      sections: build_sections(raw_data)
    }
  end

  @impl true
  def content_type, do: :movie

  @impl true
  def supported_sections, do: [:hero, :overview, :cast, :media, :details]

  @impl true
  def handles?(raw_data) when is_map(raw_data) do
    # Check if this looks like TMDB data - support both legacy and rich data formats
    has_tmdb_id = Map.has_key?(raw_data, "id") && is_integer(raw_data["id"])
    has_movie_fields = Map.has_key?(raw_data, "title") || Map.has_key?(raw_data, "name")

    # Check for TMDB fields in legacy format (direct keys)
    has_legacy_tmdb_fields = Map.has_key?(raw_data, "vote_average") || Map.has_key?(raw_data, "poster_path")

    # Check for TMDB fields in rich data format (nested in metadata)
    metadata = raw_data["metadata"] || %{}
    has_rich_tmdb_fields = Map.has_key?(metadata, "vote_average") || Map.has_key?(metadata, "poster_path")

    # Check for rich data structure indicators
    has_rich_structure = Map.has_key?(raw_data, "type") && Map.has_key?(raw_data, "metadata")

    # Accept if it's either legacy TMDB data or rich TMDB data
    has_tmdb_id && has_movie_fields && (has_legacy_tmdb_fields || has_rich_tmdb_fields || has_rich_structure)
  end

  @impl true
  def display_config do
    %{
      default_sections: [:hero, :overview, :cast, :media, :details],
      compact_sections: [:hero, :overview],
      required_fields: [:id, :title, :type],
      optional_fields: [:description, :rating, :year, :categories, :primary_image]
    }
  end

  # Private implementation functions

  defp get_tmdb_id(raw_data) do
    case raw_data["id"] do
      id when is_integer(id) -> "tmdb_#{id}"
      id when is_binary(id) -> "tmdb_#{id}"
      _ -> "tmdb_unknown"
    end
  end

  defp get_content_type(raw_data) do
    cond do
      raw_data["title"] -> :movie
      raw_data["name"] && raw_data["first_air_date"] -> :tv
      raw_data["name"] -> :movie  # Fallback for movies with 'name' field
      true -> :movie
    end
  end

  defp get_title(raw_data) do
    MovieUtils.get_title(raw_data)
  end

  defp get_description(raw_data) do
    # Support both direct fields and rich data format (string and atom keys)
    tagline = raw_data["tagline"] || get_in(raw_data, ["metadata", "tagline"]) || get_in(raw_data, [:metadata, "tagline"])
    overview = raw_data["overview"] || get_in(raw_data, ["metadata", "overview"]) || get_in(raw_data, [:metadata, "overview"]) || raw_data["description"]

    cond do
      tagline && tagline != "" -> tagline
      overview && overview != "" -> truncate_text(overview, 200)
      true -> nil
    end
  end

  defp get_primary_image(raw_data) do
    case MovieUtils.get_poster_url(raw_data) do
      url when is_binary(url) ->
        %{
          url: url,
          alt: get_title(raw_data),
          type: :poster
        }
      _ -> nil
    end
  end

  defp get_secondary_image(raw_data) do
    case MovieUtils.get_backdrop_url(raw_data) do
      url when is_binary(url) ->
        %{
          url: url,
          alt: "#{get_title(raw_data)} backdrop",
          type: :backdrop
        }
      _ -> nil
    end
  end

  defp get_rating_info(raw_data) do
    # Support both legacy and rich data format (string and atom keys)
    vote_average = raw_data["vote_average"] || get_in(raw_data, ["metadata", "vote_average"]) || get_in(raw_data, [:metadata, "vote_average"])
    vote_count = raw_data["vote_count"] || get_in(raw_data, ["metadata", "vote_count"]) || get_in(raw_data, [:metadata, "vote_count"])

    case {vote_average, vote_count} do
      {avg, count} when is_number(avg) and is_integer(count) ->
        %{
          value: avg,
          scale: 10,
          count: count,
          display: "#{format_rating(avg)}/10"
        }
      {avg, _} when is_number(avg) ->
        %{
          value: avg,
          scale: 10,
          count: 0,
          display: "#{format_rating(avg)}/10"
        }
      _ -> nil
    end
  end

  defp get_year(raw_data) do
    MovieUtils.get_release_year(raw_data)
  end

  defp get_status(raw_data) do
    status = raw_data["status"]

    case status do
      "Released" -> "released"
      "Post Production" -> "post_production"
      "In Production" -> "in_production"
      "Planned" -> "planned"
      "Canceled" -> "canceled"
      status when is_binary(status) -> String.downcase(status)
      _ -> nil
    end
  end

  defp get_categories(raw_data) do
    MovieUtils.get_genres(raw_data)
  end

  defp get_tags(raw_data) do
    tags = []

    # Add tags based on various criteria
    tags = if raw_data["adult"], do: ["Adult Content" | tags], else: tags
    tags = if (raw_data["vote_average"] || 0) >= 8.0, do: ["Highly Rated" | tags], else: tags
    tags = if (raw_data["popularity"] || 0) >= 100, do: ["Popular" | tags], else: tags

    tags
  end

  defp get_external_urls(raw_data) do
    external_ids = raw_data["external_ids"] || %{}

    %{
      source: build_tmdb_url(raw_data),
      official: raw_data["homepage"],
      imdb: build_imdb_url(external_ids["imdb_id"]),
      social: %{
        facebook: build_facebook_url(external_ids["facebook_id"]),
        twitter: build_twitter_url(external_ids["twitter_id"]),
        instagram: build_instagram_url(external_ids["instagram_id"])
      }
    }
    |> filter_empty_urls()
  end

  defp build_sections(raw_data) do
    %{
      hero: build_hero_section(raw_data),
      overview: build_overview_section(raw_data),
      cast: build_cast_section(raw_data),
      media: build_media_section(raw_data),
      details: build_details_section(raw_data)
    }
    |> Enum.filter(fn {_key, value} -> value != nil end)
    |> Enum.into(%{})
  end

  defp build_hero_section(raw_data) do
    secondary_image = get_secondary_image(raw_data)
    primary_image = get_primary_image(raw_data)

    %{
      title: get_title(raw_data),
      tagline: raw_data["tagline"] || get_in(raw_data, ["metadata", "tagline"]),
      backdrop_url: secondary_image && secondary_image[:url],
      poster_url: primary_image && primary_image[:url],
      rating: get_rating_info(raw_data),
      runtime: raw_data["runtime"] || get_in(raw_data, ["metadata", "runtime"]),
      genres: get_categories(raw_data),
      release_info: build_release_info(raw_data)
    }
  end

  defp build_overview_section(raw_data) do
    # Support both direct overview and nested in description/metadata
    overview = raw_data["overview"] ||
               get_in(raw_data, ["metadata", "overview"]) ||
               raw_data["description"]

    if overview do
      %{
        overview: overview,
        director: raw_data["director"],
        key_crew: extract_key_crew(raw_data["crew"])
      }
    end
  end

  defp build_cast_section(raw_data) do
    if raw_data["cast"] || raw_data["crew"] do
      %{
        cast: raw_data["cast"] || [],
        crew: raw_data["crew"] || [],
        director: raw_data["director"]
      }
    end
  end

  defp build_media_section(raw_data) do
    # Support both direct videos/images and nested media structure
    videos = raw_data["videos"] ||
             get_in(raw_data, ["media", "videos"]) ||
             []

    # Handle images from multiple possible locations
    images = cond do
      # Rich data format: media.images
      media_images = get_in(raw_data, ["media", "images"]) ->
        media_images

      # Legacy format: direct images field (only if it's a map)
      is_map(raw_data["images"]) ->
        raw_data["images"]

      # Default to empty map
      true ->
        %{}
    end

    if length(videos) > 0 || map_size(images) > 0 do
      %{
        videos: videos,
        images: images
      }
    end
  end

  defp build_details_section(raw_data) do
    %{
      release_date: raw_data["release_date"] ||
                   raw_data["first_air_date"] ||
                   get_in(raw_data, ["metadata", "release_date"]) ||
                   get_in(raw_data, ["metadata", "first_air_date"]),
      runtime: raw_data["runtime"] || get_in(raw_data, ["metadata", "runtime"]),
      status: raw_data["status"] || get_in(raw_data, ["metadata", "status"]),
      budget: raw_data["budget"] || get_in(raw_data, ["metadata", "budget"]),
      revenue: raw_data["revenue"] || get_in(raw_data, ["metadata", "revenue"]),
      production_companies: raw_data["production_companies"] ||
                          get_in(raw_data, ["metadata", "production_companies"]) || [],
      spoken_languages: raw_data["spoken_languages"] ||
                       get_in(raw_data, ["metadata", "spoken_languages"]) || [],
      external_ids: raw_data["external_ids"] || %{}
    }
  end

  # Helper functions

  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating, [{:decimals, 1}])
  end
  defp format_rating(_), do: "N/A"

  defp truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      text
      |> String.slice(0, max_length)
      |> String.trim_trailing()
      |> Kernel.<>("...")
    end
  end

  defp build_release_info(raw_data) do
    year = MovieUtils.get_release_year(raw_data)

    # Still need to get formatted date for this adapter's specific needs
    date_string = raw_data["release_date"] ||
                  raw_data["first_air_date"] ||
                  get_in(raw_data, ["metadata", "release_date"]) ||
                  get_in(raw_data, ["metadata", "first_air_date"])

    formatted = case date_string do
      date when is_binary(date) and date != "" ->
        case Date.from_iso8601(date) do
          {:ok, date} -> Calendar.strftime(date, "%B %d, %Y")
          _ -> nil
        end
      _ -> nil
    end

    case {year, formatted} do
      {nil, nil} -> %{}
      {year, formatted} -> %{year: year, formatted: formatted}
    end
  end

  defp extract_key_crew(nil), do: []
  defp extract_key_crew(crew) when is_list(crew) do
    crew
    |> Enum.filter(&(&1["job"] in ["Director", "Producer", "Executive Producer", "Writer", "Screenplay"]))
    |> Enum.take(5)
  end

  defp build_tmdb_url(raw_data) do
    type = if raw_data["title"], do: "movie", else: "tv"
    id = raw_data["id"]
    if id, do: "https://www.themoviedb.org/#{type}/#{id}"
  end

  defp build_imdb_url(nil), do: nil
  defp build_imdb_url(imdb_id) when is_binary(imdb_id) do
    "https://www.imdb.com/title/#{imdb_id}"
  end

  defp build_facebook_url(nil), do: nil
  defp build_facebook_url(facebook_id) when is_binary(facebook_id) do
    "https://www.facebook.com/#{facebook_id}"
  end

  defp build_twitter_url(nil), do: nil
  defp build_twitter_url(twitter_id) when is_binary(twitter_id) do
    "https://twitter.com/#{twitter_id}"
  end

  defp build_instagram_url(nil), do: nil
  defp build_instagram_url(instagram_id) when is_binary(instagram_id) do
    "https://www.instagram.com/#{instagram_id}"
  end

  defp filter_empty_urls(url_map) when is_map(url_map) do
    url_map
    |> Enum.filter(fn
      {_key, value} when is_binary(value) -> value != ""
      {_key, value} when is_map(value) -> map_size(filter_empty_urls(value)) > 0
      _ -> false
    end)
    |> Enum.into(%{})
  end
end
