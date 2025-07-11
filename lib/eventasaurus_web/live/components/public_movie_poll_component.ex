defmodule EventasaurusWeb.PublicMoviePollComponent do
  @moduledoc """
  Simple public interface for movie polling.

  Shows existing movie options and allows users to add their own suggestions
  during the list_building phase, or vote during the voting phase.
  """

  use EventasaurusWeb, :live_component

  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusWeb.Services.MovieDataService
  alias EventasaurusWeb.Utils.MovieUtils

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
      |> Repo.preload(:suggested_by)

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

  def handle_event("search_movies", %{"value" => query}, socket) do
    if String.length(query) >= 2 do
      # Use the centralized RichDataManager system (same as backend)
      search_options = %{
        providers: [:tmdb],
        limit: 5,
        content_type: :movie
      }

      case RichDataManager.search(query, search_options) do
        {:ok, results_by_provider} ->
          # Extract movie results from TMDB provider
          movie_results = case Map.get(results_by_provider, :tmdb) do
            {:ok, results} when is_list(results) -> results
            {:ok, result} -> [result]
            _ -> []
          end

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

      # Check if user is authenticated
      if is_nil(user) do
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to add movies.")
         |> assign(:adding_movie, false)}
      else
                # Find the movie in search results
        # Handle both string and integer movie_id formats
        movie_data = socket.assigns.search_results
        |> Enum.find(fn movie ->
          # Compare both integer and string formats to handle type mismatches
          case Integer.parse(movie_id) do
            {id, _} -> movie.id == id
            :error -> to_string(movie.id) == movie_id
          end
        end)

        if movie_data do
          # Set adding_movie to true to prevent multiple requests
          socket = assign(socket, :adding_movie, true)

          # Use the centralized RichDataManager to get detailed movie data (same as backend)
          case RichDataManager.get_cached_details(:tmdb, movie_data.id, :movie) do
            {:ok, rich_movie_data} ->
              # Use the shared MovieDataService to prepare movie data consistently
              option_params = MovieDataService.prepare_movie_option_data(
                movie_data.id,
                rich_movie_data
              )
              |> Map.merge(%{
                "poll_id" => socket.assigns.movie_poll.id,
                "suggested_by_id" => user.id
              })

              case Events.create_poll_option(option_params) do
                {:ok, _option} ->
                  # Reload movie options to show the new movie immediately
                  updated_movie_options = Events.list_poll_options(socket.assigns.movie_poll)
                  |> Repo.preload(:suggested_by)

                  {:noreply,
                   socket
                   |> put_flash(:info, "Movie added successfully!")
                   |> assign(:adding_movie, false)
                   |> assign(:showing_add_form, false)
                   |> assign(:search_query, "")
                   |> assign(:search_results, [])
                   |> assign(:movie_options, updated_movie_options)}

                {:error, changeset} ->
                  require Logger
                  Logger.error("Failed to create poll option: #{inspect(changeset)}")
                  {:noreply,
                   socket
                   |> put_flash(:error, "Failed to add movie. Please try again.")
                   |> assign(:adding_movie, false)}
              end

            {:error, reason} ->
              require Logger
              Logger.error("Failed to fetch rich movie data: #{inspect(reason)}")
              {:noreply,
               socket
               |> put_flash(:error, "Failed to fetch movie details. Please try again.")
               |> assign(:adding_movie, false)}
          end
        else
          require Logger
          Logger.error("Movie not found in search results: #{movie_id}")
          {:noreply,
           socket
           |> put_flash(:error, "Movie not found. Please try again.")
           |> assign(:adding_movie, false)}
        end
      end
    end
  end



  # Helper function to parse enhanced description into details line and main description
  defp parse_enhanced_description(description) do
    description = description || ""
    case String.split(description, "\n\n", parts: 2) do
      [details_line, main_description] ->
        {details_line, main_description}
      [details_line] ->
        {details_line, nil}
      _ ->
        {nil, description}
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
                    <% image_url = MovieUtils.get_image_url(option) %>
                    <%= if image_url do %>
                      <img
                        src={image_url}
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

                      <!-- Movie Details (Year, Director, Genre) -->
                      <%= if option.description do %>
                        <% {details_line, main_description} = parse_enhanced_description(option.description) %>
                        <%= if details_line do %>
                          <p class="text-sm text-gray-600 font-medium mb-2"><%= details_line %></p>
                        <% end %>
                        <%= if main_description && String.length(main_description) > 0 do %>
                          <p class="text-sm text-gray-600 line-clamp-3 mb-2"><%= main_description %></p>
                        <% end %>
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

          <!-- Add Movie Button/Form -->
          <%= if @movie_poll.phase == "list_building" do %>
            <%= if @showing_add_form do %>
              <!-- Inline Add Movie Form -->
              <div class="mt-4 p-4 border-2 border-dashed border-gray-300 rounded-lg bg-gray-50">
                <div class="mb-4">
                  <h4 class="text-md font-medium text-gray-900 mb-2">Add Movie Suggestion</h4>
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
                  <div class="space-y-3 mb-4 max-h-64 overflow-y-auto">
                    <%= for movie <- @search_results do %>
                      <div class="flex items-center p-4 border border-gray-200 rounded-lg hover:bg-blue-50 hover:border-blue-300 cursor-pointer transition-all duration-200 bg-white"
                           phx-click="add_movie"
                           phx-value-movie={movie.id}
                           phx-target={@myself}>

                        <% image_url = MovieUtils.get_image_url(movie) %>
                        <%= if image_url do %>
                          <img src={image_url} alt={movie.title} class="w-12 h-16 object-cover rounded mr-4 flex-shrink-0" />
                        <% else %>
                          <div class="w-12 h-16 bg-gray-200 rounded mr-4 flex-shrink-0 flex items-center justify-center">
                            <span class="text-xs text-gray-500">No Image</span>
                          </div>
                        <% end %>

                        <div class="flex-1 min-w-0">
                          <h4 class="font-medium text-gray-900 truncate"><%= movie.title %></h4>
                          <%= if movie.metadata && movie.metadata["release_date"] do %>
                            <p class="text-sm text-gray-600"><%= String.slice(movie.metadata["release_date"], 0, 4) %></p>
                          <% end %>
                          <%= if movie.description && String.length(movie.description) > 0 do %>
                            <p class="text-xs text-gray-500 mt-1 line-clamp-2"><%= movie.description %></p>
                          <% end %>
                        </div>

                        <div class="ml-4 flex-shrink-0 text-blue-600 text-sm font-medium">
                          <%= if @adding_movie do %>
                            <div class="flex items-center">
                              <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                              </svg>
                              Adding...
                            </div>
                          <% else %>
                            <div class="flex items-center">
                              <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                              </svg>
                              Add
                            </div>
                          <% end %>
                        </div>
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
            <% else %>
              <!-- Add Movie Button -->
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
          <% end %>
        </div>

        <!-- Remove the old modal popup code -->
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>No movie poll found for this event.</p>
        </div>
      <% end %>
    </div>
    """
  end

end
