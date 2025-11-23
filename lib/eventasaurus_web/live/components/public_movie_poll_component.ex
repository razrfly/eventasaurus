defmodule EventasaurusWeb.PublicMoviePollComponent do
  @moduledoc """
  Simple public interface for movie polling.

  Shows existing movie options and allows users to add their own suggestions
  during the list_building phase, or vote during the voting phase.
  Supports both authenticated and anonymous voting.
  """

  use EventasaurusWeb, :live_component

  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusWeb.Services.MovieDataService
  alias EventasaurusWeb.Utils.MovieUtils
  # alias EventasaurusWeb.EmbeddedProgressBarComponent - now handled by VotingInterfaceComponent
  alias EventasaurusWeb.Utils.PollPhaseUtils

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.VoterCountDisplay
  import Phoenix.HTML.SimplifiedHelpers.Truncate

  import EventasaurusWeb.PollOptionHelpers,
    only: [get_import_info: 1, format_import_attribution: 1]

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Use the provided poll or fall back to searching for a movie poll
    movie_poll = assigns[:poll] || get_movie_poll(assigns.event)
    movie_options = if movie_poll, do: Events.list_poll_options(movie_poll), else: []

    # Load user votes for this poll
    user_votes =
      if assigns.current_user && movie_poll do
        Events.list_user_poll_votes(movie_poll, assigns.current_user)
      else
        []
      end

    # Preload suggested_by for all options using batch loading
    movie_options =
      if movie_poll && length(movie_options) > 0 do
        # Check if any options need preloading
        needs_preload =
          Enum.any?(movie_options, fn option ->
            match?(%Ecto.Association.NotLoaded{}, option.suggested_by)
          end)

        if needs_preload do
          # Get all option IDs and batch load them with suggested_by preloaded
          option_ids = Enum.map(movie_options, & &1.id)
          preloaded_options = Events.list_poll_options_by_ids(option_ids, [:suggested_by])

          # Create a map for quick lookup
          preloaded_map = Map.new(preloaded_options, fn option -> {option.id, option} end)

          # Return options with preloaded data, filtering out any that were deleted
          movie_options
          |> Enum.filter(fn option -> Map.has_key?(preloaded_map, option.id) end)
          |> Enum.map(fn option -> Map.get(preloaded_map, option.id, option) end)
        else
          # All options already have suggested_by loaded
          movie_options
        end
      else
        movie_options
      end

    # Get temp votes for this poll (for anonymous users)
    temp_votes = assigns[:temp_votes] || %{}

    # Load poll statistics for embedded display
    poll_stats =
      if movie_poll do
        try do
          Events.get_poll_voting_stats(movie_poll)
        rescue
          e ->
            Logger.error(Exception.format(:error, e, __STACKTRACE__))
            %{options: []}
        end
      else
        %{options: []}
      end

    # Note: Real-time updates handled by parent LiveView

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:movie_poll, movie_poll)
     |> assign(:movie_options, movie_options)
     |> assign(:user_votes, user_votes)
     |> assign(:temp_votes, temp_votes)
     |> assign(:poll_stats, poll_stats)
     |> assign(:showing_add_form, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:adding_movie, false)}
  end

  # Note: Voting events are now handled by VotingInterfaceComponent
  # We only need to handle save_votes and clear_all_votes for anonymous users

  # Note: Voting events including save_votes and clear_all_votes are now handled by VotingInterfaceComponent

  @impl true
  def handle_event("show_add_form", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, assign(socket, :showing_add_form, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("hide_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_add_form, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

  @impl true
  def handle_event("search_movies", %{"value" => query}, socket) do
    if socket.assigns.current_user do
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
            movie_results =
              case Map.get(results_by_provider, :tmdb) do
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
    else
      {:noreply, socket}
    end
  end

  @impl true
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
        movie_data =
          socket.assigns.search_results
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
              option_params =
                MovieDataService.prepare_movie_option_data(
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
                  updated_movie_options =
                    Events.list_poll_options(socket.assigns.movie_poll)
                    |> Repo.preload(:suggested_by)

                  # Notify the parent LiveView to reload polls for all users
                  send(self(), {:poll_stats_updated, socket.assigns.movie_poll.id, %{}})

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
          {:noreply,
           socket
           |> put_flash(:error, "Movie not found in search results.")
           |> assign(:adding_movie, false)}
        end
      end
    end
  end

  @impl true
  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    with {option_id_int, _} <- Integer.parse(option_id),
         option when not is_nil(option) <-
           Enum.find(socket.assigns.movie_options, &(&1.id == option_id_int)),
         user when not is_nil(user) <- socket.assigns.current_user,
         true <- Events.can_delete_option_based_on_poll_settings?(option, user) do
      case Events.delete_poll_option(option) do
        {:ok, _} ->
          # Reload movie options with proper preloading
          updated_movie_options =
            Events.list_poll_options(socket.assigns.movie_poll)
            |> Repo.preload(:suggested_by)

          # Notify parent to reload
          send(self(), {:poll_stats_updated, socket.assigns.movie_poll.id, %{}})

          {:noreply,
           socket
           |> put_flash(:info, "Movie removed successfully.")
           |> assign(:movie_options, updated_movie_options)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove movie.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "You are not authorized to remove this movie.")}
    end
  end

  # Note: LiveComponents don't support handle_info callbacks
  # Real-time updates are handled by the parent LiveView which reloads the poll data

  # Helper function to get movie poll for an event
  defp get_movie_poll(event) do
    Events.list_polls(event)
    |> Enum.find(&(&1.poll_type == "movie"))
  end

  # Note: Voting helper functions have been removed as voting is now handled by VotingInterfaceComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-movie-poll">
      <%= if @movie_poll do %>
        <div class="mb-6">
          <div class="mb-4">
            <div class="flex items-center justify-between">
              <div>
                <div class="flex items-center">
                  <h3 class="text-lg font-semibold text-gray-900"><%= poll_emoji("movie") %> Movie Suggestions</h3>
                  <.voter_count poll_stats={@poll_stats} poll_phase={@movie_poll.phase} class="ml-4" />
                </div>
                <p class="text-sm text-gray-600 mt-1">
                  <%= PollPhaseUtils.get_phase_description(@movie_poll.phase, "movie") %>
                </p>
              </div>
            </div>
          </div>

          <!-- Voting Interface for movie polls -->
          <%= if PollPhaseUtils.voting_allowed?(@movie_poll.phase) do %>
            <div class="mb-6">
              <.live_component
                module={EventasaurusWeb.VotingInterfaceComponent}
                id={"voting-interface-movie-#{@movie_poll.id}"}
                poll={@movie_poll}
                user={@current_user}
                user_votes={@user_votes}
                loading={false}
                temp_votes={@temp_votes}
                anonymous_mode={is_nil(@current_user)}
                mode={:content}
              />
            </div>

            <!-- Current Standings (for ranked choice voting) -->
            <%= if @movie_poll.voting_system == "ranked" && EventasaurusApp.Events.Poll.show_current_standings?(@movie_poll) do %>
              <div class="mb-6">
                <.live_component
                  module={EventasaurusWeb.Live.Components.RankedChoiceLeaderboardComponent}
                  id={"rcv-leaderboard-#{@movie_poll.id}"}
                  poll={@movie_poll}
                />
              </div>
            <% end %>
          <% else %>
            <!-- List Building Phase - Show Movie Options Without Voting -->
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
                        <% movie_url = MovieUtils.get_primary_movie_url(option) %>
                        <%= if movie_url do %>
                          <h4 class="font-medium text-gray-900 mb-1">
                            <.link
                              href={movie_url}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="text-blue-600 hover:text-blue-800 hover:underline"
                            >
                              <%= option.title %>
                            </.link>
                          </h4>
                        <% else %>
                          <h4 class="font-medium text-gray-900 mb-1"><%= option.title %></h4>
                        <% end %>

                        <%= if option.description do %>
                          <p class="text-sm text-gray-600 mb-2"><%= truncate(option.description, length: 80, separator: " ") %></p>
                        <% end %>

                        <!-- Show who suggested this movie and import attribution -->
                        <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@movie_poll) do %>
                          <div class="flex items-center justify-between">
                            <div class="text-xs text-gray-500 space-y-1">
                              <%= if option.suggested_by do %>
                                <p>
                                  Suggested by <%= display_suggester_name(option.suggested_by) %>
                                </p>
                              <% end %>

                              <%= if import_info = get_import_info(option) do %>
                                <p class="flex items-center gap-1 text-blue-600">
                                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
                                  </svg>
                                  <%= format_import_attribution(import_info) %>
                                </p>
                              <% end %>
                            </div>

                            <!-- Delete button for user's own suggestions -->
                            <%= if @current_user && Events.can_delete_option_based_on_poll_settings?(option, @current_user) do %>
                              <div class="flex items-center space-x-2">
                                <button
                                  type="button"
                                  phx-click="delete_option"
                                  phx-value-option-id={option.id}
                                  phx-target={@myself}
                                  data-confirm="Are you sure you want to remove this option? This action cannot be undone."
                                  class="text-red-600 hover:text-red-900 text-xs font-medium"
                                >
                                  Remove my suggestion
                                </button>
                                <% time_remaining = get_deletion_time_remaining(option.inserted_at) %>
                                <%= if time_remaining > 0 do %>
                                  <span class="text-xs text-gray-500">
                                    (<%= format_deletion_time_remaining(time_remaining) %> left)
                                  </span>
                                <% end %>
                              </div>
                            <% end %>
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
                <% {title, subtitle} = PollPhaseUtils.get_empty_state_message("movie") %>
                <p class="font-medium"><%= title %></p>
                <p class="text-sm"><%= subtitle %></p>
              </div>
            <% end %>
          <% end %>

          <!-- Add Movie Button/Form -->
          <%= if PollPhaseUtils.suggestions_allowed?(@movie_poll.phase) do %>
            <%= if @current_user do %>
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

                          <%= if @adding_movie do %>
                            <div class="ml-4 flex-shrink-0">
                              <svg class="animate-spin h-5 w-5 text-blue-500" fill="none" viewBox="0 0 24 24">
                                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                              </svg>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="flex justify-end space-x-3">
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
                    <%= PollPhaseUtils.get_add_button_text("movie") %>
                  </button>
                </div>
              <% end %>
            <% else %>
              <!-- Show login prompt for anonymous users -->
              <div class="mt-4">
                <p class="text-sm text-gray-500 text-center py-4 bg-gray-50 rounded-lg">
                  Please <.link href="/login" class="text-blue-600 hover:underline">log in</.link> to suggest options.
                </p>
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

  # Helper functions for deletion time display
  defp get_deletion_time_remaining(inserted_at) when is_nil(inserted_at), do: 0

  defp get_deletion_time_remaining(inserted_at) do
    elapsed_seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second)
    # 300 seconds = 5 minutes
    max(0, 300 - elapsed_seconds)
  end

  defp format_deletion_time_remaining(seconds) when seconds <= 0, do: ""

  defp format_deletion_time_remaining(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 -> "#{minutes}:#{String.pad_leading(to_string(remaining_seconds), 2, "0")}"
      true -> "#{remaining_seconds}s"
    end
  end

  # Helper function to display suggester name with proper blank value handling
  defp display_suggester_name(suggested_by) when is_nil(suggested_by), do: "Anonymous"
  defp display_suggester_name(%Ecto.Association.NotLoaded{}), do: "Anonymous"

  defp display_suggester_name(suggested_by) do
    name = Map.get(suggested_by, :name)
    username = Map.get(suggested_by, :username)
    email = Map.get(suggested_by, :email)

    cond do
      is_binary(name) and String.trim(name) != "" -> String.trim(name)
      is_binary(username) and String.trim(username) != "" -> String.trim(username)
      is_binary(email) and String.trim(email) != "" -> String.trim(email)
      true -> "Anonymous"
    end
  end
end
