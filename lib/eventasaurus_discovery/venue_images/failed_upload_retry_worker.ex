defmodule EventasaurusDiscovery.VenueImages.FailedUploadRetryWorker do
  @moduledoc """
  Oban worker for retrying failed venue image uploads.

  Retries ONLY transient failures (rate limiting, network issues) without
  calling provider APIs. Uses existing provider_url from failed upload records.

  ## Features
  - Retries transient errors only (rate_limited, service_unavailable, network_timeout)
  - Skips permanent errors (not_found, forbidden, auth_error)
  - Respects rate limits with delays between uploads
  - Tracks retry attempts to prevent infinite loops
  - Updates venue_images in place with results

  ## Usage

      # Queue retry for specific venue
      FailedUploadRetryWorker.enqueue_venue(venue_id)

      # Perform immediately (for testing)
      FailedUploadRetryWorker.perform_now(venue)
  """

  use Oban.Worker,
    queue: :venue_enrichment,
    max_attempts: 3

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue

  # Error types that are worth retrying
  @transient_errors [
    "rate_limited",
    "service_unavailable",
    "network_timeout",
    "gateway_timeout",
    "bad_gateway"
  ]

  # Maximum retry attempts per image
  @max_image_retries 3

  @doc """
  Enqueues a retry job for a specific venue.
  """
  def enqueue_venue(venue_id) when is_integer(venue_id) do
    %{venue_id: venue_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Performs retry immediately (for testing/debugging).
  """
  def perform_now(venue) do
    perform(%Oban.Job{args: %{"venue_id" => venue.id}})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id}}) do
    venue = Repo.get!(Venue, venue_id)

    Logger.info("🔄 Starting failed upload retry for venue #{venue.id} (#{venue.name})")

    # Classify failed images by error type
    {retryable, non_retryable} = classify_failed_images(venue)

    if Enum.empty?(retryable) do
      Logger.info(
        "✅ No retryable failures for venue #{venue.id} (#{length(non_retryable)} permanent)"
      )

      {:ok, "No retryable failures"}
    else
      Logger.info(
        "🔄 Found #{length(retryable)} retryable failures, #{length(non_retryable)} permanent"
      )

      # Retry each failed upload with delays
      retry_results = retry_failed_uploads(venue, retryable)

      # Update venue_images with results
      update_venue_images(venue, retry_results, non_retryable)
    end
  end

  # Classify failed images into retryable and non-retryable
  defp classify_failed_images(venue) do
    failed_images =
      (venue.venue_images || [])
      |> Enum.filter(fn img -> img["upload_status"] == "failed" end)

    Enum.split_with(failed_images, fn img ->
      error_type = get_in(img, ["error_details", "error_type"])
      retry_count = img["retry_count"] || 0

      # Retryable if:
      # 1. Error type is transient
      # 2. Haven't exceeded max retries
      error_type in @transient_errors && retry_count < @max_image_retries
    end)
  end

  # Retry failed uploads with rate limiting delays
  defp retry_failed_uploads(venue, failed_images) do
    failed_images
    |> Enum.with_index()
    |> Enum.map(fn {img, index} ->
      provider = img["provider"]

      # Add delay between uploads to respect rate limits
      if index > 0 do
        delay_ms = calculate_upload_delay(provider, index)
        Logger.debug("⏱️  Rate limit delay: #{delay_ms}ms before retry #{index + 1}")
        Process.sleep(delay_ms)
      end

      retry_single_upload(venue, img)
    end)
  end

  # Retry a single failed upload
  defp retry_single_upload(venue, failed_img) do
    provider = failed_img["provider"]
    provider_url = failed_img["provider_url"]
    retry_count = (failed_img["retry_count"] || 0) + 1

    Logger.info("🔄 Retrying upload attempt #{retry_count} for #{provider}: #{String.slice(provider_url || "", 0..80)}")

    # Use existing upload_to_imagekit logic from orchestrator
    upload_result = upload_to_imagekit(venue, provider_url, provider)

    case upload_result do
      {:ok, imagekit_url, imagekit_path} ->
        Logger.info("✅ Retry successful: #{imagekit_url}")

        # Update image with success
        failed_img
        |> Map.merge(%{
          "url" => imagekit_url,
          "imagekit_path" => imagekit_path,
          "upload_status" => "uploaded",
          "retry_count" => retry_count,
          "retried_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })
        |> Map.delete("error_details")

      {:error, reason} ->
        Logger.warning("⚠️  Retry failed (attempt #{retry_count}): #{inspect(reason)}")

        # Classify new error
        error_type = classify_error(reason)

        status_code =
          case reason do
            {:download_failed, {:http_status, code}} -> code
            {:http_error, code, _body} -> code
            _ -> nil
          end

        error_detail = %{
          "error" => inspect(reason),
          "error_type" => Atom.to_string(error_type),
          "status_code" => status_code,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "retry_attempt" => retry_count
        }

        # Update image with failure info
        failed_img
        |> Map.merge(%{
          "upload_status" => if(retry_count >= @max_image_retries, do: "permanently_failed", else: "failed"),
          "retry_count" => retry_count,
          "error_details" => error_detail
        })
    end
  end

  # Upload image to ImageKit (copied from orchestrator.ex logic)
  defp upload_to_imagekit(venue, provider_url, provider) do
    alias Eventasaurus.ImageKit.{Uploader, Filename}

    # Generate deterministic filename using hash
    filename = Filename.generate(provider_url, provider)

    # Determine folder based on venue slug or ID
    folder =
      if venue.slug do
        "/venues/#{venue.slug}"
      else
        "/venues/venue-#{venue.id}"
      end

    # Upload with retry logic (handles 429, 503, timeouts)
    case Uploader.upload_from_url(provider_url, folder: folder, filename: filename) do
      {:ok, imagekit_url} ->
        imagekit_path = "#{folder}/#{filename}"
        {:ok, imagekit_url, imagekit_path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Calculate provider-specific upload delay
  defp calculate_upload_delay(provider, _index) do
    case provider do
      # Google Places: 2 requests/second = 500ms delay
      "google_places" -> 500
      # Foursquare: 5 requests/second = 200ms delay
      "foursquare" -> 200
      # Here: 5 requests/second = 200ms delay
      "here" -> 200
      # Default: 100ms for unknown providers
      _ -> 100
    end
  end

  # Classify error type (copied from orchestrator.ex)
  defp classify_error({:download_failed, {:http_status, status_code}}) do
    case status_code do
      429 -> :rate_limited
      401 -> :auth_error
      403 -> :forbidden
      404 -> :not_found
      500 -> :server_error
      502 -> :bad_gateway
      503 -> :service_unavailable
      504 -> :gateway_timeout
      _ -> :http_error
    end
  end

  defp classify_error({:http_error, _status, _body}), do: :http_error

  defp classify_error({:error, %Mint.TransportError{reason: :timeout}}), do: :network_timeout

  defp classify_error({:error, %Mint.TransportError{}}), do: :network_error

  defp classify_error(:file_too_large), do: :file_too_large

  defp classify_error({:download_failed, _}), do: :download_failed

  defp classify_error(_), do: :unknown_error

  # Update venue with retry results
  defp update_venue_images(venue, retry_results, non_retryable_failures) do
    # Get successful uploads (unchanged)
    successful_uploads =
      (venue.venue_images || [])
      |> Enum.filter(fn img -> img["upload_status"] == "uploaded" end)

    # Merge all images
    all_images = successful_uploads ++ retry_results ++ non_retryable_failures

    # Sort by quality score
    sorted_images =
      all_images
      |> Enum.sort_by(fn img -> -(img["quality_score"] || 0.0) end)

    # Count results
    newly_uploaded = Enum.count(retry_results, fn img -> img["upload_status"] == "uploaded" end)
    still_failed = Enum.count(retry_results, fn img -> img["upload_status"] != "uploaded" end)

    # Update venue
    changeset = Venue.update_venue_images(venue, sorted_images, venue.image_enrichment_metadata)

    case Repo.update(changeset) do
      {:ok, updated_venue} ->
        Logger.info(
          "✅ Retry complete for venue #{venue.id}: #{newly_uploaded} newly uploaded, #{still_failed} still failed"
        )

        {:ok, updated_venue}

      {:error, changeset} ->
        Logger.error("❌ Failed to update venue #{venue.id}: #{inspect(changeset.errors)}")
        {:error, :update_failed}
    end
  end
end
