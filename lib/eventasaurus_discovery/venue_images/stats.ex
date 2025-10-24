defmodule EventasaurusDiscovery.VenueImages.Stats do
  @moduledoc """
  Statistics and analytics for venue image upload failures.

  Provides queries and helpers for Phase 3 partial upload recovery:
  - Identify venues with failed uploads
  - Analyze failure patterns by provider and error type
  - Calculate priority scores for remediation
  """

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue

  @doc """
  Returns all venues with at least one failed upload.

  ## Examples

      iex> Stats.venues_with_failures()
      [
        %{
          id: 123,
          name: "Blue Note Jazz Club",
          city_id: 1,
          total_images: 10,
          failed_count: 3,
          uploaded_count: 7,
          failure_rate_pct: 30.0
        }
      ]
  """
  def venues_with_failures do
    query = """
    SELECT
      v.id,
      v.name,
      v.city_id,
      jsonb_array_length(v.venue_images) as total_images,
      (SELECT COUNT(*)
       FROM jsonb_array_elements(v.venue_images) img
       WHERE img->>'upload_status' IN ('failed', 'permanently_failed')) as failed_count,
      (SELECT COUNT(*)
       FROM jsonb_array_elements(v.venue_images) img
       WHERE img->>'upload_status' = 'uploaded') as uploaded_count,
      ROUND(
        100.0 * (SELECT COUNT(*) FROM jsonb_array_elements(v.venue_images) img
                 WHERE img->>'upload_status' IN ('failed', 'permanently_failed')) /
        NULLIF(jsonb_array_length(v.venue_images), 0),
        1
      ) as failure_rate_pct
    FROM venues v
    WHERE EXISTS (
      SELECT 1
      FROM jsonb_array_elements(v.venue_images) img
      WHERE img->>'upload_status' IN ('failed', 'permanently_failed')
    )
    ORDER BY failed_count DESC, failure_rate_pct DESC
    """

    {:ok, result} = Repo.query(query)

    Enum.map(result.rows, fn row ->
      [id, name, city_id, total_images, failed_count, uploaded_count, failure_rate_pct] = row

      %{
        id: id,
        name: name,
        city_id: city_id,
        total_images: total_images,
        failed_count: failed_count,
        uploaded_count: uploaded_count,
        failure_rate_pct: failure_rate_pct || 0.0
      }
    end)
  end

  @doc """
  Returns failure breakdown by provider and error type.

  ## Examples

      iex> Stats.failure_breakdown()
      [
        %{provider: "google_places", error_type: "rate_limited", count: 45},
        %{provider: "foursquare", error_type: "not_found", count: 12}
      ]
  """
  def failure_breakdown do
    query = """
    SELECT
      img->>'provider' as provider,
      img->'error_details'->>'error_type' as error_type,
      COUNT(*) as count
    FROM venues v,
      jsonb_array_elements(v.venue_images) img
    WHERE img->>'upload_status' IN ('failed', 'permanently_failed')
    GROUP BY provider, error_type
    ORDER BY count DESC
    """

    {:ok, result} = Repo.query(query)

    Enum.map(result.rows, fn [provider, error_type, count] ->
      %{
        provider: provider,
        error_type: error_type,
        count: count
      }
    end)
  end

  @doc """
  Returns venues with partial failures (both successful and failed uploads).
  These are the primary candidates for retry operations.
  """
  def partial_failure_candidates(opts \\ []) do
    min_failures = Keyword.get(opts, :min_failures, 1)
    limit = Keyword.get(opts, :limit, 100)

    query = """
    SELECT
      v.id,
      v.name,
      v.city_id,
      failed_count,
      uploaded_count,
      ROUND(100.0 * failed_count / (failed_count + uploaded_count), 1) as failure_rate_pct,
      (SELECT jsonb_agg(img->'error_details'->>'error_type')
       FROM jsonb_array_elements(v.venue_images) img
       WHERE img->>'upload_status' = 'failed') as error_types
    FROM (
      SELECT
        v.id,
        v.name,
        v.city_id,
        v.venue_images,
        (SELECT COUNT(*) FROM jsonb_array_elements(v.venue_images) img
         WHERE img->>'upload_status' = 'failed') as failed_count,
        (SELECT COUNT(*) FROM jsonb_array_elements(v.venue_images) img
         WHERE img->>'upload_status' = 'uploaded') as uploaded_count
      FROM venues v
      WHERE v.venue_images IS NOT NULL
    ) v
    WHERE failed_count >= $1 AND uploaded_count > 0
    ORDER BY failed_count DESC, failure_rate_pct DESC
    LIMIT $2
    """

    {:ok, result} = Repo.query(query, [min_failures, limit])

    Enum.map(result.rows, fn row ->
      [id, name, city_id, failed_count, uploaded_count, failure_rate_pct, error_types] = row

      %{
        id: id,
        name: name,
        city_id: city_id,
        failed_count: failed_count,
        uploaded_count: uploaded_count,
        failure_rate_pct: failure_rate_pct || 0.0,
        error_types: error_types || []
      }
    end)
  end

  @doc """
  Classifies error type as transient (retryable) or permanent.
  """
  def classify_error_type(error_type) when is_binary(error_type) do
    transient_errors = [
      "rate_limited",
      "service_unavailable",
      "network_timeout",
      "gateway_timeout",
      "bad_gateway"
    ]

    permanent_errors = [
      "not_found",
      "forbidden",
      "auth_error",
      "file_too_large"
    ]

    cond do
      error_type in transient_errors -> :transient
      error_type in permanent_errors -> :permanent
      true -> :ambiguous
    end
  end

  def classify_error_type(_), do: :unknown

  @doc """
  Returns count of venues with transient vs permanent failures.
  """
  def failure_classification_summary do
    venues = venues_with_failures()

    venues_by_id =
      Enum.map(venues, fn venue ->
        venue_full = Repo.get(Venue, venue.id)

        failed_images =
          (venue_full.venue_images || [])
          |> Enum.filter(fn img ->
            status = img["upload_status"]
            status == "failed" or status == "permanently_failed"
          end)

        error_types =
          failed_images
          |> Enum.map(fn img -> get_in(img, ["error_details", "error_type"]) end)
          |> Enum.filter(& &1)

        classifications =
          error_types
          |> Enum.map(&classify_error_type/1)
          |> Enum.frequencies()

        Map.put(venue, :classifications, classifications)
      end)

    %{
      total_venues: length(venues),
      total_failed_images: Enum.sum(Enum.map(venues, & &1.failed_count)),
      venues_with_transient:
        Enum.count(venues_by_id, fn v -> Map.get(v.classifications, :transient, 0) > 0 end),
      venues_with_permanent:
        Enum.count(venues_by_id, fn v -> Map.get(v.classifications, :permanent, 0) > 0 end),
      venues_with_ambiguous:
        Enum.count(venues_by_id, fn v -> Map.get(v.classifications, :ambiguous, 0) > 0 end)
    }
  end

  @doc """
  Calculates priority score for venue remediation.

  Higher score = higher priority for retry.

  Score factors:
  - Failed count (more failures = higher priority)
  - Failure rate percentage
  - Transient errors (easier to fix = higher priority)
  - Venue activity (popular venues = higher priority)
  """
  def calculate_priority_score(venue) do
    venue_full = Repo.get(Venue, venue.id)

    failed_images =
      (venue_full.venue_images || [])
      |> Enum.filter(fn img ->
        status = img["upload_status"]
        status == "failed" or status == "permanently_failed"
      end)

    transient_count =
      failed_images
      |> Enum.count(fn img ->
        error_type = get_in(img, ["error_details", "error_type"])
        classify_error_type(error_type) == :transient
      end)

    # Activity count (could be enhanced with actual activity metrics)
    activity_bonus = 0

    score =
      venue.failed_count * 10 +
        venue.failure_rate_pct +
        (if transient_count > 0, do: 20, else: 0) +
        activity_bonus / 100

    Float.round(score, 1)
  end

  @doc """
  Returns high-priority venues sorted by remediation priority.
  """
  def high_priority_venues(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    venues_with_failures()
    |> Enum.map(fn venue ->
      Map.put(venue, :priority_score, calculate_priority_score(venue))
    end)
    |> Enum.sort_by(& &1.priority_score, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Returns summary statistics for dashboard display.
  """
  def summary_stats do
    venues = venues_with_failures()
    classification = failure_classification_summary()
    breakdown = failure_breakdown()

    %{
      total_venues_with_failures: length(venues),
      total_failed_images: Enum.sum(Enum.map(venues, & &1.failed_count)),
      total_uploaded_images: Enum.sum(Enum.map(venues, & &1.uploaded_count)),
      average_failure_rate:
        if length(venues) > 0 do
          Enum.sum(Enum.map(venues, & &1.failure_rate_pct)) / length(venues)
          |> Float.round(1)
        else
          0.0
        end,
      venues_with_transient: classification.venues_with_transient,
      venues_with_permanent: classification.venues_with_permanent,
      top_error_types: Enum.take(breakdown, 5)
    }
  end
end
