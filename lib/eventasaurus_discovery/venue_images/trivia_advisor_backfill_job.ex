defmodule EventasaurusDiscovery.VenueImages.TriviaAdvisorBackfillJob do
  @moduledoc """
  Orchestrator job for backfilling venue images from Trivia Advisor database.

  This job connects to the Trivia Advisor production database, matches venues
  by slug and geographic proximity, then spawns individual TriviaAdvisorImageUploadJob
  workers for each matched venue.

  ## Orchestrator Pattern (follows BackfillOrchestratorJob)

  This is a parent job that:
  - Connects to Trivia Advisor database
  - Matches venues using multi-tier algorithm
  - Spawns TriviaAdvisorImageUploadJob for each matched venue
  - Returns immediately with spawned job IDs

  The individual TriviaAdvisorImageUploadJob workers then handle:
  - Development: Store Tigris S3 URLs directly
  - Production: Download from Tigris → Upload to ImageKit

  This design provides:
  - **Failure Isolation**: One venue failure doesn't affect others
  - **Granular Retries**: Failed venues retry independently
  - **Better Observability**: Track progress per venue in Oban UI
  - **Rate Limiting**: ImageKit uploads throttled at 2 req/sec

  ## Usage

      # Backfill images for a specific city
      TriviaAdvisorBackfillJob.enqueue(city_id: 5, limit: 10)

      # Process all remaining venues (unlimited)
      TriviaAdvisorBackfillJob.enqueue(city_id: 5, limit: -1)

      # Force re-process venues that already have images
      TriviaAdvisorBackfillJob.enqueue(city_id: 5, limit: 10, force: true)

      # Dry run to preview changes
      TriviaAdvisorBackfillJob.enqueue(city_id: 5, limit: 5, dry_run: true)

  ## Job Arguments

  - `:city_id` - Required. Integer city ID to filter Eventasaurus venues
  - `:limit` - Optional. Maximum number of venues to process (default: 10 in dev, 50 in prod). Use -1 for unlimited.
  - `:force` - Optional. Force re-process venues that already have trivia_advisor_migration images (default: false)
  - `:dry_run` - Optional. Preview changes without updating database (default: false)

  ## Environment Variables

  Requires `TRIVIA_ADVISOR_DATABASE_URL` to be set:

      TRIVIA_ADVISOR_DATABASE_URL=postgresql://user:pass@host:port/trivia_advisor_production

  ## Venue Matching Algorithm

  Uses multi-tier confidence scoring:

  1. **Tier 1 (Confidence: 1.00)** - Slug exact match + geo distance < 50m
  2. **Tier 2 (Confidence: 0.95)** - Google Place ID match
  3. **Tier 3 (Confidence: 0.85)** - Slug only OR geo + name similarity

  ## Job Metadata (Orchestrator)

  This orchestrator job stores minimal metadata and spawns individual jobs:

      %{
        "status" => "orchestrator",
        "city_id" => 5,
        "venues_processed" => 10,
        "venues_matched" => 10,
        "jobs_spawned" => 10,
        "spawned_job_ids" => [3501, 3502, 3503, ...],
        "spawned_jobs" => [
          %{
            "venue_id" => 123,
            "venue_name" => "Venue Name",
            "venue_slug" => "venue-slug",
            "images_count" => 5,
            "match_tier" => "slug_geo",
            "confidence" => 1.0
          }
        ],
        "processed_at" => "2024-01-01T00:00:00Z"
      }

  Individual TriviaAdvisorImageUploadJob metadata contains detailed results per venue.
  """

  use Oban.Worker,
    queue: :venue_backfill,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.VenueImages.TriviaAdvisorImageUploadJob
  import Ecto.Query

  @doc """
  Enqueues a Trivia Advisor backfill job.

  ## Examples

      # Basic backfill for city
      TriviaAdvisorBackfillJob.enqueue(city_id: 5, limit: 10)

      # Dry run to preview changes
      TriviaAdvisorBackfillJob.enqueue(city_id: 5, limit: 5, dry_run: true)

  """
  def enqueue(args) when is_list(args) do
    city_id = Keyword.get(args, :city_id)

    unless city_id do
      raise ArgumentError, "city_id is required"
    end

    # Apply safe limits
    limit = get_safe_limit(Keyword.get(args, :limit))

    # Convert to map for Oban
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
    limit = Map.get(args, "limit", get_default_limit())
    force = Map.get(args, "force", false)
    dry_run = Map.get(args, "dry_run", false)

    Logger.info("""
    🖼️  Starting Trivia Advisor image backfill:
       - City ID: #{city_id}
       - Limit: #{if limit == -1, do: "unlimited", else: limit}
       - Force: #{force}
       - Dry Run: #{dry_run}
    """)

    # Validate Trivia Advisor database connection
    ta_db_url = System.get_env("TRIVIA_ADVISOR_DATABASE_URL")

    unless ta_db_url do
      error_msg = "TRIVIA_ADVISOR_DATABASE_URL not set in environment"
      Logger.error("❌ #{error_msg}")

      store_failure_meta(job, %{
        status: "failed",
        error: error_msg,
        city_id: city_id
      })

      {:error, error_msg}
    else
      # Execute migration
      case execute_migration(ta_db_url, city_id, limit, force, dry_run) do
        {:ok, results} ->
          # Store success metadata
          store_success_meta(job, results, city_id, dry_run)

          Logger.info("""
          ✅ Trivia Advisor migration completed:
             - Venues matched: #{results.venues_matched}
             - Jobs spawned: #{results.jobs_spawned}
          """)

          :ok

        {:error, reason} ->
          Logger.error("❌ Trivia Advisor migration failed: #{inspect(reason)}")

          store_failure_meta(job, %{
            status: "failed",
            error: inspect(reason),
            city_id: city_id
          })

          {:error, reason}
      end
    end
  end

  # Private Functions

  defp execute_migration(ta_db_url, city_id, limit, force, dry_run) do
    # Connect to Trivia Advisor database
    ta_db_config = parse_database_url(ta_db_url)

    case Postgrex.start_link(ta_db_config) do
      {:ok, ta_conn} ->
        try do
          # Load venues from both databases
          Logger.info("Loading venues for matching...")

          ta_venues = load_ta_venues_with_images(ta_conn)
          ea_venues = load_ea_venues_for_city(city_id, force)

          Logger.info("""
          Loaded venues:
            - Trivia Advisor: #{length(ta_venues)} venues with images
            - Eventasaurus: #{length(ea_venues)} venues in city #{city_id}
          """)

          # Match venues
          Logger.info("Matching venues...")
          matches = match_venues(ta_venues, ea_venues, limit)

          Logger.info("Found #{length(matches)} matches - spawning individual upload jobs")

          # Always spawn individual jobs (following BackfillOrchestratorJob pattern)
          stats = spawn_upload_jobs(matches, dry_run)
          {:ok, stats}
        after
          # Always close connection
          GenServer.stop(ta_conn)
        end

      {:error, reason} ->
        {:error, {:db_connection_failed, reason}}
    end
  end

  defp spawn_upload_jobs(matches, dry_run) do
    Logger.info("🎯 Orchestrator mode: Spawning upload jobs for #{length(matches)} venues")

    if dry_run do
      Logger.info("  [DRY RUN] Would spawn #{length(matches)} TriviaAdvisorImageUploadJob jobs")

      # Return preview data for dry run
      preview_jobs =
        Enum.map(matches, fn match ->
          %{
            "venue_id" => match.ea_id,
            "venue_name" => match.ea_name,
            "venue_slug" => match.ea_slug,
            "images_count" => length(match.ta_images),
            "match_tier" => match.match_type,
            "confidence" => match.confidence
          }
        end)

      %{
        venues_processed: length(matches),
        venues_matched: length(matches),
        jobs_spawned: length(matches),
        spawned_jobs: preview_jobs,
        mode: "orchestrator",
        dry_run: true
      }
    else
      # Build job changesets for batch insertion
      job_changesets =
        matches
        |> Enum.map(fn match ->
          TriviaAdvisorImageUploadJob.new(%{
            "venue_id" => match.ea_id,
            "venue_slug" => match.ea_slug,
            "trivia_advisor_images" => match.ta_images,
            "match_tier" => match.match_type,
            "confidence" => match.confidence
          })
        end)

      # Batch insert all jobs
      jobs = Oban.insert_all(job_changesets)
      count = length(jobs)

      Logger.info("  ✅ Successfully spawned #{count} upload jobs")

      job_ids = Enum.map(jobs, & &1.id)

      %{
        venues_processed: length(matches),
        venues_matched: length(matches),
        jobs_spawned: count,
        spawned_job_ids: job_ids,
        mode: "orchestrator",
        dry_run: false
      }
    end
  end

  defp parse_database_url(url) do
    uri = URI.parse(url)
    [username, password] = String.split(uri.userinfo || ":", ":")

    [
      hostname: uri.host,
      port: uri.port || 5432,
      database: String.trim_leading(uri.path || "", "/"),
      username: username,
      password: password
    ]
  end

  defp load_ta_venues_with_images(conn) do
    {:ok, result} =
      Postgrex.query(
        conn,
        """
          SELECT id, slug, name, place_id, latitude, longitude, google_place_images
          FROM venues
          WHERE google_place_images IS NOT NULL
          AND jsonb_typeof(google_place_images) = 'array'
          AND jsonb_array_length(google_place_images) > 0
          ORDER BY id
        """,
        []
      )

    Enum.map(result.rows, fn [id, slug, name, place_id, lat, lng, images] ->
      %{
        id: id,
        slug: slug,
        name: name,
        place_id: place_id,
        latitude: lat,
        longitude: lng,
        google_place_images: images
      }
    end)
  end

  defp load_ea_venues_for_city(city_id, force) do
    query =
      from(v in Venue,
        where: v.city_id == ^city_id,
        where: not is_nil(v.latitude) and not is_nil(v.longitude),
        select: %{
          id: v.id,
          slug: v.slug,
          name: v.name,
          latitude: v.latitude,
          longitude: v.longitude,
          provider_ids: v.provider_ids,
          venue_images: v.venue_images
        }
      )

    venues = Repo.all(query)

    # Filter out venues that already have trivia_advisor_migration images (unless force=true)
    if force do
      Logger.info("  Force mode: Including all #{length(venues)} venues")
      venues
    else
      filtered_venues =
        Enum.reject(venues, fn venue ->
          has_trivia_advisor_images?(venue.venue_images)
        end)

      skipped_count = length(venues) - length(filtered_venues)

      if skipped_count > 0 do
        Logger.info(
          "  Skipped #{skipped_count} venues with existing trivia_advisor_migration images"
        )
      end

      filtered_venues
    end
  end

  defp has_trivia_advisor_images?(venue_images) when is_list(venue_images) do
    Enum.any?(venue_images, fn img ->
      img["source"] == "trivia_advisor_migration"
    end)
  end

  defp has_trivia_advisor_images?(_), do: false

  defp match_venues(ta_venues, ea_venues, limit) do
    matches =
      ta_venues
      |> Enum.map(fn ta_venue ->
        case find_best_match(ta_venue, ea_venues) do
          {ea_venue, match_type, confidence, distance, name_distance} ->
            %{
              ta_id: ta_venue.id,
              ta_slug: ta_venue.slug,
              ta_name: ta_venue.name,
              ta_images: ta_venue.google_place_images,
              ea_id: ea_venue.id,
              ea_slug: ea_venue.slug,
              ea_name: ea_venue.name,
              ea_venue: ea_venue,
              match_type: match_type,
              confidence: confidence,
              distance_m: distance,
              name_distance: name_distance
            }

          nil ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Apply limit (-1 means unlimited)
    if limit == -1 do
      Logger.info("  Processing all #{length(matches)} matched venues (unlimited mode)")
      matches
    else
      Enum.take(matches, limit)
    end
  end

  defp find_best_match(ta_venue, ea_venues) do
    ta_slug = ta_venue.slug
    ta_lat = maybe_to_float(ta_venue.latitude)
    ta_lng = maybe_to_float(ta_venue.longitude)
    ta_name = normalize_name(ta_venue.name)
    ta_place_id = ta_venue.place_id

    # Skip if no coordinates
    if is_nil(ta_lat) || is_nil(ta_lng) do
      nil
    else
      # Find best match using tiered algorithm
      Enum.reduce_while(ea_venues, nil, fn ea_venue, best_match ->
        ea_slug = ea_venue.slug
        ea_place_id = Map.get(ea_venue.provider_ids || %{}, "google_places")

        cond do
          # Tier 1: Slug + Geo (proof positive)
          ta_slug && ea_slug && ta_slug == ea_slug ->
            ea_lat = maybe_to_float(ea_venue.latitude)
            ea_lng = maybe_to_float(ea_venue.longitude)
            distance = haversine_distance(ta_lat, ta_lng, ea_lat, ea_lng)

            if distance < 50 do
              # Perfect match - stop searching
              {:halt, {ea_venue, "slug_geo", 1.00, distance, 0}}
            else
              # Slug match but too far - Tier 3a
              new_match = {ea_venue, "slug_only", 0.85, distance, 0}
              {:cont, better_match(best_match, new_match)}
            end

          # Tier 2: place_id match
          ta_place_id && ea_place_id && ta_place_id == ea_place_id ->
            ea_lat = maybe_to_float(ea_venue.latitude)
            ea_lng = maybe_to_float(ea_venue.longitude)
            distance = haversine_distance(ta_lat, ta_lng, ea_lat, ea_lng)
            new_match = {ea_venue, "place_id", 0.95, distance, 0}
            {:cont, better_match(best_match, new_match)}

          # Tier 3b: Geo + name similarity
          best_match == nil || elem(best_match, 2) < 0.85 ->
            ea_lat = maybe_to_float(ea_venue.latitude)
            ea_lng = maybe_to_float(ea_venue.longitude)
            distance = haversine_distance(ta_lat, ta_lng, ea_lat, ea_lng)

            if distance < 50 do
              ea_name = normalize_name(ea_venue.name)
              name_distance = levenshtein_distance(ta_name, ea_name)

              if name_distance <= 3 do
                new_match = {ea_venue, "geo_name", 0.85, distance, name_distance}
                {:cont, better_match(best_match, new_match)}
              else
                {:cont, best_match}
              end
            else
              {:cont, best_match}
            end

          true ->
            {:cont, best_match}
        end
      end)
    end
  end

  defp better_match(nil, new_match), do: new_match

  defp better_match(best, new_match) do
    {_, _, best_conf, best_dist, _} = best
    {_, _, new_conf, new_dist, _} = new_match

    if new_conf > best_conf || (new_conf == best_conf && new_dist < best_dist) do
      new_match
    else
      best
    end
  end

  defp haversine_distance(lat1, lon1, lat2, lon2) do
    # Convert to radians
    lat1_rad = lat1 * :math.pi() / 180
    lon1_rad = lon1 * :math.pi() / 180
    lat2_rad = lat2 * :math.pi() / 180
    lon2_rad = lon2 * :math.pi() / 180

    # Haversine formula
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(lat1_rad) * :math.cos(lat2_rad) *
          :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))

    # Earth radius in meters
    6_371_000 * c
  end

  defp levenshtein_distance(s1, s2) do
    s1 = String.downcase(s1 || "")
    s2 = String.downcase(s2 || "")

    l1 = String.length(s1)
    l2 = String.length(s2)

    matrix =
      Enum.reduce(0..l1, %{}, fn i, acc ->
        Map.put(acc, {i, 0}, i)
      end)

    matrix =
      Enum.reduce(0..l2, matrix, fn j, acc ->
        Map.put(acc, {0, j}, j)
      end)

    matrix =
      Enum.reduce(1..l1, matrix, fn i, acc ->
        Enum.reduce(1..l2, acc, fn j, acc2 ->
          cost = if String.at(s1, i - 1) == String.at(s2, j - 1), do: 0, else: 1

          Map.put(
            acc2,
            {i, j},
            min(
              Map.get(acc2, {i - 1, j}) + 1,
              min(
                Map.get(acc2, {i, j - 1}) + 1,
                Map.get(acc2, {i - 1, j - 1}) + cost
              )
            )
          )
        end)
      end)

    Map.get(matrix, {l1, l2})
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, "")
    |> String.trim()
  end

  defp normalize_name(_), do: ""

  defp store_success_meta(job, results, city_id, dry_run) do
    # Orchestrator always spawns jobs (following BackfillOrchestratorJob pattern)
    meta = %{
      "status" => "orchestrator",
      "dry_run" => dry_run,
      "city_id" => city_id,
      "venues_processed" => results.venues_processed,
      "venues_matched" => results.venues_matched,
      "jobs_spawned" => results.jobs_spawned,
      "spawned_job_ids" => Map.get(results, :spawned_job_ids, []),
      "spawned_jobs" => Map.get(results, :spawned_jobs, []),
      "processed_at" => NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
    }

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _} ->
        Logger.debug("✅ Stored results in Oban meta for job #{job.id}")

      {:error, reason} ->
        Logger.error("❌ Failed to store results in Oban meta: #{inspect(reason)}")
    end
  end

  defp store_failure_meta(job, meta_data) do
    meta =
      meta_data
      |> Map.put("processed_at", NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601())

    case Oban.update_job(job, %{meta: meta}) do
      {:ok, _} ->
        Logger.debug("✅ Stored failure info in Oban meta for job #{job.id}")

      {:error, reason} ->
        Logger.error("❌ Failed to store failure info in Oban meta: #{inspect(reason)}")
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
      |> Keyword.get(:prod_default_limit, 50)
    end
  end

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

  # Safely convert coordinates to floats for haversine distance calculations
  defp maybe_to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp maybe_to_float(value) when is_number(value), do: value
  defp maybe_to_float(_), do: nil
end
