defmodule EventasaurusWeb.Components.Breadcrumbs do
  @moduledoc """
  Shared breadcrumb navigation component for consistent hierarchy display across all show pages.

  Provides structured, accessible breadcrumb navigation with:
  - Semantic HTML using <nav> and <ol>
  - Proper ARIA labels for accessibility
  - Consistent styling across all pages
  - SEO-friendly markup
  - Mobile-responsive collapsed view with expandable dropdown
  """

  use Phoenix.Component

  @doc """
  Renders a breadcrumb navigation list.

  On mobile (< 640px), breadcrumbs with more than 3 items are collapsed to show:
  "Home / ... / Current Page" with a clickable ellipsis that expands to show hidden items.

  ## Attributes
    * `items` - List of breadcrumb items with `:label` and optional `:path` keys
    * `class` - Additional CSS classes (optional)
    * `text_color` - Text color classes (optional, defaults to gray for light backgrounds)

  ## Item Structure
  Each item should be a map with:
    * `:label` - The text to display (required)
    * `:path` - The link path (optional - if nil, renders as plain text for current page)

  ## Examples

      # Default (gray text for light backgrounds)
      <Breadcrumbs.breadcrumb items={[
        %{label: "Home", path: ~p"/"},
        %{label: "Kraków", path: ~p"/c/krakow"},
        %{label: "Festivals", path: ~p"/c/krakow/festivals"},
        %{label: "Unsound Kraków 2025", path: nil}
      ]} />

      # White text for dark backgrounds
      <Breadcrumbs.breadcrumb
        items={breadcrumb_items}
        text_color="text-white/80 hover:text-white"
      />
  """
  attr :items, :list, required: true, doc: "List of breadcrumb items with :label and :path keys"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  attr :text_color, :string,
    default: "text-gray-500 hover:text-gray-700",
    doc: "Text color classes for links and current page"

  def breadcrumb(assigns) do
    # Split items for mobile collapsed view
    # Only use collapsed view when there are > 3 items (so middle_items has content)
    items = assigns.items
    item_count = length(items)

    assigns =
      assigns
      |> assign(:item_count, item_count)
      |> assign(:first_item, List.first(items))
      |> assign(:last_item, List.last(items))
      |> assign(:middle_items, if(item_count > 3, do: Enum.slice(items, 1..-2//1), else: []))

    ~H"""
    <nav class={["mb-4 text-sm", @class]} aria-label="Breadcrumb">
      <%= if @item_count == 0 do %>
        <%!-- Empty breadcrumbs: render nothing --%>
      <% else %>
        <%!-- Desktop: Show all items --%>
        <ol class={["hidden sm:flex items-center space-x-2 flex-wrap", @text_color]}>
          <%= for {item, index} <- Enum.with_index(@items) do %>
            <%= if index > 0 do %>
              <li aria-hidden="true" class="select-none">/</li>
            <% end %>
            <li>
              <%= if item.path do %>
                <.link navigate={item.path} class="transition-colors">
                  <%= item.label %>
                </.link>
              <% else %>
                <span class="font-medium"><%= item.label %></span>
              <% end %>
            </li>
          <% end %>
        </ol>

        <%!-- Mobile: Collapsed view with expandable dropdown --%>
        <div class="sm:hidden">
          <%= if @item_count <= 3 do %>
            <%!-- Short breadcrumbs (1-3 items): show all items --%>
            <ol class={["flex items-center space-x-2 flex-wrap", @text_color]}>
              <%= for {item, index} <- Enum.with_index(@items) do %>
                <%= if index > 0 do %>
                  <li aria-hidden="true" class="select-none">/</li>
                <% end %>
                <li>
                  <%= if item.path do %>
                    <.link navigate={item.path} class="transition-colors">
                      <%= item.label %>
                    </.link>
                  <% else %>
                    <span class="font-medium"><%= item.label %></span>
                  <% end %>
                </li>
              <% end %>
            </ol>
          <% else %>
            <%!-- Long breadcrumbs (4+ items): collapsed with dropdown --%>
            <ol class={["flex items-center space-x-2", @text_color]}>
              <%!-- First item (Home) --%>
              <li>
                <%= if @first_item.path do %>
                  <.link navigate={@first_item.path} class="transition-colors">
                    <%= @first_item.label %>
                  </.link>
                <% else %>
                  <span class="font-medium"><%= @first_item.label %></span>
                <% end %>
              </li>

              <li aria-hidden="true" class="select-none">/</li>

              <%!-- Ellipsis dropdown for middle items --%>
              <li class="relative" x-data="{ open: false }" @keydown.escape.window="open = false">
                <button
                  type="button"
                  @click="open = !open"
                  @click.away="open = false"
                  class="px-2 py-1 rounded hover:bg-gray-100 transition-colors font-medium"
                  x-bind:aria-expanded="open"
                  aria-haspopup="true"
                  aria-label="Show hidden breadcrumb items"
                >
                  ...
                </button>

                <%!-- Dropdown menu --%>
                <div
                  x-show="open"
                  x-transition:enter="transition ease-out duration-100"
                  x-transition:enter-start="opacity-0 scale-95"
                  x-transition:enter-end="opacity-100 scale-100"
                  x-transition:leave="transition ease-in duration-75"
                  x-transition:leave-start="opacity-100 scale-100"
                  x-transition:leave-end="opacity-0 scale-95"
                  class="absolute left-0 mt-1 w-48 bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50"
                  style="display: none;"
                  role="menu"
                >
                  <%= for item <- @middle_items do %>
                    <%= if item.path do %>
                      <.link
                        navigate={item.path}
                        class="block px-4 py-2 text-gray-700 hover:bg-gray-100 transition-colors"
                        role="menuitem"
                      >
                        <%= item.label %>
                      </.link>
                    <% else %>
                      <span class="block px-4 py-2 text-gray-700 font-medium" role="menuitem">
                        <%= item.label %>
                      </span>
                    <% end %>
                  <% end %>
                </div>
              </li>

              <li aria-hidden="true" class="select-none">/</li>

              <%!-- Last item (current page) - truncated if too long --%>
              <li class="max-w-[150px] truncate">
                <%= if @last_item.path do %>
                  <.link navigate={@last_item.path} class="transition-colors">
                    <%= @last_item.label %>
                  </.link>
                <% else %>
                  <span class="font-medium"><%= @last_item.label %></span>
                <% end %>
              </li>
            </ol>
          <% end %>
        </div>
      <% end %>
    </nav>
    """
  end
end
