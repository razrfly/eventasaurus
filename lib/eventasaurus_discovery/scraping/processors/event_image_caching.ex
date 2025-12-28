defmodule EventasaurusDiscovery.Scraping.Processors.EventImageCaching do
  @moduledoc """
  Integration for event image caching to R2.

  Extends venue image caching to events. All sources with valid slugs
  are automatically enabled for lazy image caching on render.

  ## Usage

  Called from EventProcessor.update_event_source/4 to:
  1. Queue the image for caching via ImageCacheService
  2. Extract raw metadata for debugging
  3. Return the cached URL or fall back to original

  ## Multi-Image Support

  Sources like Ticketmaster and Resident Advisor provide multiple images.
  Use `cache_event_images/4` to cache multiple images with semantic types:

      images = [
        %{url: hero_url, image_type: "hero", position: 0},
        %{url: poster_url, image_type: "poster", position: 1},
        %{url: gallery1, image_type: "gallery", position: 2}
      ]
      cache_event_images(images, event_source_id, source_slug, scraped_data)
  """

  require Logger

  alias EventasaurusApp.Images.ImageCacheService

  # High priority sources (known failure domains like expiring URLs)
  @high_priority_sources ["question-one"]

  # Valid image types for event sources
  @valid_image_types ["hero", "poster", "gallery", "primary"]

  @doc """
  Check if image caching is enabled for a given source.

  All valid source slugs are enabled. Only nil is disabled.
  """
  @spec enabled?(String.t() | nil) :: boolean()
  def enabled?(nil), do: false
  def enabled?(source_slug) when is_binary(source_slug), do: true

  @doc """
  Get the Oban job priority for a source.

  High priority sources (known failure domains) get priority 1.
  Normal sources get priority 2.
  """
  @spec priority(String.t() | nil) :: integer()
  def priority(nil), do: 2

  def priority(source_slug) when is_binary(source_slug) do
    if source_slug in @high_priority_sources, do: 1, else: 2
  end

  @doc """
  Cache an event image and return the effective URL.

  ## Returns

  - `{:ok, url}` - Successfully queued for caching (returns original URL until cached)
  - `{:cached, cdn_url}` - Already cached, returns CDN URL
  - `{:fallback, original_url}` - Caching disabled or failed, use original
  """
  @spec cache_event_image(String.t() | nil, integer(), String.t() | nil, map()) ::
          {:ok, String.t()} | {:cached, String.t()} | {:fallback, String.t() | nil}
  def cache_event_image(nil, _event_source_id, _source_slug, _scraped_data) do
    {:fallback, nil}
  end

  def cache_event_image(image_url, event_source_id, source_slug, scraped_data) do
    if enabled?(source_slug) do
      do_cache_image(image_url, event_source_id, source_slug, scraped_data)
    else
      {:fallback, image_url}
    end
  end

  @doc """
  Cache multiple event images with semantic types.

  ## Parameters

  - `images` - List of image specs: `[%{url: String.t(), image_type: String.t(), position: integer()}]`
  - `event_source_id` - The public event source ID
  - `source_slug` - Source identifier (e.g., "ticketmaster", "resident-advisor")
  - `scraped_data` - Raw scraped data for metadata extraction

  ## Image Types

  - `"hero"` - Primary/hero image (16:9 preferred, largest)
  - `"poster"` - Poster-style image (4:3 or portrait)
  - `"gallery"` - Additional gallery images
  - `"primary"` - Legacy single-image type

  ## Returns

  - `{:ok, results}` - List of cache results for each image
  - `{:fallback, []}` - Caching disabled or no valid images
  """
  @spec cache_event_images(list(), integer(), String.t() | nil, map()) ::
          {:ok, list()} | {:fallback, list()}
  def cache_event_images([], _event_source_id, _source_slug, _scraped_data) do
    {:fallback, []}
  end

  def cache_event_images(images, event_source_id, source_slug, scraped_data)
      when is_list(images) do
    if enabled?(source_slug) do
      results =
        images
        |> Enum.filter(&valid_image_spec?/1)
        |> Enum.map(fn image_spec ->
          do_cache_typed_image(image_spec, event_source_id, source_slug, scraped_data)
        end)

      Logger.info("""
      📷 Cached #{length(results)} images for event source #{event_source_id}:
        Source: #{source_slug}
        Types: #{results |> Enum.map(fn {_, spec} -> spec.image_type end) |> Enum.join(", ")}
      """)

      {:ok, results}
    else
      {:fallback, []}
    end
  end

  def cache_event_images(_images, _event_source_id, _source_slug, _scraped_data) do
    {:fallback, []}
  end

  # Validate image spec has required fields
  defp valid_image_spec?(%{url: url, image_type: type, position: pos})
       when is_binary(url) and is_binary(type) and is_integer(pos) do
    url != "" and type in @valid_image_types and pos >= 0
  end

  defp valid_image_spec?(_), do: false

  # Cache a single image with type
  defp do_cache_typed_image(
         %{url: url, image_type: image_type, position: position} = spec,
         event_source_id,
         source_slug,
         scraped_data
       ) do
    metadata = extract_metadata(scraped_data, source_slug)
    priority = priority(source_slug)

    case ImageCacheService.cache_image(
           "public_event_source",
           event_source_id,
           position,
           url,
           source: source_slug,
           image_type: image_type,
           metadata: Map.put(metadata, "image_type", image_type),
           priority: priority
         ) do
      {:ok, _cached_image} ->
        {:ok, spec}

      {:exists, cached_image} ->
        if cached_image.status == "cached" && cached_image.cdn_url do
          {:cached, Map.put(spec, :cdn_url, cached_image.cdn_url)}
        else
          {:ok, spec}
        end

      {:skipped, :non_production} ->
        {:ok, spec}

      {:error, reason} ->
        Logger.warning("""
        📷 Failed to cache typed image:
          Event Source ID: #{event_source_id}
          Type: #{image_type}
          Position: #{position}
          Reason: #{inspect(reason)}
        """)

        {:error, spec}
    end
  end

  defp do_cache_image(image_url, event_source_id, source_slug, scraped_data) do
    metadata = extract_metadata(scraped_data, source_slug)
    priority = priority(source_slug)

    Logger.info("""
    📷 Queuing event image for caching:
      Source: #{source_slug}
      Event Source ID: #{event_source_id}
      URL: #{truncate_url(image_url)}
      Priority: #{priority}
    """)

    case ImageCacheService.cache_image(
           "public_event_source",
           event_source_id,
           0,
           image_url,
           source: source_slug,
           metadata: metadata,
           priority: priority
         ) do
      {:ok, _cached_image} ->
        {:ok, image_url}

      {:exists, cached_image} ->
        if cached_image.status == "cached" && cached_image.cdn_url do
          Logger.debug("📷 Using cached image for event source #{event_source_id}")
          {:cached, cached_image.cdn_url}
        else
          {:ok, image_url}
        end

      {:skipped, :non_production} ->
        # In dev/test, caching is skipped - use original URL
        {:ok, image_url}

      {:error, reason} ->
        Logger.warning("""
        📷 Failed to queue image for caching:
          Event Source ID: #{event_source_id}
          URL: #{truncate_url(image_url)}
          Reason: #{inspect(reason)}
        """)

        {:fallback, image_url}
    end
  end

  @doc """
  Extract raw metadata from scraped data for debugging.
  """
  @spec extract_metadata(map(), String.t() | nil) :: map()
  def extract_metadata(scraped_data, source_slug) when is_map(scraped_data) do
    %{
      "source_slug" => source_slug,
      "extraction_timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "original_keys" => extract_keys(scraped_data),
      "raw_data" => sanitize_for_storage(scraped_data)
    }
  end

  def extract_metadata(_, source_slug) do
    %{
      "source_slug" => source_slug,
      "extraction_timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "original_keys" => [],
      "raw_data" => nil
    }
  end

  defp extract_keys(data) when is_map(data) do
    data |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
  end

  defp extract_keys(_), do: []

  defp sanitize_for_storage(data) when is_map(data) do
    data
    |> Enum.reject(fn {_k, v} -> is_binary(v) && byte_size(v) > 10_000 end)
    |> Enum.map(fn {k, v} -> {to_string(k), sanitize_value(v)} end)
    |> Map.new()
  end

  defp sanitize_for_storage(data), do: data

  defp sanitize_value(v) when is_map(v), do: sanitize_for_storage(v)
  defp sanitize_value(v) when is_list(v), do: Enum.map(v, &sanitize_value/1)
  defp sanitize_value(v), do: v

  defp truncate_url(nil), do: nil

  defp truncate_url(url) when is_binary(url) do
    if String.length(url) > 80, do: String.slice(url, 0, 77) <> "...", else: url
  end

  @doc """
  Get image caching statistics.
  """
  @spec stats() :: map()
  def stats do
    %{
      overall: ImageCacheService.stats(),
      high_priority_sources: @high_priority_sources
    }
  end
end
