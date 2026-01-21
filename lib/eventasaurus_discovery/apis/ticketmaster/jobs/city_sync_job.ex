defmodule EventasaurusDiscovery.Apis.Ticketmaster.Jobs.CitySyncJob do
  @moduledoc """
  Oban job for fetching and syncing Ticketmaster events by city.

  This job:
  1. Fetches events from Ticketmaster API for a specific city
  2. Transforms the data to our schema
  3. Creates or updates events, venues, and performers
  4. Handles deduplication based on source priority
  """

  use Oban.Worker,
    queue: :discovery,
    max_attempts: 3

  require Logger

  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Apis.Ticketmaster.Client
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Performers.PerformerStore

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = args["city_id"]
    radius = args["radius"] || 50
    max_pages = args["max_pages"] || 5

    # Get city from database
    city = JobRepo.get!(City, city_id) |> JobRepo.preload(:country)

    Logger.info("""
    🎫 Starting Ticketmaster City Sync Job
    City: #{city.name}, #{city.country.name}
    Coordinates: (#{city.latitude}, #{city.longitude})
    Radius: #{radius}km
    Max pages: #{max_pages}
    """)

    # Get or create Ticketmaster source
    source = get_or_create_source()

    # Convert Decimal coordinates to float
    latitude = Decimal.to_float(city.latitude)
    longitude = Decimal.to_float(city.longitude)

    # Fetch all events from Ticketmaster
    case Client.fetch_all_events_by_city(latitude, longitude, city.name, %{
           radius: radius,
           max_pages: max_pages
         }) do
      {:ok, events} ->
        Logger.info("✅ Fetched #{length(events)} events from Ticketmaster")
        process_events(events, source, city)
        {:ok, %{events_processed: length(events)}}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch Ticketmaster events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_or_create_source do
    case JobRepo.get_by(Source, slug: "ticketmaster") do
      nil ->
        {:ok, source} =
          JobRepo.insert(%Source{
            name: "Ticketmaster",
            slug: "ticketmaster",
            website_url: "https://www.ticketmaster.com",
            # Highest priority
            priority: 100,
            is_active: true,
            metadata: %{
              api_type: "rest",
              base_url: "https://app.ticketmaster.com/discovery/v2"
            }
          })

        source

      source ->
        # Ensure priority is set to 100
        if source.priority != 100 do
          source
          |> Ecto.Changeset.change(priority: 100)
          |> JobRepo.update!()
        else
          source
        end
    end
  end

  defp process_events(events, source, city) do
    results =
      Enum.map(events, fn event_data ->
        try do
          result = process_single_event(event_data, source, city)
          Logger.info("✅ Processed: #{event_data.title}")
          {:ok, result}
        rescue
          e ->
            Logger.error("""
            ❌ Failed to process event: #{event_data.external_id}
            Error: #{Exception.message(e)}
            """)

            {:error, e}
        end
      end)

    success_count = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    Logger.info("Processing complete: #{success_count}/#{length(events)} successful")
  end

  defp process_single_event(event_data, source, _city) do
    # Process performers
    performers = process_performers(event_data.performers, source)

    # Process event with venue and performers
    # EventProcessor.process_event handles venue creation internally via venue_data
    event_attrs =
      Map.merge(event_data, %{
        performer_names: Enum.map(performers, & &1.name)
      })

    case EventProcessor.process_event(event_attrs, source.id, source.priority || 100) do
      {:ok, event} ->
        Logger.info("✅ Processed event: #{event.title}")
        event

      {:error, reason} ->
        Logger.error("❌ Failed to process event: #{inspect(reason)}")
        nil
    end
  end

  defp process_performers(performers_data, source) do
    Enum.map(performers_data, fn performer_data ->
      attrs =
        Map.merge(performer_data, %{
          source_id: source.id
        })

      case PerformerStore.find_or_create_performer(attrs) do
        {:ok, performer} -> performer
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
