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
  alias EventasaurusWeb.EmbeddedProgressBarComponent
  alias EventasaurusWeb.Utils.PollPhaseUtils

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.VoterCountDisplay
  import EventasaurusWeb.ClearVotesButton

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
    user_votes = if assigns.current_user && movie_poll do
      Events.list_user_poll_votes(movie_poll, assigns.current_user)
    else
      []
    end

    # Preload suggested_by for all options using batch loading
    movie_options = if movie_poll && length(movie_options) > 0 do
      # Check if any options need preloading
      needs_preload = Enum.any?(movie_options, fn option ->
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
    poll_stats = if movie_poll do
      try do
        Events.get_poll_voting_stats(movie_poll)
      rescue
        _ -> %{options: []}
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

  @impl true
  def handle_event("cast_binary_vote", %{"option-id" => option_id, "vote" => vote_value}, socket) do
    %{current_user: user, movie_poll: poll} = socket.assigns

    if user do
      # Authenticated user - handle normal vote
      # Validate option_id is a valid integer
      case Integer.parse(option_id) do
        {parsed_option_id, ""} ->
          # Get the PollOption struct first
          case Events.get_poll_option(parsed_option_id) do
            nil ->
              {:noreply, socket}

            poll_option ->
              case Events.cast_binary_vote(poll, poll_option, user, vote_value) do
                {:ok, _vote} ->
                  # Reload user votes to update the UI
                  user_votes = Events.list_user_poll_votes(poll, user)

                  # Send update to parent component (format: {:vote_cast, option_id, vote_value})
                  send(self(), {:vote_cast, parsed_option_id, vote_value})

                  {:noreply, assign(socket, :user_votes, user_votes)}

                {:error, _changeset} ->
                  {:noreply, socket}
              end
          end

        _ ->
          # Invalid option_id format, ignore the vote
          {:noreply, socket}
      end
    else
      # Anonymous user - handle temp vote
      case Integer.parse(option_id) do
        {parsed_option_id, ""} ->
          # Update temp votes for this option
          updated_temp_votes = Map.put(socket.assigns.temp_votes, parsed_option_id, vote_value)

          # Send update to parent LiveView
          send(self(), {:temp_votes_updated, poll.id, updated_temp_votes})

          {:noreply, assign(socket, :temp_votes, updated_temp_votes)}

        _ ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("clear_all_votes", _params, socket) do
    %{movie_poll: poll, current_user: user} = socket.assigns

    if user do
      # Clear all votes for authenticated user
      {:ok, _} = Events.clear_user_poll_votes(poll, user)
      
      # Reload user votes to update the UI
      user_votes = Events.list_user_poll_votes(poll, user)
      {:noreply, assign(socket, :user_votes, user_votes)}
    else
      # Clear temp votes for anonymous user
      send(self(), {:temp_votes_updated, poll.id, %{}})
      {:noreply, assign(socket, :temp_votes, %{})}
    end
  end

  def handle_event("save_votes", _params, socket) do
    %{movie_poll: poll, temp_votes: temp_votes} = socket.assigns

    if map_size(temp_votes) > 0 do
      # Send save request to parent LiveView
      send(self(), {:show_anonymous_voter_modal, poll.id, temp_votes})
    end

    {:noreply, socket}
  end

  def handle_event("show_add_form", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, assign(socket, :showing_add_form, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hide_add_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:showing_add_form, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])}
  end

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
    else
      {:noreply, socket}
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

  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    with {option_id_int, _} <- Integer.parse(option_id),
         option when not is_nil(option) <- Enum.find(socket.assigns.movie_options, &(&1.id == option_id_int)),
         true <- Events.can_delete_own_suggestion?(option, socket.assigns.current_user) do
      
      case Events.delete_poll_option(option) do
        {:ok, _} ->
          # Reload movie options with proper preloading
          updated_movie_options = Events.list_poll_options(socket.assigns.movie_poll)
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

  # Helper function to get user's vote for a specific option
  defp get_user_vote(option_id, user_votes) do
    case Enum.find(user_votes, fn vote -> vote.poll_option_id == option_id end) do
      %{vote_value: vote_value} -> vote_value
      _ -> nil
    end
  end

  # Helper function to generate button classes based on vote state
  defp binary_button_class(current_vote, button_vote) do
    base_classes = "inline-flex items-center px-3 py-1 text-xs font-medium rounded-full transition-colors"

    if current_vote == button_vote do
      case button_vote do
        "yes" -> "#{base_classes} bg-green-100 text-green-800 border border-green-300"
        "maybe" -> "#{base_classes} bg-yellow-100 text-yellow-800 border border-yellow-300"
        "no" -> "#{base_classes} bg-red-100 text-red-800 border border-red-300"
      end
    else
      case button_vote do
        "yes" -> "#{base_classes} bg-white text-green-700 border border-green-300 hover:bg-green-50"
        "maybe" -> "#{base_classes} bg-white text-yellow-700 border border-yellow-300 hover:bg-yellow-50"
        "no" -> "#{base_classes} bg-white text-red-700 border border-red-300 hover:bg-red-50"
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
              
              <%= if @movie_poll.phase in ["voting", "voting_with_suggestions", "voting_only"] do %>
                <.clear_votes_button
                  id={"clear-all-votes-movie-#{@movie_poll.id}"}
                  target={@myself}
                  has_votes={@current_user && length(@user_votes) > 0 || !@current_user && map_size(@temp_votes) > 0}
                  loading={false}
                  anonymous_mode={!@current_user}
                  variant="text"
                />
              <% end %>
            </div>
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
                        <div class="flex items-center justify-between mb-2">
                          <p class="text-xs text-gray-500">
                            Suggested by <%= option.suggested_by.name || option.suggested_by.email %>
                          </p>
                          <!-- Delete button for user's own suggestions -->
                          <%= if @current_user && Events.can_delete_own_suggestion?(option, @current_user) do %>
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

                      <!-- Embedded Progress Bar -->
                      <%= if @movie_poll.phase in ["voting", "voting_with_suggestions", "voting_only"] do %>
                        <div class="mt-2">
                          <.live_component
                            module={EmbeddedProgressBarComponent}
                            id={"progress-#{option.id}"}
                            poll_stats={@poll_stats}
                            option_id={option.id}
                            voting_system={@movie_poll.voting_system}
                            compact={true}
                            show_labels={false}
                            show_counts={true}
                            anonymous_mode={!@current_user}
                          />
                        </div>
                      <% end %>

                      <!-- Voting buttons for movie polls in voting phase -->
                      <%= if @movie_poll.phase in ["voting", "voting_with_suggestions", "voting_only"] do %>
                        <div class="flex space-x-2 mt-3">
                          <% current_vote = if @current_user, do: get_user_vote(option.id, @user_votes), else: Map.get(@temp_votes, option.id) %>
                          <% temp_vote_badge = if !@current_user && Map.get(@temp_votes, option.id), do: "📝", else: "" %>

                          <button
                            type="button"
                            phx-click="cast_binary_vote"
                            phx-value-option-id={option.id}
                            phx-value-vote="yes"
                            phx-target={@myself}
                            class={binary_button_class(current_vote, "yes")}
                          >
                            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                            </svg>
                            Yes <%= if current_vote == "yes" && !@current_user, do: temp_vote_badge %>
                          </button>

                          <button
                            type="button"
                            phx-click="cast_binary_vote"
                            phx-value-option-id={option.id}
                            phx-value-vote="maybe"
                            phx-target={@myself}
                            class={binary_button_class(current_vote, "maybe")}
                          >
                            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                            Maybe <%= if current_vote == "maybe" && !@current_user, do: temp_vote_badge %>
                          </button>

                          <button
                            type="button"
                            phx-click="cast_binary_vote"
                            phx-value-option-id={option.id}
                            phx-value-vote="no"
                            phx-target={@myself}
                            class={binary_button_class(current_vote, "no")}
                          >
                            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                            </svg>
                            No <%= if current_vote == "no" && !@current_user, do: temp_vote_badge %>
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
              <% {title, subtitle} = PollPhaseUtils.get_empty_state_message("movie") %>
              <p class="font-medium"><%= title %></p>
              <p class="text-sm"><%= subtitle %></p>
            </div>
          <% end %>

          <!-- Anonymous Voting Status and Save Button -->
          <%= if !@current_user && @movie_poll.phase in ["voting", "voting_with_suggestions", "voting_only"] && map_size(@temp_votes) > 0 do %>
            <div class="mt-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
              <div class="flex items-start">
                <div class="flex-shrink-0">
                  <svg class="h-5 w-5 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </div>
                <div class="ml-3 flex-1">
                  <p class="text-sm text-blue-700">
                    Your votes are temporarily stored. Save them to participate!
                  </p>
                </div>
              </div>
              <div class="mt-4 flex space-x-3">
                <button
                  type="button"
                  phx-click="save_votes"
                  phx-target={@myself}
                  class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4" />
                  </svg>
                  Save My Votes
                </button>
                <.clear_votes_button
                  id={"clear-temp-votes-movie-#{@movie_poll.id}"}
                  target={@myself}
                  has_votes={map_size(@temp_votes) > 0}
                  loading={false}
                  anonymous_mode={true}
                  variant="button"
                />
              </div>
            </div>
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
    max(0, 300 - elapsed_seconds)  # 300 seconds = 5 minutes
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

end
