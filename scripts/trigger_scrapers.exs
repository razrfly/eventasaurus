#!/usr/bin/env elixir

# Script to trigger Cinema City and Kino Krakow scrapers to generate execution data

alias EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob, as: CinemaCityJob
alias EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob, as: KinoKrakowJob

IO.puts("\n🎬 Triggering scrapers to generate baseline data...\n")

# Trigger Cinema City
IO.puts("📊 Enqueueing Cinema City sync job...")
case CinemaCityJob.new(%{}) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Cinema City job #{job.id} enqueued successfully")
  {:error, reason} ->
    IO.puts("❌ Failed to enqueue Cinema City: #{inspect(reason)}")
end

# Wait a moment
Process.sleep(1000)

# Trigger Kino Krakow
IO.puts("\n📊 Enqueueing Kino Krakow sync job...")
case KinoKrakowJob.new(%{}) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Kino Krakow job #{job.id} enqueued successfully")
  {:error, reason} ->
    IO.puts("❌ Failed to enqueue Kino Krakow: #{inspect(reason)}")
end

IO.puts("\n✅ Jobs enqueued! Monitor progress in Oban dashboard or logs.")
IO.puts("Jobs will create execution data in job_execution_summaries table.\n")
