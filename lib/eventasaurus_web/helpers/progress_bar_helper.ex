defmodule EventasaurusWeb.Helpers.ProgressBarHelper do
  @moduledoc """
  Helper module for rendering progress bars and visual indicators for poll voting.
  
  Provides functions for generating progress bar HTML and CSS classes
  tailored to different voting systems and accessibility requirements.
  """

  import Phoenix.HTML
  
  alias EventasaurusWeb.Helpers.VoteCountHelper, as: VC

  @doc """
  Renders a horizontal progress bar for binary voting (Yes/Maybe/No).
  
  ## Parameters
  - `breakdown`: Map with yes_percentage, maybe_percentage, no_percentage
  - `total_votes`: Total number of votes for display
  - `opts`: Options for customization
  
  ## Returns
  Phoenix.HTML.safe() content for the progress bar
  """
  def render_binary_progress_bar(breakdown, total_votes, opts \\ []) do
    compact = Keyword.get(opts, :compact, false)
    show_labels = Keyword.get(opts, :show_labels, true)
    
    height_class = if compact, do: "h-1.5", else: "h-2"
    
    ~s"""
    <div class="#{if compact, do: "mb-1", else: "mb-2"}">
      #{if show_labels and total_votes > 0 do
        render_binary_labels(breakdown, total_votes)
      else
        ""
      end}
      <div class="flex #{height_class} bg-gray-100 rounded-full overflow-hidden">
        #{if total_votes > 0 do
          render_binary_segments(breakdown, height_class)
        else
          ~s(<div class="bg-gray-200 w-full"></div>)
        end}
      </div>
    </div>
    """
    |> raw()
  end

  @doc """
  Renders a progress bar for approval voting.
  
  ## Parameters
  - `approval_percentage`: Approval percentage as float
  - `total_votes`: Total number of votes
  - `opts`: Options for customization
  
  ## Returns
  Phoenix.HTML.safe() content for the progress bar
  """
  def render_approval_progress_bar(approval_percentage, total_votes, opts \\ []) do
    compact = Keyword.get(opts, :compact, false)
    show_count = Keyword.get(opts, :show_count, true)
    
    height_class = if compact, do: "h-1.5", else: "h-2"
    
    ~s"""
    <div class="#{if compact, do: "mb-1", else: "mb-2"}">
      #{if show_count and total_votes > 0 do
        ~s(<div class="text-xs text-gray-500 mb-1">#{total_votes} #{if total_votes == 1, do: "approval", else: "approvals"} • #{Float.round(approval_percentage, 1)}%</div>)
      else
        ""
      end}
      <div class="flex #{height_class} bg-gray-100 rounded-full overflow-hidden">
        <div class="bg-green-500" style="width: #{approval_percentage}%"></div>
      </div>
    </div>
    """
    |> raw()
  end

  @doc """
  Renders a progress bar for ranked voting showing rank quality.
  
  ## Parameters
  - `average_rank`: Average rank as float
  - `total_votes`: Total number of votes
  - `opts`: Options for customization
  
  ## Returns
  Phoenix.HTML.safe() content for the progress bar
  """
  def render_ranked_progress_bar(average_rank, total_votes, opts \\ []) do
    compact = Keyword.get(opts, :compact, false)
    show_labels = Keyword.get(opts, :show_labels, true)
    
    height_class = if compact, do: "h-1.5", else: "h-2"
    rank_quality_percentage = get_rank_quality_percentage(average_rank)
    
    ~s"""
    <div class="#{if compact, do: "mb-1", else: "mb-2"}">
      #{if show_labels and total_votes > 0 do
        ~s(<div class="text-xs text-gray-500 mb-1">Avg rank: #{Float.round(average_rank, 1)} • #{total_votes} #{if total_votes == 1, do: "ranking", else: "rankings"}</div>)
      else
        ""
      end}
      <div class="flex #{height_class} bg-gray-100 rounded-full overflow-hidden">
        <div class="bg-indigo-500" style="width: #{rank_quality_percentage}%"></div>
      </div>
    </div>
    """
    |> raw()
  end

  @doc """
  Renders a progress bar for star voting showing rating distribution.
  
  ## Parameters
  - `star_breakdown`: Map with star rating percentages
  - `average_rating`: Average rating as float
  - `total_votes`: Total number of votes
  - `opts`: Options for customization
  
  ## Returns
  Phoenix.HTML.safe() content for the progress bar
  """
  def render_star_progress_bar(star_breakdown, average_rating, total_votes, opts \\ []) do
    compact = Keyword.get(opts, :compact, false)
    show_labels = Keyword.get(opts, :show_labels, true)
    
    height_class = if compact, do: "h-1.5", else: "h-2"
    positive_percentage = star_breakdown.four_star_percentage + star_breakdown.five_star_percentage
    
    ~s"""
    <div class="#{if compact, do: "mb-1", else: "mb-2"}">
      #{if show_labels and total_votes > 0 do
        ~s(<div class="text-xs text-gray-500 mb-1">⭐ #{Float.round(average_rating, 1)}/5 • #{Float.round(positive_percentage, 1)}% positive • #{total_votes} #{if total_votes == 1, do: "rating", else: "ratings"}</div>)
      else
        ""
      end}
      <div class="flex #{height_class} bg-gray-100 rounded-full overflow-hidden">
        #{if total_votes > 0 do
          render_star_segments(star_breakdown, height_class)
        else
          ~s(<div class="bg-gray-200 w-full"></div>)
        end}
      </div>
    </div>
    """
    |> raw()
  end

  @doc """
  Renders a compact vote count badge.
  
  ## Parameters
  - `count`: Number of votes
  - `label`: Label for the votes (e.g., "votes", "approvals")
  - `opts`: Options for styling
  
  ## Returns
  Phoenix.HTML.safe() content for the badge
  """
  def render_vote_count_badge(count, label, opts \\ []) do
    color = Keyword.get(opts, :color, "gray")
    size = Keyword.get(opts, :size, "sm")
    
    color_classes = get_badge_color_classes(color)
    size_classes = get_badge_size_classes(size)
    
    ~s"""
    <span class="inline-flex items-center rounded-full #{color_classes} #{size_classes}">
      #{count} #{if count == 1, do: String.trim_trailing(label, "s"), else: label}
    </span>
    """
    |> raw()
  end

  @doc """
  Renders a simple statistics summary line.
  
  ## Parameters
  - `stats`: Map of statistics to display
  - `voting_system`: The voting system type
  - `opts`: Options for customization
  
  ## Returns
  Phoenix.HTML.safe() content for the summary
  """
  def render_stats_summary(stats, voting_system, opts \\ []) do
    compact = Keyword.get(opts, :compact, false)
    text_class = if compact, do: "text-xs", else: "text-sm"
    
    summary_text = case voting_system do
      "binary" ->
        "#{stats.total_votes} #{if stats.total_votes == 1, do: "vote", else: "votes"} • #{stats.positive_percentage}% positive"
      
      "approval" ->
        "#{stats.total_votes} #{if stats.total_votes == 1, do: "approval", else: "approvals"} • #{stats.approval_percentage}% approval rate"
      
      "ranked" ->
        "Avg rank: #{stats.average_rank} • #{stats.total_votes} #{if stats.total_votes == 1, do: "ranking", else: "rankings"}"
      
      "star" ->
        "⭐ #{stats.average_rating}/5 • #{stats.positive_percentage}% positive • #{stats.total_votes} #{if stats.total_votes == 1, do: "rating", else: "ratings"}"
      
      _ ->
        "#{stats.total_votes} #{if stats.total_votes == 1, do: "vote", else: "votes"}"
    end
    
    ~s"""
    <div class="#{text_class} text-gray-500 mb-1">
      #{summary_text}
    </div>
    """
    |> raw()
  end

  # Private helper functions

  defp render_binary_labels(breakdown, total_votes) do
    ~s"""
    <div class="flex justify-between text-xs text-gray-500 mb-1">
      <span>#{VC.calculate_vote_count(breakdown.yes_percentage, total_votes)} Yes</span>
      <span>#{VC.calculate_vote_count(breakdown.maybe_percentage, total_votes)} Maybe</span>
      <span>#{VC.calculate_vote_count(breakdown.no_percentage, total_votes)} No</span>
    </div>
    """
  end

  defp render_binary_segments(breakdown, height_class) do
    ~s"""
    <div class="bg-green-500 #{height_class}" style="width: #{breakdown.yes_percentage}%"></div>
    <div class="bg-yellow-400 #{height_class}" style="width: #{breakdown.maybe_percentage}%"></div>
    <div class="bg-red-400 #{height_class}" style="width: #{breakdown.no_percentage}%"></div>
    """
  end

  defp render_star_segments(star_breakdown, height_class) do
    ~s"""
    <div class="bg-red-400 #{height_class}" style="width: #{star_breakdown.one_star_percentage}%"></div>
    <div class="bg-orange-400 #{height_class}" style="width: #{star_breakdown.two_star_percentage}%"></div>
    <div class="bg-yellow-400 #{height_class}" style="width: #{star_breakdown.three_star_percentage}%"></div>
    <div class="bg-lime-500 #{height_class}" style="width: #{star_breakdown.four_star_percentage}%"></div>
    <div class="bg-green-500 #{height_class}" style="width: #{star_breakdown.five_star_percentage}%"></div>
    """
  end

  defp get_badge_color_classes(color) do
    case color do
      "green" -> "bg-green-100 text-green-800"
      "blue" -> "bg-blue-100 text-blue-800"
      "yellow" -> "bg-yellow-100 text-yellow-800"
      "red" -> "bg-red-100 text-red-800"
      "indigo" -> "bg-indigo-100 text-indigo-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp get_badge_size_classes(size) do
    case size do
      "xs" -> "px-2 py-0.5 text-xs font-medium"
      "sm" -> "px-2.5 py-0.5 text-xs font-medium"
      "md" -> "px-3 py-1 text-sm font-medium"
      _ -> "px-2.5 py-0.5 text-xs font-medium"
    end
  end


  defp get_rank_quality_percentage(average_rank) when is_number(average_rank) do
    # Convert rank to percentage where rank 1 = 100%, rank 5 = 20%
    quality_percentage = max(0, 120 - (average_rank * 20))
    min(100, quality_percentage)
  end

  defp get_rank_quality_percentage(_), do: 0.0
end