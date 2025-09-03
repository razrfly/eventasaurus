defmodule EventasaurusWeb.Live.Components.RankedChoiceLeaderboardComponent do
  @moduledoc """
  Component for displaying ranked choice voting (IRV) results and current standings.
  Shows a clear leaderboard with winner indication, elimination status, and voting rounds.
  """
  use EventasaurusWeb, :live_component
  alias EventasaurusApp.Events.RankedChoiceVoting

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="ranked-choice-leaderboard">
      <%= if @irv_results && @irv_results.total_voters > 0 do %>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700 p-4 mb-4">
          <!-- Header with Winner Indication -->
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100">
              Current Standings
            </h3>
            <div class="text-sm text-gray-600 dark:text-gray-400">
              <%= @irv_results.total_voters %> <%= if @irv_results.total_voters == 1, do: "voter", else: "voters" %>
              • <%= length(@irv_results.rounds) %> <%= if length(@irv_results.rounds) == 1, do: "round", else: "rounds" %>
            </div>
          </div>

          <!-- Winner Banner (if determined) -->
          <%= if @irv_results.winner do %>
            <div class="bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg p-3 mb-4">
              <div class="flex items-center">
                <svg class="w-5 h-5 text-green-600 dark:text-green-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                </svg>
                <span class="font-semibold text-green-800 dark:text-green-200">
                  Winner: <%= @irv_results.winner.title %>
                </span>
                <%= if map_size(@irv_results.final_percentages) > 0 do %>
                  <span class="ml-2 text-sm text-green-600 dark:text-green-400">
                    (<%= format_percentage(Map.get(@irv_results.final_percentages, @irv_results.winner.id, 0)) %>)
                  </span>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg p-3 mb-4">
              <div class="flex items-center">
                <svg class="w-5 h-5 text-yellow-600 dark:text-yellow-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm0-7a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zm0-3a1 1 0 100 2 1 1 0 000-2z" clip-rule="evenodd"/>
                </svg>
                <span class="text-yellow-800 dark:text-yellow-200">
                  No majority winner yet (need <%= @irv_results.majority_threshold %> votes for majority)
                </span>
              </div>
            </div>
          <% end %>

          <!-- Leaderboard List -->
          <div class="space-y-2">
            <%= for entry <- @leaderboard do %>
              <div class={[
                "flex items-center justify-between p-3 rounded-lg transition-colors",
                get_entry_bg_class(entry.status)
              ]}>
                <div class="flex items-center flex-1">
                  <!-- Position Badge -->
                  <div class={[
                    "w-8 h-8 rounded-full flex items-center justify-center mr-3 text-sm font-bold",
                    get_position_badge_class(entry.position, entry.status)
                  ]}>
                    <%= entry.position %>
                  </div>
                  
                  <!-- Option Name and Status -->
                  <div class="flex-1">
                    <div class="flex items-center">
                      <span class={[
                        "font-medium",
                        get_text_class(entry.status)
                      ]}>
                        <%= entry.option.title %>
                      </span>
                      <%= if entry.status == :winner do %>
                        <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800 dark:bg-green-800 dark:text-green-100">
                          WINNER
                        </span>
                      <% end %>
                      <%= if entry.status == :eliminated && entry.eliminated_round do %>
                        <span class="ml-2 text-xs text-gray-500 dark:text-gray-400">
                          Eliminated round <%= entry.eliminated_round %>
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>
                
                <!-- Vote Count and Percentage -->
                <div class="text-right ml-4">
                  <div class={[
                    "font-semibold",
                    get_text_class(entry.status)
                  ]}>
                    <%= entry.votes %> <%= if entry.votes == 1, do: "vote", else: "votes" %>
                  </div>
                  <div class="text-sm text-gray-600 dark:text-gray-400">
                    <%= format_percentage(entry.percentage) %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <!-- Round Details Toggle -->
          <%= if length(@irv_results.rounds) > 1 do %>
            <div class="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
              <button
                phx-click="toggle_round_details"
                phx-target={@myself}
                class="text-sm text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 font-medium"
              >
                <%= if @show_round_details do %>
                  Hide round-by-round details ▴
                <% else %>
                  Show round-by-round details ▾
                <% end %>
              </button>
              
              <%= if @show_round_details do %>
                <div class="mt-3 space-y-3">
                  <%= for round <- @irv_results.rounds do %>
                    <div class="bg-gray-50 dark:bg-gray-900 rounded-lg p-3">
                      <div class="flex items-center justify-between mb-2">
                        <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
                          Round <%= round.round_number %>
                        </span>
                        <%= if round.eliminated do %>
                          <span class="text-xs text-red-600 dark:text-red-400">
                            Eliminated: <%= get_option_title(round.eliminated, @poll) %>
                          </span>
                        <% end %>
                      </div>
                      <div class="grid grid-cols-2 gap-2 text-xs">
                        <%= for {option_id, votes} <- round.vote_counts do %>
                          <div class="flex justify-between">
                            <span class="text-gray-600 dark:text-gray-400">
                              <%= get_option_title(option_id, @poll) %>:
                            </span>
                            <span class="font-medium text-gray-900 dark:text-gray-100">
                              <%= votes %> (<%= format_percentage(Map.get(round.percentages, option_id, 0)) %>)
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <!-- IRV Explanation -->
          <div class="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
            <button
              phx-click="toggle_irv_explanation"
              phx-target={@myself}
              class="text-xs text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
            >
              <%= if @show_irv_explanation do %>
                ℹ Hide how ranked choice voting works
              <% else %>
                ℹ How does ranked choice voting work?
              <% end %>
            </button>
            
            <%= if @show_irv_explanation do %>
              <div class="mt-2 text-xs text-gray-600 dark:text-gray-400 space-y-1">
                <p>• Voters rank options in order of preference (1st, 2nd, 3rd, etc.)</p>
                <p>• First choices are counted initially</p>
                <p>• If no option has a majority (>50%), the lowest is eliminated</p>
                <p>• Votes for eliminated options transfer to next preferences</p>
                <p>• Process repeats until a winner emerges with majority support</p>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <!-- No votes yet -->
        <div class="bg-gray-50 dark:bg-gray-900 rounded-lg p-4 text-center text-gray-600 dark:text-gray-400">
          <svg class="w-12 h-12 mx-auto mb-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
          </svg>
          <p>No votes cast yet</p>
          <p class="text-xs mt-1">Rankings will appear here as votes come in</p>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, 
      show_round_details: false,
      show_irv_explanation: false
    )}
  end

  @impl true
  def update(assigns, socket) do
    # Get IRV results and leaderboard if we have a poll
    {irv_results, leaderboard} = if assigns[:poll] && assigns.poll.voting_system == "ranked" do
      results = RankedChoiceVoting.calculate_irv_winner(assigns.poll)
      board = RankedChoiceVoting.get_leaderboard(assigns.poll)
      {results, board}
    else
      {nil, []}
    end

    {:ok, 
     socket
     |> assign(assigns)
     |> assign(irv_results: irv_results, leaderboard: leaderboard)
    }
  end

  @impl true
  def handle_event("toggle_round_details", _, socket) do
    {:noreply, assign(socket, show_round_details: !socket.assigns.show_round_details)}
  end

  @impl true
  def handle_event("toggle_irv_explanation", _, socket) do
    {:noreply, assign(socket, show_irv_explanation: !socket.assigns.show_irv_explanation)}
  end

  # Helper functions

  defp get_entry_bg_class(:winner), do: "bg-green-50 dark:bg-green-900/10 border border-green-200 dark:border-green-800"
  defp get_entry_bg_class(:runner_up), do: "bg-gray-50 dark:bg-gray-900/50 hover:bg-gray-100 dark:hover:bg-gray-900/70"
  defp get_entry_bg_class(:eliminated), do: "bg-gray-50 dark:bg-gray-900/30 opacity-75"
  defp get_entry_bg_class(_), do: "bg-gray-50 dark:bg-gray-900/50"

  defp get_position_badge_class(1, :winner), do: "bg-green-500 text-white"
  defp get_position_badge_class(1, _), do: "bg-blue-500 text-white"
  defp get_position_badge_class(2, _), do: "bg-gray-400 text-white"
  defp get_position_badge_class(3, _), do: "bg-orange-400 text-white"
  defp get_position_badge_class(_, :eliminated), do: "bg-gray-300 dark:bg-gray-700 text-gray-600 dark:text-gray-400"
  defp get_position_badge_class(_, _), do: "bg-gray-200 dark:bg-gray-700 text-gray-700 dark:text-gray-300"

  defp get_text_class(:winner), do: "text-green-800 dark:text-green-200"
  defp get_text_class(:eliminated), do: "text-gray-500 dark:text-gray-400 line-through"
  defp get_text_class(_), do: "text-gray-900 dark:text-gray-100"

  defp format_percentage(percentage) when is_number(percentage) do
    "#{Float.round(percentage, 1)}%"
  end
  defp format_percentage(_), do: "0%"

  defp get_option_title(option_id, poll) do
    # Find the option in the poll
    case Enum.find(poll.poll_options, & &1.id == option_id) do
      nil -> "Unknown"
      option -> option.title
    end
  end
end