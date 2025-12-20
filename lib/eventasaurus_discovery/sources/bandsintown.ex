defmodule EventasaurusDiscovery.Sources.Bandsintown do
  @moduledoc """
  Bandsintown scraper for international concert and live music events.

  This is a high-priority international scraper that provides comprehensive
  coverage of live music events worldwide.

  ## Features
  - City-based event discovery via web scraping
  - GPS coordinates via JSON-LD structured data
  - Comprehensive artist/performer data
  - Pagination support for complete coverage
  - Cross-source deduplication with priority handling

  ## Limitations
  - Requires JavaScript rendering for initial city pages (via Playwright)
  - Rate limiting recommended (2-3s between requests)
  - Some events may have placeholder venues when venue data unavailable
  """

  alias EventasaurusDiscovery.Sources.Bandsintown.{
    Source,
    Config,
    Jobs.SyncJob,
    DedupHandler
  }

  alias EventasaurusDiscovery.Sources.SourceStore

  @doc """
  Start a sync job to fetch events from Bandsintown.

  Options:
  - `:cities` - List of city slugs to scrape (default: configured cities)
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

  Checks if event exists from higher-priority sources (Ticketmaster).
  Validates event quality before processing.

  ## Parameters
  - `event_data` - Event data with external_id, title, starts_at, venue_data
  - `source` - Source struct with priority and domains

  ## Returns
  - `{:unique, event_data}` - Event is unique, proceed with import
  - `{:duplicate, existing}` - Event already exists (same source or higher priority)
  - `{:enriched, event_data}` - Event enriched with additional data
  - `{:error, reason}` - Event validation failed
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
    case SourceStore.get_or_create_source(Config.source_config()) do
      {:ok, source} -> %{source_id: source.id}
      {:error, reason} -> raise "Failed to create source: #{inspect(reason)}"
    end
  end
end
