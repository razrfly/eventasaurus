# REAL FIX: Convert events that SHOULD be physical but are marked as virtual
# The actual problem: Events with venue_id assigned but is_virtual=true
# This is what the working ai-crimes1 fix actually did!

alias EventasaurusApp.{Repo, Events, Venues}
import Ecto.Query
require Logger

defmodule FixVirtualEventsWithVenues do
  def run do
    Logger.info("Finding events that have venues but are marked as virtual...")
    
    # The REAL issue: Events with venue_id assigned but still marked as is_virtual=true
    broken_events = Repo.all(
      from e in Events.Event,
      where: e.is_virtual == true and not is_nil(e.venue_id),
      order_by: [desc: e.inserted_at]
    )
    
    Logger.info("Found #{length(broken_events)} events that have venues but are marked as virtual")
    
    if length(broken_events) > 0 do
      # Fix them: set is_virtual=false since they already have venue_id
      broken_events
      |> Enum.each(fn event ->
        case Events.update_event(event, %{is_virtual: false, virtual_venue_url: nil}) do
          {:ok, updated_event} ->
            venue = Repo.get(Venues.Venue, event.venue_id)
            venue_name = if venue, do: venue.name, else: "Unknown Venue"
            Logger.info("✅ Fixed '#{String.slice(event.title, 0..50)}' → now physical at #{venue_name}")
            
          {:error, reason} ->
            Logger.error("❌ Failed to fix event #{event.id}: #{inspect(reason)}")
        end
      end)
      
      Logger.info("Virtual-to-Physical conversion complete! Fixed #{length(broken_events)} events.")
    else
      Logger.info("No events found that have venues but are marked as virtual")
    end
  end
end

# Run the real fix
FixVirtualEventsWithVenues.run()