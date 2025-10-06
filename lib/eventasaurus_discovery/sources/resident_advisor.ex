defmodule EventasaurusDiscovery.Sources.ResidentAdvisor do
  @moduledoc """
  Resident Advisor scraper for international electronic music events.

  This is a high-priority international scraper that provides comprehensive
  coverage of electronic music events worldwide using RA's GraphQL API.

  ## Features
  - GraphQL API integration (no HTML scraping)
  - Multi-city support via area ID mapping
  - Rich event metadata (artists, images, editorial picks)
  - Multi-strategy venue geocoding (GraphQL → Google Places → city center)
  - Ticketing information and attendance tracking

  ## Limitations
  - Requires manual area ID discovery via DevTools for new cities
  - Venue coordinates not in GraphQL, requires geocoding enrichment
  - Limited performer details in event listings
  - Rate limited to prevent API abuse

  ## Usage

  Start a sync job for a city:

      iex> city = Repo.get_by(City, name: "London")
      iex> ResidentAdvisor.sync(%{city_id: city.id, area_id: 34})
      {:ok, %Oban.Job{}}

  Check source status:

      iex> ResidentAdvisor.enabled?()
      true

      iex> ResidentAdvisor.validate()
      {:ok, "Resident Advisor source configuration valid"}

  ## Configuration

  Environment variables:
  - `RESIDENT_ADVISOR_ENABLED` - Enable/disable source (default: true)

  Application config:
  - `:resident_advisor_enabled` - Override via config

  ## Area ID Mapping

  Area IDs must be discovered manually via browser DevTools:
  1. Visit https://ra.co/events/{country}/{city}
  2. Open DevTools → Network → Filter "graphql"
  3. Find `variables.filters.areas.eq` value (integer)
  4. Add to AreaMapper module

  See `EventasaurusDiscovery.Sources.ResidentAdvisor.Helpers.AreaMapper` for
  current mappings and discovery process.
  """

  alias EventasaurusDiscovery.Sources.ResidentAdvisor.{
    Source,
    Jobs.SyncJob,
    DedupHandler
  }

  @doc """
  Start a sync job to fetch events from Resident Advisor for a specific city.

  ## Required Options
  - `:city_id` - Database ID of the city to sync
  - `:area_id` - RA integer area ID (see AreaMapper)

  ## Optional Options
  - `:start_date` - ISO date string (default: today)
  - `:end_date` - ISO date string (default: today + 30 days)
  - `:page_size` - Results per page (default: 20)

  ## Examples

      iex> city = Repo.get_by(City, name: "London")
      iex> ResidentAdvisor.sync(%{city_id: city.id, area_id: 34})
      {:ok, %Oban.Job{}}

      iex> ResidentAdvisor.sync(%{
      ...>   city_id: city.id,
      ...>   area_id: 34,
      ...>   start_date: "2025-10-06",
      ...>   end_date: "2025-11-06"
      ...> })
      {:ok, %Oban.Job{}}
  """
  def sync(options \\ %{}) do
    if Source.enabled?() do
      # Validate required options
      with :ok <- validate_sync_options(options) do
        args = Source.sync_job_args(options)

        %{source_id: source_id} = ensure_source_exists()
        args = Map.put(args, "source_id", source_id)

        {:ok, job} = Oban.insert(SyncJob.new(args))
        {:ok, job}
      end
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

  Tests GraphQL endpoint accessibility and verifies job modules are loaded.

  Returns:
  - `{:ok, message}` - Configuration is valid
  - `{:error, reason}` - Configuration or connectivity issue
  """
  def validate, do: Source.validate_config()

  @doc """
  Process an event through deduplication.

  Checks if event exists from higher-priority sources (Ticketmaster, Bandsintown).
  Validates event quality before processing.
  Detects umbrella events and creates containers instead of regular events.

  Returns:
  - `{:unique, event_data}` - Event is unique, proceed with import
  - `{:duplicate, existing}` - Event exists from higher-priority source
  - `{:enriched, event_data}` - Event enriched with additional data
  - `{:container, container}` - Umbrella event created as container
  - `{:error, reason}` - Event validation failed
  """
  def deduplicate_event(event_data) do
    case DedupHandler.validate_event_quality(event_data) do
      {:ok, validated} ->
        DedupHandler.check_duplicate(validated)

      {:container, container} ->
        # Umbrella event was created as container, don't import as regular event
        {:container, container}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp validate_sync_options(options) do
    cond do
      is_nil(options[:city_id]) ->
        {:error, "city_id is required"}

      is_nil(options[:area_id]) ->
        {:error, "area_id is required (see AreaMapper for city mappings)"}

      true ->
        :ok
    end
  end

  defp ensure_source_exists do
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Sources.Source, as: SourceSchema

    case Repo.get_by(SourceSchema, slug: Source.key()) do
      nil ->
        {:ok, source} =
          Repo.insert(
            SourceSchema.changeset(%SourceSchema{}, %{
              name: Source.name(),
              slug: Source.key(),
              website_url: "https://ra.co",
              is_active: Source.enabled?(),
              priority: Source.priority(),
              metadata: Source.config()
            })
          )

        %{source_id: source.id}

      source ->
        # Update metadata if changed
        if source.metadata != Source.config() do
          {:ok, updated} =
            Repo.update(
              SourceSchema.changeset(source, %{
                metadata: Source.config(),
                priority: Source.priority()
              })
            )

          %{source_id: updated.id}
        else
          %{source_id: source.id}
        end
    end
  end
end
