# Test script to verify freshness checker works for recurring events
# Run with: mix run test_freshness.exs

alias EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob
alias EventasaurusApp.{Cities, Repo}

# Get Kraków
krakow = Cities.get_by_slug("krakow")

if krakow do
  IO.puts("🎫 Testing Ticketmaster sync for Kraków...")
  IO.puts("Before sync, check how many jobs will be created\n")

  # Run the sync
  result = SyncJob.perform(%Oban.Job{
    args: %{
      "city_id" => krakow.id,
      "limit" => 1000,
      "options" => %{}
    }
  })

  IO.puts("\n✅ Sync result: #{inspect(result, pretty: true)}")
else
  IO.puts("❌ Kraków not found in database")
end