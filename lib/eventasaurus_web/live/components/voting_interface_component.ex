defmodule EventasaurusWeb.VotingInterfaceComponent do
  @moduledoc """
  A reusable LiveView component for handling different voting systems in polls.

  Provides specialized interfaces for binary, approval, ranked choice, and star rating
  voting systems. Handles user vote state, submission, and real-time updates.

  ## Attributes:
  - poll: Poll struct with preloaded options and votes (required)
  - user: User struct (required)
  - user_votes: List of user's existing votes for this poll
  - loading: Whether a vote operation is in progress

  ## Usage:
      <.live_component
        module={EventasaurusWeb.VotingInterfaceComponent}
        id="voting-interface"
        poll={@poll}
        user={@user}
        user_votes={@user_votes}
        loading={@loading}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.PollVote

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:vote_state, %{})
     |> assign(:ranked_options, [])}
  end

  @impl true
  def update(assigns, socket) do
    # Initialize vote state based on existing user votes
    vote_state = initialize_vote_state(assigns.poll, assigns.user_votes)

    # For ranked voting, initialize ordered options
    ranked_options = case assigns.poll.voting_system do
      "ranked" -> initialize_ranked_options(assigns.poll.poll_options, assigns.user_votes)
      _ -> []
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:vote_state, vote_state)
     |> assign(:ranked_options, ranked_options)
     |> assign_new(:loading, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg">
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-lg font-medium text-gray-900">
              <%= get_voting_title(@poll.voting_system) %>
            </h3>
            <p class="text-sm text-gray-500">
              <%= get_voting_instructions(@poll.voting_system) %>
            </p>
          </div>

          <%= if has_votes?(@vote_state, @poll.voting_system) do %>
            <button
              type="button"
              phx-click="clear_all_votes"
              phx-target={@myself}
              data-confirm="Are you sure you want to clear all your votes?"
              class="text-sm text-red-600 hover:text-red-900 font-medium"
            >
              Clear All Votes
            </button>
          <% end %>
        </div>
      </div>

      <!-- Voting Interface -->
      <div class="divide-y divide-gray-200">
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
      <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
        <%= render_vote_summary(assigns) %>
      </div>
    </div>
    """
  end

  # Binary Voting (Yes/No)
  defp render_binary_voting(assigns) do
    ~H"""
    <%= for option <- @poll.poll_options do %>
      <div class="px-6 py-4">
        <div class="flex items-center justify-between">
          <div class="flex-1 min-w-0">
            <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
            <%= if option.description do %>
              <p class="text-sm text-gray-500 mt-1"><%= option.description %></p>
            <% end %>
          </div>

          <div class="ml-4 flex space-x-3">
            <button
              type="button"
              phx-click="cast_binary_vote"
              phx-value-option-id={option.id}
              phx-value-vote="yes"
              phx-target={@myself}
              disabled={@loading}
              class={binary_button_class(@vote_state[option.id], "yes")}
            >
              <svg class="h-5 w-5 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              Yes
            </button>

            <button
              type="button"
              phx-click="cast_binary_vote"
              phx-value-option-id={option.id}
              phx-value-vote="no"
              phx-target={@myself}
              disabled={@loading}
              class={binary_button_class(@vote_state[option.id], "no")}
            >
              <svg class="h-5 w-5 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
              No
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
      <div class="px-6 py-4">
        <label class="flex items-center cursor-pointer hover:bg-gray-50 -mx-2 px-2 py-2 rounded">
          <input
            type="checkbox"
            phx-click="toggle_approval_vote"
            phx-value-option-id={option.id}
            phx-target={@myself}
            checked={@vote_state[option.id] == "approved"}
            disabled={@loading}
            class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"
          />
          <div class="ml-3 flex-1 min-w-0">
            <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
            <%= if option.description do %>
              <p class="text-sm text-gray-500 mt-1"><%= option.description %></p>
            <% end %>
          </div>
        </label>
      </div>
    <% end %>
    """
  end

  # Ranked Choice Voting (Drag and drop)
  defp render_ranked_voting(assigns) do
    ~H"""
    <div class="px-6 py-4">
      <div class="space-y-4">
        <!-- Instructions -->
        <div class="bg-blue-50 border border-blue-200 rounded-md p-4">
          <div class="flex">
            <svg class="h-5 w-5 text-blue-400" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
            </svg>
            <div class="ml-3">
              <p class="text-sm text-blue-800">
                Use the up/down arrows to rank options in order of preference (1st choice at top). Unranked options won't receive votes.
              </p>
            </div>
          </div>
        </div>

        <!-- Ranked Options -->
        <div class="space-y-2">
          <%= for {option, index} <- Enum.with_index(@ranked_options) do %>
            <div class="flex items-center p-3 bg-white border border-gray-200 rounded-lg shadow-sm">
              <div class="flex items-center justify-center w-8 h-8 bg-indigo-100 text-indigo-800 text-sm font-medium rounded-full mr-3">
                <%= index + 1 %>
              </div>
              <div class="flex-1 min-w-0">
                <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
                <%= if option.description do %>
                  <p class="text-xs text-gray-500 mt-1"><%= option.description %></p>
                <% end %>
              </div>
              <div class="ml-3 flex items-center space-x-2">
                <%= if index > 0 do %>
                  <button
                    type="button"
                    phx-click="move_option_up"
                    phx-value-option-id={option.id}
                    phx-target={@myself}
                    class="text-gray-400 hover:text-gray-600"
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
                    class="text-gray-400 hover:text-gray-600"
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
                  class="text-red-400 hover:text-red-600"
                  title="Remove from ranking"
                >
                  <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Unranked Options -->
        <%= if length(@ranked_options) < length(@poll.poll_options) do %>
          <div class="border-t border-gray-200 pt-4">
            <h5 class="text-sm font-medium text-gray-700 mb-2">Unranked Options</h5>
            <div class="space-y-2">
              <%= for option <- get_unranked_options(@poll.poll_options, @ranked_options) do %>
                <div class="flex items-center p-3 bg-gray-50 border border-gray-200 rounded-lg">
                  <div class="flex-1 min-w-0">
                    <h4 class="text-sm font-medium text-gray-600"><%= option.title %></h4>
                  </div>
                  <button
                    type="button"
                    phx-click="add_to_ranking"
                    phx-value-option-id={option.id}
                    phx-target={@myself}
                    class="ml-3 text-sm text-indigo-600 hover:text-indigo-900 font-medium"
                  >
                    Add to Ranking
                  </button>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Submit Ranking Button -->
        <div class="pt-4">
          <button
            type="button"
            phx-click="submit_ranked_votes"
            phx-target={@myself}
            disabled={@loading || Enum.empty?(@ranked_options)}
            class="w-full inline-flex justify-center items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <%= if @loading do %>
              <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Submitting Ranking...
            <% else %>
              Submit Ranking (<%= length(@ranked_options) %> ranked)
            <% end %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Star Rating (1-5 stars)
  defp render_star_voting(assigns) do
    ~H"""
    <%= for option <- @poll.poll_options do %>
      <div class="px-6 py-4">
        <div class="flex items-start justify-between">
          <div class="flex-1 min-w-0 mr-4">
            <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
            <%= if option.description do %>
              <p class="text-sm text-gray-500 mt-1"><%= option.description %></p>
            <% end %>
          </div>

          <div class="flex items-center space-x-1">
            <%= for star <- 1..5 do %>
              <button
                type="button"
                phx-click="cast_star_vote"
                phx-value-option-id={option.id}
                phx-value-rating={star}
                phx-target={@myself}
                disabled={@loading}
                class={star_class(@vote_state[option.id], star)}
              >
                <svg class="h-6 w-6" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                </svg>
              </button>
            <% end %>

            <%= if @vote_state[option.id] do %>
              <span class="ml-2 text-sm text-gray-600">
                (<%= @vote_state[option.id] %>/5)
              </span>
              <button
                type="button"
                phx-click="clear_star_vote"
                phx-value-option-id={option.id}
                phx-target={@myself}
                class="ml-2 text-xs text-red-600 hover:text-red-900"
              >
                Clear
              </button>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Vote Summary
  defp render_vote_summary(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <div class="text-sm text-gray-500">
        <%= get_vote_summary_text(@vote_state, @poll.voting_system) %>
      </div>

      <%= if @poll.voting_deadline do %>
        <div class="text-sm text-gray-500">
          Voting ends: <%= format_deadline(@poll.voting_deadline) %>
        </div>
      <% end %>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("cast_binary_vote", %{"option-id" => option_id, "vote" => vote}, socket) do
    socket = assign(socket, :loading, true)
    option_id = String.to_integer(option_id)

    case submit_binary_vote(socket, option_id, vote) do
      {:ok, _vote} ->
        new_vote_state = Map.put(socket.assigns.vote_state, option_id, vote)
        send(self(), {:vote_cast, option_id, vote})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:vote_state, new_vote_state)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to cast vote"})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  @impl true
  def handle_event("toggle_approval_vote", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)
    current_vote = socket.assigns.vote_state[option_id]
    new_vote = if current_vote == "approved", do: nil, else: "approved"

    socket = assign(socket, :loading, true)

    case submit_approval_vote(socket, option_id, new_vote) do
      {:ok, _} ->
        new_vote_state = if new_vote do
          Map.put(socket.assigns.vote_state, option_id, new_vote)
        else
          Map.delete(socket.assigns.vote_state, option_id)
        end

        send(self(), {:vote_cast, option_id, new_vote})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:vote_state, new_vote_state)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to update vote"})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  @impl true
  def handle_event("cast_star_vote", %{"option-id" => option_id, "rating" => rating}, socket) do
    socket = assign(socket, :loading, true)
    option_id = String.to_integer(option_id)
    rating = String.to_integer(rating)

    case submit_star_vote(socket, option_id, rating) do
      {:ok, _vote} ->
        new_vote_state = Map.put(socket.assigns.vote_state, option_id, rating)
        send(self(), {:vote_cast, option_id, rating})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:vote_state, new_vote_state)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to cast vote"})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  @impl true
  def handle_event("clear_star_vote", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)

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

  @impl true
  def handle_event("add_to_ranking", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)
    option = Enum.find(socket.assigns.poll.poll_options, &(&1.id == option_id))

    if option do
      new_ranked_options = socket.assigns.ranked_options ++ [option]
      {:noreply, assign(socket, :ranked_options, new_ranked_options)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit_ranked_votes", _params, socket) do
    socket = assign(socket, :loading, true)

    case submit_ranked_votes(socket) do
      {:ok, _} ->
        send(self(), {:ranked_votes_submitted})
        {:noreply, assign(socket, :loading, false)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to submit ranking"})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  @impl true
  def handle_event("move_option_up", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)
    ranked_options = socket.assigns.ranked_options

    case Enum.find_index(ranked_options, &(&1.id == option_id)) do
      nil -> {:noreply, socket}
      0 -> {:noreply, socket}  # Already at top
      index ->
        new_ranked_options = ranked_options
        |> List.delete_at(index)
        |> List.insert_at(index - 1, Enum.at(ranked_options, index))

        {:noreply, assign(socket, :ranked_options, new_ranked_options)}
    end
  end

  @impl true
  def handle_event("move_option_down", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)
    ranked_options = socket.assigns.ranked_options

    case Enum.find_index(ranked_options, &(&1.id == option_id)) do
      nil -> {:noreply, socket}
      index when index == length(ranked_options) - 1 -> {:noreply, socket}  # Already at bottom
      index ->
        new_ranked_options = ranked_options
        |> List.delete_at(index)
        |> List.insert_at(index + 1, Enum.at(ranked_options, index))

        {:noreply, assign(socket, :ranked_options, new_ranked_options)}
    end
  end

  @impl true
  def handle_event("remove_from_ranking", %{"option-id" => option_id}, socket) do
    option_id = String.to_integer(option_id)
    new_ranked_options = Enum.reject(socket.assigns.ranked_options, &(&1.id == option_id))
    {:noreply, assign(socket, :ranked_options, new_ranked_options)}
  end

  @impl true
  def handle_event("clear_all_votes", _params, socket) do
    case clear_all_user_votes(socket) do
      {:ok, _} ->
        empty_state = case socket.assigns.poll.voting_system do
          "ranked" -> %{}
          _ -> %{}
        end

        send(self(), {:all_votes_cleared})
        {:noreply, assign(socket, :vote_state, empty_state)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to clear votes"})
        {:noreply, socket}
    end
  end

  # Private helper functions

  defp initialize_vote_state(poll, user_votes) do
    case poll.voting_system do
      "binary" ->
        user_votes
        |> Enum.reduce(%{}, fn vote, acc ->
          Map.put(acc, vote.poll_option_id, vote.vote_value)
        end)

      "approval" ->
        user_votes
        |> Enum.reduce(%{}, fn vote, acc ->
          Map.put(acc, vote.poll_option_id, "approved")
        end)

      "star" ->
        user_votes
        |> Enum.reduce(%{}, fn vote, acc ->
          rating = vote.vote_numeric |> Decimal.to_integer()
          Map.put(acc, vote.poll_option_id, rating)
        end)

      "ranked" ->
        # For ranked voting, we manage state differently
        %{}
    end
  end

  defp initialize_ranked_options(poll_options, user_votes) do
    # Sort user votes by rank and return corresponding options
    user_votes
    |> Enum.sort_by(& &1.vote_rank)
    |> Enum.map(fn vote ->
      Enum.find(poll_options, &(&1.id == vote.poll_option_id))
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp submit_binary_vote(socket, option_id, vote_value) do
    option = Enum.find(socket.assigns.poll.poll_options, &(&1.id == option_id))
    Events.cast_binary_vote(socket.assigns.poll, option, socket.assigns.user, vote_value)
  end

  defp submit_approval_vote(socket, option_id, vote_value) do
    option = Enum.find(socket.assigns.poll.poll_options, &(&1.id == option_id))

    if vote_value do
      Events.cast_approval_vote(socket.assigns.poll, option, socket.assigns.user, true)
    else
      Events.remove_user_vote(option, socket.assigns.user)
    end
  end

  defp submit_star_vote(socket, option_id, rating) do
    option = Enum.find(socket.assigns.poll.poll_options, &(&1.id == option_id))
    Events.cast_star_vote(socket.assigns.poll, option, socket.assigns.user, rating)
  end

  defp submit_ranked_votes(socket) do
    # Prepare ranked options with their ranks
    ranked_options = socket.assigns.ranked_options
    |> Enum.with_index(1)
    |> Enum.map(fn {option, rank} -> {option.id, rank} end)

    Events.cast_ranked_votes(socket.assigns.poll, ranked_options, socket.assigns.user)
  end

  defp clear_vote(socket, option_id) do
    option = Enum.find(socket.assigns.poll.poll_options, &(&1.id == option_id))
    case option do
      nil -> {:ok, nil}
      option -> Events.remove_user_vote(option, socket.assigns.user)
    end
  end

  defp clear_all_user_votes(socket) do
    Events.clear_user_poll_votes(socket.assigns.poll, socket.assigns.user)
  end

  defp get_unranked_options(all_options, ranked_options) do
    ranked_ids = Enum.map(ranked_options, & &1.id)
    Enum.reject(all_options, &(&1.id in ranked_ids))
  end

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
      "binary" -> "Vote yes or no for each option"
      "approval" -> "Check all options you approve of"
      "ranked" -> "Use arrows to rank options in order of preference"
      "star" -> "Rate each option from 1 to 5 stars"
    end
  end

  defp binary_button_class(current_vote, vote_type) do
    base_classes = "inline-flex items-center px-3 py-2 border text-sm leading-4 font-medium rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"

    if current_vote == vote_type do
      case vote_type do
        "yes" -> base_classes <> " border-green-500 text-green-700 bg-green-50"
        "no" -> base_classes <> " border-red-500 text-red-700 bg-red-50"
      end
    else
      base_classes <> " border-gray-300 text-gray-700 bg-white hover:bg-gray-50"
    end
  end

  defp star_class(current_rating, star_position) do
    base_classes = "text-gray-300 hover:text-yellow-400 focus:outline-none"

    if current_rating && current_rating >= star_position do
      "text-yellow-400 " <> base_classes
    else
      base_classes
    end
  end

  defp has_votes?(vote_state, voting_system) do
    case voting_system do
      "ranked" -> false  # Managed separately
      _ -> !Enum.empty?(vote_state)
    end
  end

  defp get_vote_summary_text(vote_state, voting_system) do
    case voting_system do
      "binary" ->
        vote_count = Enum.count(vote_state)
        if vote_count == 0, do: "No votes cast", else: "#{vote_count} votes cast"

      "approval" ->
        approved_count = Enum.count(vote_state)
        if approved_count == 0, do: "No options selected", else: "#{approved_count} options approved"

      "star" ->
        rated_count = Enum.count(vote_state)
        if rated_count == 0, do: "No ratings given", else: "#{rated_count} options rated"

      "ranked" ->
        "Add options to ranking and use arrows to reorder"
    end
  end

  defp format_deadline(deadline) do
    case deadline do
      %DateTime{} = dt ->
        dt
        |> DateTime.to_date()
        |> Date.to_string()

      _ -> "Not set"
    end
  end
end
