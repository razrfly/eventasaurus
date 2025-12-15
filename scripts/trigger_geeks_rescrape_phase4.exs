# Trigger full re-scrape of Geeks Who Drink events - Phase 4 (Time Extraction Fix)
#
# Run with: mix run trigger_geeks_rescrape_phase4.exs

alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.VenueDetailJob
alias EventasaurusApp.Repo
import Ecto.Query

# Get all Geeks Who Drink event source IDs
geeks_source_id = 6

event_sources =
  from(es in "public_event_sources",
    where: es.source_id == ^geeks_source_id,
    select: %{
      id: es.id,
      event_id: es.event_id,
      external_id: es.external_id
    }
  )
  |> Repo.all()

IO.puts("Found #{length(event_sources)} Geeks Who Drink event sources")
IO.puts("Scheduling VenueDetailJob for all events...")

# Schedule a VenueDetailJob for each event source
Enum.each(event_sources, fn es ->
  # Extract venue ID from external_id (format: "geeks_who_drink_3084221980")
  venue_id = String.replace(es.external_id, "geeks_who_drink_", "")
  venue_url = "https://www.geekswhodrink.com/venues/#{venue_id}"

  %{
    "event_source_id" => es.id,
    "venue_url" => venue_url
  }
  |> VenueDetailJob.new()
  |> Oban.insert()
end)

IO.puts("✅ Scheduled #{length(event_sources)} VenueDetailJob tasks")
IO.puts("Jobs will process in the background. Check progress with:")
IO.puts("  SELECT count(*) FROM oban_jobs WHERE worker = 'EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.VenueDetailJob' AND state = 'completed';")
