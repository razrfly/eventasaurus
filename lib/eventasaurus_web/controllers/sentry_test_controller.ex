defmodule EventasaurusWeb.SentryTestController do
  use EventasaurusWeb, :controller

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
end