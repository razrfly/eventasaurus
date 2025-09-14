defmodule Mix.Tasks.Ticketmaster.SimpleTest do
  @moduledoc """
  Simple test to process a single Ticketmaster event directly.
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query

  @shortdoc "Simple test of Ticketmaster event processing"

  def run(_args) do
    Application.ensure_all_started(:eventasaurus)

    # Get or create source
    source = case Repo.get_by(Source, slug: "ticketmaster") do
      nil ->
        {:ok, s} = Repo.insert(%Source{
          name: "Ticketmaster",
          slug: "ticketmaster",
          website_url: "https://www.ticketmaster.com",
          priority: 100,
          is_active: true
        })
        s
      s -> s
    end

    Logger.info("Using source: #{source.name} (ID: #{source.id}, Priority: #{source.priority})")

    # Create a simple test event
    event_attrs = %{
      title: "Test Ticketmaster Event #{:rand.uniform(1000)}",
      external_id: "tm_test_#{:rand.uniform(1000000)}",
      description: "This is a test event from Ticketmaster",
      starts_at: DateTime.utc_now() |> DateTime.add(7, :day),
      status: "active",
      metadata: %{
        "ticketmaster_data" => %{
          "test" => true,
          "created_at" => DateTime.utc_now()
        }
      }
    }

    Logger.info("Creating event with attrs: #{inspect(event_attrs, pretty: true)}")

    # Try direct insertion first
    case create_event_directly(event_attrs, source) do
      {:ok, event} ->
        Logger.info("✅ Event created successfully!")
        Logger.info("Event ID: #{event.id}")
        Logger.info("Event title: #{event.title}")
        Logger.info("External ID in source: #{get_external_id(event, source)}")

        # Verify in database
        verify_in_database(event.id, source.id)

      {:error, reason} ->
        Logger.error("❌ Failed to create event: #{inspect(reason)}")
    end
  end

  defp create_event_directly(attrs, source) do
    Repo.transaction(fn ->
      # Create the event
      event_changeset = PublicEvent.changeset(%PublicEvent{}, attrs)

      case Repo.insert(event_changeset) do
        {:ok, event} ->
          Logger.info("Event inserted with ID: #{event.id}")

          # Create the source association
          source_attrs = %{
            event_id: event.id,
            source_id: source.id,
            external_id: attrs.external_id,
            source_url: "https://www.ticketmaster.com/event/#{attrs.external_id}",
            last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
            metadata: %{
              "priority" => source.priority || 100
            }
          }

          case Repo.insert(%PublicEventSource{} |> Ecto.Changeset.change(source_attrs)) do
            {:ok, _event_source} ->
              Logger.info("Event source created")
              event
            {:error, changeset} ->
              Logger.error("Failed to create event source: #{inspect(changeset.errors)}")
              Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Logger.error("Failed to create event: #{inspect(changeset.errors)}")
          Repo.rollback(changeset)
      end
    end)
  end

  defp get_external_id(event, source) do
    query = from(pes in PublicEventSource,
      where: pes.event_id == ^event.id and pes.source_id == ^source.id,
      select: pes.external_id
    )
    Repo.one(query)
  end

  defp verify_in_database(event_id, source_id) do
    # Check public_events
    event = Repo.get(PublicEvent, event_id)
    Logger.info("\n📊 DATABASE VERIFICATION:")
    Logger.info("Event exists: #{not is_nil(event)}")

    if event do
      Logger.info("  Title: #{event.title}")
      Logger.info("  Metadata: #{inspect(event.metadata)}")
    end

    # Check public_event_sources
    source_record = Repo.one(from pes in PublicEventSource,
      where: pes.event_id == ^event_id and pes.source_id == ^source_id
    )

    Logger.info("Event source exists: #{not is_nil(source_record)}")

    if source_record do
      Logger.info("  External ID: #{source_record.external_id}")
      Logger.info("  Last seen: #{source_record.last_seen_at}")
    end

    # Count total Ticketmaster events
    tm_count = Repo.one(from pes in PublicEventSource,
      where: pes.source_id == ^source_id,
      select: count(pes.id)
    )

    Logger.info("\nTotal Ticketmaster events in database: #{tm_count}")
  end
end