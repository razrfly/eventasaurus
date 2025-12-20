defmodule EventasaurusWeb.Components.Activity.PerformerHeroCard do
  @moduledoc """
  Hero card for performer/artist pages.

  Displays performer information with a prominent background image,
  matching the visual style of other hero cards (VenueHeroCard,
  ConcertHeroCard, etc.)

  ## Features

  - Rounded card design matching activity pages
  - Background image from performer with gradient overlay
  - Purple gradient fallback for music artists
  - Performer name prominently displayed
  - Country flag and origin
  - Genre badges from metadata
  - External links (Resident Advisor, etc.)
  - Upcoming event count badge
  - Stats integrated as badges
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN

  alias EventasaurusWeb.Components.Activity.{
    HeroCardBadge,
    HeroCardBackground,
    HeroCardIcons,
    HeroCardTheme
  }

  alias EventasaurusWeb.Components.CountryFlag

  @doc """
  Renders the performer hero card.

  ## Attributes

    * `:performer` - Required. The performer struct with name, image_url, metadata, etc.
    * `:upcoming_event_count` - Required. Number of upcoming events for this performer.
    * `:total_event_count` - Optional. Total number of events (past + upcoming).
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :performer, :map, required: true, doc: "Performer struct with name, image_url, metadata"
  attr :upcoming_event_count, :integer, required: true, doc: "Number of upcoming events"
  attr :total_event_count, :integer, default: 0, doc: "Total number of events"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def performer_hero_card(assigns) do
    # Extract metadata fields
    genres = get_genres(assigns.performer)
    country = get_country(assigns.performer)
    country_code = get_country_code(assigns.performer)
    ra_url = get_ra_url(assigns.performer)

    assigns =
      assigns
      |> assign(:genres, genres)
      |> assign(:country, country)
      |> assign(:country_code, country_code)
      |> assign(:ra_url, ra_url)

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background -->
      <HeroCardBackground.background image_url={@performer.image_url} theme={:performer} />

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="flex flex-col md:flex-row gap-6">
          <!-- Performer Image -->
          <%= if @performer.image_url do %>
            <div class="flex-shrink-0 self-start">
              <img
                src={CDN.url(@performer.image_url, width: 200, height: 200, fit: "cover", quality: 90)}
                alt={@performer.name}
                class="w-32 md:w-40 h-32 md:h-40 object-cover rounded-lg shadow-2xl"
                loading="lazy"
              />
            </div>
          <% else %>
            <!-- Fallback avatar with initial -->
            <div class="flex-shrink-0 self-start">
              <div class="w-32 md:w-40 h-32 md:h-40 rounded-lg bg-gradient-to-br from-purple-500 to-fuchsia-600 flex items-center justify-center shadow-2xl">
                <span class="text-5xl md:text-6xl text-white font-bold">
                  <%= String.first(@performer.name) %>
                </span>
              </div>
            </div>
          <% end %>

          <div class="flex-1">
            <!-- Badges Row -->
            <div class="flex flex-wrap items-center gap-2 mb-4">
              <!-- Artist Badge -->
              <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", HeroCardTheme.badge_class(:performer)]}>
                <HeroCardIcons.icon type={:performer} class="w-4 h-4 mr-1.5" />
                <%= HeroCardTheme.label(:performer) %>
              </span>

              <!-- Upcoming Event Count Badge -->
              <%= if @upcoming_event_count > 0 do %>
                <HeroCardBadge.success_badge>
                  <Heroicons.calendar class="w-4 h-4 mr-1.5" />
                  <%= ngettext("%{count} upcoming event", "%{count} upcoming events", @upcoming_event_count, count: @upcoming_event_count) %>
                </HeroCardBadge.success_badge>
              <% end %>

              <!-- Total Events Badge -->
              <%= if @total_event_count > 0 do %>
                <HeroCardBadge.muted_badge>
                  <Heroicons.chart_bar class="w-4 h-4 mr-1.5" />
                  <%= ngettext("%{count} total event", "%{count} total events", @total_event_count, count: @total_event_count) %>
                </HeroCardBadge.muted_badge>
              <% end %>
            </div>

            <!-- Performer Name with Country Flag -->
            <div class="flex items-center gap-3 mb-3">
              <h1 class="text-2xl md:text-4xl font-bold text-white tracking-tight">
                <%= @performer.name %>
              </h1>
              <%= if @country_code do %>
                <CountryFlag.flag country_code={@country_code} size="lg" />
              <% end %>
            </div>

            <!-- Country -->
            <%= if @country do %>
              <div class="flex items-center text-white/80 mb-4">
                <Heroicons.map_pin class="w-5 h-5 mr-2" />
                <span><%= @country %></span>
              </div>
            <% end %>

            <!-- Genre Badges -->
            <%= if length(@genres) > 0 do %>
              <div class="flex flex-wrap gap-2 mb-5">
                <%= for genre <- Enum.take(@genres, 5) do %>
                  <span class="px-3 py-1 bg-white/20 rounded-full text-sm font-medium text-white">
                    <%= genre %>
                  </span>
                <% end %>
              </div>
            <% end %>

            <!-- External Links -->
            <div class="flex flex-wrap items-center gap-3">
              <%= if @ra_url do %>
                <a
                  href={@ra_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class={["inline-flex items-center px-5 py-2.5 text-sm font-semibold rounded-lg transition shadow-md", HeroCardTheme.button_class(:performer)]}
                >
                  <Heroicons.arrow_top_right_on_square class="w-5 h-5 mr-2" />
                  <%= gettext("Resident Advisor") %>
                </a>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helpers

  defp get_genres(%{metadata: %{"genres" => genres}}) when is_list(genres), do: genres
  defp get_genres(_), do: []

  defp get_country(%{metadata: %{"country" => country}}) when is_binary(country), do: country
  defp get_country(_), do: nil

  defp get_country_code(%{metadata: %{"country_code" => code}}) when is_binary(code), do: code
  defp get_country_code(_), do: nil

  defp get_ra_url(%{metadata: %{"ra_artist_url" => url}}) when is_binary(url), do: url
  defp get_ra_url(_), do: nil
end
