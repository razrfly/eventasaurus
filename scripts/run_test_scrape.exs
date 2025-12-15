require Logger

# Schedule a sync job with limit=3 to test bilingual functionality
job_args = %{"limit" => 3}

case EventasaurusDiscovery.Sources.Sortiraparis.Jobs.SyncJob.new(job_args) |> Oban.insert() do
  {:ok, job} ->
    IO.puts("✅ Sync job scheduled successfully!")
    IO.puts("Job ID: #{job.id}")
    IO.puts("Limit: 3 articles")
    IO.puts("")
    IO.puts("Waiting for job to complete (may take 1-2 minutes)...")
    IO.puts("")

    # Wait for job to complete
    :timer.sleep(120_000)  # 2 minutes

    # Check results
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("RESULTS")
    IO.puts(String.duplicate("=", 80))
    IO.puts("")

  {:error, reason} ->
    IO.puts("❌ Failed to schedule job: #{inspect(reason)}")
end
