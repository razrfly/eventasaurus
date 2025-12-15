# Trigger Geeks Who Drink IndexJob - Phase 4 (Time Extraction Fix)
# This will re-index all venues and schedule VenueDetailJobs with correct parameters
#
# Run with: mix run trigger_geeks_index_phase4.exs

alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.IndexJob

# Get source_id for Geeks Who Drink
source_id = 6

IO.puts("Scheduling Geeks Who Drink IndexJob...")

# Schedule the IndexJob with force=true to process all venues (not just stale ones)
job = %{
  "source_id" => source_id,
  "force" => true
}
|> IndexJob.new()
|> Oban.insert!()

IO.puts("✅ IndexJob scheduled with ID: #{job.id}")
IO.puts("This will re-index all Geeks Who Drink venues and schedule detail jobs.")
IO.puts("Monitor progress with:")
IO.puts("  SELECT count(*) FROM oban_jobs WHERE worker = 'Elixir.EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.VenueDetailJob' AND state = 'completed';")
