# Test recurring event consolidation with inline processing
# Run with: mix run test_recurring_inline.exs

require Logger
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.PublicEvents.PublicEvent
import Ecto.Query

# First, check the current state
before_count = Repo.aggregate(PublicEvent, :count, :id)

before_with_occurrences =
  from(e in PublicEvent, where: not is_nil(e.occurrences)) |> Repo.aggregate(:count, :id)

Logger.info("""
📊 Before running scraper:
- Total events: #{before_count}
- Events with occurrences: #{before_with_occurrences}
""")

# Check for Muzeum Banksy before
muzeum_before =
  from(e in PublicEvent,
    where: ilike(e.title, "%muzeum banksy%"),
    select: {e.id, e.title, e.occurrences}
  )
  |> Repo.all()

Logger.info("Muzeum Banksy events before: #{length(muzeum_before)}")

# Now run the Ticketmaster sync for Krakow with a small limit
Logger.info("\n🚀 Running Ticketmaster sync for Krakow...")

Mix.Task.run("discovery.sync", ["ticketmaster", "--city", "krakow", "--limit", "100", "--inline"])

# Give it a moment to process
Process.sleep(2000)

# Check the state after
after_count = Repo.aggregate(PublicEvent, :count, :id)

after_with_occurrences =
  from(e in PublicEvent, where: not is_nil(e.occurrences)) |> Repo.aggregate(:count, :id)

Logger.info("""

📊 After running scraper:
- Total events: #{after_count}
- Events with occurrences: #{after_with_occurrences}
- New events added: #{after_count - before_count}
- Events with occurrences added: #{after_with_occurrences - before_with_occurrences}
""")

# Check Muzeum Banksy specifically
muzeum_after =
  from(e in PublicEvent,
    where: ilike(e.title, "%muzeum banksy%"),
    select: {e.id, e.title, e.occurrences}
  )
  |> Repo.all()

Logger.info("\n🎨 Muzeum Banksy events after: #{length(muzeum_after)}")

Enum.each(muzeum_after, fn {id, title, occ} ->
  if occ && occ["dates"] do
    Logger.info("  ID #{id}: #{title} - Has #{length(occ["dates"])} occurrences")
    # Show first few dates
    occ["dates"]
    |> Enum.take(3)
    |> Enum.each(fn date ->
      Logger.info("    - #{date["date"]} at #{date["time"]}")
    end)

    if length(occ["dates"]) > 3 do
      Logger.info("    ... and #{length(occ["dates"]) - 3} more dates")
    end
  else
    Logger.info("  ID #{id}: #{title} - NO occurrences")
  end
end)

# Success check
if length(muzeum_after) == 1 && after_with_occurrences > before_with_occurrences do
  Logger.info("""

  ✅ SUCCESS! Recurring event consolidation is working!
  - Muzeum Banksy consolidated into 1 event with occurrences
  """)
else
  Logger.warning("""

  ⚠️  Consolidation may not be working as expected.
  - Expected 1 Muzeum Banksy event with occurrences
  - Got #{length(muzeum_after)} events
  """)
end
