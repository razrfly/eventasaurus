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
    alias EventasaurusApp.Repo
    alias EventasaurusDiscovery.Sources.Source, as: SourceSchema

    case Repo.get_by(SourceSchema, slug: Source.key()) do
      nil ->
        {:ok, source} =
          Repo.insert(
            SourceSchema.changeset(%SourceSchema{}, %{
              name: Source.name(),
              slug: Source.key(),
              website_url: "https://www.geekswhodrink.com",
              is_active: Source.enabled?(),
              priority: Source.priority(),
              domains: ["trivia", "entertainment"],
              metadata: Source.config()
            })
          )

        %{source_id: source.id}

      source ->
        # Update metadata and domains if changed
        if source.metadata != Source.config() or source.domains != ["trivia", "entertainment"] do
          {:ok, updated} =
            Repo.update(
              SourceSchema.changeset(source, %{
                metadata: Source.config(),
                priority: Source.priority(),
                domains: ["trivia", "entertainment"]
              })
            )

          %{source_id: updated.id}
        else
          %{source_id: source.id}
        end
    end
  end
end
