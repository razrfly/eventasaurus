# Test script for country detection fix

alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City
alias EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob

# Get Kraków with country preloaded
city = Repo.get_by!(City, name: "Kraków") |> Repo.preload(:country)
IO.puts("City: #{city.name}, Country: #{city.country.name}, Code: #{city.country.code}")

# Queue the sync job
job = %{city_id: city.id, limit: 5}
|> SyncJob.new()
|> Oban.insert!()

IO.puts("Job queued with ID: #{job.id}")
IO.puts("Waiting for job to process...")

# Give it a moment to process
Process.sleep(10_000)

IO.puts("Check logs for 'Unknown country' warnings - there should be none!")