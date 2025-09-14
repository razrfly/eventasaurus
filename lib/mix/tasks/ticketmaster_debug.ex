defmodule Mix.Tasks.Ticketmaster.Debug do
  @moduledoc """
  Debug Ticketmaster sync to see exactly what's happening.

  Usage:
    mix ticketmaster.debug
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Apis.Ticketmaster.Client
  alias EventasaurusDiscovery.Scraping.Processors.{EventProcessor, VenueProcessor}
  alias EventasaurusDiscovery.Performers.PerformerStore

  @shortdoc "Debug Ticketmaster sync with detailed output"

  def run(_args) do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:tesla)
    Application.ensure_all_started(:eventasaurus)

    # Get Kraków
    city = Repo.get!(City, 1) |> Repo.preload(:country)

    Logger.info("🔍 DEBUG MODE: Processing single event from Kraków")

    # Get or create source
    source = get_or_create_source()
    Logger.info("Source: #{inspect(source, pretty: true)}")

    # Convert coordinates
    latitude = Decimal.to_float(city.latitude)
    longitude = Decimal.to_float(city.longitude)

    # Fetch just one page with one event
    case Client.fetch_events_by_city(latitude, longitude, city.name, %{radius: 30, size: 1}) do
      {:ok, [event_data | _]} ->
        Logger.info("""

        ============================================
        RAW EVENT DATA FROM TICKETMASTER:
        ============================================
        #{inspect(event_data, pretty: true, limit: :infinity)}
        ============================================
        """)

        # Try to process venue
        Logger.info("\n🏛️ PROCESSING VENUE...")
        venue_result = if event_data.venue_data do
          venue_attrs = Map.merge(event_data.venue_data, %{
            city_id: city.id
          })

          Logger.info("Venue attrs: #{inspect(venue_attrs, pretty: true)}")

          result = VenueProcessor.process_venue(venue_attrs, "ticketmaster")
          Logger.info("Venue result: #{inspect(result, pretty: true)}")

          case result do
            {:ok, venue} -> venue
            {:error, reason} ->
              Logger.error("Venue error: #{inspect(reason)}")
              nil
          end
        else
          nil
        end

        # Try to process performers
        Logger.info("\n🎤 PROCESSING PERFORMERS...")
        performers = Enum.map(event_data.performers || [], fn performer_data ->
          attrs = Map.merge(performer_data, %{
            source_id: source.id
          })

          Logger.info("Performer attrs: #{inspect(attrs, pretty: true)}")

          case PerformerStore.find_or_create_performer(attrs) do
            {:ok, performer} ->
              Logger.info("Created performer: #{performer.name}")
              performer
            {:error, reason} ->
              Logger.error("Performer error: #{inspect(reason)}")
              nil
          end
        end) |> Enum.reject(&is_nil/1)

        # Try to process event
        Logger.info("\n📅 PROCESSING EVENT...")
        event_attrs = Map.merge(event_data, %{
          venue_id: venue_result && venue_result.id,
          performer_names: Enum.map(performers, & &1.name)
        })

        Logger.info("""
        Event attrs being sent to EventProcessor:
        #{inspect(event_attrs, pretty: true, limit: :infinity)}
        """)

        Logger.info("\nCalling EventProcessor.process_event/3 with:")
        Logger.info("  - event_attrs (see above)")
        Logger.info("  - source_id: #{source.id}")
        Logger.info("  - priority: #{source.priority}")

        case EventProcessor.process_event(event_attrs, source.id, source.priority || 100) do
          {:ok, event} ->
            Logger.info("""

            ✅ SUCCESS! Event created/updated:
            ID: #{event.id}
            Title: #{event.title}
            External ID: #{event.external_id}
            """)

            # Check the database
            check_database(event)

          {:error, reason} ->
            Logger.error("""

            ❌ FAILED TO PROCESS EVENT!
            Error: #{inspect(reason, pretty: true)}
            """)

            # Try to understand the error
            analyze_error(reason, event_attrs)
        end

      {:ok, []} ->
        Logger.error("No events found")

      {:error, reason} ->
        Logger.error("Failed to fetch from API: #{inspect(reason)}")
    end
  end

  defp get_or_create_source do
    case Repo.get_by(Source, slug: "ticketmaster") do
      nil ->
        {:ok, source} = Repo.insert(%Source{
          name: "Ticketmaster",
          slug: "ticketmaster",
          website_url: "https://www.ticketmaster.com",
          priority: 100,
          is_active: true,
          metadata: %{
            api_type: "rest",
            base_url: "https://app.ticketmaster.com/discovery/v2"
          }
        })
        source
      source ->
        source
    end
  end

  defp check_database(event) do
    import Ecto.Query

    # Check public_events
    event_count = from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
      where: pe.id == ^event.id
    ) |> Repo.aggregate(:count)

    Logger.info("Event in public_events table: #{event_count > 0}")

    # Check public_event_sources
    source_count = from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
      where: pes.event_id == ^event.id
    ) |> Repo.aggregate(:count)

    Logger.info("Event in public_event_sources table: #{source_count > 0}")

    # Check if we can find by external_id
    external_count = from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
      where: like(pes.external_id, "tm_%")
    ) |> Repo.aggregate(:count)

    Logger.info("Total Ticketmaster events in public_event_sources: #{external_count}")
  end

  defp analyze_error(reason, event_attrs) do
    Logger.info("""

    🔍 ERROR ANALYSIS:
    """)

    # Check for missing required fields
    required_fields = [:external_id, :title, :start_at]
    missing = Enum.filter(required_fields, fn field ->
      is_nil(Map.get(event_attrs, field))
    end)

    if missing != [] do
      Logger.error("Missing required fields: #{inspect(missing)}")
    end

    # Check date format
    if event_attrs[:start_at] do
      Logger.info("start_at type: #{inspect(event_attrs.start_at.__struct__)}")
      Logger.info("start_at value: #{inspect(event_attrs.start_at)}")
    end

    # Check if it's a changeset error
    case reason do
      %Ecto.Changeset{} = changeset ->
        Logger.error("Changeset errors: #{inspect(changeset.errors)}")
        Logger.error("Changeset changes: #{inspect(changeset.changes)}")
      _ ->
        :ok
    end
  end
end