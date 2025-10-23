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
  def perform(%Oban.Job{args: %{"venue_id" => venue_id} = args}) do
    providers = Map.get(args, "providers")
    geocode = Map.get(args, "geocode", false)
    force = Map.get(args, "force", false)

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
        {:discard, :not_found}

      venue ->
        # Handle backfill-specific processing
        case enrich_single_venue(venue, providers: providers, geocode: geocode, force: force) do
          {:ok, enriched_venue} ->
            # Check if we actually got images
            images_count = length(enriched_venue.venue_images || [])

            if images_count > 0 do
              Logger.info("✅ Venue #{venue_id} enriched with #{images_count} images")
              :ok
            else
              # Extract error details from metadata
              metadata = enriched_venue.image_enrichment_metadata || %{}
              providers_failed = metadata["providers_failed"] || metadata[:providers_failed] || []
              error_details = metadata["error_details"] || metadata[:error_details] || %{}

              if Enum.empty?(providers_failed) do
                Logger.warning("⚠️  Venue #{venue_id} enrichment completed but no images fetched (no errors reported)")
                :ok
              else
                # Build error message with actual provider errors
                error_messages =
                  Enum.map(providers_failed, fn provider ->
                    error = Map.get(error_details, provider) || Map.get(error_details, to_string(provider))
                    "#{provider}: #{inspect(error)}"
                  end)
                  |> Enum.join(", ")

                # Check if ANY error is retryable (only retry transient failures)
                # RETRYABLE: rate limits, timeouts, network errors, server errors (5xx)
                # NOT RETRYABLE: everything else (no images, auth errors, 4xx, etc.)
                any_retryable? =
                  Enum.any?(providers_failed, fn provider ->
                    error = Map.get(error_details, provider) || Map.get(error_details, to_string(provider))
                    retryable_error?(error)
                  end)

                if any_retryable? do
                  Logger.error("❌ Venue #{venue_id} failed with retryable error: #{error_messages}")
                  {:error, "Failed to fetch images: #{error_messages}"}
                else
                  Logger.info("ℹ️  Venue #{venue_id} failed with permanent error (not retrying): #{error_messages}")
                  :ok
                end
              end
            end

          {:skip, reason} ->
            Logger.info("⏭️  Skipped venue #{venue_id}: #{reason}")
            :ok

          {:error, reason} ->
            Logger.error("❌ Failed to enrich venue #{venue_id}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_ids" => venue_ids}}) do
    Logger.info("🖼️  Processing batch venue enrichment: #{length(venue_ids)} venues")

    venues = Repo.all(from v in Venue, where: v.id in ^venue_ids)
    _ = enrich_venues_batch(venues)
    :ok
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
      _ = enrich_venues_batch(stale_venues)
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
      where:
        # Never enriched
        is_nil(fragment("? ->> 'last_enriched_at'", v.image_enrichment_metadata)) or
          # No images (handle NULL venue_images)
          fragment("COALESCE(jsonb_array_length(?), 0) = 0", v.venue_images) or
          # Stale images (>30 days)
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
            {:error, _reason} -> venue  # Continue with original venue if geocoding fails
          end
        else
          venue
        end

      # Build enrichment options
      enrichment_opts = [
        max_retries: max_retries
      ]

      enrichment_opts =
        if providers, do: Keyword.put(enrichment_opts, :providers, providers), else: enrichment_opts

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
                   geocoding_performance: result[:geocoding_metadata] || result["geocoding_metadata"],
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

  # Determines if an error should be retried
  # ONLY retry transient failures (network issues, rate limits, server errors)
  # DO NOT retry permanent failures (no images, auth errors, invalid data, client errors)
  defp retryable_error?(error) do
    case error do
      # Transient network/infrastructure errors - SHOULD RETRY
      :rate_limited -> true
      :timeout -> true
      :network_error -> true

      # HTTP errors - only retry 429 and 5xx
      error when is_binary(error) ->
        String.starts_with?(error, "HTTP 429") or  # Rate limit
        String.starts_with?(error, "HTTP 500") or  # Internal server error
        String.starts_with?(error, "HTTP 502") or  # Bad gateway
        String.starts_with?(error, "HTTP 503") or  # Service unavailable
        String.starts_with?(error, "HTTP 504")     # Gateway timeout

      # All other errors are permanent - DO NOT RETRY
      _ -> false
    end
  end
end
