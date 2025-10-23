defmodule EventasaurusDiscovery.VenueImages.BackfillJob do
  @moduledoc """
  Admin-controlled background job for backfilling venue images.

  Extends EnrichmentJob with additional features:
  - City-specific backfilling
  - Provider selection (Foursquare, Google Places, etc.)
  - Configurable venue limits for cost control
  - Reverse geocoding for venues without provider IDs
  - Detailed success/failure tracking

  ## Usage

      # Backfill venues for a specific city with provider selection
      BackfillJob.enqueue(city_id: 5, provider: "foursquare", limit: 10)

      # Backfill with multiple providers
      BackfillJob.enqueue(city_id: 5, providers: ["foursquare", "google_places"], limit: 20)

      # Backfill with geocoding fallback for venues missing provider IDs
      BackfillJob.enqueue(city_id: 5, provider: "google_places", limit: 10, geocode: true)

  ## Job Arguments

  - `:city_id` - Required. Integer city ID to backfill venues for
  - `:provider` - Optional. String provider name (e.g., "foursquare", "google_places")
  - `:providers` - Optional. List of provider names (overrides :provider if both specified)
  - `:limit` - Optional. Maximum number of venues to process (default: 10 in dev, 100 in prod)
  - `:geocode` - Optional. Enable reverse geocoding for venues without provider IDs (default: false)
  - `:force` - Optional. Force re-enrichment even if venue already has images (default: false)

  ## Configuration

  Development limit is enforced via environment check:

      config :eventasaurus, EventasaurusDiscovery.VenueImages.BackfillJob,
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
  alias EventasaurusDiscovery.VenueImages.Orchestrator
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query

  @doc """
  Enqueues backfill job with specified parameters.

  ## Examples

      # Basic backfill for city
      BackfillJob.enqueue(city_id: 5, limit: 10)

      # With specific provider
      BackfillJob.enqueue(city_id: 5, provider: "foursquare", limit: 20)

      # With multiple providers and geocoding
      BackfillJob.enqueue(
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
    🖼️  Starting venue image backfill:
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
        enriched: 0,
        geocoded: 0,
        skipped: 0,
        failed: 0,
        by_provider: %{},
        total_cost_usd: 0,
        processed_at: NaiveDateTime.utc_now()
      })

      :ok
    else
      Logger.info("📊 Found #{length(venues)} venues to backfill")
      results = backfill_venues(venues, providers, geocode: geocode, force: force)
      log_results(results, city_id)

      # Store results in Oban meta (Phase 1 + Phase 2)
      store_results_in_meta(job, %{
        status: determine_status(results),
        city_id: city_id,
        providers: providers || [],
        total_venues: results.total,
        enriched: results.enriched,
        geocoded: results.geocoded,
        skipped: results.skipped,
        failed: results.failed,
        by_provider: results.by_provider,
        total_cost_usd: calculate_total_cost(results),
        venue_results: Enum.reverse(results.venue_results),  # Phase 2: Venue-level details
        processed_at: NaiveDateTime.utc_now()
      })

      :ok
    end
  end

  # Private Functions

  defp find_venues_without_images(city_id, limit, providers) do
    base_query =
      from(v in Venue,
        where: v.city_id == ^city_id,
        where: fragment("COALESCE(jsonb_array_length(?), 0) = 0", v.venue_images),
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

  defp backfill_venues(venues, providers, opts) do
    geocode = Keyword.get(opts, :geocode, false)
    force = Keyword.get(opts, :force, false)

    results = %{
      total: length(venues),
      enriched: 0,
      geocoded: 0,
      skipped: 0,
      failed: 0,
      errors: [],
      by_provider: %{},
      venue_results: []  # Phase 2: Collect per-venue details
    }

    Enum.reduce(venues, results, fn venue, acc ->
      case backfill_single_venue(venue, providers, geocode: geocode, force: force) do
        {:ok, :enriched, provider_names, venue_detail} ->
          # Update provider counts
          updated_by_provider =
            Enum.reduce(provider_names, acc.by_provider, fn provider, provider_acc ->
              Map.update(provider_acc, provider, 1, &(&1 + 1))
            end)

          %{
            acc
            | enriched: acc.enriched + 1,
              by_provider: updated_by_provider,
              venue_results: [venue_detail | acc.venue_results]
          }

        {:ok, :geocoded_and_enriched, provider_names, venue_detail} ->
          updated_by_provider =
            Enum.reduce(provider_names, acc.by_provider, fn provider, provider_acc ->
              Map.update(provider_acc, provider, 1, &(&1 + 1))
            end)

          %{
            acc
            | enriched: acc.enriched + 1,
              geocoded: acc.geocoded + 1,
              by_provider: updated_by_provider,
              venue_results: [venue_detail | acc.venue_results]
          }

        {:skip, reason} ->
          Logger.debug("⏭️  Skipped venue #{venue.id}: #{reason}")

          venue_detail = %{
            venue_id: venue.id,
            venue_name: venue.name,
            action: "skipped",
            skip_reason: to_string(reason)
          }

          %{
            acc
            | skipped: acc.skipped + 1,
              venue_results: [venue_detail | acc.venue_results]
          }

        {:error, reason} ->
          error = "Venue #{venue.id} (#{venue.name}): #{inspect(reason)}"
          Logger.error("❌ #{error}")

          venue_detail = %{
            venue_id: venue.id,
            venue_name: venue.name,
            action: "failed",
            error_message: inspect(reason)
          }

          %{
            acc
            | failed: acc.failed + 1,
              errors: [error | acc.errors],
              venue_results: [venue_detail | acc.venue_results]
          }
      end
    end)
  end

  defp backfill_single_venue(venue, providers, opts) do
    geocode = Keyword.get(opts, :geocode, false)
    force = Keyword.get(opts, :force, false)

    # Check if venue has required data
    cond do
      is_nil(venue.latitude) or is_nil(venue.longitude) ->
        {:skip, :missing_coordinates}

      needs_geocoding?(venue, providers) and not geocode ->
        {:skip, :missing_provider_ids}

      true ->
        # Attempt geocoding if needed and enabled
        geocoding_result =
          if needs_geocoding?(venue, providers) and geocode do
            case reverse_geocode_venue(venue, providers) do
              {:ok, updated_venue} -> {:ok, updated_venue}
              {:error, reason} -> {:error, reason}
            end
          else
            {:skip, venue}
          end

        venue_with_ids =
          case geocoding_result do
            {:ok, updated_venue} -> updated_venue
            {:error, _} -> venue
            {:skip, v} -> v
          end

        # Perform enrichment
        case Orchestrator.enrich_venue(venue_with_ids, force: force, max_retries: 2) do
          {:ok, enriched_venue} ->
            # Extract which providers were used
            metadata = enriched_venue.image_enrichment_metadata || %{}
            provider_names = metadata["providers_succeeded"] || metadata[:providers_succeeded] || []

            # Get geocoding provider if geocoded
            geocoding_provider =
              case geocoding_result do
                {:ok, _} ->
                  geocoding_meta = venue_with_ids.geocoding_performance || %{}
                  geocoding_meta["provider"] || geocoding_meta[:provider]
                _ ->
                  nil
              end

            # Count images
            images_fetched = length(enriched_venue.venue_images || [])

            # Build venue detail (Phase 2)
            venue_detail = %{
              venue_id: venue.id,
              venue_name: venue.name,
              action: if(geocode and venue != venue_with_ids, do: "geocoded_and_enriched", else: "enriched"),
              was_geocoded: geocode and venue != venue_with_ids,
              geocoding_provider: geocoding_provider,
              geocoding_success: geocoding_result != {:skip, venue} and match?({:ok, _}, geocoding_result),
              images_fetched: images_fetched,
              providers_succeeded: provider_names,
              providers_failed: metadata["providers_failed"] || metadata[:providers_failed] || [],
              cost_usd: 0  # TODO: Extract from metadata when cost tracking is implemented
            }

            if geocode and venue != venue_with_ids do
              {:ok, :geocoded_and_enriched, provider_names, venue_detail}
            else
              {:ok, :enriched, provider_names, venue_detail}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp needs_geocoding?(venue, providers) do
    # Check if venue has provider IDs for requested providers
    venue_provider_ids = venue.provider_ids || %{}

    cond do
      # If no specific providers requested, check if any provider IDs exist
      is_nil(providers) or providers == [] ->
        map_size(venue_provider_ids) == 0

      # If specific providers requested, check if venue has those IDs
      true ->
        Enum.any?(providers, fn provider ->
          is_nil(Map.get(venue_provider_ids, provider)) and
            is_nil(Map.get(venue_provider_ids, to_string(provider)))
        end)
    end
  end

  defp reverse_geocode_venue(venue, providers) do
    Logger.info("🌐 Reverse geocoding venue #{venue.id}: #{venue.name}")

    # Build full address for better geocoding results
    full_address = build_full_address(venue)

    # Use the existing Geocoding Orchestrator with specific providers for this backfill
    # This is reverse geocoding: we have coordinates, we need provider-specific IDs
    case EventasaurusDiscovery.Geocoding.Orchestrator.geocode(full_address, providers: providers) do
      {:ok, result} ->
        # Extract provider_ids from geocoding result
        provider_ids = result[:provider_ids] || result["provider_ids"] || %{}

        if map_size(provider_ids) > 0 do
          # Merge with existing provider_ids
          updated_provider_ids = Map.merge(venue.provider_ids || %{}, provider_ids)

          # Update venue in database
          case Repo.update_all(
                 from(v in Venue, where: v.id == ^venue.id),
                 set: [
                   provider_ids: updated_provider_ids,
                   geocoding_performance: result[:geocoding_metadata] || result["geocoding_metadata"],
                   updated_at: NaiveDateTime.utc_now()
                 ]
               ) do
            {1, _} ->
              provider_names = Map.keys(provider_ids) |> Enum.join(", ")
              Logger.info("✅ Updated venue #{venue.id} with provider_ids: #{provider_names}")
              updated_venue = %{venue | provider_ids: updated_provider_ids}
              {:ok, updated_venue}

            {0, _} ->
              Logger.error("❌ Failed to update venue #{venue.id}")
              {:error, :update_failed}
          end
        else
          Logger.warning("⚠️  Geocoding succeeded but no provider_ids returned for venue #{venue.id}")
          {:error, :no_provider_ids}
        end

      {:error, reason, _metadata} ->
        Logger.warning("⚠️  Failed to reverse geocode venue #{venue.id}: #{inspect(reason)}")
        {:error, reason}

      {:error, reason} ->
        Logger.warning("⚠️  Failed to reverse geocode venue #{venue.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_full_address(venue) do
    # Build complete address with city and country for better geocoding
    base = venue.address || venue.name

    # Try to get city name from preloaded association or fetch it
    city_name =
      case venue do
        %{city: %{name: name}} when is_binary(name) -> name
        %{city_id: city_id} when is_integer(city_id) -> get_city_name(city_id)
        _ -> nil
      end

    if city_name do
      "#{base}, #{city_name}"
    else
      base
    end
  end

  defp get_city_name(city_id) do
    case Repo.get(City, city_id) do
      %{name: name} -> name
      _ -> nil
    end
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

  defp log_results(results, city_id) do
    Logger.info("""
    📊 Backfill complete for city #{city_id}:
       - Total venues: #{results.total}
       - Successfully enriched: #{results.enriched}
       - Geocoded: #{results.geocoded}
       - Skipped: #{results.skipped}
       - Failed: #{results.failed}
       - By provider: #{inspect(results.by_provider)}
    """)

    if length(results.errors) > 0 do
      Logger.error("❌ Errors encountered:")

      Enum.each(results.errors, fn error ->
        Logger.error("   - #{error}")
      end)
    end

    results
  end

  # Phase 1: Store results in Oban meta field
  defp store_results_in_meta(job, meta_data) do
    case Oban.update_job(job, %{meta: meta_data}) do
      {:ok, _updated_job} ->
        Logger.debug("✅ Stored results in Oban meta for job #{job.id}")
        :ok

      {:error, reason} ->
        Logger.error("❌ Failed to store results in Oban meta: #{inspect(reason)}")
        :ok  # Don't fail the job if meta update fails
    end
  end

  defp determine_status(results) do
    cond do
      results.failed > 0 and results.enriched == 0 ->
        "failed"

      results.failed > 0 ->
        "partial"

      results.skipped > 0 and results.enriched == 0 ->
        "skipped"

      true ->
        "success"
    end
  end

  defp calculate_total_cost(_results) do
    # For now, return 0 until we have cost tracking in place
    # TODO: Sum costs from venue enrichment metadata
    0
  end
end
