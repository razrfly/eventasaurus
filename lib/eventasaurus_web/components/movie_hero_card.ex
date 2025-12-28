defmodule EventasaurusWeb.Components.MovieHeroCard do
  @moduledoc """
  Cinematic hero card for movie screenings on activity pages.

  Displays movie information in a hero-style layout with backdrop, poster,
  metadata, and action links. Designed to work with the Movie struct directly.

  ## Features

  - Cinematic backdrop with gradient overlay
  - Movie poster alongside metadata
  - Runtime, genres, and ratings display
  - Links to aggregated screenings, Cinegraph, and TMDB
  - TMDB attribution
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN
  alias Eventasaurus.Integrations.Cinegraph
  alias EventasaurusApp.Images.MovieImages

  attr :movie, :map, required: true, doc: "Movie struct with title, poster_url, metadata, etc."

  attr :show_see_all_link, :boolean,
    default: false,
    doc: "Whether to show 'See All Screenings' link"

  attr :aggregated_movie_url, :string, default: nil, doc: "URL to movie aggregation page"
  attr :class, :string, default: "", doc: "Additional CSS classes for the container"

  def movie_hero_card(assigns) do
    ~H"""
    <div class={"relative rounded-xl overflow-hidden mb-8 #{@class}"}>
      <!-- Backdrop Image with Gradient Overlay -->
      <%= if backdrop_url = MovieImages.get_backdrop_url(@movie.id, @movie.backdrop_url) do %>
        <div class="absolute inset-0">
          <img
            src={CDN.url(backdrop_url, width: 1200, quality: 85)}
            alt=""
            class="w-full h-full object-cover"
            aria-hidden="true"
          />
          <div class="absolute inset-0 bg-gradient-to-r from-gray-900 via-gray-900/80 to-gray-900/40" />
        </div>
      <% else %>
        <div class="absolute inset-0 bg-gradient-to-r from-indigo-900 via-indigo-800 to-indigo-700" />
      <% end %>

      <!-- Content -->
      <div class="relative p-6 md:p-8 flex flex-col md:flex-row gap-6">
        <!-- Movie Poster -->
        <%= if poster_url = MovieImages.get_poster_url(@movie.id, @movie.poster_url) do %>
          <div class="flex-shrink-0 self-start">
            <img
              src={CDN.url(poster_url, width: 200, height: 300, fit: "cover", quality: 90)}
              alt={"#{@movie.title} poster"}
              class="w-32 md:w-40 h-48 md:h-60 object-cover rounded-lg shadow-2xl"
              loading="lazy"
            />
          </div>
        <% end %>

        <!-- Movie Details -->
        <div class="flex-1 text-white space-y-4">
          <!-- Title -->
          <div>
            <h2 class="text-2xl md:text-3xl font-bold tracking-tight">
              <%= @movie.title %>
              <%= if @movie.release_date do %>
                <span class="font-normal text-white/70">
                  (<%= Calendar.strftime(@movie.release_date, "%Y") %>)
                </span>
              <% end %>
            </h2>
            <%= if @movie.original_title && @movie.original_title != @movie.title do %>
              <p class="text-sm text-white/70 italic mt-1">
                <%= gettext("Original title:") %> <%= @movie.original_title %>
              </p>
            <% end %>
          </div>

          <!-- Metadata Row -->
          <div class="flex flex-wrap items-center gap-4 text-sm">
            <%= if rating = get_in(@movie.metadata, ["vote_average"]) do %>
              <div class="flex items-center gap-1">
                <Heroicons.star solid class="w-4 h-4 text-yellow-400" />
                <span class="font-medium"><%= format_rating(rating) %></span>
              </div>
            <% end %>

            <%= if @movie.runtime do %>
              <span class="text-white/80"><%= format_runtime(@movie.runtime) %></span>
            <% end %>

            <%= if genres = get_in(@movie.metadata, ["genres"]) do %>
              <%= if is_list(genres) && length(genres) > 0 do %>
                <div class="flex flex-wrap gap-2">
                  <%= for genre <- Enum.take(genres, 3) do %>
                    <span class="px-2 py-1 bg-white/20 rounded-full text-xs font-medium">
                      <%= genre %>
                    </span>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>

          <!-- Overview -->
          <%= if @movie.overview do %>
            <p class="text-white/90 leading-relaxed line-clamp-3 max-w-3xl">
              <%= @movie.overview %>
            </p>
          <% end %>

          <!-- Action Links -->
          <div class="flex flex-wrap gap-3 pt-2">
            <%= if @show_see_all_link && @aggregated_movie_url do %>
              <.link
                navigate={@aggregated_movie_url}
                class="inline-flex items-center px-4 py-2 bg-white text-gray-900 text-sm font-medium rounded-lg hover:bg-gray-100 transition shadow-md"
              >
                <Heroicons.film class="w-4 h-4 mr-2" />
                <%= gettext("See All Screenings") %>
              </.link>
            <% end %>

            <%= if Cinegraph.linkable?(@movie) do %>
              <a
                href={Cinegraph.movie_url(@movie)}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-4 py-2 bg-indigo-600 text-white text-sm font-medium rounded-lg hover:bg-indigo-700 transition"
                title={gettext("View detailed movie information on Cinegraph")}
              >
                <Heroicons.film class="w-4 h-4 mr-2" />
                <%= gettext("View on Cinegraph") %>
              </a>
            <% end %>

            <%= if @movie.tmdb_id do %>
              <a
                href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-4 py-2 bg-white/10 border border-white/30 text-white text-sm font-medium rounded-lg hover:bg-white/20 transition"
              >
                <svg class="w-4 h-4 mr-2" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M11.42 2c-4.05 0-7.34 3.28-7.34 7.33 0 4.05 3.29 7.33 7.34 7.33 4.05 0 7.33-3.28 7.33-7.33C18.75 5.28 15.47 2 11.42 2zM8.85 14.4l-1.34-2.8 2.59-5.4h1.93l-2.17 4.52L12.4 8.4h1.8l-2.59 5.4H9.68l2.17-4.52L9.31 11.6H7.51L8.85 14.4z"/>
                </svg>
                <%= gettext("View on TMDB") %>
              </a>
            <% end %>
          </div>

          <!-- TMDB Attribution -->
          <p class="text-xs text-white/50 pt-2">
            <%= gettext("Movie data provided by") %>
            <a
              href="https://www.themoviedb.org/"
              target="_blank"
              rel="noopener noreferrer"
              class="text-white/70 hover:text-white underline"
            >
              TMDB
            </a>.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating / 1, decimals: 1)
  end

  defp format_rating(_), do: nil

  defp format_runtime(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 && mins > 0 -> "#{hours}h #{mins}min"
      hours > 0 -> "#{hours}h"
      true -> "#{mins}min"
    end
  end

  defp format_runtime(_), do: nil
end
