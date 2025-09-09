defmodule EventasaurusWeb.PublicMusicTrackPollComponent do
  @moduledoc """
  Public interface for music track polling.

  Shows existing music track options and allows users to add their own suggestions
  during the list_building phase, or vote during the voting phase.
  Supports both authenticated and anonymous voting.

  Uses frontend JavaScript integration with MusicBrainz API for search functionality.
  """

  use EventasaurusWeb, :live_component

  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusWeb.Utils.PollPhaseUtils
  
  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.VoterCountDisplay
  import Phoenix.HTML.SimplifiedHelpers.Truncate

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Use the provided poll or fall back to searching for a music track poll
    music_poll = assigns[:poll] || get_music_track_poll(assigns.event)
    music_options = if music_poll, do: Events.list_poll_options(music_poll), else: []

    # Load user votes for this poll
    user_votes =
      if assigns.current_user && music_poll do
        Events.list_user_poll_votes(music_poll, assigns.current_user)
      else
        []
      end

    # Preload suggested_by for all options using batch loading
    music_options =
      if music_poll && length(music_options) > 0 do
        # Check if any options need preloading
        needs_preload =
          Enum.any?(music_options, fn option ->
            match?(%Ecto.Association.NotLoaded{}, option.suggested_by)
          end)

        if needs_preload do
          # Get all option IDs and batch load them with suggested_by preloaded
          option_ids = Enum.map(music_options, & &1.id)
          preloaded_options = Events.list_poll_options_by_ids(option_ids, [:suggested_by])

          # Create a map for quick lookup
          preloaded_map = Map.new(preloaded_options, fn option -> {option.id, option} end)

          # Return options with preloaded data, filtering out any that were deleted
          music_options
          |> Enum.filter(fn option -> Map.has_key?(preloaded_map, option.id) end)
          |> Enum.map(fn option -> Map.get(preloaded_map, option.id, option) end)
        else
          # All options already have suggested_by loaded
          music_options
        end
      else
        music_options
      end

    # Get temp votes for this poll (for anonymous users)
    temp_votes = assigns[:temp_votes] || %{}

    # Load poll statistics for embedded display
    poll_stats =
      if music_poll do
        try do
          Events.get_poll_voting_stats(music_poll)
        rescue
          e ->
            Logger.error(Exception.format(:error, e, __STACKTRACE__))
            %{options: []}
        end
      else
        %{options: []}
      end

      {:ok,
       socket
       |> assign(assigns)
       |> assign(:music_poll, music_poll)
       |> assign(:music_options, music_options)
       |> assign(:user_votes, user_votes)
       |> assign(:temp_votes, temp_votes)
       |> assign(:poll_stats, poll_stats)
       |> assign(:showing_add_form, false)
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:adding_track, false)}
  end

  # ============================================================================
  # Template
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="public-music-poll">
      <%= if @music_poll do %>
        <div class="mb-6">
          <div class="mb-4">
            <div class="flex items-center justify-between">
              <div>
                <div class="flex items-center">
                  <h3 class="text-lg font-semibold text-gray-900"><%= poll_emoji("music_track") %> Music Track Suggestions</h3>
                  <.voter_count poll_stats={@poll_stats} poll_phase={@music_poll.phase} class="ml-4" />
                </div>
                <p class="text-sm text-gray-600 mt-1">
                  <%= PollPhaseUtils.get_phase_description(@music_poll.phase, "music_track") %>
                </p>
              </div>
            </div>
          </div>

          <!-- Voting Interface for music polls -->
          <%= if PollPhaseUtils.voting_allowed?(@music_poll.phase) do %>
            <div class="mb-6">
              <.live_component
                module={EventasaurusWeb.VotingInterfaceComponent}
                id={"voting-interface-music-#{@music_poll.id}"}
                poll={@music_poll}
                user={@current_user}
                user_votes={@user_votes}
                loading={false}
                temp_votes={@temp_votes}
                anonymous_mode={is_nil(@current_user)}
                show_header={false}
              />
            </div>

            <!-- Current Standings (for ranked choice voting) -->
            <%= if @music_poll.voting_system == "ranked" && EventasaurusApp.Events.Poll.show_current_standings?(@music_poll) do %>
              <div class="mb-6">
                <.live_component
                  module={EventasaurusWeb.Live.Components.RankedChoiceLeaderboardComponent}
                  id={"rcv-leaderboard-#{@music_poll.id}"}
                  poll={@music_poll}
                />
              </div>
            <% end %>
          <% else %>
            <!-- List Building Phase - Show Music Options Without Voting -->
            <%= if length(@music_options) > 0 do %>
              <div class="space-y-3">
                <%= for option <- @music_options do %>
                  <div class="bg-white border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                    <div class="flex">
                      <%= if option.image_url do %>
                        <img
                          src={option.image_url}
                          alt={"#{option.title} album art"}
                          class="w-16 h-24 object-cover rounded-lg mr-4 flex-shrink-0"
                          loading="lazy"
                        />
                      <% else %>
                        <div class="w-16 h-24 bg-gray-200 rounded-lg mr-4 flex-shrink-0 flex items-center justify-center">
                          <svg class="w-8 h-8 text-gray-400" fill="currentColor" viewBox="0 0 20 20">
                            <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v6.114A4.978 4.978 0 003 11c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V5.82l8-1.6v5.894A4.978 4.978 0 0011 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z"/>
                          </svg>
                        </div>
                      <% end %>

                      <div class="flex-1 min-w-0">
                        <h4 class="font-medium text-gray-900 mb-1"><%= option.title %></h4>

                        <%= if option.description do %>
                          <p class="text-sm text-gray-600 mb-2"><%= truncate(option.description, length: 80, separator: " ") %></p>
                        <% end %>

                        <!-- Show who suggested this track -->
                        <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@music_poll) and option.suggested_by do %>
                          <div class="flex items-center justify-between">
                            <p class="text-xs text-gray-500">
                              Suggested by <%= display_suggester_name(option.suggested_by) %>
                            </p>
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
                <svg class="w-12 h-12 mx-auto mb-4 text-gray-300" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v6.114A4.978 4.978 0 003 11c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V5.82l8-1.6v5.894A4.978 4.978 0 0011 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z"/>
                </svg>
                <% {title, subtitle} = PollPhaseUtils.get_empty_state_message("music_track") %>
                <p class="font-medium"><%= title %></p>
                <p class="text-sm"><%= subtitle %></p>
              </div>
            <% end %>
          <% end %>

          <!-- Add Music Track Button/Form -->
          <%= if PollPhaseUtils.suggestions_allowed?(@music_poll.phase) do %>
            <%= if @current_user do %>
              <%= if @showing_add_form do %>
                <!-- Inline Add Music Track Form -->
                <div class="mt-4 p-4 border-2 border-dashed border-gray-300 rounded-lg bg-gray-50">
                  <div class="mb-4">
                    <h4 class="text-md font-medium text-gray-900 mb-2">Add Music Track Suggestion</h4>
                    <p class="text-sm text-gray-600">Search for a track to add to the list</p>
                  </div>

                  <div class="mb-4">
                    <input
                      type="text"
                      placeholder="Search for a music track..."
                      value={@search_query}
                      phx-keyup="search_music_tracks"
                      phx-target={@myself}
                      phx-debounce="300"
                      class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                    />
                  </div>

                  <%= if length(@search_results) > 0 do %>
                    <div class="space-y-3 mb-4 max-h-64 overflow-y-auto">
                      <%= for track <- @search_results do %>
                        <div class="flex items-center p-4 border border-gray-200 rounded-lg hover:bg-blue-50 hover:border-blue-300 cursor-pointer transition-all duration-200 bg-white"
                             phx-click="add_track"
                             phx-value-track={track.id}
                             phx-target={@myself}>

                          <%= if track.image_url do %>
                            <img src={track.image_url} alt={track.title} class="w-12 h-16 object-cover rounded mr-4 flex-shrink-0" />
                          <% else %>
                            <div class="w-12 h-16 bg-gray-200 rounded mr-4 flex-shrink-0 flex items-center justify-center">
                              <span class="text-xs text-gray-500">No Image</span>
                            </div>
                          <% end %>

                          <div class="flex-1 min-w-0">
                            <h4 class="font-medium text-gray-900 truncate"><%= track.title %></h4>
                            <%= if track.metadata && track.metadata["duration_formatted"] do %>
                              <p class="text-sm text-gray-600"><%= track.metadata["duration_formatted"] %></p>
                            <% end %>
                            <%= if track.description && String.length(track.description) > 0 do %>
                              <p class="text-xs text-gray-500 mt-1 line-clamp-2"><%= track.description %></p>
                            <% end %>
                          </div>

                          <%= if @adding_track do %>
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
                <!-- Add Music Track Button -->
                <div class="mt-4">
                  <button
                    phx-click="show_add_form"
                    phx-target={@myself}
                    class="w-full flex items-center justify-center px-4 py-3 border border-gray-300 border-dashed rounded-lg text-sm font-medium text-gray-600 hover:text-gray-900 hover:border-gray-400 transition-colors"
                  >
                    <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    <%= PollPhaseUtils.get_add_button_text("music_track") %>
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
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <p>No music track poll found for this event.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    with {option_id_int, _} <- Integer.parse(option_id),
         option when not is_nil(option) <-
           Enum.find(socket.assigns.music_options, &(&1.id == option_id_int)),
         user when not is_nil(user) <- socket.assigns.current_user,
         true <- Events.can_delete_option_based_on_poll_settings?(option, user) do
      case Events.delete_poll_option(option) do
        {:ok, _} ->
          # Reload music options with proper preloading
          updated_music_options =
            Events.list_poll_options(socket.assigns.music_poll)
            |> Repo.preload(:suggested_by)

          # Notify parent to reload
          send(self(), {:poll_stats_updated, socket.assigns.music_poll.id, %{}})

          {:noreply,
           socket
           |> put_flash(:info, "Music track removed successfully.")
           |> assign(:music_options, updated_music_options)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to remove music track.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "You are not authorized to remove this music track.")}
    end
  end

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
  def handle_event("search_music_tracks", %{"value" => query}, socket) do
    Logger.debug("=== SEARCH MUSIC TRACKS EVENT ===")
    Logger.debug("Query: #{inspect(query)}")
    Logger.debug("Current user: #{inspect(socket.assigns.current_user.id)}")
    
    if socket.assigns.current_user do
      if String.length(query) >= 2 do
        Logger.debug("Query length >= 2, performing search...")
        # Use the centralized RichDataManager system (same as movie component)
        search_options = %{
          providers: [:spotify],
          limit: 5,
          content_type: :track
        }

        case RichDataManager.search(query, search_options) do
          {:ok, results_by_provider} ->
            # Extract track results from Spotify provider
            track_results =
              case Map.get(results_by_provider, :spotify) do
                {:ok, results} when is_list(results) -> results
                {:ok, result} -> [result]
                _ -> []
              end

            Logger.debug("=== SEARCH RESULTS ASSIGNED ===")
            Logger.debug("Track results count: #{length(track_results)}")
            Logger.debug("First result: #{inspect(List.first(track_results))}")
            
            {:noreply,
             socket
             |> assign(:search_query, query)
             |> assign(:search_results, track_results)}

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
  def handle_event("add_track", %{"track" => track_id}, socket) do
    if socket.assigns.adding_track do
      {:noreply, socket}
    else
      user = socket.assigns.current_user

      # Check if user is authenticated
      if is_nil(user) do
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to add music tracks.")
         |> assign(:adding_track, false)}
      else
        # Find the track in search results
        track_data =
          socket.assigns.search_results
          |> Enum.find(fn track ->
            # Simple string comparison since both track.id and track_id are strings
            track.id == track_id
          end)
        
        if track_data do
          # Set adding_track to true to prevent multiple requests
          socket = assign(socket, :adding_track, true)

          # Use the search result data directly to avoid Spotify API 403 issues
          # The search results already contain all the metadata we need
          option_params = %{
            "title" => track_data.title,
            "description" => track_data.description,
            "external_id" => to_string(track_data.id),
            "image_url" => track_data.image_url,
            "rich_data" => track_data.metadata || %{},
            "poll_id" => socket.assigns.music_poll.id,
            "suggested_by_id" => user.id
          }

          case Events.create_poll_option(option_params) do
            {:ok, _option} ->
              # Reload music options to show the new track immediately
              updated_music_options =
                Events.list_poll_options(socket.assigns.music_poll)
                |> Repo.preload(:suggested_by)

              # Notify the parent LiveView to reload polls for all users
              send(self(), {:poll_stats_updated, socket.assigns.music_poll.id, %{}})

              {:noreply,
               socket
               |> put_flash(:info, "Music track added successfully!")
               |> assign(:adding_track, false)
               |> assign(:showing_add_form, false)
               |> assign(:search_query, "")
               |> assign(:search_results, [])
               |> assign(:music_options, updated_music_options)}

            {:error, changeset} ->
              require Logger
              Logger.error("Failed to create poll option: #{inspect(changeset)}")

              {:noreply,
               socket
               |> put_flash(:error, "Failed to add music track. Please try again.")
               |> assign(:adding_track, false)}
          end
        else
          {:noreply,
           socket
           |> put_flash(:error, "Track not found in search results.")
           |> assign(:adding_track, false)}
        end
      end
    end
  end

  @impl true
  def handle_event("music_track_selected", %{"track" => track_data}, socket) do
    # This event is triggered by the frontend JavaScript when a user selects a track
    Logger.info("Music track selected: #{inspect(track_data)}")

    # Prepare option data
    option_data = %{
      title: track_data["title"],
      description: track_data["description"],
      external_id: track_data["id"],
      poll_type: "music_track",
      image_url: track_data["image_url"],
      rich_data: track_data["metadata"]
    }

    # Send to parent LiveView for processing
    send(self(), {:music_track_selected, track_data, option_data})

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_vote", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)
    current_user = socket.assigns.current_user
    
    if current_user do
      # Send vote event to parent
      send(self(), {:vote_toggled, option_id, current_user.id})
      {:noreply, socket}
    else
      # Handle temporary vote for anonymous users
      temp_votes = socket.assigns.temp_votes
      current_temp_vote = Map.get(temp_votes, option_id)
      
      updated_temp_votes = if current_temp_vote do
        Map.delete(temp_votes, option_id)
      else
        Map.put(temp_votes, option_id, true)
      end
      
      # Send temp vote to parent for persistence
      send(self(), {:temp_vote_changed, socket.assigns.music_poll.id, updated_temp_votes})
      
      {:noreply, assign(socket, :temp_votes, updated_temp_votes)}
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Helper function to get music track poll for an event
  defp get_music_track_poll(event) do
    Events.list_polls(event)
    |> Enum.find(&(&1.poll_type == "music_track"))
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

  # Deletion time remaining helpers (5-minute window)
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
end