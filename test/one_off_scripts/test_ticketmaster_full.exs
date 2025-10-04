# Test Ticketmaster sync with more events
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City
alias EventasaurusDiscovery.Sources.Ticketmaster

# Get a city (Kraków)
city = Repo.get(City, 1) |> Repo.preload(:country)

if city do
  IO.puts("Testing Ticketmaster sync for #{city.name} with 10 events")

  # Create the job args
  args = %{
    "city_id" => city.id,
    "limit" => 10,
    "options" => %{}
  }

  # Create an Oban job structure
  job = %Oban.Job{args: args}

  # Run the sync
  result = Ticketmaster.Jobs.SyncJob.perform(job)

  IO.inspect(result, label: "Sync Result")

  # Wait for processing
  Process.sleep(10_000)

  # Check job status
  import Ecto.Query

  jobs =
    Repo.all(
      from(j in Oban.Job,
        where: j.worker == "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob",
        order_by: [desc: j.inserted_at],
        limit: 20
      )
    )

  completed = Enum.count(jobs, &(&1.state == "completed"))
  failed = Enum.count(jobs, &(&1.state in ["discarded", "retryable"]))

  IO.puts("\n=== Job Summary ===")
  IO.puts("Total jobs: #{length(jobs)}")
  IO.puts("Completed: #{completed}")
  IO.puts("Failed: #{failed}")

  if failed > 0 do
    IO.puts("\n=== Failed Jobs ===")

    jobs
    |> Enum.filter(&(&1.state in ["discarded", "retryable"]))
    |> Enum.each(fn job ->
      IO.puts("Job #{job.id}: #{inspect(job.errors)}")
    end)
  end
else
  IO.puts("City not found!")
end
