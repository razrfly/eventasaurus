defmodule EventasaurusWeb.Layouts do
  use EventasaurusWeb, :html
  import EventasaurusWeb.RadiantComponents

  embed_templates "layouts/*"

  @doc """
  Check if the current path matches an admin navigation route.

  Options:
  - `:exact` - Match exactly (for dashboard home)
  - Default - Match if path starts with the given route

  ## Examples

      admin_nav_active?(@conn, "/admin", :exact)  # Only matches /admin exactly
      admin_nav_active?(@conn, "/admin/monitoring")  # Matches /admin/monitoring/*
  """
  def admin_nav_active?(conn_or_socket, path, mode \\ :prefix)

  def admin_nav_active?(%Plug.Conn{} = conn, path, :exact) do
    Phoenix.Controller.current_path(conn) == path
  end

  def admin_nav_active?(%Plug.Conn{} = conn, path, :prefix) do
    current = Phoenix.Controller.current_path(conn)
    String.starts_with?(current, path)
  end

  # Handle LiveView socket (use URI from socket)
  def admin_nav_active?(%Phoenix.LiveView.Socket{} = socket, path, mode) do
    current = socket.assigns[:current_path] || socket.assigns[:__changed__][:current_path] || "/"

    case mode do
      :exact -> current == path
      :prefix -> String.starts_with?(current, path)
    end
  end

  # Fallback for any other type - try to extract path from assigns
  # IMPORTANT: Check current_path FIRST because in LiveView layouts,
  # socket.assigns is AssignsNotInSocket during static render
  def admin_nav_active?(assigns, path, mode) when is_map(assigns) do
    cond do
      # Check current_path first - set by admin_layout hook, available in assigns
      Map.has_key?(assigns, :current_path) ->
        current = assigns.current_path || "/"

        case mode do
          :exact -> current == path
          :prefix -> String.starts_with?(current, path)
        end

      Map.has_key?(assigns, :conn) ->
        admin_nav_active?(assigns.conn, path, mode)

      # Only use socket as last resort - may have AssignsNotInSocket during render
      Map.has_key?(assigns, :socket) ->
        # Try to get current_path from socket's __changed__ tracking if available
        socket = assigns.socket

        current =
          case socket do
            %{assigns: %{current_path: cp}} when is_binary(cp) -> cp
            _ -> "/"
          end

        case mode do
          :exact -> current == path
          :prefix -> String.starts_with?(current, path)
        end

      true ->
        false
    end
  end

  @doc """
  Get the base URL for the application from endpoint configuration.
  Used for generating absolute URLs in hreflang tags and structured data.
  """
  def get_base_url do
    endpoint = Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint, [])
    url_config = Keyword.get(endpoint, :url, [])

    scheme = Keyword.get(url_config, :scheme, "https")
    host = Keyword.get(url_config, :host, "wombie.com")
    port = Keyword.get(url_config, :port)

    # Only include port if not standard (80 for http, 443 for https)
    if (scheme == "http" && port == 80) || (scheme == "https" && port == 443) || is_nil(port) do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
