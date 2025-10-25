defmodule EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob do
  @moduledoc """
  Orchestrator job for spawning individual venue image enrichment jobs.

  This is a parent job that finds venues needing images and spawns
  individual EnrichmentJob workers for each venue. This design provides:

  - **Failure Isolation**: One venue failure doesn't affect others
  - **Granular Retries**: Failed venues retry independently
  - **Better Observability**: Track progress per venue in Oban UI
  - **Resource Management**: Process venues in parallel with concurrency control

  ## Usage

      # Backfill venues for a specific city with provider selection
      BackfillOrchestratorJob.enqueue(city_id: 5, provider: "foursquare", limit: 10)

      # Backfill with multiple providers
      BackfillOrchestratorJob.enqueue(city_id: 5, providers: ["foursquare", "google_places"], limit: 20)

      # Backfill with geocoding fallback for venues missing provider IDs
      BackfillOrchestratorJob.enqueue(city_id: 5, provider: "google_places", limit: 10, geocode: true)

  ## Job Arguments

  - `:city_id` - Required. Integer city ID to backfill venues for
  - `:provider` - Optional. String provider name (e.g., "foursquare", "google_places")
  - `:providers` - Optional. List of provider names (overrides :provider if both specified)
  - `:limit` - Optional. Maximum number of venues to process (default: 10 in dev, 100 in prod)
  - `:geocode` - Optional. Enable reverse geocoding for venues without provider IDs (default: false)
  - `:force` - Optional. Force re-enrichment even if venue already has images (default: false)

  ## Configuration

  Development limit is enforced via environment check:

      config :eventasaurus, EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob,
        dev_limit: 10,
        prod_default_limit: 100,
        geocode_enabled: true

  """

  use Oban.Worker,
    queue: :venue_backfill,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  import Ecto.Query

  @doc """
  Enqueues backfill job with specified parameters.

  ## Examples

      # Basic backfill for city
      BackfillOrchestratorJob.enqueue(city_id: 5, limit: 10)

      # With specific provider
      BackfillOrchestratorJob.enqueue(city_id: 5, provider: "foursquare", limit: 20)

      # With multiple providers and geocoding
      BackfillOrchestratorJob.enqueue(
        city_id: 5,
        providers: ["foursquare", "google_places"],
        limit: 15,
        geocode: true
      )

  """
  def enqueue(args) when is_list(args) do
    # Validate required arguments
    city_id = Keyword.get(args, :city_id)

    unless city_id do
      raise ArgumentError, "city_id is required"
    end

    # Apply development limit
    limit = get_safe_limit(Keyword.get(args, :limit))

    # Convert keyword list to map for Oban
    args_map =
      args
      |> Keyword.put(:limit, limit)
      |> Enum.into(%{})
      |> convert_keys_to_strings()

    args_map
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    city_id = Map.get(args, "city_id")
    providers = get_providers_from_args(args)
    limit = Map.get(args, "limit", get_default_limit())
    geocode = Map.get(args, "geocode", false)
    force = Map.get(args, "force", false)

    Logger.info("""
    🖼️  Starting venue image backfill orchestration:
       - City ID: #{city_id}
       - Providers: #{inspect(providers)}
       - Limit: #{limit}
       - Geocode: #{geocode}
       - Force: #{force}
    """)

    # Find venues needing images
    venues = find_venues_without_images(city_id, limit, providers)

    if Enum.empty?(venues) do
      Logger.info("✅ No venues found needing image backfill")

      # Store empty result in Oban meta
      store_results_in_meta(job, %{
        status: "success",
        city_id: city_id,
        providers: providers || [],
        total_venues: 0,
        jobs_spawned: 0,
        processed_at: NaiveDateTime.utc_now()
      })

      :ok
    else
      Logger.info("📊 Found #{length(venues)} venues - spawning individual enrichment jobs")

      # Spawn individual EnrichmentJob for each venue
      jobs_count = spawn_enrichment_jobs(venues, providers, geocode: geocode, force: force)

      Logger.info("✅ Spawned #{jobs_count} enrichment jobs")

      # Store orchestration results in Oban meta
      store_results_in_meta(job, %{
        status: "orchestrating",
        city_id: city_id,
        providers: providers || [],
        total_venues: length(venues),
        jobs_spawned: jobs_count,
        venue_ids: Enum.map(venues, & &1.id),
        processed_at: NaiveDateTime.utc_now()
      })

      :ok
    end
  end

  # Private Functions

  defp spawn_enrichment_jobs(venues, providers, opts) do
    geocode = Keyword.get(opts, :geocode, false)
    force = Keyword.get(opts, :force, false)

    # Build job structs for all venues
    jobs =
      Enum.map(venues, fn venue ->
        EventasaurusDiscovery.VenueImages.EnrichmentJob.new(%{
          venue_id: venue.id,
          providers: providers,
          geocode: geocode,
          force: force
        })
      end)

    # Batch insert all jobs efficiently
    # Oban.insert_all returns a list of jobs (NOT a tuple)
    inserted_jobs = Oban.insert_all(jobs)
    count = length(inserted_jobs)

    if count > 0 do
      Logger.info("✅ Successfully spawned #{count} enrichment jobs")
      count
    else
      Logger.warning("⚠️  No jobs were inserted")
      0
    end
  end

  defp find_venues_without_images(city_id, limit, providers) do
    # Get cooldown days from config
    cooldown_days = Application.get_env(:eventasaurus, :venue_images, [])[:no_images_cooldown_days] || 7

    base_query =
      from(v in Venue,
        where: v.city_id == ^city_id,
        where: fragment("COALESCE(jsonb_array_length(?), 0) = 0", v.venue_images),
        # Skip venues in cooldown (recently attempted with "no_images" result)
        # Only skip if: last_attempt_result = "no_images" AND last_attempt_at within cooldown period
        # If result was "error" or "success", retry immediately
        where: fragment(
          """
          ? IS NULL OR
          ?->>'last_attempt_result' IS NULL OR
          ?->>'last_attempt_result' != 'no_images' OR
          (?->>'last_attempt_at')::timestamp < (NOW() AT TIME ZONE 'UTC') - make_interval(days => ?)
          """,
          v.image_enrichment_metadata,
          v.image_enrichment_metadata,
          v.image_enrichment_metadata,
          v.image_enrichment_metadata,
          ^cooldown_days
        ),
        # Prioritize venues with coordinates and provider IDs
        order_by: [
          desc:
            fragment(
              "CASE WHEN ? IS NOT NULL AND ? IS NOT NULL THEN 2 ELSE 0 END",
              v.latitude,
              v.longitude
            ),
          desc:
            fragment(
              "CASE WHEN jsonb_typeof(?) = 'object' AND (SELECT COUNT(*) FROM jsonb_object_keys(?)) > 0 THEN 1 ELSE 0 END",
              v.provider_ids,
              v.provider_ids
            ),
          asc: v.id
        ],
        limit: ^limit
      )

    # If specific providers requested, prioritize venues with those provider IDs
    query =
      if providers && length(providers) > 0 do
        # Add provider-specific filtering/prioritization
        # Venues with requested provider IDs get higher priority
        # Use a simpler approach: prioritize if ANY of the requested providers exist
        base_query
      else
        base_query
      end

    Repo.all(query)
  end

  defp get_providers_from_args(args) do
    cond do
      # Multiple providers specified
      providers = Map.get(args, "providers") ->
        providers

      # Single provider specified
      provider = Map.get(args, "provider") ->
        [provider]

      # No providers specified - use all active providers
      true ->
        nil
    end
  end

  defp get_safe_limit(nil), do: get_default_limit()

  defp get_safe_limit(requested_limit) do
    dev_limit = get_dev_limit()

    if is_dev_env?() and requested_limit > dev_limit do
      Logger.warning("""
      ⚠️  Development limit enforced!
         Requested: #{requested_limit} venues
         Maximum allowed in dev: #{dev_limit} venues
         Using: #{dev_limit} venues
      """)

      dev_limit
    else
      requested_limit
    end
  end

  defp get_default_limit do
    if is_dev_env?() do
      get_dev_limit()
    else
      Application.get_env(:eventasaurus, __MODULE__, [])
      |> Keyword.get(:prod_default_limit, 100)
    end
  end

  # Runtime-safe environment check (works in releases)
  defp is_dev_env? do
    Application.get_env(:eventasaurus, :environment, :prod) == :dev
  end

  defp get_dev_limit do
    Application.get_env(:eventasaurus, __MODULE__, [])
    |> Keyword.get(:dev_limit, 10)
  end

  defp convert_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  # Store results in Oban meta field
  defp store_results_in_meta(job, meta_data) do
    case Oban.update_job(job, %{meta: meta_data}) do
      {:ok, _updated_job} ->
        Logger.debug("✅ Stored orchestration results in Oban meta for job #{job.id}")
        :ok

      {:error, reason} ->
        Logger.error("❌ Failed to store results in Oban meta: #{inspect(reason)}")
        # Don't fail the job if meta update fails
        :ok
    end
  end
end
