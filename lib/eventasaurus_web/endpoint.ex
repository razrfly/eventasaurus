defmodule EventasaurusWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :eventasaurus

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_eventasaurus_key",
    signing_salt: "ouM7Fmf1",
    # Configure session for persistent login support
    # 30 days default (can be overridden per session)
    max_age: 30 * 24 * 60 * 60,
    # Better security for modern browsers (CSRF protection)
    same_site: "Lax",
    # HTTPS only in production
    secure: Application.compile_env(:eventasaurus, :environment) == :prod,
    # Prevent XSS attacks by blocking JavaScript access
    http_only: true
  ]

  # CDN Caching: Disable CSRF check and session requirement for WebSocket connections.
  # This enables HTTP caching of LiveView pages by removing the session cookie dependency.
  #
  # Why session is removed from connect_info:
  # - CDN caching strips Set-Cookie headers, so first-time visitors have no session cookie
  # - Without session cookie, LiveView returns "stale" error and causes infinite reload loop
  # - Auth is handled by Clerk (client-side), not session cookies
  # - No LiveView code uses get_connect_info(:session) in this codebase
  #
  # Security: check_origin is enabled in production (via runtime.exs) to prevent
  # Cross-Site WebSocket Hijacking (CSWSH) attacks. Origin validation is sufficient
  # security for WebSocket since SameSite cookie attribute doesn't apply to WS.
  #
  # See: https://svground.fr/blog/posts/caching-liveviews-part-1/
  # See: https://github.com/razrfly/eventasaurus/issues/2970
  # See: https://github.com/razrfly/eventasaurus/issues/2981
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [check_csrf: false, connect_info: [:uri]],
    longpoll: [connect_info: [:uri]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :eventasaurus,
    gzip: false,
    only: EventasaurusWeb.static_paths()

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EventasaurusWeb.Router
end
