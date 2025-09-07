defmodule EventasaurusWeb.Live.Components.PublicMusicTrackPollComponent do
  @moduledoc """
  Public music track poll component.
  
  Handles music track search, voting, and display functionality for public users.
  Uses the same patterns as PublicMoviePollComponent but for music content.
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.Services.RichDataManager

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:search_query, fn -> "" end)
      |> assign_new(:search_results, fn -> [] end)
      |> assign_new(:search_loading, fn -> false end)
      |> assign_new(:selected_search_result, fn -> nil end)
      |> assign_new(:temp_votes, fn -> %{} end)
      |> assign_new(:loading_rich_data, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow p-6">
      <div class="mb-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-2"><%= @poll.title %></h3>
        <%= if @poll.description do %>
          <p class="text-gray-600 text-sm mb-4"><%= @poll.description %></p>
        <% end %>

        <!-- Phase-specific content -->
        <%= case @poll.phase do %>
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
    </div>
    """
  end

  # List Building Phase - Users can search and suggest music tracks
  defp render_list_building_phase(assigns) do
    ~H"""
    <div>
      <!-- Search Interface -->
      <div class="mb-6">
        <form phx-target={@myself} phx-submit="search_music">
          <div class="flex gap-2">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search for music tracks..."
              class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
              phx-debounce="300"
              phx-target={@myself}
              phx-change="search_input_changed"
            />
            <button
              type="submit"
              disabled={@search_loading || String.length(@search_query) < 2}
              class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <%= if @search_loading do %>
                <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" />
              <% else %>
                Search
              <% end %>
            </button>
          </div>
        </form>
      </div>

      <!-- Search Results -->
      <%= if length(@search_results) > 0 do %>
        <div class="mb-6">
          <h4 class="text-sm font-medium text-gray-900 mb-3">Search Results</h4>
          <div class="space-y-2">
            <%= for result <- @search_results do %>
              <div class="border rounded-lg p-3 hover:bg-gray-50">
                <div class="flex justify-between items-start">
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 mb-1">
                      <.icon name="hero-musical-note" class="h-4 w-4 text-blue-600 flex-shrink-0" />
                      <h5 class="font-medium text-gray-900 truncate"><%= result.title %></h5>
                    </div>
                    <%= if result.metadata["artist_credit"] do %>
                      <p class="text-sm text-gray-600 mb-1">
                        <%= result.metadata["artist_credit"] |> Enum.map(& &1["name"] || &1["artist"]["name"]) |> Enum.join(", ") %>
                      </p>
                    <% end %>
                    <%= if result.metadata["duration_formatted"] do %>
                      <p class="text-xs text-gray-500">Duration: <%= result.metadata["duration_formatted"] %></p>
                    <% end %>
                  </div>
                  <button
                    type="button"
                    phx-click="select_music_result"
                    phx-value-result-id={result.id}
                    phx-target={@myself}
                    class="ml-3 px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
                  >
                    Add to Poll
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Loading Rich Data -->
      <%= if @loading_rich_data do %>
        <div class="text-center py-4">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin text-blue-600 mx-auto" />
          <p class="text-sm text-gray-600 mt-2">Loading track details...</p>
        </div>
      <% end %>

      <!-- Current Options -->
      <%= render_current_options(assigns) %>
    </div>
    """
  end

  # Voting Phase - Users can vote on existing options
  defp render_voting_phase(assigns) do
    ~H"""
    <div>
      <%= if @poll.phase == "voting_with_suggestions" do %>
        <!-- Show search interface for suggestions -->
        <div class="mb-6 p-4 bg-blue-50 rounded-lg">
          <h4 class="text-sm font-medium text-blue-900 mb-2">Suggest New Tracks</h4>
          <form phx-target={@myself} phx-submit="search_music">
            <div class="flex gap-2">
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search for music tracks..."
                class="flex-1 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                phx-debounce="300"
                phx-target={@myself}
                phx-change="search_input_changed"
              />
              <button
                type="submit"
                disabled={@search_loading || String.length(@search_query) < 2}
                class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
              >
                <%= if @search_loading do %>
                  <.icon name="hero-arrow-path" class="h-4 w-4 animate-spin" />
                <% else %>
                  Search
                <% end %>
              </button>
            </div>
          </form>

          <!-- Search Results for Suggestions -->
          <%= if length(@search_results) > 0 do %>
            <div class="mt-4 space-y-2">
              <%= for result <- @search_results do %>
                <div class="border rounded-lg p-3 bg-white">
                  <div class="flex justify-between items-start">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2 mb-1">
                        <.icon name="hero-musical-note" class="h-4 w-4 text-blue-600 flex-shrink-0" />
                        <h5 class="font-medium text-gray-900 truncate"><%= result.title %></h5>
                      </div>
                      <%= if result.metadata["artist_credit"] do %>
                        <p class="text-sm text-gray-600">
                          <%= result.metadata["artist_credit"] |> Enum.map(& &1["name"] || &1["artist"]["name"]) |> Enum.join(", ") %>
                        </p>
                      <% end %>
                    </div>
                    <button
                      type="button"
                      phx-click="select_music_result"
                      phx-value-result-id={result.id}
                      phx-target={@myself}
                      class="ml-3 px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
                    >
                      Suggest
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Voting Options -->
      <%= render_voting_options(assigns) %>
    </div>
    """
  end

  # Results Phase - Show poll results
  defp render_results_phase(assigns) do
    ~H"""
    <div>
      <div class="mb-4">
        <div class="flex items-center justify-between">
          <h4 class="text-lg font-medium text-gray-900">Poll Results</h4>
          <div class="text-sm text-gray-600">
            <%= length(@poll.poll_options) %> options • <%= get_total_votes(@poll.poll_options) %> total votes
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
    <%= if length(@poll.poll_options) > 0 do %>
      <div>
        <h4 class="text-sm font-medium text-gray-900 mb-3">Current Options (<%= length(@poll.poll_options) %>)</h4>
        <div class="space-y-3">
          <%= for option <- @poll.poll_options do %>
            <div class="border rounded-lg p-4">
              <%= render_music_option_content(assigns, option) %>
            </div>
          <% end %>
        </div>
      </div>
    <% else %>
      <div class="text-center py-8 text-gray-500">
        <.icon name="hero-musical-note" class="h-12 w-12 mx-auto mb-3 text-gray-400" />
        <p>No music tracks have been added yet.</p>
        <p class="text-sm">Search above to add the first track.</p>
      </div>
    <% end %>
    """
  end

  # Voting options with vote buttons
  defp render_voting_options(assigns) do
    ~H"""
    <%= if length(@poll.poll_options) > 0 do %>
      <div class="space-y-3">
        <%= for option <- @poll.poll_options do %>
          <div class="border rounded-lg p-4 hover:bg-gray-50">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <%= render_music_option_content(assigns, option) %>
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
        <.icon name="hero-musical-note" class="h-12 w-12 mx-auto mb-3 text-gray-400" />
        <p>No tracks to vote on yet.</p>
      </div>
    <% end %>
    """
  end

  # Results display with vote counts and percentages
  defp render_results_options(assigns) do
    total_votes = get_total_votes(assigns.poll.poll_options)

    assigns = assign(assigns, :total_votes, total_votes)

    ~H"""
    <div class="space-y-3">
      <%= for {option, index} <- Enum.with_index(@poll.poll_options) do %>
        <div class="border rounded-lg p-4">
          <div class="flex items-start justify-between mb-3">
            <div class="flex-1">
              <%= render_music_option_content(assigns, option) %>
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

  # Music option content rendering
  defp render_music_option_content(assigns, option) do
    assigns = assign(assigns, :option, option)

    ~H"""
    <div>
      <div class="flex items-start gap-3">
        <div class="flex-shrink-0">
          <.icon name="hero-musical-note" class="h-5 w-5 text-blue-600 mt-0.5" />
        </div>
        <div class="flex-1 min-w-0">
          <h5 class="font-medium text-gray-900 mb-1"><%= @option.title %></h5>
          
          <%= if Map.has_key?(@option, :rich_data) && @option.rich_data do %>
            <%= render_rich_music_data(assigns, @option.rich_data) %>
          <% else %>
            <%= if @option.description do %>
              <p class="text-sm text-gray-600"><%= @option.description %></p>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Rich music data display
  defp render_rich_music_data(assigns, rich_data) do
    assigns = assign(assigns, :rich_data, rich_data)

    ~H"""
    <div class="space-y-2">
      <%= if @rich_data["artist_credit"] do %>
        <p class="text-sm text-gray-700">
          <span class="font-medium">Artist:</span>
          <%= @rich_data["artist_credit"] |> Enum.map(& &1["name"] || &1["artist"]["name"]) |> Enum.join(", ") %>
        </p>
      <% end %>

      <%= if @rich_data["releases"] && length(@rich_data["releases"]) > 0 do %>
        <p class="text-sm text-gray-600">
          <span class="font-medium">Album:</span>
          <%= List.first(@rich_data["releases"])["title"] %>
        </p>
      <% end %>

      <%= if @rich_data["duration_formatted"] do %>
        <p class="text-sm text-gray-600">
          <span class="font-medium">Duration:</span>
          <%= @rich_data["duration_formatted"] %>
        </p>
      <% end %>

      <%= if @rich_data["disambiguation"] do %>
        <p class="text-xs text-gray-500 italic"><%= @rich_data["disambiguation"] %></p>
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
          <.icon name="hero-heart-solid" class="h-4 w-4 inline mr-1" />
          Voted
        <% else %>
          <.icon name="hero-heart" class="h-4 w-4 inline mr-1" />
          Vote
        <% end %>
      </button>
      
      <div class="text-xs text-gray-500 text-center">
        <%= (@option.vote_count || 0) + (if @temp_vote && not @current_user_vote, do: 1, else: 0) %> votes
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("search_input_changed", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("search_music", %{"query" => query}, socket) do
    if String.length(String.trim(query)) >= 2 do
      socket = 
        socket
        |> assign(:search_loading, true)
        |> assign(:search_query, query)

      # Use RichDataManager to search for music tracks
      search_options = %{
        providers: [:musicbrainz],
        limit: 8,
        content_type: :track
      }

      case RichDataManager.search(query, search_options) do
        {:ok, results_by_provider} ->
          music_results = case Map.get(results_by_provider, :musicbrainz) do
            nil -> []
            results when is_list(results) -> results
            _ -> []
          end

          {:noreply,
           socket
           |> assign(:search_results, music_results)
           |> assign(:search_loading, false)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:search_results, [])
           |> assign(:search_loading, false)
           |> put_flash(:error, "Search failed. Please try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_music_result", %{"result-id" => result_id}, socket) do
    # Find the selected result
    selected_result = Enum.find(socket.assigns.search_results, &(&1.id == result_id))
    
    if selected_result do
      socket = assign(socket, :loading_rich_data, true)
      
      # Get detailed data for the selected track
      case RichDataManager.get_details(selected_result.id, :musicbrainz, %{content_type: :track}) do
        {:ok, rich_data} ->
          # Prepare option data and send to parent
          option_data = prepare_music_option_data(selected_result, rich_data)
          send(self(), {:music_track_selected, selected_result, rich_data, option_data})
          
          {:noreply,
           socket
           |> assign(:search_results, [])
           |> assign(:search_query, "")
           |> assign(:loading_rich_data, false)}

        {:error, _reason} ->
          # Fallback to basic data if rich data fails
          option_data = prepare_music_option_data(selected_result, nil)
          send(self(), {:music_track_selected, selected_result, nil, option_data})
          
          {:noreply,
           socket
           |> assign(:search_results, [])
           |> assign(:search_query, "")
           |> assign(:loading_rich_data, false)}
      end
    else
      {:noreply, put_flash(socket, :error, "Track not found.")}
    end
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
      send(self(), {:temp_vote_changed, socket.assigns.poll.id, updated_temp_votes})
      
      {:noreply, assign(socket, :temp_votes, updated_temp_votes)}
    end
  end

  # Helper Functions

  defp prepare_music_option_data(search_result, rich_data) do
    base_data = %{
      title: search_result.title,
      description: format_track_description(search_result),
      external_id: search_result.id,
      rich_data: rich_data
    }

    if rich_data do
      Map.merge(base_data, %{
        title: search_result.title,
        description: format_rich_track_description(rich_data)
      })
    else
      base_data
    end
  end

  defp format_track_description(search_result) do
    parts = []
    
    parts = if search_result.metadata["artist_credit"] do
      artist_names = search_result.metadata["artist_credit"] 
        |> Enum.map(& &1["name"] || &1["artist"]["name"])
        |> Enum.join(", ")
      parts ++ ["by #{artist_names}"]
    else
      parts
    end

    parts = if search_result.metadata["duration_formatted"] do
      parts ++ ["(#{search_result.metadata["duration_formatted"]})"]
    else
      parts
    end

    Enum.join(parts, " ")
  end

  defp format_rich_track_description(rich_data) do
    parts = []
    
    parts = if rich_data["artist_credit"] do
      artist_names = rich_data["artist_credit"] 
        |> Enum.map(& &1["name"] || &1["artist"]["name"])
        |> Enum.join(", ")
      parts ++ ["by #{artist_names}"]
    else
      parts
    end

    parts = if rich_data["releases"] && length(rich_data["releases"]) > 0 do
      album_title = List.first(rich_data["releases"])["title"]
      parts ++ ["from #{album_title}"]
    else
      parts
    end

    parts = if rich_data["duration_formatted"] do
      parts ++ ["(#{rich_data["duration_formatted"]})"]
    else
      parts
    end

    Enum.join(parts, " ")
  end

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