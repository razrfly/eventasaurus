# Test Ticketmaster sync with individual job processing
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City
alias EventasaurusDiscovery.Sources.Ticketmaster

# Get a city (Kraków)
city = Repo.get(City, 1) |> Repo.preload(:country)

if city do
  IO.puts("Testing Ticketmaster sync for #{city.name}")

  # Create the job args
  args = %{
    "city_id" => city.id,
    "limit" => 2,
    "options" => %{}
  }

  # Create an Oban job structure
  job = %Oban.Job{args: args}

  # Run the sync
  result = Ticketmaster.Jobs.SyncJob.perform(job)

  IO.inspect(result, label: "Sync Result")
else
  IO.puts("City not found!")
end