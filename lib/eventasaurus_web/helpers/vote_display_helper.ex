defmodule EventasaurusWeb.Helpers.VoteDisplayHelper do
  @moduledoc """
  Helper module for formatting and displaying vote-related information.

  Provides utilities for formatting vote counts, percentages, and other
  vote-related data in a consistent way across the application.
  """

  alias EventasaurusWeb.Utils.TimeUtils

  @doc """
  Formats a vote count with proper pluralization and optional percentage.

  ## Parameters
  - `count`: The number of votes
  - `total`: Total votes for percentage calculation (optional)
  - `label`: Base label (e.g., "vote", "approval", "rating")
  - `opts`: Options for formatting

  ## Returns
  A formatted string like "5 votes (25%)" or "1 approval"

  ## Examples
      iex> VoteDisplayHelper.format_vote_count(1, "vote")
      "1 vote"
      
      iex> VoteDisplayHelper.format_vote_count(5, "vote")
      "5 votes"
      
      iex> VoteDisplayHelper.format_vote_count(5, 20, "vote")
      "5 votes (25%)"
  """
  def format_vote_count(count, total \\ nil, label, opts \\ [])

  def format_vote_count(count, nil, label, _opts) do
    pluralized_label = if count == 1, do: label, else: "#{label}s"
    "#{count} #{pluralized_label}"
  end

  def format_vote_count(count, total, label, opts) do
    show_percentage = Keyword.get(opts, :show_percentage, true)
    pluralized_label = if count == 1, do: label, else: "#{label}s"
    base_text = "#{count} #{pluralized_label}"

    if show_percentage and total > 0 do
      percentage = Float.round(count / total * 100, 1)
      "#{base_text} (#{percentage}%)"
    else
      base_text
    end
  end

  @doc """
  Formats a percentage value for display.

  ## Parameters
  - `percentage`: The percentage as a float
  - `opts`: Options for formatting

  ## Returns
  A formatted percentage string

  ## Examples
      iex> VoteDisplayHelper.format_percentage(75.5)
      "75.5%"
      
      iex> VoteDisplayHelper.format_percentage(75.5, decimal_places: 0)
      "76%"
  """
  def format_percentage(percentage, opts \\ []) do
    decimal_places = Keyword.get(opts, :decimal_places, 1)
    rounded = Float.round(percentage, decimal_places)

    if decimal_places == 0 do
      "#{round(rounded)}%"
    else
      "#{rounded}%"
    end
  end

  @doc """
  Formats a star rating for display.

  ## Parameters
  - `rating`: The rating as a float
  - `opts`: Options for formatting

  ## Returns
  A formatted rating string

  ## Examples
      iex> VoteDisplayHelper.format_star_rating(4.5)
      "⭐ 4.5/5"
      
      iex> VoteDisplayHelper.format_star_rating(4.5, show_emoji: false)
      "4.5/5"
  """
  def format_star_rating(rating, opts \\ []) do
    show_emoji = Keyword.get(opts, :show_emoji, true)
    decimal_places = Keyword.get(opts, :decimal_places, 1)

    formatted_rating = Float.round(rating, decimal_places)

    if show_emoji do
      "⭐ #{formatted_rating}/5"
    else
      "#{formatted_rating}/5"
    end
  end

  @doc """
  Formats a rank for display.

  ## Parameters
  - `rank`: The rank as a float
  - `opts`: Options for formatting

  ## Returns
  A formatted rank string

  ## Examples
      iex> VoteDisplayHelper.format_rank(2.3)
      "Avg rank: 2.3"
      
      iex> VoteDisplayHelper.format_rank(2.3, show_label: false)
      "2.3"
  """
  def format_rank(rank, opts \\ []) do
    show_label = Keyword.get(opts, :show_label, true)
    decimal_places = Keyword.get(opts, :decimal_places, 1)

    formatted_rank = Float.round(rank, decimal_places)

    if show_label do
      "Avg rank: #{formatted_rank}"
    else
      "#{formatted_rank}"
    end
  end

  @doc """
  Gets the appropriate CSS classes for vote status indicators.

  ## Parameters
  - `vote_value`: The vote value (e.g., "yes", "no", "maybe")
  - `voting_system`: The voting system type
  - `opts`: Options for styling

  ## Returns
  A string of CSS classes

  ## Examples
      iex> VoteDisplayHelper.get_vote_status_classes("yes", "binary")
      "bg-green-100 text-green-800"
      
      iex> VoteDisplayHelper.get_vote_status_classes("no", "binary")
      "bg-red-100 text-red-800"
  """
  def get_vote_status_classes(vote_value, voting_system, opts \\ []) do
    anonymous_mode = Keyword.get(opts, :anonymous_mode, false)

    base_classes =
      case {voting_system, vote_value} do
        {"binary", "yes"} -> "bg-green-100 text-green-800"
        {"binary", "no"} -> "bg-red-100 text-red-800"
        {"binary", "maybe"} -> "bg-yellow-100 text-yellow-800"
        {"approval", "approved"} -> "bg-green-100 text-green-800"
        {"star", _} when is_number(vote_value) -> "bg-yellow-100 text-yellow-800"
        {"ranked", _} when is_number(vote_value) -> "bg-indigo-100 text-indigo-800"
        _ -> "bg-gray-100 text-gray-800"
      end

    if anonymous_mode do
      # Add subtle blue tint for anonymous mode
      String.replace(base_classes, ~r/bg-(\w+)-100/, "bg-blue-50 border border-blue-200")
    else
      base_classes
    end
  end

  @doc """
  Formats a time range for display.

  ## Parameters
  - `start_time`: Start time string
  - `end_time`: End time string
  - `opts`: Options for formatting

  ## Returns
  A formatted time range string

  ## Examples
      iex> VoteDisplayHelper.format_time_range("14:00", "16:00")
      "2:00 PM - 4:00 PM"
  """
  def format_time_range(start_time, end_time, opts \\ [])
      when is_binary(start_time) and is_binary(end_time) do
    format_24h = Keyword.get(opts, :format_24h, true)

    if format_24h do
      "#{start_time} - #{end_time}"
    else
      # Convert to 12-hour format (legacy, not recommended)
      start_display = TimeUtils.format_time_12hour(start_time)
      end_display = TimeUtils.format_time_12hour(end_time)
      "#{start_display} - #{end_display}"
    end
  end

  @doc """
  Gets appropriate color classes for progress bars based on voting system.

  ## Parameters
  - `voting_system`: The voting system type
  - `value_type`: The specific value type (e.g., "yes", "star_4", "rank_high")

  ## Returns
  A string of CSS classes for the progress bar segment
  """
  def get_progress_bar_color_classes(voting_system, value_type) do
    case {voting_system, value_type} do
      {"binary", "yes"} -> "bg-green-500"
      {"binary", "maybe"} -> "bg-yellow-400"
      {"binary", "no"} -> "bg-red-400"
      {"approval", "approved"} -> "bg-green-500"
      {"star", "1"} -> "bg-red-400"
      {"star", "2"} -> "bg-orange-400"
      {"star", "3"} -> "bg-yellow-400"
      {"star", "4"} -> "bg-lime-500"
      {"star", "5"} -> "bg-green-500"
      {"ranked", "quality"} -> "bg-indigo-500"
      _ -> "bg-gray-400"
    end
  end

  @doc """
  Determines if a vote count should be considered "significant" for display purposes.

  ## Parameters
  - `count`: The vote count
  - `total`: Total possible votes
  - `threshold`: Minimum percentage threshold (default: 5%)

  ## Returns
  Boolean indicating if the count is significant
  """
  def significant_vote_count?(count, total, threshold \\ 5) do
    if total == 0 do
      false
    else
      percentage = count / total * 100
      percentage >= threshold
    end
  end

  @doc """
  Formats a complete voting summary for a poll option.

  ## Parameters
  - `option`: The poll option
  - `stats`: Statistics for the option
  - `voting_system`: The voting system type
  - `opts`: Options for formatting

  ## Returns
  A formatted summary string
  """
  def format_option_summary(_option, stats, voting_system, opts \\ []) do
    compact = Keyword.get(opts, :compact, false)

    base_summary =
      case voting_system do
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

    if compact do
      # Shorten labels for compact display
      String.replace(base_summary, ~r/approval rate/, "approval")
      |> String.replace(~r/positive/, "pos")
      |> String.replace(~r/rankings/, "ranks")
      |> String.replace(~r/rating/, "rat")
    else
      base_summary
    end
  end
end
