defmodule EventasaurusDiscovery.Admin.VenueCountryCheckJob do
  @moduledoc """
  Oban worker for checking venue country assignments against GPS coordinates.

  This job processes venues in batches, checking if each venue's assigned country
  matches what the GPS coordinates indicate. Results are stored in the venue's
  metadata field under the `country_check` key.

  ## Usage

      # Queue a check for all venues
      VenueCountryCheckJob.queue_check()

      # Queue with options
      VenueCountryCheckJob.queue_check(batch_size: 50, source: "speed_quizzing")

  ## Metadata Schema

  Results are stored in venue.metadata["country_check"]:

      %{
        "checked_at" => "2024-12-06T10:00:00Z",
        "expected_country" => "Ireland",
        "expected_city" => "Dublin",
        "current_country" => "United Kingdom",
        "confidence" => "high",
        "is_mismatch" => true,
        "status" => "pending"  # pending | fixed | ignored
      }
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 300, fields: [:args], states: [:available, :scheduled, :executing]]

  import Ecto.Query
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  # Repo: Used for Repo.replica() read-only queries (uses read replica for performance)
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Helpers.CityResolver
  require Logger

  @batch_size 100
  @pubsub_topic "venue_country_check"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    batch_size = args["batch_size"] || @batch_size
    source_filter = args["source"]
    offset = args["offset"] || 0

    Logger.info("""
    [VenueCountryCheck] Starting batch processing
    Batch size: #{batch_size}
    Offset: #{offset}
    Source filter: #{source_filter || "all"}
    """)

    broadcast_progress(:started, %{batch_size: batch_size, offset: offset})

    # Process venues in batches
    {:ok, stats} = process_batch(batch_size, offset, source_filter)

    Logger.info("[VenueCountryCheck] Batch complete: #{inspect(stats)}")
    broadcast_progress(:completed, stats)

    # If there are more venues, queue the next batch
    if stats.processed == batch_size do
      queue_next_batch(args, offset + batch_size)
    end

    :ok
  end

  defp process_batch(batch_size, offset, source_filter) do
    # Query venues with GPS coordinates that haven't been checked recently
    # or have never been checked
    query =
      from(v in Venue,
        join: c in City,
        on: c.id == v.city_id,
        join: co in Country,
        on: co.id == c.country_id,
        where: not is_nil(v.latitude) and not is_nil(v.longitude),
        order_by: [asc: v.id],
        offset: ^offset,
        limit: ^batch_size,
        preload: [city_ref: {c, country: co}],
        select: v
      )

    # Add source filter if specified
    query =
      if source_filter do
        from(v in query, where: v.source == ^source_filter)
      else
        query
      end

    venues = Repo.replica().all(query)

    stats = %{
      processed: 0,
      mismatches: 0,
      matches: 0,
      errors: 0,
      updated: 0
    }

    # Process each venue and update metadata
    final_stats =
      Enum.reduce(venues, stats, fn venue, acc ->
        case check_and_update_venue(venue) do
          {:ok, :mismatch} ->
            %{
              acc
              | processed: acc.processed + 1,
                mismatches: acc.mismatches + 1,
                updated: acc.updated + 1
            }

          {:ok, :match} ->
            %{
              acc
              | processed: acc.processed + 1,
                matches: acc.matches + 1,
                updated: acc.updated + 1
            }

          {:error, _reason} ->
            %{acc | processed: acc.processed + 1, errors: acc.errors + 1}
        end
      end)

    {:ok, final_stats}
  end

  defp check_and_update_venue(%Venue{} = venue) do
    lat = venue.latitude
    lng = venue.longitude

    # Get current country CODE and name from venue's city (the actual DB assignment)
    current_code = get_venue_country_code(venue)
    current_country = get_venue_country_name(venue)
    current_city = get_venue_city_name(venue)

    if is_nil(current_code) do
      {:error, :no_country}
    else
      # Resolve expected country from GPS coordinates using offline geocoding
      case CityResolver.resolve_city_and_country(lat, lng) do
        {:ok, {expected_city, expected_code}} ->
          # Compare COUNTRY CODES - this is the definitive check
          # If the venue's assigned country code differs from what GPS says, it's a mismatch
          current_code_upper = String.upcase(current_code || "")
          expected_code_upper = String.upcase(expected_code || "")
          is_mismatch = current_code_upper != expected_code_upper

          confidence =
            if is_mismatch do
              determine_confidence(current_code_upper, expected_code_upper)
            else
              nil
            end

          # Find the scraper source for this venue
          scraper_source = get_venue_scraper_source(venue)

          # Build the country_check metadata (names are for display only)
          check_result = %{
            "checked_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "current_country_code" => current_code_upper,
            "expected_country_code" => expected_code_upper,
            "expected_country" => country_name_from_code(expected_code),
            "expected_city" => expected_city,
            "current_country" => current_country,
            "current_city" => current_city,
            "confidence" => if(confidence, do: Atom.to_string(confidence), else: nil),
            "is_mismatch" => is_mismatch,
            "status" => if(is_mismatch, do: "pending", else: "ok"),
            "scraper_source" => scraper_source
          }

          # Update venue metadata
          update_venue_metadata(venue, check_result)

          if is_mismatch do
            {:ok, :mismatch}
          else
            {:ok, :match}
          end

        {:error, reason} ->
          Logger.debug(
            "[VenueCountryCheck] Geocoding failed for venue #{venue.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp update_venue_metadata(venue, check_result) do
    current_metadata = venue.metadata || %{}
    updated_metadata = Map.put(current_metadata, "country_check", check_result)

    venue
    |> Ecto.Changeset.change(%{metadata: updated_metadata})
    |> JobRepo.update()
  end

  defp get_venue_country_code(%Venue{} = venue) do
    case venue.city_ref do
      %City{country: %Country{code: code}} -> code
      _ -> nil
    end
  end

  defp get_venue_country_name(%Venue{} = venue) do
    case venue.city_ref do
      %City{country: %Country{name: name}} -> name
      _ -> nil
    end
  end

  defp get_venue_city_name(%Venue{} = venue) do
    case venue.city_ref do
      %City{name: name} -> name
      _ -> nil
    end
  end

  # Find the scraper source for a venue
  # First tries to find via linked events, then falls back to venue metadata
  # This handles orphan venues (venues with no events) that still have source info in metadata
  defp get_venue_scraper_source(%Venue{id: venue_id, metadata: metadata}) do
    # First try to get from events (most reliable when available)
    event_source = get_venue_scraper_source_from_events(venue_id)

    # Fall back to metadata if no events found
    event_source ||
      get_in(metadata || %{}, ["source_data", "source_scraper"]) ||
      get_in(metadata || %{}, ["geocoding", "source_scraper"])
  end

  # Query events to find the most common scraper source
  defp get_venue_scraper_source_from_events(venue_id) do
    query =
      from(pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        join: s in Source,
        on: s.id == pes.source_id,
        where: pe.venue_id == ^venue_id,
        group_by: s.slug,
        order_by: [desc: count(pe.id)],
        limit: 1,
        select: s.slug
      )

    Repo.replica().one(query)
  end

  # Convert ISO country code to full name (for display purposes only)
  defp country_name_from_code(code) when is_binary(code) do
    # Common mappings - the geocoding library returns ISO codes
    case String.upcase(code) do
      "IE" -> "Ireland"
      "GB" -> "United Kingdom"
      "US" -> "United States"
      "DE" -> "Germany"
      "FR" -> "France"
      "ES" -> "Spain"
      "IT" -> "Italy"
      "NL" -> "Netherlands"
      "BE" -> "Belgium"
      "PL" -> "Poland"
      "CZ" -> "Czech Republic"
      "AT" -> "Austria"
      "CH" -> "Switzerland"
      "PT" -> "Portugal"
      "SE" -> "Sweden"
      "NO" -> "Norway"
      "DK" -> "Denmark"
      "FI" -> "Finland"
      "AU" -> "Australia"
      "NZ" -> "New Zealand"
      "CA" -> "Canada"
      "MX" -> "Mexico"
      "JP" -> "Japan"
      "KR" -> "South Korea"
      "CN" -> "China"
      "IN" -> "India"
      "BR" -> "Brazil"
      "AR" -> "Argentina"
      "ZA" -> "South Africa"
      # If no mapping, return the code as-is
      _ -> code
    end
  end

  defp country_name_from_code(code), do: to_string(code)

  # Determine confidence level based on country code pairs
  # Uses ISO country codes (e.g., "GB", "IE", "US") for comparison
  defp determine_confidence(current_code, expected_code) do
    # Known high-confidence mismatches (common data quality issues)
    # These are country CODE pairs that frequently indicate real misassignments
    high_confidence_pairs = [
      # UK/Ireland - common scraper confusion
      {"GB", "IE"},
      {"IE", "GB"},
      # Germany/Austria - border confusion
      {"DE", "AT"},
      {"AT", "DE"},
      # US/Canada - border confusion
      {"US", "CA"},
      {"CA", "US"},
      # Belgium/Netherlands - border confusion
      {"BE", "NL"},
      {"NL", "BE"}
    ]

    pair = {current_code, expected_code}

    if pair in high_confidence_pairs do
      :high
    else
      # For other country code mismatches, use medium confidence
      :medium
    end
  end

  defp queue_next_batch(args, new_offset) do
    args
    |> Map.put("offset", new_offset)
    |> new()
    |> Oban.insert()

    Logger.info("[VenueCountryCheck] Queued next batch at offset #{new_offset}")
  end

  defp broadcast_progress(status, data) do
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      @pubsub_topic,
      {:venue_country_check_progress, Map.put(data, :status, status)}
    )
  end

  @doc """
  Queue a venue country check job.

  ## Options
    - `:batch_size` - Number of venues per batch (default: 100)
    - `:source` - Filter by source (optional)
  """
  def queue_check(opts \\ []) do
    args =
      %{}
      |> maybe_put("batch_size", Keyword.get(opts, :batch_size))
      |> maybe_put("source", Keyword.get(opts, :source))

    args
    |> new()
    |> Oban.insert()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Get statistics about the last country check run.
  """
  def get_last_check_stats do
    query =
      from(v in Venue,
        where: not is_nil(fragment("?->'country_check'", v.metadata)),
        select: %{
          total_checked: count(v.id),
          mismatches:
            count(
              fragment(
                "CASE WHEN (?->'country_check'->>'is_mismatch')::boolean = true THEN 1 END",
                v.metadata
              )
            ),
          pending:
            count(
              fragment(
                "CASE WHEN ?->'country_check'->>'status' = 'pending' THEN 1 END",
                v.metadata
              )
            ),
          fixed:
            count(
              fragment(
                "CASE WHEN ?->'country_check'->>'status' = 'fixed' THEN 1 END",
                v.metadata
              )
            ),
          ignored:
            count(
              fragment(
                "CASE WHEN ?->'country_check'->>'status' = 'ignored' THEN 1 END",
                v.metadata
              )
            ),
          last_checked:
            max(
              fragment(
                "(?->'country_check'->>'checked_at')::timestamptz",
                v.metadata
              )
            )
        }
      )

    Repo.replica().one(query)
  end

  @doc """
  Get venues with country mismatches.
  """
  def get_mismatches(opts \\ []) do
    status = Keyword.get(opts, :status, "pending")
    limit = Keyword.get(opts, :limit, 50)
    confidence = Keyword.get(opts, :confidence)

    query =
      from(v in Venue,
        join: c in City,
        on: c.id == v.city_id,
        join: co in Country,
        on: co.id == c.country_id,
        where: fragment("(?->'country_check'->>'is_mismatch')::boolean = true", v.metadata),
        where: fragment("?->'country_check'->>'status' = ?", v.metadata, ^status),
        order_by: [desc: fragment("?->'country_check'->>'checked_at'", v.metadata)],
        limit: ^limit,
        preload: [city_ref: {c, country: co}]
      )

    query =
      if confidence do
        from(v in query,
          where: fragment("?->'country_check'->>'confidence' = ?", v.metadata, ^confidence)
        )
      else
        query
      end

    Repo.replica().all(query)
  end
end
