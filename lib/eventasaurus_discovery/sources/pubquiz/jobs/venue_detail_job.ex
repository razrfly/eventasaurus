defmodule EventasaurusDiscovery.Sources.Pubquiz.Jobs.VenueDetailJob do
  @moduledoc """
  Processes a single PubQuiz venue, creating venue and recurring event records.

  This is where venue data is transformed into a PublicEvent with recurrence_rule.
  Follows the BandsInTown pattern: passes city/country as strings and lets
  VenueProcessor auto-create cities with coordinates.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Sources.Pubquiz

  alias EventasaurusDiscovery.Sources.Pubquiz.{
    Client,
    DetailExtractor,
    Transformer
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    venue_url = args["venue_url"]
    venue_name = args["venue_name"]
    source_id = args["source_id"]
    # Now a string, not ID!
    city_name = args["city_name"]

    external_id = extract_external_id(venue_url)

    # Mark as seen first (follows Karnet/BandsInTown pattern)
    EventProcessor.mark_event_as_seen(external_id, source_id)

    Logger.info("🎭 Processing PubQuiz venue: #{venue_name} (#{city_name})")

    with {:ok, html} <- Client.fetch_venue_page(venue_url),
         details <- DetailExtractor.extract_venue_details(html),
         source <- Repo.get!(Source, source_id) do
      # Combine data from job args and extracted details
      venue_data = Map.merge(args, details)

      # Process through pipeline
      process_through_pipeline(venue_data, source, city_name, external_id)
    else
      {:error, :not_found} ->
        Logger.warning("Venue page not found: #{venue_url}")
        {:ok, :not_found}

      {:error, reason} = error ->
        Logger.error("Failed to process venue #{venue_name}: #{inspect(reason)}")
        error
    end
  end

  defp process_through_pipeline(venue_data, source, city_name, external_id) do
    # Build event map for processor
    event_map = %{
      title: Transformer.build_title(venue_data["venue_name"]),
      source_url: venue_data["venue_url"],
      external_id: external_id,

      # CRITICAL: Venue data with city/country as STRINGS (not IDs)
      # This allows VenueProcessor to auto-create cities with coordinates
      venue_data: %{
        name: venue_data["venue_name"],
        address: venue_data[:address],
        # STRING - VenueProcessor will find/create city
        city: city_name,
        # STRING - VenueProcessor will find/create country
        country: "Poland",
        # May be nil, geocoding will handle
        latitude: venue_data[:latitude],
        # May be nil, geocoding will handle
        longitude: venue_data[:longitude]
      },

      # Recurring event info
      # Will be set by transformer if schedule found
      recurrence_rule: nil,
      # Will be calculated from recurrence_rule
      starts_at: nil,
      ends_at: nil,

      # Additional metadata
      image_url: venue_data["venue_image_url"],
      category: "Trivia",
      is_free: false,
      metadata: %{
        "host" => venue_data[:host],
        "phone" => venue_data[:phone],
        "description" => venue_data[:description],
        "schedule_text" => venue_data[:schedule],
        "source_url" => venue_data["venue_url"]
      }
    }

    # Try to parse schedule and add recurrence_rule
    event_map =
      case Transformer.parse_schedule_to_recurrence(venue_data[:schedule]) do
        {:ok, recurrence_rule} ->
          case Transformer.calculate_next_occurrence(recurrence_rule) do
            {:ok, next_occurrence} ->
              %{
                event_map
                | recurrence_rule: recurrence_rule,
                  starts_at: next_occurrence,
                  ends_at: DateTime.add(next_occurrence, 2 * 3600, :second)
              }

            {:error, reason} ->
              Logger.warning(
                "Could not calculate next occurrence for #{venue_data["venue_name"]}: #{inspect(reason)}"
              )

              event_map
          end

        {:error, reason} ->
          Logger.warning(
            "Could not parse schedule for #{venue_data["venue_name"]}: #{inspect(reason)}"
          )

          event_map
      end

    # Only process if we have dates
    if event_map.starts_at do
      # Check for duplicates before processing
      case check_deduplication(event_map) do
        {:ok, :unique} ->
          Logger.info("✅ Processing unique recurring event: #{event_map.title}")
          Processor.process_single_event(event_map, source)

        {:ok, :skip_duplicate} ->
          Logger.info("⏭️  Skipping duplicate recurring event: #{event_map.title}")
          # Still process through Processor to create/update PublicEventSource entry
          Processor.process_single_event(event_map, source)

        {:ok, :validation_failed} ->
          Logger.warning("⚠️ Validation failed, processing anyway: #{event_map.title}")
          Processor.process_single_event(event_map, source)
      end
    else
      Logger.warning("⚠️ Skipping venue without valid schedule: #{venue_data["venue_name"]}")

      {:discard, :no_valid_schedule}
    end
  end

  defp check_deduplication(event_data) do
    # Convert string keys to atom keys for dedup handler
    event_with_atom_keys = atomize_event_data(event_data)

    case Pubquiz.deduplicate_event(event_with_atom_keys) do
      {:unique, _} ->
        {:ok, :unique}

      {:duplicate, existing} ->
        Logger.info("""
        ⏭️  Skipping duplicate PubQuiz event
        New: #{event_data[:title] || event_data["title"]}
        Existing: #{existing.title} (ID: #{existing.id})
        """)

        {:ok, :skip_duplicate}

      {:error, reason} ->
        Logger.warning("⚠️ Deduplication validation failed: #{inspect(reason)}")
        # Continue with processing even if dedup fails
        {:ok, :validation_failed}
    end
  end

  defp atomize_event_data(event_data) when is_map(event_data) do
    event_data
    |> Enum.map(fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  rescue
    _ -> event_data
  end

  defp extract_external_id(url) do
    # Create a stable ID from the URL
    # Format: pubquiz_warszawa_centrum
    url
    |> String.trim_trailing("/")
    |> String.split("/")
    |> Enum.take(-2)
    |> Enum.join("_")
    |> String.replace("-", "_")
    |> then(&"pubquiz-pl_#{&1}")
  end
end
