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
  """

  require Logger

  alias EventasaurusApp.Images.ImageCacheService

  # High priority sources (known failure domains like expiring URLs)
  @high_priority_sources ["question-one"]

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
