defmodule EventasaurusDiscovery.Sources.Waw4Free do
  @moduledoc """
  Waw4Free Warsaw scraper for free events in Warsaw, Poland.

  This is a lower-priority, localized scraper that focuses exclusively
  on FREE events in Warsaw (Warszawa).

  ## Features
  - HTML scraping (no API available)
  - Polish language support
  - All events are FREE
  - Category-based discovery (8 categories)
  - District-level filtering for Warsaw neighborhoods
  - Single-page category listings (no pagination)

  ## Limitations
  - Warsaw-only events
  - No performer information
  - No ticket information (all events are free)
  - Lower priority than international sources
  """

  alias EventasaurusDiscovery.Sources.Waw4Free.{
    Source,
    Jobs.SyncJob,
    DedupHandler
  }

  alias EventasaurusDiscovery.Sources.SourceStore

  @doc """
  Start a sync job to fetch events from Waw4Free.

  Options:
  - `:max_pages` - Maximum number of category pages to fetch (default: 1, no pagination)
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
    # validate_event_quality always returns {:ok, validated} in current implementation
    {:ok, validated} = DedupHandler.validate_event_quality(event_data)
    DedupHandler.check_duplicate(validated, source)
  end

  # Private functions

  defp ensure_source_exists do
    case SourceStore.get_or_create_source(SyncJob.source_config()) do
      {:ok, source} -> %{source_id: source.id}
      {:error, reason} -> raise "Failed to create source: #{inspect(reason)}"
    end
  end
end
