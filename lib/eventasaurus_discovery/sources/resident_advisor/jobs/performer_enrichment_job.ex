defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.PerformerEnrichmentJob do
  @moduledoc """
  Background job to enrich performer records with Resident Advisor artist data.

  Phase III of the RA performer enrichment system. This job:
  1. Finds performers with RA artist IDs that need enrichment
  2. Updates performer records with metadata from Phase II data
  3. Provides foundation for future scraping-based enrichment

  ## Usage

      # Enrich a specific performer
      %{performer_id: 123}
      |> PerformerEnrichmentJob.new()
      |> Oban.insert()

      # Enrich all RA performers missing data (batch)
      PerformerEnrichmentJob.enrich_all_pending()

  ## Enrichment Strategy

  Currently uses data already available from Phase II:
  - Profile images (if missing)
  - Country information
  - RA profile URLs
  - Source attribution

  Future enhancement: Add web scraping for artist pages to get:
  - Bios/descriptions
  - Social media links
  - Follower counts
  - Genre tags
  """

  use Oban.Worker,
    queue: :enrichment,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Performers.{Performer, PerformerStore}
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  import Ecto.Query

  @doc """
  Perform enrichment for a single performer.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"performer_id" => performer_id}} = job) do
    external_id = "ra_enrichment_performer#{performer_id}_#{Date.utc_today()}"
    Logger.info("Starting RA artist enrichment for performer_id=#{performer_id}")

    case PerformerStore.get_performer(performer_id) do
      nil ->
        Logger.warning("Performer #{performer_id} not found, skipping enrichment")
        # Use standard category for ErrorCategories.categorize_error/1
        # See docs/error-handling-guide.md for category definitions
        MetricsTracker.record_failure(job, :performer_error, external_id)
        :ok

      performer ->
        case enrich_performer(performer) do
          :ok ->
            MetricsTracker.record_success(job, external_id)
            :ok

          {:error, _reason} = error ->
            # Use standard category for ErrorCategories.categorize_error/1
            # See docs/error-handling-guide.md for category definitions
            MetricsTracker.record_failure(job, :performer_error, external_id)

            error
        end
    end
  end

  @doc """
  Enrich all performers with RA artist IDs that need enrichment.

  Returns `{:ok, count}` on success or `{:error, :enqueue_failed}` if any job fails to enqueue.
  Stops at the first failure to prevent partial batch execution.
  """
  def enrich_all_pending do
    performers = find_performers_needing_enrichment()

    result =
      Enum.reduce_while(performers, {:ok, 0}, fn performer, {:ok, acc} ->
        case %{performer_id: performer.id} |> new() |> Oban.insert() do
          {:ok, _job} -> {:cont, {:ok, acc + 1}}
          {:error, changeset} -> {:halt, {:error, {performer.id, changeset}}}
        end
      end)

    case result do
      {:ok, scheduled} ->
        Logger.info("Scheduled enrichment for #{scheduled} RA performers")
        {:ok, scheduled}

      {:error, {performer_id, changeset}} ->
        Logger.error(
          "Failed to enqueue enrichment for performer #{performer_id}: #{inspect(changeset.errors)}"
        )

        {:error, :enqueue_failed}
    end
  end

  @doc """
  Find performers that have RA artist IDs but missing enrichment data.
  """
  def find_performers_needing_enrichment(limit \\ 100) do
    JobRepo.all(
      from(p in Performer,
        where:
          fragment("?->'ra_artist_id' IS NOT NULL", p.metadata) and
            (is_nil(p.image_url) or
               fragment("?->'ra_artist_url' IS NULL", p.metadata) or
               fragment("?->'enriched_at' IS NULL", p.metadata)),
        limit: ^limit
      )
    )
  end

  # Private Functions

  defp enrich_performer(performer) do
    ra_artist_id = get_in(performer.metadata, ["ra_artist_id"])

    if ra_artist_id do
      Logger.debug("Enriching performer #{performer.id} with RA artist_id=#{ra_artist_id}")

      enrichment_data = build_enrichment_data(performer)

      case PerformerStore.update_performer(performer, enrichment_data) do
        {:ok, updated_performer} ->
          Logger.info("""
          Successfully enriched performer #{performer.id}:
            Name: #{updated_performer.name}
            Image: #{updated_performer.image_url || "none"}
            RA URL: #{get_in(updated_performer.metadata, ["ra_artist_url"]) || "none"}
          """)

          :ok

        {:error, changeset} ->
          Logger.error("""
          Failed to enrich performer #{performer.id}:
            Errors: #{inspect(changeset.errors)}
          """)

          {:error, :update_failed}
      end
    else
      Logger.warning("Performer #{performer.id} has no RA artist ID, skipping")
      :ok
    end
  end

  defp build_enrichment_data(performer) do
    metadata = performer.metadata || %{}

    # Build enrichment updates based on available metadata
    updates = %{}

    # Add image_url if missing and we have it in metadata
    updates =
      if is_nil(performer.image_url) && metadata["image_url"] do
        Map.put(updates, :image_url, metadata["image_url"])
      else
        updates
      end

    # Ensure metadata has all RA fields
    metadata_updates = %{
      "ra_artist_id" => metadata["ra_artist_id"],
      "ra_artist_url" => metadata["ra_artist_url"],
      "country" => metadata["country"],
      "country_code" => metadata["country_code"],
      "source" => metadata["source"] || "resident_advisor",
      "enriched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Merge with existing metadata
    updated_metadata = Map.merge(metadata, metadata_updates)

    Map.put(updates, :metadata, updated_metadata)
  end

  @doc """
  Batch enrich performers by scheduling jobs with rate limiting.

  Options:
  - batch_size: Number of jobs to schedule at once (default: 50)
  - delay_seconds: Delay between batches (default: 60)
  """
  def enrich_batch(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 50)
    delay_seconds = Keyword.get(opts, :delay_seconds, 60)

    performers = find_performers_needing_enrichment(batch_size)

    result =
      performers
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, 0}, fn {performer, index}, {:ok, acc} ->
        # Stagger jobs to avoid overwhelming the system
        schedule_in = index * delay_seconds

        case %{performer_id: performer.id} |> new(schedule_in: schedule_in) |> Oban.insert() do
          {:ok, _job} -> {:cont, {:ok, acc + 1}}
          {:error, changeset} -> {:halt, {:error, {performer.id, changeset}}}
        end
      end)

    case result do
      {:ok, scheduled} ->
        Logger.info("Scheduled batch enrichment for #{scheduled} performers")
        {:ok, scheduled}

      {:error, {performer_id, changeset}} ->
        Logger.error(
          "Failed to enqueue batch enrichment for performer #{performer_id}: #{inspect(changeset.errors)}"
        )

        {:error, :enqueue_failed}
    end
  end

  @doc """
  Get enrichment statistics.
  """
  def enrichment_stats do
    total_ra_performers =
      JobRepo.one(
        from(p in Performer,
          where: fragment("?->'ra_artist_id' IS NOT NULL", p.metadata),
          select: count(p.id)
        )
      )

    enriched_performers =
      JobRepo.one(
        from(p in Performer,
          where:
            fragment("?->'ra_artist_id' IS NOT NULL", p.metadata) and
              fragment("?->'enriched_at' IS NOT NULL", p.metadata),
          select: count(p.id)
        )
      )

    performers_with_images =
      JobRepo.one(
        from(p in Performer,
          where:
            fragment("?->'ra_artist_id' IS NOT NULL", p.metadata) and
              not is_nil(p.image_url),
          select: count(p.id)
        )
      )

    %{
      total_ra_performers: total_ra_performers,
      enriched_performers: enriched_performers,
      performers_with_images: performers_with_images,
      pending_enrichment: total_ra_performers - enriched_performers,
      enrichment_percentage:
        if(total_ra_performers > 0,
          do: Float.round(enriched_performers / total_ra_performers * 100, 2),
          else: 0.0
        )
    }
  end
end
