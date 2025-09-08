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
  alias EventasaurusWeb.Services.RichDataManager
  import EventasaurusWeb.PollView, only: [poll_emoji: 1]

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
     |> assign(:search_loading, false)
     |> assign(:selected_track, nil)}
  end

  # ============================================================================
  # Template
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="music-track-poll-container">
      <%= if @music_poll do %>
        <div class="mb-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-2 flex items-center gap-2">
            <span class="text-blue-600"><%= poll_emoji(@music_poll) %></span>
            <%= @music_poll.title %>
          </h3>
          <%= if @music_poll.description do %>
            <p class="text-gray-600 text-sm mb-4"><%= @music_poll.description %></p>
          <% end %>

          <!-- Phase-specific content -->
          <%= case @music_poll.phase do %>
            <% "list_building" -> %>
              <%= render_list_building_phase(assigns) %>
            <% phase when phase in ["voting", "voting_with_suggestions", "voting_only"] -> %>
              <%= render_voting_phase(assigns) %>
            <% "closed" -> %>
              <%= render_results_phase(assigns) %>
            <% _ -> %>
              <div class="text-center py-4 text-gray-500">
                <p>Poll details will be available soon.</p>
              </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-8 text-gray-500">
          <div class="text-4xl mb-3">🎵</div>
          <p class="text-lg">No music track poll found</p>
          <p class="text-sm">A music poll may be added to this event later.</p>
        </div>
      <% end %>
    </div>
    """
  end

  # ============================================================================
  # Phase Rendering Functions
  # ============================================================================

  defp render_list_building_phase(assigns) do
    ~H"""
    <div>
      <!-- Search Interface -->
      <div class="mb-6">
        <h4 class="text-sm font-medium text-gray-900 mb-3">Add Music Tracks</h4>
        
        <div class="bg-blue-50 rounded-lg p-4 mb-4">
          <div class="flex items-start gap-3">
            <div class="text-blue-600 mt-0.5">
              <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                <path d="M9 12a1 1 0 102 0V6.414l1.293 1.293a1 1 0 001.414-1.414l-3-3a1 1 0 00-1.414 0l-3 3a1 1 0 101.414 1.414L9 6.414V12z"/>
              </svg>
            </div>
            <div class="flex-1">
              <p class="text-sm text-blue-800">
                <strong>Search for music tracks</strong> by typing in the box below. 
                Results come from MusicBrainz, a comprehensive music database.
              </p>
            </div>
          </div>
        </div>

        <div class="relative">
          <input
            type="text"
            name="search_query"
            value={@search_query}
            placeholder="Search for music tracks (e.g., 'Don't Stop Me Now')"
            class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            phx-keyup="search_music_tracks"
            phx-target={@myself}
            phx-debounce="300"
            autocomplete="off"
          />
          <div class="absolute right-3 top-3">
            <%= if @search_loading do %>
              <svg class="animate-spin h-5 w-5 text-blue-500" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Search Results Container -->
      <%= if length(@search_results) > 0 do %>
        <div class="mb-6">
          <h4 class="text-sm font-medium text-gray-900 mb-3">Search Results</h4>
          <div class="space-y-2">
            <%= for track <- @search_results do %>
              <div class="border rounded-lg p-3 bg-white hover:bg-gray-50 cursor-pointer transition-colors" 
                   phx-click="add_track" 
                   phx-value-track-id={track.id} 
                   phx-target={@myself}>
                <div class="flex items-start gap-3">
                  <div class="text-blue-600 mt-0.5">
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v6.114A4.978 4.978 0 003 11c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V5.82l8-1.6v5.894A4.978 4.978 0 0011 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z"/>
                    </svg>
                  </div>
                  <div class="flex-1">
                    <h5 class="font-medium text-gray-900"><%= track.title %></h5>
                    <p class="text-sm text-gray-600"><%= track.description %></p>
                  </div>
                  <div class="text-blue-600">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
                    </svg>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Current Options -->
      <%= render_current_options(assigns) %>
    </div>
    """
  end

  defp render_voting_phase(assigns) do
    ~H"""
    <div>
      <%= if @music_poll.phase == "voting_with_suggestions" do %>
        <!-- Show search interface for suggestions -->
        <div class="mb-6 p-4 bg-blue-50 rounded-lg">
          <h4 class="text-sm font-medium text-blue-900 mb-2">Suggest Additional Tracks</h4>
          
          <div class="relative">
            <input
              type="text"
              name="search_query"
              value={@search_query}
              placeholder="Search for music tracks to suggest"
              class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              phx-keyup="search_music_tracks"
              phx-target={@myself}
              phx-debounce="300"
              autocomplete="off"
            />
          </div>

          <!-- Search Results for Suggestions -->
          <%= if length(@search_results) > 0 do %>
            <div class="mt-4">
              <div class="space-y-2">
                <%= for track <- @search_results do %>
                  <div class="border rounded-lg p-3 bg-white hover:bg-gray-50 cursor-pointer transition-colors" 
                       phx-click="add_track" 
                       phx-value-track-id={track.id} 
                       phx-target={@myself}>
                    <div class="flex items-start gap-3">
                      <div class="text-blue-600 mt-0.5">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                          <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v6.114A4.978 4.978 0 003 11c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V5.82l8-1.6v5.894A4.978 4.978 0 0011 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z"/>
                        </svg>
                      </div>
                      <div class="flex-1">
                        <h5 class="font-medium text-gray-900"><%= track.title %></h5>
                        <p class="text-sm text-gray-600"><%= track.description %></p>
                      </div>
                      <div class="text-blue-600">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
                        </svg>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Voting Options -->
      <%= render_voting_options(assigns) %>
    </div>
    """
  end

  defp render_results_phase(assigns) do
    ~H"""
    <div>
      <div class="mb-4">
        <div class="flex items-center justify-between">
          <h4 class="text-lg font-medium text-gray-900">Poll Results</h4>
          <div class="text-sm text-gray-600">
            <%= length(@music_options) %> tracks • <%= get_total_votes(@music_options) %> total votes
          </div>
        </div>
      </div>
      
      <%= render_results_options(assigns) %>
    </div>
    """
  end

  # Current options display for list building phase
  defp render_current_options(assigns) do
    ~H"""
    <%= if length(@music_options) > 0 do %>
      <div>
        <h4 class="text-sm font-medium text-gray-900 mb-3">
          Current Tracks (<%= length(@music_options) %>)
        </h4>
        <div class="space-y-3">
          <%= for option <- @music_options do %>
            <div class="border rounded-lg p-4 bg-white">
              <%= render_track_option_content(assigns, option) %>
            </div>
          <% end %>
        </div>
      </div>
    <% else %>
      <div class="text-center py-8 text-gray-500">
        <div class="text-4xl mb-3">🎵</div>
        <p>No music tracks have been added yet.</p>
        <p class="text-sm">Search above to add the first track.</p>
      </div>
    <% end %>
    """
  end

  # Voting options with vote buttons
  defp render_voting_options(assigns) do
    ~H"""
    <%= if length(@music_options) > 0 do %>
      <div class="space-y-3">
        <%= for option <- @music_options do %>
          <div class="border rounded-lg p-4 bg-white hover:bg-gray-50 transition-colors">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <%= render_track_option_content(assigns, option) %>
              </div>
              <div class="ml-4 flex-shrink-0">
                <%= render_vote_button(assigns, option) %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      <div class="text-center py-8 text-gray-500">
        <div class="text-4xl mb-3">🎵</div>
        <p>No tracks to vote on yet.</p>
      </div>
    <% end %>
    """
  end

  # Results display with vote counts and percentages
  defp render_results_options(assigns) do
    total_votes = get_total_votes(assigns.music_options)
    assigns = assign(assigns, :total_votes, total_votes)

    ~H"""
    <div class="space-y-3">
      <%= for {option, index} <- Enum.with_index(@music_options) do %>
        <div class="border rounded-lg p-4 bg-white">
          <div class="flex items-start justify-between mb-3">
            <div class="flex-1">
              <%= render_track_option_content(assigns, option) %>
            </div>
            <div class="ml-4 text-right">
              <div class="text-lg font-semibold text-gray-900"><%= option.vote_count || 0 %></div>
              <div class="text-sm text-gray-600">
                <%= if @total_votes > 0, do: "#{round((option.vote_count || 0) / @total_votes * 100)}%", else: "0%" %>
              </div>
            </div>
          </div>
          
          <!-- Vote bar -->
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div
              class="h-2 rounded-full transition-all duration-300"
              style={"width: #{if @total_votes > 0, do: (option.vote_count || 0) / @total_votes * 100, else: 0}%; background-color: #{get_option_color(index)}"}
            >
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Music track option content rendering
  defp render_track_option_content(assigns, option) do
    assigns = assign(assigns, :option, option)

    ~H"""
    <div>
      <div class="flex items-start gap-3">
        <div class="flex-shrink-0">
          <div class="text-blue-600 mt-0.5">
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v6.114A4.978 4.978 0 003 11c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V5.82l8-1.6v5.894A4.978 4.978 0 0011 10c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z"/>
            </svg>
          </div>
        </div>
        <div class="flex-1 min-w-0">
          <h5 class="font-medium text-gray-900 mb-1"><%= @option.title %></h5>
          
          <%= if @option.description do %>
            <p class="text-sm text-gray-600 mb-2"><%= @option.description %></p>
          <% end %>

          <%= if @option.rich_data do %>
            <%= render_rich_track_data(assigns, @option.rich_data) %>
          <% end %>

          <%= if @option.suggested_by do %>
            <div class="flex items-center gap-1 mt-2">
              <span class="text-xs text-gray-500">Suggested by</span>
              <span class="text-xs font-medium text-gray-700"><%= @option.suggested_by.name %></span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Rich music data display
  defp render_rich_track_data(assigns, rich_data) do
    assigns = assign(assigns, :rich_data, rich_data)

    ~H"""
    <div class="space-y-1 text-sm">
      <%= if @rich_data["artist_credit"] do %>
        <div class="text-gray-700">
          <span class="font-medium">Artist:</span>
          <%= extract_artist_names(@rich_data["artist_credit"]) %>
        </div>
      <% end %>

      <%= if @rich_data["releases"] && length(@rich_data["releases"]) > 0 do %>
        <div class="text-gray-600">
          <span class="font-medium">Album:</span>
          <%= List.first(@rich_data["releases"])["title"] %>
        </div>
      <% end %>

      <%= if @rich_data["duration_formatted"] do %>
        <div class="text-gray-600">
          <span class="font-medium">Duration:</span>
          <%= @rich_data["duration_formatted"] %>
        </div>
      <% end %>

      <%= if @rich_data["disambiguation"] do %>
        <div class="text-xs text-gray-500 italic"><%= @rich_data["disambiguation"] %></div>
      <% end %>
    </div>
    """
  end

  # Vote button rendering
  defp render_vote_button(assigns, option) do
    current_user_vote = get_current_user_vote(option, assigns.current_user)
    temp_vote = Map.get(assigns.temp_votes, option.id)
    
    assigns = 
      assigns
      |> assign(:option, option)
      |> assign(:current_user_vote, current_user_vote)
      |> assign(:temp_vote, temp_vote)

    ~H"""
    <div class="flex flex-col items-center gap-2">
      <button
        type="button"
        phx-click="toggle_vote"
        phx-value-option-id={@option.id}
        phx-target={@myself}
        class={[
          "px-4 py-2 rounded-md text-sm font-medium transition-colors",
          (@current_user_vote || @temp_vote) && "bg-blue-600 text-white hover:bg-blue-700" || 
          "bg-gray-200 text-gray-700 hover:bg-gray-300"
        ]}
      >
        <%= if @current_user_vote || @temp_vote do %>
          <svg class="w-4 h-4 inline mr-1" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" clip-rule="evenodd"/>
          </svg>
          Voted
        <% else %>
          <svg class="w-4 h-4 inline mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"/>
          </svg>
          Vote
        <% end %>
      </button>
      
      <div class="text-xs text-gray-500 text-center">
        <%= (@option.vote_count || 0) + (if @temp_vote && not @current_user_vote, do: 1, else: 0) %> votes
      </div>
    </div>
    """
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true  
  def handle_event("search_music_tracks", params, socket) do
    Logger.info("PublicMusicTrackPollComponent.handle_event search_music_tracks called with params: #{inspect(params)}")
    
    query = case params do
      %{"value" => q} -> String.trim(q)
      %{"search_query" => q} -> String.trim(q)
      _ -> 
        Logger.error("Unexpected search_music_tracks params: #{inspect(params)}")
        ""
    end
    
    Logger.info("Extracted query: '#{query}', length: #{String.length(query)}")
    
    if String.length(query) >= 2 do
      Logger.info("Searching MusicBrainz for: #{query}")
      
      # Set loading state
      socket = assign(socket, :search_loading, true)
      
      case EventasaurusWeb.Services.RichDataManager.search(query, %{providers: [:musicbrainz], type: :track}) do
        {:ok, provider_results} ->
          Logger.info("PublicMusicTrackPollComponent received provider results: #{inspect(provider_results)}")
          
          # Extract tracks from provider results format: %{provider => {:ok, tracks}}
          tracks = case provider_results do
            %{musicbrainz: {:ok, track_list}} -> track_list
            [{:musicbrainz, {:ok, track_list}}] -> track_list  # fallback format
            results when is_list(results) -> 
              # Handle case where results are already in the expected format
              results
            other -> 
              Logger.error("Unexpected provider results format: #{inspect(other)}")
              []
          end
          
          Logger.info("Found #{length(tracks)} music tracks")
          {:noreply, 
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, tracks)
           |> assign(:search_loading, false)}
        
        {:error, reason} ->
          Logger.error("Music search failed: #{inspect(reason)}")
          {:noreply, 
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, [])
           |> assign(:search_loading, false)}
      end
    else
      {:noreply, 
       socket
       |> assign(:search_query, query)
       |> assign(:search_results, [])
       |> assign(:search_loading, false)}
    end
  end

  @impl true
  def handle_event("add_track", %{"track-id" => track_id}, socket) do
    # Find the selected track in search results
    case Enum.find(socket.assigns.search_results, &(&1.id == track_id)) do
      nil ->
        Logger.error("Track not found in search results: #{track_id}")
        {:noreply, socket}
      
      track ->
        Logger.info("Adding track: #{track.title}")
        
        # Prepare track data for adding to poll
        track_data = %{
          "id" => track.id,
          "title" => track.title,
          "description" => track.description,
          "metadata" => track.metadata || %{}
        }
        
        # Create option data
        option_data = %{
          title: track.title,
          description: track.description,
          external_id: track.id,
          poll_type: "music_track",
          rich_data: track.metadata || %{}
        }
        
        # Send to parent LiveView
        send(self(), {:music_track_selected, track_data, option_data})
        
        # Clear search results after adding
        {:noreply, 
         socket
         |> assign(:search_query, "")
         |> assign(:search_results, [])
         |> assign(:search_loading, false)}
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
  # Private Helper Functions
  # ============================================================================

  defp get_music_track_poll(event) do
    Events.get_event_poll(event, "music_track")
  end

  defp extract_artist_names(artist_credit) when is_list(artist_credit) do
    artist_credit
    |> Enum.map(fn credit ->
      case credit do
        %{"name" => name} -> name
        %{"artist" => %{"name" => name}} -> name
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  defp extract_artist_names(_), do: "Unknown Artist"

  defp get_current_user_vote(option, user) do
    if user do
      Enum.find(option.poll_votes || [], &(&1.user_id == user.id))
    else
      nil
    end
  end

  defp get_total_votes(options) do
    Enum.sum(Enum.map(options, &(&1.vote_count || 0)))
  end

  defp get_option_color(index) do
    colors = ["#3B82F6", "#EF4444", "#10B981", "#F59E0B", "#8B5CF6", "#EC4899", "#6B7280", "#14B8A6"]
    Enum.at(colors, rem(index, length(colors)))
  end
end