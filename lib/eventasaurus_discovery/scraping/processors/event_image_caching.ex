defmodule EventasaurusDiscovery.Scraping.Processors.EventImageCaching do
  @moduledoc """
  Configuration and integration for event image caching to R2.

  Phase 2 of image caching - extends the existing venue image caching to events.
  Uses a phased source-by-source rollout for safe deployment.

  ## Wave 1 Sources (Test)
  - question-one: 125 images (known 403 failures - perfect test case)
  - pubquiz-pl: 106 images (small, low risk)

  ## Usage

  This module is called from EventProcessor.update_event_source/4 to:
  1. Check if the source is enabled for image caching
  2. Extract raw metadata for debugging
  3. Queue the image for caching via ImageCacheService
  4. Return the cached URL or fall back to original

  ## Configuration

  Sources are enabled by adding their slug to @enabled_sources.
  Each wave is validated before proceeding to the next.
  """

  require Logger

  alias EventasaurusApp.Images.ImageCacheService

  # Wave 1 sources (enabled for testing)
  # Add more sources as each wave is validated
  @enabled_sources [
    "question-one",
    "pubquiz-pl"
  ]

  # High priority sources (known failure domains, cache immediately)
  @high_priority_sources [
    "question-one"
  ]

  @doc """
  Check if image caching is enabled for a given source.

  ## Parameters

  - `source_slug` - The slug of the source (e.g., "question-one", "pubquiz-pl")

  ## Returns

  - `true` if the source is enabled for image caching
  - `false` otherwise
  """
  @spec enabled?(String.t() | nil) :: boolean()
  def enabled?(nil), do: false
  def enabled?(source_slug) when is_binary(source_slug) do
    source_slug in @enabled_sources
  end

  @doc """
  Get the Oban job priority for a source.

  High priority sources (known failure domains) get priority 1.
  Normal sources get priority 2.

  ## Parameters

  - `source_slug` - The slug of the source

  ## Returns

  - Integer priority (1 = high, 2 = normal)
  """
  @spec priority(String.t() | nil) :: integer()
  def priority(nil), do: 2
  def priority(source_slug) when is_binary(source_slug) do
    if source_slug in @high_priority_sources, do: 1, else: 2
  end

  @doc """
  Cache an event image and return the effective URL.

  If caching is enabled for the source:
  1. Extracts metadata from the scraped data for debugging
  2. Queues the image for caching via ImageCacheService
  3. Returns {:ok, url} where url is either cached or original

  If caching is disabled or fails:
  - Returns {:fallback, original_url}

  ## Parameters

  - `image_url` - The original image URL to cache
  - `event_source_id` - The ID of the PublicEventSource record
  - `source_slug` - The slug of the source (e.g., "question-one")
  - `scraped_data` - The raw scraped data map for metadata extraction

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

  # Internal: Actually perform the caching
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

    # Use position 0 for primary event image
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
        # Image queued for caching - return original URL for now
        # The cached URL will be used once the job completes
        {:ok, image_url}

      {:exists, cached_image} ->
        # Already cached - return the CDN URL if available
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

  Preserves the complete source data to aid in debugging image failures.

  ## Parameters

  - `scraped_data` - The raw scraped data map
  - `source_slug` - The slug of the source

  ## Returns

  Map with extracted metadata including:
  - source_slug: The source identifier
  - extraction_timestamp: When the data was extracted
  - original_keys: List of keys in the scraped data
  - raw_data: The complete scraped data (for debugging)
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

  # Extract keys from a map, handling both atom and string keys
  defp extract_keys(data) when is_map(data) do
    data
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp extract_keys(_), do: []

  # Sanitize data for storage - remove very large fields
  defp sanitize_for_storage(data) when is_map(data) do
    data
    |> Enum.reject(fn {_k, v} ->
      # Remove very large binary data
      is_binary(v) && byte_size(v) > 10_000
    end)
    |> Enum.map(fn {k, v} ->
      # Convert atom keys to strings
      {to_string(k), sanitize_value(v)}
    end)
    |> Map.new()
  end

  defp sanitize_for_storage(data), do: data

  # Recursively sanitize nested maps
  defp sanitize_value(v) when is_map(v), do: sanitize_for_storage(v)
  defp sanitize_value(v) when is_list(v), do: Enum.map(v, &sanitize_value/1)
  defp sanitize_value(v), do: v

  # Truncate long URLs for logging
  defp truncate_url(nil), do: nil
  defp truncate_url(url) when is_binary(url) do
    if String.length(url) > 80 do
      String.slice(url, 0, 77) <> "..."
    else
      url
    end
  end

  @doc """
  Get the list of currently enabled sources.

  Useful for monitoring and debugging.
  """
  @spec enabled_sources() :: [String.t()]
  def enabled_sources, do: @enabled_sources

  @doc """
  Get image caching statistics for enabled sources.

  Returns counts of cached, pending, and failed images per source.
  """
  @spec stats() :: map()
  def stats do
    # Get overall stats from ImageCacheService
    overall = ImageCacheService.stats()

    %{
      overall: overall,
      enabled_sources: @enabled_sources,
      high_priority_sources: @high_priority_sources
    }
  end
end
