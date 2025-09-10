defmodule EventasaurusWeb.VoteConfirmationDialogComponent do
  @moduledoc """
  A reusable LiveView component for confirming poll votes.

  This component displays a confirmation dialog that shows what the user is about to vote for
  and requires explicit confirmation before the vote is cast. It supports all voting systems
  (binary, approval, ranked, star) and provides context about the vote being confirmed.

  ## Attributes:
  - show: Whether to show the dialog (required)
  - poll: Poll struct (required)
  - option: Poll option being voted on (required for non-ranked votes)
  - vote_data: Map containing vote information (required)
  - voting_system: The poll's voting system (required)
  - anonymous_mode: Whether user is in anonymous mode (default: false)

  ## Vote Data Structure:
  - Binary: %{type: "binary", option_id: 123, vote: "yes"}
  - Approval: %{type: "approval", option_id: 123, vote: "approved"}
  - Star: %{type: "star", option_id: 123, rating: 4}
  - Ranked: %{type: "ranked", ranked_options: [option1, option2, ...]}
  - Clear: %{type: "clear", option_id: 123} or %{type: "clear_all"}

  ## Usage:
      <.live_component
        module={EventasaurusWeb.VoteConfirmationDialogComponent}
        id="vote-confirmation"
        show={@show_confirmation}
        poll={@poll}
        option={@option}
        vote_data={@vote_data}
        voting_system={@poll.voting_system}
        anonymous_mode={@anonymous_mode}
      />
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusWeb.Utils.MovieUtils

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:anonymous_mode, fn -> false end)
     |> assign_new(:show, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @show do %>
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity z-40" phx-click="close_confirmation" phx-target={@myself}></div>
      
      <!-- Dialog -->
      <div class="fixed inset-0 z-50 overflow-y-auto">
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <div class="relative transform overflow-hidden rounded-lg bg-white text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg">
            <!-- Header -->
            <div class="bg-white px-4 pb-4 pt-5 sm:p-6 sm:pb-4">
              <div class="sm:flex sm:items-start">
                <div class="mx-auto flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-yellow-100 sm:mx-0 sm:h-10 sm:w-10">
                  <svg class="h-6 w-6 text-yellow-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 18.5c-.77.833.192 2.5 1.732 2.5z" />
                  </svg>
                </div>
                <div class="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left flex-1">
                  <h3 class="text-lg font-medium leading-6 text-gray-900">
                    Confirm Your Vote
                  </h3>
                  <div class="mt-2">
                    <%= render_vote_confirmation_details(assigns) %>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Footer -->
            <div class="bg-gray-50 px-4 py-3 sm:flex sm:flex-row-reverse sm:px-6 gap-3">
              <button
                type="button"
                phx-click="confirm_vote"
                phx-target={@myself}
                class="inline-flex w-full justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 sm:w-auto"
              >
                <%= if @anonymous_mode do %>
                  Store Vote
                <% else %>
                  Confirm Vote
                <% end %>
              </button>
              <button
                type="button"
                phx-click="close_confirmation"
                phx-target={@myself}
                class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Render vote confirmation details based on vote type
  defp render_vote_confirmation_details(assigns) do
    case assigns.vote_data do
      %{type: "binary"} -> render_binary_confirmation(assigns)
      %{type: "approval"} -> render_approval_confirmation(assigns)  
      %{type: "star"} -> render_star_confirmation(assigns)
      %{type: "ranked"} -> render_ranked_confirmation(assigns)
      %{type: "clear"} -> render_clear_confirmation(assigns)
      %{type: "clear_all"} -> render_clear_all_confirmation(assigns)
      _ -> render_generic_confirmation(assigns)
    end
  end

  defp render_binary_confirmation(assigns) do
    vote = assigns.vote_data.vote
    assigns = assign(assigns, :vote_display, case vote do
      "yes" -> "Yes"
      "no" -> "No"
      "maybe" -> "Maybe"
      _ -> String.capitalize(vote)
    end)

    ~H"""
    <p class="text-sm text-gray-500 mb-3">
      You are about to vote <span class="font-medium text-gray-900"><%= @vote_display %></span> for:
    </p>
    <%= render_option_details(assigns) %>
    <%= if @anonymous_mode do %>
      <p class="text-xs text-blue-600 mt-3 bg-blue-50 p-2 rounded">
        This vote will be stored temporarily. You'll need to save your votes later to participate in the poll.
      </p>
    <% end %>
    """
  end

  defp render_approval_confirmation(assigns) do
    assigns = assign(assigns, :action, 
      if(assigns.vote_data.vote == "approved", do: "approve", else: "remove your approval from"))
    
    ~H"""
    <p class="text-sm text-gray-500 mb-3">
      You are about to <span class="font-medium text-gray-900"><%= @action %></span>:
    </p>
    <%= render_option_details(assigns) %>
    <%= if @anonymous_mode do %>
      <p class="text-xs text-blue-600 mt-3 bg-blue-50 p-2 rounded">
        This selection will be stored temporarily. You'll need to save your votes later to participate in the poll.
      </p>
    <% end %>
    """
  end

  defp render_star_confirmation(assigns) do
    rating = assigns.vote_data.rating
    assigns = assigns 
    |> assign(:rating, rating)
    |> assign(:star_text, if(rating == 1, do: "star", else: "stars"))
    
    ~H"""
    <p class="text-sm text-gray-500 mb-3">
      You are about to rate this option <span class="font-medium text-gray-900"><%= @rating %> <%= @star_text %></span>:
    </p>
    <%= render_option_details(assigns) %>
    <%= if @anonymous_mode do %>
      <p class="text-xs text-blue-600 mt-3 bg-blue-50 p-2 rounded">
        This rating will be stored temporarily. You'll need to save your votes later to participate in the poll.
      </p>
    <% end %>
    """
  end

  defp render_ranked_confirmation(assigns) do
    assigns = assign(assigns, :ranked_options, assigns.vote_data.ranked_options || [])
    
    ~H"""
    <p class="text-sm text-gray-500 mb-3">
      You are about to submit this ranking:
    </p>
    <div class="space-y-2 max-h-32 overflow-y-auto">
      <%= for {option, index} <- Enum.with_index(@ranked_options) do %>
        <div class="flex items-center text-sm">
          <span class="flex-shrink-0 w-6 h-6 bg-indigo-100 text-indigo-800 rounded-full flex items-center justify-center text-xs font-semibold mr-2">
            <%= index + 1 %>
          </span>
          <span class="text-gray-900 flex-1 truncate"><%= option.title %></span>
        </div>
      <% end %>
    </div>
    <%= if @anonymous_mode do %>
      <p class="text-xs text-blue-600 mt-3 bg-blue-50 p-2 rounded">
        This ranking will be stored temporarily. You'll need to save your votes later to participate in the poll.
      </p>
    <% end %>
    """
  end

  defp render_clear_confirmation(assigns) do
    ~H"""
    <p class="text-sm text-gray-500 mb-3">
      You are about to clear your vote for:
    </p>
    <%= render_option_details(assigns) %>
    """
  end

  defp render_clear_all_confirmation(assigns) do
    assigns = assign(assigns, :system_name, case assigns.voting_system do
      "binary" -> "votes"
      "approval" -> "selections"  
      "ranked" -> "ranking"
      "star" -> "ratings"
      _ -> "votes"
    end)

    ~H"""
    <p class="text-sm text-gray-500">
      You are about to clear all your <span class="font-medium text-gray-900"><%= @system_name %></span> for this poll.
    </p>
    <p class="text-sm text-gray-600 mt-2">
      This action cannot be undone.
    </p>
    """
  end

  defp render_generic_confirmation(assigns) do
    ~H"""
    <p class="text-sm text-gray-500">
      Are you sure you want to proceed with this vote?
    </p>
    """
  end

  defp render_option_details(assigns) do
    assigns = assign(assigns, :option, assigns.option)

    ~H"""
    <div class="bg-gray-50 rounded-lg p-3">
      <div class="flex items-start">
        <!-- Movie/Option Image -->
        <%= if @poll.poll_type == "movie" do %>
          <div class="w-12 h-18 mr-3 flex-shrink-0 overflow-hidden rounded">
            <% image_url = MovieUtils.get_image_url(@option) %>
            <%= if image_url do %>
              <img
                src={image_url}
                alt={"#{@option.title} poster"}
                class="w-full h-full object-cover"
                loading="lazy"
              />
            <% else %>
              <div class="w-full h-full bg-gray-200 flex items-center justify-center">
                <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 4v16M17 4v16M3 8h4m10 0h4M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
                </svg>
              </div>
            <% end %>
          </div>
        <% else %>
          <%= if @option.image_url do %>
            <div class="w-12 h-18 mr-3 flex-shrink-0 overflow-hidden rounded">
              <img
                src={@option.image_url}
                alt={"#{@option.title} image"}
                class="w-full h-full object-cover"
                loading="lazy"
              />
            </div>
          <% end %>
        <% end %>
        
        <div class="flex-1 min-w-0">
          <h4 class="text-sm font-medium text-gray-900 break-words">
            <%= @option.title %>
          </h4>
          <%= if @option.description do %>
            <p class="text-xs text-gray-600 mt-1 line-clamp-2"><%= @option.description %></p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("confirm_vote", _params, socket) do
    # Send the confirmation to the parent component
    send_update(EventasaurusWeb.VotingInterfaceComponent, 
      id: "voting-interface-#{socket.assigns.poll.id}",
      vote_confirmed: socket.assigns.vote_data)
    {:noreply, assign(socket, show: false)}
  end

  @impl true
  def handle_event("close_confirmation", _params, socket) do
    # Send cancellation to parent component  
    send_update(EventasaurusWeb.VotingInterfaceComponent, 
      id: "voting-interface-#{socket.assigns.poll.id}",
      vote_confirmation_cancelled: true)
    {:noreply, assign(socket, show: false)}
  end
end