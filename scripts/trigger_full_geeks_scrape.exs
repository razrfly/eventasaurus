# Trigger FULL Geeks Who Drink re-scrape (no limit)
alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob

IO.puts("🔄 Triggering FULL Geeks Who Drink re-scrape...")
IO.puts("⚠️ This will re-scrape ALL Geeks Who Drink venues")

result = %{"force" => true}
|> SyncJob.new()
|> Oban.insert()

case result do
  {:ok, job} ->
    IO.puts("✅ Successfully enqueued full scrape job: #{job.id}")
    IO.puts("📊 This will process all Geeks Who Drink venues")
    IO.puts("⏳ Check admin UI or database to monitor progress")

  {:error, reason} ->
    IO.puts("❌ Failed to enqueue job: #{inspect(reason)}")
end
