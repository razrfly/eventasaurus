defmodule EventasaurusWeb.Components.Activity.GenericHeroCard do
  @moduledoc """
  Generic hero card for non-movie events on activity pages.

  Displays event information in a hero-style layout with cover image,
  title, date/time, category badge, and description excerpt.
  Works as the fallback for all event types that don't have
  a specialized hero card (concerts, trivia, theatre, etc.).

  ## Features

  - Cover image with gradient overlay (or category-colored fallback)
  - Event title prominently displayed
  - Date and time information
  - Category badge with schema.org type
  - Description excerpt
  - Ticket link (if available)
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN
  alias EventasaurusWeb.Components.Activity.HeroCardHelpers

  @doc """
  Renders the generic hero card for non-movie events.

  ## Attributes

    * `:event` - Required. The public event struct with title, categories, venue, etc.
    * `:cover_image_url` - Optional. Cover image URL for the event.
    * `:ticket_url` - Optional. URL to purchase tickets.
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :event, :map, required: true, doc: "PublicEvent struct with display_title, categories, etc."
  attr :cover_image_url, :string, default: nil, doc: "Cover image URL for the hero background"
  attr :ticket_url, :string, default: nil, doc: "URL to ticket purchase page"
  attr :class, :string, default: "", doc: "Additional CSS classes for the container"

  def generic_hero_card(assigns) do
    # Get primary category for styling and badge
    primary_category = get_primary_category(assigns.event)
    category_color = get_category_color(primary_category)
    schema_type = get_schema_type(primary_category)

    assigns =
      assigns
      |> assign(:primary_category, primary_category)
      |> assign(:category_color, category_color)
      |> assign(:schema_type, schema_type)

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background Image or Gradient -->
      <%= if @cover_image_url do %>
        <div class="absolute inset-0">
          <img
            src={CDN.url(@cover_image_url, width: 1200, quality: 85)}
            alt=""
            class="w-full h-full object-cover"
            aria-hidden="true"
          />
          <div class="absolute inset-0 bg-gradient-to-r from-gray-900 via-gray-900/80 to-gray-900/40" />
        </div>
      <% else %>
        <!-- Category-colored gradient fallback -->
        <div class={["absolute inset-0", gradient_class(@category_color)]} />
      <% end %>

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="max-w-3xl">
          <!-- Category Badge -->
          <%= if @primary_category do %>
            <div class="mb-4">
              <span class={[
                "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
                badge_class(@category_color)
              ]}>
                <.category_icon category={@primary_category} class="w-4 h-4 mr-1.5" />
                <%= @primary_category.name %>
              </span>
            </div>
          <% end %>

          <!-- Title -->
          <h1 class="text-2xl md:text-4xl font-bold text-white tracking-tight mb-4">
            <%= @event.display_title || @event.title %>
          </h1>

          <!-- Date & Time -->
          <%= if @event.starts_at do %>
            <div class="flex items-center text-white/90 mb-4">
              <Heroicons.calendar class="w-5 h-5 mr-2" />
              <span class="text-lg">
                <%= HeroCardHelpers.format_datetime(@event.starts_at, "%A, %B %d, %Y · %I:%M %p") %>
              </span>
            </div>
          <% end %>

          <!-- Venue (if available) -->
          <%= if @event.venue do %>
            <div class="flex items-center text-white/80 mb-4">
              <Heroicons.map_pin class="w-5 h-5 mr-2" />
              <span>
                <%= @event.venue.name %>
                <%= if city_name = HeroCardHelpers.get_city_name(@event.venue) do %>
                  <span class="text-white/60">· <%= city_name %></span>
                <% end %>
              </span>
            </div>
          <% end %>

          <!-- Description Excerpt -->
          <%= if @event.display_description do %>
            <p class="text-white/90 leading-relaxed line-clamp-2 max-w-2xl mb-6">
              <%= HeroCardHelpers.truncate_text(@event.display_description, 200) %>
            </p>
          <% end %>

          <!-- Action Buttons -->
          <div class="flex flex-wrap gap-3">
            <%= if @ticket_url do %>
              <a
                href={@ticket_url}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-5 py-2.5 bg-white text-gray-900 text-sm font-semibold rounded-lg hover:bg-gray-100 transition shadow-md"
              >
                <Heroicons.ticket class="w-5 h-5 mr-2" />
                <%= gettext("Get Tickets") %>
              </a>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Category icon component based on schema type
  attr :category, :map, required: true
  attr :class, :string, default: ""

  defp category_icon(assigns) do
    assigns = assign(assigns, :schema_type, assigns.category && assigns.category.schema_type)

    ~H"""
    <%= case @schema_type do %>
      <% "MusicEvent" -> %>
        <Heroicons.musical_note class={@class} />
      <% "SocialEvent" -> %>
        <Heroicons.user_group class={@class} />
      <% "TheaterEvent" -> %>
        <Heroicons.ticket class={@class} />
      <% "ComedyEvent" -> %>
        <Heroicons.face_smile class={@class} />
      <% "SportsEvent" -> %>
        <Heroicons.trophy class={@class} />
      <% "FoodEvent" -> %>
        <Heroicons.cake class={@class} />
      <% "EducationEvent" -> %>
        <Heroicons.academic_cap class={@class} />
      <% "ChildrensEvent" -> %>
        <Heroicons.puzzle_piece class={@class} />
      <% "Festival" -> %>
        <Heroicons.sparkles class={@class} />
      <% "VisualArtsEvent" -> %>
        <Heroicons.paint_brush class={@class} />
      <% "BusinessEvent" -> %>
        <Heroicons.briefcase class={@class} />
      <% _ -> %>
        <Heroicons.calendar class={@class} />
    <% end %>
    """
  end

  # Helper functions

  defp get_primary_category(%{categories: categories}) when is_list(categories) do
    # Try to find the primary category first
    Enum.find(categories, List.first(categories), fn cat ->
      Map.get(cat, :is_primary, false)
    end)
  end

  defp get_primary_category(_), do: nil

  defp get_category_color(nil), do: :default

  defp get_category_color(%{schema_type: schema_type}) do
    case schema_type do
      "MusicEvent" -> :purple
      "SocialEvent" -> :blue
      "TheaterEvent" -> :red
      "ComedyEvent" -> :yellow
      "SportsEvent" -> :green
      "FoodEvent" -> :orange
      "EducationEvent" -> :teal
      "ChildrensEvent" -> :pink
      "Festival" -> :indigo
      "VisualArtsEvent" -> :rose
      "BusinessEvent" -> :slate
      _ -> :default
    end
  end

  defp get_category_color(_), do: :default

  defp get_schema_type(%{schema_type: schema_type}), do: schema_type
  defp get_schema_type(_), do: "Event"

  defp gradient_class(:purple), do: "bg-gradient-to-r from-purple-900 via-purple-800 to-purple-700"
  defp gradient_class(:blue), do: "bg-gradient-to-r from-blue-900 via-blue-800 to-blue-700"
  defp gradient_class(:red), do: "bg-gradient-to-r from-red-900 via-red-800 to-red-700"
  defp gradient_class(:yellow), do: "bg-gradient-to-r from-amber-900 via-amber-800 to-amber-700"
  defp gradient_class(:green), do: "bg-gradient-to-r from-emerald-900 via-emerald-800 to-emerald-700"
  defp gradient_class(:orange), do: "bg-gradient-to-r from-orange-900 via-orange-800 to-orange-700"
  defp gradient_class(:teal), do: "bg-gradient-to-r from-teal-900 via-teal-800 to-teal-700"
  defp gradient_class(:pink), do: "bg-gradient-to-r from-pink-900 via-pink-800 to-pink-700"
  defp gradient_class(:indigo), do: "bg-gradient-to-r from-indigo-900 via-indigo-800 to-indigo-700"
  defp gradient_class(:rose), do: "bg-gradient-to-r from-rose-900 via-rose-800 to-rose-700"
  defp gradient_class(:slate), do: "bg-gradient-to-r from-slate-900 via-slate-800 to-slate-700"
  defp gradient_class(_), do: "bg-gradient-to-r from-gray-900 via-gray-800 to-gray-700"

  defp badge_class(:purple), do: "bg-purple-500/20 text-purple-100"
  defp badge_class(:blue), do: "bg-blue-500/20 text-blue-100"
  defp badge_class(:red), do: "bg-red-500/20 text-red-100"
  defp badge_class(:yellow), do: "bg-amber-500/20 text-amber-100"
  defp badge_class(:green), do: "bg-emerald-500/20 text-emerald-100"
  defp badge_class(:orange), do: "bg-orange-500/20 text-orange-100"
  defp badge_class(:teal), do: "bg-teal-500/20 text-teal-100"
  defp badge_class(:pink), do: "bg-pink-500/20 text-pink-100"
  defp badge_class(:indigo), do: "bg-indigo-500/20 text-indigo-100"
  defp badge_class(:rose), do: "bg-rose-500/20 text-rose-100"
  defp badge_class(:slate), do: "bg-slate-500/20 text-slate-100"
  defp badge_class(_), do: "bg-white/20 text-white"
end
