defmodule EventasaurusWeb.Components.MovieCards do
  @moduledoc """
  Shared movie card components for the movies index page.

  Provides card rendering for movies showing screening counts and city availability.
  """

  use Phoenix.Component
  use EventasaurusWeb, :verified_routes
  use Gettext, backend: EventasaurusWeb.Gettext

  import EventasaurusWeb.Components.CDNImage

  alias EventasaurusApp.Images.MovieImages

  @doc """
  Renders a movie card for the movies index grid.

  ## Assigns
  - `:movie` - The Movie struct
  - `:city_count` - Number of cities showing this movie
  - `:screening_count` - Total number of screenings
  - `:next_screening` - DateTime of the next screening (optional)
  """
  attr :movie, :map, required: true
  attr :city_count, :integer, required: true
  attr :screening_count, :integer, required: true
  attr :next_screening, :any, default: nil

  def movie_card(assigns) do
    ~H"""
    <.link navigate={~p"/movies/#{@movie.slug}"} class="block group">
      <div class="bg-white rounded-lg shadow-md hover:shadow-xl transition-all duration-200 overflow-hidden">
        <!-- Movie Poster -->
        <div class="aspect-[2/3] bg-gray-200 relative overflow-hidden">
          <%= if poster_url = MovieImages.get_poster_url(@movie.id, @movie.poster_url) do %>
            <.cdn_img
              src={poster_url}
              alt={@movie.title}
              width={300}
              height={450}
              fit="cover"
              quality={85}
              class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
              loading="lazy"
            />
          <% else %>
            <div class="w-full h-full flex items-center justify-center bg-gray-100">
              <Heroicons.film class="w-16 h-16 text-gray-300" />
            </div>
          <% end %>

          <!-- Rating Badge -->
      <%= if rating = get_vote_average(@movie) do %>
        <div class="absolute top-2 left-2 bg-yellow-500 text-white px-2 py-1 rounded-md text-xs font-bold flex items-center">
          <Heroicons.star solid class="w-3 h-3 mr-1" />
          <%= Float.round(rating, 1) %>
        </div>
      <% end %>

          <!-- City Count Badge -->
          <div class="absolute top-2 right-2 bg-blue-600 text-white px-2 py-1 rounded-md text-xs font-medium">
            <%= @city_count %> <%= ngettext("city", "cities", @city_count) %>
          </div>

          <!-- Screening Count Badge -->
          <div class="absolute bottom-2 right-2 bg-black/70 text-white px-2 py-1 rounded-md text-xs font-medium flex items-center">
            <Heroicons.ticket class="w-3 h-3 mr-1" />
            <%= @screening_count %> <%= ngettext("screening", "screenings", @screening_count) %>
          </div>
        </div>

        <!-- Movie Details -->
        <div class="p-3">
          <h3 class="font-semibold text-gray-900 line-clamp-2 text-sm group-hover:text-blue-600 transition-colors">
            <%= @movie.title %>
          </h3>

          <%= if @movie.release_date do %>
            <p class="text-xs text-gray-500 mt-1">
              <%= Calendar.strftime(@movie.release_date, "%Y") %>
              <%= if @movie.runtime do %>
                <span class="mx-1">&middot;</span>
                <%= format_runtime(@movie.runtime) %>
              <% end %>
            </p>
          <% end %>

          <%= if genres = get_genres(@movie) do %>
            <div class="mt-2 flex flex-wrap gap-1">
              <%= for genre <- Enum.take(genres, 2) do %>
                <span class="px-1.5 py-0.5 bg-gray-100 text-gray-600 rounded text-xs">
                  <%= genre %>
                </span>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a compact city card for the "Browse by City" section.
  """
  attr :city, :map, required: true
  attr :movie_count, :integer, required: true
  attr :screening_count, :integer, required: true

  def city_movie_card(assigns) do
    ~H"""
    <.link navigate={~p"/c/#{@city.slug}"} class="block group">
      <div class="bg-white rounded-lg shadow-sm hover:shadow-md transition-shadow p-4 border border-gray-100">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-full bg-blue-100 flex items-center justify-center flex-shrink-0">
            <Heroicons.building_office_2 class="w-5 h-5 text-blue-600" />
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="font-medium text-gray-900 truncate group-hover:text-blue-600 transition-colors">
              <%= @city.name %>
            </h3>
            <p class="text-sm text-gray-500">
              <%= @movie_count %> <%= ngettext("movie", "movies", @movie_count) %>
              <span class="mx-1">&middot;</span>
              <%= @screening_count %> <%= ngettext("screening", "screenings", @screening_count) %>
            </p>
          </div>
          <Heroicons.chevron_right class="w-5 h-5 text-gray-400 group-hover:text-blue-600 transition-colors" />
        </div>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a "Coming Soon" card for TMDB movies.
  Note: TMDB data structure uses string keys and different field names.
  """
  attr :movie, :map, required: true

  def coming_soon_card(assigns) do
    ~H"""
    <div class="block group relative flex-shrink-0 w-40 md:w-48 snap-start">
      <div class="bg-white rounded-lg shadow-md hover:shadow-xl transition-all duration-200 overflow-hidden h-full flex flex-col">
        <!-- Poster -->
        <div class="aspect-[2/3] bg-gray-200 relative overflow-hidden">
          <%= if @movie["poster_path"] do %>
            <img
              src={"https://image.tmdb.org/t/p/w342#{@movie["poster_path"]}"}
              alt={@movie["title"]}
              class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
              loading="lazy"
            />
          <% else %>
            <div class="w-full h-full flex items-center justify-center bg-gray-100">
              <Heroicons.film class="w-12 h-12 text-gray-300" />
            </div>
          <% end %>

          <!-- Release Date Badge -->
          <%= if @movie["release_date"] do %>
            <div class="absolute bottom-2 left-2 right-2 bg-black/70 backdrop-blur-sm text-white px-2 py-1 rounded text-xs font-medium text-center truncate">
              <%= format_tmdb_date(@movie["release_date"]) %>
            </div>
          <% end %>
        </div>

        <!-- Details -->
        <div class="p-3 bg-white flex-1">
          <h3 class="font-semibold text-gray-900 text-sm line-clamp-2 leading-tight group-hover:text-blue-600 transition-colors" title={@movie["title"]}>
            <%= @movie["title"] %>
          </h3>
          <%= if @movie["vote_average"] && @movie["vote_average"] > 0 do %>
             <div class="flex items-center mt-2 text-xs text-gray-500">
               <Heroicons.star solid class="w-3 h-3 text-yellow-400 mr-1" />
               <%= Float.round(@movie["vote_average"] / 1, 1) %>
             </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp format_runtime(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 && mins > 0 -> "#{hours}h #{mins}m"
      hours > 0 -> "#{hours}h"
      true -> "#{mins}m"
    end
  end

  defp format_runtime(_), do: nil

  defp get_genres(%{metadata: %{"genres" => genres}}) when is_list(genres), do: genres
  defp get_genres(_), do: nil

  defp get_vote_average(%{metadata: %{"vote_average" => avg}}) when is_number(avg) and avg > 0,
    do: avg / 1.0

  defp get_vote_average(_), do: nil

  defp format_tmdb_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> Calendar.strftime(date, "%b %d, %Y")
      _ -> date_str
    end
  end

  defp format_tmdb_date(_), do: ""
end
