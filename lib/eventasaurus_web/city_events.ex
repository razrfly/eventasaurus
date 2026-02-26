defmodule EventasaurusWeb.CityEvents do
  @moduledoc """
  Shared resilience primitives for city page event fetching.

  Encapsulates the common Tier 3–4 logic used by both CityLive and the mobile API:
  - `fetch_from_mv/2`          — Tier 3: MV fallback
  - `with_circuit_breaker/3`   — Tier 4: live query wrapped in circuit breaker
  - `serve_degraded/2`         — Tier 4 failure: MV → empty

  The high-level cache routing (base cache, per-filter cache decisions) stays in
  each caller since it is web-specific.
  """

  alias EventasaurusWeb.Cache.CityEventsFallback
  alias EventasaurusWeb.Cache.LiveQueryCircuitBreaker
  require Logger

  @type result_tuple :: {list(), non_neg_integer(), non_neg_integer(), map(), atom()}

  @doc """
  Try to serve events from the materialized view (Tier 3).

  Returns `{:ok, {events, total, all_count, date_counts, :mv_fallback}}` on hit,
  or `:miss` when the MV is empty, city_slug is nil, or an error occurs.

  ## Options

    * `:page` (default 1)
    * `:page_size` (default 30)
    * `:skip` (default false) — pass `true` when caller has complex filters the MV can't handle
  """
  @spec fetch_from_mv(String.t() | nil, keyword()) :: {:ok, result_tuple()} | :miss
  def fetch_from_mv(nil, _opts), do: :miss

  def fetch_from_mv(city_slug, opts) when is_binary(city_slug) do
    if Keyword.get(opts, :skip, false) do
      :miss
    else
      mv_opts = [
        page: Keyword.get(opts, :page, 1),
        page_size: Keyword.get(opts, :page_size, 30)
      ]

      case CityEventsFallback.get_events_with_counts(city_slug, mv_opts) do
        {:ok, %{events: [_ | _] = events} = data} ->
          {:ok,
           {events, data.total_count, data.all_events_count, data.date_counts, :mv_fallback}}

        _ ->
          :miss
      end
    end
  end

  @doc """
  Run `live_query_fn` inside the circuit breaker.

  On success returns the result of `live_query_fn` (which must return a result_tuple).
  On failure or open circuit calls the `:on_failure` opt if provided, otherwise
  falls back to `serve_degraded/2`.

  ## Options

    * `:on_failure` — `fn() -> result_tuple` — custom degraded fallback
  """
  @spec with_circuit_breaker(String.t() | nil, (-> result_tuple()), keyword()) :: result_tuple()
  def with_circuit_breaker(city_slug, live_query_fn, opts \\ []) do
    fallback_fn =
      Keyword.get(opts, :on_failure, fn -> serve_degraded(city_slug) end)

    case LiveQueryCircuitBreaker.allow_request?() do
      :ok ->
        try do
          result = live_query_fn.()
          LiveQueryCircuitBreaker.record_success()
          result
        rescue
          e ->
            LiveQueryCircuitBreaker.record_failure(Exception.message(e))

            Logger.warning(
              "[CityEvents] Live query failed for #{city_slug}: #{Exception.message(e)}"
            )

            fallback_fn.()
        end

      {:circuit_open, :serve_fallback} ->
        Logger.info("[CityEvents] Circuit OPEN for #{city_slug} — serving degraded fallback")
        fallback_fn.()
    end
  end

  @doc """
  Serve-stale-on-error: try MV → empty (Tier 4 failure path).

  Emits `[:eventasaurus, :fallback, :degraded]` telemetry at each step.
  Returns `{events, total, all_count, date_counts, :degraded_mv | :degraded_empty}`.

  Note: the web caller (`city_live`) inserts a stale Cachex step between MV and empty
  by calling `fetch_from_mv/2` first and wrapping this function for the empty case.
  """
  @spec serve_degraded(String.t() | nil, keyword()) :: result_tuple()
  def serve_degraded(city_slug, _opts \\ []) do
    case CityEventsFallback.get_events_with_counts(city_slug || "") do
      {:ok, %{events: [_ | _] = events} = data} ->
        emit_degraded(:mv, city_slug)
        {events, data.total_count, data.all_events_count, data.date_counts, :degraded_mv}

      _ ->
        emit_degraded(:empty, city_slug)
        {[], 0, 0, %{}, :degraded_empty}
    end
  end

  defp emit_degraded(source, city_slug) do
    :telemetry.execute(
      [:eventasaurus, :fallback, :degraded],
      %{system_time: System.system_time(:millisecond)},
      %{source: source, city: city_slug}
    )
  end
end
