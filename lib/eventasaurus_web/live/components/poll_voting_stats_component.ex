defmodule EventasaurusWeb.PollVotingStatsComponent do
  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Events

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{poll: poll} = assigns, socket) do
    # Get the voting statistics
    voting_stats = Events.get_poll_voting_stats(poll)

    socket = socket
    |> assign(:poll, poll)
    |> assign(:voting_stats, voting_stats)
    |> assign_new(:show_vote_counts, fn -> true end)
    |> assign_new(:show_percentages, fn -> true end)
    |> assign_new(:show_progress_bars, fn -> true end)
    |> assign_new(:compact_mode, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="poll-voting-stats" data-poll-id={@poll.id}>
      <%= if @voting_stats.total_unique_voters > 0 do %>
        <div class="mb-4">
          <div class="flex items-center justify-between text-sm text-gray-600 mb-2">
            <span><%= @voting_stats.total_unique_voters %> <%= if @voting_stats.total_unique_voters == 1, do: "voter", else: "voters" %></span>
            <span class="text-xs"><%= voting_system_label(@voting_stats.voting_system) %></span>
          </div>
        </div>

        <div class="space-y-3">
          <%= for option <- @voting_stats.options do %>
            <div class="poll-option-stats" data-option-id={option.option_id}>
              <!-- Option Title and Summary -->
              <div class="flex items-center justify-between mb-2">
                <div class="flex-1 min-w-0">
                  <h4 class="font-medium text-gray-900 truncate"><%= option.option_title %></h4>
                  <%= if option.option_description && option.option_description != "" do %>
                    <p class="text-sm text-gray-500 truncate"><%= option.option_description %></p>
                  <% end %>
                </div>

                <%= if @show_vote_counts or @show_percentages do %>
                  <div class="flex-shrink-0 ml-3 text-right">
                    <%= render_stats_summary(assigns, option) %>
                  </div>
                <% end %>
              </div>

              <!-- Progress Bars -->
              <%= if @show_progress_bars do %>
                <%= render_progress_bars(assigns, option) %>
              <% end %>

              <!-- Detailed Breakdown (non-compact mode) -->
              <%= unless @compact_mode do %>
                <%= render_detailed_breakdown(assigns, option) %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-4 text-gray-500">
          <div class="text-sm">No votes cast yet</div>
          <div class="text-xs text-gray-400 mt-1">Be the first to vote!</div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_stats_summary(assigns, option) do
    ~H"""
    <div class="text-sm">
      <%= case @voting_stats.voting_system do %>
        <% "binary" -> %>
          <div class="font-semibold text-gray-900"><%= option.tally.percentage %>%</div>
          <div class="text-xs text-gray-500"><%= option.tally.total %> votes</div>
        <% "approval" -> %>
          <div class="font-semibold text-gray-900"><%= option.tally.percentage %>%</div>
          <div class="text-xs text-gray-500"><%= option.tally.selected %> selected</div>
        <% "star" -> %>
          <div class="font-semibold text-gray-900">★ <%= option.tally.average_rating %></div>
          <div class="text-xs text-gray-500"><%= option.tally.total %> ratings</div>
        <% "ranked" -> %>
          <div class="font-semibold text-gray-900">#<%= option.tally.average_rank %></div>
          <div class="text-xs text-gray-500"><%= option.tally.total %> ranks</div>
        <% _ -> %>
          <div class="font-semibold text-gray-900"><%= option.tally.total %></div>
          <div class="text-xs text-gray-500">votes</div>
      <% end %>
    </div>
    """
  end

  defp render_progress_bars(assigns, option) do
    ~H"""
    <div class="progress-bars mb-2">
      <%= case @voting_stats.voting_system do %>
        <% "binary" -> %>
          <!-- Binary voting: yes/maybe/no bars -->
          <div class="flex h-3 bg-gray-100 rounded-full overflow-hidden">
            <%= if option.tally.total > 0 do %>
              <div class="bg-green-500" style={"width: #{option.tally.yes_percentage}%"}></div>
              <div class="bg-yellow-400" style={"width: #{option.tally.maybe_percentage}%"}></div>
              <div class="bg-red-400" style={"width: #{option.tally.no_percentage}%"}></div>
            <% end %>
          </div>
          <div class="flex justify-between text-xs text-gray-500 mt-1">
            <span>Yes: <%= option.tally.yes %></span>
            <span>Maybe: <%= option.tally.maybe %></span>
            <span>No: <%= option.tally.no %></span>
          </div>

        <% "approval" -> %>
          <!-- Approval voting: single bar -->
          <div class="flex h-3 bg-gray-100 rounded-full overflow-hidden">
            <div class="bg-blue-500" style={"width: #{option.tally.percentage}%"}></div>
          </div>
          <div class="flex justify-between text-xs text-gray-500 mt-1">
            <span>Selected by <%= option.tally.percentage %>% of voters</span>
            <span><%= option.tally.selected %> selections</span>
          </div>

        <% "star" -> %>
          <!-- Star rating: distribution bars -->
          <div class="space-y-1">
            <%= for %{rating: rating, count: count, percentage: perc} <- option.tally.rating_distribution do %>
              <div class="flex items-center text-xs">
                <span class="w-8 text-gray-600"><%= rating %>★</span>
                <div class="flex-1 mx-2 h-2 bg-gray-100 rounded-full overflow-hidden">
                  <div class="h-full bg-yellow-400" style={"width: #{perc}%"}></div>
                </div>
                <span class="w-8 text-gray-500"><%= count %></span>
              </div>
            <% end %>
          </div>

        <% "ranked" -> %>
          <!-- Ranked voting: rank distribution -->
          <div class="space-y-1">
            <%= for %{rank: rank, count: count, percentage: perc} <- option.tally.rank_distribution do %>
              <div class="flex items-center text-xs">
                <span class="w-8 text-gray-600">#<%= rank %></span>
                <div class="flex-1 mx-2 h-2 bg-gray-100 rounded-full overflow-hidden">
                  <div class="h-full bg-purple-500" style={"width: #{perc}%"}></div>
                </div>
                <span class="w-8 text-gray-500"><%= count %></span>
              </div>
            <% end %>
          </div>

        <% _ -> %>
          <!-- Generic: simple bar -->
          <div class="flex h-3 bg-gray-100 rounded-full overflow-hidden">
            <div class="bg-blue-500" style={"width: #{min(option.tally.percentage, 100)}%"}></div>
          </div>
          <div class="text-xs text-gray-500 mt-1">
            <%= option.tally.total %> votes
          </div>
      <% end %>
    </div>
    """
  end

  defp render_detailed_breakdown(assigns, option) do
    ~H"""
    <%= unless @compact_mode do %>
      <div class="detailed-breakdown text-xs text-gray-500 mt-2 space-y-1">
        <%= case @voting_stats.voting_system do %>
          <% "binary" -> %>
            <div class="flex justify-between">
              <span>Positive Score:</span>
              <span><%= option.tally.score %>/<%= option.tally.total %></span>
            </div>
          <% "star" -> %>
            <div class="flex justify-between">
              <span>Average Rating:</span>
              <span><%= option.tally.average_rating %>/5.0</span>
            </div>
          <% "ranked" -> %>
            <div class="flex justify-between">
              <span>Average Rank:</span>
              <span><%= option.tally.average_rank %></span>
            </div>
          <% _ -> %>
            <!-- No additional details for other types -->
        <% end %>
      </div>
    <% end %>
    """
  end

  defp voting_system_label(voting_system) do
    case voting_system do
      "binary" -> "Yes/Maybe/No"
      "approval" -> "Select Multiple"
      "star" -> "Star Rating"
      "ranked" -> "Ranked Choice"
      _ -> "Voting"
    end
  end
end
