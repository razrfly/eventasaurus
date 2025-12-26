defmodule EventasaurusApp.Workers.ImageCacheJob do
  @moduledoc """
  Oban worker that downloads external images and uploads them to R2 storage.

  This worker is the core of the image caching infrastructure. It:
  1. Downloads images from external URLs
  2. Uploads them to Cloudflare R2
  3. Updates the CachedImage record with the result

  ## Process Flow

  1. Receives `cached_image_id` as job argument
  2. Loads the CachedImage record
  3. Downloads from `original_url`
  4. Uploads to R2 with path: `images/{entity_type}/{entity_id}/{role}.{ext}`
  5. Updates record with `cdn_url`, `status`, metadata

  ## Error Handling

  - HTTP 403/401: Likely hotlink protection, retry won't help
  - HTTP 404: Image no longer exists
  - HTTP 5xx: Server error, will retry
  - Timeout: Network issue, will retry
  - File too large: Permanent failure

  ## Retry Strategy

  - max_attempts: 3
  - Exponential backoff for transient errors
  - Permanent failures don't retry

  ## Queue Configuration

  Uses the `image_cache` queue which should be configured with:
  - Moderate concurrency (5-10) to avoid hammering external servers
  - Rate limiting if needed for specific sources
  """

  use Oban.Worker, queue: :image_cache, max_attempts: 3

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Images.CachedImage
  alias EventasaurusApp.Services.R2Client

  require Logger

  @permanent_failures [:file_too_large, {:http_error, 404}, {:http_error, 401}]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"cached_image_id" => cached_image_id}}) do
    Logger.info("📸 ImageCacheJob: Starting cache for cached_image_id=#{cached_image_id}")

    case Repo.get(CachedImage, cached_image_id) do
      nil ->
        Logger.error("CachedImage not found: #{cached_image_id}")
        {:error, :not_found}

      cached_image ->
        process_image(cached_image)
    end
  end

  defp process_image(%CachedImage{} = cached_image) do
    # Mark as downloading
    cached_image
    |> CachedImage.cache_result_changeset(%{status: "downloading"})
    |> Repo.update()

    r2_path = build_r2_path(cached_image)

    case R2Client.download_and_upload(cached_image.original_url, r2_path) do
      {:ok, result} ->
        handle_success(cached_image, result)

      {:error, reason} ->
        handle_failure(cached_image, reason)
    end
  end

  defp handle_success(cached_image, result) do
    Logger.info(
      "✅ ImageCacheJob: Successfully cached #{cached_image.entity_type}/#{cached_image.entity_id}/#{cached_image.image_role}"
    )

    attrs = %{
      status: "cached",
      r2_key: result.r2_key,
      cdn_url: result.cdn_url,
      content_type: result.content_type,
      file_size: result.file_size,
      cached_at: DateTime.utc_now(),
      last_error: nil
    }

    cached_image
    |> CachedImage.cache_result_changeset(attrs)
    |> Repo.update()

    :ok
  end

  defp handle_failure(cached_image, reason) do
    error_message = format_error(reason)

    Logger.warning(
      "❌ ImageCacheJob: Failed to cache #{cached_image.entity_type}/#{cached_image.entity_id}/#{cached_image.image_role}: #{error_message}"
    )

    attrs = %{
      status: "failed",
      retry_count: cached_image.retry_count + 1,
      last_error: error_message
    }

    cached_image
    |> CachedImage.cache_result_changeset(attrs)
    |> Repo.update()

    # Determine if this is a permanent failure
    if permanent_failure?(reason) do
      Logger.info("📸 ImageCacheJob: Permanent failure, not retrying")
      # Return :ok to prevent Oban from retrying
      :ok
    else
      # Return error to trigger Oban retry
      {:error, reason}
    end
  end

  defp build_r2_path(%CachedImage{} = cached_image) do
    extension = get_extension(cached_image.original_url)

    "images/#{cached_image.entity_type}/#{cached_image.entity_id}/#{cached_image.image_role}#{extension}"
  end

  defp get_extension(url) do
    uri = URI.parse(url)
    path = uri.path || ""

    cond do
      String.ends_with?(path, ".jpg") or String.ends_with?(path, ".jpeg") -> ".jpg"
      String.ends_with?(path, ".png") -> ".png"
      String.ends_with?(path, ".gif") -> ".gif"
      String.ends_with?(path, ".webp") -> ".webp"
      String.ends_with?(path, ".avif") -> ".avif"
      # Default to jpg if unknown
      true -> ".jpg"
    end
  end

  defp format_error({:http_error, status}), do: "HTTP #{status}"
  defp format_error({:download_failed, reason}), do: "Download failed: #{inspect(reason)}"
  defp format_error(:file_too_large), do: "File too large (>10MB)"
  defp format_error({:not_configured, msg}), do: "R2 not configured: #{msg}"
  defp format_error(reason), do: inspect(reason)

  defp permanent_failure?(reason) do
    reason in @permanent_failures or
      match?({:http_error, 403}, reason) or
      match?({:not_configured, _}, reason)
  end
end
