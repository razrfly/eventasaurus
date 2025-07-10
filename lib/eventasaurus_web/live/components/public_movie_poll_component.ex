defmodule EventasaurusWeb.PublicMoviePollComponent do
  @moduledoc """
  Simple public interface for movie polling.

  Shows existing movie options and allows users to add their own suggestions
  during the list_building phase, or vote during the voting phase.
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Events
  alias EventasaurusWeb.Services.TmdbRichDataProvider

  @impl true
  def update(assigns, socket) do
    event = assigns.event
    user = assigns.current_user

    # Find the movie poll for this event
    movie_poll = Events.list_polls(event)
    |> Enum.find(&(&1.poll_type == "movie"))

    if movie_poll do
      # Load movie options with suggested_by user
      movie_options = Events.list_poll_options(movie_poll)
      |> EventasaurusApp.Repo.preload(:suggested_by)

      {:ok,
       socket
       |> assign(:event, event)
       |> assign(:current_user, user)
       |> assign(:movie_poll, movie_poll)
       |> assign(:movie_options, movie_options)
       |> assign(:showing_add_form, false)
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:adding_movie, false)}
    else
      {:ok, assign(socket, :movie_poll, nil)}
    end
  end

  @impl true
  def handle_event("show_add_form", _params, socket) do
    {:noreply, assign(socket, :showing_add_form, true)}
  end

  def handle_event("hide_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_add_form, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  def handle_event("stop_propagation", _params, socket) do
    # This event handler does nothing - it's just to stop event propagation
    # from the modal content to prevent the modal from closing when clicking inside
    {:noreply, socket}
  end

  def handle_event("search_movies", %{"query" => query}, socket) do
            if String.length(query) >= 2 do
      # Search TMDB for movies using the rich data provider
      case TmdbRichDataProvider.search(query) do
        {:ok, results} ->
          # Filter for movies only and take first 5 results
          movie_results = results
          |> Enum.filter(&(&1.type == :movie))
          |> Enum.take(5)
          {:noreply,
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, movie_results)}
        {:error, _} ->
          {:noreply,
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, [])}
      end
    else
      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:search_results, [])}
    end
  end

            def handle_event("add_movie", %{"movie" => movie_id}, socket) do
    if socket.assigns.adding_movie do
      {:noreply, socket}
    else
      user = socket.assigns.current_user

      # Movie suggestions require a user to be logged in
      if !user do
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to suggest movies")
         |> assign(:search_query, "")
         |> assign(:search_results, [])}
      else
        # Find the movie in search results
        movie_data = socket.assigns.search_results
        |> Enum.find(&(to_string(&1.id) == movie_id))

        if movie_data do
          movie_poll = socket.assigns.movie_poll

          # Get comprehensive movie details using the rich data provider
          case TmdbRichDataProvider.get_cached_details(movie_data.id, :movie) do
            {:ok, rich_movie_data} ->
              # Extract poster path from the correct location in rich data structure
              poster_path = get_in(rich_movie_data, [:media, :images, :posters, Access.at(0), :file_path]) ||
                           get_in(rich_movie_data, [:metadata, "poster_path"]) ||
                           get_in(rich_movie_data, [:images, Access.at(0), :url])

              image_url = if poster_path do
                if is_binary(poster_path) && String.starts_with?(poster_path, "/") do
                  # It's a TMDB path, construct full URL
                  "https://image.tmdb.org/t/p/w500#{poster_path}"
                else
                  # It's already a full URL
                  poster_path
                end
              else
                nil
              end

              option_params = %{
                title: rich_movie_data.title,
                description: rich_movie_data.description,
                external_id: to_string(rich_movie_data.id),
                external_data: safe_json_encode(rich_movie_data), # Use safe JSON encoding
                image_url: image_url,
                poll_id: movie_poll.id,
                suggested_by_id: user.id
              }

              case Events.create_poll_option(option_params) do
                {:ok, _option} ->
                  # Reload options
                  movie_options = Events.list_poll_options(movie_poll)
                  |> EventasaurusApp.Repo.preload(:suggested_by)

                  {:noreply,
                   socket
                   |> assign(:movie_options, movie_options)
                   |> assign(:showing_add_form, false)
                   |> assign(:search_query, "")
                   |> assign(:search_results, [])
                   |> assign(:adding_movie, false)
                   |> put_flash(:info, "Movie added successfully!")}
                {:error, _changeset} ->
                  {:noreply,
                   socket
                   |> assign(:adding_movie, false)
                   |> put_flash(:error, "Failed to add movie. It may already exist.")}
              end

            {:error, _error} ->
              {:noreply,
               socket
               |> assign(:adding_movie, false)
               |> put_flash(:error, "Could not fetch movie details. Please try again.")}
          end
      else
        {:noreply,
         socket
         |> assign(:adding_movie, false)
         |> put_flash(:error, "Movie not found in search results.")}
        end
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-movie-poll">
      <%= if @movie_poll do %>
        <div class="mb-6">
          <div class="mb-4">
            <h3 class="text-lg font-semibold text-gray-900">🎬 Movie Suggestions</h3>
            <p class="text-sm text-gray-600">
              <%= if @movie_poll.phase == "list_building" do %>
                Help build the movie list! Add your suggestions below.
              <% else %>
                Vote on your favorite movies below.
              <% end %>
            </p>
          </div>

          <!-- Movie Options List -->
          <%= if length(@movie_options) > 0 do %>
            <div class="space-y-3">
              <%= for option <- @movie_options do %>
                <div class="bg-white border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                  <div class="flex">
                    <%= if option.image_url do %>
                      <img
                        src={option.image_url}
                        alt={"#{option.title} poster"}
                        class="w-16 h-24 object-cover rounded-lg mr-4 flex-shrink-0"
                        loading="lazy"
                      />
                    <% else %>
                      <div class="w-16 h-24 bg-gray-200 rounded-lg mr-4 flex-shrink-0 flex items-center justify-center">
                        <svg class="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2a1 1 0 011-1h4a1 1 0 011 1v2m0 0V3a1 1 0 011 1v4a1 1 0 01-1-1h-2m-6 0h8m-8 0V8a1 1 0 01-1-1V3a1 1 0 011-1h2"/>
                        </svg>
                      </div>
                    <% end %>

                    <div class="flex-1 min-w-0">
                      <h4 class="font-medium text-gray-900 mb-1"><%= option.title %></h4>
                      <%= if option.description do %>
                        <p class="text-sm text-gray-600 line-clamp-3 mb-2"><%= option.description %></p>
                      <% end %>

                      <!-- Show who suggested this movie -->
                      <%= if option.suggested_by do %>
                        <p class="text-xs text-gray-500 mb-2">
                          Suggested by <%= option.suggested_by.name || option.suggested_by.email %>
                        </p>
                      <% end %>

                      <%= if @movie_poll.phase == "voting" do %>
                        <!-- Voting buttons will go here -->
                        <div class="flex items-center space-x-2 mt-2">
                          <button class="px-3 py-1 text-xs bg-green-100 text-green-800 rounded-full hover:bg-green-200">
                            👍 Yes
                          </button>
                          <button class="px-3 py-1 text-xs bg-red-100 text-red-800 rounded-full hover:bg-red-200">
                            👎 No
                          </button>
                        </div>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="text-center py-8 text-gray-500">
              <svg class="w-12 h-12 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M7 4V2a1 1 0 011-1h4a1 1 0 011 1v2m0 0V3a1 1 0 011 1v4a1 1 0 01-1-1h-2m-6 0h8m-8 0V8a1 1 0 01-1-1V3a1 1 0 011-1h2"/>
              </svg>
              <p class="font-medium">No movies suggested yet</p>
              <p class="text-sm">Be the first to add a movie suggestion!</p>
            </div>
          <% end %>

          <!-- Add Movie Button at bottom -->
          <%= if @movie_poll.phase == "list_building" do %>
            <div class="mt-4">
              <button
                phx-click="show_add_form"
                phx-target={@myself}
                class="w-full flex items-center justify-center px-4 py-3 border border-gray-300 border-dashed rounded-lg text-sm font-medium text-gray-600 hover:text-gray-900 hover:border-gray-400 transition-colors"
              >
                <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
                Add Movie Suggestion
              </button>
            </div>
          <% end %>
        </div>

        <!-- Add Movie Form -->
        <%= if @showing_add_form do %>
          <div class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50" phx-click="hide_add_form" phx-target={@myself}>
            <div class="relative top-20 mx-auto p-5 border w-11/12 md:w-1/2 lg:w-1/3 shadow-lg rounded-md bg-white" phx-click="stop_propagation" phx-target={@myself}>
              <div class="mb-4">
                <h3 class="text-lg font-medium text-gray-900">Add Movie Suggestion</h3>
                <p class="text-sm text-gray-600">Search for a movie to add to the list</p>
              </div>

              <div class="mb-4">
                <input
                  type="text"
                  placeholder="Search for a movie..."
                  value={@search_query}
                  phx-keyup="search_movies"
                  phx-target={@myself}
                  phx-debounce="300"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <%= if length(@search_results) > 0 do %>
                <div class="space-y-2 mb-4 max-h-64 overflow-y-auto">
                  <%= for movie <- @search_results do %>
                                      <div class="flex items-center p-3 border border-gray-200 rounded-lg hover:bg-gray-50 cursor-pointer"
                       phx-click="add_movie"
                       phx-value-movie={movie.id}
                       phx-target={@myself}>
                                                              <%= if movie.images && length(movie.images) > 0 do %>
                      <% image = List.first(movie.images) %>
                      <%= if image && Map.has_key?(image, :url) do %>
                        <img
                          src={image.url}
                          alt={movie.title}
                          class="w-12 h-18 object-cover rounded mr-3"
                        />
                      <% else %>
                        <div class="w-12 h-18 bg-gray-200 rounded mr-3 flex items-center justify-center">
                          <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2a1 1 0 011-1h4a1 1 0 011 1v2m0 0V3a1 1 0 011 1v4a1 1 0 01-1-1h-2m-6 0h8m-8 0V8a1 1 0 01-1-1V3a1 1 0 011-1h2"/>
                          </svg>
                        </div>
                      <% end %>
                    <% else %>
                      <div class="w-12 h-18 bg-gray-200 rounded mr-3 flex items-center justify-center">
                        <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4V2a1 1 0 011-1h4a1 1 0 011 1v2m0 0V3a1 1 0 011 1v4a1 1 0 01-1-1h-2m-6 0h8m-8 0V8a1 1 0 01-1-1V3a1 1 0 011-1h2"/>
                        </svg>
                      </div>
                    <% end %>

                    <div class="flex-1 min-w-0">
                      <h4 class="font-medium text-gray-900"><%= movie.title %></h4>
                      <%= if movie.release_date do %>
                        <p class="text-sm text-gray-600"><%= String.slice(movie.release_date, 0, 4) %></p>
                      <% end %>
                      <%= if movie.overview && String.length(movie.overview) > 0 do %>
                        <p class="text-xs text-gray-500 mt-1 line-clamp-2"><%= movie.overview %></p>
                      <% end %>
                    </div>

                      <button class="ml-2 px-3 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700">
                        Add
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="flex justify-end space-x-2">
                <button
                  phx-click="hide_add_form"
                  phx-target={@myself}
                  class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        <% end %>
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>No movie poll found for this event.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper function to safely encode JSON data
  defp safe_json_encode(data) do
    case Jason.encode(data) do
      {:ok, json} -> json
      {:error, _} -> "{}"
    end
  end
end
