defmodule EventasaurusWeb.Components.Activity.ConcertHeroCard do
  @moduledoc """
  Specialized hero card for concert/music events on activity pages.

  Displays concert information in a hero-style layout with cover image,
  performer names, venue, date/time, and genre badges. Optimized for
  MusicEvent schema types.

  ## Features

  - Cover image with gradient overlay (or purple gradient fallback)
  - Headliner/performer names prominently displayed
  - Performer images (if available)
  - Venue and location information
  - Date and time with doors/start times
  - Genre badges from performer metadata
  - Ticket link (if available)
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN
  alias EventasaurusApp.Images.PerformerImages

  alias EventasaurusWeb.Components.Activity.{
    HeroCardBackground,
    HeroCardHelpers,
    HeroCardIcons,
    HeroCardTheme
  }

  @doc """
  Renders the concert hero card for music events.

  ## Attributes

    * `:event` - Required. The public event struct with title, performers, venue, etc.
    * `:performers` - Required. List of performer structs associated with the event.
    * `:cover_image_url` - Optional. Cover image URL for the hero background.
    * `:ticket_url` - Optional. URL to purchase tickets.
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :event, :map, required: true, doc: "PublicEvent struct with display_title, venue, etc."
  attr :performers, :list, required: true, doc: "List of Performer structs"
  attr :cover_image_url, :string, default: nil, doc: "Cover image URL for the hero background"
  attr :ticket_url, :string, default: nil, doc: "URL to ticket purchase page"
  attr :class, :string, default: "", doc: "Additional CSS classes for the container"

  def concert_hero_card(assigns) do
    # Get headliner (first performer) and supporting acts
    headliner = List.first(assigns.performers)
    supporting_acts = Enum.drop(assigns.performers, 1)

    # Extract genres from performer metadata
    genres = extract_genres(assigns.performers)

    # Batch fetch cached image URLs for all performers (avoids N+1)
    performer_fallbacks =
      Map.new(assigns.performers, fn p -> {p.id, p.image_url} end)

    performer_image_urls = PerformerImages.get_urls_with_fallbacks(performer_fallbacks)

    # Get headliner image URL
    headliner_image_url =
      if headliner, do: Map.get(performer_image_urls, headliner.id), else: nil

    assigns =
      assigns
      |> assign(:headliner, headliner)
      |> assign(:headliner_image_url, headliner_image_url)
      |> assign(:supporting_acts, supporting_acts)
      |> assign(:performer_image_urls, performer_image_urls)
      |> assign(:genres, genres)

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background -->
      <HeroCardBackground.background image_url={@cover_image_url} theme={:music} />

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="flex flex-col md:flex-row gap-6">
          <!-- Performer Image (if headliner has one) -->
          <%= if @headliner && @headliner_image_url do %>
            <div class="flex-shrink-0 self-start">
              <img
                src={CDN.url(@headliner_image_url, width: 200, height: 200, fit: "cover", quality: 90)}
                alt={@headliner.name}
                class="w-32 md:w-40 h-32 md:h-40 object-cover rounded-lg shadow-2xl"
                loading="lazy"
              />
            </div>
          <% end %>

          <div class="flex-1">
            <!-- Music Event Badge -->
            <div class="mb-4">
              <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", HeroCardTheme.badge_class(:music)]}>
                <HeroCardIcons.icon type={:music} class="w-4 h-4 mr-1.5" />
                <%= HeroCardTheme.label(:music) %>
              </span>
            </div>

            <!-- Headliner Name -->
            <%= if @headliner do %>
              <h1 class="text-3xl md:text-4xl font-bold text-white tracking-tight mb-2">
                <%= @headliner.name %>
              </h1>
            <% else %>
              <h1 class="text-3xl md:text-4xl font-bold text-white tracking-tight mb-2">
                <%= @event.display_title || @event.title %>
              </h1>
            <% end %>

            <!-- Supporting Acts -->
            <%= if length(@supporting_acts) > 0 do %>
              <p class="text-lg text-white/80 mb-4">
                <%= gettext("with") %>
                <span class="text-white font-medium">
                  <%= format_supporting_acts(@supporting_acts) %>
                </span>
              </p>
            <% end %>

            <!-- Genre Badges -->
            <%= if length(@genres) > 0 do %>
              <div class="flex flex-wrap gap-2 mb-4">
                <%= for genre <- Enum.take(@genres, 4) do %>
                  <span class="px-2 py-1 bg-white/20 rounded-full text-xs font-medium text-white">
                    <%= genre %>
                  </span>
                <% end %>
              </div>
            <% end %>

            <!-- Date & Time -->
            <%= if @event.starts_at do %>
              <div class="flex items-center text-white/90 mb-3">
                <Heroicons.calendar class="w-5 h-5 mr-2" />
                <span class="text-lg">
                  <%= HeroCardHelpers.format_datetime(@event.starts_at, "%A, %B %d, %Y · %I:%M %p") %>
                </span>
              </div>
            <% end %>

            <!-- Venue -->
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
                  class={["inline-flex items-center px-5 py-2.5 text-sm font-semibold rounded-lg transition shadow-md", HeroCardTheme.button_class(:music)]}
                >
                  <Heroicons.ticket class="w-5 h-5 mr-2" />
                  <%= gettext("Get Tickets") %>
                </a>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Additional Performers Row (if many performers) -->
        <%= if length(@supporting_acts) > 3 do %>
          <div class="mt-6 pt-6 border-t border-white/20">
            <h3 class="text-sm font-medium text-white/70 mb-3">
              <%= gettext("Also Performing") %>
            </h3>
            <div class="flex flex-wrap gap-4">
              <%= for performer <- Enum.drop(@supporting_acts, 3) do %>
                <% performer_img = Map.get(@performer_image_urls, performer.id) %>
                <div class="flex items-center gap-2">
                  <%= if performer_img do %>
                    <img
                      src={CDN.url(performer_img, width: 32, height: 32, fit: "cover", quality: 80)}
                      alt={performer.name}
                      class="w-8 h-8 rounded-full object-cover"
                    />
                  <% else %>
                    <div class="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center">
                      <Heroicons.user class="w-4 h-4 text-white/60" />
                    </div>
                  <% end %>
                  <span class="text-sm text-white/80"><%= performer.name %></span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp extract_genres(performers) do
    performers
    |> Enum.flat_map(fn performer ->
      case performer.metadata do
        %{"genres" => genres} when is_list(genres) -> genres
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.take(6)
  end

  defp format_supporting_acts(performers) do
    performers
    |> Enum.take(3)
    |> Enum.map(& &1.name)
    |> case do
      [single] -> single
      [a, b] -> "#{a} & #{b}"
      names -> Enum.join(names, ", ")
    end
  end
end
