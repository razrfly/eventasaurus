defmodule EventasaurusWeb.Components.Breadcrumbs do
  @moduledoc """
  Shared breadcrumb navigation component for consistent hierarchy display across all show pages.

  Provides structured, accessible breadcrumb navigation with:
  - Semantic HTML using <nav> and <ol>
  - Proper ARIA labels for accessibility
  - Consistent styling across all pages
  - SEO-friendly markup
  """

  use Phoenix.Component

  @doc """
  Renders a breadcrumb navigation list.

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
    ~H"""
    <nav class={["mb-4 text-sm", @class]} aria-label="Breadcrumb">
      <ol class={["flex items-center space-x-2", @text_color]}>
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
    </nav>
    """
  end
end
