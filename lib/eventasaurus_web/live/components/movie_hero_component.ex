defmodule EventasaurusWeb.Live.Components.MovieHeroComponent do
  @moduledoc """
  Hero section component for movie/TV show display.

  Features backdrop image, poster, title, tagline, ratings, and key metadata
  inspired by TMDB's movie page design.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Utils.MovieUtils

  @impl true
  def update(assigns, socket) do
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("MovieHeroComponent update called with rich_data: #{inspect(assigns[:rich_data])}")
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:compact, fn -> false end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative">
      <%= if @has_backdrop do %>
        <!-- Backdrop Image -->
        <div class="relative aspect-video lg:aspect-[21/9] bg-gray-900 rounded-lg overflow-hidden">
          <img
            src={@backdrop_url}
            alt={@title}
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <!-- Gradient overlay -->
          <div class="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />

          <!-- Hero content overlay -->
          <div class="absolute inset-0 flex items-end">
            <div class="w-full p-6 lg:p-8">
              <div class="flex flex-col lg:flex-row gap-6">
                <%= if @has_poster do %>
                  <!-- Poster -->
                  <div class="flex-shrink-0">
                    <img
                      src={@poster_url}
                      alt={"#{@title} poster"}
                      class="w-32 lg:w-48 h-auto rounded-lg shadow-2xl"
                      loading="lazy"
                    />
                  </div>
                <% end %>

                <!-- Title and details -->
                <div class="flex-1 text-white">
                  <.hero_title_section
                    title={@title}
                    tagline={@tagline}
                    release_info={@release_info}
                    rating={@rating}
                    runtime={@runtime}
                    genres={@genres}
                    compact={@compact}
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <!-- No backdrop fallback -->
        <div class="bg-gradient-to-br from-gray-900 to-gray-800 text-white rounded-lg p-6 lg:p-8">
          <div class="flex flex-col lg:flex-row gap-6">
            <%= if @has_poster do %>
              <div class="flex-shrink-0">
                <img
                  src={@poster_url}
                  alt={"#{@title} poster"}
                  class="w-32 lg:w-48 h-auto rounded-lg shadow-lg"
                  loading="lazy"
                />
              </div>
            <% end %>

            <div class="flex-1">
              <.hero_title_section
                title={@title}
                tagline={@tagline}
                release_info={@release_info}
                rating={@rating}
                runtime={@runtime}
                genres={@genres}
                compact={@compact}
              />
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp hero_title_section(assigns) do
    ~H"""
    <div class="space-y-3">
      <!-- Title -->
      <h1 class={[
        "font-bold tracking-tight",
        @compact && "text-2xl lg:text-3xl" || "text-3xl lg:text-5xl"
      ]}>
        <%= @title %>
        <%= if @release_info[:year] do %>
          <span class="font-normal text-white/80">(<%= @release_info[:year] %>)</span>
        <% end %>
      </h1>

      <!-- Tagline -->
      <%= if @tagline do %>
        <p class={[
          "italic text-white/90",
          @compact && "text-sm" || "text-lg"
        ]}>
          <%= @tagline %>
        </p>
      <% end %>

      <!-- Metadata row -->
      <div class="flex flex-wrap items-center gap-4 text-sm lg:text-base">
        <!-- Rating -->
        <%= if @rating do %>
          <div class="flex items-center gap-1">
            <.icon name="hero-star-solid" class="h-4 w-4 text-yellow-400" />
            <span class="font-medium"><%= format_rating(@rating) %></span>
          </div>
        <% end %>

        <!-- Release date -->
        <%= if @release_info[:formatted] do %>
          <span class="text-white/80"><%= @release_info[:formatted] %></span>
        <% end %>

        <!-- Runtime -->
        <%= if @runtime do %>
          <span class="text-white/80"><%= format_runtime(@runtime) %></span>
        <% end %>
      </div>

      <!-- Genres -->
      <%= if @genres && length(@genres) > 0 do %>
        <div class="flex flex-wrap gap-2">
          <%= for genre <- Enum.take(@genres, 4) do %>
            <span class="px-2 py-1 bg-white/20 rounded-full text-xs font-medium">
              <%= genre %>
            </span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data

    socket
    |> assign(:title, MovieUtils.get_title(rich_data))
    |> assign(:tagline, rich_data["tagline"])
    |> assign(:has_backdrop, has_backdrop?(rich_data))
    |> assign(:backdrop_url, MovieUtils.get_backdrop_url(rich_data))
    |> assign(:has_poster, has_poster?(rich_data))
    |> assign(:poster_url, MovieUtils.get_poster_url(rich_data))
    |> assign(:rating, rich_data["vote_average"])
    |> assign(:runtime, rich_data["runtime"])
    |> assign(:genres, MovieUtils.get_genres(rich_data))
    |> assign(:release_info, get_release_info(rich_data))
  end

  defp has_backdrop?(rich_data) do
    backdrop_path = rich_data["backdrop_path"]
    is_binary(backdrop_path) && backdrop_path != ""
  end

  defp has_poster?(rich_data) do
    poster_path = rich_data["poster_path"]
    is_binary(poster_path) && poster_path != ""
  end

  defp get_release_info(rich_data) do
    release_date = rich_data["release_date"] || rich_data["first_air_date"]

    case release_date do
      date_string when is_binary(date_string) and date_string != "" ->
        case Date.from_iso8601(date_string) do
          {:ok, date} ->
            %{
              year: date.year,
              formatted: Calendar.strftime(date, "%B %d, %Y")
            }
          _ ->
            %{}
        end
      _ ->
        %{}
    end
  end

  defp format_rating(nil), do: nil
  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating, [{:decimals, 1}])
  end
  defp format_rating(_), do: nil

  defp format_runtime(nil), do: nil
  defp format_runtime(runtime) when is_integer(runtime) and runtime > 0 do
    hours = div(runtime, 60)
    minutes = rem(runtime, 60)

    case {hours, minutes} do
      {0, min} -> "#{min}m"
      {hr, 0} -> "#{hr}h"
      {hr, min} -> "#{hr}h #{min}m"
    end
  end
  defp format_runtime(_), do: nil
end
