defmodule EventasaurusWeb.Components.MovieDetailsCard do
  @moduledoc """
  Reusable component for displaying movie details consistently across pages.

  Used on:
  - Movie aggregation pages (showing all screenings for a movie)
  - Individual activity/showtime pages (showing specific screening details)
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

  def movie_details_card(assigns) do
    ~H"""
    <div class={"mb-8 p-6 bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg border border-blue-100 #{@class}"}>
      <div class="flex flex-col md:flex-row gap-6">
        <!-- Movie Poster -->
        <%= if poster_url = MovieImages.get_poster_url(@movie.id, @movie.poster_url) do %>
          <div class="flex-shrink-0">
            <img
              src={CDN.url(poster_url, width: 200, height: 300, fit: "cover", quality: 90)}
              alt={"#{@movie.title} poster"}
              class="w-32 h-48 object-cover rounded-lg shadow-lg"
              loading="lazy"
            />
          </div>
        <% end %>

        <!-- Movie Details -->
        <div class="flex-1 space-y-4">
          <div>
            <h2 class="text-2xl font-bold text-gray-900 mb-2">
              <%= @movie.title %>
              <%= if @movie.release_date do %>
                <span class="text-lg font-normal text-gray-600">
                  (<%= Calendar.strftime(@movie.release_date, "%Y") %>)
                </span>
              <% end %>
            </h2>
            <%= if @movie.original_title && @movie.original_title != @movie.title do %>
              <p class="text-sm text-gray-600 italic">
                <%= gettext("Original title:") %> <%= @movie.original_title %>
              </p>
            <% end %>
          </div>

          <!-- Movie Metadata -->
          <div class="flex flex-wrap gap-4 text-sm">
            <%= if @movie.runtime do %>
              <div class="flex items-center text-gray-700">
                <Heroicons.clock class="w-4 h-4 mr-1" />
                <span><%= format_movie_runtime(@movie.runtime) %></span>
              </div>
            <% end %>

            <%= if genres = get_in(@movie.metadata, ["genres"]) do %>
              <%= if is_list(genres) && length(genres) > 0 do %>
                <div class="flex flex-wrap gap-2">
                  <%= for genre <- Enum.take(genres, 3) do %>
                    <span class="px-2 py-1 bg-blue-100 text-blue-800 rounded-full text-xs font-medium">
                      <%= genre %>
                    </span>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>

          <!-- Movie Overview -->
          <%= if @movie.overview do %>
            <div>
              <p class="text-gray-700 leading-relaxed line-clamp-3">
                <%= @movie.overview %>
              </p>
            </div>
          <% end %>

          <!-- Links Row -->
          <div class="flex flex-wrap gap-3">
            <!-- See All Screenings Link -->
            <%= if @show_see_all_link && @aggregated_movie_url do %>
              <.link
                navigate={@aggregated_movie_url}
                class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition"
              >
                <Heroicons.film class="w-4 h-4 mr-2" />
                <%= gettext("See All Screenings") %>
              </.link>
            <% end %>

            <!-- Cinegraph Link -->
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

            <!-- TMDB Link -->
            <%= if @movie.tmdb_id do %>
              <a
                href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 transition"
              >
                <svg class="w-4 h-4 mr-2" viewBox="0 0 24 24" fill="#01b4e4">
                  <path d="M11.42 2c-4.05 0-7.34 3.28-7.34 7.33 0 4.05 3.29 7.33 7.34 7.33 4.05 0 7.33-3.28 7.33-7.33C18.75 5.28 15.47 2 11.42 2zM8.85 14.4l-1.34-2.8 2.59-5.4h1.93l-2.17 4.52L12.4 8.4h1.8l-2.59 5.4H9.68l2.17-4.52L9.31 11.6H7.51L8.85 14.4z"/>
                </svg>
                <%= gettext("View on TMDB") %>
              </a>
            <% end %>
          </div>

          <!-- TMDB Attribution -->
          <p class="text-xs text-gray-500 mt-2">
            <%= gettext("Movie data provided by") %>
            <a
              href="https://www.themoviedb.org/"
              target="_blank"
              rel="noopener noreferrer"
              class="text-blue-600 hover:text-blue-800 underline"
            >
              The Movie Database (TMDB)
            </a>.
            <%= gettext("This product uses the TMDB API but is not endorsed or certified by TMDB.") %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Helper function for formatting movie runtime
  defp format_movie_runtime(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)

    cond do
      hours > 0 && mins > 0 -> "#{hours}h #{mins}min"
      hours > 0 -> "#{hours}h"
      true -> "#{mins}min"
    end
  end

  defp format_movie_runtime(_), do: nil
end
