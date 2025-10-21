defmodule EventasaurusDiscovery.VenueImages.EnrichmentJob do
  @moduledoc """
  Background job for enriching venues with images from providers.

  Runs periodically to find stale venues (>30 days since last enrichment
  or never enriched) and fetch fresh images from all active providers.

  ## Usage

      # Enqueue job manually
      EnrichmentJob.enqueue()

      # Process single venue
      EnrichmentJob.enqueue_venue(venue_id)

      # Process batch of venues
      EnrichmentJob.enqueue_batch(venue_ids)

  ## Configuration

  Configured in config/config.exs:

      config :eventasaurus, EventasaurusDiscovery.VenueImages.EnrichmentJob,
        batch_size: 100,
        max_retries: 3,
        schedule: "0 2 * * *"  # Daily at 2am

  """

  use Oban.Worker,
    queue: :venue_enrichment,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.VenueImages.Orchestrator
  import Ecto.Query

  @doc """
  Enqueues job to process all stale venues.
  """
  def enqueue do
    %{}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues job to process specific venue.
  """
  def enqueue_venue(venue_id) when is_integer(venue_id) do
    %{venue_id: venue_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues job to process batch of venues.
  """
  def enqueue_batch(venue_ids) when is_list(venue_ids) do
    %{venue_ids: venue_ids}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id}}) do
    Logger.info("🖼️  Processing single venue enrichment: #{venue_id}")

    case Repo.get(Venue, venue_id) do
      nil ->
        Logger.warning("⚠️ Venue #{venue_id} not found")
        {:error, :not_found}

      venue ->
        enrich_single_venue(venue)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_ids" => venue_ids}}) do
    Logger.info("🖼️  Processing batch venue enrichment: #{length(venue_ids)} venues")

    venues = Repo.all(from v in Venue, where: v.id in ^venue_ids)
    enrich_venues_batch(venues)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("🖼️  Starting scheduled venue image enrichment")

    batch_size = get_batch_size()
    stale_venues = find_stale_venues(batch_size)

    if Enum.empty?(stale_venues) do
      Logger.info("✅ No stale venues found")
      :ok
    else
      Logger.info("📊 Found #{length(stale_venues)} stale venues to enrich")
      enrich_venues_batch(stale_venues)
    end
  end

  # Private Functions

  defp find_stale_venues(limit) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-30, :day)

    from(v in Venue,
      where:
        # Never enriched
        is_nil(fragment("? ->> 'last_enriched_at'", v.image_enrichment_metadata)) or
          # No images
          fragment("jsonb_array_length(?) = 0", v.venue_images) or
          # Stale images (>30 days)
          fragment(
            "(? ->> 'last_enriched_at')::timestamp < ?",
            v.image_enrichment_metadata,
            ^cutoff_date
          ),
      # Prioritize venues with coordinates and provider IDs
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      where: fragment("jsonb_typeof(?) = 'object'", v.provider_ids),
      where: fragment("jsonb_object_keys(?) IS NOT NULL", v.provider_ids),
      order_by: [
        desc:
          fragment(
            "COALESCE((? ->> 'last_enriched_at')::timestamp, '1970-01-01'::timestamp)",
            v.image_enrichment_metadata
          )
      ],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp enrich_venues_batch(venues) do
    results = %{
      total: length(venues),
      enriched: 0,
      skipped: 0,
      failed: 0,
      errors: []
    }

    final_results =
      Enum.reduce(venues, results, fn venue, acc ->
        case enrich_single_venue(venue) do
          {:ok, _venue} ->
            %{acc | enriched: acc.enriched + 1}

          {:skip, reason} ->
            Logger.debug("⏭️  Skipped venue #{venue.id}: #{reason}")
            %{acc | skipped: acc.skipped + 1}

          {:error, reason} ->
            error = "Venue #{venue.id}: #{inspect(reason)}"
            Logger.error("❌ #{error}")

            %{
              acc
              | failed: acc.failed + 1,
                errors: [error | acc.errors]
            }
        end
      end)

    Logger.info("""
    📊 Batch enrichment complete:
       - Total: #{final_results.total}
       - Enriched: #{final_results.enriched}
       - Skipped: #{final_results.skipped}
       - Failed: #{final_results.failed}
    """)

    if final_results.failed > 0 do
      {:error, %{results: final_results, errors: Enum.reverse(final_results.errors)}}
    else
      {:ok, final_results}
    end
  end

  defp enrich_single_venue(venue) do
    max_retries = get_max_retries()

    # Check if enrichment is needed
    if Orchestrator.needs_enrichment?(venue) do
      case Orchestrator.enrich_venue(venue, max_retries: max_retries) do
        {:ok, enriched_venue} ->
          Logger.info("✅ Enriched venue #{venue.id} with images")
          {:ok, enriched_venue}

        {:error, reason} ->
          Logger.error("❌ Failed to enrich venue #{venue.id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:skip, :not_stale}
    end
  end

  defp get_batch_size do
    Application.get_env(
      :eventasaurus,
      __MODULE__,
      []
    )
    |> Keyword.get(:batch_size, 100)
  end

  defp get_max_retries do
    Application.get_env(
      :eventasaurus,
      __MODULE__,
      []
    )
    |> Keyword.get(:max_retries, 3)
  end
end
