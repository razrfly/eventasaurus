defmodule EventasaurusWeb.Plugs.ObanAuthPlug do
  @moduledoc """
  Plug for authenticating Oban Web UI access.

  This plug provides two authentication methods:
  1. Admin email list - checks if the logged-in user's email is in the ADMIN_EMAILS env var
  2. Admin password - fallback to OBAN_PASSWORD env var for backward compatibility

  If ADMIN_EMAILS is configured, users with emails in that list bypass the password prompt.
  Otherwise, falls back to the legacy OBAN_PASSWORD authentication.
  """

  import Plug.Conn
  import Phoenix.Controller

  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router

  require Logger

  def init(default), do: default

  def call(conn, _default) do
    # Check if user is authorized via email list
    if is_admin_email?(conn) do
      conn
    else
      # Fall back to password authentication for backward compatibility
      handle_password_auth(conn)
    end
  end

  # Check if the current user's email is in the admin email list
  defp is_admin_email?(conn) do
    admin_emails = get_admin_emails()
    current_user = conn.assigns[:user]

    # Only check if we have both admin emails configured and a logged-in user
    admin_emails != [] && current_user && current_user.email &&
      String.downcase(current_user.email) in admin_emails
  end

  # Parse the ADMIN_EMAILS environment variable into a list
  defp get_admin_emails do
    case System.get_env("ADMIN_EMAILS") do
      nil ->
        []

      "" ->
        []

      emails ->
        emails
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.downcase/1)
        |> Enum.filter(&(&1 != ""))
    end
  end

  # Handle legacy password authentication
  defp handle_password_auth(conn) do
    admin_password = System.get_env("OBAN_PASSWORD")

    cond do
      # If no admin password is configured, check if we should provide more helpful message
      is_nil(admin_password) or admin_password == "" ->
        admin_emails = get_admin_emails()

        error_message =
          if admin_emails == [] do
            "Admin access is not configured. Please set either ADMIN_EMAILS or OBAN_PASSWORD environment variable."
          else
            "Access denied. Your email is not authorized for admin access."
          end

        conn
        |> put_flash(:error, error_message)
        |> redirect(to: ~p"/dashboard")
        |> halt()

      # If session already verified with current password digest, allow access
      get_session(conn, "oban_admin_token") == oban_password_digest(admin_password) ->
        conn

      # Handle POSTed password securely
      conn.method == "POST" and is_binary(conn.params["admin_password"]) and
          Plug.Crypto.secure_compare(conn.params["admin_password"], admin_password) ->
        conn
        |> configure_session(renew: true)
        |> put_session("oban_admin_token", oban_password_digest(admin_password))
        # clear query params
        |> redirect(to: conn.request_path)
        |> halt()

      # If this is a GET request, show auth form
      conn.method == "GET" ->
        show_auth_form(conn)

      # Wrong password provided
      true ->
        show_auth_form(conn, "Invalid admin password")
    end
  end

  defp oban_password_digest(password) do
    :crypto.hash(:sha256, password) |> Base.url_encode64()
  end

  defp show_auth_form(conn, error_message \\ nil) do
    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Oban Admin Authentication</title>
      <style nonce="#{conn.assigns[:csp_nonce]}">
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          margin: 0;
          padding: 0;
          background: #f5f5f5;
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
        }
        .auth-container {
          background: white;
          padding: 2rem;
          border-radius: 8px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
          width: 100%;
          max-width: 400px;
        }
        .logo {
          text-align: center;
          margin-bottom: 2rem;
          color: #333;
        }
        .form-group {
          margin-bottom: 1rem;
        }
        label {
          display: block;
          margin-bottom: 0.5rem;
          font-weight: 500;
          color: #333;
        }
        input[type="password"] {
          width: 100%;
          padding: 0.75rem;
          border: 1px solid #ddd;
          border-radius: 4px;
          font-size: 1rem;
          box-sizing: border-box;
        }
        input[type="password"]:focus {
          outline: none;
          border-color: #007bff;
          box-shadow: 0 0 0 2px rgba(0,123,255,0.25);
        }
        button {
          width: 100%;
          padding: 0.75rem;
          background: #007bff;
          color: white;
          border: none;
          border-radius: 4px;
          font-size: 1rem;
          cursor: pointer;
          font-weight: 500;
        }
        button:hover {
          background: #0056b3;
        }
        .error {
          color: #dc3545;
          background: #f8d7da;
          border: 1px solid #f5c6cb;
          padding: 0.75rem;
          border-radius: 4px;
          margin-bottom: 1rem;
        }
        .info {
          color: #721c24;
          font-size: 0.875rem;
          margin-top: 1rem;
          text-align: center;
        }
      </style>
    </head>
    <body>
      <div class="auth-container">
        <div class="logo">
          <h2>🔒 Oban Admin Access</h2>
        </div>
        
        #{if error_message, do: ~s(<div class="error">#{error_message}</div>), else: ""}
        
        <form method="post" action="#{conn.request_path}">
          <input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}">
          <div class="form-group">
            <label for="admin_password">Admin Password:</label>
            <input type="password" id="admin_password" name="admin_password" required autofocus autocomplete="current-password">
          </div>
          
          <button type="submit">Access Oban Dashboard</button>
        </form>
        
        <div class="info">
          Enter the admin password to access the Oban Web UI dashboard.
        </div>
      </div>
    </body>
    </html>
    """

    status = if error_message, do: 401, else: 200

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end
end
