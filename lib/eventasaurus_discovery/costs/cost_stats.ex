defmodule EventasaurusDiscovery.Costs.CostStats do
  @moduledoc """
  Query module for external service cost tracking and analysis.

  Provides metrics and reporting for all external service costs including:
  - Web scraping (Crawlbase, Zyte)
  - Geocoding (Google Places, Google Maps)
  - ML inference (Hugging Face, planned)
  - LLM providers (Anthropic, OpenAI, planned)

  ## Usage Examples

      # Get total costs for current month
      CostStats.monthly_total()

      # Get costs by service type
      CostStats.costs_by_service_type()

      # Get costs by provider
      CostStats.costs_by_provider()

      # Get daily cost breakdown
      CostStats.daily_costs(~D[2025-01-01], ~D[2025-01-31])
  """

  import Ecto.Query
  alias EventasaurusDiscovery.Costs.ExternalServiceCost
  alias EventasaurusApp.Repo

  # Use read replica for all read operations
  defp repo, do: Repo.replica()

  @doc """
  Calculate total costs for a given month.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, %{total_cost: Decimal, count: integer}}` - Total cost and record count

  ## Examples

      iex> CostStats.monthly_total(~D[2025-01-15])
      {:ok, %{total_cost: Decimal.new("127.45"), count: 15420}}
  """
  def monthly_total(date \\ Date.utc_today()) do
    {start_dt, end_dt} = month_range(date)

    query =
      from(c in ExternalServiceCost,
        where: c.occurred_at >= ^start_dt and c.occurred_at <= ^end_dt,
        select: %{
          total_cost: sum(c.cost_usd),
          count: count(c.id)
        }
      )

    case repo().one(query) do
      nil ->
        {:ok, %{total_cost: Decimal.new("0.00"), count: 0}}

      %{total_cost: nil, count: count} ->
        {:ok, %{total_cost: Decimal.new("0.00"), count: count}}

      result ->
        {:ok, %{total_cost: result.total_cost || Decimal.new("0.00"), count: result.count}}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get costs broken down by service type.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{service_type: string, total_cost: Decimal, count: integer}]}`

  ## Examples

      iex> CostStats.costs_by_service_type()
      {:ok, [
        %{service_type: "geocoding", total_cost: Decimal.new("89.20"), count: 2450},
        %{service_type: "scraping", total_cost: Decimal.new("28.15"), count: 1410},
        %{service_type: "ml_inference", total_cost: Decimal.new("10.10"), count: 340}
      ]}
  """
  def costs_by_service_type(date \\ Date.utc_today()) do
    {start_dt, end_dt} = month_range(date)

    query =
      from(c in ExternalServiceCost,
        where: c.occurred_at >= ^start_dt and c.occurred_at <= ^end_dt,
        group_by: c.service_type,
        select: %{
          service_type: c.service_type,
          total_cost: sum(c.cost_usd),
          count: count(c.id)
        },
        order_by: [desc: sum(c.cost_usd)]
      )

    {:ok, repo().all(query)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get costs broken down by provider.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{provider: string, service_type: string, total_cost: Decimal, count: integer}]}`

  ## Examples

      iex> CostStats.costs_by_provider()
      {:ok, [
        %{provider: "google_places", service_type: "geocoding", total_cost: Decimal.new("78.40"), count: 2450},
        %{provider: "crawlbase", service_type: "scraping", total_cost: Decimal.new("23.00"), count: 1150},
        %{provider: "zyte", service_type: "scraping", total_cost: Decimal.new("5.15"), count: 260}
      ]}
  """
  def costs_by_provider(date \\ Date.utc_today()) do
    {start_dt, end_dt} = month_range(date)

    query =
      from(c in ExternalServiceCost,
        where: c.occurred_at >= ^start_dt and c.occurred_at <= ^end_dt,
        group_by: [c.provider, c.service_type],
        select: %{
          provider: c.provider,
          service_type: c.service_type,
          total_cost: sum(c.cost_usd),
          count: count(c.id)
        },
        order_by: [desc: sum(c.cost_usd)]
      )

    {:ok, repo().all(query)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get costs broken down by operation within a provider.

  ## Parameters
  - `provider` - Provider name (e.g., "crawlbase", "zyte")
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{operation: string, total_cost: Decimal, count: integer, avg_cost: Decimal}]}`

  ## Examples

      iex> CostStats.costs_by_operation("crawlbase")
      {:ok, [
        %{operation: "javascript", total_cost: Decimal.new("17.80"), count: 890, avg_cost: Decimal.new("0.02")},
        %{operation: "normal", total_cost: Decimal.new("5.20"), count: 520, avg_cost: Decimal.new("0.01")}
      ]}
  """
  def costs_by_operation(provider, date \\ Date.utc_today()) do
    {start_dt, end_dt} = month_range(date)

    query =
      from(c in ExternalServiceCost,
        where:
          c.occurred_at >= ^start_dt and
            c.occurred_at <= ^end_dt and
            c.provider == ^provider,
        group_by: c.operation,
        select: %{
          operation: c.operation,
          total_cost: sum(c.cost_usd),
          count: count(c.id),
          avg_cost: avg(c.cost_usd)
        },
        order_by: [desc: sum(c.cost_usd)]
      )

    {:ok, repo().all(query)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get daily cost breakdown for a date range.

  ## Parameters
  - `start_date` - Start date
  - `end_date` - End date (default: today)

  ## Returns
  - `{:ok, [%{date: Date, total_cost: Decimal, count: integer}]}`

  ## Examples

      iex> CostStats.daily_costs(~D[2025-01-01], ~D[2025-01-07])
      {:ok, [
        %{date: ~D[2025-01-01], total_cost: Decimal.new("4.25"), count: 520},
        %{date: ~D[2025-01-02], total_cost: Decimal.new("3.80"), count: 480},
        ...
      ]}
  """
  def daily_costs(start_date, end_date \\ Date.utc_today()) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(c in ExternalServiceCost,
        where: c.occurred_at >= ^start_dt and c.occurred_at <= ^end_dt,
        group_by: fragment("DATE(?)", c.occurred_at),
        select: %{
          date: fragment("DATE(?)", c.occurred_at),
          total_cost: sum(c.cost_usd),
          count: count(c.id)
        },
        order_by: [asc: fragment("DATE(?)", c.occurred_at)]
      )

    {:ok, repo().all(query)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get daily costs by service type for trend analysis.

  ## Parameters
  - `start_date` - Start date
  - `end_date` - End date (default: today)

  ## Returns
  - `{:ok, [%{date: Date, service_type: string, total_cost: Decimal, count: integer}]}`
  """
  def daily_costs_by_service(start_date, end_date \\ Date.utc_today()) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    query =
      from(c in ExternalServiceCost,
        where: c.occurred_at >= ^start_dt and c.occurred_at <= ^end_dt,
        group_by: [fragment("DATE(?)", c.occurred_at), c.service_type],
        select: %{
          date: fragment("DATE(?)", c.occurred_at),
          service_type: c.service_type,
          total_cost: sum(c.cost_usd),
          count: count(c.id)
        },
        order_by: [asc: fragment("DATE(?)", c.occurred_at), asc: c.service_type]
      )

    {:ok, repo().all(query)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get top cost drivers (provider + operation combinations).

  ## Parameters
  - `limit` - Maximum number of results (default: 10)
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, [%{provider: string, operation: string, total_cost: Decimal, count: integer}]}`
  """
  def top_cost_drivers(limit \\ 10, date \\ Date.utc_today()) do
    {start_dt, end_dt} = month_range(date)

    query =
      from(c in ExternalServiceCost,
        where: c.occurred_at >= ^start_dt and c.occurred_at <= ^end_dt,
        group_by: [c.provider, c.operation],
        select: %{
          provider: c.provider,
          operation: c.operation,
          total_cost: sum(c.cost_usd),
          count: count(c.id)
        },
        order_by: [desc: sum(c.cost_usd)],
        limit: ^limit
      )

    {:ok, repo().all(query)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get a summary of all costs for dashboard display.

  ## Parameters
  - `date` - Any date within the target month (default: current month)

  ## Returns
  - `{:ok, map}` with keys: :total, :by_service_type, :by_provider, :top_drivers
  """
  def dashboard_summary(date \\ Date.utc_today()) do
    with {:ok, total} <- monthly_total(date),
         {:ok, by_service_type} <- costs_by_service_type(date),
         {:ok, by_provider} <- costs_by_provider(date),
         {:ok, top_drivers} <- top_cost_drivers(5, date) do
      {:ok,
       %{
         total: total,
         by_service_type: by_service_type,
         by_provider: by_provider,
         top_drivers: top_drivers
       }}
    end
  end

  # Private helper to get month date range as DateTimes
  defp month_range(date) do
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)

    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    {start_dt, end_dt}
  end
end
