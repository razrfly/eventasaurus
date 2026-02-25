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

  alias EventasaurusWeb.Components.Activity.{
    HeroCardBackground,
    HeroCardHelpers,
    HeroCardIcons,
    HeroCardTheme
  }

  @doc """
  Renders the generic hero card for non-movie events.

  ## Attributes

    * `:event` - Required. The public event struct with title, categories, venue, etc.
    * `:cover_image_url` - Optional. Cover image URL for the event.
    * `:ticket_url` - Optional. URL to purchase tickets.
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :event, :map,
    required: true,
    doc: "PublicEvent struct with display_title, categories, etc."

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
      <!-- Background -->
      <HeroCardBackground.background image_url={@cover_image_url} theme={@category_color} />

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="max-w-3xl">
          <!-- Category Badge -->
          <%= if @primary_category do %>
            <div class="mb-4">
              <span class={[
                "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium",
                HeroCardTheme.badge_class(@category_color)
              ]}>
                <HeroCardIcons.icon type={@schema_type} class="w-4 h-4 mr-1.5" />
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
                <%= HeroCardHelpers.format_datetime(@event.starts_at, @event.venue, "%A, %B %d, %Y · %H:%M") %>
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
end
