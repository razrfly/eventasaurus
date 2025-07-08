defmodule EventasaurusWeb.Live.Components.RichDataDisplayComponent do
  @moduledoc """
  A generic reusable LiveView component for displaying rich external data.

  Uses a data adapter system to normalize different data sources (TMDB, Google Places, etc.)
  into a standardized format, then leverages a section registry to dynamically select
  the appropriate display components for each content type.

  ## Key Features:
  - **Automatic Data Adaptation**: Detects and normalizes different data formats
  - **Dynamic Section Selection**: Uses registry to map content types to components
  - **Flexible Display Modes**: Supports compact and full display modes
  - **Extensible Architecture**: Easy to add new content types and sections

  ## Attributes:
  - rich_data: Raw external data (will be automatically adapted)
  - show_sections: List of sections to display (default: auto-detected)
  - compact: Boolean for compact display mode (default: false)
  - loading: Boolean for loading state (default: false)
  - error: String for error message (default: nil)
  - class: Additional CSS classes
  - force_adapter: Atom to force specific adapter (optional)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.Live.Components.RichDataDisplayComponent}
        id="rich-data-display"
        rich_data={@raw_data}
        compact={false}
        show_sections={[:hero, :overview, :cast]}
      />

  ## Automatic Content Type Detection:

  The component automatically detects content type from the data:
  - TMDB data → :movie/:tv with sections [:hero, :overview, :cast, :media, :details]
  - Google Places data → :venue/:restaurant/:activity with sections [:hero, :details, :reviews, :photos]
  - Future data types → Automatically supported through adapter registration

  ## Extension:

  To add support for new data types:
  1. Create an adapter implementing `RichDataAdapterBehaviour`
  2. Register it with `RichDataAdapterManager`
  3. Create section components and register them with `RichDataSectionRegistry`

  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents

  alias EventasaurusWeb.Live.Components.{
    RichDataAdapterManager,
    RichDataSectionRegistry
  }

  @impl true
  def update(assigns, socket) do
    require Logger
    Logger.debug("RichDataDisplayComponent update called with rich_data: #{inspect(assigns[:rich_data])}")

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:error, fn -> nil end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:force_adapter, fn -> nil end)
     |> process_rich_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["rich-data-display", @class]}>
      <%= if @loading do %>
        <div class="animate-pulse">
          <.loading_skeleton content_type={@content_type} />
        </div>
      <% end %>

      <%= if @error do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
          <div class="flex">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-red-400" />
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">Error Loading Data</h3>
              <p class="mt-1 text-sm text-red-700"><%= @error %></p>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @standardized_data && !@loading && !@error do %>
        <div class="space-y-8">
          <%= render_sections(assigns) %>
        </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp render_sections(assigns) do
    ~H"""
    <%= for section_name <- @display_sections do %>
      <%= render_section(assigns, section_name) %>
    <% end %>
    """
  end

  defp render_section(assigns, section_name) do
    component_module = RichDataSectionRegistry.get_section_component(assigns.content_type, section_name)

    if component_module do
      assigns = Map.put(assigns, :section_name, section_name)
      render_dynamic_section(assigns, component_module)
    else
      assigns
      |> Map.put(:section_name, section_name)
      |> render_unsupported_section()
    end
  end

  defp render_dynamic_section(assigns, component_module) do
    # Generate unique ID for this section component
    section_id = "#{assigns.content_type}-#{assigns.section_name}"

    # Extract section-specific data from standardized data
    section_data = get_section_data(assigns.standardized_data, assigns.section_name)

    assigns = assign(assigns, :component_module, component_module)
    assigns = assign(assigns, :section_id, section_id)
    assigns = assign(assigns, :section_data, section_data)

    ~H"""
    <.live_component
      module={@component_module}
      id={@section_id}
      rich_data={@section_data}
      compact={@compact}
    />
    """
  end

  defp render_unsupported_section(assigns) do
    ~H"""
    <%= if Application.get_env(:eventasaurus, :env) == :dev do %>
      <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
        <div class="flex">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-yellow-400" />
          <div class="ml-3">
            <h3 class="text-sm font-medium text-yellow-800">Development Notice</h3>
            <p class="mt-1 text-sm text-yellow-700">
              No component registered for section :<%= @section_name %> of type :<%= @content_type %>
            </p>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= case @content_type do %>
        <% type when type in [:movie, :tv] -> %>
          <!-- Movie/TV skeleton -->
          <div class="relative aspect-video bg-gray-200 rounded-lg overflow-hidden">
            <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent" />
            <div class="absolute bottom-6 left-6 right-6">
              <div class="h-8 bg-gray-300 rounded w-3/4 mb-4" />
              <div class="h-4 bg-gray-300 rounded w-1/2" />
            </div>
          </div>
        <% type when type in [:venue, :restaurant, :activity] -> %>
          <!-- Venue skeleton -->
          <div class="relative aspect-video lg:aspect-[21/9] bg-gray-200 rounded-lg overflow-hidden">
            <div class="absolute bottom-6 left-6 right-6">
              <div class="h-6 bg-gray-300 rounded w-2/3 mb-2" />
              <div class="h-4 bg-gray-300 rounded w-1/2" />
            </div>
          </div>
        <% _ -> %>
          <!-- Generic skeleton -->
          <div class="h-48 bg-gray-200 rounded-lg" />
      <% end %>

      <!-- Content skeleton -->
      <div class="space-y-4">
        <div class="h-6 bg-gray-200 rounded w-1/4" />
        <div class="space-y-2">
          <div class="h-4 bg-gray-200 rounded w-full" />
          <div class="h-4 bg-gray-200 rounded w-3/4" />
        </div>
      </div>

      <%= if @content_type in [:movie, :tv] do %>
        <!-- Cast skeleton for movies -->
        <div class="space-y-4">
          <div class="h-6 bg-gray-200 rounded w-1/4" />
          <div class="flex space-x-4">
            <%= for _ <- 1..4 do %>
              <div class="flex-shrink-0">
                <div class="w-16 h-16 bg-gray-200 rounded-full" />
                <div class="h-3 bg-gray-200 rounded w-12 mt-2" />
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @content_type in [:venue, :restaurant, :activity] do %>
        <!-- Photos skeleton for venues -->
        <div class="space-y-4">
          <div class="h-6 bg-gray-200 rounded w-1/4" />
          <div class="grid grid-cols-4 gap-2">
            <%= for _ <- 1..4 do %>
              <div class="aspect-square bg-gray-200 rounded" />
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Public helper functions (maintaining backward compatibility)

  @doc """
  Generates a TMDB image URL for the given path and size.

  ## Examples

      iex> RichDataDisplayComponent.tmdb_image_url("/abc123.jpg", "w500")
      "https://image.tmdb.org/t/p/w500/abc123.jpg"
  """
  def tmdb_image_url(path, size \\ "w500")
  def tmdb_image_url(nil, _size), do: nil
  def tmdb_image_url("", _size), do: nil
  def tmdb_image_url(path, size) when is_binary(path) and is_binary(size) do
    "https://image.tmdb.org/t/p/#{size}#{path}"
  end
  def tmdb_image_url(_, _), do: nil

  # Private functions

  defp process_rich_data(socket) do
    raw_data = socket.assigns[:rich_data]
    force_adapter = socket.assigns[:force_adapter]

    case adapt_raw_data(raw_data, force_adapter) do
      {:ok, standardized_data} ->
        socket
        |> assign(:standardized_data, standardized_data)
        |> assign(:content_type, standardized_data.type)
        |> assign(:display_sections, determine_display_sections(socket.assigns, standardized_data))
        |> assign(:adaptation_error, nil)

      {:error, reason} ->
        socket
        |> assign(:standardized_data, nil)
        |> assign(:content_type, :unknown)
        |> assign(:display_sections, [])
        |> assign(:adaptation_error, reason)
        |> assign(:error, "Failed to process data: #{reason}")
    end
  end

  defp adapt_raw_data(nil, _), do: {:error, "No data provided"}
  defp adapt_raw_data(raw_data, nil) do
    RichDataAdapterManager.adapt_data(raw_data)
  end
  defp adapt_raw_data(raw_data, force_adapter) do
    RichDataAdapterManager.adapt_data(raw_data, force_adapter)
  end

  defp determine_display_sections(assigns, standardized_data) do
    # Use explicitly provided sections if available
    if assigns[:show_sections] && is_list(assigns[:show_sections]) do
      assigns[:show_sections]
    else
      # Auto-determine based on content type and compact mode
      content_type = standardized_data.type

      if assigns[:compact] do
        RichDataSectionRegistry.get_compact_sections(content_type)
      else
        RichDataSectionRegistry.get_default_sections(content_type)
      end
    end
  end

  defp get_section_data(standardized_data, section_name) do
    # Extract section-specific data from the standardized format
    section_data = get_in(standardized_data, [:sections, section_name]) || %{}

    # Merge with global data that all sections might need
    Map.merge(standardized_data, section_data)
  end
end
