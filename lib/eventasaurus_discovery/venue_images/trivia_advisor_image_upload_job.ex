defmodule EventasaurusDiscovery.VenueImages.TriviaAdvisorImageUploadJob do
  @moduledoc """
  Processes individual venue images from Trivia Advisor (child job).

  Spawned by TriviaAdvisorBackfillJob orchestrator. Each job processes one venue
  and adapts behavior based on ImageKit configuration.

  ## Modes

  **Development Mode (ImageKit disabled):**
  - Stores Tigris S3 URLs directly in venue_images
  - No external API calls
  - Fast processing with immediate results

  **Production Mode (ImageKit enabled):**
  - Downloads images from Tigris S3
  - Uploads to ImageKit with Google Places naming
  - Rate limiting: 500ms delay between uploads
  - Updates venue with ImageKit URLs

  ## Architecture

  Following the orchestrator pattern (like BackfillOrchestratorJob → EnrichmentJob):
  ```
  TriviaAdvisorBackfillJob (orchestrator)
    └─ Spawns TriviaAdvisorImageUploadJob for each matched venue
        ├─ Development: Store Tigris URLs
        └─ Production: Download → Upload → Store ImageKit URLs
  ```

  ## Usage

      # Spawned by orchestrator with match data
      TriviaAdvisorImageUploadJob.enqueue(
        venue_id: 123,
        venue_slug: "three-johns-angel",
        trivia_advisor_images: [
          %{"local_path" => "/uploads/google_place_images/three-johns-angel/original_google_place_1.jpg"},
          ...
        ]
      )

  ## Queue Configuration

  Uses `venue_enrichment` queue with concurrency: 1 to prevent rate limit issues.
  Combined with 500ms delays = guaranteed max 2 req/sec to ImageKit.
  """

  use Oban.Worker,
    queue: :venue_enrichment,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias Eventasaurus.ImageKit.{Uploader, Filename}

  @tigris_base_url "https://cdn.quizadvisor.com"
  @upload_delay_ms 500

  @doc """
  Enqueues an image upload job for a single venue.

  ## Parameters

  - `:venue_id` - Eventasaurus venue ID (required)
  - `:venue_slug` - Venue slug for ImageKit folder structure (required)
  - `:trivia_advisor_images` - List of image maps from Trivia Advisor (required)
  - `:match_tier` - Match quality tier for logging (optional)
  - `:confidence` - Match confidence score for logging (optional)

  ## Examples

      TriviaAdvisorImageUploadJob.enqueue(
        venue_id: 123,
        venue_slug: "three-johns-angel",
        trivia_advisor_images: [
          %{"local_path" => "/uploads/google_place_images/..."}
        ],
        match_tier: "slug_geo",
        confidence: 1.0
      )
  """
  def enqueue(args) when is_list(args) do
    venue_id = Keyword.get(args, :venue_id)
    venue_slug = Keyword.get(args, :venue_slug)
    trivia_advisor_images = Keyword.get(args, :trivia_advisor_images)

    unless venue_id && venue_slug && trivia_advisor_images do
      raise ArgumentError,
            "venue_id, venue_slug, and trivia_advisor_images are required"
    end

    # Convert to string keys for Oban
    args_map =
      args
      |> Enum.into(%{})
      |> convert_keys_to_strings()

    args_map
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    venue_id = Map.get(args, "venue_id")
    venue_slug = Map.get(args, "venue_slug")
    trivia_advisor_images = Map.get(args, "trivia_advisor_images", [])
    match_tier = Map.get(args, "match_tier")
    confidence = Map.get(args, "confidence")

    # Detect mode based on ImageKit configuration
    imagekit_config = Application.get_env(:eventasaurus, :imagekit, [])
    imagekit_enabled = Keyword.get(imagekit_config, :enabled, false)

    mode = if imagekit_enabled, do: "production", else: "development"

    Logger.info("""
    📸 Processing Trivia Advisor images for venue #{venue_id} (#{mode} mode):
       - Slug: #{venue_slug}
       - Images: #{length(trivia_advisor_images)}
       - Match tier: #{match_tier}
       - Confidence: #{if confidence, do: Float.round(confidence * 100, 1), else: "N/A"}%
    """)

    case process_venue_images(venue_id, venue_slug, trivia_advisor_images, mode) do
      {:ok, results} ->
        results_with_match = Map.merge(results, %{
          match_tier: match_tier,
          confidence: confidence,
          mode: mode
        })

        Logger.info("""
        ✅ Venue #{venue_id} completed (#{mode} mode):
           - Images processed: #{results.images_added}
           - Images failed: #{Map.get(results, :images_failed, 0)}
        """)

        store_success_meta(job, results_with_match, venue_id, venue_slug)
        :ok

      {:error, reason} ->
        Logger.error("❌ Failed to process venue #{venue_id}: #{inspect(reason)}")

        store_failure_meta(job, %{
          status: "failed",
          error: inspect(reason),
          venue_id: venue_id,
          venue_slug: venue_slug,
          match_tier: match_tier,
          confidence: confidence,
          mode: mode
        })

        {:error, reason}
    end
  end

  # Private Functions

  defp process_venue_images(venue_id, venue_slug, trivia_advisor_images, "development") do
    # Development mode: Store Tigris URLs directly (no ImageKit upload)
    Logger.info("🔧 Development mode: Storing Tigris URLs directly")

    venue = Repo.get(Venue, venue_id)

    unless venue do
      {:error, :venue_not_found}
    else
      current_images = venue.venue_images || []

      # Transform Tigris images to venue_images format
      # Filter out images without original_url (required for deduplication)
      new_images =
        trivia_advisor_images
        |> Enum.filter(fn ta_image ->
          if ta_image["original_url"] do
            true
          else
            Logger.warning("⚠️  Skipping image without original_url: #{ta_image["local_path"]}")
            false
          end
        end)
        |> Enum.map(fn ta_image ->
          local_path = ta_image["local_path"]
          tigris_url = "#{@tigris_base_url}#{local_path}"

          %{
            "url" => tigris_url,
            "provider_url" => ta_image["original_url"],
            "upload_status" => "external",
            "width" => ta_image["width"],
            "height" => ta_image["height"],
            "source" => "trivia_advisor_migration",
            "fetched_at" => ta_image["fetched_at"],
            "migrated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        end)

      # Merge with existing images (avoid duplicates)
      merged_images = merge_images(current_images, new_images)

      Logger.info("  Images before: #{length(current_images)}, after: #{length(merged_images)}")

      # Update venue
      case Repo.update(Ecto.Changeset.change(venue, venue_images: merged_images)) do
        {:ok, _updated_venue} ->
          {:ok,
           %{
             venue_id: venue_id,
             venue_slug: venue_slug,
             images_added: length(new_images),
             images_failed: 0,
             tigris_urls: Enum.map(new_images, & &1["url"])
           }}

        {:error, changeset} ->
          {:error, {:db_update_failed, changeset.errors}}
      end
    end
  end

  defp process_venue_images(venue_id, venue_slug, trivia_advisor_images, "production") do
    # Production mode: Download from Tigris and upload to ImageKit
    Logger.info("📦 Production mode: Uploading to ImageKit")
    upload_to_imagekit(venue_id, venue_slug, trivia_advisor_images)
  end

  defp upload_to_imagekit(venue_id, venue_slug, trivia_advisor_images) do
    # Load venue
    venue = Repo.get(Venue, venue_id)

    unless venue do
      {:error, :venue_not_found}
    else
      # Get current images
      current_images = venue.venue_images || []

      Logger.info("Current venue images: #{length(current_images)}")

      # Filter out images without original_url (required for deduplication)
      valid_images =
        Enum.filter(trivia_advisor_images, fn ta_image ->
          if ta_image["original_url"] do
            true
          else
            Logger.warning("⚠️  Skipping upload for image without original_url: #{ta_image["local_path"]}")
            false
          end
        end)

      # Upload each valid image to ImageKit
      upload_results =
        valid_images
        |> Enum.with_index(1)
        |> Enum.map(fn {ta_image, position} ->
          upload_single_image(venue_slug, ta_image, position)
        end)

      # Calculate statistics
      successful_uploads =
        Enum.filter(upload_results, fn r -> r.success end)

      failed_uploads =
        Enum.filter(upload_results, fn r -> !r.success end)

      # Build new image entries for successful uploads
      new_images =
        successful_uploads
        |> Enum.map(fn result ->
          %{
            "url" => result.imagekit_url,
            "provider_url" => result.original_url,
            "width" => nil,
            "height" => nil,
            "source" => "trivia_advisor_migration",
            "upload_status" => "uploaded",
            "fetched_at" => result.fetched_at,
            "migrated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "original_tigris_url" => result.tigris_url
          }
        end)

      # Merge with existing images (avoid duplicates)
      merged_images = merge_images(current_images, new_images)

      Logger.info("After merge: #{length(merged_images)} total images")

      # Update venue
      case Repo.update(Ecto.Changeset.change(venue, venue_images: merged_images)) do
        {:ok, _updated_venue} ->
          Logger.info("✓ Updated venue #{venue_id} successfully")

          {:ok,
           %{
             venue_id: venue_id,
             venue_slug: venue_slug,
             images_added: length(successful_uploads),
             images_failed: length(failed_uploads),
             failed_uploads: Enum.map(failed_uploads, & &1.error),
             imagekit_urls: Enum.map(successful_uploads, & &1.imagekit_url)
           }}

        {:error, changeset} ->
          Logger.error("✗ Update failed: #{inspect(changeset.errors)}")
          {:error, {:db_update_failed, changeset.errors}}
      end
    end
  end

  defp upload_single_image(venue_slug, ta_image, position) do
    local_path = ta_image["local_path"]
    tigris_url = "#{@tigris_base_url}#{local_path}"
    original_url = ta_image["original_url"]
    fetched_at = ta_image["fetched_at"]

    Logger.info("  [#{position}] Uploading from: #{tigris_url}")

    # Upload to ImageKit with hash-based Google Places naming convention
    folder = "/venues/#{venue_slug}"
    filename = Filename.generate(original_url, "google_places")

    case Uploader.upload_from_url(tigris_url,
           folder: folder,
           filename: filename,
           tags: ["trivia_advisor_migration", "google_places"]
         ) do
      {:ok, imagekit_url} ->
        Logger.info("  [#{position}] ✓ Uploaded: #{imagekit_url}")

        # Add delay to respect rate limits (except for last image)
        Process.sleep(@upload_delay_ms)

        %{
          success: true,
          position: position,
          tigris_url: tigris_url,
          imagekit_url: imagekit_url,
          original_url: original_url,
          fetched_at: fetched_at,
          error: nil
        }

      {:error, reason} ->
        Logger.error("  [#{position}] ✗ Upload failed: #{inspect(reason)}")

        %{
          success: false,
          position: position,
          tigris_url: tigris_url,
          imagekit_url: nil,
          original_url: original_url,
          fetched_at: fetched_at,
          error: inspect(reason)
        }
    end
  end

  defp merge_images(original_images, new_images) do
    # Deduplicate by URL (both against existing and within new batch)
    initial_urls = MapSet.new(original_images, fn img -> img["url"] end)

    {unique_new_images, _} =
      Enum.reduce(new_images, {[], initial_urls}, fn img, {acc, urls} ->
        url = img["url"]

        if MapSet.member?(urls, url) do
          # Skip duplicate (already seen in original_images or earlier in new_images)
          {acc, urls}
        else
          # Add this image and mark URL as seen
          {[img | acc], MapSet.put(urls, url)}
        end
      end)

    original_images ++ Enum.reverse(unique_new_images)
  end

  defp store_success_meta(job, results, venue_id, venue_slug) do
    # Determine status based on results
    status =
      cond do
        Map.get(results, :images_failed, 0) == 0 && results.images_added > 0 -> "success"
        results.images_added > 0 -> "partial"
        true -> "no_images"
      end

    # Build comprehensive metadata (following EnrichmentJob pattern)
    meta = %{
      "status" => status,
      "mode" => results.mode,
      "venue_id" => venue_id,
      "venue_slug" => venue_slug,
      "images_added" => results.images_added,
      "images_failed" => Map.get(results, :images_failed, 0),
      "match_tier" => results.match_tier,
      "confidence" => results.confidence,
      "processed_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
    }

    # Add mode-specific details
    meta =
      case results.mode do
        "development" ->
          Map.put(meta, "tigris_urls", Map.get(results, :tigris_urls, []))

        "production" ->
          meta
          |> Map.put("imagekit_urls", Map.get(results, :imagekit_urls, []))
          |> Map.put("failed_uploads", Map.get(results, :failed_uploads, []))

        _ ->
          meta
      end

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _} ->
        Logger.debug("✅ Stored results in Oban meta for job #{job.id}")

      {:error, reason} ->
        Logger.error("❌ Failed to store results in Oban meta: #{inspect(reason)}")
    end
  end

  defp store_failure_meta(job, meta_data) do
    meta =
      meta_data
      |> Map.put("processed_at", NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601())

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _} ->
        Logger.debug("✅ Stored failure info in Oban meta for job #{job.id}")

      {:error, reason} ->
        Logger.error("❌ Failed to store failure info in Oban meta: #{inspect(reason)}")
    end
  end

  defp convert_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
