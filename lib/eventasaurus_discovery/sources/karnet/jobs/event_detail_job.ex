defmodule EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for processing individual Karnet event details.

  Fetches the event page, extracts details, and processes them through
  the unified discovery pipeline.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Sources.Karnet.{Client, DetailExtractor, DateParser}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    url = args["url"]
    source_id = args["source_id"]
    event_metadata = args["event_metadata"] || %{}

    Logger.info("🎭 Processing Karnet event: #{url}")

    # Fetch the event page
    case Client.fetch_page(url) do
      {:ok, html} ->
        process_event_html(html, url, source_id, event_metadata)

      {:error, :not_found} ->
        Logger.warning("Event page not found: #{url}")
        {:ok, :not_found}

      {:error, reason} ->
        Logger.error("Failed to fetch event page #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_event_html(html, url, source_id, metadata) do
    # Extract event details
    case DetailExtractor.extract_event_details(html, url) do
      {:ok, event_data} ->
        # Merge with metadata from index if available
        enriched_data = merge_metadata(event_data, metadata)

        # Parse dates
        enriched_data = add_parsed_dates(enriched_data)

        # Get source
        source = Repo.get!(Source, source_id)

        # Process through unified pipeline
        case process_through_pipeline(enriched_data, source) do
          {:ok, event} ->
            Logger.info("✅ Successfully processed Karnet event: #{event.id} - #{event.title}")
            {:ok, event}

          {:error, reason} ->
            Logger.error("Failed to process event through pipeline: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to extract event details from #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp merge_metadata(event_data, metadata) do
    # Prefer extracted data but fall back to metadata from index
    Map.merge(metadata, event_data, fn _key, meta_val, event_val ->
      if is_nil(event_val) || event_val == "", do: meta_val, else: event_val
    end)
  end

  defp add_parsed_dates(event_data) do
    # Parse the date text into actual DateTime values
    case DateParser.parse_date_string(event_data[:date_text]) do
      {:ok, {start_dt, end_dt}} ->
        event_data
        |> Map.put(:starts_at, start_dt)
        |> Map.put(:ends_at, if(start_dt == end_dt, do: nil, else: end_dt))

      _ ->
        # If we can't parse the date, use a fallback
        Logger.warning("Could not parse date: #{event_data[:date_text]}")

        # Use a reasonable fallback: 30 days from now for the event
        # This allows the event to be stored but marked as needing review
        fallback_date = DateTime.add(DateTime.utc_now(), 30 * 86400, :second)

        event_data
        |> Map.put(:starts_at, fallback_date)
        |> Map.put(:ends_at, nil)
        |> Map.update(:source_metadata, %{}, fn meta ->
          Map.put(meta, "date_parse_failed", true)
        end)
    end
  end

  defp process_through_pipeline(event_data, source) do
    # Transform data to match processor expectations
    processor_data = transform_for_processor(event_data)

    # Process through unified pipeline
    Processor.process_single_event(processor_data, source)
  end

  defp transform_for_processor(event_data) do
    # Ensure we always have venue data (required by processor)
    venue_data = event_data[:venue_data] || %{
      name: "Kraków City Center",
      city: "Kraków",
      country: "Poland"
    }

    %{
      # Required fields
      title: event_data[:title] || "Untitled Event",
      source_url: event_data[:url],

      # Dates
      starts_at: event_data[:starts_at],
      ends_at: event_data[:ends_at],
      date: event_data[:starts_at],  # Legacy field

      # Venue - will be processed by VenueProcessor
      venue_data: venue_data,
      venue: venue_data,  # Alternative key

      # Performers
      performers: event_data[:performers] || [],
      performer_names: extract_performer_names(event_data[:performers]),

      # Additional fields
      description: event_data[:description],
      ticket_url: event_data[:ticket_url],
      image_url: event_data[:image_url],
      category: event_data[:category],
      is_free: event_data[:is_free] || false,
      is_festival: event_data[:is_festival] || false,

      # Metadata
      external_id: extract_external_id(event_data[:url]),
      source_metadata: %{
        "url" => event_data[:url],
        "category" => event_data[:category],
        "date_text" => event_data[:date_text],
        "extracted_at" => event_data[:extracted_at]
      }
    }
  end

  defp extract_performer_names(nil), do: []
  defp extract_performer_names([]), do: []
  defp extract_performer_names(performers) when is_list(performers) do
    Enum.map(performers, fn
      %{name: name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp extract_external_id(url) do
    # Extract the event ID from the URL
    # Format: /60682-krakow-event-name
    case Regex.run(~r/\/(\d+)-/, url) do
      [_, id] -> "karnet_#{id}"
      _ -> nil
    end
  end
end