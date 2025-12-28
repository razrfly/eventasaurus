defmodule EventasaurusApp.Images.ComputeImageCacheStatsJob do
  @moduledoc """
  Oban worker for computing image cache stats in the background.

  This job runs daily at 6 AM UTC and computes all stats for the image cache
  dashboard, storing the results in the image_cache_stats_snapshots table.

  The dashboard reads from the latest snapshot instead of computing stats
  on-demand, which avoids connection pool pressure and provides instant loading.

  ## Manual Trigger

      EventasaurusApp.Images.ComputeImageCacheStatsJob.trigger_now()

  """

  use Oban.Worker,
    queue: :reports,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :scheduled, :executing]]

  require Logger

  alias EventasaurusApp.Images.{ImageCacheStats, ImageCacheStatsSnapshot}

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt}) do
    if attempt > 1 do
      Logger.info("🔄 Image cache stats computation retry attempt #{attempt}/3")
    end

    Logger.info("📊 Starting image cache stats computation...")
    start_time = System.monotonic_time(:millisecond)

    try do
      stats = ImageCacheStats.get_dashboard_stats()
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # Store the snapshot
      case ImageCacheStatsSnapshot.insert(%{
             stats_data: stats,
             computed_at: DateTime.utc_now(),
             computation_time_ms: duration_ms,
             status: "completed"
           }) do
        {:ok, snapshot} ->
          # Cleanup old snapshots (keep last 5)
          ImageCacheStatsSnapshot.cleanup(5)

          Logger.info(
            "✅ Image cache stats computation completed in #{duration_ms}ms (snapshot ##{snapshot.id})"
          )

          :ok

        {:error, changeset} ->
          Logger.error("❌ Failed to save image cache stats snapshot: #{inspect(changeset.errors)}")
          {:error, "Failed to save snapshot"}
      end
    rescue
      e ->
        Logger.error("❌ Image cache stats computation failed: #{Exception.message(e)}")
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Manually trigger stats computation (for admin refresh button).
  Returns {:ok, job} or {:error, reason}.
  """
  def trigger_now do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
