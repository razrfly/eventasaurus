#!/usr/bin/env elixir
# Script to clean up legacy Oban jobs with corrupted UTF-8 data
# Run with: mix run cleanup_legacy_jobs.exs

require Logger
import Ecto.Query
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Utils.UTF8

# Start the application so Repo/Oban/etc. are available
Mix.Task.run("app.start")

IO.puts("\n=== Cleaning Up Legacy Oban Jobs with UTF-8 Corruption ===\n")

# Find all retryable/scheduled jobs in relevant queues
jobs_query =
  from(j in Oban.Job,
    where: j.state in ["retryable", "scheduled", "available"],
    where: j.queue in ["scraper_detail", "discovery"],
    where:
      j.worker in [
        "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob",
        "EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob"
      ],
    order_by: [asc: j.id]
  )

jobs = Repo.all(jobs_query)

IO.puts("Found #{length(jobs)} jobs to check for UTF-8 corruption\n")

# Track statistics
stats = %{
  total: length(jobs),
  corrupted: 0,
  cleaned: 0,
  failed: 0,
  cancelled: 0
}

# Process each job
updated_stats =
  Enum.reduce(jobs, stats, fn job, acc ->
    # Check if job has UTF-8 corruption
    has_corruption =
      try do
        # Try to encode to JSON - this will fail if there's invalid UTF-8
        Jason.encode!(job.args)
        false
      rescue
        _ -> true
      end

    if has_corruption do
      IO.puts("Job #{job.id} (#{job.worker}):")
      IO.puts("  State: #{job.state}, Attempts: #{job.attempt}/#{job.max_attempts}")

      # Try to clean the args
      try do
        clean_args = UTF8.validate_map_strings(job.args)

        # Verify cleaning worked
        Jason.encode!(clean_args)

        # Cancel the old job and create a new one with clean data
        {:ok, _} = Oban.cancel_job(job.id)

        # Create new job with cleaned args
        new_job =
          case job.worker do
            "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob" ->
              EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob.new(
                clean_args,
                queue: job.queue,
                max_attempts: job.max_attempts
              )

            "EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob" ->
              EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob.new(
                clean_args,
                queue: job.queue,
                max_attempts: job.max_attempts
              )
          end

        case Oban.insert(new_job) do
          {:ok, new} ->
            IO.puts("  ✅ Cancelled corrupted job #{job.id}, created clean job #{new.id}")
            Map.update!(acc, :cleaned, &(&1 + 1))

          {:error, reason} ->
            IO.puts("  ❌ Failed to create replacement job: #{inspect(reason)}")
            Map.update!(acc, :failed, &(&1 + 1))
        end
      rescue
        e ->
          # If we can't clean it, just cancel it
          IO.puts("  ⚠️  Cannot clean job args: #{inspect(e)}")
          {:ok, _} = Oban.cancel_job(job.id)
          IO.puts("  🚫 Cancelled uncleanable job #{job.id}")
          Map.update!(acc, :cancelled, &(&1 + 1))
      end
      |> Map.update!(:corrupted, &(&1 + 1))
    else
      acc
    end
  end)

# Print summary
IO.puts("\n=== Cleanup Summary ===")
IO.puts("Total jobs checked: #{updated_stats.total}")
IO.puts("Jobs with corruption: #{updated_stats.corrupted}")
IO.puts("Jobs cleaned and re-queued: #{updated_stats.cleaned}")
IO.puts("Jobs cancelled (uncleanable): #{updated_stats.cancelled}")
IO.puts("Failed to process: #{updated_stats.failed}")

if updated_stats.corrupted > 0 do
  IO.puts("\n✅ Cleanup complete. Re-queued jobs will be processed with UTF-8 protection.")
else
  IO.puts("\n✅ No corrupted jobs found. All jobs are clean.")
end
