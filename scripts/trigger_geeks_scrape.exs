# Trigger Geeks Who Drink scrape with limit=1 for testing
alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob
alias EventasaurusApp.Repo

IO.puts("🔄 Triggering Geeks Who Drink scrape (limit=1)...")

result = %{"force" => true, "limit" => 1}
|> SyncJob.new()
|> Oban.insert()

case result do
  {:ok, job} ->
    IO.puts("✅ Successfully enqueued scrape job: #{job.id}")
    IO.puts("⏳ Waiting 30 seconds for job to complete...")
    Process.sleep(30_000)

    # Check the job status
    case Oban.Job |> Repo.get(job.id) do
      nil -> IO.puts("⚠️ Job not found")
      updated_job ->
        IO.puts("📊 Job status: #{updated_job.state}")
        if updated_job.state == "completed" do
          IO.puts("✅ Job completed successfully!")
        else
          IO.puts("⚠️ Job state: #{updated_job.state}")
        end
    end

  {:error, reason} ->
    IO.puts("❌ Failed to enqueue job: #{inspect(reason)}")
end
