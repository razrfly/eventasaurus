defmodule EventasaurusDiscovery.Http.Telemetry do
  @moduledoc """
  Telemetry event handlers for HTTP client monitoring.

  Captures HTTP request lifecycle events to provide visibility into
  request performance, adapter usage, and blocking detection.

  ## Events Monitored

  - `[:eventasaurus, :http, :request, :start]` - Request begins
  - `[:eventasaurus, :http, :request, :stop]` - Request completes successfully
  - `[:eventasaurus, :http, :request, :exception]` - Request fails with error
  - `[:eventasaurus, :http, :blocked]` - Adapter blocked, fallback triggered

  ## Usage

  This module is automatically attached during application startup via
  `EventasaurusApp.Application.start/2`.

  ## Metrics Tracked

  - Request duration by source and adapter
  - Success/failure rates by source
  - Blocking events by adapter and blocking type
  - Fallback usage frequency
  - Adapter selection patterns
  """

  require Logger

  @doc """
  Attaches telemetry handlers for HTTP client events.

  This should be called once during application startup.
  """
  def attach do
    events = [
      [:eventasaurus, :http, :request, :start],
      [:eventasaurus, :http, :request, :stop],
      [:eventasaurus, :http, :request, :exception],
      [:eventasaurus, :http, :blocked]
    ]

    :telemetry.attach_many(
      "http-client-monitoring",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("📡 HTTP client telemetry handlers attached")
  end

  @doc """
  Handles telemetry events from the HTTP client.
  """
  def handle_event([:eventasaurus, :http, :request, :start], _measurements, metadata, _config) do
    Logger.debug(
      "🌐 HTTP request started",
      url: metadata.url,
      source: metadata.source,
      strategy: metadata.strategy,
      adapter_chain: metadata.adapter_chain
    )

    :ok
  end

  def handle_event([:eventasaurus, :http, :request, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.debug("""
    ✅ HTTP request completed
    URL: #{metadata.url}
    Source: #{metadata.source}
    Adapter: #{metadata.adapter}
    Status: #{metadata.status_code}
    Duration: #{duration_ms}ms
    Attempts: #{metadata.attempts}
    #{if length(metadata.blocked_by) > 0, do: "Blocked by: #{Enum.join(metadata.blocked_by, ", ")}", else: ""}
    """)

    # Track slow requests
    if duration_ms > 5000 do
      Logger.warning(
        "⚠️  Slow HTTP request: #{duration_ms}ms",
        url: metadata.url,
        source: metadata.source,
        adapter: metadata.adapter
      )
    end

    # Track fallback usage
    if metadata.attempts > 1 do
      Logger.info(
        "📊 HTTP fallback used: #{metadata.attempts} attempts",
        url: metadata.url,
        source: metadata.source,
        adapter: metadata.adapter,
        blocked_by: metadata.blocked_by
      )
    end

    :ok
  end

  def handle_event([:eventasaurus, :http, :request, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.warning("""
    ❌ HTTP request failed
    URL: #{metadata.url}
    Source: #{metadata.source}
    Duration: #{duration_ms}ms
    Error: #{inspect(metadata.error)}
    """)

    # Report critical errors (all adapters failed)
    case metadata.error do
      {:all_adapters_failed, blocked_by} ->
        Logger.error(
          "🚨 All HTTP adapters failed",
          url: metadata.url,
          source: metadata.source,
          blocked_by: Enum.map(blocked_by, & &1.adapter)
        )

        report_to_sentry(:all_adapters_failed, metadata, blocked_by)

      {:http_error, status_code, _body, _meta} when status_code >= 500 ->
        Logger.error(
          "🚨 HTTP server error",
          url: metadata.url,
          source: metadata.source,
          status_code: status_code
        )

      _ ->
        :ok
    end

    :ok
  end

  def handle_event([:eventasaurus, :http, :blocked], _measurements, metadata, _config) do
    Logger.info("""
    🛡️ HTTP adapter blocked
    URL: #{metadata.url}
    Source: #{metadata.source}
    Adapter: #{metadata.adapter}
    Blocking type: #{metadata.blocking_type}
    Status code: #{metadata.status_code}
    #{if Map.has_key?(metadata, :retry_after), do: "Retry after: #{metadata.retry_after}s", else: ""}
    """)

    # Track blocking patterns for analysis
    case metadata.blocking_type do
      :cloudflare ->
        Logger.warning(
          "🔒 Cloudflare blocking detected",
          source: metadata.source,
          adapter: metadata.adapter
        )

      :rate_limit ->
        retry_after = Map.get(metadata, :retry_after, "unknown")

        Logger.warning(
          "⏱️ Rate limit detected, retry after #{retry_after}s",
          source: metadata.source,
          adapter: metadata.adapter
        )

      :captcha ->
        Logger.warning(
          "🤖 CAPTCHA challenge detected",
          source: metadata.source,
          adapter: metadata.adapter
        )

      _ ->
        :ok
    end

    :ok
  end

  # Report critical HTTP errors to Sentry (if configured)
  defp report_to_sentry(error_type, metadata, blocked_by) do
    if Code.ensure_loaded?(Sentry) do
      context = %{
        url: metadata.url,
        source: metadata.source,
        error_type: error_type,
        blocked_by:
          Enum.map(blocked_by, fn block ->
            %{
              adapter: block.adapter,
              blocking_type: Map.get(block, :blocking_type),
              status_code: Map.get(block, :status_code),
              error: Map.get(block, :error) |> inspect()
            }
          end)
      }

      title = "HTTP All Adapters Failed: #{metadata.source}"

      tags = %{
        error_type: to_string(error_type),
        source: to_string(metadata.source)
      }

      Sentry.capture_message(title,
        level: :error,
        extra: context,
        tags: tags
      )

      Logger.debug("📡 Reported HTTP failure to Sentry: #{title}")
    end
  end
end
