defmodule EventasaurusWeb.Admin.CategoryHierarchyLive do
  @moduledoc """
  LiveView for category hierarchy tree view.
  Shows collapsible tree structure with parent-child relationships and aggregate counts.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.CategoryAnalytics
  alias EventasaurusDiscovery.Categories

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Category Hierarchy")
      |> assign(:loading, true)
      |> assign(:expanded, MapSet.new())
      |> load_hierarchy()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("expand_all", _params, socket) do
    # Get all category IDs that have children
    all_parent_ids =
      socket.assigns.category_tree
      |> Enum.flat_map(&get_all_parent_ids/1)
      |> MapSet.new()

    {:noreply, assign(socket, :expanded, all_parent_ids)}
  end

  def handle_event("collapse_all", _params, socket) do
    {:noreply, assign(socket, :expanded, MapSet.new())}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    category = Categories.get_category!(id)

    case Categories.delete_category(category) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Category deleted successfully.")
          |> load_hierarchy()

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not delete category.")}
    end
  end

  defp load_hierarchy(socket) do
    category_tree = CategoryAnalytics.categories_with_hierarchy()

    socket
    |> assign(:category_tree, category_tree)
    |> assign(:loading, false)
  end

  defp get_all_parent_ids(category) do
    if Enum.empty?(category.children) do
      []
    else
      [category.id | Enum.flat_map(category.children, &get_all_parent_ids/1)]
    end
  end

  # Helper functions for template
  def has_children?(category), do: not Enum.empty?(category.children)

  def is_expanded?(expanded, id), do: MapSet.member?(expanded, id)

  def category_icon(nil), do: "📁"
  def category_icon(""), do: "📁"
  def category_icon(icon), do: icon

  def category_color(nil), do: "#6B7280"
  def category_color(""), do: "#6B7280"
  def category_color(color), do: color

  def format_count(count) when is_integer(count) and count >= 1000 do
    "#{Float.round(count / 1000, 1)}K"
  end

  def format_count(count) when is_integer(count), do: Integer.to_string(count)
  def format_count(_), do: "0"

  # Function component for recursive tree node rendering
  attr :category, :map, required: true
  attr :expanded, :any, required: true
  attr :level, :integer, default: 0

  def tree_node(assigns) do
    ~H"""
    <div class={[
      "tree-node",
      not @category.is_active && "opacity-50"
    ]}>
      <div class={[
        "flex items-center py-2 px-3 rounded-lg hover:bg-gray-50 group",
        @category.direct_event_count == 0 && @category.children_event_count == 0 && "bg-amber-50"
      ]}>
        <!-- Indentation -->
        <div style={"margin-left: #{@level * 24}px"} class="flex items-center flex-1 min-w-0">
          <!-- Expand/Collapse Toggle -->
          <%= if has_children?(@category) do %>
            <button
              phx-click="toggle_expand"
              phx-value-id={@category.id}
              class="p-1 hover:bg-gray-200 rounded mr-1 flex-shrink-0"
            >
              <%= if is_expanded?(@expanded, @category.id) do %>
                <svg class="h-4 w-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
                </svg>
              <% else %>
                <svg class="h-4 w-4 text-gray-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                </svg>
              <% end %>
            </button>
          <% else %>
            <div class="w-6 mr-1 flex-shrink-0"></div>
          <% end %>

          <!-- Category Icon with Color Background -->
          <div
            class="w-8 h-8 rounded-lg flex items-center justify-center text-lg flex-shrink-0 mr-3"
            style={"background-color: #{category_color(@category.color)}20"}
          >
            <%= category_icon(@category.icon) %>
          </div>

          <!-- Category Name -->
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-medium text-gray-900 truncate">
                <%= @category.name %>
              </span>
              <%= if not @category.is_active do %>
                <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600">
                  Inactive
                </span>
              <% end %>
              <%= if @category.slug == "other" do %>
                <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-amber-100 text-amber-700">
                  Fallback
                </span>
              <% end %>
            </div>

            <!-- Event Counts -->
            <div class="text-sm text-gray-500 mt-0.5">
              <%= if has_children?(@category) do %>
                <span class="font-medium"><%= format_count(@category.total_event_count) %></span> total
                <span class="mx-1">·</span>
                Direct: <%= format_count(@category.direct_event_count) %>
                <span class="mx-1">·</span>
                Children: <%= format_count(@category.children_event_count) %>
              <% else %>
                <span class="font-medium"><%= format_count(@category.direct_event_count) %></span> events
              <% end %>
            </div>
          </div>
        </div>

        <!-- Actions -->
        <div class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
          <.link
            navigate={~p"/admin/categories/#{@category.id}/edit"}
            class="p-1.5 text-gray-400 hover:text-blue-600 hover:bg-blue-50 rounded"
            title="Edit"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
            </svg>
          </.link>
          <.link
            navigate={~p"/admin/categories/new?parent_id=#{@category.id}"}
            class="p-1.5 text-gray-400 hover:text-green-600 hover:bg-green-50 rounded"
            title="Add Subcategory"
          >
            <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
          </.link>
          <%= if @category.direct_event_count == 0 and Enum.empty?(@category.children) do %>
            <button
              phx-click="delete"
              phx-value-id={@category.id}
              data-confirm="Are you sure you want to delete this category?"
              class="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded"
              title="Delete"
            >
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
              </svg>
            </button>
          <% end %>
        </div>
      </div>

      <!-- Children (recursive) -->
      <%= if has_children?(@category) and is_expanded?(@expanded, @category.id) do %>
        <div class="ml-2 border-l-2 border-gray-200">
          <%= for child <- @category.children do %>
            <.tree_node category={child} expanded={@expanded} level={@level + 1} />
          <% end %>

          <!-- Add Subcategory Link -->
          <div style={"margin-left: #{(@level + 1) * 24 + 6}px"} class="py-2">
            <.link
              navigate={~p"/admin/categories/new?parent_id=#{@category.id}"}
              class="inline-flex items-center text-sm text-gray-400 hover:text-indigo-600"
            >
              <svg class="h-3 w-3 mr-1" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
              </svg>
              Add Subcategory
            </.link>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
