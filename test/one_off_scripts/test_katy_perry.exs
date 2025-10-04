# Test processing the problematic Katy Perry event
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Sources.Ticketmaster
import Ecto.Query

# Clear any existing failed jobs for a clean test
Repo.delete_all(
  from(j in Oban.Job,
    where:
      j.worker == "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob" and
        j.state in ["retryable", "discarded"]
  )
)

# Get Kraków city
city = Repo.get(EventasaurusDiscovery.Locations.City, 1) |> Repo.preload(:country)

if city do
  IO.puts("Testing Ticketmaster sync for #{city.name} - focusing on Katy Perry event")

  # Run sync with a limit that should include Katy Perry
  args = %{
    "city_id" => city.id,
    "limit" => 30,
    "options" => %{}
  }

  job = %Oban.Job{args: args}
  result = Ticketmaster.Jobs.SyncJob.perform(job)

  IO.inspect(result, label: "Sync Result")

  # Wait for processing
  Process.sleep(15_000)

  # Check if Katy Perry event processed successfully
  katy_event =
    Repo.one(
      from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        where: ilike(pe.title, "%Katy Perry%")
      )
    )

  if katy_event do
    IO.puts("\n✅ Katy Perry event processed successfully:")
    IO.puts("  Title: #{katy_event.title}")
    IO.puts("  Starts at: #{katy_event.starts_at}")
    IO.puts("  Ends at: #{katy_event.ends_at || "nil"}")
    IO.puts("  Occurrences: #{inspect(katy_event.occurrences)}")
  else
    IO.puts("\n❌ Katy Perry event not found in database")
  end

  # Check for failed jobs
  failed_jobs =
    Repo.all(
      from(j in Oban.Job,
        where:
          j.worker == "EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob" and
            j.state in ["discarded", "retryable"],
        limit: 5
      )
    )

  if length(failed_jobs) > 0 do
    IO.puts("\n⚠️  Found #{length(failed_jobs)} failed jobs:")

    Enum.each(failed_jobs, fn job ->
      IO.puts("  Job #{job.id}: #{inspect(job.errors)}")
    end)
  else
    IO.puts("\n✅ No failed jobs")
  end
else
  IO.puts("City not found!")
end
