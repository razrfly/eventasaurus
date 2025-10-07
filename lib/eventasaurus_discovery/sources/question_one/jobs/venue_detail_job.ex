defmodule EventasaurusDiscovery.Sources.QuestionOne.Jobs.VenueDetailJob do
  @moduledoc """
  Scrapes individual venue detail pages and creates events.

  ## Workflow
  1. Fetch venue HTML page
  2. Parse with VenueExtractor (icon-based extraction)
  3. Transform to unified format
  4. Process through Processor.process_source_data/2
  5. VenueProcessor geocodes address automatically
  6. EventProcessor creates/updates event and marks as seen

  ## Critical Features
  - Uses Processor.process_source_data/2 (NOT manual VenueStore/EventStore)
  - VenueProcessor handles geocoding (no manual Google Places calls)
  - EventProcessor updates last_seen_at timestamp
  - Stable external_ids for deduplication
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.QuestionOne.{
    Client,
    Extractors.VenueExtractor,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.Processor

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    venue_url = args["venue_url"]
    venue_title = args["venue_title"]
    source_id = args["source_id"]

    Logger.info("🔍 Processing Question One venue: #{venue_title}")

    with {:ok, body} <- Client.fetch_venue_page(venue_url),
         {:ok, document} <- parse_document(body),
         {:ok, venue_data} <- VenueExtractor.extract_venue_data(document, venue_url, venue_title),
         {:ok, transformed} <- transform_and_validate(venue_data),
         {:ok, results} <- process_event(transformed, source_id) do
      Logger.info("✅ Successfully processed venue: #{venue_title}")
      log_results(results)
      {:ok, results}
    else
      {:error, reason} = error ->
        Logger.error("❌ Failed to process venue #{venue_url}: #{inspect(reason)}")
        error
    end
  end

  defp parse_document(html) do
    document = Floki.parse_document!(html)
    {:ok, document}
  rescue
    error ->
      {:error, "Failed to parse HTML: #{inspect(error)}"}
  end

  defp transform_and_validate(venue_data) do
    case Transformer.transform_event(venue_data) do
      transformed when is_map(transformed) ->
        {:ok, transformed}

      _ ->
        {:error, "Transformation failed"}
    end
  end

  # CRITICAL: Use Processor.process_source_data/2
  # This handles:
  # - VenueProcessor geocoding
  # - EventProcessor creation/update
  # - last_seen_at timestamps
  # - Deduplication via external_id
  defp process_event(transformed, source_id) do
    case Processor.process_source_data([transformed], source_id) do
      {:ok, results} -> {:ok, results}
      error -> error
    end
  end

  defp log_results(results) do
    created = Enum.count(results, fn r -> r.action == :created end)
    updated = Enum.count(results, fn r -> r.action == :updated end)

    Logger.info("""
    📊 Processing results:
    - Created: #{created}
    - Updated: #{updated}
    """)
  end
end
