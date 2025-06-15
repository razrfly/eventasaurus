defmodule EventasaurusWeb.Plugs.SecurityPlug do
  @moduledoc """
  Security plug for enforcing HTTPS and other security measures.

  This plug provides:
  - HTTPS enforcement for sensitive endpoints
  - Security headers
  - Request validation
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    conn
    |> maybe_enforce_https(opts)
    |> add_security_headers(opts)
    |> validate_request_size(opts)
  end

  # HTTPS Enforcement
  defp maybe_enforce_https(conn, opts) do
    if Keyword.get(opts, :force_https, false) do
      enforce_https(conn)
    else
      conn
    end
  end

  defp enforce_https(conn) do
    if https_required?() and not secure_request?(conn) do
      Logger.warning("HTTPS required but request is not secure",
        path: conn.request_path,
        method: conn.method,
        remote_ip: format_ip(conn.remote_ip)
      )

      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{
        error: "https_required",
        message: "HTTPS is required for this endpoint"
      })
      |> halt()
    else
      conn
    end
  end

  defp https_required? do
    case System.get_env("FORCE_HTTPS") do
      "true" -> true
      "false" -> false
      nil -> Application.get_env(:eventasaurus, :force_https, false)
      _ -> false
    end
  end

  defp secure_request?(conn) do
    # Check if request is over HTTPS
    case get_req_header(conn, "x-forwarded-proto") do
      ["https"] -> true
      _ -> conn.scheme == :https
    end
  end

  # Security Headers
  defp add_security_headers(conn, opts) do
    if Keyword.get(opts, :security_headers, true) do
      conn
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("x-frame-options", "DENY")
      |> put_resp_header("x-xss-protection", "1; mode=block")
      |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
      |> put_resp_header("permissions-policy", "geolocation=(), microphone=(), camera=()")
      |> maybe_add_hsts_header()
    else
      conn
    end
  end

  defp maybe_add_hsts_header(conn) do
    if secure_request?(conn) do
      put_resp_header(conn, "strict-transport-security", "max-age=31536000; includeSubDomains")
    else
      conn
    end
  end

  # Request Size Validation
  defp validate_request_size(conn, opts) do
    max_size = Keyword.get(opts, :max_request_size, 10_000_000)  # 10MB default

    case get_req_header(conn, "content-length") do
      [size_str] ->
        case Integer.parse(size_str) do
          {size, ""} when size > max_size ->
            Logger.warning("Request size exceeds limit",
              size: size,
              max_size: max_size,
              path: conn.request_path,
              remote_ip: format_ip(conn.remote_ip)
            )

            conn
            |> put_status(:request_entity_too_large)
            |> Phoenix.Controller.json(%{
              error: "request_too_large",
              message: "Request size exceeds maximum allowed size"
            })
            |> halt()

          _ ->
            conn
        end

      _ ->
        conn
    end
  end

  # Helper Functions
  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(_), do: "unknown"
end
