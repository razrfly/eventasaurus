defmodule EventasaurusDiscovery.Metrics.GeocodingStats do
  @moduledoc """
  Query module for geocoding cost tracking and provider performance analysis.

  Provides metrics and reporting for geocoding API usage across all scrapers.
  All queries operate on `venues.geocoding_performance` JSONB field.

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

  # Use read replica for all read operations in this module
  defp repo, do: Repo.replica()

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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ),
        select: %{
          total_cost:
            sum(
              fragment(
                "COALESCE((?->>'cost_per_call')::double precision, 0.0)",
                v.geocoding_performance
              )
            ),
          count: count(v.id)
        }
      )

    case repo().one(query) do
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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ),
        group_by: fragment("?->'attempted_providers'->>-1", v.geocoding_performance),
        select: %{
          provider: fragment("?->'attempted_providers'->>-1", v.geocoding_performance),
          total_cost:
            sum(
              fragment(
                "COALESCE((?->>'cost_per_call')::double precision, 0.0)",
                v.geocoding_performance
              )
            ),
          count: count(v.id)
        },
        order_by: [
          desc:
            fragment(
              "sum(COALESCE((?->>'cost_per_call')::double precision, 0.0))",
              v.geocoding_performance
            )
        ]
      )

    case repo().all(query) do
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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ),
        group_by: fragment("?->>'source_scraper'", v.geocoding_performance),
        select: %{
          scraper: fragment("?->>'source_scraper'", v.geocoding_performance),
          total_cost:
            sum(
              fragment(
                "COALESCE((?->>'cost_per_call')::double precision, 0.0)",
                v.geocoding_performance
              )
            ),
          count: count(v.id)
        },
        order_by: [
          desc:
            fragment(
              "sum(COALESCE((?->>'cost_per_call')::double precision, 0.0))",
              v.geocoding_performance
            )
        ]
      )

    case repo().all(query) do
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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment("(?->>'geocoding_failed')::boolean = true", v.geocoding_performance),
        select: count(v.id)
      )

    case repo().one(query) do
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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment("(?->>'geocoding_failed')::boolean = true", v.geocoding_performance),
        select: %{
          id: v.id,
          name: v.name,
          address: v.address,
          city_id: v.city_id,
          failure_reason: fragment("?->>'failure_reason'", v.geocoding_performance),
          geocoded_at: fragment("(?->>'geocoded_at')::timestamp", v.geocoding_performance)
        },
        order_by: [desc: fragment("(?->>'geocoded_at')::timestamp", v.geocoding_performance)],
        limit: ^limit
      )

    case repo().all(query) do
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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment("(?->>'needs_manual_geocoding')::boolean = true", v.geocoding_performance),
        select: count(v.id)
      )

    case repo().one(query) do
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
        Enum.filter(by_provider, fn p ->
          p.provider in ["openstreetmap", "city_resolver_offline", "provided"]
        end)
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
    start_datetime =
      case start_date do
        %Date{} -> NaiveDateTime.new!(start_date, ~T[00:00:00])
        %NaiveDateTime{} -> start_date
        %DateTime{} -> DateTime.to_naive(start_date)
      end

    end_datetime =
      case end_date do
        %Date{} -> NaiveDateTime.new!(end_date, ~T[23:59:59])
        %NaiveDateTime{} -> end_date
        %DateTime{} -> DateTime.to_naive(end_date)
      end

    query =
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_datetime
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_datetime
            ),
        select: %{
          total_cost:
            sum(
              fragment(
                "COALESCE((?->>'cost_per_call')::double precision, 0.0)",
                v.geocoding_performance
              )
            ),
          count: count(v.id)
        }
      )

    case repo().one(query) do
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

    # Query for successful geocodings grouped by provider (last element of attempted_providers array)
    success_query =
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ) and
            fragment("jsonb_array_length(?->'attempted_providers') > 0", v.geocoding_performance),
        group_by: fragment("?->'attempted_providers'->>-1", v.geocoding_performance),
        select: %{
          provider: fragment("?->'attempted_providers'->>-1", v.geocoding_performance),
          success_count: count(v.id)
        }
      )

    # Execute success query
    success_results = repo().all(success_query)

    # Get total attempts by expanding attempted_providers arrays
    attempt_results =
      repo().all(
        from(v in Venue,
          where:
            not is_nil(v.geocoding_performance) and
              fragment(
                "(?->>'geocoded_at')::timestamp >= ?",
                v.geocoding_performance,
                ^start_of_month
              ) and
              fragment(
                "(?->>'geocoded_at')::timestamp <= ?",
                v.geocoding_performance,
                ^end_of_month
              )
        )
      )
      |> Enum.flat_map(fn venue ->
        case get_in(venue.geocoding_performance, ["attempted_providers"]) do
          providers when is_list(providers) -> providers
          _ -> []
        end
      end)
      |> Enum.frequencies()

    # Combine success counts with attempt counts
    # Build a map of providers with their success counts
    success_map =
      success_results
      |> Enum.into(%{}, fn %{provider: provider, success_count: count} ->
        {provider, count}
      end)

    # Get all providers (both those with successes and those with only attempts)
    providers =
      Map.keys(attempt_results)
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Map.keys(success_map)))
      |> MapSet.to_list()

    # Calculate metrics for all providers
    results =
      providers
      |> Enum.map(fn provider ->
        success_count = Map.get(success_map, provider, 0)
        total_attempts = Map.get(attempt_results, provider, success_count)
        # Ensure total_attempts is at least as large as success_count
        total_attempts = max(total_attempts, success_count)

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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ) and
            not is_nil(fragment("?->>'attempts'", v.geocoding_performance)),
        select: %{
          average_attempts:
            avg(
              fragment(
                "(?->>'attempts')::integer",
                v.geocoding_performance
              )
            ),
          total_geocoded: count(v.id),
          single_provider_success:
            sum(
              fragment(
                "CASE WHEN (?->>'attempts')::integer = 1 THEN 1 ELSE 0 END",
                v.geocoding_performance
              )
            )
        }
      )

    case repo().one(query) do
      nil ->
        {:ok, %{average_attempts: 0.0, total_geocoded: 0, single_provider_success: 0}}

      result ->
        avg_attempts =
          case result.average_attempts do
            nil -> 0.0
            %Decimal{} = d -> Decimal.to_float(d) |> Float.round(2)
            val when is_float(val) -> Float.round(val, 2)
            val when is_integer(val) -> Float.round(val * 1.0, 2)
          end

        {:ok,
         %{
           average_attempts: avg_attempts,
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
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ),
        group_by: [
          fragment(
            "array_to_string(ARRAY(SELECT jsonb_array_elements_text(?->'attempted_providers')), ',')",
            v.geocoding_performance
          ),
          fragment("?->'attempted_providers'->-1", v.geocoding_performance)
        ],
        select: %{
          pattern:
            fragment(
              "array_to_string(ARRAY(SELECT jsonb_array_elements_text(?->'attempted_providers')), ',')",
              v.geocoding_performance
            ),
          count: count(v.id),
          success_provider: fragment("?->'attempted_providers'->-1", v.geocoding_performance)
        },
        order_by: [desc: count(v.id)],
        limit: ^limit
      )

    case repo().all(query) do
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
          cost_data =
            Enum.find(costs, fn c -> c.provider == success.provider end) || %{total_cost: 0.0}

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

  @doc """
  Calculate overall geocoding success rate for the month.

  Success = venue has coordinates AND has geocoding_metadata.provider
  Failure = geocoding attempted but failed (has geocoding_metadata but no provider)

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, %{success_rate: float, total_attempts: integer, successful: integer, failed: integer}}`
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.overall_success_rate()
      {:ok, %{success_rate: 95.2, total_attempts: 150, successful: 143, failed: 7}}
  """
  def overall_success_rate(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    # Count successful geocodings (has attempted_providers array and coordinates)
    success_query =
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ) and
            fragment("jsonb_array_length(?->'attempted_providers') > 0", v.geocoding_performance) and
            not is_nil(v.latitude) and
            not is_nil(v.longitude),
        select: count(v.id)
      )

    # Count failed geocodings (has geocoding_performance but no coordinates)
    failure_query =
      from(v in Venue,
        where:
          not is_nil(v.geocoding_performance) and
            fragment(
              "(?->>'geocoded_at')::timestamp >= ?",
              v.geocoding_performance,
              ^start_of_month
            ) and
            fragment(
              "(?->>'geocoded_at')::timestamp <= ?",
              v.geocoding_performance,
              ^end_of_month
            ) and
            (is_nil(v.latitude) or is_nil(v.longitude)),
        select: count(v.id)
      )

    successful = repo().one(success_query) || 0
    failed = repo().one(failure_query) || 0
    total = successful + failed

    success_rate =
      if total > 0 do
        Float.round(successful / total * 100, 2)
      else
        0.0
      end

    {:ok,
     %{
       success_rate: success_rate,
       total_attempts: total,
       successful: successful,
       failed: failed
     }}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get usage distribution and success rates for each provider.

  Extracts all attempted_providers arrays and counts:
  - How many times each provider was attempted
  - How many times each provider succeeded
  - Success rate per provider

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{provider: string, attempts: integer, successes: integer, success_rate: float, avg_position: float}]}`
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.provider_hit_rates()
      {:ok, [
        %{provider: "mapbox", attempts: 150, successes: 143, success_rate: 95.3, avg_position: 1.0},
        %{provider: "here", attempts: 30, successes: 18, success_rate: 60.0, avg_position: 2.0}
      ]}
  """
  def provider_hit_rates(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    # Get all venues with geocoding attempts in the date range
    venues =
      repo().all(
        from(v in Venue,
          where:
            not is_nil(v.geocoding_performance) and
              fragment(
                "(?->>'geocoded_at')::timestamp >= ?",
                v.geocoding_performance,
                ^start_of_month
              ) and
              fragment(
                "(?->>'geocoded_at')::timestamp <= ?",
                v.geocoding_performance,
                ^end_of_month
              ),
          select: %{
            attempted_providers: fragment("?->'attempted_providers'", v.geocoding_performance),
            successful_provider: fragment("?->'attempted_providers'->-1", v.geocoding_performance)
          }
        )
      )

    # Count attempts per provider
    attempt_counts =
      venues
      |> Enum.flat_map(fn venue ->
        case venue.attempted_providers do
          providers when is_list(providers) ->
            providers
            |> Enum.with_index(1)
            |> Enum.map(fn {provider, position} -> {provider, position} end)

          _ ->
            []
        end
      end)
      |> Enum.reduce(%{}, fn {provider, position}, acc ->
        current = Map.get(acc, provider, %{count: 0, positions: []})

        Map.put(acc, provider, %{
          count: current.count + 1,
          positions: [position | current.positions]
        })
      end)

    # Count successes per provider
    success_counts =
      venues
      |> Enum.map(fn venue -> venue.successful_provider end)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    # Combine data
    results =
      attempt_counts
      |> Enum.map(fn {provider, data} ->
        successes = Map.get(success_counts, provider, 0)
        attempts = data.count

        success_rate =
          if attempts > 0 do
            Float.round(successes / attempts * 100, 2)
          else
            0.0
          end

        avg_position =
          if length(data.positions) > 0 do
            Float.round(Enum.sum(data.positions) / length(data.positions), 2)
          else
            0.0
          end

        %{
          provider: provider,
          attempts: attempts,
          successes: successes,
          success_rate: success_rate,
          avg_position: avg_position
        }
      end)
      |> Enum.sort_by(& &1.attempts, :desc)

    {:ok, results}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Analyze success rates by fallback depth (attempt number).

  Shows how often geocoding succeeds on 1st try, 2nd try, 3rd+ try.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{depth: integer, total: integer, successful: integer, success_rate: float}]}`
  - `{:error, reason}` - If query fails

  ## Examples

      iex> GeocodingStats.fallback_depth_analysis()
      {:ok, [
        %{depth: 1, total: 120, successful: 114, success_rate: 95.0},
        %{depth: 2, total: 25, successful: 18, success_rate: 72.0},
        %{depth: 3, total: 5, successful: 2, success_rate: 40.0}
      ]}
  """
  def fallback_depth_analysis(date \\ Date.utc_today()) do
    start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
    end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])

    # Get all venues with geocoding attempts in the date range
    venues =
      repo().all(
        from(v in Venue,
          where:
            not is_nil(v.geocoding_performance) and
              fragment(
                "(?->>'geocoded_at')::timestamp >= ?",
                v.geocoding_performance,
                ^start_of_month
              ) and
              fragment(
                "(?->>'geocoded_at')::timestamp <= ?",
                v.geocoding_performance,
                ^end_of_month
              ) and
              fragment(
                "jsonb_array_length(?->'attempted_providers') > 0",
                v.geocoding_performance
              ),
          select: %{
            attempted_providers: fragment("?->'attempted_providers'", v.geocoding_performance),
            successful_provider: fragment("?->>'provider'", v.geocoding_performance)
          }
        )
      )

    # Calculate success rate at each provider position
    # Position 1 = first provider tried, Position 2 = second provider tried, etc.
    max_depth =
      venues
      |> Enum.map(fn v ->
        case v.attempted_providers do
          providers when is_list(providers) -> length(providers)
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    results =
      1..max_depth
      |> Enum.map(fn position ->
        # Count venues that tried this position (have at least position providers in array)
        total_at_position =
          venues
          |> Enum.count(fn v ->
            case v.attempted_providers do
              providers when is_list(providers) -> length(providers) >= position
              _ -> false
            end
          end)

        # Count venues where provider at this position succeeded
        # (provider field matches the provider at index position-1)
        successful_at_position =
          venues
          |> Enum.count(fn v ->
            case v.attempted_providers do
              providers when is_list(providers) and length(providers) >= position ->
                provider_at_position = Enum.at(providers, position - 1)
                provider_at_position == v.successful_provider

              _ ->
                false
            end
          end)

        success_rate =
          if total_at_position > 0 do
            Float.round(successful_at_position / total_at_position * 100, 2)
          else
            0.0
          end

        %{
          depth: position,
          total: total_at_position,
          successful: successful_at_position,
          success_rate: success_rate
        }
      end)
      |> Enum.reject(fn row -> row.total == 0 end)

    {:ok, results}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Enhanced summary including performance metrics.

  Combines cost tracking with performance tracking for comprehensive dashboard.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, map}` - Complete statistics including performance and cost data
  - `{:error, reason}` - If query fails
  """
  def performance_summary(date \\ Date.utc_today()) do
    with {:ok, cost_summary} <- summary(),
         {:ok, success_rate} <- overall_success_rate(date),
         {:ok, hit_rates} <- provider_hit_rates(date),
         {:ok, fallback_depth} <- fallback_depth_analysis(date),
         {:ok, avg_attempts_data} <- average_attempts(date) do
      {:ok,
       Map.merge(cost_summary, %{
         overall_success_rate: success_rate,
         provider_hit_rates: hit_rates,
         fallback_depth: fallback_depth,
         average_attempts: avg_attempts_data.average_attempts
       })}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
