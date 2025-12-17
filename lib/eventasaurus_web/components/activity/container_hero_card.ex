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
      |> assign(:gradient_class, gradient_class(theme))
      |> assign(:overlay_class, overlay_class(theme))
      |> assign(:badge_class, badge_class(theme))

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
            <!-- Container Type Badge -->
            <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", @badge_class]}>
              <.theme_icon theme={@theme} class="w-4 h-4 mr-1.5" />
              <%= container_type_label(@container_type) %>
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

  # Theme icon component
  attr :theme, :atom, required: true
  attr :class, :string, default: ""

  defp theme_icon(assigns) do
    ~H"""
    <%= case @theme do %>
      <% :festival -> %>
        <Heroicons.sparkles class={@class} />
      <% :conference -> %>
        <Heroicons.academic_cap class={@class} />
      <% :tour -> %>
        <Heroicons.map class={@class} />
      <% :series -> %>
        <Heroicons.queue_list class={@class} />
      <% :exhibition -> %>
        <Heroicons.photo class={@class} />
      <% :tournament -> %>
        <Heroicons.trophy class={@class} />
      <% :food -> %>
        <Heroicons.cake class={@class} />
      <% :music -> %>
        <Heroicons.musical_note class={@class} />
      <% :movies -> %>
        <Heroicons.film class={@class} />
      <% _ -> %>
        <Heroicons.calendar class={@class} />
    <% end %>
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

  # Gradient backgrounds - matching AggregatedHeroCard style
  defp gradient_class(:festival), do: "bg-gradient-to-r from-indigo-900 via-violet-800 to-purple-800"
  defp gradient_class(:conference), do: "bg-gradient-to-r from-blue-900 via-blue-800 to-cyan-800"
  defp gradient_class(:tour), do: "bg-gradient-to-r from-emerald-900 via-teal-800 to-cyan-800"
  defp gradient_class(:series), do: "bg-gradient-to-r from-purple-900 via-purple-800 to-fuchsia-900"
  defp gradient_class(:exhibition), do: "bg-gradient-to-r from-amber-900 via-orange-800 to-yellow-800"
  defp gradient_class(:tournament), do: "bg-gradient-to-r from-red-900 via-rose-800 to-pink-800"
  defp gradient_class(_), do: "bg-gradient-to-r from-gray-900 via-gray-800 to-gray-700"

  # Overlay for images (semi-transparent gradient)
  defp overlay_class(:festival), do: "bg-gradient-to-r from-indigo-900/95 via-violet-900/80 to-purple-900/60"
  defp overlay_class(:conference), do: "bg-gradient-to-r from-blue-900/95 via-blue-900/80 to-cyan-900/60"
  defp overlay_class(:tour), do: "bg-gradient-to-r from-emerald-900/95 via-teal-900/80 to-cyan-900/60"
  defp overlay_class(:series), do: "bg-gradient-to-r from-purple-900/95 via-purple-900/80 to-fuchsia-900/60"
  defp overlay_class(:exhibition), do: "bg-gradient-to-r from-amber-900/95 via-orange-900/80 to-yellow-900/60"
  defp overlay_class(:tournament), do: "bg-gradient-to-r from-red-900/95 via-rose-900/80 to-pink-900/60"
  defp overlay_class(_), do: "bg-gradient-to-t from-gray-900/80 to-transparent"

  # Badge styling
  defp badge_class(:festival), do: "bg-indigo-500/20 text-indigo-100"
  defp badge_class(:conference), do: "bg-blue-500/20 text-blue-100"
  defp badge_class(:tour), do: "bg-emerald-500/20 text-emerald-100"
  defp badge_class(:series), do: "bg-purple-500/20 text-purple-100"
  defp badge_class(:exhibition), do: "bg-amber-500/20 text-amber-100"
  defp badge_class(:tournament), do: "bg-red-500/20 text-red-100"
  defp badge_class(_), do: "bg-white/20 text-white"

  # Container type labels
  defp container_type_label(:festival), do: gettext("Festival")
  defp container_type_label(:conference), do: gettext("Conference")
  defp container_type_label(:tour), do: gettext("Tour")
  defp container_type_label(:series), do: gettext("Series")
  defp container_type_label(:exhibition), do: gettext("Exhibition")
  defp container_type_label(:tournament), do: gettext("Tournament")
  defp container_type_label(_), do: gettext("Event Collection")

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
