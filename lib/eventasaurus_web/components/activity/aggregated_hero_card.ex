defmodule EventasaurusWeb.Components.Activity.AggregatedHeroCard do
  @moduledoc """
  Hero card for aggregated source pages (e.g., /c/krakow/social/pubquiz-pl).

  Displays source/brand information with content-type theming based on
  the source's primary domain or aggregation type. Matches the visual
  style of individual activity hero cards (TriviaHeroCard, ConcertHeroCard, etc.)

  ## Features

  - Rounded card design matching activity pages
  - Content-type based gradient theming (trivia, food, movies, music, etc.)
  - Source branding with optional logo
  - City context with multi-city awareness
  - Event/location counts
  - Scope toggle integration (all cities / city only)
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN
  alias EventasaurusWeb.Components.Activity.HeroCardTheme

  @doc """
  Renders the aggregated hero card for source aggregation pages.

  ## Attributes

    * `:source_name` - Required. Display name of the source (e.g., "PubQuiz Poland").
    * `:source_logo_url` - Optional. Logo URL for the source.
    * `:city` - Required. The current city struct with name and slug.
    * `:content_type` - Required. Schema.org type (e.g., "SocialEvent", "FoodEvent").
    * `:domain` - Optional. Primary domain from source (e.g., "trivia", "food", "movies").
    * `:hero_image` - Optional. Background image URL.
    * `:total_event_count` - Required. Total events across all cities.
    * `:location_count` - Required. Number of locations/venues in current scope.
    * `:unique_cities` - Optional. Number of unique cities with events.
    * `:out_of_city_count` - Optional. Events outside current city.
    * `:scope` - Optional. Current scope (:city_only or :all_cities).
    * `:class` - Optional. Additional CSS classes.
  """
  attr :source_name, :string, required: true, doc: "Display name of the source"
  attr :source_logo_url, :string, default: nil, doc: "Logo URL for the source"
  attr :city, :map, required: true, doc: "Current city struct"
  attr :content_type, :string, required: true, doc: "Schema.org event type"
  attr :domain, :string, default: nil, doc: "Primary domain (trivia, food, movies, etc.)"
  attr :hero_image, :string, default: nil, doc: "Background image URL"
  attr :total_event_count, :integer, required: true, doc: "Total events across all cities"
  attr :location_count, :integer, required: true, doc: "Locations in current scope"
  attr :unique_cities, :integer, default: 1, doc: "Number of unique cities"
  attr :out_of_city_count, :integer, default: 0, doc: "Events outside current city"
  attr :scope, :atom, default: :city_only, doc: "Current scope (:city_only or :all_cities)"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def aggregated_hero_card(assigns) do
    theme = get_theme(assigns.domain, assigns.content_type)

    assigns =
      assigns
      |> assign(:theme, theme)
      |> assign(:gradient_class, HeroCardTheme.gradient_class(theme))
      |> assign(:overlay_class, HeroCardTheme.overlay_class(theme))
      |> assign(:badge_class, HeroCardTheme.badge_class(theme))
      |> assign(:button_class, HeroCardTheme.button_class(theme))

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background Image or Gradient -->
      <%= if @hero_image do %>
        <div class="absolute inset-0">
          <img
            src={CDN.url(@hero_image, width: 1200, quality: 85)}
            alt=""
            class="w-full h-full object-cover"
            aria-hidden="true"
          />
          <div class={"absolute inset-0 #{@overlay_class}"} />
        </div>
      <% else %>
        <div class={"absolute inset-0 #{@gradient_class}"} />
      <% end %>

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="max-w-3xl">
          <!-- Badges Row -->
          <div class="flex flex-wrap items-center gap-2 mb-4">
            <!-- Category Badge -->
            <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", @badge_class]}>
              <.theme_icon theme={@theme} class="w-4 h-4 mr-1.5" />
              <%= category_label(@theme) %>
            </span>

            <!-- Multi-city Badge -->
            <%= if @out_of_city_count > 0 do %>
              <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-500/20 text-blue-100">
                <Heroicons.map_pin class="w-4 h-4 mr-1.5" />
                <%= gettext("Multi-city") %>
              </span>
            <% end %>
          </div>

          <!-- Source Logo + Title -->
          <div class="flex items-start gap-4 mb-4">
            <%= if @source_logo_url do %>
              <img
                src={CDN.url(@source_logo_url, width: 80, height: 80, fit: "contain")}
                alt={@source_name}
                class="w-16 h-16 md:w-20 md:h-20 rounded-lg bg-white/10 p-2 flex-shrink-0"
              />
            <% end %>
            <div>
              <h1 class="text-2xl md:text-4xl font-bold text-white tracking-tight">
                <%= @source_name %>
              </h1>
              <p class="text-lg md:text-xl text-white/80 mt-1">
                <%= gettext("in") %> <%= @city.name %>
              </p>
            </div>
          </div>

          <!-- Location Stats -->
          <div class="flex items-center text-white/90 mb-6">
            <Heroicons.building_storefront class="w-5 h-5 mr-2" />
            <span>
              <%= if @scope == :all_cities do %>
                <%= @total_event_count %> <%= ngettext("location", "locations", @total_event_count) %> <%= gettext("across") %> <%= @unique_cities %> <%= ngettext("city", "cities", @unique_cities) %>
              <% else %>
                <%= @location_count %> <%= ngettext("location", "locations", @location_count) %> <%= gettext("in") %> <%= @city.name %>
              <% end %>
            </span>
          </div>

          <!-- Scope Toggle Buttons -->
          <div class="flex flex-wrap gap-3">
            <%= if @scope == :city_only && @out_of_city_count > 0 do %>
              <button
                phx-click="toggle_scope"
                phx-value-scope="all_cities"
                class={["inline-flex items-center px-5 py-2.5 text-sm font-semibold rounded-lg transition shadow-md", @button_class]}
              >
                <Heroicons.globe_alt class="w-5 h-5 mr-2" />
                <%= gettext("View all %{count} locations in %{cities} cities", count: @total_event_count, cities: @unique_cities) %>
              </button>
            <% end %>

            <%= if @scope == :all_cities do %>
              <button
                phx-click="toggle_scope"
                phx-value-scope="city_only"
                class="inline-flex items-center px-5 py-2.5 bg-white/10 border border-white/30 text-white text-sm font-medium rounded-lg hover:bg-white/20 transition"
              >
                <Heroicons.arrow_uturn_left class="w-5 h-5 mr-2" />
                <%= gettext("Show only %{city}", city: @city.name) %>
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Theme icon component
  attr :theme, :atom, required: true
  attr :class, :string, default: ""

  defp theme_icon(assigns) do
    ~H"""
    <%= case @theme do %>
      <% :trivia -> %>
        <Heroicons.puzzle_piece class={@class} />
      <% :food -> %>
        <Heroicons.cake class={@class} />
      <% :movies -> %>
        <Heroicons.film class={@class} />
      <% :music -> %>
        <Heroicons.musical_note class={@class} />
      <% :festival -> %>
        <Heroicons.sparkles class={@class} />
      <% :social -> %>
        <Heroicons.user_group class={@class} />
      <% :comedy -> %>
        <Heroicons.face_smile class={@class} />
      <% :theater -> %>
        <Heroicons.ticket class={@class} />
      <% :sports -> %>
        <Heroicons.trophy class={@class} />
      <% _ -> %>
        <Heroicons.calendar class={@class} />
    <% end %>
    """
  end

  # Determine theme based on domain and content type
  defp get_theme(domain, content_type) do
    # Domain takes priority over content_type
    case domain do
      d when d in ["trivia", "quiz"] -> :trivia
      d when d in ["food", "restaurant"] -> :food
      d when d in ["movies", "screening", "cinema"] -> :movies
      d when d in ["music", "concert"] -> :music
      d when d in ["festival"] -> :festival
      d when d in ["comedy"] -> :comedy
      d when d in ["theater", "theatre"] -> :theater
      d when d in ["sports"] -> :sports
      _ -> get_theme_from_content_type(content_type)
    end
  end

  defp get_theme_from_content_type(content_type) do
    case content_type do
      "SocialEvent" -> :social
      "FoodEvent" -> :food
      "ScreeningEvent" -> :movies
      "MusicEvent" -> :music
      "Festival" -> :festival
      "ComedyEvent" -> :comedy
      "TheaterEvent" -> :theater
      "SportsEvent" -> :sports
      _ -> :default
    end
  end

  # Category labels
  defp category_label(:trivia), do: gettext("Pub Quiz")
  defp category_label(:food), do: gettext("Food & Dining")
  defp category_label(:movies), do: gettext("Movies")
  defp category_label(:music), do: gettext("Music")
  defp category_label(:festival), do: gettext("Festival")
  defp category_label(:social), do: gettext("Social Events")
  defp category_label(:comedy), do: gettext("Comedy")
  defp category_label(:theater), do: gettext("Theater")
  defp category_label(:sports), do: gettext("Sports")
  defp category_label(_), do: gettext("Events")
end
