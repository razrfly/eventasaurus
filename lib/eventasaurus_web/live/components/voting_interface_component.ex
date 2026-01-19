defmodule EventasaurusWeb.VotingInterfaceComponent do
  @moduledoc """
  A reusable LiveView component for handling different voting systems in polls.

  Provides specialized interfaces for binary, approval, ranked choice, and star rating
  voting systems. Handles user vote state, submission, and real-time updates.

  Supports both authenticated and anonymous voting patterns.

  ## Attributes:
  - poll: Poll struct with preloaded options and votes (required)
  - user: User struct (nil for anonymous users)
  - user_votes: List of user's existing votes for this poll
  - loading: Whether a vote operation is in progress
  - temp_votes: Map of temporary votes for anonymous users
  - anonymous_mode: Boolean to enable anonymous voting flow

  ## Usage:
      # Authenticated user
      <.live_component
        module={EventasaurusWeb.VotingInterfaceComponent}
        id="voting-interface"
        poll={@poll}
        user={@user}
        user_votes={@user_votes}
        loading={@loading}
      />

      # Anonymous user
      <.live_component
        module={EventasaurusWeb.VotingInterfaceComponent}
        id="voting-interface"
        poll={@poll}
        user={nil}
        user_votes={[]}
        loading={@loading}
        temp_votes={@temp_votes}
        anonymous_mode={true}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Poll
  alias EventasaurusWeb.Utils.MovieUtils
  alias EventasaurusWeb.EmbeddedProgressBarComponent
  import EventasaurusWeb.VoterCountDisplay
  import EventasaurusWeb.ClearVotesButton

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:vote_state, %{})
     |> assign(:ranked_options, [])
     |> assign(:temp_votes, %{})
     |> assign(:anonymous_mode, false)}
  end

  @impl true
  def update(assigns, socket) do
    # Determine if we're in anonymous mode
    anonymous_mode = assigns[:anonymous_mode] || is_nil(assigns[:user])
    temp_votes = assigns[:temp_votes] || %{}

    # Ensure poll options are preloaded with suggested_by
    poll =
      if assigns.poll do
        # Batch preload suggested_by association for options that don't have it loaded
        options_with_suggested_by =
          case assigns.poll.poll_options do
            [] ->
              []

            options ->
              # Check if any options need preloading
              needs_preload =
                Enum.any?(options, fn option ->
                  match?(%Ecto.Association.NotLoaded{}, option.suggested_by)
                end)

              if needs_preload do
                # Get all option IDs and batch load them with suggested_by preloaded
                option_ids = Enum.map(options, & &1.id)
                preloaded_options = Events.list_poll_options_by_ids(option_ids, [:suggested_by])

                # Create a map for quick lookup
                preloaded_map = Map.new(preloaded_options, fn option -> {option.id, option} end)

                # Return options with preloaded data, filtering out any that were deleted
                options
                |> Enum.filter(fn option -> Map.has_key?(preloaded_map, option.id) end)
                |> Enum.map(fn option -> Map.get(preloaded_map, option.id, option) end)
              else
                # All options already have suggested_by loaded
                options
              end
          end

        %{assigns.poll | poll_options: options_with_suggested_by}
      else
        assigns.poll
      end

    # Initialize vote state based on user votes or temp votes
    vote_state =
      if anonymous_mode do
        initialize_anonymous_vote_state(poll, temp_votes)
      else
        initialize_vote_state(poll, assigns.user_votes)
      end

    # For ranked voting, initialize ordered options
    ranked_options =
      case poll && poll.voting_system do
        "ranked" ->
          if anonymous_mode do
            initialize_anonymous_ranked_options(poll.poll_options, temp_votes)
          else
            initialize_ranked_options(poll.poll_options, assigns.user_votes)
          end

        _ ->
          []
      end

    # Load poll statistics for embedded display
    poll_stats =
      if poll do
        try do
          Events.get_poll_voting_stats(poll)
        rescue
          error in [ArgumentError, RuntimeError] ->
            require Logger
            Logger.error("Failed to load poll stats: #{inspect(error)}")
            %{options: [], total_unique_voters: 0}
        end
      else
        %{options: [], total_unique_voters: 0}
      end

    # Ensure anonymous ID is assigned before we use it
    socket_with_anon_id =
      if anonymous_mode do
        Eventasaurus.Services.AnonymousIdService.assign_anonymous_id(socket)
      else
        socket
      end

    # Subscribe to poll statistics updates for real-time updates
    if connected?(socket_with_anon_id) && poll do
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "polls:#{poll.id}:stats")

      # Track poll view analytics (only on initial mount, not on updates)
      if !socket_with_anon_id.assigns[:poll_view_tracked] do
        user_id = if anonymous_mode, do: nil, else: assigns[:user] && assigns.user.id

        # Get consistent anonymous ID for this session
        user_identifier =
          Eventasaurus.Services.AnonymousIdService.get_user_identifier(
            user_id,
            socket_with_anon_id
          )

        metadata = %{
          event_id: poll.event_id,
          poll_type: poll.voting_system,
          poll_phase: poll.phase,
          is_anonymous: anonymous_mode
        }

        Eventasaurus.Services.PollAnalyticsService.track_poll_viewed(
          user_identifier,
          to_string(poll.id),
          metadata
        )
      end
    end

    {:ok,
     socket_with_anon_id
     |> assign(assigns)
     |> assign(:poll, poll)
     |> assign(:vote_state, vote_state)
     |> assign(:ranked_options, ranked_options)
     |> assign(:temp_votes, temp_votes)
     |> assign(:anonymous_mode, anonymous_mode)
     |> assign(:poll_stats, poll_stats)
     |> assign(:poll_view_tracked, true)
     |> assign_new(:loading, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    # Handle mode prop with backward compatibility for show_header
    # mode: :full (default) - Show header with voting title, instructions, voter count
    # mode: :content - Show only voting interface, parent handles header
    mode =
      cond do
        Map.has_key?(assigns, :mode) -> assigns.mode
        Map.has_key?(assigns, :show_header) -> if assigns.show_header, do: :full, else: :content
        true -> :full
      end

    assigns = assign(assigns, :mode, mode)

    ~H"""
    <div class={if @mode == :full, do: "bg-white shadow rounded-lg", else: ""}>
      <!-- Header (optional) -->
      <%= if @mode == :full do %>
        <div class="px-4 sm:px-6 py-4 border-b border-gray-200">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
            <div class="flex-1">
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                <h3 class="text-base sm:text-lg font-medium text-gray-900">
                  <%= get_voting_title(@poll.voting_system) %>
                </h3>
                <.voter_count poll_stats={@poll_stats} poll_phase={@poll.phase} class="sm:ml-4" />
              </div>
              <p class="text-xs sm:text-sm text-gray-500">
                <%= get_voting_instructions(@poll.voting_system) %>
              </p>
              <%= if @anonymous_mode and has_temp_votes?(@temp_votes, @poll.voting_system) do %>
                <div class="mt-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                  <svg class="mr-1 h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                  </svg>
                  Temporary votes stored
                </div>
              <% end %>
            </div>

            <.clear_votes_button
              id={"clear-votes-#{@poll.id}"}
              target={@myself}
              has_votes={has_votes?(@vote_state, @poll.voting_system)}
              loading={@loading}
              anonymous_mode={@anonymous_mode}
              variant="text"
            />
          </div>
        </div>
      <% end %>

      <!-- Voting Interface -->
      <div class={if @mode == :full, do: "divide-y divide-gray-200", else: ""}>
        <%= case @poll.voting_system do %>
          <% "binary" -> %>
            <%= render_binary_voting(assigns) %>
          <% "approval" -> %>
            <%= render_approval_voting(assigns) %>
          <% "ranked" -> %>
            <%= render_ranked_voting(assigns) %>
          <% "star" -> %>
            <%= render_star_voting(assigns) %>
        <% end %>
      </div>

      <!-- Vote Summary -->
      <div class="px-4 sm:px-6 py-4 bg-gray-50 border-t border-gray-200">
        <%= render_vote_summary(assigns) %>
      </div>

      <!-- Anonymous Voting Call-to-Action -->
      <%= if @anonymous_mode and has_temp_votes?(@temp_votes, @poll.voting_system) do %>
        <div class="px-4 sm:px-6 py-4 bg-blue-50 border-t border-blue-200">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div class="flex items-start sm:items-center">
              <svg class="h-5 w-5 text-blue-400 mr-2 flex-shrink-0 mt-0.5 sm:mt-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <p class="text-sm text-blue-800">
                Your votes are temporarily stored. Save them to participate!
              </p>
            </div>
            <button
              type="button"
              phx-click="show_save_votes_modal"
              phx-target={@myself}
              class="bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium py-2 px-4 rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 w-full sm:w-auto"
            >
              Save My Votes
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Binary Voting (Yes/No/Maybe)
  defp render_binary_voting(assigns) do
    ~H"""
    <%= for option <- @poll.poll_options do %>
      <div class="px-4 sm:px-6 py-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <!-- Movie Image for movie polls -->
          <%= if @poll.poll_type == "movie" do %>
            <div class="flex sm:block">
              <div class="w-12 h-18 sm:w-16 sm:h-24 mr-3 flex-shrink-0 overflow-hidden rounded">
                <% image_url = MovieUtils.get_image_url(option) %>
                <%= if image_url do %>
                  <img
                    src={image_url}
                    alt={"#{option.title} poster"}
                    class="w-full h-full object-cover"
                    loading="lazy"
                  />
                <% else %>
                  <div class="w-full h-full bg-gray-200 flex items-center justify-center">
                    <svg class="w-6 h-6 sm:w-8 sm:h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
                    </svg>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <!-- Images for non-movie polls (places, etc.) -->
            <%= if option.image_url do %>
              <div class="flex sm:block">
                <div class="w-12 h-18 sm:w-16 sm:h-24 mr-3 flex-shrink-0 overflow-hidden rounded">
                  <img
                    src={option.image_url}
                    alt={"#{option.title} image"}
                    class="w-full h-full object-cover"
                    loading="lazy"
                  />
                </div>
              </div>
            <% end %>
          <% end %>
          
          <div class="flex-1 min-w-0">
            <div class="flex items-center space-x-2">
              <% movie_url = if @poll.poll_type == "movie", do: MovieUtils.get_primary_movie_url(option), else: nil %>
              <%= if movie_url do %>
                <h4 class={"text-sm font-medium " <> if(@poll.poll_type == "movie", do: "line-clamp-1 sm:line-clamp-none", else: "break-words")}>
                  <.link
                    href={movie_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    phx-click="stop_propagation"
                    onclick="event.stopPropagation()"
                    class="text-blue-600 hover:text-blue-800 hover:underline"
                  >
                    <%= option.title %>
                  </.link>
                </h4>
              <% else %>
                <h4 class={"text-sm font-medium text-gray-900 " <> if(@poll.poll_type == "movie", do: "line-clamp-1 sm:line-clamp-none", else: "break-words")}><%= option.title %></h4>
              <% end %>
              <%= if has_time_slots?(option) do %>
                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
                  <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                  Times
                </span>
              <% end %>
            </div>

            <%= if option.description do %>
              <p class={"text-sm text-gray-500 mt-1 " <> if(@poll.poll_type in ["movie", "cocktail"], do: "line-clamp-2", else: "")}><%= option.description %></p>
            <% end %>
            
            <!-- Show who suggested this option -->
            <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@poll) and option.suggested_by do %>
              <p class="text-xs text-gray-500 mt-1">
                Suggested by <%= option.suggested_by.name || option.suggested_by.username || option.suggested_by.email || "Anonymous" %>
              </p>
            <% end %>
            
            <!-- Delete button for user's own suggestions -->
            <%= if option.suggested_by && @user && Events.can_delete_option_based_on_poll_settings?(option, @user) do %>
              <div class="mt-2 flex items-center space-x-2">
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

            <!-- Time Slots Display -->
            <%= if has_time_slots?(option) do %>
              <div class="mt-2 flex flex-wrap gap-1">
                <%= for time_slot <- get_time_slots_from_option(option) do %>
                  <span class="inline-flex items-center px-2 py-1 rounded-md text-xs bg-white border border-gray-200 text-gray-700">
                    <%= format_time_slot_display(time_slot) %>
                  </span>
                <% end %>
              </div>
            <% end %>

            <!-- Embedded Progress Bar -->
            <div class="mt-2">
              <.live_component
                module={EmbeddedProgressBarComponent}
                id={"progress-#{@poll.id}-#{option.id}-binary"}
                poll_stats={@poll_stats}
                option_id={option.id}
                voting_system={@poll.voting_system}
                compact={true}
                show_labels={false}
                show_counts={true}
                anonymous_mode={@anonymous_mode}
              />
            </div>
          </div>

          <div class="w-full sm:w-auto sm:ml-4 flex flex-row gap-2">
            <button
              type="button"
              phx-click="cast_binary_vote"
              phx-value-option-id={option.id}
              phx-value-vote="yes"
              phx-target={@myself}
              disabled={@loading}
              class={binary_button_class(@vote_state[option.id], "yes", @anonymous_mode) <> " flex-1 sm:flex-initial min-h-[44px] sm:min-h-[36px] touch-target"}
            >
              <svg class="h-5 w-5 sm:mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              <span class="sr-only sm:not-sr-only">Yes</span>
            </button>

            <button
              type="button"
              phx-click="cast_binary_vote"
              phx-value-option-id={option.id}
              phx-value-vote="maybe"
              phx-target={@myself}
              disabled={@loading}
              class={binary_button_class(@vote_state[option.id], "maybe", @anonymous_mode) <> " flex-1 sm:flex-initial min-h-[44px] sm:min-h-[36px] touch-target"}
            >
              <svg class="h-5 w-5 sm:mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span class="sr-only sm:not-sr-only">Maybe</span>
            </button>

            <button
              type="button"
              phx-click="cast_binary_vote"
              phx-value-option-id={option.id}
              phx-value-vote="no"
              phx-target={@myself}
              disabled={@loading}
              class={binary_button_class(@vote_state[option.id], "no", @anonymous_mode) <> " flex-1 sm:flex-initial min-h-[44px] sm:min-h-[36px] touch-target"}
            >
              <svg class="h-5 w-5 sm:mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
              <span class="sr-only sm:not-sr-only">No</span>
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Approval Voting (Multiple checkboxes)
  defp render_approval_voting(assigns) do
    ~H"""
    <%= for option <- @poll.poll_options do %>
      <div class="px-4 sm:px-6 py-4">
        <label class="flex items-start cursor-pointer hover:bg-gray-50 -mx-2 px-2 py-3 sm:py-2 rounded touch-target min-h-[60px] sm:min-h-[auto]">
          <input
            type="checkbox"
            phx-click="toggle_approval_vote"
            phx-value-option-id={option.id}
            phx-target={@myself}
            checked={@vote_state[option.id] == "approved"}
            disabled={@loading}
            class={approval_checkbox_class(@vote_state[option.id], @anonymous_mode) <> " w-5 h-5 sm:w-4 sm:h-4 mt-0.5 sm:mt-0 flex-shrink-0"}
          />
          
          <!-- Movie Image for movie polls -->
          <%= if @poll.poll_type == "movie" do %>
            <div class="w-12 h-18 sm:w-16 sm:h-24 ml-2 mr-2 sm:ml-3 sm:mr-3 flex-shrink-0 overflow-hidden rounded">
              <% image_url = MovieUtils.get_image_url(option) %>
              <%= if image_url do %>
                <img
                  src={image_url}
                  alt={"#{option.title} poster"}
                  class="w-full h-full object-cover"
                  loading="lazy"
                />
              <% else %>
                <div class="w-full h-full bg-gray-200 flex items-center justify-center">
                  <svg class="w-6 h-6 sm:w-8 sm:h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
                  </svg>
                </div>
              <% end %>
            </div>
          <% else %>
            <!-- Images for non-movie polls (places, etc.) -->
            <%= if option.image_url do %>
              <div class="w-12 h-18 sm:w-16 sm:h-24 ml-2 mr-2 sm:ml-3 sm:mr-3 flex-shrink-0 overflow-hidden rounded">
                <img
                  src={option.image_url}
                  alt={"#{option.title} image"}
                  class="w-full h-full object-cover"
                  loading="lazy"
                />
              </div>
            <% else %>
              <div class="ml-3"></div>
            <% end %>
          <% end %>
          
          <div class="flex-1 min-w-0">
            <div class="flex items-start sm:items-center space-x-2">
              <% movie_url = if @poll.poll_type == "movie", do: MovieUtils.get_primary_movie_url(option), else: nil %>
              <%= if movie_url do %>
                <h4 class={"text-sm font-medium " <> if(@poll.poll_type == "movie", do: "line-clamp-1 sm:line-clamp-none", else: "break-words")}>
                  <.link
                    href={movie_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    phx-click="stop_propagation"
                    onclick="event.stopPropagation()"
                    class="text-blue-600 hover:text-blue-800 hover:underline"
                  >
                    <%= option.title %>
                  </.link>
                </h4>
              <% else %>
                <h4 class={"text-sm font-medium text-gray-900 " <> if(@poll.poll_type == "movie", do: "line-clamp-1 sm:line-clamp-none", else: "break-words")}><%= option.title %></h4>
              <% end %>
              <%= if has_time_slots?(option) do %>
                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
                  <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                  </svg>
                  Times
                </span>
              <% end %>
            </div>

            <%= if option.description do %>
              <p class={"text-sm text-gray-500 mt-1 " <> if(@poll.poll_type in ["movie", "cocktail"], do: "line-clamp-2", else: "")}><%= option.description %></p>
            <% end %>
            
            <!-- Show who suggested this option -->
            <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@poll) and option.suggested_by do %>
              <p class="text-xs text-gray-500 mt-1">
                Suggested by <%= option.suggested_by.name || option.suggested_by.username || option.suggested_by.email || "Anonymous" %>
              </p>
            <% end %>
            
            <!-- Delete button for user's own suggestions -->
            <%= if option.suggested_by && @user && Events.can_delete_option_based_on_poll_settings?(option, @user) do %>
              <div class="mt-2 flex items-center space-x-2">
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

            <!-- Time Slots Display -->
            <%= if has_time_slots?(option) do %>
              <div class="mt-2 flex flex-wrap gap-1">
                <%= for time_slot <- get_time_slots_from_option(option) do %>
                  <span class="inline-flex items-center px-2 py-1 rounded-md text-xs bg-white border border-gray-200 text-gray-700">
                    <%= format_time_slot_display(time_slot) %>
                  </span>
                <% end %>
              </div>
            <% end %>

            <!-- Embedded Progress Bar -->
            <div class="mt-2">
              <.live_component
                module={EmbeddedProgressBarComponent}
                id={"progress-#{@poll.id}-#{option.id}-approval"}
                poll_stats={@poll_stats}
                option_id={option.id}
                voting_system={@poll.voting_system}
                compact={true}
                show_labels={false}
                show_counts={true}
                anonymous_mode={@anonymous_mode}
              />
            </div>
          </div>
        </label>
      </div>
    <% end %>
    """
  end

  # Ranked Choice Voting (Drag and drop)
  defp render_ranked_voting(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 py-4">
      <div class="space-y-4">
        <!-- Instructions -->
        <div class={"hidden sm:block border rounded-md p-3 sm:p-4 " <> if(@anonymous_mode, do: "bg-blue-50 border-blue-200", else: "bg-blue-50 border-blue-200")}>
          <div class="flex">
            <svg class="h-5 w-5 text-blue-400 flex-shrink-0 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
            </svg>
            <div class="ml-3">
              <p class="text-xs sm:text-sm text-blue-800">
                Use the up/down arrows to rank options in order of preference (1st choice at top). Unranked options won't receive votes.
                <%= if @anonymous_mode do %>
                  <span class="font-medium">Rankings are temporarily stored.</span>
                <% end %>
                <br/>
                <% max_rankings = @poll |> Poll.get_max_rankings() %>
                <%= if max_rankings do %>
                  <span class="font-medium">
                    Ranking limit: <%= length(@ranked_options) %>/<%= max_rankings %> choices
                    <%= if length(@ranked_options) >= max_rankings do %>
                      <span class="text-amber-700">(limit reached)</span>
                    <% end %>
                  </span>
                <% end %>
              </p>
            </div>
          </div>
        </div>

        <!-- Ranked Options -->
        <div class="space-y-2">
          <%= for {option, index} <- Enum.with_index(@ranked_options) do %>
            <div class={"flex items-start p-2 sm:p-3 border rounded-lg shadow-sm " <> if(@anonymous_mode, do: "bg-blue-50 border-blue-200", else: "bg-white border-gray-200")}>
              <div class={"flex items-center justify-center w-5 h-5 sm:w-6 sm:h-6 text-xs sm:text-sm font-semibold rounded-full mr-2 flex-shrink-0 mt-1 sm:mt-0 " <> if(@anonymous_mode, do: "bg-blue-200 text-blue-800", else: "bg-indigo-100 text-indigo-800")}>
                <%= index + 1 %>
              </div>
              
              <!-- Movie Image for movie polls -->
              <%= if @poll.poll_type == "movie" do %>
                <div class="w-12 h-18 sm:w-16 sm:h-24 mr-2 sm:mr-3 flex-shrink-0 overflow-hidden rounded">
                  <% image_url = MovieUtils.get_image_url(option) %>
                  <%= if image_url do %>
                    <img
                      src={image_url}
                      alt={"#{option.title} poster"}
                      class="w-full h-full object-cover"
                      loading="lazy"
                    />
                  <% else %>
                    <div class="w-full h-full bg-gray-200 flex items-center justify-center">
                      <svg class="w-6 h-6 sm:w-8 sm:h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
                      </svg>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <!-- Images for non-movie polls (places, etc.) -->
                <%= if option.image_url do %>
                  <div class="w-12 h-18 sm:w-16 sm:h-24 mr-2 sm:mr-3 flex-shrink-0 overflow-hidden rounded">
                    <img
                      src={option.image_url}
                      alt={"#{option.title} image"}
                      class="w-full h-full object-cover"
                      loading="lazy"
                    />
                  </div>
                <% end %>
              <% end %>
              
              <div class="flex-1 min-w-0">
                <% movie_url = if @poll.poll_type == "movie", do: MovieUtils.get_primary_movie_url(option), else: nil %>
                <%= if movie_url do %>
                  <h4 class="text-sm font-medium line-clamp-1 sm:line-clamp-none">
                    <.link
                      href={movie_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      phx-click="stop_propagation"
                      onclick="event.stopPropagation()"
                      class="text-blue-600 hover:text-blue-800 hover:underline"
                    >
                      <%= option.title %>
                    </.link>
                  </h4>
                <% else %>
                  <h4 class="text-sm font-medium text-gray-900 line-clamp-1 sm:line-clamp-none"><%= option.title %></h4>
                <% end %>
                <%= if option.description do %>
                  <p class={"text-xs text-gray-500 mt-0.5 sm:mt-1 " <> if(@poll.poll_type in ["movie", "cocktail"], do: "line-clamp-2", else: "")}><%= option.description %></p>
                <% end %>
                
                <!-- Show who suggested this option -->
                <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@poll) and option.suggested_by do %>
                  <p class="text-xs text-gray-500 mt-1">
                    Suggested by <%= option.suggested_by.name || option.suggested_by.username || option.suggested_by.email || "Anonymous" %>
                  </p>
                <% end %>

                <!-- Embedded Progress Bar -->
                <div class="mt-1">
                  <.live_component
                    module={EmbeddedProgressBarComponent}
                    id={"progress-#{@poll.id}-#{option.id}-ranked"}
                    poll_stats={@poll_stats}
                    option_id={option.id}
                    voting_system={@poll.voting_system}
                    compact={true}
                    show_labels={false}
                    show_counts={true}
                    anonymous_mode={@anonymous_mode}
                  />
                </div>
              </div>
              <div class="ml-2 flex items-center gap-1">
                <%= if index > 0 do %>
                  <button
                    type="button"
                    phx-click="move_option_up"
                    phx-value-option-id={option.id}
                    phx-target={@myself}
                    class="text-gray-400 hover:text-gray-600 p-0.5 sm:p-1"
                    title="Move up"
                  >
                    <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
                    </svg>
                  </button>
                <% end %>
                <%= if index < length(@ranked_options) - 1 do %>
                  <button
                    type="button"
                    phx-click="move_option_down"
                    phx-value-option-id={option.id}
                    phx-target={@myself}
                    class="text-gray-400 hover:text-gray-600 p-0.5 sm:p-1"
                    title="Move down"
                  >
                    <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                <% end %>
                <button
                  type="button"
                  phx-click="remove_from_ranking"
                  phx-value-option-id={option.id}
                  phx-target={@myself}
                  class="text-red-400 hover:text-red-600 p-0.5 sm:p-1"
                  title="Remove from ranking"
                >
                  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Unranked Options -->
        <%= if length(@ranked_options) < length(@poll.poll_options) do %>
          <div class="border-t pt-4">
            <h4 class="text-sm font-medium text-gray-900 mb-3">Available Options</h4>
            <div class="space-y-2">
              <%= for option <- get_unranked_options(@poll.poll_options, @ranked_options) do %>
                <div class="flex items-center p-2 sm:p-3 bg-gray-50 border border-gray-200 rounded-lg">
                  <!-- Movie Image for movie polls -->
                  <%= if @poll.poll_type == "movie" do %>
                    <div class="w-12 h-18 sm:w-16 sm:h-24 mr-2 sm:mr-3 flex-shrink-0 overflow-hidden rounded">
                      <% image_url = MovieUtils.get_image_url(option) %>
                      <%= if image_url do %>
                        <img
                          src={image_url}
                          alt={"#{option.title} poster"}
                          class="w-full h-full object-cover"
                          loading="lazy"
                        />
                      <% else %>
                        <div class="w-full h-full bg-gray-200 flex items-center justify-center">
                          <svg class="w-6 h-6 sm:w-8 sm:h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
                          </svg>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <!-- Images for non-movie polls (places, etc.) -->
                    <%= if option.image_url do %>
                      <div class="w-12 h-18 sm:w-16 sm:h-24 mr-2 sm:mr-3 flex-shrink-0 overflow-hidden rounded">
                        <img
                          src={option.image_url}
                          alt={"#{option.title} image"}
                          class="w-full h-full object-cover"
                          loading="lazy"
                        />
                      </div>
                    <% end %>
                  <% end %>
                  
                  <div class="flex-1 min-w-0">
                    <% movie_url = if @poll.poll_type == "movie", do: MovieUtils.get_primary_movie_url(option), else: nil %>
                    <%= if movie_url do %>
                      <h5 class="text-sm font-medium line-clamp-1 sm:line-clamp-none">
                        <.link
                          href={movie_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          phx-click="stop_propagation"
                          onclick="event.stopPropagation()"
                          class="text-blue-600 hover:text-blue-800 hover:underline"
                        >
                          <%= option.title %>
                        </.link>
                      </h5>
                    <% else %>
                      <h5 class="text-sm font-medium text-gray-900 line-clamp-1 sm:line-clamp-none"><%= option.title %></h5>
                    <% end %>
                    <%= if option.description do %>
                      <p class={"text-xs text-gray-500 mt-0.5 " <> if(@poll.poll_type in ["movie", "cocktail"], do: "line-clamp-1 sm:line-clamp-2", else: "mt-1")}><%= option.description %></p>
                    <% end %>
                    
                    <!-- Show who suggested this option -->
                    <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@poll) and option.suggested_by do %>
                      <p class="text-xs text-gray-500 mt-1">
                        Suggested by <%= option.suggested_by.name || option.suggested_by.username || option.suggested_by.email || "Anonymous" %>
                      </p>
                    <% end %>
                    
                    <!-- Delete button for user's own suggestions -->
                    <%= if option.suggested_by && @user && Events.can_delete_option_based_on_poll_settings?(option, @user) do %>
                      <div class="mt-2 flex items-center space-x-2">
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

                    <!-- Embedded Progress Bar -->
                    <div class="mt-1">
                      <.live_component
                        module={EmbeddedProgressBarComponent}
                        id={"progress-#{@poll.id}-#{option.id}-ranked-drag"}
                        poll_stats={@poll_stats}
                        option_id={option.id}
                        voting_system={@poll.voting_system}
                        compact={true}
                        show_labels={false}
                        show_counts={true}
                        anonymous_mode={@anonymous_mode}
                      />
                    </div>
                  </div>
                  <% max_rankings = @poll |> Poll.get_max_rankings() %>
                  <% can_add = max_rankings == nil || length(@ranked_options) < max_rankings %>
                  <button
                    type="button"
                    phx-click="add_to_ranking"
                    phx-value-option-id={option.id}
                    phx-target={@myself}
                    disabled={!can_add}
                    class={[
                      "flex items-center px-2 py-1.5 sm:px-3 sm:py-2 ml-2 text-xs sm:text-sm rounded whitespace-nowrap",
                      if(can_add, 
                        do: "bg-indigo-600 text-white hover:bg-indigo-700", 
                        else: "bg-gray-300 text-gray-500 cursor-not-allowed"
                      )
                    ]}
                    title={if can_add, do: "Add to ranking", else: "Ranking limit reached"}
                  >
                    <svg class="h-3 w-3 sm:h-4 sm:w-4 mr-0.5 sm:mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                    </svg>
                    <span class="hidden sm:inline">Add to Ranking</span>
                    <span class="sm:hidden">Add</span>
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
        
      </div>
    </div>
    """
  end

  # Star Rating Voting
  defp render_star_voting(assigns) do
    ~H"""
    <%= for option <- @poll.poll_options do %>
      <div class="px-4 sm:px-6 py-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <!-- Movie/Cocktail Image -->
          <%= if @poll.poll_type == "movie" do %>
            <div class="flex sm:block">
              <div class="w-12 h-18 sm:w-16 sm:h-24 mr-3 flex-shrink-0 overflow-hidden rounded">
                <% image_url = MovieUtils.get_image_url(option) %>
                <%= if image_url do %>
                  <img
                    src={image_url}
                    alt={"#{option.title} poster"}
                    class="w-full h-full object-cover"
                    loading="lazy"
                  />
                <% else %>
                  <div class="w-full h-full bg-gray-200 flex items-center justify-center">
                    <svg class="w-6 h-6 sm:w-8 sm:h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
                    </svg>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <!-- Images for non-movie polls (cocktails, places, etc.) -->
            <%= if option.image_url do %>
              <div class="flex sm:block">
                <div class="w-12 h-18 sm:w-16 sm:h-24 mr-3 flex-shrink-0 overflow-hidden rounded">
                  <img
                    src={option.image_url}
                    alt={"#{option.title} image"}
                    class="w-full h-full object-cover"
                    loading="lazy"
                  />
                </div>
              </div>
            <% end %>
          <% end %>

          <div class="flex-1 min-w-0">
            <% movie_url = if @poll.poll_type == "movie", do: MovieUtils.get_primary_movie_url(option), else: nil %>
            <%= if movie_url do %>
              <h4 class="text-sm font-medium">
                <.link
                  href={movie_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  phx-click="stop_propagation"
                  onclick="event.stopPropagation()"
                  class="text-blue-600 hover:text-blue-800 hover:underline"
                >
                  <%= option.title %>
                </.link>
              </h4>
            <% else %>
              <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
            <% end %>
            <%= if option.description do %>
              <p class={"text-sm text-gray-500 mt-1 " <> if(@poll.poll_type in ["movie", "cocktail"], do: "line-clamp-2", else: "")}><%= option.description %></p>
            <% end %>
            
            <!-- Show who suggested this option -->
            <%= if EventasaurusApp.Events.Poll.show_suggester_names?(@poll) and option.suggested_by do %>
              <p class="text-xs text-gray-500 mt-1">
                Suggested by <%= option.suggested_by.name || option.suggested_by.username || option.suggested_by.email || "Anonymous" %>
              </p>
            <% end %>
            
            <!-- Delete button for user's own suggestions -->
            <%= if option.suggested_by && @user && Events.can_delete_option_based_on_poll_settings?(option, @user) do %>
              <div class="mt-2 flex items-center space-x-2">
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

            <!-- Embedded Progress Bar -->
            <div class="mt-2">
              <.live_component
                module={EmbeddedProgressBarComponent}
                id={"progress-#{@poll.id}-#{option.id}-star"}
                poll_stats={@poll_stats}
                option_id={option.id}
                voting_system={@poll.voting_system}
                compact={true}
                show_labels={false}
                show_counts={true}
                anonymous_mode={@anonymous_mode}
              />
            </div>
          </div>

          <div class="sm:ml-4 flex !flex-row items-center justify-between sm:justify-start space-x-1">
            <div class="flex !flex-row items-center space-x-1">
              <%= for star <- 1..5 do %>
                <button
                  type="button"
                  phx-click="cast_star_vote"
                  phx-value-option-id={option.id}
                  phx-value-rating={star}
                  phx-target={@myself}
                  disabled={@loading}
                  class={star_class(@vote_state[option.id], star, @anonymous_mode) <> " p-1 sm:p-0 touch-target"}
                  aria-label={"Rate #{star} star#{if star > 1, do: "s"}"}
                  aria-pressed={to_string(@vote_state[option.id] == star)}
                >
                  <svg class="h-6 w-6 sm:h-5 sm:w-5" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                  </svg>
                </button>
              <% end %>
            </div>
            <%= if @vote_state[option.id] do %>
              <button
                type="button"
                phx-click="clear_star_vote"
                phx-value-option-id={option.id}
                phx-target={@myself}
                class="ml-2 text-gray-400 hover:text-gray-600"
                title="Clear rating"
              >
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            <% end %>
            <%= if @anonymous_mode and @vote_state[option.id] do %>
              <div class="ml-2 text-blue-500">
                <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                </svg>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Vote Summary
  defp render_vote_summary(assigns) do
    case assigns.poll.voting_system do
      "binary" -> render_binary_summary(assigns)
      "approval" -> render_approval_summary(assigns)
      "ranked" -> render_ranked_summary(assigns)
      "star" -> render_star_summary(assigns)
    end
  end

  defp render_binary_summary(assigns) do
    ~H"""
    <div class="text-sm">
      <span class="font-medium text-gray-900">Your votes:</span>
      <%= if map_size(@vote_state) > 0 do %>
        <span class="ml-2 text-gray-600">
          <%= for {option_id, vote} <- @vote_state do %>
            <% option = find_poll_option(assigns, option_id) %>
            <%= if option do %>
              <span class={"inline-flex items-center px-2 py-1 rounded-full text-xs font-medium mr-2 #{vote_badge_class(vote)}"}>
                <%= option.title %>: <%= String.capitalize(vote) %>
              </span>
            <% end %>
          <% end %>
        </span>
      <% else %>
        <span class="ml-2 text-gray-500">No votes cast yet</span>
      <% end %>
    </div>
    """
  end

  defp render_approval_summary(assigns) do
    ~H"""
    <div class="text-sm">
      <span class="font-medium text-gray-900">Selected options:</span>
      <%= if map_size(@vote_state) > 0 do %>
        <span class="ml-2 text-gray-600">
          <%= for {option_id, _} <- @vote_state do %>
            <% option = find_poll_option(assigns, option_id) %>
            <%= if option do %>
              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800 mr-2">
                <%= option.title %>
              </span>
            <% end %>
          <% end %>
        </span>
      <% else %>
        <span class="ml-2 text-gray-500">No selections made</span>
      <% end %>
    </div>
    """
  end

  defp render_ranked_summary(assigns) do
    ~H"""
    <div class="text-sm">
      <span class="font-medium text-gray-900">Your ranking:</span>
      <%= if length(@ranked_options) > 0 do %>
        <span class="ml-2 text-gray-600">
          <%= for {option, index} <- Enum.with_index(@ranked_options) do %>
            <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800 mr-2">
              #<%= index + 1 %>: <%= option.title %>
            </span>
          <% end %>
        </span>
      <% else %>
        <span class="ml-2 text-gray-500">No ranking set</span>
      <% end %>
    </div>
    """
  end

  defp render_star_summary(assigns) do
    ~H"""
    <div class="text-sm">
      <span class="font-medium text-gray-900">Your ratings:</span>
      <%= if map_size(@vote_state) > 0 do %>
        <span class="ml-2 text-gray-600">
          <%= for {option_id, rating} <- @vote_state do %>
            <% option = find_poll_option(assigns, option_id) %>
            <%= if option do %>
              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800 mr-2">
                <%= option.title %>: <%= rating %> <%= if rating == 1, do: "star", else: "stars" %>
              </span>
            <% end %>
          <% end %>
        </span>
      <% else %>
        <span class="ml-2 text-gray-500">No ratings given</span>
      <% end %>
    </div>
    """
  end

  defp vote_badge_class(vote) do
    case vote do
      "yes" -> "bg-green-100 text-green-800"
      "no" -> "bg-red-100 text-red-800"
      "maybe" -> "bg-yellow-100 text-yellow-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  # Event Handlers

  @impl true
  def handle_event("cast_binary_vote", %{"option-id" => option_id, "vote" => vote}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id} ->
        if socket.assigns.anonymous_mode do
          handle_anonymous_binary_vote(socket, option_id, vote)
        else
          handle_authenticated_binary_vote(socket, option_id, vote)
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid option ID"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_approval_vote", params, socket) do
    # Extract option-id from params, handling any additional parameters like "value"
    case Map.get(params, "option-id") do
      nil ->
        send(self(), {:show_error, "No option ID provided"})
        {:noreply, socket}

      option_id ->
        case safe_string_to_integer(option_id) do
          {:ok, option_id} ->
            if socket.assigns.anonymous_mode do
              handle_anonymous_approval_vote(socket, option_id)
            else
              handle_authenticated_approval_vote(socket, option_id)
            end

          {:error, _} ->
            send(self(), {:show_error, "Invalid option ID"})
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_event("cast_star_vote", %{"option-id" => option_id, "rating" => rating}, socket) do
    with {:ok, option_id} <- safe_string_to_integer(option_id),
         {:ok, rating} <- safe_string_to_integer(rating) do
      if socket.assigns.anonymous_mode do
        handle_anonymous_star_vote(socket, option_id, rating)
      else
        handle_authenticated_star_vote(socket, option_id, rating)
      end
    else
      {:error, _} ->
        send(self(), {:show_error, "Invalid option ID or rating"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_star_vote", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id} ->
        if socket.assigns.anonymous_mode do
          handle_anonymous_clear_star_vote(socket, option_id)
        else
          handle_authenticated_clear_star_vote(socket, option_id)
        end

      {:error, _} ->
        send(self(), {:show_error, "Invalid option ID"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_save_votes_modal", _params, socket) do
    send(self(), {:show_anonymous_voter_modal, socket.assigns.poll.id, socket.assigns.temp_votes})
    {:noreply, socket}
  end

  # Additional event handlers for ranked voting...
  @impl true
  def handle_event("move_option_up", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id} ->
        new_ranked_options = move_option_up(socket.assigns.ranked_options, option_id)

        if socket.assigns.anonymous_mode do
          # Update temp votes for anonymous users
          temp_votes =
            update_temp_votes_for_ranked(
              socket.assigns.temp_votes,
              new_ranked_options,
              socket.assigns.poll.voting_system
            )

          send(self(), {:temp_votes_updated, socket.assigns.poll.id, temp_votes})

          {:noreply,
           socket
           |> assign(:ranked_options, new_ranked_options)
           |> assign(:temp_votes, temp_votes)
           |> assign(
             :vote_state,
             initialize_anonymous_vote_state(socket.assigns.poll, temp_votes)
           )}
        else
          # Submit for authenticated users
          submit_ranked_votes(socket, new_ranked_options)
          {:noreply, assign(socket, :ranked_options, new_ranked_options)}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_option_down", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id} ->
        new_ranked_options = move_option_down(socket.assigns.ranked_options, option_id)

        if socket.assigns.anonymous_mode do
          # Update temp votes for anonymous users
          temp_votes =
            update_temp_votes_for_ranked(
              socket.assigns.temp_votes,
              new_ranked_options,
              socket.assigns.poll.voting_system
            )

          send(self(), {:temp_votes_updated, socket.assigns.poll.id, temp_votes})

          {:noreply,
           socket
           |> assign(:ranked_options, new_ranked_options)
           |> assign(:temp_votes, temp_votes)
           |> assign(
             :vote_state,
             initialize_anonymous_vote_state(socket.assigns.poll, temp_votes)
           )}
        else
          # Submit for authenticated users
          submit_ranked_votes(socket, new_ranked_options)
          {:noreply, assign(socket, :ranked_options, new_ranked_options)}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_to_ranking", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id} ->
        option = find_poll_option(socket, option_id)
        max_rankings = Poll.get_max_rankings(socket.assigns.poll)

        if option &&
             not Enum.any?(socket.assigns.ranked_options, &(&1.id == option_id)) &&
             can_add_more_rankings?(socket.assigns.ranked_options, max_rankings) do
          new_ranked_options = socket.assigns.ranked_options ++ [option]

          if socket.assigns.anonymous_mode do
            # Update temp votes for anonymous users
            temp_votes =
              update_temp_votes_for_ranked(
                socket.assigns.temp_votes,
                new_ranked_options,
                socket.assigns.poll.voting_system
              )

            send(self(), {:temp_votes_updated, socket.assigns.poll.id, temp_votes})

            {:noreply,
             socket
             |> assign(:ranked_options, new_ranked_options)
             |> assign(:temp_votes, temp_votes)
             |> assign(
               :vote_state,
               initialize_anonymous_vote_state(socket.assigns.poll, temp_votes)
             )}
          else
            # Submit for authenticated users
            submit_ranked_votes(socket, new_ranked_options)
            {:noreply, assign(socket, :ranked_options, new_ranked_options)}
          end
        else
          {:noreply, socket}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_from_ranking", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id} ->
        new_ranked_options = Enum.reject(socket.assigns.ranked_options, &(&1.id == option_id))

        if socket.assigns.anonymous_mode do
          # Update temp votes for anonymous users
          temp_votes =
            update_temp_votes_for_ranked(
              socket.assigns.temp_votes,
              new_ranked_options,
              socket.assigns.poll.voting_system
            )

          send(self(), {:temp_votes_updated, socket.assigns.poll.id, temp_votes})

          {:noreply,
           socket
           |> assign(:ranked_options, new_ranked_options)
           |> assign(:temp_votes, temp_votes)
           |> assign(
             :vote_state,
             initialize_anonymous_vote_state(socket.assigns.poll, temp_votes)
           )}
        else
          # Submit for authenticated users
          submit_ranked_votes(socket, new_ranked_options)
          {:noreply, assign(socket, :ranked_options, new_ranked_options)}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    with {option_id_int, _} <- Integer.parse(option_id),
         option when not is_nil(option) <-
           Enum.find(socket.assigns.poll.poll_options, &(&1.id == option_id_int)),
         true <- Events.can_delete_option_based_on_poll_settings?(option, socket.assigns.user) do
      case Events.delete_poll_option(option) do
        {:ok, _} ->
          # Send message to parent to reload poll
          send(self(), {:poll_stats_updated, socket.assigns.poll.id, %{}})

          {:noreply, socket}

        {:error, _} ->
          send(self(), {:show_error, "Failed to remove option"})
          {:noreply, socket}
      end
    else
      _ ->
        send(self(), {:show_error, "You are not authorized to remove this option"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_all_votes", _params, socket) do
    if socket.assigns.anonymous_mode do
      # Clear temp votes for anonymous users
      empty_temp_votes = %{}
      send(self(), {:temp_votes_updated, socket.assigns.poll.id, empty_temp_votes})

      {:noreply,
       socket
       |> assign(:temp_votes, empty_temp_votes)
       |> assign(:vote_state, %{})
       |> assign(:ranked_options, [])}
    else
      # Clear authenticated user votes
      socket = assign(socket, :loading, true)

      {:ok, _} = clear_all_user_votes(socket)
      send(self(), {:votes_cleared})

      {:noreply,
       socket
       |> assign(:loading, false)
       |> assign(:vote_state, %{})
       |> assign(:ranked_options, [])}
    end
  end

  # Event handler to stop propagation for movie links in voting interfaces
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  # Note: LiveComponents don't support handle_info callbacks
  # Real-time updates are handled by the parent LiveView which reloads the poll data

  # Anonymous vote handlers

  defp handle_anonymous_binary_vote(socket, option_id, vote) do
    new_vote_state = Map.put(socket.assigns.vote_state, option_id, vote)
    new_temp_votes = Map.put(socket.assigns.temp_votes, option_id, vote)

    send(self(), {:temp_votes_updated, socket.assigns.poll.id, new_temp_votes})

    {:noreply,
     socket
     |> assign(:vote_state, new_vote_state)
     |> assign(:temp_votes, new_temp_votes)}
  end

  defp handle_anonymous_approval_vote(socket, option_id) do
    current_vote = socket.assigns.vote_state[option_id]
    new_vote = if current_vote == "approved", do: nil, else: "approved"

    new_vote_state =
      if new_vote do
        Map.put(socket.assigns.vote_state, option_id, new_vote)
      else
        Map.delete(socket.assigns.vote_state, option_id)
      end

    new_temp_votes =
      if new_vote do
        Map.put(socket.assigns.temp_votes, option_id, "selected")
      else
        Map.delete(socket.assigns.temp_votes, option_id)
      end

    send(self(), {:temp_votes_updated, socket.assigns.poll.id, new_temp_votes})

    {:noreply,
     socket
     |> assign(:vote_state, new_vote_state)
     |> assign(:temp_votes, new_temp_votes)}
  end

  defp handle_anonymous_star_vote(socket, option_id, rating) do
    new_vote_state = Map.put(socket.assigns.vote_state, option_id, rating)
    new_temp_votes = Map.put(socket.assigns.temp_votes, option_id, rating)

    send(self(), {:temp_votes_updated, socket.assigns.poll.id, new_temp_votes})

    {:noreply,
     socket
     |> assign(:vote_state, new_vote_state)
     |> assign(:temp_votes, new_temp_votes)}
  end

  defp handle_anonymous_clear_star_vote(socket, option_id) do
    new_vote_state = Map.delete(socket.assigns.vote_state, option_id)
    new_temp_votes = Map.delete(socket.assigns.temp_votes, option_id)

    send(self(), {:temp_votes_updated, socket.assigns.poll.id, new_temp_votes})

    {:noreply,
     socket
     |> assign(:vote_state, new_vote_state)
     |> assign(:temp_votes, new_temp_votes)}
  end

  # Authenticated vote handlers

  defp handle_authenticated_binary_vote(socket, option_id, vote_value) do
    socket = assign(socket, :loading, true)

    case submit_binary_vote(socket, option_id, vote_value) do
      {:ok, _vote} ->
        new_vote_state = Map.put(socket.assigns.vote_state, option_id, vote_value)
        send(self(), {:vote_cast, option_id, vote_value})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:vote_state, new_vote_state)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to cast vote"})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  defp handle_authenticated_approval_vote(socket, option_id) do
    current_vote = socket.assigns.vote_state[option_id]
    new_vote = if current_vote == "approved", do: nil, else: "approved"

    socket = assign(socket, :loading, true)

    case submit_approval_vote(socket, option_id, new_vote) do
      {:ok, _} ->
        new_vote_state =
          if new_vote do
            Map.put(socket.assigns.vote_state, option_id, new_vote)
          else
            Map.delete(socket.assigns.vote_state, option_id)
          end

        send(self(), {:vote_cast, option_id, new_vote})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:vote_state, new_vote_state)}

      {:error, :option_not_found} ->
        send(self(), {:show_error, "Option not found"})
        {:noreply, assign(socket, :loading, false)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to update vote"})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  defp handle_authenticated_star_vote(socket, option_id, rating) do
    socket = assign(socket, :loading, true)

    case submit_star_vote(socket, option_id, rating) do
      {:ok, _vote} ->
        new_vote_state = Map.put(socket.assigns.vote_state, option_id, rating)
        send(self(), {:vote_cast, option_id, rating})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:vote_state, new_vote_state)}

      {:error, :option_not_found} ->
        send(self(), {:show_error, "Option not found"})
        {:noreply, assign(socket, :loading, false)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to cast vote"})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  defp handle_authenticated_clear_star_vote(socket, option_id) do
    case clear_vote(socket, option_id) do
      {:ok, _} ->
        new_vote_state = Map.delete(socket.assigns.vote_state, option_id)
        send(self(), {:vote_cleared, option_id})

        {:noreply, assign(socket, :vote_state, new_vote_state)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to clear vote"})
        {:noreply, socket}
    end
  end

  # Helper functions

  defp initialize_anonymous_vote_state(poll, temp_votes) do
    case poll.voting_system do
      "binary" ->
        temp_votes

      "approval" ->
        for {option_id, _} <- temp_votes, into: %{} do
          {option_id, "approved"}
        end

      "star" ->
        temp_votes

      "ranked" ->
        case temp_votes do
          %{poll_type: :ranked, votes: votes} when is_list(votes) ->
            for %{option_id: option_id, rank: rank} <- votes, into: %{} do
              {option_id, rank}
            end

          %{poll_type: :ranked, votes: votes} when is_map(votes) ->
            votes

          _ ->
            %{}
        end
    end
  end

  defp initialize_anonymous_ranked_options(poll_options, temp_votes) do
    case temp_votes do
      %{poll_type: :ranked, votes: votes} when is_list(votes) ->
        # Sort by rank and find corresponding options
        votes
        |> Enum.sort_by(& &1.rank)
        |> Enum.map(fn %{option_id: option_id} ->
          Enum.find(poll_options, &(&1.id == option_id))
        end)
        |> Enum.reject(&is_nil/1)

      %{poll_type: :ranked, votes: votes} when is_map(votes) ->
        # Convert map format to list and sort by rank
        votes
        |> Enum.sort_by(fn {_option_id, rank} -> rank end)
        |> Enum.map(fn {option_id, _rank} ->
          Enum.find(poll_options, &(&1.id == option_id))
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp has_temp_votes?(temp_votes, _voting_system) do
    case temp_votes do
      %{poll_type: :ranked, votes: votes} when is_list(votes) ->
        length(votes) > 0

      %{poll_type: :ranked, votes: votes} when is_map(votes) ->
        map_size(votes) > 0

      votes when is_map(votes) ->
        map_size(votes) > 0

      _ ->
        false
    end
  end

  defp update_temp_votes_for_ranked(temp_votes, ranked_options, voting_system) do
    case voting_system do
      "ranked" ->
        ranked_votes =
          ranked_options
          |> Enum.with_index(1)
          |> Enum.map(fn {option, rank} ->
            %{option_id: option.id, rank: rank}
          end)

        %{
          poll_type: :ranked,
          votes: ranked_votes
        }

      _ ->
        temp_votes
    end
  end

  # Existing helper functions...
  defp initialize_vote_state(poll, user_votes) do
    case poll.voting_system do
      "binary" ->
        user_votes
        |> Enum.map(fn vote -> {vote.poll_option_id, vote.vote_value} end)
        |> Map.new()

      "approval" ->
        user_votes
        |> Enum.map(fn vote -> {vote.poll_option_id, "approved"} end)
        |> Map.new()

      "star" ->
        user_votes
        |> Enum.map(fn vote -> {vote.poll_option_id, safe_to_integer(vote.vote_numeric)} end)
        |> Map.new()

      "ranked" ->
        user_votes
        |> Enum.map(fn vote -> {vote.poll_option_id, vote.vote_rank} end)
        |> Map.new()
    end
  end

  defp initialize_ranked_options(poll_options, user_votes) do
    options_map = poll_options |> Enum.map(&{&1.id, &1}) |> Map.new()

    user_votes
    |> Enum.sort_by(& &1.vote_rank)
    |> Enum.map(fn vote ->
      Map.get(options_map, vote.poll_option_id)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp submit_binary_vote(socket, option_id, vote_value) do
    case find_poll_option(socket, option_id) do
      nil ->
        {:error, :option_not_found}

      option ->
        Events.cast_binary_vote(socket.assigns.poll, option, socket.assigns.user, vote_value)
    end
  end

  defp submit_approval_vote(socket, option_id, vote_value) do
    case find_poll_option(socket, option_id) do
      nil ->
        {:error, :option_not_found}

      option ->
        if vote_value do
          Events.cast_approval_vote(socket.assigns.poll, option, socket.assigns.user, true)
        else
          case Events.get_user_poll_vote(option, socket.assigns.user) do
            nil -> {:ok, nil}
            existing_vote -> Events.delete_poll_vote(existing_vote)
          end
        end
    end
  end

  defp submit_star_vote(socket, option_id, rating) do
    case find_poll_option(socket, option_id) do
      nil -> {:error, :option_not_found}
      option -> Events.cast_star_vote(socket.assigns.poll, option, socket.assigns.user, rating)
    end
  end

  defp submit_ranked_votes(socket, ranked_options) do
    # Prepare ranked options with their ranks
    ranked_options_with_ranks =
      ranked_options
      |> Enum.with_index(1)
      |> Enum.map(fn {option, rank} -> {option.id, rank} end)

    Events.cast_ranked_votes(socket.assigns.poll, ranked_options_with_ranks, socket.assigns.user)
  end

  defp clear_vote(socket, option_id) do
    case find_poll_option(socket, option_id) do
      nil ->
        {:ok, nil}

      option ->
        case Events.get_user_poll_vote(option, socket.assigns.user) do
          nil -> {:ok, nil}
          existing_vote -> Events.delete_poll_vote(existing_vote)
        end
    end
  end

  defp find_poll_option(socket_or_assigns, option_id) do
    poll_options =
      case socket_or_assigns do
        %Phoenix.LiveView.Socket{assigns: %{poll: %{poll_options: options}}} -> options
        %{poll: %{poll_options: options}} -> options
        _ -> []
      end

    Enum.find(poll_options, &(&1.id == option_id))
  end

  defp clear_all_user_votes(socket) do
    Events.clear_user_poll_votes(socket.assigns.poll, socket.assigns.user)
  end

  defp get_unranked_options(all_options, ranked_options) do
    ranked_ids = Enum.map(ranked_options, & &1.id)
    Enum.reject(all_options, &(&1.id in ranked_ids))
  end

  defp move_option_up(ranked_options, option_id) do
    case Enum.find_index(ranked_options, &(&1.id == option_id)) do
      # Already at top
      0 ->
        ranked_options

      # Option not found
      nil ->
        ranked_options

      index ->
        ranked_options
        |> List.pop_at(index)
        |> elem(1)
        |> List.insert_at(index - 1, Enum.at(ranked_options, index))
    end
  end

  defp move_option_down(ranked_options, option_id) do
    case Enum.find_index(ranked_options, &(&1.id == option_id)) do
      # Option not found
      nil ->
        ranked_options

      # Already at bottom
      index when index == length(ranked_options) - 1 ->
        ranked_options

      index ->
        ranked_options
        |> List.pop_at(index)
        |> elem(1)
        |> List.insert_at(index + 1, Enum.at(ranked_options, index))
    end
  end

  # Helper function to check if more rankings can be added
  defp can_add_more_rankings?(ranked_options, max_rankings) when is_integer(max_rankings) do
    length(ranked_options) < max_rankings
  end

  # No limit for non-ranked polls
  defp can_add_more_rankings?(_, nil), do: true

  # UI Helper Functions

  defp get_voting_title(voting_system) do
    case voting_system do
      "binary" -> "Cast Your Votes"
      "approval" -> "Select Your Choices"
      "ranked" -> "Rank Your Preferences"
      "star" -> "Rate the Options"
    end
  end

  defp get_voting_instructions(voting_system) do
    case voting_system do
      "binary" -> "Vote yes, maybe, or no for each option"
      "approval" -> "Check all options you approve of"
      "ranked" -> "Use arrows to rank options in order of preference"
      "star" -> "Rate each option from 1 to 5 stars"
    end
  end

  defp binary_button_class(current_vote, vote_type, anonymous_mode) do
    base_classes =
      "inline-flex items-center px-3 py-2 border text-sm leading-4 font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"

    if current_vote == vote_type do
      active_classes =
        case vote_type do
          "yes" -> " border-green-500 text-green-700 bg-green-50"
          "no" -> " border-red-500 text-red-700 bg-red-50"
          "maybe" -> " border-yellow-500 text-yellow-700 bg-yellow-50"
        end

      # Add subtle indicator for anonymous mode
      if anonymous_mode do
        base_classes <> active_classes <> " ring-2 ring-blue-200"
      else
        base_classes <> active_classes
      end
    else
      base_classes <> " border-gray-300 text-gray-700 bg-white hover:bg-gray-50"
    end
  end

  defp approval_checkbox_class(current_vote, anonymous_mode) do
    base_classes = "h-4 w-4 border-gray-300 rounded focus:ring-indigo-500"

    if anonymous_mode and current_vote == "approved" do
      base_classes <> " text-blue-600 focus:ring-blue-500"
    else
      base_classes <> " text-indigo-600 focus:ring-indigo-500"
    end
  end

  defp star_class(current_rating, star_position, anonymous_mode) do
    base_classes = "focus:outline-none"

    # Ensure current_rating is an integer for proper comparison
    current_rating = safe_to_integer(current_rating)

    if current_rating && current_rating >= star_position do
      if anonymous_mode do
        base_classes <> " text-blue-400 hover:text-blue-500"
      else
        base_classes <> " text-yellow-400 hover:text-yellow-500"
      end
    else
      base_classes <> " text-gray-300 hover:text-yellow-400"
    end
  end

  defp has_votes?(vote_state, voting_system) do
    case voting_system do
      "ranked" -> map_size(vote_state) > 0
      _ -> map_size(vote_state) > 0
    end
  end

  defp safe_string_to_integer(string) do
    case Integer.parse(string) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp has_time_slots?(option) do
    case option.metadata do
      %{"time_enabled" => true, "time_slots" => time_slots}
      when is_list(time_slots) and length(time_slots) > 0 ->
        true

      _ ->
        false
    end
  end

  defp get_time_slots_from_option(option) do
    case option.metadata do
      %{"time_enabled" => true, "time_slots" => time_slots} when is_list(time_slots) ->
        time_slots

      _ ->
        []
    end
  end

  defp format_time_slot_display(slot) when is_map(slot) do
    case {slot["start_time"], slot["end_time"]} do
      {start_time, end_time} when is_binary(start_time) and is_binary(end_time) ->
        # Use 24-hour format for display (European standard)
        "#{start_time} - #{end_time}"

      _ ->
        "Invalid time slot"
    end
  end

  defp format_time_slot_display(_), do: "Invalid time slot"

  defp safe_to_integer(value) do
    case value do
      rating when is_integer(rating) ->
        rating

      rating when is_binary(rating) ->
        case Integer.parse(rating) do
          {int, ""} -> int
          _ -> nil
        end

      %Decimal{} = rating ->
        try do
          Decimal.to_integer(rating)
        rescue
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # Helper functions for deletion time display
  defp get_deletion_time_remaining(inserted_at) when is_nil(inserted_at), do: 0

  defp get_deletion_time_remaining(inserted_at) do
    elapsed_seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), inserted_at, :second)
    # Use < 300 to match original time-based deletion boundary condition (≤ 300)
    # When elapsed_seconds = 300, remaining = 0, so button disappears at same time as countdown
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
