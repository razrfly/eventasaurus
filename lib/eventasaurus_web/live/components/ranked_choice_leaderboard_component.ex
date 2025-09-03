defmodule EventasaurusWeb.Live.Components.RankedChoiceLeaderboardComponent do
  @moduledoc """
  Clean, professional RCV leaderboard with simple card-based layout.
  No complex flexbox - just clean stacked cards and simple grid.
  """
  
  use EventasaurusWeb, :live_component
  
  alias EventasaurusApp.Events.RankedChoiceVoting
  alias EventasaurusApp.Repo
  import Ecto.Query
  
  @impl true
  def mount(socket) do
    {:ok, 
     socket
     |> assign(
       show_participation_metrics: false,
       show_round_breakdown: false,
       show_other_contenders: false
     )}
  end

  @impl true
  def update(assigns, socket) do
    # Get IRV results and leaderboard data
    {irv_results, leaderboard} = if assigns[:poll] && assigns.poll.voting_system == "ranked" do
      results = RankedChoiceVoting.calculate_irv_winner(assigns.poll)
      board = RankedChoiceVoting.get_leaderboard(assigns.poll)
      {results, board}
    else
      {nil, []}
    end

    # Prepare display data
    display_data = if irv_results && leaderboard != [] do
      prepare_display_data(irv_results, leaderboard, assigns.poll)
    else
      %{
        winner: nil,
        contenders: [],
        other_contenders: [],
        stats: %{voters: 0, majority: 0, final_round: 0}
      }
    end

    {:ok, 
     socket
     |> assign(assigns)
     |> assign(
       irv_results: irv_results,
       leaderboard: leaderboard,
       display_data: display_data
     )}
  end

  @impl true
  def handle_event("toggle_participation_metrics", _params, socket) do
    {:noreply, assign(socket, :show_participation_metrics, !socket.assigns.show_participation_metrics)}
  end

  def handle_event("toggle_round_breakdown", _params, socket) do
    {:noreply, assign(socket, :show_round_breakdown, !socket.assigns.show_round_breakdown)}
  end

  def handle_event("toggle_other_contenders", _params, socket) do
    {:noreply, assign(socket, :show_other_contenders, !socket.assigns.show_other_contenders)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white rounded-lg border border-gray-200 shadow-sm">
      <%= if @display_data.stats.voters > 0 do %>
        <!-- Header -->
        <div class="px-6 py-4 pb-6 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <h3 class="text-lg font-semibold text-gray-900 mr-8">Current Standings</h3>
            <div class="flex items-center gap-6 text-sm text-gray-600">
              <div class="flex items-center gap-1">
                <span>👥</span>
                <span><%= @display_data.stats.voters %> voters</span>
              </div>
              <div class="flex items-center gap-1">
                <span>✓</span>
                <span>Majority = <%= @display_data.stats.majority %></span>
              </div>
              <div class="flex items-center gap-1">
                <span>📊</span>
                <span>Round <%= @display_data.stats.final_round %></span>
              </div>
            </div>
          </div>
        </div>

        <!-- Winner Section -->
        <%= if @display_data.winner do %>
          <div class="p-6 border-b border-gray-200">
            <div class="bg-green-50 rounded-lg p-6 border border-green-200">
              <!-- Winner Header -->
              <div class="grid grid-cols-3 gap-4 items-center mb-4">
                <div class="flex items-center gap-3">
                  <span class="text-2xl">🏆</span>
                  <div>
                    <h4 class="text-xl font-bold text-green-900"><%= @display_data.winner.option.title %></h4>
                    <span class="inline-block px-2 py-1 text-xs font-medium bg-green-100 text-green-800 rounded">
                      LEADING
                    </span>
                  </div>
                </div>
                <div class="text-center">
                  <div class="text-2xl font-bold text-green-900"><%= @display_data.winner.percentage %>%</div>
                  <div class="text-sm text-green-700"><%= @display_data.winner.votes %> votes</div>
                </div>
                <div class="text-right text-sm text-green-800">
                  <div>(<%= @display_data.winner.percentage %>%) in Round <%= @display_data.stats.final_round %></div>
                  <div><%= @display_data.winner.votes %>/<%= @display_data.stats.voters %> votes</div>
                </div>
              </div>

              <!-- Winner Summary -->
              <div class="pt-4 border-t border-green-200">
                <p class="text-sm text-green-800">
                  <strong><%= @display_data.winner.option.title %></strong> is currently leading with a majority in Round <%= @display_data.stats.final_round %>
                  (<%= @display_data.winner.votes %>/<%= @display_data.stats.voters %> first-choice votes = <%= @display_data.winner.percentage %>%)
                </p>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Top Contenders -->
        <%= if length(@display_data.contenders) > 0 do %>
          <div class="p-6 border-b border-gray-200">
            <!-- Section Header -->
            <div class="flex items-center justify-between mb-6">
              <h5 class="text-sm font-medium text-gray-700">📊 Top Contenders</h5>
              <%= if length(@display_data.other_contenders) > 0 do %>
                <button
                  phx-click="toggle_other_contenders"
                  phx-target={@myself}
                  class="text-sm text-gray-600 hover:text-gray-800 hover:underline"
                >
                  <%= if @show_other_contenders do %>
                    Hide other options
                  <% else %>
                    Show <%= length(@display_data.other_contenders) %> other options
                  <% end %>
                </button>
              <% end %>
            </div>

            <!-- Contenders List -->
            <div class="space-y-4">
              <%= for {contender, index} <- Enum.with_index(@display_data.contenders, 2) do %>
                <div class="bg-blue-50 border border-blue-100 rounded-lg p-4">
                  <div class="grid grid-cols-3 gap-4 items-center">
                    <div class="flex items-center gap-3">
                      <span class="w-8 h-8 bg-blue-100 text-blue-800 rounded-full flex items-center justify-center text-sm font-semibold flex-shrink-0">
                        <%= index %>
                      </span>
                      <span class="font-medium text-gray-900"><%= contender.option.title %></span>
                    </div>
                    <div class="text-center">
                      <div class="text-lg font-semibold text-blue-900"><%= contender.percentage %>%</div>
                    </div>
                    <div class="text-right">
                      <div class="text-sm text-gray-600"><%= contender.votes %> votes</div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Other Contenders (Expandable) -->
            <%= if @show_other_contenders && length(@display_data.other_contenders) > 0 do %>
              <div class="mt-6 pt-6 border-t border-gray-200">
                <div class="space-y-3">
                  <%= for contender <- @display_data.other_contenders do %>
                    <div class="bg-gray-50 border border-gray-200 rounded-lg p-4">
                      <div class="flex items-center justify-between">
                        <span class="font-medium text-gray-700"><%= contender.option.title %></span>
                        <span class="text-sm text-gray-500"><%= contender.votes %> votes</span>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- Section 2: Participation Metrics (Expandable) -->
        <div class="border-b border-gray-200">
          <button
            phx-click="toggle_participation_metrics"
            phx-target={@myself}
            class="w-full px-6 py-4 text-left hover:bg-gray-50 flex items-center justify-between"
          >
            <span class="font-medium text-gray-900">📋 See how people ranked every option overall</span>
            <svg class={[
              "w-5 h-5 text-gray-400 transition-transform",
              if(@show_participation_metrics, do: "rotate-180", else: "")
            ]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
            </svg>
          </button>
          
          <%= if @show_participation_metrics do %>
            <div class="px-6 pb-6">
              <div class="space-y-3">
                <%= for metric <- @display_data.participation_metrics do %>
                  <div class="bg-white border border-gray-200 rounded-lg p-4">
                    <div class="grid grid-cols-3 gap-4 items-start">
                      <!-- Title Column (Fixed Width) -->
                      <div class="w-72">
                        <div class="font-medium text-gray-900 break-words">
                          <%= metric.option.title %>
                        </div>
                      </div>
                      
                      <!-- Rank Distribution & Average Column -->
                      <div class="flex items-center justify-center gap-4">
                        <div class="flex items-center gap-2">
                          <span class="text-sm text-gray-600">Rank distribution:</span>
                          <div class="flex gap-1">
                            <%= for position <- 1..5 do %>
                              <span class={[
                                "w-2 h-2 rounded-full",
                                if(position <= metric.max_rank, do: 
                                  if(Map.get(metric.rank_distribution, position, 0) > 0, 
                                     do: "bg-blue-600", 
                                     else: "bg-gray-300"),
                                  else: "bg-gray-200"
                                )
                              ]}></span>
                            <% end %>
                          </div>
                        </div>
                        <div class="text-sm text-gray-600">
                          Avg: <span class="font-medium"><%= metric.avg_rank %></span>
                        </div>
                      </div>
                      
                      <!-- Voters Column (Right Aligned) -->
                      <div class="text-right">
                        <div class="text-sm font-medium text-gray-900">
                          <%= metric.total_rankings %> voters
                        </div>
                        <div class="text-sm text-gray-500">
                          (<%= metric.participation_percentage %>%)
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Section 3: Round Breakdown (Expandable) -->
        <div>
          <button
            phx-click="toggle_round_breakdown"
            phx-target={@myself}
            class="w-full px-6 py-4 text-left hover:bg-gray-50 flex items-center justify-between"
          >
            <span class="font-medium text-gray-900">📊 How the rounds played out</span>
            <svg class={[
              "w-5 h-5 text-gray-400 transition-transform",
              if(@show_round_breakdown, do: "rotate-180", else: "")
            ]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
            </svg>
          </button>
          
          <%= if @show_round_breakdown do %>
            <div class="px-6 pb-6">
              <%= if @display_data.round_explanation do %>
                <!-- Single Round Explanation -->
                <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div class="flex items-start gap-3">
                    <span class="text-blue-600 text-lg">ℹ️</span>
                    <div>
                      <p class="text-blue-900"><%= @display_data.round_explanation %></p>
                    </div>
                  </div>
                </div>
              <% else %>
                <!-- Multi-Round Breakdown -->
                <div class="space-y-4">
                  <%= for {round, round_index} <- Enum.with_index(@irv_results.rounds, 1) do %>
                    <div class="bg-white border border-gray-200 rounded-lg p-4">
                      <div class="flex items-center justify-between mb-3">
                        <h4 class="font-semibold text-gray-900">Round <%= round_index %></h4>
                        <div class="text-sm text-gray-500">
                          Majority needed: <%= @display_data.stats.majority %>
                        </div>
                      </div>
                      
                      <div class="space-y-2">
                        <%= for {option_id, votes} <- Enum.sort_by(round.vote_counts, fn {_, v} -> -v end) do %>
                          <% option = Map.get(@display_data.options_by_id, option_id) %>
                          <% percentage = if votes > 0, do: (votes / @irv_results.total_voters * 100) |> Float.round(1), else: 0 %>
                          <% is_winner = @irv_results.winner && @irv_results.winner.id == option_id %>
                          <% is_eliminated = round.eliminated == option_id %>
                          <div class="flex items-center justify-between">
                            <div class="flex items-center flex-1">
                              <div class="w-32 text-sm font-medium truncate" title={option.title}>
                                <%= option.title %>
                              </div>
                              <%= if is_winner do %>
                                <span class="ml-2 text-xs bg-green-100 text-green-800 px-2 py-0.5 rounded">
                                  LEADING
                                </span>
                              <% end %>
                              <%= if is_eliminated do %>
                                <span class="ml-2 text-xs bg-red-100 text-red-800 px-2 py-0.5 rounded">
                                  ELIMINATED
                                </span>
                              <% end %>
                            </div>
                            <div class="flex items-center gap-2">
                              <div class="w-24 bg-gray-200 rounded-full h-2">
                                <div 
                                  class={[
                                    "h-2 rounded-full",
                                    cond do
                                      is_winner -> "bg-green-500"
                                      is_eliminated -> "bg-red-400"
                                      true -> "bg-blue-500"
                                    end
                                  ]}
                                  style={"width: #{percentage}%"}
                                ></div>
                              </div>
                              <div class="text-right min-w-[4rem]">
                                <div class="font-semibold text-gray-900"><%= votes %></div>
                                <div class="text-xs text-gray-500"><%= percentage %>%</div>
                              </div>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

      <% else %>
        <!-- No votes state -->
        <div class="p-8 text-center">
          <div class="text-gray-400 mb-2 text-2xl">📊</div>
          <p class="text-gray-600">No votes cast yet</p>
        </div>
      <% end %>
    </div>
    """
  end

  # Prepare display data with proper structure  
  defp prepare_display_data(irv_results, leaderboard, poll) do
    # Sort leaderboard by status and votes
    sorted_leaderboard = Enum.sort_by(leaderboard, fn entry ->
      case entry.status do
        :winner -> {0, -entry.votes}
        :runner_up -> {1, -entry.votes}
        :eliminated -> {2, entry.eliminated_round || 999, -entry.votes}
      end
    end)

    # Extract winner and contenders
    winner = Enum.find(sorted_leaderboard, & &1.status == :winner)
    non_winners = Enum.reject(sorted_leaderboard, & &1.status == :winner)
    
    # Split contenders by vote count
    {contenders, other_contenders} = Enum.split_with(non_winners, & &1.votes > 0)
    
    # Take only top 2 contenders for clean display
    contenders = Enum.take(contenders, 2)

    # Prepare participation metrics with rank distribution
    participation_metrics = prepare_participation_metrics(leaderboard, poll)
    
    # Build options map to avoid N+1 queries in templates
    options_by_id = Map.new(leaderboard, &{&1.option_id, &1.option})

    # Determine round explanation (for single round cases)
    round_explanation = if length(irv_results.rounds) == 1 && winner do
      "Only 1 round was needed because #{winner.option.title} already had a majority in Round 1 (#{winner.percentage}%). No eliminations or transfers were required."
    else
      nil
    end

    %{
      winner: winner,
      contenders: contenders,
      other_contenders: other_contenders,
      participation_metrics: participation_metrics,
      round_explanation: round_explanation,
      options_by_id: options_by_id,
      stats: %{
        voters: irv_results.total_voters,
        majority: irv_results.majority_threshold,
        final_round: length(irv_results.rounds)
      }
    }
  end

  # Prepare enhanced participation metrics with rank distribution
  defp prepare_participation_metrics(leaderboard, poll) do
    # Get all votes for this poll to calculate rank distributions
    votes = from(v in EventasaurusApp.Events.PollVote,
      where: v.poll_id == ^poll.id and not is_nil(v.vote_rank) and is_nil(v.deleted_at),
      preload: :poll_option
    ) |> Repo.all()

    # Calculate total unique voters once (computed once)
    total_voters = from(v in EventasaurusApp.Events.PollVote,
      where: v.poll_id == ^poll.id and not is_nil(v.vote_rank) and is_nil(v.deleted_at),
      select: count(fragment("DISTINCT ?", v.voter_id))
    ) |> Repo.one()

    # Group votes by option to calculate distributions
    votes_by_option = Enum.group_by(votes, & &1.poll_option_id)

    Enum.map(leaderboard, fn entry ->
      option_votes = Map.get(votes_by_option, entry.option_id, [])
      
      # Calculate rank distribution
      rank_distribution = option_votes
        |> Enum.group_by(& &1.vote_rank)
        |> Map.new(fn {rank, votes} -> {rank, length(votes)} end)

      # Calculate average rank
      total_votes = length(option_votes)
      avg_rank = if total_votes > 0 do
        sum_ranks = option_votes |> Enum.map(& &1.vote_rank) |> Enum.sum()
        (sum_ranks / total_votes) |> Float.round(1)
      else
        0.0
      end

      # Calculate participation percentage using pre-computed total_voters
      participation_percentage = if total_voters > 0 do
        (total_votes / total_voters * 100) |> Float.round(0) |> trunc()
      else
        0
      end

      max_rank = if option_votes != [], do: Enum.max_by(option_votes, & &1.vote_rank).vote_rank, else: 0

      %{
        option: entry.option,
        option_id: entry.option_id,
        rank_distribution: rank_distribution,
        avg_rank: avg_rank,
        total_rankings: total_votes,
        participation_percentage: participation_percentage,
        max_rank: max_rank
      }
    end)
    |> Enum.sort_by(& -(&1.total_rankings)) # Sort by participation
  end

end