defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink do
  @moduledoc """
  Geeks Who Drink scraper for trivia events across the United States and Canada.

  This is a regional specialist scraper that provides comprehensive coverage
  of weekly trivia nights from a well-established trivia company.

  ## Features
  - 700+ weekly recurring trivia events
  - GPS coordinates provided directly (no geocoding needed)
  - Performer data (quizmaster profiles)
  - US and Canada national coverage
  - A+ grade city resolution with CityResolver

  ## Data Quality
  - GPS coordinates: ✅ Provided by API
  - City validation: ✅ CityResolver with conservative fallback
  - Event deduplication: ✅ Stable external IDs
  - Recurring events: ✅ Weekly schedule support

  ## Limitations
  - All events are free (no ticket pricing)
  - Limited to Geeks Who Drink branded events
  - Requires WordPress nonce authentication
  """

  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.{
    Source,
    Jobs.SyncJob
  }

  alias EventasaurusDiscovery.Sources.SourceStore

  @doc """
  Start a sync job to fetch events from Geeks Who Drink.

  Options:
  - `:limit` - Maximum number of venues to process (default: all)
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

  # Private functions

  defp ensure_source_exists do
    case SourceStore.get_or_create_source(SyncJob.source_config()) do
      {:ok, source} -> %{source_id: source.id}
      {:error, reason} -> raise "Failed to create source: #{inspect(reason)}"
    end
  end
end
