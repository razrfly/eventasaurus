defmodule EventasaurusWeb.Live.Components.PublicMovieHeroComponent do
  @moduledoc """
  Hero section component for public event pages with movie data.

  Creates a cinematic hero section with movie backdrop, event details overlay,
  and integrated movie information in a Facebook-style layout.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative min-h-[40vh] md:min-h-[50vh] bg-gray-900 rounded-lg overflow-hidden">
      <!-- Movie Backdrop -->
      <%= if @has_backdrop do %>
        <img
          src={@backdrop_url}
          alt={@movie_title}
          class="absolute inset-0 w-full h-full object-cover"
          loading="lazy"
        />
      <% end %>

      <!-- Gradient Overlay -->
      <div class="absolute inset-0 bg-gradient-to-t from-black/80 via-black/40 to-black/20" />

      <!-- Hero Content -->
      <div class="absolute inset-0 flex items-end">
        <div class="w-full p-6 lg:p-8">
          <div class="flex flex-col lg:flex-row gap-6 max-w-6xl mx-auto">
            <!-- Movie Poster -->
            <%= if @has_poster do %>
              <div class="flex-shrink-0">
                <img
                  src={@poster_url}
                  alt={"#{@movie_title} poster"}
                  class="w-32 h-48 lg:w-40 lg:h-60 object-cover rounded-lg shadow-2xl"
                  loading="lazy"
                />
              </div>
            <% end %>

            <!-- Movie & Event Info -->
            <div class="flex-1 text-white space-y-4">
              <!-- Movie Title -->
              <div>
                <h1 class="text-3xl md:text-4xl font-bold tracking-tight mb-2">
                  <%= @movie_title %>
                  <%= if @release_year do %>
                    <span class="font-normal text-white/80">(<%= @release_year %>)</span>
                  <% end %>
                </h1>

                <%= if @tagline do %>
                  <p class="text-lg md:text-xl italic text-white/90 mb-3">
                    <%= @tagline %>
                  </p>
                <% end %>
              </div>

              <!-- Movie Details Row -->
              <div class="flex flex-wrap items-center gap-4 text-sm md:text-base">
                <%= if @rating do %>
                  <div class="flex items-center gap-1">
                    <.icon name="hero-star-solid" class="h-4 w-4 text-yellow-400" />
                    <span class="font-medium"><%= format_rating(@rating) %></span>
                  </div>
                <% end %>

                <%= if @runtime do %>
                  <span class="text-white/80"><%= format_runtime(@runtime) %></span>
                <% end %>

                <%= if @genres && length(@genres) > 0 do %>
                  <div class="flex flex-wrap gap-2">
                    <%= for genre <- Enum.take(@genres, 3) do %>
                      <span class="px-2 py-1 bg-white/20 rounded-full text-xs font-medium">
                        <%= genre %>
                      </span>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <!-- Movie Overview -->
              <%= if @overview do %>
                <div class="max-w-3xl">
                  <p class="text-white/90 leading-relaxed line-clamp-3">
                    <%= @overview %>
                  </p>
                </div>
              <% end %>
            </div>

            <!-- Event Details Card -->
            <div class="flex-shrink-0 bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20 min-w-80">
              <div class="space-y-4">
                <!-- Event Title -->
                <div>
                  <h2 class="text-xl font-semibold text-white mb-2">
                    <%= @event.title %>
                  </h2>
                  <%= if @event.tagline && @event.tagline != @tagline do %>
                    <p class="text-white/80 text-sm">
                      <%= @event.tagline %>
                    </p>
                  <% end %>
                </div>

                <!-- Event Date/Time -->
                <div class="flex items-center gap-3">
                  <div class="flex-shrink-0 w-8 h-8 bg-white/20 rounded-lg flex items-center justify-center">
                    <.icon name="hero-calendar-days" class="w-4 h-4 text-white" />
                  </div>
                  <div class="text-white">
                    <div class="font-medium">
                      <%= format_event_date(@event) %>
                    </div>
                    <div class="text-sm text-white/80">
                      <%= format_event_time(@event) %>
                    </div>
                  </div>
                </div>

                <!-- Event Location -->
                <div class="flex items-center gap-3">
                  <div class="flex-shrink-0 w-8 h-8 bg-white/20 rounded-lg flex items-center justify-center">
                    <.icon name="hero-map-pin" class="w-4 h-4 text-white" />
                  </div>
                  <div class="text-white">
                    <div class="font-medium">
                      <%= if @venue do %>
                        <%= @venue.name %>
                      <% else %>
                        Virtual Event
                      <% end %>
                    </div>
                    <%= if @venue do %>
                      <div class="text-sm text-white/80">
                        <%= @venue.address %>
                      </div>
                    <% end %>
                  </div>
                </div>

                <!-- Event Type -->
                <div class="flex items-center gap-3">
                  <div class="flex-shrink-0 w-8 h-8 bg-white/20 rounded-lg flex items-center justify-center">
                    <.icon name="hero-ticket" class="w-4 h-4 text-white" />
                  </div>
                  <div class="text-white">
                    <div class="font-medium">
                      <%= format_event_type(@event) %>
                    </div>
                    <div class="text-sm text-white/80">
                      <%= get_event_type_description(@event) %>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns[:rich_data]

    socket
    |> assign(:movie_title, get_movie_title(rich_data))
    |> assign(:tagline, get_tagline(rich_data))
    |> assign(:release_year, get_release_year(rich_data))
    |> assign(:rating, get_rating(rich_data))
    |> assign(:runtime, get_runtime(rich_data))
    |> assign(:genres, get_genres(rich_data))
    |> assign(:overview, get_overview(rich_data))
    |> assign(:has_backdrop, has_backdrop?(rich_data))
    |> assign(:backdrop_url, get_backdrop_url(rich_data))
    |> assign(:has_poster, has_poster?(rich_data))
    |> assign(:poster_url, get_poster_url(rich_data))
  end

  defp get_movie_title(nil), do: nil
  defp get_movie_title(rich_data) do
    rich_data["title"] || rich_data["name"]
  end

  defp get_tagline(nil), do: nil
  defp get_tagline(rich_data) do
    get_in(rich_data, ["metadata", "tagline"])
  end

  defp get_release_year(nil), do: nil
  defp get_release_year(rich_data) do
    date = get_in(rich_data, ["metadata", "release_date"]) || get_in(rich_data, ["metadata", "first_air_date"])
    case date do
      date when is_binary(date) ->
        case String.slice(date, 0, 4) do
          year when byte_size(year) == 4 -> year
          _ -> nil
        end
      _ -> nil
    end
  end

  defp get_rating(nil), do: nil
  defp get_rating(rich_data) do
    get_in(rich_data, ["metadata", "vote_average"])
  end

  defp get_runtime(nil), do: nil
  defp get_runtime(rich_data) do
    get_in(rich_data, ["metadata", "runtime"])
  end

  defp get_genres(nil), do: []
  defp get_genres(rich_data) do
    get_in(rich_data, ["metadata", "genres"]) || []
  end

  defp get_overview(nil), do: nil
  defp get_overview(rich_data) do
    rich_data["description"] || get_in(rich_data, ["metadata", "overview"])
  end

  defp has_backdrop?(nil), do: false
  defp has_backdrop?(rich_data) do
    backdrops = get_in(rich_data, ["media", "images", "backdrops"])
    is_list(backdrops) && length(backdrops) > 0
  end

  defp get_backdrop_url(rich_data) do
    case get_in(rich_data, ["media", "images", "backdrops"]) do
      [first_backdrop | _] when is_map(first_backdrop) ->
        case first_backdrop["file_path"] do
          path when is_binary(path) and path != "" ->
            RichDataDisplayComponent.tmdb_image_url(path, "w1280")
          _ -> nil
        end
      _ -> nil
    end
  end

  defp has_poster?(nil), do: false
  defp has_poster?(rich_data) do
    posters = get_in(rich_data, ["media", "images", "posters"])
    is_list(posters) && length(posters) > 0
  end

  defp get_poster_url(rich_data) do
    case get_in(rich_data, ["media", "images", "posters"]) do
      [first_poster | _] when is_map(first_poster) ->
        case first_poster["file_path"] do
          path when is_binary(path) and path != "" ->
            RichDataDisplayComponent.tmdb_image_url(path, "w342")
          _ -> nil
        end
      _ -> nil
    end
  end

  # Helper functions for formatting

  defp format_rating(nil), do: nil
  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating, [{:decimals, 1}])
  end
  defp format_rating(_), do: nil

  defp format_runtime(nil), do: nil
  defp format_runtime(runtime) when is_integer(runtime) do
    hours = div(runtime, 60)
    minutes = rem(runtime, 60)

    cond do
      hours > 0 && minutes > 0 -> "#{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h"
      minutes > 0 -> "#{minutes}m"
      true -> nil
    end
  end
  defp format_runtime(_), do: nil

  defp format_event_date(event) do
    case event.start_at do
      %DateTime{} = dt ->
        timezone = event.timezone || "UTC"
        dt
        |> EventasaurusWeb.TimezoneHelpers.convert_to_timezone(timezone)
        |> Calendar.strftime("%A, %B %d, %Y")
      _ -> "TBD"
    end
  end

  defp format_event_time(event) do
    case event.start_at do
      %DateTime{} = dt ->
        timezone = event.timezone || "UTC"
        start_time = dt
        |> EventasaurusWeb.TimezoneHelpers.convert_to_timezone(timezone)
        |> Calendar.strftime("%I:%M %p")
        |> String.replace(" 0", " ")

        end_time = case event.ends_at do
          %DateTime{} = end_dt ->
            end_dt
            |> EventasaurusWeb.TimezoneHelpers.convert_to_timezone(timezone)
            |> Calendar.strftime("%I:%M %p")
            |> String.replace(" 0", " ")
          _ -> nil
        end

        if end_time do
          "#{start_time} - #{end_time} #{timezone}"
        else
          "#{start_time} #{timezone}"
        end
      _ -> "Time TBD"
    end
  end

  defp format_event_type(event) do
    case event.taxation_type do
      "ticketed_event" -> "Ticketed Event"
      "contribution_collection" -> "Contribution Collection"
      "ticketless" -> "Free Event"
      _ -> "Free Event"
    end
  end

  defp get_event_type_description(event) do
    case event.taxation_type do
      "ticketed_event" -> "Requires ticket purchase"
      "contribution_collection" -> "Free with optional contributions"
      "ticketless" -> "Free registration"
      _ -> "Free registration"
    end
  end
end
