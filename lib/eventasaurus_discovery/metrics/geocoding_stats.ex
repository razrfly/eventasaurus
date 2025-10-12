defmodule EventasaurusDiscovery.Metrics.GeocodingStats do
  @moduledoc """
  Query module for geocoding cost tracking and provider performance analysis.

  Provides metrics and reporting for geocoding API usage across all scrapers.
  All queries operate on `venues.metadata.geocoding` JSONB field.

  ## Cost Tracking Examples

      # Get total costs for current month
      GeocodingStats.monthly_cost(Date.utc_today())

      # Get costs by provider
      GeocodingStats.costs_by_provider()

      # Get costs by scraper
      GeocodingStats.costs_by_scraper()

  ## Performance Tracking Examples (Phase 3)

      # Get success rates by provider
      GeocodingStats.success_rate_by_provider()

      # Get average attempts before success
      GeocodingStats.average_attempts()

      # Get provider fallback patterns
      GeocodingStats.fallback_patterns()

      # Get failed geocoding attempts
      GeocodingStats.failed_geocoding_count()
  """

  import Ecto.Query
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Repo

  @doc """
  Calculate total geocoding costs for a given month.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, %{total_cost: float, count: integer}}` - Total cost and venue count
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.monthly_cost(~D[2025-01-15])
      {:ok, %{total_cost: 4.37, count: 143}}
  """
  def monthly_cost(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    query =
      from v in Venue,
        where:
          fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
            fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
            not is_nil(fragment("?->'geocoding'", v.metadata)),
        select: %{
          total_cost:
            sum(
              fragment(
                "COALESCE((?->'geocoding'->>'cost_per_call')::numeric, 0)",
                v.metadata
              )
            ),
          count: count(v.id)
        }

    case Repo.one(query) do
      nil ->
        {:ok, %{total_cost: 0.0, count: 0}}
      %{total_cost: nil, count: count} ->
        {:ok, %{total_cost: 0.0, count: count}}
      result ->
        {:ok, %{total_cost: result.total_cost || 0.0, count: result.count}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get geocoding costs broken down by provider.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{provider: string, total_cost: float, count: integer}]}` - Costs by provider
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.costs_by_provider()
      {:ok, [
        %{provider: "google_places", total_cost: 3.70, count: 100},
        %{provider: "google_maps", total_cost: 0.25, count: 50},
        %{provider: "openstreetmap", total_cost: 0.0, count: 200}
      ]}
  """
  def costs_by_provider(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    query =
      from v in Venue,
        where:
          fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
            fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
            not is_nil(fragment("?->'geocoding'", v.metadata)),
        group_by: fragment("?->'geocoding'->>'provider'", v.metadata),
        select: %{
          provider: fragment("?->'geocoding'->>'provider'", v.metadata),
          total_cost:
            sum(
              fragment(
                "COALESCE((?->'geocoding'->>'cost_per_call')::numeric, 0)",
                v.metadata
              )
            ),
          count: count(v.id)
        },
        order_by: [desc: fragment("sum(COALESCE((?->'geocoding'->>'cost_per_call')::numeric, 0))", v.metadata)]

    case Repo.all(query) do
      results -> {:ok, results}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get geocoding costs broken down by source scraper.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{scraper: string, total_cost: float, count: integer}]}` - Costs by scraper
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.costs_by_scraper()
      {:ok, [
        %{scraper: "resident_advisor", total_cost: 3.70, count: 100},
        %{scraper: "kino_krakow", total_cost: 0.74, count: 20},
        %{scraper: "question_one", total_cost: 0.25, count: 50}
      ]}
  """
  def costs_by_scraper(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    query =
      from v in Venue,
        where:
          fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
            fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
            not is_nil(fragment("?->'geocoding'", v.metadata)),
        group_by: fragment("?->'geocoding'->>'source_scraper'", v.metadata),
        select: %{
          scraper: fragment("?->'geocoding'->>'source_scraper'", v.metadata),
          total_cost:
            sum(
              fragment(
                "COALESCE((?->'geocoding'->>'cost_per_call')::numeric, 0)",
                v.metadata
              )
            ),
          count: count(v.id)
        },
        order_by: [desc: fragment("sum(COALESCE((?->'geocoding'->>'cost_per_call')::numeric, 0))", v.metadata)]

    case Repo.all(query) do
      results -> {:ok, results}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Count venues with failed geocoding attempts.

  ## Returns
  - `{:ok, integer}` - Number of venues with failed geocoding
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.failed_geocoding_count()
      {:ok, 5}
  """
  def failed_geocoding_count do
    query =
      from v in Venue,
        where:
          not is_nil(fragment("?->'geocoding'", v.metadata)) and
            fragment("(?->'geocoding'->>'geocoding_failed')::boolean = true", v.metadata),
        select: count(v.id)

    case Repo.one(query) do
      count -> {:ok, count}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get list of venues with failed geocoding for manual review.

  ## Parameters
  - `limit` - Maximum number of results (default: 50)

  ## Returns
  - `{:ok, [%{id: integer, name: string, address: string, failure_reason: string}]}` - Failed venues
  - `{:error, reason}` - If query fails
  """
  def failed_geocoding_venues(limit \\ 50) do
    query =
      from v in Venue,
        where:
          not is_nil(fragment("?->'geocoding'", v.metadata)) and
            fragment("(?->'geocoding'->>'geocoding_failed')::boolean = true", v.metadata),
        select: %{
          id: v.id,
          name: v.name,
          address: v.address,
          city: v.city,
          failure_reason: fragment("?->'geocoding'->>'failure_reason'", v.metadata),
          geocoded_at: fragment("(?->'geocoding'->>'geocoded_at')::timestamp", v.metadata)
        },
        order_by: [desc: fragment("(?->'geocoding'->>'geocoded_at')::timestamp", v.metadata)],
        limit: ^limit

    case Repo.all(query) do
      results -> {:ok, results}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Count venues needing manual geocoding (deferred pattern).

  ## Returns
  - `{:ok, integer}` - Number of venues needing geocoding
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.deferred_geocoding_count()
      {:ok, 23}
  """
  def deferred_geocoding_count do
    query =
      from v in Venue,
        where:
          not is_nil(fragment("?->'geocoding'", v.metadata)) and
            fragment("(?->'geocoding'->>'needs_manual_geocoding')::boolean = true", v.metadata),
        select: count(v.id)

    case Repo.one(query) do
      count -> {:ok, count}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get comprehensive geocoding statistics summary.

  Returns all key metrics in a single query for dashboard display.

  ## Returns
  - `{:ok, map}` - Complete statistics summary
  - `{:error, reason}` - If query fails

  ## Example Result

      {:ok, %{
        total_venues_geocoded: 350,
        total_cost: 4.37,
        by_provider: [...],
        by_scraper: [...],
        failed_count: 5,
        deferred_count: 23,
        free_geocoding_count: 200,
        paid_geocoding_count: 150
      }}
  """
  def summary do
    with {:ok, monthly} <- monthly_cost(),
         {:ok, by_provider} <- costs_by_provider(),
         {:ok, by_scraper} <- costs_by_scraper(),
         {:ok, failed} <- failed_geocoding_count(),
         {:ok, deferred} <- deferred_geocoding_count() do
      # Calculate free vs paid counts
      free_count =
        Enum.filter(by_provider, fn p -> p.provider in ["openstreetmap", "city_resolver_offline", "provided"] end)
        |> Enum.map(& &1.count)
        |> Enum.sum()

      paid_count = monthly.count - free_count

      {:ok,
       %{
         total_venues_geocoded: monthly.count,
         total_cost: monthly.total_cost,
         by_provider: by_provider,
         by_scraper: by_scraper,
         failed_count: failed,
         deferred_count: deferred,
         free_geocoding_count: free_count,
         paid_geocoding_count: paid_count
       }}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get geocoding costs for a specific date range.

  ## Parameters
  - `start_date` - Start of date range (inclusive)
  - `end_date` - End of date range (inclusive)

  ## Returns
  - `{:ok, %{total_cost: float, count: integer}}` - Total cost and count
  - `{:error, reason}` - If query fails
  """
  def cost_for_range(start_date, end_date) do
    # Convert Date structs to NaiveDateTime if needed
    start_datetime = case start_date do
      %Date{} -> NaiveDateTime.new!(start_date, ~T[00:00:00])
      %NaiveDateTime{} -> start_date
      %DateTime{} -> DateTime.to_naive(start_date)
    end

    end_datetime = case end_date do
      %Date{} -> NaiveDateTime.new!(end_date, ~T[23:59:59])
      %NaiveDateTime{} -> end_date
      %DateTime{} -> DateTime.to_naive(end_date)
    end

    query =
      from v in Venue,
        where:
          fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_datetime) and
            fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_datetime) and
            not is_nil(fragment("?->'geocoding'", v.metadata)),
        select: %{
          total_cost:
            sum(
              fragment(
                "COALESCE((?->'geocoding'->>'cost_per_call')::numeric, 0)",
                v.metadata
              )
            ),
          count: count(v.id)
        }

    case Repo.one(query) do
      nil ->
        {:ok, %{total_cost: 0.0, count: 0}}
      %{total_cost: nil, count: count} ->
        {:ok, %{total_cost: 0.0, count: count}}
      result ->
        {:ok, %{total_cost: result.total_cost || 0.0, count: result.count}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get success rates for each provider in the multi-provider system.

  Analyzes how often each provider successfully geocodes when attempted.
  Uses the `geocoding_metadata.attempted_providers` and `geocoding_metadata.provider` fields.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{provider: string, success_count: integer, total_attempts: integer, success_rate: float}]}`
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.success_rate_by_provider()
      {:ok, [
        %{provider: "mapbox", success_count: 120, total_attempts: 150, success_rate: 80.0},
        %{provider: "here", success_count: 18, total_attempts: 30, success_rate: 60.0},
        %{provider: "openstreetmap", success_count: 10, total_attempts: 20, success_rate: 50.0}
      ]}
  """
  def success_rate_by_provider(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    # Query for successful geocodings grouped by provider
    success_query =
      from v in Venue,
        where:
          fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
            fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
            not is_nil(fragment("?->'geocoding_metadata'", v.metadata)) and
            not is_nil(fragment("?->'geocoding_metadata'->>'provider'", v.metadata)),
        group_by: fragment("?->'geocoding_metadata'->>'provider'", v.metadata),
        select: %{
          provider: fragment("?->'geocoding_metadata'->>'provider'", v.metadata),
          success_count: count(v.id)
        }

    # Execute success query
    success_results = Repo.all(success_query)

    # Get total attempts by expanding attempted_providers arrays
    attempt_results =
      Repo.all(
        from v in Venue,
          where:
            fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
              fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
              not is_nil(fragment("?->'geocoding_metadata'", v.metadata))
      )
      |> Enum.flat_map(fn venue ->
        case get_in(venue.metadata, ["geocoding_metadata", "attempted_providers"]) do
          providers when is_list(providers) -> providers
          _ -> []
        end
      end)
      |> Enum.frequencies()

    # Combine success counts with attempt counts
    results =
      success_results
      |> Enum.map(fn success ->
        provider = success.provider
        success_count = success.success_count
        total_attempts = Map.get(attempt_results, provider, success_count)

        success_rate =
          if total_attempts > 0 do
            Float.round(success_count / total_attempts * 100, 2)
          else
            0.0
          end

        %{
          provider: provider,
          success_count: success_count,
          total_attempts: total_attempts,
          success_rate: success_rate
        }
      end)
      |> Enum.sort_by(& &1.success_rate, :desc)

    {:ok, results}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Calculate average number of provider attempts before successful geocoding.

  Analyzes the `geocoding_metadata.attempts` field to understand fallback frequency.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, %{average_attempts: float, total_geocoded: integer}}` - Average attempts and count
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.average_attempts()
      {:ok, %{average_attempts: 1.3, total_geocoded: 150, single_provider_success: 120}}
  """
  def average_attempts(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    query =
      from v in Venue,
        where:
          fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
            fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
            not is_nil(fragment("?->'geocoding_metadata'", v.metadata)) and
            not is_nil(fragment("?->'geocoding_metadata'->>'attempts'", v.metadata)),
        select: %{
          average_attempts:
            avg(
              fragment(
                "(?->'geocoding_metadata'->>'attempts')::integer",
                v.metadata
              )
            ),
          total_geocoded: count(v.id),
          single_provider_success:
            sum(
              fragment(
                "CASE WHEN (?->'geocoding_metadata'->>'attempts')::integer = 1 THEN 1 ELSE 0 END",
                v.metadata
              )
            )
        }

    case Repo.one(query) do
      nil ->
        {:ok, %{average_attempts: 0.0, total_geocoded: 0, single_provider_success: 0}}

      result ->
        {:ok,
         %{
           average_attempts: Float.round(result.average_attempts || 0.0, 2),
           total_geocoded: result.total_geocoded,
           single_provider_success: result.single_provider_success || 0
         }}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Analyze common fallback patterns in the multi-provider system.

  Shows which provider sequences are most common when primary provider fails.

  ## Parameters
  - `date` - Any date within the target month (default: current month)
  - `limit` - Maximum number of patterns to return (default: 10)

  ## Returns
  - `{:ok, [%{pattern: string, count: integer, success_provider: string}]}` - Common patterns
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.fallback_patterns()
      {:ok, [
        %{pattern: "mapbox", count: 120, success_provider: "mapbox"},
        %{pattern: "mapbox,here", count: 18, success_provider: "here"},
        %{pattern: "mapbox,here,geoapify", count: 5, success_provider: "geoapify"}
      ]}
  """
  def fallback_patterns(date \\ Date.utc_today(), limit \\ 10) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    query =
      from v in Venue,
        where:
          fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
            fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
            not is_nil(fragment("?->'geocoding_metadata'", v.metadata)),
        group_by: [
          fragment(
            "array_to_string(ARRAY(SELECT jsonb_array_elements_text(?->'geocoding_metadata'->'attempted_providers')), ',')",
            v.metadata
          ),
          fragment("?->'geocoding_metadata'->>'provider'", v.metadata)
        ],
        select: %{
          pattern:
            fragment(
              "array_to_string(ARRAY(SELECT jsonb_array_elements_text(?->'geocoding_metadata'->'attempted_providers')), ',')",
              v.metadata
            ),
          count: count(v.id),
          success_provider: fragment("?->'geocoding_metadata'->>'provider'", v.metadata)
        },
        order_by: [desc: count(v.id)],
        limit: ^limit

    case Repo.all(query) do
      results -> {:ok, results}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get provider performance comparison showing success rates and costs.

  Combines success rate data with cost data for comprehensive provider comparison.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{provider: string, success_rate: float, cost: float, count: integer}]}`
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.provider_performance()
      {:ok, [
        %{provider: "mapbox", success_rate: 85.0, total_cost: 0.0, count: 120, avg_attempts: 1.2},
        %{provider: "here", success_rate: 65.0, total_cost: 0.0, count: 30, avg_attempts: 1.8}
      ]}
  """
  def provider_performance(date \\ Date.utc_today()) do
    with {:ok, success_rates} <- success_rate_by_provider(date),
         {:ok, costs} <- costs_by_provider(date) do
      # Merge success rates with cost data
      results =
        success_rates
        |> Enum.map(fn success ->
          cost_data = Enum.find(costs, fn c -> c.provider == success.provider end) || %{total_cost: 0.0}

          %{
            provider: success.provider,
            success_rate: success.success_rate,
            total_cost: cost_data.total_cost || 0.0,
            count: success.success_count,
            total_attempts: success.total_attempts
          }
        end)
        |> Enum.sort_by(& &1.success_rate, :desc)

      {:ok, results}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Format summary statistics as a human-readable report.

  ## Parameters
  - `summary` - Output from `summary/0` function

  ## Returns
  - String formatted report
  """
  def format_report(summary) do
    """
    # Geocoding Cost Report

    ## Overview
    - Total Venues Geocoded: #{summary.total_venues_geocoded}
    - Total Cost: $#{Float.round(summary.total_cost, 2)}
    - Free Geocoding: #{summary.free_geocoding_count} venues ($0.00)
    - Paid Geocoding: #{summary.paid_geocoding_count} venues ($#{Float.round(summary.total_cost, 2)})

    ## Costs by Provider
    #{format_provider_table(summary.by_provider)}

    ## Costs by Scraper
    #{format_scraper_table(summary.by_scraper)}

    ## Issues Requiring Attention
    - Failed Geocoding: #{summary.failed_count} venues
    - Deferred Geocoding: #{summary.deferred_count} venues

    ---
    Report generated: #{DateTime.utc_now() |> DateTime.to_string()}
    """
  end

  defp format_provider_table(providers) do
    providers
    |> Enum.map(fn p ->
      "  - #{p.provider}: #{p.count} venues ($#{Float.round(p.total_cost, 2)})"
    end)
    |> Enum.join("\n")
  end

  defp format_scraper_table(scrapers) do
    scrapers
    |> Enum.map(fn s ->
      "  - #{s.scraper}: #{s.count} venues ($#{Float.round(s.total_cost, 2)})"
    end)
    |> Enum.join("\n")
  end
end
