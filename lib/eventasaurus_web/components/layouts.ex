defmodule EventasaurusWeb.Layouts do
  use EventasaurusWeb, :html
  import EventasaurusWeb.RadiantComponents

  embed_templates "layouts/*"

  # Icon paths for admin sidebar navigation
  # Using Heroicons outline style (stroke-based)
  @admin_icons %{
    home: "M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6",
    chart_bar: "M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z",
    map_pin: "M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z M15 11a3 3 0 11-6 0 3 3 0 016 0z",
    clock: "M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z",
    upload: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12",
    document_chart: "M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
    cog: "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z",
    film: "M7 4v16M17 4v16M3 8h4m10 0h4M3 12h18M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z",
    tag: "M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z",
    archive: "M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10",
    building: "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
    duplicate: "M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z",
    photograph: "M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z",
    globe: "M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
    map: "M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7",
    server: "M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01",
    arrow_left: "M11 17l-5-5m0 0l5-5m-5 5h12"
  }

  @doc """
  Renders a sidebar navigation item with active state styling.

  ## Examples

      <.sidebar_item
        path="/admin/monitoring"
        label="Sources"
        icon={:chart_bar}
        assigns={assigns}
      />

      <.sidebar_item
        path="/admin"
        label="Dashboard"
        icon={:home}
        assigns={assigns}
        exact={true}
      />
  """
  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :icon, :atom, required: true
  attr :assigns, :map, required: true
  attr :exact, :boolean, default: false
  attr :exclude_path, :string, default: nil

  def sidebar_item(assigns) do
    mode = if assigns.exact, do: :exact, else: :prefix

    # Handle special case where we need to exclude a sub-path
    is_active =
      if assigns.exclude_path do
        admin_nav_active?(assigns.assigns, assigns.path, mode) &&
          !admin_nav_active?(assigns.assigns, assigns.exclude_path)
      else
        admin_nav_active?(assigns.assigns, assigns.path, mode)
      end

    icon_path = Map.get(@admin_icons, assigns.icon, "")

    assigns =
      assigns
      |> assign(:is_active, is_active)
      |> assign(:icon_path, icon_path)

    ~H"""
    <a href={@path} class={[
      "group relative flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-sm/6 font-medium transition-colors",
      @is_active && "text-zinc-950 bg-zinc-950/5",
      !@is_active && "text-zinc-700 hover:bg-zinc-950/5 hover:text-zinc-950"
    ]}>
      <span :if={@is_active} class="absolute inset-y-2 -left-4 w-0.5 rounded-full bg-zinc-950"></span>
      <svg class="size-5 shrink-0 text-zinc-500 group-hover:text-zinc-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d={@icon_path} />
      </svg>
      <span class="truncate"><%= @label %></span>
    </a>
    """
  end

  @doc """
  Renders a sidebar section with a title heading and nav items.

  ## Examples

      <.sidebar_section title="Monitoring">
        <.sidebar_item path="/admin/sources" label="Sources" icon={:chart_bar} assigns={assigns} />
        <.sidebar_item path="/admin/jobs" label="Jobs" icon={:clock} assigns={assigns} />
      </.sidebar_section>
  """
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def sidebar_section(assigns) do
    ~H"""
    <div class={["mt-8 flex flex-col gap-0.5", @class]}>
      <h3 class="mb-1 px-2 text-xs/6 font-medium text-zinc-500"><%= @title %></h3>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Renders a mobile sidebar navigation item (simplified, no active indicator).
  """
  attr :path, :string, required: true
  attr :label, :string, required: true

  def mobile_sidebar_item(assigns) do
    ~H"""
    <a href={@path} class="flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-base/6 font-medium text-zinc-700 hover:bg-zinc-950/5">
      <%= @label %>
    </a>
    """
  end

  @doc """
  Renders a mobile sidebar section with title.
  """
  attr :title, :string, required: true
  slot :inner_block, required: true

  def mobile_sidebar_section(assigns) do
    ~H"""
    <div class="mt-8">
      <h3 class="mb-1 px-2 text-xs/6 font-medium text-zinc-500"><%= @title %></h3>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  @doc """
  Check if the current path matches an admin navigation route.

  Options:
  - `:exact` - Match exactly (for dashboard home)
  - Default - Match if path starts with the given route

  ## Examples

      admin_nav_active?(@conn, "/admin", :exact)  # Only matches /admin exactly
      admin_nav_active?(@conn, "/admin/monitoring")  # Matches /admin/monitoring/*
  """
  @spec admin_nav_active?(Plug.Conn.t() | Phoenix.LiveView.Socket.t() | map(), String.t(), :prefix | :exact) ::
          boolean()
  def admin_nav_active?(conn_or_socket, path, mode \\ :prefix)

  def admin_nav_active?(%Plug.Conn{} = conn, path, :exact) do
    Phoenix.Controller.current_path(conn) == path
  end

  def admin_nav_active?(%Plug.Conn{} = conn, path, :prefix) do
    current = Phoenix.Controller.current_path(conn)
    String.starts_with?(current, path)
  end

  # Handle LiveView socket (use URI from socket)
  # Priority: socket.assigns.current_path (binary) > socket.assigns.__changed__[:current_path] (binary) > "/"
  def admin_nav_active?(%Phoenix.LiveView.Socket{} = socket, path, mode) do
    current = extract_current_path_from_socket(socket)

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
      is_binary(assigns[:current_path]) ->
        current = assigns.current_path

        case mode do
          :exact -> current == path
          :prefix -> String.starts_with?(current, path)
        end

      Map.has_key?(assigns, :current_path) ->
        # current_path exists but is nil - default to "/"
        case mode do
          :exact -> "/" == path
          :prefix -> String.starts_with?("/", path)
        end

      Map.has_key?(assigns, :conn) ->
        admin_nav_active?(assigns.conn, path, mode)

      # Only use socket as last resort - may have AssignsNotInSocket during render
      Map.has_key?(assigns, :socket) ->
        socket = assigns.socket
        current = extract_current_path_from_socket(socket)

        case mode do
          :exact -> current == path
          :prefix -> String.starts_with?(current, path)
        end

      true ->
        false
    end
  end

  # Extract current_path from socket with robust fallback chain
  # Returns a binary path, guaranteed - defaults to "/" if no valid path found
  defp extract_current_path_from_socket(socket) do
    cond do
      # First: direct assigns.current_path if it's a binary
      is_binary(socket.assigns[:current_path]) ->
        socket.assigns.current_path

      # Second: __changed__ map with binary current_path
      is_map(socket.assigns[:__changed__]) and is_binary(socket.assigns.__changed__[:current_path]) ->
        socket.assigns.__changed__[:current_path]

      # Fallback: default to root
      true ->
        "/"
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
