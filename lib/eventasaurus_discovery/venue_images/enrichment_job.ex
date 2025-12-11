defmodule EventasaurusDiscovery.VenueImages.EnrichmentJob do
  @moduledoc """
  Background job for enriching venues with images from providers.

  Runs periodically to find stale venues (>30 days since last enrichment
  or never enriched) and fetch fresh images from all active providers.

  ## Usage

      # Scheduled enrichment (SQL pre-filtering, efficient)
      EnrichmentJob.enqueue()

      # Single venue enrichment
      EnrichmentJob.enqueue_venue(venue_id)

      # Batch enrichment (processes venues in ONE job)
      EnrichmentJob.enqueue_batch(venue_ids)

      # Bulk enqueueing with pre-filtering (RECOMMENDED for 10+ venues)
      # Creates individual jobs only for stale venues
      venue_ids = [1, 2, 3, ..., 300]
      EnrichmentJob.enqueue_stale_venues(venue_ids)
      # => {:ok, 90}  # Only 90 jobs created (70% filtered out)

  ## When to Use Each Method

  - `enqueue()` - Scheduled/automated enrichment runs (uses SQL filtering)
  - `enqueue_venue(id)` - Single venue updates or admin UI actions
  - `enqueue_batch(ids)` - Process multiple venues in ONE worker (e.g., city backfill)
  - `enqueue_stale_venues(ids)` - Bulk manual operations (creates jobs only for stale venues)

  **AVOID:** Looping `enqueue_venue/1` for bulk operations - creates wasteful jobs that immediately skip.
  **INSTEAD:** Use `enqueue_stale_venues/1` to pre-filter and reduce resource waste by 60-70%.

  ## Configuration

  Configured in config/config.exs:

      config :eventasaurus, EventasaurusDiscovery.VenueImages.EnrichmentJob,
        batch_size: 100,
        max_retries: 3,
        schedule: "0 2 * * *"  # Daily at 2am

  """

  use Oban.Worker,
    queue: :venue,
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

  @doc """
  Enqueues enrichment jobs for stale venues only (pre-filtered).

  Uses `Orchestrator.needs_enrichment?/1` to filter venues before creating jobs,
  reducing resource waste for bulk operations.

  ## Usage

      # Bulk operations (preferred for 10+ venues)
      venue_ids = [1, 2, 3, ..., 300]
      EnrichmentJob.enqueue_stale_venues(venue_ids)
      # => {:ok, 90}  # Only creates jobs for stale venues

      # With options
      EnrichmentJob.enqueue_stale_venues(venue_ids, force: true, providers: ["google_places"])

  ## Options

  - `:force` - Skip staleness check and enqueue all venues (default: false)
  - `:providers` - Specific providers to use (default: all active providers)

  ## Returns

  - `{:ok, count}` - Number of jobs enqueued
  - `{:error, reason}` - If batch insert fails
  """
  def enqueue_stale_venues(venue_ids, opts \\ []) when is_list(venue_ids) do
    force = Keyword.get(opts, :force, false)
    providers = Keyword.get(opts, :providers)

    # Load venues; JSON fields like venue_images are part of the struct
    venues = Repo.all(from(v in Venue, where: v.id in ^venue_ids))

    # Pre-filter using existing staleness logic
    stale_venues =
      if force do
        venues
      else
        Enum.filter(venues, &Orchestrator.needs_enrichment?/1)
      end

    # Log filtering results
    filtered_count = length(venues) - length(stale_venues)

    Logger.info("""
    🔍 Venue Enrichment Pre-filtering:
      Total venues: #{length(venues)}
      Stale venues: #{length(stale_venues)}
      Filtered (skipped): #{filtered_count}
    """)

    # Batch insert only stale venues
    # Build job args with only the parameters that should be in the job
    jobs =
      Enum.map(stale_venues, fn venue ->
        job_args = %{venue_id: venue.id}
        job_args = if providers, do: Map.put(job_args, :providers, providers), else: job_args
        new(job_args)
      end)

    # Oban.insert_all returns a list of inserted jobs on success
    try do
      inserted_jobs = Oban.insert_all(jobs)
      count = length(inserted_jobs)
      Logger.info("✅ Enqueued #{count} venue enrichment jobs")
      {:ok, count}
    rescue
      e ->
        Logger.error("❌ Failed to enqueue jobs: #{inspect(e)}")
        {:error, e}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id} = args} = job) do
    providers = Map.get(args, "providers")
    geocode = Map.get(args, "geocode", false)
    force = Map.get(args, "force", false)

    start_time = DateTime.utc_now()

    Logger.info("""
    🖼️  Processing single venue enrichment:
       - Venue ID: #{venue_id}
       - Providers: #{inspect(providers)}
       - Geocode: #{geocode}
       - Force: #{force}
    """)

    case Repo.get(Venue, venue_id) do
      nil ->
        Logger.warning("⚠️ Venue #{venue_id} not found")
        update_job_meta(job, build_error_metadata("Venue not found", start_time))
        {:discard, :not_found}

      venue ->
        # Handle backfill-specific processing
        case enrich_single_venue(venue, providers: providers, geocode: geocode, force: force) do
          {:ok, enriched_venue} ->
            # Check if we actually got images
            images_count = length(enriched_venue.venue_images || [])

            # Build and update job metadata
            metadata = build_success_metadata(enriched_venue, start_time)
            update_job_meta(job, metadata)

            if images_count > 0 do
              Logger.info("✅ Venue #{venue_id} enriched with #{images_count} images")
              :ok
            else
              # Extract error details from metadata
              metadata = enriched_venue.image_enrichment_metadata || %{}
              providers_failed = metadata["providers_failed"] || metadata[:providers_failed] || []
              error_details = metadata["error_details"] || metadata[:error_details] || %{}

              if Enum.empty?(providers_failed) do
                Logger.warning(
                  "⚠️  Venue #{venue_id} enrichment completed but no images fetched (no errors reported)"
                )

                :ok
              else
                # Check if ANY error is a permanent failure (API auth, config issues)
                any_permanent? =
                  Enum.any?(providers_failed, fn provider ->
                    error =
                      Map.get(error_details, provider) ||
                        Map.get(error_details, to_string(provider))

                    permanent_failure?(error)
                  end)

                # Check if ANY error is retryable (rate limits, timeouts, server errors)
                any_retryable? =
                  Enum.any?(providers_failed, fn provider ->
                    error =
                      Map.get(error_details, provider) ||
                        Map.get(error_details, to_string(provider))

                    retryable_error?(error)
                  end)

                # Build error message with actual provider errors
                error_messages = build_error_messages(providers_failed, error_details)

                cond do
                  any_permanent? ->
                    Logger.error(
                      "❌ Venue #{venue_id} failed with permanent error: #{error_messages}"
                    )

                    {:error, "API authentication/configuration error: #{error_messages}"}

                  any_retryable? ->
                    Logger.error(
                      "❌ Venue #{venue_id} failed with retryable error: #{error_messages}"
                    )

                    {:error, "Transient error (will retry): #{error_messages}"}

                  true ->
                    # Providers failed but errors are neither permanent nor retryable
                    # This is the "no images available" case (e.g., ZERO_RESULTS)
                    Logger.info("ℹ️  Venue #{venue_id} completed but no images: #{error_messages}")

                    :ok
                end
              end
            end

          {:skip, reason} ->
            Logger.info("⏭️  Skipped venue #{venue_id}: #{reason}")

            update_job_meta(job, %{
              status: "skipped",
              reason: to_string(reason),
              execution_time_ms: DateTime.diff(DateTime.utc_now(), start_time, :millisecond)
            })

            :ok

          {:error, reason} ->
            Logger.error("❌ Failed to enrich venue #{venue_id}: #{inspect(reason)}")
            update_job_meta(job, build_error_metadata(reason, start_time, venue))
            {:error, reason}
        end
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_ids" => venue_ids}} = job) do
    start_time = DateTime.utc_now()
    Logger.info("🖼️  Processing batch venue enrichment: #{length(venue_ids)} venues")

    venues = Repo.all(from(v in Venue, where: v.id in ^venue_ids))
    {:ok, results} = enrich_venues_batch(venues)

    # Build batch metadata
    execution_time = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)

    metadata = %{
      status: "batch_completed",
      total_venues: results.total,
      enriched: results.enriched,
      skipped: results.skipped,
      failed: results.failed,
      execution_time_ms: execution_time,
      completed_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    update_job_meta(job, metadata)
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args} = job) do
    start_time = DateTime.utc_now()
    Logger.info("🖼️  Starting scheduled venue image enrichment")

    batch_size = get_batch_size()
    stale_venues = find_stale_venues(batch_size)

    if Enum.empty?(stale_venues) do
      Logger.info("✅ No stale venues found")

      update_job_meta(job, %{
        status: "no_work",
        message: "No stale venues found",
        execution_time_ms: DateTime.diff(DateTime.utc_now(), start_time, :millisecond)
      })

      :ok
    else
      Logger.info("📊 Found #{length(stale_venues)} stale venues to enrich")
      {:ok, results} = enrich_venues_batch(stale_venues)

      # Build scheduled batch metadata
      execution_time = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)

      metadata = %{
        status: "scheduled_batch_completed",
        total_venues: results.total,
        enriched: results.enriched,
        skipped: results.skipped,
        failed: results.failed,
        execution_time_ms: execution_time,
        completed_at: DateTime.to_iso8601(DateTime.utc_now())
      }

      update_job_meta(job, metadata)
      :ok
    end
  end

  # Private Functions

  defp find_stale_venues(limit) do
    cutoff_date =
      DateTime.utc_now()
      |> DateTime.add(-30, :day)
      |> DateTime.to_naive()

    from(v in Venue,
      # Never enriched
      # No images (handle NULL venue_images)
      # Stale images (>30 days)
      where:
        is_nil(fragment("? ->> 'last_enriched_at'", v.image_enrichment_metadata)) or
          fragment("COALESCE(jsonb_array_length(?), 0) = 0", v.venue_images) or
          fragment(
            "(? ->> 'last_enriched_at')::timestamp < ?::timestamp",
            v.image_enrichment_metadata,
            ^cutoff_date
          ),
      # Prioritize venues with coordinates and provider IDs
      where: not is_nil(v.latitude) and not is_nil(v.longitude),
      where: fragment("jsonb_typeof(?) = 'object'", v.provider_ids),
      # Check if provider_ids has at least one key (count keys using jsonb_object_keys)
      where: fragment("(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 0", v.provider_ids),
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

    # Always return :ok for batch jobs - failures are logged internally
    {:ok, final_results}
  end

  defp enrich_single_venue(venue, opts \\ []) do
    max_retries = get_max_retries()
    providers = Keyword.get(opts, :providers)
    geocode = Keyword.get(opts, :geocode, false)
    force = Keyword.get(opts, :force, false)

    # Check if enrichment is needed (or forced)
    if force or Orchestrator.needs_enrichment?(venue) do
      # Handle geocoding if requested and venue needs it
      venue_with_ids =
        if geocode and needs_geocoding?(venue, providers) do
          case reverse_geocode_venue(venue, providers) do
            {:ok, updated_venue} -> updated_venue
            # Continue with original venue if geocoding fails
            {:error, _reason} -> venue
          end
        else
          venue
        end

      # Build enrichment options
      enrichment_opts = [
        max_retries: max_retries
      ]

      enrichment_opts =
        if providers,
          do: Keyword.put(enrichment_opts, :providers, providers),
          else: enrichment_opts

      enrichment_opts =
        if force, do: Keyword.put(enrichment_opts, :force, force), else: enrichment_opts

      # Enrich the venue
      case Orchestrator.enrich_venue(venue_with_ids, enrichment_opts) do
        {:ok, enriched_venue} ->
          {:ok, enriched_venue}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:skip, :not_stale}
    end
  end

  defp needs_geocoding?(venue, providers) do
    venue_provider_ids = venue.provider_ids || %{}

    cond do
      # Missing coordinates
      is_nil(venue.latitude) or is_nil(venue.longitude) ->
        false

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

    # For google_places image enrichment, we need BUSINESS place_ids not ADDRESS place_ids
    # Use nearby search instead of geocoding API
    if providers == ["google_places"] or providers == [:google_places] do
      get_google_places_business_id(venue)
    else
      # For other providers, use standard geocoding
      get_provider_ids_via_geocoding(venue, providers)
    end
  end

  defp get_google_places_business_id(venue) do
    Logger.info("🔍 Finding Google Places business ID for venue #{venue.id}: #{venue.name}")

    # Use Nearby Search to find the actual business
    case search_nearby_business(venue) do
      {:ok, place_id} ->
        updated_provider_ids =
          Map.merge(venue.provider_ids || %{}, %{"google_places" => place_id})

        # Update venue in database
        case Repo.update_all(
               from(v in Venue, where: v.id == ^venue.id),
               set: [
                 provider_ids: updated_provider_ids,
                 updated_at: NaiveDateTime.utc_now()
               ]
             ) do
          {1, _} ->
            Logger.info("✅ Updated venue #{venue.id} with Google Places business ID")
            {:ok, %{venue | provider_ids: updated_provider_ids}}

          {0, _} ->
            {:error, :update_failed}
        end

      {:error, reason} ->
        Logger.warning(
          "⚠️ Could not find Google Places business ID for venue #{venue.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp search_nearby_business(venue) do
    api_key = System.get_env("GOOGLE_MAPS_API_KEY")

    if is_nil(api_key) do
      {:error, :api_key_missing}
    else
      # Use Nearby Search to find businesses at this location
      url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"

      params = [
        location: "#{venue.latitude},#{venue.longitude}",
        # 50 meter radius
        radius: 50,
        key: api_key
      ]

      query = URI.encode_query(params)

      case HTTPoison.get("#{url}?#{query}", [], recv_timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case parse_nearby_search_response(body, venue) do
            {:ok, place_id} ->
              # Validate that this is a business, not an address
              validate_business_place_id(place_id, api_key, venue)

            error ->
              error
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          Logger.error("❌ Google Nearby Search HTTP #{status}")
          {:error, "HTTP #{status}"}

        {:error, %HTTPoison.Error{reason: :timeout}} ->
          {:error, :timeout}

        {:error, _} ->
          {:error, :network_error}
      end
    end
  end

  defp validate_business_place_id(place_id, api_key, venue) do
    # Call Place Details to verify this is a business, not an address
    url = "https://maps.googleapis.com/maps/api/place/details/json"

    params = [
      place_id: place_id,
      fields: "name,types,photos",
      key: api_key
    ]

    query = URI.encode_query(params)

    case HTTPoison.get("#{url}?#{query}", [], recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"result" => result, "status" => "OK"}} ->
            place_name = Map.get(result, "name", "Unknown")
            place_types = Map.get(result, "types", [])
            photo_count = length(Map.get(result, "photos", []))

            # Check if this is an address (reject) or business (accept)
            cond do
              is_address_place_id?(place_types) ->
                Logger.warning("""
                ⚠️  Venue #{venue.id} (#{venue.name}): Rejected address place_id
                   - Place Name: #{place_name}
                   - Types: #{inspect(place_types)}
                   - Photos: #{photo_count}
                   - Reason: This is a street address, not a business
                """)

                {:error, {:address_not_business, place_name, place_types}}

              is_business_place_id?(place_types) ->
                Logger.info("""
                ✅ Venue #{venue.id} (#{venue.name}): Valid business place_id
                   - Place Name: #{place_name}
                   - Types: #{inspect(Enum.take(place_types, 3))}
                   - Photos: #{photo_count}
                """)

                {:ok, place_id}

              true ->
                Logger.warning("""
                ⚠️  Venue #{venue.id} (#{venue.name}): Uncertain place_id type
                   - Place Name: #{place_name}
                   - Types: #{inspect(place_types)}
                   - Photos: #{photo_count}
                   - Accepting anyway (has #{photo_count} photos)
                """)

                {:ok, place_id}
            end

          {:ok, %{"status" => status}} ->
            Logger.error("❌ Place Details validation error: #{status}")
            # If validation fails, accept the place_id anyway (don't block enrichment)
            {:ok, place_id}

          _ ->
            # If we can't validate, accept anyway
            {:ok, place_id}
        end

      _ ->
        # If validation call fails, accept the place_id anyway
        {:ok, place_id}
    end
  end

  # Address types that should be rejected (no photos)
  defp is_address_place_id?(types) when is_list(types) do
    address_types = ["street_address", "premise", "subpremise", "route"]
    Enum.any?(types, fn type -> type in address_types end)
  end

  defp is_address_place_id?(_), do: false

  # Business types that should be accepted (has photos)
  defp is_business_place_id?(types) when is_list(types) do
    business_types = [
      "bar",
      "restaurant",
      "night_club",
      "museum",
      "cafe",
      "store",
      "establishment",
      "point_of_interest",
      "tourist_attraction",
      "lodging",
      "food",
      "shopping_mall"
    ]

    Enum.any?(types, fn type -> type in business_types end)
  end

  defp is_business_place_id?(_), do: false

  defp parse_nearby_search_response(body, venue) do
    case Jason.decode(body) do
      {:ok, %{"results" => results, "status" => "OK"}}
      when is_list(results) and length(results) > 0 ->
        # Try to find best matching result by name similarity
        best_match =
          Enum.find(results, fn result ->
            result_name = Map.get(result, "name", "")
            venue_name = venue.name || ""

            # Simple name matching - could be improved with fuzzy matching
            String.downcase(result_name) == String.downcase(venue_name) or
              String.contains?(String.downcase(result_name), String.downcase(venue_name)) or
              String.contains?(String.downcase(venue_name), String.downcase(result_name))
          end)

        # If no name match, use first result (closest by distance)
        result = best_match || List.first(results)
        place_id = Map.get(result, "place_id")

        if place_id do
          Logger.info("✅ Found candidate place_id for #{venue.name}")
          {:ok, place_id}
        else
          {:error, :no_place_id}
        end

      {:ok, %{"status" => "ZERO_RESULTS"}} ->
        {:error, :no_results}

      {:ok, %{"status" => status}} ->
        Logger.error("❌ Google Nearby Search error: #{status}")
        {:error, "API error: #{status}"}

      {:error, reason} ->
        {:error, {:json_decode, reason}}
    end
  end

  defp get_provider_ids_via_geocoding(venue, providers) do
    # Build full address
    full_address = build_full_address(venue)

    # Use Geocoding Orchestrator to get provider IDs
    case EventasaurusDiscovery.Geocoding.Orchestrator.geocode(full_address, providers: providers) do
      {:ok, result} ->
        provider_ids = result[:provider_ids] || result["provider_ids"] || %{}

        if map_size(provider_ids) > 0 do
          updated_provider_ids = Map.merge(venue.provider_ids || %{}, provider_ids)

          # Update venue in database
          case Repo.update_all(
                 from(v in Venue, where: v.id == ^venue.id),
                 set: [
                   provider_ids: updated_provider_ids,
                   geocoding_performance:
                     result[:geocoding_metadata] || result["geocoding_metadata"],
                   updated_at: NaiveDateTime.utc_now()
                 ]
               ) do
            {1, _} ->
              provider_names = Map.keys(provider_ids) |> Enum.join(", ")
              Logger.info("✅ Updated venue #{venue.id} with provider_ids: #{provider_names}")
              {:ok, %{venue | provider_ids: updated_provider_ids}}

            {0, _} ->
              {:error, :update_failed}
          end
        else
          {:error, :no_provider_ids}
        end

      {:error, reason, _metadata} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_full_address(venue) do
    base = venue.address || venue.name

    city_name =
      case venue do
        %{city: %{name: name}} when is_binary(name) ->
          name

        %{city_id: city_id} when is_integer(city_id) ->
          case Repo.get(EventasaurusDiscovery.Locations.City, city_id) do
            %{name: name} -> name
            _ -> nil
          end

        _ ->
          nil
      end

    if city_name, do: "#{base}, #{city_name}", else: base
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

  # Metadata Building Functions

  defp update_job_meta(job, metadata) do
    try do
      job
      |> Ecto.Changeset.change(meta: metadata)
      |> Repo.update()
    rescue
      e ->
        Logger.warning("⚠️ Failed to update job metadata: #{inspect(e)}")
        :ok
    end
  end

  # Determines the correct job status by distinguishing between:
  # - "success": Images were successfully fetched and uploaded
  # - "error": Providers failed with API errors (INVALID_REQUEST, auth failures, etc.)
  # - "no_images": Providers explicitly said no images available (ZERO_RESULTS)
  defp determine_job_status(successful_images, providers_failed, metadata) do
    cond do
      # If we got images (uploaded or skipped_dev), it's a success
      length(successful_images) > 0 ->
        "success"

      # If no providers failed, but we have no images, treat as no_images
      # (edge case where providers returned empty results without error)
      Enum.empty?(providers_failed) ->
        "no_images"

      # If providers failed, check WHY they failed
      true ->
        error_details = metadata["error_details"] || metadata[:error_details] || %{}

        # Check if ANY provider had an API error (not ZERO_RESULTS)
        has_api_errors? =
          Enum.any?(providers_failed, fn provider ->
            error = get_provider_error(error_details, provider)
            is_api_error?(error)
          end)

        if has_api_errors? do
          # If ANY provider had an API error, this is an "error" not "no_images"
          "error"
        else
          # All providers returned ZERO_RESULTS (genuine no images available)
          "no_images"
        end
    end
  end

  # Gets the error for a specific provider from error_details map
  defp get_provider_error(error_details, provider) do
    Map.get(error_details, provider) || Map.get(error_details, to_string(provider))
  end

  # Checks if an error is an API error (not ZERO_RESULTS)
  # API errors include: INVALID_REQUEST, authentication failures, rate limits, etc.
  # ZERO_RESULTS is NOT an API error - it means "no images available"
  defp is_api_error?(error) do
    # Check if it's a permanent failure (auth, config, invalid request)
    # Check if it's a retryable error (rate limit, timeout, network)
    # Check for any other error patterns that are not ZERO_RESULTS
    permanent_failure?(error) or
      retryable_error?(error) or
      (is_binary(error) and not is_zero_results?(error))
  end

  # Checks if an error represents "no images available" (ZERO_RESULTS)
  # This is the ONLY case that should trigger "no_images" status
  defp is_zero_results?(error) when is_binary(error) do
    String.contains?(error, "ZERO_RESULTS") or
      String.contains?(error, "No images") or
      String.contains?(error, "no images")
  end

  defp is_zero_results?(_), do: false

  defp build_success_metadata(enriched_venue, start_time) do
    execution_time = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)

    metadata = enriched_venue.image_enrichment_metadata || %{}
    all_images = enriched_venue.venue_images || []

    # Separate successful and failed images
    # Successful = uploaded (production) OR skipped_dev (development)
    successful_images =
      Enum.filter(all_images, fn img ->
        img["upload_status"] == "uploaded" or img["upload_status"] == "skipped_dev"
      end)

    failed_images = Enum.filter(all_images, fn img -> img["upload_status"] == "failed" end)

    # Extract and normalize provider lists - deduplicate to avoid mixing atom/string keys
    providers_succeeded =
      (metadata["providers_succeeded"] || metadata[:providers_succeeded] ||
         metadata["providers_used"] || metadata[:providers_used] || [])
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    providers_failed =
      (metadata["providers_failed"] || metadata[:providers_failed] || [])
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    total_cost = metadata["total_cost"] || metadata[:total_cost] || 0.0

    # Build failure breakdown statistics
    failure_breakdown =
      failed_images
      |> Enum.group_by(fn img -> get_in(img, ["error_details", "error_type"]) end)
      |> Enum.map(fn {error_type, images} -> {error_type || "unknown", length(images)} end)
      |> Map.new()

    # Extract detailed failure information
    failed_image_details =
      failed_images
      |> Enum.map(fn img ->
        error_details = img["error_details"] || %{}

        %{
          "provider_url" => img["provider_url"],
          "provider" => img["provider"],
          "error_type" => error_details["error_type"],
          "status_code" => error_details["status_code"],
          "timestamp" => error_details["timestamp"]
        }
      end)

    # Determine status correctly - distinguish between genuine "no images" vs errors
    status = determine_job_status(successful_images, providers_failed, metadata)

    %{
      status: status,
      venue_context: build_venue_context(enriched_venue),
      images_discovered: length(all_images),
      images_uploaded: length(successful_images),
      images_failed: length(failed_images),
      failure_breakdown: failure_breakdown,
      failed_images: failed_image_details,
      providers: build_provider_details(metadata, enriched_venue.venue_images),
      imagekit_urls: extract_imagekit_urls(enriched_venue.venue_images),
      total_cost_usd: total_cost,
      execution_time_ms: execution_time,
      completed_at: DateTime.to_iso8601(DateTime.utc_now()),
      summary:
        build_summary(
          status,
          providers_succeeded,
          providers_failed,
          length(successful_images),
          length(all_images)
        )
    }
  end

  defp build_error_metadata(reason, start_time, venue \\ nil) do
    execution_time = DateTime.diff(DateTime.utc_now(), start_time, :millisecond)

    base_metadata = %{
      status: "error",
      error: inspect(reason),
      images_found: 0,
      execution_time_ms: execution_time,
      failed_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    # Add venue context if venue is available
    if venue do
      Map.put(base_metadata, :venue_context, build_venue_context(venue))
    else
      base_metadata
    end
  end

  defp extract_imagekit_urls(venue_images) when is_list(venue_images) do
    venue_images
    |> Enum.filter(fn img ->
      upload_status = img["upload_status"] || img[:upload_status]
      upload_status == "uploaded"
    end)
    |> Enum.map(fn img -> img["url"] || img[:url] end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_imagekit_urls(_), do: []

  defp build_provider_details(metadata, venue_images) do
    cost_breakdown = metadata["cost_breakdown"] || metadata[:cost_breakdown] || %{}
    error_details = metadata["error_details"] || metadata[:error_details] || %{}

    # Guard against nil venue_images
    venue_images = venue_images || []

    # Extract and normalize provider lists - deduplicate to avoid mixing atom/string keys
    providers_succeeded =
      (metadata["providers_succeeded"] || metadata[:providers_succeeded] ||
         metadata["providers_used"] || metadata[:providers_used] || [])
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    providers_failed =
      (metadata["providers_failed"] || metadata[:providers_failed] || [])
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    # Build details for successful providers
    success_details =
      providers_succeeded
      |> Enum.map(fn provider ->
        provider_images =
          venue_images
          |> Enum.filter(fn img ->
            to_string(img["provider"] || img[:provider]) == provider
          end)

        images_fetched = length(provider_images)

        images_uploaded =
          Enum.count(provider_images, fn img ->
            (img["upload_status"] || img[:upload_status]) == "uploaded"
          end)

        imagekit_urls =
          provider_images
          |> Enum.filter(fn img ->
            (img["upload_status"] || img[:upload_status]) == "uploaded"
          end)
          |> Enum.map(fn img -> img["url"] || img[:url] end)

        {provider,
         %{
           status: "success",
           images_fetched: images_fetched,
           images_uploaded: images_uploaded,
           imagekit_urls: imagekit_urls,
           cost_usd:
             Map.get(cost_breakdown, provider) || Map.get(cost_breakdown, to_string(provider)) ||
               0.0
         }}
      end)
      |> Map.new()

    # Build details for failed providers
    failed_details =
      providers_failed
      |> Enum.map(fn provider ->
        error = Map.get(error_details, provider) || Map.get(error_details, to_string(provider))

        {provider,
         %{
           status: "failed",
           reason: inspect(error)
         }}
      end)
      |> Map.new()

    Map.merge(success_details, failed_details)
  end

  defp build_summary(
         status,
         providers_succeeded,
         providers_failed,
         images_uploaded,
         images_discovered
       ) do
    case status do
      "success" ->
        provider_names =
          if Enum.empty?(providers_succeeded),
            do: "unknown provider",
            else: Enum.join(providers_succeeded, ", ")

        cond do
          images_uploaded == images_discovered ->
            "Found #{images_discovered} images from #{provider_names}, all processed successfully"

          images_uploaded < images_discovered ->
            failed_count = images_discovered - images_uploaded

            "Found #{images_discovered} images from #{provider_names}, #{images_uploaded} processed, #{failed_count} failed"
        end

      "no_images" ->
        "No images found - venue has no available photos"

      "error" ->
        failed_names =
          if Enum.empty?(providers_failed), do: "unknown", else: Enum.join(providers_failed, ", ")

        "Failed - #{failed_names} encountered errors"

      _ ->
        "Unknown status"
    end
  end

  # Helper to build error messages from providers and error details
  defp build_error_messages(providers_failed, error_details) do
    Enum.map(providers_failed, fn provider ->
      error =
        Map.get(error_details, provider) ||
          Map.get(error_details, to_string(provider))

      "#{provider}: #{inspect(error)}"
    end)
    |> Enum.join(", ")
  end

  # Determines if an error is a permanent failure that should fail the job
  # These errors should NOT retry and should mark the job as failed
  defp permanent_failure?(error) do
    case error do
      # API Authentication & Configuration - FAIL JOB
      :api_key_missing ->
        true

      :no_provider_id ->
        true

      :module_not_found ->
        true

      :invalid_api_key ->
        true

      # String-based errors (from API responses)
      error when is_binary(error) ->
        # Google API authentication errors
        # HTTP authentication/authorization errors
        String.contains?(error, "REQUEST_DENIED") or
          String.contains?(error, "INVALID_API_KEY") or
          String.contains?(error, "INVALID_REQUEST") or
          String.starts_with?(error, "HTTP 400") or
          String.starts_with?(error, "HTTP 401") or
          String.starts_with?(error, "HTTP 403")

      # All other errors are either retryable or success with no images
      _ ->
        false
    end
  end

  # Determines if an error should be retried
  # ONLY retry transient failures (network issues, rate limits, server errors)
  # DO NOT retry permanent failures (auth errors, config errors) or success cases (no images)
  defp retryable_error?(error) do
    case error do
      # Transient network/infrastructure errors - SHOULD RETRY
      :rate_limited ->
        true

      :timeout ->
        true

      :network_error ->
        true

      # HTTP errors - only retry 429 and 5xx
      # Also handle string patterns as safety net while providers migrate to atoms
      error when is_binary(error) ->
        # Rate limit
        # Internal server error
        # Bad gateway
        # Service unavailable
        # Gateway timeout
        # Network errors (safety net)
        # Google rate limit
        # Google resource exhausted
        String.starts_with?(error, "HTTP 429") or
          String.starts_with?(error, "HTTP 500") or
          String.starts_with?(error, "HTTP 502") or
          String.starts_with?(error, "HTTP 503") or
          String.starts_with?(error, "HTTP 504") or
          String.starts_with?(error, "Network error") or
          String.contains?(error, "OVER_QUERY_LIMIT") or
          String.contains?(error, "RESOURCE_EXHAUSTED")

      # All other errors are permanent - DO NOT RETRY
      _ ->
        false
    end
  end

  # Builds diagnostic context about the venue for metadata
  # Helps debug issues like missing provider_ids, coordinates, etc.
  defp build_venue_context(venue) do
    provider_ids = venue.provider_ids || %{}

    %{
      venue_id: venue.id,
      venue_name: venue.name,
      venue_address: venue.address,
      has_coordinates: not is_nil(venue.latitude) and not is_nil(venue.longitude),
      coordinates:
        if venue.latitude && venue.longitude do
          "#{venue.latitude},#{venue.longitude}"
        else
          nil
        end,
      city_id: venue.city_id,
      provider_ids_available: Map.keys(provider_ids) |> Enum.map(&to_string/1),
      provider_ids_count: map_size(provider_ids)
    }
  end
end
