defmodule EventasaurusDiscovery.Sources.Karnet do
  @moduledoc """
  Karnet Kraków scraper for cultural events in Kraków, Poland.

  This is a lower-priority, localized scraper that complements
  Ticketmaster and BandsInTown with local Kraków events.

  ## Features
  - HTML scraping (no API available)
  - Polish language support
  - Simplified festival handling
  - Basic deduplication against other sources

  ## Limitations
  - Kraków-only events
  - Limited performer information
  - No sub-event extraction for festivals
  - Lower priority than international sources
  """

  alias EventasaurusDiscovery.Sources.Karnet.{
    Source,
    Jobs.SyncJob,
    DedupHandler
  }

  alias EventasaurusDiscovery.Sources.SourceStore

  @doc """
  Start a sync job to fetch events from Karnet.

  Options:
  - `:max_pages` - Maximum number of pages to fetch (default: from config)
  - `:force` - Skip deduplication checks
  """
  def sync(options \\ %{}) do
    if Source.enabled?() do
      args = Source.sync_job_args(options)

      %{source_id: source_id} = ensure_source_exists()
      args = Map.put(args, "source_id", source_id)

      {:ok, job} = Oban.insert(SyncJob.new(args))
      {:ok, job}
    else
      {:error, :source_disabled}
    end
  end

  @doc """
  Get the source configuration.
  """
  def config, do: Source.config()

  @doc """
  Check if the source is enabled.
  """
  def enabled?, do: Source.enabled?()

  @doc """
  Validate source configuration and connectivity.
  """
  def validate, do: Source.validate_config()

  @doc """
  Process an event through deduplication.

  Two-phase deduplication strategy:
  - Phase 1: Check if THIS source already imported it (same-source dedup)
  - Phase 2: Check if higher-priority source imported it (cross-source fuzzy match)

  ## Parameters
  - `event_data` - Event data with external_id, title, starts_at, venue_data
  - `source` - Source struct with priority and domains

  ## Returns
  - `{:unique, event_data}` - Event is unique, proceed with import
  - `{:duplicate, existing}` - Event already exists (same source or higher priority)
  - `{:enriched, event_data}` - Event enriched with additional data
  """
  def deduplicate_event(event_data, source) do
    case DedupHandler.validate_event_quality(event_data) do
      {:ok, validated} ->
        DedupHandler.check_duplicate(validated, source)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp ensure_source_exists do
    case SourceStore.get_or_create_source(SyncJob.source_config()) do
      {:ok, source} -> %{source_id: source.id}
      {:error, reason} -> raise "Failed to create source: #{inspect(reason)}"
    end
  end
end
