defmodule EventasaurusWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :eventasaurus

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_eventasaurus_key",
    signing_salt: "ouM7Fmf1",
    # Configure session for persistent login support
    max_age: 30 * 24 * 60 * 60,  # 30 days default (can be overridden per session)
    same_site: "Lax",             # Better security for modern browsers (CSRF protection)
    secure: Application.compile_env(:eventasaurus, :environment) == :prod,  # HTTPS only in production
    http_only: true               # Prevent XSS attacks by blocking JavaScript access
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

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

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EventasaurusWeb.Router
end
