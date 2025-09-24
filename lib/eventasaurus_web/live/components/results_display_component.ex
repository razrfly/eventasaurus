defmodule EventasaurusWeb.ResultsDisplayComponent do
  @moduledoc """
  A reusable LiveView component for displaying live poll results and analytics.

  Provides real-time vote counts, percentages, rankings, and visual charts for
  different voting systems. Updates automatically via PubSub when votes are cast.

  ## Attributes:
  - poll: Poll struct with preloaded options and votes (required)
  - show_voter_details: Whether to show individual voter information (default: false)
  - compact_view: Whether to show a condensed version of results (default: false)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.ResultsDisplayComponent}
        id="poll-results"
        poll={@poll}
        show_voter_details={false}
        compact_view={false}
      />
  """

  use EventasaurusWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:vote_analytics, %{})
     |> assign(:total_voters, 0)}
  end

  @impl true
  def update(assigns, socket) do
    # Calculate analytics
    analytics = calculate_vote_analytics(assigns.poll)
    total_voters = count_unique_voters(assigns.poll)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:vote_analytics, analytics)
     |> assign(:total_voters, total_voters)
     |> assign_new(:show_voter_details, fn -> false end)
     |> assign_new(:compact_view, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg">
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-lg font-medium text-gray-900">Poll Results</h3>
            <p class="text-sm text-gray-500">
              <%= @total_voters %> voters • <%= get_results_summary(@poll.voting_system, @vote_analytics) %>
            </p>
          </div>

          <%= if @poll.status == "closed" do %>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
              Final Results
            </span>
          <% else %>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
              Live Results
            </span>
          <% end %>
        </div>
      </div>

      <!-- Results Display -->
      <div class="divide-y divide-gray-200">
        <%= case @poll.voting_system do %>
          <% "binary" -> %>
            <%= render_binary_results(assigns) %>
          <% "approval" -> %>
            <%= render_approval_results(assigns) %>
          <% "ranked" -> %>
            <%= render_ranked_results(assigns) %>
          <% "star" -> %>
            <%= render_star_results(assigns) %>
        <% end %>
      </div>

      <!-- Footer Info -->
      <%= unless @compact_view do %>
        <div class="px-6 py-4 bg-gray-50 border-t border-gray-200">
          <div class="flex items-center justify-between text-sm text-gray-500">
            <div>
              Last updated: <%= format_last_update(@poll) %>
            </div>
            <%= if @poll.voting_deadline do %>
              <div>
                <%= if @poll.status == "voting" do %>
                  Voting ends: <%= format_deadline(@poll.voting_deadline) %>
                <% else %>
                  Voting ended: <%= format_deadline(@poll.voting_deadline) %>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Binary Voting Results (Yes/No/Maybe)
  defp render_binary_results(assigns) do
    ~H"""
    <%= for {option, stats} <- @vote_analytics do %>
      <div class="px-6 py-4">
        <div class="flex items-start justify-between mb-3">
          <div class="flex-1 min-w-0">
            <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
            <%= if option.description do %>
              <p class="text-sm text-gray-500 mt-1"><%= option.description %></p>
            <% end %>
          </div>
          <div class="ml-4 text-right">
            <div class="text-sm font-medium text-gray-900">
              <%= stats.total_votes %> votes
            </div>
            <div class="text-xs text-gray-500">
              <%= format_percentage(stats.total_votes, @total_voters) %>
            </div>
          </div>
        </div>

        <!-- Yes/Maybe/No Bars -->
        <div class="space-y-2">
          <div class="flex items-center">
            <div class="w-12 text-xs text-gray-600">Yes</div>
            <div class="flex-1 mx-3">
              <div class="bg-gray-200 rounded-full h-2">
                <div
                  class="bg-green-500 h-2 rounded-full"
                  style={"width: #{stats.yes_percentage}%"}
                ></div>
              </div>
            </div>
            <div class="w-12 text-xs text-gray-900 text-right">
              <%= stats.yes_count %> (<%= round(stats.yes_percentage) %>%)
            </div>
          </div>

          <div class="flex items-center">
            <div class="w-12 text-xs text-gray-600">Maybe</div>
            <div class="flex-1 mx-3">
              <div class="bg-gray-200 rounded-full h-2">
                <div
                  class="bg-yellow-500 h-2 rounded-full"
                  style={"width: #{stats.maybe_percentage}%"}
                ></div>
              </div>
            </div>
            <div class="w-12 text-xs text-gray-900 text-right">
              <%= stats.maybe_count %> (<%= round(stats.maybe_percentage) %>%)
            </div>
          </div>

          <div class="flex items-center">
            <div class="w-12 text-xs text-gray-600">No</div>
            <div class="flex-1 mx-3">
              <div class="bg-gray-200 rounded-full h-2">
                <div
                  class="bg-red-500 h-2 rounded-full"
                  style={"width: #{stats.no_percentage}%"}
                ></div>
              </div>
            </div>
            <div class="w-12 text-xs text-gray-900 text-right">
              <%= stats.no_count %> (<%= round(stats.no_percentage) %>%)
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Approval Voting Results (Multiple selections)
  defp render_approval_results(assigns) do
    ~H"""
    <%= for {option, stats} <- sort_by_approval(@vote_analytics) do %>
      <div class="px-6 py-4">
        <div class="flex items-center justify-between mb-2">
          <div class="flex-1 min-w-0">
            <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
            <%= if option.description do %>
              <p class="text-sm text-gray-500 mt-1"><%= option.description %></p>
            <% end %>
          </div>
          <div class="ml-4 text-right">
            <div class="text-sm font-medium text-gray-900">
              <%= stats.approval_count %> approvals
            </div>
            <div class="text-xs text-gray-500">
              <%= format_percentage(stats.approval_count, @total_voters) %>
            </div>
          </div>
        </div>

        <!-- Approval Progress Bar -->
        <div class="flex items-center">
          <div class="flex-1">
            <div class="bg-gray-200 rounded-full h-3">
              <div
                class="bg-indigo-500 h-3 rounded-full transition-all duration-300"
                style={"width: #{stats.approval_percentage}%"}
              ></div>
            </div>
          </div>
          <div class="ml-3 text-sm font-medium text-gray-900">
            <%= round(stats.approval_percentage) %>%
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Ranked Choice Results (Rankings table)
  defp render_ranked_results(assigns) do
    ~H"""
    <div class="px-6 py-4">
      <div class="overflow-hidden">
        <table class="min-w-full">
          <thead>
            <tr class="border-b border-gray-200">
              <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Rank
              </th>
              <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Option
              </th>
              <th class="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                Points
              </th>
              <th class="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                1st Choice
              </th>
              <th class="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                Votes
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-100">
            <%= for {{option, stats}, index} <- Enum.with_index(sort_by_ranking(@vote_analytics)) do %>
              <tr class="hover:bg-gray-50">
                <td class="px-3 py-3">
                  <div class="flex items-center justify-center w-6 h-6 bg-gray-100 text-gray-700 text-sm font-medium rounded-full">
                    <%= index + 1 %>
                  </div>
                </td>
                <td class="px-3 py-3">
                  <div>
                    <div class="text-sm font-medium text-gray-900"><%= option.title %></div>
                    <%= if option.description do %>
                      <div class="text-xs text-gray-500"><%= truncate_text(option.description, 50) %></div>
                    <% end %>
                  </div>
                </td>
                <td class="px-3 py-3 text-center">
                  <div class="text-sm font-medium text-gray-900"><%= stats.total_points %></div>
                  <div class="text-xs text-gray-500">points</div>
                </td>
                <td class="px-3 py-3 text-center">
                  <div class="text-sm text-gray-900"><%= stats.first_choice_count %></div>
                  <div class="text-xs text-gray-500">
                    (<%= format_percentage(stats.first_choice_count, @total_voters) %>)
                  </div>
                </td>
                <td class="px-3 py-3 text-center">
                  <div class="text-sm text-gray-900"><%= stats.total_votes %></div>
                  <div class="text-xs text-gray-500">voters</div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  # Star Rating Results (Average ratings)
  defp render_star_results(assigns) do
    ~H"""
    <%= for {option, stats} <- sort_by_rating(@vote_analytics) do %>
      <div class="px-6 py-4">
        <div class="flex items-start justify-between mb-3">
          <div class="flex-1 min-w-0">
            <h4 class="text-sm font-medium text-gray-900"><%= option.title %></h4>
            <%= if option.description do %>
              <p class="text-sm text-gray-500 mt-1"><%= option.description %></p>
            <% end %>
          </div>
          <div class="ml-4 text-right">
            <div class="flex items-center">
              <%= render_star_display(stats.average_rating) %>
              <span class="ml-2 text-sm font-medium text-gray-900">
                <%= format_rating(stats.average_rating) %>
              </span>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              <%= stats.rating_count %> ratings
            </div>
          </div>
        </div>

        <!-- Rating Distribution -->
        <%= unless @compact_view do %>
          <div class="grid grid-cols-5 gap-1 mt-3">
            <%= for star <- 5..1//-1 do %>
              <div class="text-center">
                <div class="text-xs text-gray-500 mb-1"><%= star %>★</div>
                <div class="bg-gray-200 rounded h-16 flex items-end">
                  <div
                    class="bg-yellow-400 rounded w-full transition-all duration-300"
                    style={"height: #{get_star_percentage(stats, star)}%"}
                  ></div>
                </div>
                <div class="text-xs text-gray-500 mt-1">
                  <%= Map.get(stats.star_distribution, star, 0) %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Note: LiveComponents don't support handle_info callbacks
  # Real-time updates are handled by the parent LiveView which reloads the poll data

  # Private helper functions

  defp calculate_vote_analytics(poll) do
    case poll.voting_system do
      "binary" -> calculate_binary_analytics(poll)
      "approval" -> calculate_approval_analytics(poll)
      "ranked" -> calculate_ranked_analytics(poll)
      "star" -> calculate_star_analytics(poll)
    end
  end

  defp calculate_binary_analytics(poll) do
    poll.poll_options
    |> Enum.map(fn option ->
      votes = option.votes || []

      yes_count = Enum.count(votes, &(&1.vote_value == "yes"))
      maybe_count = Enum.count(votes, &(&1.vote_value == "maybe"))
      no_count = Enum.count(votes, &(&1.vote_value == "no"))
      total_votes = yes_count + maybe_count + no_count

      yes_percentage = if total_votes > 0, do: yes_count / total_votes * 100, else: 0
      maybe_percentage = if total_votes > 0, do: maybe_count / total_votes * 100, else: 0
      no_percentage = if total_votes > 0, do: no_count / total_votes * 100, else: 0

      stats = %{
        yes_count: yes_count,
        maybe_count: maybe_count,
        no_count: no_count,
        total_votes: total_votes,
        yes_percentage: yes_percentage,
        maybe_percentage: maybe_percentage,
        no_percentage: no_percentage
      }

      {option, stats}
    end)
    |> Enum.into(%{})
  end

  defp calculate_approval_analytics(poll) do
    total_voters = count_unique_voters(poll)

    poll.poll_options
    |> Enum.map(fn option ->
      votes = option.votes || []
      approval_count = length(votes)

      approval_percentage = if total_voters > 0, do: approval_count / total_voters * 100, else: 0

      stats = %{
        approval_count: approval_count,
        approval_percentage: approval_percentage
      }

      {option, stats}
    end)
    |> Enum.into(%{})
  end

  defp calculate_ranked_analytics(poll) do
    poll.poll_options
    |> Enum.map(fn option ->
      votes = option.votes || []

      # Calculate points (higher rank = more points)
      total_points =
        votes
        |> Enum.map(fn vote ->
          max_rank = length(poll.poll_options)
          rank = vote.vote_rank || max_rank
          max_rank - rank + 1
        end)
        |> Enum.sum()

      first_choice_count = Enum.count(votes, &(&1.vote_rank == 1))
      total_votes = length(votes)

      stats = %{
        total_points: total_points,
        first_choice_count: first_choice_count,
        total_votes: total_votes
      }

      {option, stats}
    end)
    |> Enum.into(%{})
  end

  defp calculate_star_analytics(poll) do
    poll.poll_options
    |> Enum.map(fn option ->
      votes = option.votes || []

      ratings =
        Enum.map(votes, fn vote ->
          if vote.vote_numeric, do: Decimal.to_float(vote.vote_numeric), else: 0
        end)

      rating_count = length(ratings)
      average_rating = if rating_count > 0, do: Enum.sum(ratings) / rating_count, else: 0

      # Calculate distribution
      star_distribution =
        1..5
        |> Enum.map(fn star ->
          count = Enum.count(ratings, &(trunc(&1) == star))
          {star, count}
        end)
        |> Enum.into(%{})

      stats = %{
        average_rating: average_rating,
        rating_count: rating_count,
        star_distribution: star_distribution
      }

      {option, stats}
    end)
    |> Enum.into(%{})
  end

  defp count_unique_voters(poll) do
    poll.poll_options
    |> Enum.flat_map(fn option -> option.votes || [] end)
    |> Enum.map(& &1.voter_id)
    |> Enum.uniq()
    |> length()
  end

  # Sorting helpers
  defp sort_by_approval(analytics) do
    analytics
    |> Enum.sort_by(fn {_option, stats} -> stats.approval_count end, :desc)
  end

  defp sort_by_ranking(analytics) do
    analytics
    |> Enum.sort_by(fn {_option, stats} -> stats.total_points end, :desc)
  end

  defp sort_by_rating(analytics) do
    analytics
    |> Enum.sort_by(fn {_option, stats} -> stats.average_rating end, :desc)
  end

  # UI Helper Functions

  defp get_results_summary(voting_system, analytics) do
    case voting_system do
      "binary" -> "Yes/Maybe/No voting results"
      "approval" -> "#{map_size(analytics)} options • Approval voting"
      "ranked" -> "#{map_size(analytics)} options • Ranked by points"
      "star" -> "#{map_size(analytics)} options • Average ratings"
    end
  end

  defp render_star_display(rating) do
    assigns = %{rating: rating}

    ~H"""
    <div class="flex items-center">
      <%= for star <- 1..5 do %>
        <svg class={"h-4 w-4 #{if @rating >= star, do: "text-yellow-400", else: "text-gray-300"}"} fill="currentColor" viewBox="0 0 20 20">
          <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
        </svg>
      <% end %>
    </div>
    """
  end

  defp get_star_percentage(stats, star) do
    total = stats.rating_count
    count = Map.get(stats.star_distribution, star, 0)
    if total > 0, do: count / total * 100, else: 0
  end

  defp format_rating(rating) do
    :erlang.float_to_binary(rating, decimals: 1)
  end

  defp format_percentage(count, total) do
    if total > 0 do
      percentage = count / total * 100
      "#{round(percentage)}%"
    else
      "0%"
    end
  end

  defp format_last_update(poll) do
    case poll.updated_at do
      %DateTime{} = dt ->
        now = DateTime.utc_now()
        diff = DateTime.diff(now, dt, :minute)

        cond do
          diff < 1 -> "just now"
          diff < 60 -> "#{diff}m ago"
          diff < 1440 -> "#{div(diff, 60)}h ago"
          true -> "#{div(diff, 1440)}d ago"
        end

      _ ->
        "unknown"
    end
  end

  defp format_deadline(deadline) do
    case deadline do
      %DateTime{} = dt ->
        dt
        |> DateTime.to_date()
        |> Date.to_string()

      _ ->
        "Not set"
    end
  end

  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end
end
