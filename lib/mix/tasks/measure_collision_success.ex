defmodule Mix.Tasks.MeasureCollisionSuccess do
  @moduledoc """
  Measure the success of collision detection by loading events from multiple sources.
  """

  use Mix.Task
  require Logger
  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Apis.Ticketmaster.Jobs.CitySyncJob
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Locations.City

  @shortdoc "Measure collision detection success"

  def run(_args) do
    Application.ensure_all_started(:eventasaurus)

    Logger.info("""

    📊 COLLISION DETECTION SUCCESS MEASUREMENT
    ==========================================
    Testing with Kraków data from multiple sources
    """)

    # Get Kraków city
    krakow = Repo.get_by!(City, slug: "krakow") |> Repo.preload(:country)

    # Clear existing test data (optional - comment out to keep accumulating)
    # clear_test_data()

    # Record initial state
    initial_stats = get_stats()

    Logger.info("""
    📈 Initial State:
      Total Events: #{initial_stats.total_events}
      Total Venues: #{initial_stats.total_venues}
      Total Performers: #{initial_stats.total_performers}
      Events with multiple sources: #{initial_stats.multi_source_events}
    """)

    # Step 1: Load Ticketmaster data
    Logger.info("\n🎫 Loading Ticketmaster events...")
    load_ticketmaster_events(krakow)

    ticketmaster_stats = get_stats()

    Logger.info("""
    After Ticketmaster:
      Events added: #{ticketmaster_stats.total_events - initial_stats.total_events}
      Venues added: #{ticketmaster_stats.total_venues - initial_stats.total_venues}
      Performers added: #{ticketmaster_stats.total_performers - initial_stats.total_performers}
    """)

    # Step 2: Load BandsInTown data
    Logger.info("\n🎸 Loading BandsInTown events...")
    load_bandsintown_events(krakow)

    final_stats = get_stats()

    Logger.info("""

    📊 FINAL RESULTS:
    =================
    Total Events: #{final_stats.total_events}
    Total Venues: #{final_stats.total_venues}
    Total Performers: #{final_stats.total_performers}

    🎯 SUCCESS METRICS:
    Events with multiple sources: #{final_stats.multi_source_events}
    Percentage with multiple sources: #{Float.round(final_stats.multi_source_events / final_stats.total_events * 100, 1)}%

    📈 DEDUPLICATION RESULTS:
    Events added by Ticketmaster: #{ticketmaster_stats.total_events - initial_stats.total_events}
    Events added by BandsInTown: #{final_stats.total_events - ticketmaster_stats.total_events}
    Events matched (not duplicated): #{final_stats.multi_source_events}
    """)

    # Show examples of matched events
    show_matched_events()

    # Check for duplicate venues
    check_duplicate_venues()

    # Check for duplicate performers
    check_duplicate_performers()
  end

  defp get_stats do
    total_events = Repo.one(from(e in PublicEvent, select: count(e.id)))
    total_venues = Repo.one(from(v in EventasaurusApp.Venues.Venue, select: count(v.id)))

    total_performers =
      Repo.one(from(p in EventasaurusDiscovery.Performers.Performer, select: count(p.id)))

    multi_source_events =
      Repo.one(
        from(e in PublicEvent,
          join: es in PublicEventSource,
          on: es.event_id == e.id,
          group_by: e.id,
          having: count(es.source_id) > 1,
          select: count(e.id)
        )
      )

    %{
      total_events: total_events || 0,
      total_venues: total_venues || 0,
      total_performers: total_performers || 0,
      multi_source_events: multi_source_events || 0
    }
  end

  defp load_ticketmaster_events(city) do
    job = %Oban.Job{
      args: %{
        "city_id" => city.id,
        "radius" => 50,
        # Load 2 pages for good sample
        "max_pages" => 2
      }
    }

    CitySyncJob.perform(job)
  end

  defp load_bandsintown_events(city) do
    # Run BandsInTown scraper
    Mix.Task.run("scrape.bandsintown", ["--city", city.slug])
  end

  defp show_matched_events do
    Logger.info("\n✨ EXAMPLES OF MATCHED EVENTS:")

    matched_events =
      from(e in PublicEvent,
        join: es in PublicEventSource,
        on: es.event_id == e.id,
        join: s in Source,
        on: s.id == es.source_id,
        group_by: [e.id, e.title, e.starts_at],
        having: count(es.source_id) > 1,
        select: %{
          id: e.id,
          title: e.title,
          starts_at: e.starts_at,
          sources: fragment("array_agg(?)", s.name)
        },
        limit: 10
      )
      |> Repo.all()

    Enum.each(matched_events, fn event ->
      sources = Enum.join(event.sources, " + ")
      Logger.info("  #{event.title}")
      Logger.info("    📅 #{event.starts_at}")
      Logger.info("    📍 Sources: #{sources}")
    end)

    if Enum.empty?(matched_events) do
      Logger.warning(
        "  No matched events found! This suggests the matching logic may not be working."
      )
    end
  end

  defp check_duplicate_venues do
    Logger.info("\n🏢 CHECKING FOR DUPLICATE VENUES:")

    # Find venues within 100 meters of each other
    duplicate_venues =
      Repo.all(
        from(v1 in EventasaurusApp.Venues.Venue,
          join: v2 in EventasaurusApp.Venues.Venue,
          on:
            v1.id < v2.id and
              v1.city_id == v2.city_id and
              fragment("abs(? - ?) < 0.001", v1.latitude, v2.latitude) and
              fragment("abs(? - ?) < 0.001", v1.longitude, v2.longitude),
          select: %{
            id1: v1.id,
            name1: v1.name,
            id2: v2.id,
            name2: v2.name,
            lat1: v1.latitude,
            lng1: v1.longitude,
            lat2: v2.latitude,
            lng2: v2.longitude
          },
          limit: 10
        )
      )

    if Enum.empty?(duplicate_venues) do
      Logger.info("  ✅ No duplicate venues found within 100m!")
    else
      Logger.warning("  ⚠️ Found #{length(duplicate_venues)} potential duplicate venues:")

      Enum.each(duplicate_venues, fn dup ->
        Logger.warning("    - '#{dup.name1}' (#{dup.id1}) vs '#{dup.name2}' (#{dup.id2})")
        Logger.warning("      Coords: (#{dup.lat1}, #{dup.lng1}) vs (#{dup.lat2}, #{dup.lng2})")
      end)
    end
  end

  defp check_duplicate_performers do
    Logger.info("\n🎤 CHECKING FOR DUPLICATE PERFORMERS:")

    # Get all performers and check for similar names
    performers =
      Repo.all(
        from(p in EventasaurusDiscovery.Performers.Performer, select: %{id: p.id, name: p.name})
      )

    duplicates =
      for p1 <- performers,
          p2 <- performers,
          p1.id < p2.id,
          similarity = String.jaro_distance(String.downcase(p1.name), String.downcase(p2.name)),
          similarity > 0.85 do
        %{
          id1: p1.id,
          name1: p1.name,
          id2: p2.id,
          name2: p2.name,
          similarity: similarity
        }
      end
      |> Enum.take(10)

    if Enum.empty?(duplicates) do
      Logger.info("  ✅ No duplicate performers found (>85% similarity)!")
    else
      Logger.warning("  ⚠️ Found #{length(duplicates)} potential duplicate performers:")

      Enum.each(duplicates, fn dup ->
        Logger.warning(
          "    - '#{dup.name1}' (#{dup.id1}) vs '#{dup.name2}' (#{dup.id2}) - #{Float.round(dup.similarity * 100, 1)}% similar"
        )
      end)
    end
  end
end
