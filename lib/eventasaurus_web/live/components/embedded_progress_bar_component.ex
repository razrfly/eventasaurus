defmodule EventasaurusWeb.EmbeddedProgressBarComponent do
  @moduledoc """
  A reusable component for displaying embedded progress bars within poll voting interfaces.
  
  This component provides visual indicators for voting statistics directly within
  the voting interface, supporting all voting systems (binary, approval, ranked, star).
  
  ## Attributes:
  - poll_stats: Poll statistics data structure (required)
  - option_id: ID of the poll option to display stats for (required)
  - voting_system: The voting system type (required)
  - compact: Whether to use compact display (default: false)
  - show_labels: Whether to show vote labels (default: true)
  - show_counts: Whether to show vote counts (default: true)
  - anonymous_mode: Whether in anonymous voting mode (default: false)
  
  ## Usage:
      <.live_component
        module={EventasaurusWeb.EmbeddedProgressBarComponent}
        id="progress-123"
        poll_stats={@poll_stats}
        option_id={123}
        voting_system={@poll.voting_system}
        compact={false}
        show_labels={true}
        show_counts={true}
        anonymous_mode={@anonymous_mode}
      />
  """

  use EventasaurusWeb, :live_component
  
  alias EventasaurusWeb.Helpers.PollStatsHelper
  alias EventasaurusWeb.Helpers.VoteDisplayHelper

  @impl true
  def update(assigns, socket) do
    # Extract simplified statistics for this option
    stats = PollStatsHelper.get_simplified_option_stats(
      assigns.poll_stats,
      assigns.option_id,
      assigns.voting_system
    )
    
    # Pre-calculate breakdown data to avoid variables in templates
    breakdown_data = case assigns.voting_system do
      "binary" -> 
        breakdown = PollStatsHelper.get_binary_breakdown(assigns.poll_stats, assigns.option_id)
        %{
          yes_percentage: breakdown.yes_percentage || 0.0,
          maybe_percentage: breakdown.maybe_percentage || 0.0,
          no_percentage: breakdown.no_percentage || 0.0
        }
      "star" ->
        breakdown = PollStatsHelper.get_star_breakdown(assigns.poll_stats, assigns.option_id)
        %{
          one_star_percentage: breakdown.one_star_percentage || 0.0,
          two_star_percentage: breakdown.two_star_percentage || 0.0,
          three_star_percentage: breakdown.three_star_percentage || 0.0,
          four_star_percentage: breakdown.four_star_percentage || 0.0,
          five_star_percentage: breakdown.five_star_percentage || 0.0
        }
      "ranked" ->
        %{rank_quality_percentage: PollStatsHelper.get_rank_quality_percentage(stats.average_rank || 0.0)}
      _ ->
        %{}
    end
    
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:stats, stats)
     |> assign(:breakdown_data, breakdown_data)
     |> assign_new(:compact, fn -> false end)
     |> assign_new(:show_labels, fn -> true end)
     |> assign_new(:show_counts, fn -> true end)
     |> assign_new(:anonymous_mode, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["embedded-progress-bar", @compact && "compact"]}>
      <%= case @voting_system do %>
        <% "binary" -> %>
          <%= render_binary_progress(assigns) %>
        <% "approval" -> %>
          <%= render_approval_progress(assigns) %>
        <% "ranked" -> %>
          <%= render_ranked_progress(assigns) %>
        <% "star" -> %>
          <%= render_star_progress(assigns) %>
        <% _ -> %>
          <%= render_generic_progress(assigns) %>
      <% end %>
    </div>
    """
  end

  # Binary voting progress (Yes/Maybe/No)
  defp render_binary_progress(assigns) do
    ~H"""
    <div class={["binary-progress", @compact && "compact"]}>
      <%= if @show_counts and @stats.total_votes > 0 do %>
        <div class={["text-gray-500 mb-1", @compact && "text-xs" || "text-sm"]}>
          <%= VoteDisplayHelper.format_vote_count(@stats.total_votes, "vote") %>
          • <%= VoteDisplayHelper.format_percentage(@stats.positive_percentage || 0.0) %> positive
        </div>
      <% end %>
      
      <!-- Visual progress bar for binary voting -->
      <div class={["flex bg-gray-100 rounded-full overflow-hidden", @compact && "h-1.5" || "h-2"]}>
        <%= if @stats.total_votes > 0 do %>
          <div class="bg-green-500" style={"width: #{@breakdown_data.yes_percentage}%"}></div>
          <div class="bg-yellow-400" style={"width: #{@breakdown_data.maybe_percentage}%"}></div>
          <div class="bg-red-400" style={"width: #{@breakdown_data.no_percentage}%"}></div>
        <% else %>
          <div class="bg-gray-200 w-full"></div>
        <% end %>
      </div>
      
      <%= if @show_labels and @stats.total_votes > 0 and not @compact do %>
        <div class="flex justify-between text-xs text-gray-500 mt-1">
          <span><%= calculate_vote_count(@breakdown_data.yes_percentage, @stats.total_votes) %> Yes</span>
          <span><%= calculate_vote_count(@breakdown_data.maybe_percentage, @stats.total_votes) %> Maybe</span>
          <span><%= calculate_vote_count(@breakdown_data.no_percentage, @stats.total_votes) %> No</span>
        </div>
      <% end %>
    </div>
    """
  end

  # Approval voting progress
  defp render_approval_progress(assigns) do
    ~H"""
    <div class={["approval-progress", @compact && "compact"]}>
      <%= if @show_counts and @stats.total_votes > 0 do %>
        <div class={["text-gray-500 mb-1", @compact && "text-xs" || "text-sm"]}>
          <%= VoteDisplayHelper.format_vote_count(@stats.total_votes, "approval") %>
          • <%= VoteDisplayHelper.format_percentage(@stats.approval_percentage || 0.0) %> approval rate
        </div>
      <% end %>
      
      <!-- Visual progress bar for approval voting -->
      <div class={["flex bg-gray-100 rounded-full overflow-hidden", @compact && "h-1.5" || "h-2"]}>
        <%= if @stats.total_votes > 0 do %>
          <div class="bg-green-500" style={"width: #{@stats.approval_percentage || 0.0}%"}></div>
        <% else %>
          <div class="bg-gray-200 w-full"></div>
        <% end %>
      </div>
    </div>
    """
  end

  # Ranked voting progress
  defp render_ranked_progress(assigns) do
    ~H"""
    <div class={["ranked-progress", @compact && "compact"]}>
      <%= if @show_counts and @stats.total_votes > 0 do %>
        <div class={["text-gray-500 mb-1", @compact && "text-xs" || "text-sm"]}>
          <%= VoteDisplayHelper.format_rank(@stats.average_rank || 0.0, show_label: true) %>
          • <%= VoteDisplayHelper.format_vote_count(@stats.total_votes, "ranking") %>
        </div>
      <% end %>
      
      <!-- Visual progress bar for ranked voting (lower rank = better) -->
      <div class={["flex bg-gray-100 rounded-full overflow-hidden", @compact && "h-1.5" || "h-2"]}>
        <%= if @stats.total_votes > 0 do %>
          <div class="bg-indigo-500" style={"width: #{@breakdown_data.rank_quality_percentage}%"}></div>
        <% else %>
          <div class="bg-gray-200 w-full"></div>
        <% end %>
      </div>
    </div>
    """
  end

  # Star voting progress
  defp render_star_progress(assigns) do
    ~H"""
    <div class={["star-progress", @compact && "compact"]}>
      <%= if @show_counts and @stats.total_votes > 0 do %>
        <div class={["text-gray-500 mb-1", @compact && "text-xs" || "text-sm"]}>
          <%= VoteDisplayHelper.format_star_rating(@stats.average_rating || 0.0) %>
          • <%= VoteDisplayHelper.format_percentage(@stats.positive_percentage || 0.0) %> positive
          • <%= VoteDisplayHelper.format_vote_count(@stats.total_votes, "rating") %>
        </div>
      <% end %>
      
      <!-- Visual progress bar for star ratings -->
      <div class={["flex bg-gray-100 rounded-full overflow-hidden", @compact && "h-1.5" || "h-2"]}>
        <%= if @stats.total_votes > 0 do %>
          <div class="bg-red-400" style={"width: #{@breakdown_data.one_star_percentage}%"}></div>
          <div class="bg-orange-400" style={"width: #{@breakdown_data.two_star_percentage}%"}></div>
          <div class="bg-yellow-400" style={"width: #{@breakdown_data.three_star_percentage}%"}></div>
          <div class="bg-lime-500" style={"width: #{@breakdown_data.four_star_percentage}%"}></div>
          <div class="bg-green-500" style={"width: #{@breakdown_data.five_star_percentage}%"}></div>
        <% else %>
          <div class="bg-gray-200 w-full"></div>
        <% end %>
      </div>
      
      <%= if @show_labels and @stats.total_votes > 0 and not @compact do %>
        <div class="flex justify-between text-xs text-gray-500 mt-1">
          <span>1⭐</span>
          <span>2⭐</span>
          <span>3⭐</span>
          <span>4⭐</span>
          <span>5⭐</span>
        </div>
      <% end %>
    </div>
    """
  end

  # Generic progress for unknown voting systems
  defp render_generic_progress(assigns) do
    ~H"""
    <div class={["generic-progress", @compact && "compact"]}>
      <%= if @show_counts and @stats.total_votes > 0 do %>
        <div class={["text-gray-500 mb-1", @compact && "text-xs" || "text-sm"]}>
          <%= VoteDisplayHelper.format_vote_count(@stats.total_votes, "vote") %>
        </div>
      <% end %>
      
      <!-- Basic progress indicator -->
      <div class={["flex bg-gray-100 rounded-full overflow-hidden", @compact && "h-1.5" || "h-2"]}>
        <%= if @stats.total_votes > 0 do %>
          <div class="bg-blue-500 w-full"></div>
        <% else %>
          <div class="bg-gray-200 w-full"></div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper function to calculate vote count from percentage
  defp calculate_vote_count(percentage, total_votes) do
    round(percentage * total_votes / 100)
  end

  # Helper function to get voter count display from poll stats
  defp get_voter_count_display(poll_stats) do
    case poll_stats do
      %{total_unique_voters: count} when is_integer(count) and count > 0 ->
        if count == 1, do: "1 voter", else: "#{count} voters"
      _ ->
        "0 voters"
    end
  end
end