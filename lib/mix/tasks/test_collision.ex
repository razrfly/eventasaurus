defmodule Mix.Tasks.TestCollision do
  @moduledoc """
  Test event collision handling between sources.
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  import Ecto.Query

  @shortdoc "Test collision handling between sources"

  def run(_args) do
    Application.ensure_all_started(:eventasaurus)

    # Get our sources
    tm_source = Repo.get_by!(Source, slug: "ticketmaster")
    bit_source = Repo.get_by!(Source, slug: "bandsintown")

    Logger.info("""

    🔍 Testing Event Collision Handling
    =====================================
    Ticketmaster Priority: #{tm_source.priority}
    BandsInTown Priority: #{bit_source.priority}
    """)

    # Create a test event that could come from either source
    test_event = %{
      external_id: "test_collision_001",
      title: "Coldplay",
      description: "World tour concert",
      start_at: DateTime.utc_now() |> DateTime.add(30, :day),
      venue_data: %{
        name: "Tauron Arena Kraków",
        city: "Kraków",
        country: "Poland",
        address: "Stanisława Lema 7"
      },
      performer_names: ["Coldplay"],
      source_url: "https://example.com/event",
      metadata: %{test: true}
    }

    # Scenario 1: Event from Ticketmaster first (higher priority)
    Logger.info("\n📝 Scenario 1: Adding event from Ticketmaster...")
    scenario_1_event_id = case EventProcessor.process_event(test_event, tm_source.id, tm_source.priority) do
      {:ok, event} ->
        Logger.info("✅ Event created: ID=#{event.id}")
        event.id
      {:error, reason} ->
        Logger.error("❌ Failed: #{inspect(reason)}")
        nil
    end

    # Scenario 2: Same event from BandsInTown (lower priority)
    Logger.info("\n📝 Scenario 2: Adding same event from BandsInTown...")
    bit_event = Map.put(test_event, :external_id, "bit_collision_001")

    _scenario_2_event_id = case EventProcessor.process_event(bit_event, bit_source.id, bit_source.priority) do
      {:ok, event} ->
        Logger.info("✅ Event processed: ID=#{event.id}")

        if scenario_1_event_id == event.id do
          Logger.info("✨ COLLISION DETECTED: Reused existing event!")
        else
          Logger.warning("⚠️ Created duplicate event instead of merging!")
        end

        event.id
      {:error, reason} ->
        Logger.error("❌ Failed: #{inspect(reason)}")
        nil
    end

    # Check the database state
    if scenario_1_event_id do
      Logger.info("\n📊 Checking database state...")

      sources_query = from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
        join: s in Source, on: s.id == pes.source_id,
        where: pes.event_id == ^scenario_1_event_id,
        select: {s.name, pes.external_id, pes.metadata}
      )

      sources = Repo.all(sources_query)

      Logger.info("Event #{scenario_1_event_id} has #{length(sources)} source(s):")
      Enum.each(sources, fn {name, ext_id, meta} ->
        Logger.info("  - #{name}: external_id=#{ext_id}, priority=#{meta["priority"]}")
      end)
    end

    # Scenario 3: Test with slightly different title
    Logger.info("\n📝 Scenario 3: Testing with slightly different title...")
    varied_event = test_event
    |> Map.put(:external_id, "test_varied_001")
    |> Map.put(:title, "Coldplay - Music of the Spheres Tour")

    case EventProcessor.process_event(varied_event, bit_source.id, bit_source.priority) do
      {:ok, event} ->
        if scenario_1_event_id == event.id do
          Logger.info("✅ Matched despite title variation!")
        else
          Logger.info("📌 Created new event due to title difference: ID=#{event.id}")
        end
      {:error, reason} ->
        Logger.error("❌ Failed: #{inspect(reason)}")
    end

    # Scenario 4: Test with different time (2 hours later)
    Logger.info("\n📝 Scenario 4: Testing with different time (2 hours later)...")
    time_varied = test_event
    |> Map.put(:external_id, "test_time_001")
    |> Map.put(:start_at, DateTime.add(test_event.start_at, 7200, :second))

    case EventProcessor.process_event(time_varied, bit_source.id, bit_source.priority) do
      {:ok, event} ->
        if scenario_1_event_id == event.id do
          Logger.info("✅ Matched despite 2-hour time difference!")
        else
          Logger.info("📌 Created new event due to time difference: ID=#{event.id}")
        end
      {:error, reason} ->
        Logger.error("❌ Failed: #{inspect(reason)}")
    end

    Logger.info("\n✨ Collision test complete!")
  end
end