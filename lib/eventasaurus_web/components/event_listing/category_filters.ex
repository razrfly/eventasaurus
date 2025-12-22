defmodule EventasaurusWeb.Components.EventListing.CategoryFilters do
  @moduledoc """
  Category filter components for event listings.

  Provides checkbox-based category selection for filtering events.
  Supports both grid layout (for filter panels) and compact tag layout.

  ## Events Emitted

  - `toggle_category` with `category_id` value - when a category is toggled
  - `remove_category` with `id` value - when removing from active tags

  ## Example

      <.category_checkboxes
        categories={@categories}
        selected_ids={@filters.categories}
      />

  Or for display of selected categories as removable tags:

      <.category_tags
        categories={@categories}
        selected_ids={@filters.categories}
      />
  """

  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  @doc """
  Renders category checkboxes in a grid layout.

  Best used in filter panels or expanded filter sections.

  ## Attributes

  - `categories` - List of category structs with `id` and `name` fields
  - `selected_ids` - List of currently selected category IDs
  - `name` - Input name attribute for form submission (default: "filter[categories][]")
  - `form_mode` - If true, works within a form. If false, emits events directly. (default: false)
  - `columns` - Number of columns in grid (default: 2 on mobile, 3 on md, 4 on lg)
  - `label` - Section label (default: "Categories")
  - `show_label` - Whether to show the label (default: true)
  - `class` - Additional CSS classes
  """
  attr :categories, :list, required: true
  attr :selected_ids, :list, default: []
  attr :name, :string, default: "filter[categories][]"
  attr :form_mode, :boolean, default: false
  attr :columns, :string, default: "grid-cols-2 md:grid-cols-3 lg:grid-cols-4"
  attr :label, :string, default: nil
  attr :show_label, :boolean, default: true
  attr :class, :string, default: nil

  def category_checkboxes(assigns) do
    assigns = assign_new(assigns, :display_label, fn ->
      assigns.label || gettext("Categories")
    end)

    # Ensure selected_ids is a list
    assigns = assign(assigns, :selected_ids, assigns.selected_ids || [])

    ~H"""
    <div class={["category-filters", @class]}>
      <%= if @show_label do %>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          <%= @display_label %>
        </label>
      <% end %>

      <div class={["grid gap-2", @columns]}>
        <%= for category <- @categories do %>
          <label class="flex items-center space-x-2 cursor-pointer">
            <%= if @form_mode do %>
              <input
                type="checkbox"
                name={@name}
                value={category.id}
                checked={category.id in @selected_ids}
                class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
            <% else %>
              <input
                type="checkbox"
                phx-click="toggle_category"
                phx-value-category_id={category.id}
                checked={category.id in @selected_ids}
                class="rounded border-gray-300 text-blue-600 focus:ring-blue-500 cursor-pointer"
              />
            <% end %>
            <span class="text-sm text-gray-700"><%= category.name %></span>
          </label>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders selected categories as removable tags/badges.

  Best used to show active filters that can be individually removed.

  ## Attributes

  - `categories` - List of all category structs (used to look up names)
  - `selected_ids` - List of currently selected category IDs
  - `class` - Additional CSS classes
  """
  attr :categories, :list, required: true
  attr :selected_ids, :list, default: []
  attr :class, :string, default: nil

  def category_tags(assigns) do
    assigns = assign(assigns, :selected_ids, assigns.selected_ids || [])

    ~H"""
    <div class={["flex flex-wrap gap-2", @class]}>
      <%= for category_id <- @selected_ids do %>
        <% category = Enum.find(@categories, & &1.id == category_id) %>
        <%= if category do %>
          <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
            <%= category.name %>
            <button
              type="button"
              phx-click="remove_category"
              phx-value-id={category_id}
              class="ml-2 hover:text-blue-600"
              title={gettext("Remove %{category}", category: category.name)}
            >
              <Heroicons.x_mark class="w-4 h-4" />
            </button>
          </span>
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a compact dropdown for category selection.

  Best used in horizontal filter bars where space is limited.

  ## Attributes

  - `categories` - List of category structs with `id` and `name` fields
  - `selected_ids` - List of currently selected category IDs
  - `name` - Input name for form mode
  - `form_mode` - If true, works within a form
  - `placeholder` - Placeholder text (default: "All Categories")
  - `class` - Additional CSS classes
  """
  attr :categories, :list, required: true
  attr :selected_ids, :list, default: []
  attr :name, :string, default: "category"
  attr :form_mode, :boolean, default: false
  attr :placeholder, :string, default: nil
  attr :class, :string, default: nil

  def category_dropdown(assigns) do
    assigns = assign(assigns, :selected_ids, assigns.selected_ids || [])

    assigns = assign_new(assigns, :display_placeholder, fn ->
      assigns.placeholder || gettext("All Categories")
    end)

    ~H"""
    <div class={["inline-flex items-center gap-2", @class]}>
      <span class="text-sm text-gray-600"><%= gettext("Category:") %></span>
      <div class="relative inline-block">
        <%= if @form_mode do %>
          <select
            name={@name}
            class="appearance-none bg-white border border-gray-300 rounded-lg px-3 py-1.5 pr-8 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value=""><%= @display_placeholder %></option>
            <%= for category <- @categories do %>
              <option value={category.id} selected={category.id in @selected_ids}>
                <%= category.name %>
              </option>
            <% end %>
          </select>
        <% else %>
          <select
            phx-change="select_category"
            name={@name}
            class="appearance-none bg-white border border-gray-300 rounded-lg px-3 py-1.5 pr-8 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 cursor-pointer"
          >
            <option value=""><%= @display_placeholder %></option>
            <%= for category <- @categories do %>
              <option value={category.id} selected={category.id in @selected_ids}>
                <%= category.name %>
              </option>
            <% end %>
          </select>
        <% end %>
        <div class="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-gray-500">
          <Heroicons.chevron_down class="w-4 h-4" />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders category filter as horizontal scrollable pills/buttons.

  Good for quick single-category selection on mobile.

  ## Attributes

  - `categories` - List of category structs
  - `selected_id` - Single selected category ID (or nil for all)
  - `show_all_option` - Whether to show "All" option (default: true)
  - `class` - Additional CSS classes
  """
  attr :categories, :list, required: true
  attr :selected_id, :integer, default: nil
  attr :show_all_option, :boolean, default: true
  attr :class, :string, default: nil

  def category_pills(assigns) do
    ~H"""
    <div class={["flex gap-2 overflow-x-auto pb-2", @class]}>
      <%= if @show_all_option do %>
        <button
          type="button"
          phx-click="select_category"
          phx-value-category_id=""
          class={[
            "px-4 py-2 rounded-full text-sm font-medium whitespace-nowrap transition-all",
            if(@selected_id == nil,
              do: "bg-blue-600 text-white shadow-md",
              else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
            )
          ]}
        >
          <%= gettext("All") %>
        </button>
      <% end %>

      <%= for category <- @categories do %>
        <button
          type="button"
          phx-click="select_category"
          phx-value-category_id={category.id}
          class={[
            "px-4 py-2 rounded-full text-sm font-medium whitespace-nowrap transition-all",
            if(@selected_id == category.id,
              do: "bg-blue-600 text-white shadow-md",
              else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
            )
          ]}
        >
          <%= category.name %>
        </button>
      <% end %>
    </div>
    """
  end
end
