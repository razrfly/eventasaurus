defmodule EventasaurusWeb.Components.CategoryCards do
  use Phoenix.Component
  use EventasaurusWeb, :verified_routes

  attr :category, :map, required: true
  attr :event_count, :integer, required: true

  def category_card(assigns) do
    ~H"""
    <.link navigate={~p"/activities"} class="block group">
      <div
        class="relative h-48 rounded-lg overflow-hidden shadow-lg hover:shadow-xl transition-shadow"
        style={background_style(@category)}
      >
        <!-- Icon/Image -->
        <div class="absolute inset-0 flex items-center justify-center">
          <%= if @category.icon do %>
            <div class="text-6xl opacity-20">
              <%= @category.icon %>
            </div>
          <% else %>
            <div class="text-6xl opacity-20">
              <%= category_emoji(@category.slug) %>
            </div>
          <% end %>
        </div>
        <!-- Overlay -->
        <div class="absolute inset-0 bg-gradient-to-t from-black/50 to-transparent"></div>
        <!-- Content -->
        <div class="absolute bottom-0 left-0 right-0 p-6 text-white">
          <h3 class="text-xl font-bold mb-2">
            <%= @category.name %>
          </h3>
          <div class="flex items-center text-sm">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= @event_count %> events
          </div>
        </div>
        <!-- Hover Arrow -->
        <div class="absolute top-4 right-4 opacity-0 group-hover:opacity-100 transition-opacity">
          <Heroicons.arrow_right class="w-6 h-6 text-white" />
        </div>
      </div>
    </.link>
    """
  end

  defp background_style(category) do
    color = category.color || "#6366f1"
    # Simple gradient generation
    "background: linear-gradient(135deg, #{color} 0%, #{color} 100%);"
  end

  defp category_emoji("trivia"), do: "🎯"
  defp category_emoji("film"), do: "🎬"
  defp category_emoji("concerts"), do: "🎵"
  defp category_emoji("education"), do: "📚"
  defp category_emoji("nightlife"), do: "🌃"
  defp category_emoji("family"), do: "👨‍👩‍👧‍👦"
  defp category_emoji("arts"), do: "🎨"
  defp category_emoji("theatre"), do: "🎭"
  defp category_emoji("sports"), do: "⚽"
  defp category_emoji("festivals"), do: "🎪"
  defp category_emoji("food-drink"), do: "🍽️"
  defp category_emoji("comedy"), do: "😂"
  defp category_emoji(_), do: "📅"
end
