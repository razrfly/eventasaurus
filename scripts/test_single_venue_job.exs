# Test single venue job to see actual errors
alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.VenueDetailJob
alias EventasaurusApp.Repo
import Ecto.Query

# Get one Geeks Who Drink event source
geeks_source_id = 6

event_source =
  from(es in "public_event_sources",
    where: es.source_id == ^geeks_source_id,
    limit: 1,
    select: %{
      id: es.id,
      event_id: es.event_id,
      external_id: es.external_id
    }
  )
  |> Repo.one()

IO.puts("Testing with event source: #{inspect(event_source)}")

# Extract venue ID from external_id format: "geeks_who_drink_3084221980" -> "3084221980"
venue_id = String.replace(event_source.external_id, "geeks_who_drink_", "")
venue_url = "https://www.geekswhodrink.com/venues/#{venue_id}"

IO.puts("Constructed venue URL: #{venue_url}")

# Schedule the job
job = %{
  "event_source_id" => event_source.id,
  "venue_url" => venue_url
}
|> VenueDetailJob.new()
|> Oban.insert!()

IO.puts("✅ Job scheduled with ID: #{job.id}")
IO.puts("Waiting 10 seconds for job to process...")

:timer.sleep(10_000)

# Check job status
job_status = Repo.get(Oban.Job, job.id)
IO.puts("\nJob status: #{job_status.state}")
if job_status.state == "discarded" do
  IO.puts("Errors: #{inspect(job_status.errors)}")
end
