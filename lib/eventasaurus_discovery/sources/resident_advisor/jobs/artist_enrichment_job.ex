defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Jobs.ArtistEnrichmentJob do
  @moduledoc """
  Background job to enrich performer records with Resident Advisor artist data.

  Phase III of the RA performer enrichment system. This job:
  1. Finds performers with RA artist IDs that need enrichment
  2. Updates performer records with metadata from Phase II data
  3. Provides foundation for future scraping-based enrichment

  ## Usage

      # Enrich a specific performer
      %{performer_id: 123}
      |> ArtistEnrichmentJob.new()
      |> Oban.insert()

      # Enrich all RA performers missing data (batch)
      ArtistEnrichmentJob.enrich_all_pending()

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
  alias EventasaurusApp.Repo

  import Ecto.Query

  @doc """
  Perform enrichment for a single performer.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"performer_id" => performer_id}}) do
    Logger.info("Starting RA artist enrichment for performer_id=#{performer_id}")

    case PerformerStore.get_performer(performer_id) do
      nil ->
        Logger.warning("Performer #{performer_id} not found, skipping enrichment")
        :ok

      performer ->
        enrich_performer(performer)
    end
  end

  @doc """
  Enrich all performers with RA artist IDs that need enrichment.

  Returns count of jobs scheduled.
  """
  def enrich_all_pending do
    performers = find_performers_needing_enrichment()
    count = length(performers)

    Logger.info("Scheduling enrichment for #{count} RA performers")

    performers
    |> Enum.each(fn performer ->
      %{performer_id: performer.id}
      |> new()
      |> Oban.insert()
    end)

    {:ok, count}
  end

  @doc """
  Find performers that have RA artist IDs but missing enrichment data.
  """
  def find_performers_needing_enrichment(limit \\ 100) do
    Repo.all(
      from p in Performer,
        where:
          fragment("?->'ra_artist_id' IS NOT NULL", p.metadata) and
            (is_nil(p.image_url) or
               fragment("?->'ra_artist_url' IS NULL", p.metadata)),
        limit: ^limit
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
    count = length(performers)

    Logger.info("Scheduling batch enrichment for #{count} performers")

    performers
    |> Enum.with_index()
    |> Enum.each(fn {performer, index} ->
      # Stagger jobs to avoid overwhelming the system
      schedule_in = index * delay_seconds

      %{performer_id: performer.id}
      |> new(schedule_in: schedule_in)
      |> Oban.insert()
    end)

    {:ok, count}
  end

  @doc """
  Get enrichment statistics.
  """
  def enrichment_stats do
    total_ra_performers =
      Repo.one(
        from p in Performer,
          where: fragment("?->'ra_artist_id' IS NOT NULL", p.metadata),
          select: count(p.id)
      )

    enriched_performers =
      Repo.one(
        from p in Performer,
          where:
            fragment("?->'ra_artist_id' IS NOT NULL", p.metadata) and
              fragment("?->'enriched_at' IS NOT NULL", p.metadata),
          select: count(p.id)
      )

    performers_with_images =
      Repo.one(
        from p in Performer,
          where:
            fragment("?->'ra_artist_id' IS NOT NULL", p.metadata) and
              not is_nil(p.image_url),
          select: count(p.id)
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
