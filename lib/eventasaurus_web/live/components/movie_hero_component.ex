defmodule EventasaurusWeb.Live.Components.MovieHeroComponent do
  @moduledoc """
  Hero section component for movie/TV show display.

  Features a full-bleed backdrop image with overlaid poster, title, tagline,
  ratings, and key metadata. Inspired by Cinegraph's movie page design.

  ## Variants

  - `:full` (default) - Full-bleed hero with large backdrop (h-96 to h-[500px])
  - `:compact` - Smaller hero for embedded contexts (h-64 to h-80)

  ## Props

  - `rich_data` - Movie data from TMDB (required)
  - `variant` - `:full` | `:compact` (default: `:full`)
  - `show_poster` - Boolean to show/hide poster (default: true)
  - `show_director` - Boolean to show director credits (default: true for :full)
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Utils.MovieUtils

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:variant, fn -> :full end)
     |> assign_new(:show_poster, fn -> true end)
     |> assign_new(:show_director, fn -> assigns[:variant] != :compact end)
     |> assign_computed_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative">
      <%= if @has_backdrop do %>
        <!-- Full-bleed Backdrop Hero -->
        <div class={hero_container_classes(@variant)}>
          <img
            src={@backdrop_url}
            alt=""
            class="w-full h-full object-cover"
            loading="lazy"
            aria-hidden="true"
          />
          <!-- Gradient overlay - stronger at bottom for text readability -->
          <div class="absolute inset-0 bg-gradient-to-t from-black via-black/50 to-transparent" />
        </div>

        <!-- Hero Content - positioned over backdrop -->
        <div class={hero_content_wrapper_classes(@variant)}>
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex flex-col md:flex-row gap-6 lg:gap-8 items-start">
              <!-- Poster -->
              <%= if @show_poster && @has_poster do %>
                <div class="flex-shrink-0">
                  <img
                    src={@poster_url}
                    alt={"#{@title} poster"}
                    class={poster_classes(@variant)}
                    loading="lazy"
                  />
                </div>
              <% end %>

              <!-- Movie Info -->
              <div class="flex-1 text-white min-w-0">
                <.hero_content
                  title={@title}
                  tagline={@tagline}
                  release_info={@release_info}
                  rating={@rating}
                  runtime={@runtime}
                  genres={@genres}
                  director={@director}
                  variant={@variant}
                  show_director={@show_director}
                  overview={@overview}
                />
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <!-- No backdrop fallback - gradient background -->
        <div class={fallback_container_classes(@variant)}>
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 lg:py-12">
            <div class="flex flex-col md:flex-row gap-6 lg:gap-8 items-start">
              <%= if @show_poster && @has_poster do %>
                <div class="flex-shrink-0">
                  <img
                    src={@poster_url}
                    alt={"#{@title} poster"}
                    class={poster_classes(@variant)}
                    loading="lazy"
                  />
                </div>
              <% end %>

              <div class="flex-1 text-white min-w-0">
                <.hero_content
                  title={@title}
                  tagline={@tagline}
                  release_info={@release_info}
                  rating={@rating}
                  runtime={@runtime}
                  genres={@genres}
                  director={@director}
                  variant={@variant}
                  show_director={@show_director}
                  overview={@overview}
                />
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp hero_content(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Title -->
      <h1 class={title_classes(@variant)}>
        <%= @title %>
        <%= if @release_info[:year] do %>
          <span class="font-normal text-white/80">(<%= @release_info[:year] %>)</span>
        <% end %>
      </h1>

      <!-- Tagline -->
      <%= if @tagline && @tagline != "" do %>
        <p class={tagline_classes(@variant)}>
          "<%= @tagline %>"
        </p>
      <% end %>

      <!-- Metadata Pills -->
      <div class="flex flex-wrap items-center gap-3">
        <%= if @release_info[:year] do %>
          <.metadata_pill><%= @release_info[:year] %></.metadata_pill>
        <% end %>

        <%= if @runtime do %>
          <.metadata_pill><%= format_runtime(@runtime) %></.metadata_pill>
        <% end %>

        <%= if @rating do %>
          <.metadata_pill>
            <span class="flex items-center gap-1">
              <.icon name="hero-star-solid" class="h-3.5 w-3.5 text-yellow-400" />
              <%= format_rating(@rating) %>/10
            </span>
          </.metadata_pill>
        <% end %>
      </div>

      <!-- Genres -->
      <%= if @genres && length(@genres) > 0 do %>
        <div class="flex flex-wrap gap-2">
          <%= for genre <- Enum.take(@genres, 4) do %>
            <span class="px-3 py-1 bg-white/10 border border-white/20 rounded-full text-sm font-medium text-white/90">
              <%= genre %>
            </span>
          <% end %>
        </div>
      <% end %>

      <!-- Director -->
      <%= if @show_director && @director do %>
        <div class="pt-2">
          <p class="text-sm text-white/60 uppercase tracking-wide font-semibold mb-1">
            Directed by
          </p>
          <p class="text-lg text-white font-medium">
            <%= @director %>
          </p>
        </div>
      <% end %>

      <!-- Overview (only in full variant) -->
      <%= if @variant == :full && @overview && @overview != "" do %>
        <div class="pt-2 max-w-3xl">
          <p class="text-white/90 text-base lg:text-lg leading-relaxed line-clamp-3">
            <%= @overview %>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp metadata_pill(assigns) do
    ~H"""
    <span class="px-3 py-1.5 bg-white/20 backdrop-blur-sm rounded-full text-sm font-medium text-white">
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  # CSS class helpers

  defp hero_container_classes(:full) do
    "absolute inset-0 h-96 md:h-[450px] lg:h-[500px]"
  end

  defp hero_container_classes(:compact) do
    "absolute inset-0 h-64 md:h-72 lg:h-80"
  end

  defp hero_content_wrapper_classes(:full) do
    "relative z-10 pt-16 pb-8 md:pt-24 lg:pt-32"
  end

  defp hero_content_wrapper_classes(:compact) do
    "relative z-10 pt-12 pb-6 md:pt-16"
  end

  defp fallback_container_classes(:full) do
    "bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 min-h-[400px]"
  end

  defp fallback_container_classes(:compact) do
    "bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 min-h-[280px]"
  end

  defp poster_classes(:full) do
    "w-48 md:w-56 lg:w-64 h-auto rounded-lg shadow-2xl ring-1 ring-white/10"
  end

  defp poster_classes(:compact) do
    "w-32 md:w-40 h-auto rounded-lg shadow-xl ring-1 ring-white/10"
  end

  defp title_classes(:full) do
    "text-3xl md:text-4xl lg:text-5xl font-bold tracking-tight leading-tight"
  end

  defp title_classes(:compact) do
    "text-2xl md:text-3xl font-bold tracking-tight leading-tight"
  end

  defp tagline_classes(:full) do
    "text-lg md:text-xl italic text-white/80"
  end

  defp tagline_classes(:compact) do
    "text-base italic text-white/80"
  end

  # Private functions

  defp assign_computed_data(socket) do
    rich_data = socket.assigns.rich_data

    socket
    |> assign(:title, MovieUtils.get_title(rich_data))
    |> assign(:tagline, get_tagline(rich_data))
    |> assign(:has_backdrop, has_backdrop?(rich_data))
    |> assign(:backdrop_url, MovieUtils.get_backdrop_url(rich_data))
    |> assign(:has_poster, has_poster?(rich_data))
    |> assign(:poster_url, MovieUtils.get_poster_url(rich_data))
    |> assign(:rating, get_rating(rich_data))
    |> assign(:runtime, get_runtime(rich_data))
    |> assign(:genres, MovieUtils.get_genres(rich_data))
    |> assign(:release_info, get_release_info(rich_data))
    |> assign(:director, MovieUtils.get_director(rich_data))
    |> assign(:overview, get_overview(rich_data))
  end

  defp has_backdrop?(rich_data) do
    backdrop_path =
      rich_data["backdrop_path"] ||
        get_in(rich_data, ["metadata", "backdrop_path"])

    is_binary(backdrop_path) && backdrop_path != ""
  end

  defp has_poster?(rich_data) do
    poster_path =
      rich_data["poster_path"] ||
        get_in(rich_data, ["metadata", "poster_path"])

    is_binary(poster_path) && poster_path != ""
  end

  defp get_tagline(rich_data) do
    rich_data["tagline"] ||
      get_in(rich_data, ["metadata", "tagline"])
  end

  defp get_rating(rich_data) do
    rich_data["vote_average"] ||
      get_in(rich_data, ["metadata", "vote_average"])
  end

  defp get_runtime(rich_data) do
    rich_data["runtime"] ||
      get_in(rich_data, ["metadata", "runtime"])
  end

  defp get_overview(rich_data) do
    rich_data["overview"] ||
      get_in(rich_data, ["metadata", "overview"]) ||
      rich_data["description"]
  end

  defp get_release_info(rich_data) do
    release_date =
      rich_data["release_date"] ||
        rich_data["first_air_date"] ||
        get_in(rich_data, ["metadata", "release_date"]) ||
        get_in(rich_data, ["metadata", "first_air_date"])

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
    :erlang.float_to_binary(rating * 1.0, decimals: 1)
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
