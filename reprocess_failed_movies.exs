# Reprocess discarded TMDB matching jobs after threshold improvements
# Run with: mix run reprocess_failed_movies.exs

alias EventasaurusApp.Repo
import Ecto.Query

IO.puts("\n=== Reprocessing Discarded Movie Matching Jobs ===\n")

# Get all discarded MovieDetailJob jobs
discarded_jobs =
  from(j in Oban.Job,
    where: j.worker == "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob",
    where: j.state == "discarded",
    select: j
  )
  |> Repo.all()

total = length(discarded_jobs)
IO.puts("Found #{total} discarded jobs to reprocess\n")

if total == 0 do
  IO.puts("No jobs to reprocess!")
  System.halt(0)
end

IO.puts("This will:")
IO.puts("  1. Transition jobs from 'discarded' → 'available'")
IO.puts("  2. Reset attempt counter to 0")
IO.puts("  3. Jobs will be picked up by Oban workers automatically")
IO.puts("")

# Prompt for confirmation
IO.write("Continue? (y/n): ")
response = IO.gets("") |> String.trim() |> String.downcase()

if response != "y" do
  IO.puts("\nAborted.")
  System.halt(0)
end

IO.puts("\nReprocessing jobs...")

{updated_count, _} =
  from(j in Oban.Job,
    where: j.worker == "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob",
    where: j.state == "discarded"
  )
  |> Repo.update_all(
    set: [
      state: "available",
      attempt: 0,
      max_attempts: 3,
      scheduled_at: DateTime.utc_now(),
      errors: []
    ]
  )

IO.puts("✅ Transitioned #{updated_count} jobs to 'available' state")
IO.puts("\nJobs will be processed by Oban workers automatically.")
IO.puts("Monitor progress in:")
IO.puts("  - Logs: tail -f log/dev.log | grep 'TMDB'")
IO.puts("  - Oban Dashboard: http://localhost:4000/admin/oban")
IO.puts("")
