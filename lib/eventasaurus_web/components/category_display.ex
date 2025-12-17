defmodule EventasaurusWeb.Components.CategoryDisplay do
  @moduledoc """
  Components for displaying event categories.

  Provides multiple display formats:
  - `category_badges/1` - Simple badges for listings
  - `category_badge/1` - Single badge display
  - `category_list/1` - Comma-separated text list
  - `category_filter/1` - Interactive filter selector
  - `event_category_section/1` - Full section for event detail pages with links and hints
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: EventasaurusWeb.Endpoint, router: EventasaurusWeb.Router
  alias EventasaurusDiscovery.Categories.Category

  @doc """
  Displays category badges for an event.

  ## Examples

      <.category_badges event={@event} locale="en" />
      <.category_badges event={@event} locale="pl" show_all={false} />
  """
  attr :event, :map, required: true
  attr :locale, :string, default: "en"
  attr :show_all, :boolean, default: true
  attr :class, :string, default: ""

  def category_badges(assigns) do
    ~H"""
    <div class={"flex flex-wrap gap-2 #{@class}"}>
      <%= if @show_all && is_list(@event.categories) do %>
        <%= for {category, index} <- Enum.with_index(@event.categories) do %>
          <.category_badge category={category} is_primary={index == 0} locale={@locale} />
        <% end %>
      <% else %>
        <%= if primary = get_primary_category(@event) do %>
          <.category_badge category={primary} is_primary={true} locale={@locale} />
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  Displays a single category badge.
  """
  attr :category, :map, required: true
  attr :is_primary, :boolean, default: false
  attr :locale, :string, default: "en"

  def category_badge(assigns) do
    assigns = assign(assigns, :name, Category.get_name(assigns.category, assigns.locale))
    assigns = assign(assigns, :color, assigns.category.color || "#6B7280")

    ~H"""
    <span
      class={[
        "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
        @is_primary && "ring-2 ring-offset-1 ring-opacity-50"
      ]}
      style={"background-color: #{@color}20; color: #{@color}; #{if @is_primary, do: "ring-color: #{@color};"}"}
    >
      <%= if @category.icon do %>
        <span class="mr-1">
          <.icon name={@category.icon} class="h-3 w-3" />
        </span>
      <% end %>
      <%= @name %>
      <%= if @is_primary do %>
        <span class="ml-1 text-[10px] opacity-70">(primary)</span>
      <% end %>
    </span>
    """
  end

  @doc """
  Displays categories as a simple comma-separated list.
  """
  attr :event, :map, required: true
  attr :locale, :string, default: "en"
  attr :class, :string, default: ""

  def category_list(assigns) do
    ~H"""
    <span class={@class}>
      <%= if is_list(@event.categories) && length(@event.categories) > 0 do %>
        <%= @event.categories
            |> Enum.map(fn cat -> Category.get_name(cat, @locale) end)
            |> Enum.join(", ") %>
      <% else %>
        <span class="text-gray-400">No category</span>
      <% end %>
    </span>
    """
  end

  @doc """
  Category filter selector for event listings.
  """
  attr :categories, :list, default: []
  attr :selected, :list, default: []
  attr :locale, :string, default: "en"
  attr :on_change, :any, required: true

  def category_filter(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <%= for category <- @categories do %>
        <button
          type="button"
          phx-click={@on_change}
          phx-value-category={category.slug}
          class={[
            "px-3 py-1 rounded-full text-sm font-medium transition-colors",
            if(category.slug in @selected,
              do: "bg-blue-500 text-white",
              else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
            )
          ]}
        >
          <%= Category.get_name(category, @locale) %>
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Displays a full category section for event detail pages.

  Shows primary category as a prominent badge with icon and link,
  secondary categories as smaller badges, and a helpful hint text.

  ## Examples

      <CategoryDisplay.event_category_section
        event={@event}
        primary_category={@primary_category}
        secondary_categories={@secondary_categories}
      />

  ## Attributes

    * `:event` - Required. The event map (used for fallback if categories not provided separately).
    * `:primary_category` - Optional. The primary category map. If not provided, uses first category.
    * `:secondary_categories` - Optional. List of secondary category maps. If not provided, uses remaining.
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :event, :map, required: true
  attr :primary_category, :map, default: nil
  attr :secondary_categories, :list, default: []
  attr :class, :string, default: ""

  def event_category_section(assigns) do
    # Use provided categories or extract from event
    # Note: Can't use assign_new/3 here because attrs with defaults (nil, [])
    # are always present in assigns, so we check for actual "unset" values
    primary =
      if assigns.primary_category,
        do: assigns.primary_category,
        else: get_primary_category_from_event(assigns.event)

    secondary =
      if assigns.secondary_categories != [],
        do: assigns.secondary_categories,
        else: get_secondary_categories_from_event(assigns.event)

    assigns =
      assigns
      |> assign(:primary_category, primary)
      |> assign(:secondary_categories, secondary)

    ~H"""
    <%= if has_categories?(@event) do %>
      <div class={["mb-4", @class]}>
        <div class="flex flex-wrap gap-2 items-center">
          <!-- Primary category - larger and emphasized -->
          <%= if @primary_category do %>
            <.link
              navigate={~p"/activities?#{[category: @primary_category.slug]}"}
              class="inline-flex items-center px-4 py-2 rounded-full text-sm font-semibold text-white hover:opacity-90 transition"
              style={safe_background_style(@primary_category.color)}
            >
              <%= if @primary_category.icon do %>
                <span class="mr-1"><%= @primary_category.icon %></span>
              <% end %>
              <%= @primary_category.name %>
            </.link>
          <% end %>

          <!-- Secondary categories - smaller and less emphasized -->
          <%= if @secondary_categories != [] do %>
            <span class="text-gray-400 mx-1">•</span>
            <%= for category <- @secondary_categories do %>
              <.link
                navigate={~p"/activities?#{[category: category.slug]}"}
                class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 transition"
              >
                <%= category.name %>
              </.link>
            <% end %>
          <% end %>
        </div>

        <!-- Category hint text -->
        <p class="mt-2 text-xs text-gray-500">
          <%= if @secondary_categories != [] do %>
            <%= gettext("Also filed under: %{categories}",
                categories: Enum.map_join(@secondary_categories, ", ", & &1.name)) %>
          <% else %>
            <%= gettext("Click category to see related events") %>
          <% end %>
        </p>
      </div>
    <% end %>
    """
  end

  # Private helpers

  defp has_categories?(event) do
    is_list(event.categories) && event.categories != []
  end

  defp get_primary_category_from_event(event) do
    case event.primary_category_id do
      nil ->
        # Fallback to first category
        case event.categories do
          [first | _] -> first
          _ -> nil
        end

      cat_id ->
        Enum.find(event.categories, &(&1.id == cat_id))
    end
  end

  defp get_secondary_categories_from_event(event) do
    case event.primary_category_id do
      nil ->
        # If no primary explicitly set, treat all but first as secondary
        case event.categories do
          [_first | rest] -> rest
          _ -> []
        end

      cat_id ->
        # Filter out the primary category
        Enum.reject(event.categories || [], &(&1.id == cat_id))
    end
  end

  defp safe_background_style(color) do
    color = if valid_hex_color?(color), do: color, else: "#6B7280"
    "background-color: #{color}"
  end

  defp valid_hex_color?(color) when is_binary(color) do
    case color do
      <<?#, _::binary>> = hex when byte_size(hex) in [4, 7] ->
        String.match?(hex, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/)

      _ ->
        false
    end
  end

  defp valid_hex_color?(_), do: false

  # Legacy helper for backward compatibility
  defp get_primary_category(event) do
    case event.categories do
      [first | _] -> first
      _ -> nil
    end
  end

  # Icon component helper (simplified)
  defp icon(assigns) do
    ~H"""
    <svg class={@class} fill="currentColor" viewBox="0 0 20 20">
      <%= case @name do %>
        <% "music" -> %>
          <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v9.114A4.369 4.369 0 005 14c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V7.82l8-1.6v5.894A4.37 4.37 0 0015 12c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z" />
        <% "theater" -> %>
          <path d="M10 18a8 8 0 100-16 8 8 0 000 16zM4.332 8.027a6.012 6.012 0 011.912-2.706C6.512 5.73 6.974 6 7.5 6A1.5 1.5 0 019 7.5V8a2 2 0 004 0 2 2 0 011.523-1.943A5.977 5.977 0 0116 10c0 .34-.028.675-.083 1H15a2 2 0 00-2 2v2.197A5.973 5.973 0 0110 16v-2a2 2 0 00-2-2 2 2 0 01-2-2 2 2 0 00-1.668-1.973z" />
        <% "book" -> %>
          <path d="M9 4.804A7.968 7.968 0 005.5 4c-1.255 0-2.443.29-3.5.804v10A7.969 7.969 0 015.5 14c1.669 0 3.218.51 4.5 1.385A7.962 7.962 0 0114.5 14c1.255 0 2.443.29 3.5.804v-10A7.968 7.968 0 0014.5 4c-1.255 0-2.443.29-3.5.804V12a1 1 0 11-2 0V4.804z" />
        <% "film" -> %>
          <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm3 2h6v4H7V5zm8 8v2h1v-2h-1zm-2-2H7v4h6v-4zm2 0h1V9h-1v2zm1-4V5h-1v2h1zM5 5v2H4V5h1zm0 4H4v2h1V9zm-1 4h1v2H4v-2z" clip-rule="evenodd" />
        <% "art" -> %>
          <path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clip-rule="evenodd" />
        <% _ -> %>
          <path fill-rule="evenodd" d="M17.707 9.293a1 1 0 010 1.414l-7 7a1 1 0 01-1.414 0l-7-7A.997.997 0 012 10V5a3 3 0 013-3h5c.256 0 .512.098.707.293l7 7zM5 6a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
      <% end %>
    </svg>
    """
  end
end
