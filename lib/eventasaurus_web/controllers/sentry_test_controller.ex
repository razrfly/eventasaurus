defmodule EventasaurusWeb.SentryTestController do
  use EventasaurusWeb, :controller
  require Logger

  def test_error(conn, _params) do
    try do
      a = 1 / 0
      IO.puts(a)
    rescue
      my_exception ->
        Sentry.capture_exception(my_exception, stacktrace: __STACKTRACE__)

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Test error sent to Sentry"})
    end
  end

  def test_message(conn, _params) do
    Sentry.capture_message("Test message from Eventasaurus", level: :info)

    conn
    |> put_status(:ok)
    |> json(%{message: "Test message sent to Sentry"})
  end

  def test_production_error(conn, _params) do
    # Only allow in production with specific header for security
    if Mix.env() == :prod and get_req_header(conn, "x-sentry-test") == ["production-test"] do
      # Audit log the production test request
      Logger.info("Production Sentry test triggered",
        remote_ip: format_ip(conn.remote_ip),
        user_agent: get_req_header(conn, "user-agent") |> List.first(),
        user_id: get_user_id(conn),
        timestamp: DateTime.utc_now()
      )

      try do
        # Simulate a production error
        raise "Production Sentry Test Error - #{DateTime.utc_now()}"
      rescue
        exception ->
          case Sentry.capture_exception(exception, stacktrace: __STACKTRACE__) do
            {:ok, event_id} ->
              Logger.info("Production Sentry test completed successfully",
                event_id: event_id,
                timestamp: DateTime.utc_now()
              )

              conn
              |> put_status(:ok)
              |> json(%{
                success: true,
                message: "Production test error sent to Sentry",
                event_id: event_id,
                timestamp: DateTime.utc_now(),
                environment: Mix.env()
              })

            {:error, reason} ->
              Logger.error("Failed to send production test error to Sentry",
                reason: reason,
                timestamp: DateTime.utc_now()
              )

              conn
              |> put_status(:internal_server_error)
              |> json(%{
                error: "Failed to send test error to Sentry",
                reason: to_string(reason),
                timestamp: DateTime.utc_now()
              })
          end
      end
    else
      # Log unauthorized access attempts
      Logger.warning("Unauthorized access attempt to production Sentry test endpoint",
        remote_ip: format_ip(conn.remote_ip),
        user_agent: get_req_header(conn, "user-agent") |> List.first(),
        headers: get_req_header(conn, "x-sentry-test"),
        environment: Mix.env()
      )

      conn
      |> put_status(:forbidden)
      |> json(%{error: "Production test endpoint requires proper environment and headers"})
    end
  end

  def health_check(conn, _params) do
    sentry_configured =
      case Application.get_env(:sentry, :dsn) do
        nil -> false
        "" -> false
        _dsn -> true
      end

    conn
    |> put_status(:ok)
    |> json(%{
      sentry_configured: sentry_configured,
      environment: Mix.env(),
      timestamp: DateTime.utc_now()
    })
  end

  # Helper functions for logging
  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_), do: "unknown"

  defp get_user_id(conn) do
    case conn.assigns[:user] do
      %{id: user_id} -> user_id
      _ -> nil
    end
  end
end
