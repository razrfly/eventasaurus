defmodule EventasaurusWeb.Components.Activity.ContainerHeroCard do
  @moduledoc """
  Hero card for container detail pages (festivals, conferences, tours, etc.).

  Displays container information with content-type theming that matches
  the AggregatedHeroCard and individual activity hero cards.

  ## Features

  - Rounded card design matching activity pages
  - Content-type based gradient theming (festival, food, movies, music, etc.)
  - Container branding with optional logo
  - Date range display
  - Event count
  - City context
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN
  alias EventasaurusWeb.Components.Activity.{HeroCardBackground, HeroCardIcons, HeroCardTheme}

  @doc """
  Renders the hero card for container detail pages.

  ## Attributes

    * `:title` - Required. Display title of the container.
    * `:container_type` - Required. Type atom (:festival, :conference, :tour, etc.).
    * `:description` - Optional. Container description.
    * `:city` - Required. The current city struct with name and slug.
    * `:hero_image` - Optional. Background image URL.
    * `:event_count` - Required. Number of events in this container.
    * `:start_date` - Optional. Container start date.
    * `:end_date` - Optional. Container end date.
    * `:logo_url` - Optional. Logo URL for the container/source.
    * `:class` - Optional. Additional CSS classes.
  """
  attr :title, :string, required: true, doc: "Display title of the container"
  attr :container_type, :atom, required: true, doc: "Type (:festival, :conference, :tour, etc.)"
  attr :description, :string, default: nil, doc: "Container description"
  attr :city, :map, required: true, doc: "Current city struct"
  attr :hero_image, :string, default: nil, doc: "Background image URL"
  attr :event_count, :integer, required: true, doc: "Number of events"
  attr :start_date, :any, default: nil, doc: "Container start date"
  attr :end_date, :any, default: nil, doc: "Container end date"
  attr :logo_url, :string, default: nil, doc: "Logo URL for the container"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def container_hero_card(assigns) do
    theme = get_theme_from_container_type(assigns.container_type)

    assigns =
      assigns
      |> assign(:theme, theme)
      |> assign(:badge_class, HeroCardTheme.badge_class(theme))

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background -->
      <HeroCardBackground.background image_url={@hero_image} theme={@theme} />

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="max-w-3xl">
          <!-- Badges Row -->
          <div class="flex flex-wrap items-center gap-2 mb-4">
            <!-- Container Type Badge -->
            <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", @badge_class]}>
              <HeroCardIcons.icon type={@theme} class="w-4 h-4 mr-1.5" />
              <%= HeroCardTheme.label(@theme) %>
            </span>
          </div>

          <!-- Logo + Title -->
          <div class="flex items-start gap-4 mb-4">
            <%= if @logo_url do %>
              <img
                src={CDN.url(@logo_url, width: 80, height: 80, fit: "contain")}
                alt={@title}
                class="w-16 h-16 md:w-20 md:h-20 rounded-lg bg-white/10 p-2 flex-shrink-0"
              />
            <% end %>
            <div>
              <h1 class="text-2xl md:text-4xl font-bold text-white tracking-tight">
                <%= @title %>
              </h1>
              <p class="text-lg md:text-xl text-white/80 mt-1">
                <%= gettext("in") %> <%= @city.name %>
              </p>
            </div>
          </div>

          <!-- Stats Row -->
          <div class="flex flex-wrap items-center gap-6 text-white/90 mb-4">
            <!-- Date Range -->
            <%= if @start_date do %>
              <div class="flex items-center">
                <Heroicons.calendar class="w-5 h-5 mr-2" />
                <span class="font-medium">
                  <%= format_date_range(@start_date, @end_date) %>
                </span>
              </div>
            <% end %>

            <!-- Event Count -->
            <div class="flex items-center">
              <Heroicons.ticket class="w-5 h-5 mr-2" />
              <span><%= @event_count %> <%= ngettext("event", "events", @event_count) %></span>
            </div>
          </div>

          <!-- Description -->
          <%= if @description do %>
            <p class="text-white/80 text-base md:text-lg max-w-2xl">
              <%= @description %>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Map container type to theme
  defp get_theme_from_container_type(container_type) do
    case container_type do
      :festival -> :festival
      :conference -> :conference
      :tour -> :tour
      :series -> :series
      :exhibition -> :exhibition
      :tournament -> :tournament
      _ -> :default
    end
  end

  # Format date range
  defp format_date_range(nil, _end_date), do: gettext("Date TBD")

  defp format_date_range(%DateTime{} = start_date, nil) do
    gettext("Starting %{date}", date: format_date(start_date))
  end

  defp format_date_range(%DateTime{} = start_date, %DateTime{} = end_date) do
    "#{format_date(start_date)} - #{format_date(end_date)}"
  end

  defp format_date_range(start_date, end_date) do
    # Handle other date types
    "#{format_date(start_date)} - #{format_date(end_date)}"
  end

  defp format_date(nil), do: gettext("TBD")

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  defp format_date(_), do: gettext("TBD")
end
