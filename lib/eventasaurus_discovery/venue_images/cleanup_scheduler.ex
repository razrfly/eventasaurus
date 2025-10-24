defmodule EventasaurusDiscovery.VenueImages.CleanupScheduler do
  @moduledoc """
  Nightly scheduled worker that identifies venues with failed uploads
  and queues retry jobs for transient failures.

  Runs daily at 4 AM UTC via Oban cron (configured in config/config.exs).

  ## Responsibilities
  - Scan all venues with failed uploads
  - Classify failures as transient vs permanent
  - Queue retry jobs for high-priority venues with transient failures
  - Log stats about permanent failures for monitoring

  ## Scheduling
  Add to Oban config:
  ```elixir
  {Oban.Plugins.Cron,
   crontab: [
     # ... existing jobs
     {"0 4 * * *", EventasaurusDiscovery.VenueImages.CleanupScheduler}
   ]}
  ```
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.VenueImages.{Stats, FailedUploadRetryWorker}

  @doc """
  Enqueues the cleanup job manually (for testing).
  """
  def enqueue do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🧹 Starting nightly venue image cleanup scan")

    start_time = System.monotonic_time(:millisecond)

    # Get all venues with failures
    venues_with_failures = Stats.venues_with_failures()

    if Enum.empty?(venues_with_failures) do
      Logger.info("✅ No venues with failed uploads found")
      {:ok, "No failures to process"}
    else
      Logger.info("📊 Found #{length(venues_with_failures)} venues with failed uploads")

      # Process each venue and collect stats
      stats =
        venues_with_failures
        |> Enum.map(&process_venue/1)
        |> Enum.reduce(
          %{
            transient_queued: 0,
            permanent_logged: 0,
            ambiguous_skipped: 0,
            errors: 0
          },
          fn result, acc ->
            Map.merge(acc, result, fn _k, v1, v2 -> v1 + v2 end)
          end
        )

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      Logger.info("""
      ✅ Cleanup scan complete (#{elapsed_ms}ms):
         - Retry jobs queued: #{stats.transient_queued}
         - Permanent failures logged: #{stats.permanent_logged}
         - Ambiguous failures skipped: #{stats.ambiguous_skipped}
         - Errors: #{stats.errors}
      """)

      {:ok, stats}
    end
  end

  # Process a single venue and queue retry if needed
  defp process_venue(venue_summary) do
    try do
      venue = Repo.get(Venue, venue_summary.id)

      if is_nil(venue) do
        Logger.warning("⚠️  Venue #{venue_summary.id} not found, skipping")
        %{errors: 1}
      else
        classify_and_queue(venue, venue_summary)
      end
    rescue
      error ->
        Logger.error("❌ Error processing venue #{venue_summary.id}: #{inspect(error)}")
        %{errors: 1}
    end
  end

  # Classify venue failures and queue retry if appropriate
  defp classify_and_queue(venue, _venue_summary) do
    failed_images =
      (venue.venue_images || [])
      |> Enum.filter(fn img -> img["upload_status"] == "failed" end)

    # Classify each failed image
    classifications =
      failed_images
      |> Enum.map(fn img ->
        error_type = get_in(img, ["error_details", "error_type"])
        Stats.classify_error_type(error_type)
      end)
      |> Enum.frequencies()

    transient_count = classifications[:transient] || 0
    permanent_count = classifications[:permanent] || 0
    ambiguous_count = classifications[:ambiguous] || 0

    cond do
      transient_count > 0 ->
        # Has retryable failures, queue retry job
        case FailedUploadRetryWorker.enqueue_venue(venue.id) do
          {:ok, _job} ->
            Logger.info(
              "✅ Queued retry for venue #{venue.id} (#{transient_count} transient failures)"
            )

            %{transient_queued: 1}

          {:error, reason} ->
            Logger.error(
              "❌ Failed to queue retry for venue #{venue.id}: #{inspect(reason)}"
            )

            %{errors: 1}
        end

      permanent_count > 0 ->
        # Only permanent failures, log for monitoring
        Logger.info(
          "ℹ️  Venue #{venue.id} has #{permanent_count} permanent failures (not retrying)"
        )

        %{permanent_logged: 1}

      ambiguous_count > 0 ->
        # Only ambiguous failures, skip for now
        Logger.debug(
          "⏭️  Venue #{venue.id} has #{ambiguous_count} ambiguous failures (skipping)"
        )

        %{ambiguous_skipped: 1}

      true ->
        # No failures (shouldn't happen)
        %{}
    end
  end
end
