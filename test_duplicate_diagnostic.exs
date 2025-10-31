# Diagnostic Test Script for Duplicate Venue Issue
# This script runs a controlled test to diagnose why duplicates are being created

alias EventasaurusApp.Repo
alias EventasaurusApp.Venues.Venue

IO.puts("\n=== DIAGNOSTIC TEST FOR DUPLICATE VENUES ===\n")

# Step 1: Clear all existing venues
IO.puts("Step 1: Clearing all venues from database...")
{deleted_count, _} = Repo.delete_all(Venue)
IO.puts("✓ Deleted #{deleted_count} venues\n")

# Step 2: Run a single scraper to create venues
IO.puts("Step 2: Running QuestionOne scraper...")
IO.puts("Watch for 🔍 log messages showing venue creation flow\n")

try do
  EventasaurusDiscovery.Sources.QuestionOne.run_scraper()
  IO.puts("\n✓ Scraper completed successfully\n")
rescue
  e ->
    IO.puts("\n❌ Scraper failed: #{inspect(e)}\n")
    reraise e, __STACKTRACE__
end

# Step 3: Check for duplicates
IO.puts("Step 3: Checking for duplicate venues...")

duplicates_query = """
WITH duplicate_groups AS (
  SELECT
    name,
    ROUND(latitude::numeric, 6) as lat,
    ROUND(longitude::numeric, 6) as lng,
    COUNT(*) as duplicate_count,
    array_agg(id ORDER BY id) as venue_ids,
    array_agg(TO_CHAR(inserted_at, 'HH24:MI:SS')) as insertion_times
  FROM venues
  GROUP BY name, ROUND(latitude::numeric, 6), ROUND(longitude::numeric, 6)
  HAVING COUNT(*) > 1
)
SELECT
  name,
  lat,
  lng,
  duplicate_count,
  venue_ids,
  insertion_times
FROM duplicate_groups
ORDER BY name;
"""

case Repo.query(duplicates_query) do
  {:ok, %{rows: rows, num_rows: count}} ->
    if count == 0 do
      IO.puts("✅ NO DUPLICATES FOUND!")
    else
      IO.puts("❌ FOUND #{count} DUPLICATE GROUPS:\n")

      Enum.each(rows, fn [name, lat, lng, dup_count, venue_ids, times] ->
        IO.puts("  • #{name}")
        IO.puts("    Coordinates: (#{lat}, #{lng})")
        IO.puts("    Duplicate count: #{dup_count}")
        IO.puts("    Venue IDs: #{inspect(venue_ids)}")
        IO.puts("    Insertion times: #{inspect(times)}")
        IO.puts("")
      end)
    end

  {:error, error} ->
    IO.puts("❌ Query failed: #{inspect(error)}")
end

# Step 4: Summary statistics
IO.puts("\nStep 4: Summary Statistics")

total_venues = Repo.aggregate(Venue, :count, :id)
IO.puts("  Total venues created: #{total_venues}")

IO.puts("\n=== DIAGNOSTIC TEST COMPLETE ===")
IO.puts("\nNEXT STEPS:")
IO.puts("1. Review the 🔍 log messages above to see the venue creation flow")
IO.puts("2. Check if advisory lock messages (🔒) appeared")
IO.puts("3. For any duplicates found, note the insertion times")
IO.puts("4. If duplicates exist, check logs for those specific venue names")
IO.puts("\nLOG MARKERS TO LOOK FOR:")
IO.puts("  🔍 ENTER create_venue - Function entry")
IO.puts("  🔍 CALL insert_venue_with_advisory_lock - About to acquire lock")
IO.puts("  🔍 ENTER insert_venue_with_advisory_lock - Lock function entry")
IO.puts("  🔍 Lock key=... - Shows lock key and rounded coordinates")
IO.puts("  🔒 Acquired advisory lock - Successfully got lock")
IO.puts("  🔍 Searching for duplicates - About to search")
IO.puts("  🔍 Duplicate search result - Shows if duplicate was found")
IO.puts("  🏛️ ✅ DUPLICATE FOUND - Returning existing venue")
IO.puts("  🔍 NO DUPLICATE - Will insert new venue")
IO.puts("  ✅ INSERT SUCCESS - New venue created")
IO.puts("")
