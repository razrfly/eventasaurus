defmodule EventasaurusWeb.Helpers.PollStatsHelper do
  @moduledoc """
  Helper module for calculating and formatting poll statistics for embedded display.
  
  Provides unified functions for extracting simplified statistics from poll data
  and formatting them for display within voting interfaces.
  """

  @doc """
  Extracts simplified statistics for a specific poll option based on voting system.
  
  ## Parameters
  - `poll_stats`: The poll statistics data structure from Events.get_poll_voting_stats/1
  - `option_id`: The ID of the specific poll option
  - `voting_system`: The voting system type ("binary", "approval", "ranked", "star")
  
  ## Returns
  A map containing simplified statistics appropriate for the voting system:
  - Binary: `%{total_votes: integer, positive_percentage: float}`
  - Approval: `%{total_votes: integer, approval_percentage: float}`
  - Ranked: `%{total_votes: integer, average_rank: float}`
  - Star: `%{total_votes: integer, average_rating: float, positive_percentage: float}`
  """
  def get_simplified_option_stats(poll_stats, option_id, voting_system) do
    case poll_stats do
      %{options: options} when is_list(options) ->
        case Enum.find(options, &(&1.option_id == option_id)) do
          %{tally: tally} ->
            calculate_stats_for_system(tally, voting_system)
          _ ->
            default_stats_for_system(voting_system)
        end
      _ ->
        default_stats_for_system(voting_system)
    end
  end

  @doc """
  Calculates breakdown percentages for binary voting (Yes/Maybe/No).
  
  ## Parameters
  - `poll_stats`: The poll statistics data structure
  - `option_id`: The ID of the specific poll option
  
  ## Returns
  A map with percentage breakdowns:
  `%{yes_percentage: float, maybe_percentage: float, no_percentage: float}`
  """
  def get_binary_breakdown(poll_stats, option_id) do
    case poll_stats do
      %{options: options} when is_list(options) ->
        option_data = Enum.find(options, &(&1.option_id == option_id))
        
        case option_data do
          %{tally: tally} ->
            total_votes = Map.get(tally, :total, 0)
            yes_count = Map.get(tally, :yes, 0)
            maybe_count = Map.get(tally, :maybe, 0)
            no_count = Map.get(tally, :no, 0)

            %{
              yes_percentage: safe_percentage(yes_count, total_votes),
              maybe_percentage: safe_percentage(maybe_count, total_votes),
              no_percentage: safe_percentage(no_count, total_votes)
            }
          _ ->
            %{yes_percentage: 0.0, maybe_percentage: 0.0, no_percentage: 0.0}
        end
      _ ->
        %{yes_percentage: 0.0, maybe_percentage: 0.0, no_percentage: 0.0}
    end
  end

  @doc """
  Calculates star rating breakdown for star voting system.
  
  ## Parameters
  - `poll_stats`: The poll statistics data structure
  - `option_id`: The ID of the specific poll option
  
  ## Returns
  A map with star rating percentages:
  `%{one_star_percentage: float, two_star_percentage: float, ...}`
  """
  def get_star_breakdown(poll_stats, option_id) do
    case poll_stats do
      %{options: options} when is_list(options) ->
        option_data = Enum.find(options, &(&1.option_id == option_id))
        
        case option_data do
          %{tally: tally} ->
            total_votes = Map.get(tally, :total, 0)
            rating_distribution = Map.get(tally, :rating_distribution, [])

            # Extract counts for each star rating
            star_counts = rating_distribution
            |> Enum.reduce(%{1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0}, fn
              %{rating: rating, count: count}, acc when rating in 1..5 ->
                Map.put(acc, rating, count)
              _, acc -> acc
            end)

            %{
              one_star_percentage: safe_percentage(star_counts[1], total_votes),
              two_star_percentage: safe_percentage(star_counts[2], total_votes),
              three_star_percentage: safe_percentage(star_counts[3], total_votes),
              four_star_percentage: safe_percentage(star_counts[4], total_votes),
              five_star_percentage: safe_percentage(star_counts[5], total_votes)
            }
          _ ->
            default_star_breakdown()
        end
      _ ->
        default_star_breakdown()
    end
  end

  @doc """
  Converts average rank to a quality percentage for visual display.
  Lower rank numbers (better performance) get longer bars.
  
  ## Parameters
  - `average_rank`: The average rank as a float
  
  ## Returns
  A percentage value between 20 and 100 representing rank display width
  """
  def get_rank_quality_percentage(average_rank) when is_number(average_rank) do
    # Better ranks (lower numbers) get longer bars
    # Formula: Invert the rank so rank 1 = 100%, rank 5 = 20%
    # Using max rank of 5 for calculation: max(20, 120 - (average_rank * 20))
    quality_percentage = max(20, 120 - (average_rank * 20))
    min(100, quality_percentage)
  end

  def get_rank_quality_percentage(_), do: 0.0

  @doc """
  Gets the appropriate color class for ranked voting based on average rank.
  Better ranks (lower numbers) get better colors.
  
  ## Parameters
  - `average_rank`: The average rank as a float
  
  ## Returns
  A CSS color class string
  """
  def get_rank_color_class(average_rank) when is_number(average_rank) do
    cond do
      average_rank <= 1.5 -> "bg-green-500"    # Excellent (rank 1-1.5)
      average_rank <= 2.0 -> "bg-blue-500"     # Good (rank 1.5-2.0)
      average_rank <= 2.5 -> "bg-yellow-500"   # Average (rank 2.0-2.5)
      average_rank <= 3.0 -> "bg-orange-500"   # Below average (rank 2.5-3.0)
      true -> "bg-red-500"                      # Poor (rank 3.0+)
    end
  end

  def get_rank_color_class(_), do: "bg-gray-400"

  @doc """
  Formats vote counts with proper pluralization.
  
  ## Parameters
  - `count`: The number of votes
  - `singular`: The singular form (e.g., "vote")
  - `plural`: The plural form (e.g., "votes")
  
  ## Returns
  A formatted string like "1 vote" or "5 votes"
  """
  def format_vote_count(count, singular, plural \\ nil) do
    plural = plural || "#{singular}s"
    if count == 1, do: "#{count} #{singular}", else: "#{count} #{plural}"
  end

  @doc """
  Formats percentage values for display.
  
  ## Parameters
  - `percentage`: The percentage as a float
  - `decimal_places`: Number of decimal places (default: 1)
  
  ## Returns
  A formatted percentage string like "75.5%"
  """
  def format_percentage(percentage, decimal_places \\ 1) do
    "#{Float.round(percentage, decimal_places)}%"
  end

  # Private helper functions

  defp calculate_stats_for_system(tally, voting_system) do
    case voting_system do
      "binary" ->
        total_votes = Map.get(tally, :total, 0)
        yes_count = Map.get(tally, :yes, 0)
        maybe_count = Map.get(tally, :maybe, 0)
        positive_count = yes_count + maybe_count
        
        %{
          total_votes: total_votes,
          positive_percentage: safe_percentage(positive_count, total_votes)
        }

      "approval" ->
        total_votes = Map.get(tally, :selected, 0)
        approval_percentage = Map.get(tally, :percentage, 0.0)

        %{
          total_votes: total_votes,
          approval_percentage: Float.round(approval_percentage, 1)
        }

      "star" ->
        total_votes = Map.get(tally, :total, 0)
        average_rating = Map.get(tally, :average_rating, 0.0)
        # Consider 4-5 stars as positive
        rating_distribution = Map.get(tally, :rating_distribution, [])
        positive_ratings = Enum.reduce(rating_distribution, 0, fn
          %{rating: rating, count: count}, acc when rating >= 4 -> acc + count
          _, acc -> acc
        end)
        
        %{
          total_votes: total_votes,
          average_rating: Float.round(average_rating, 1),
          positive_percentage: safe_percentage(positive_ratings, total_votes)
        }

      "ranked" ->
        total_votes = Map.get(tally, :total, 0)
        average_rank = Map.get(tally, :average_rank, 0.0)

        %{
          total_votes: total_votes,
          average_rank: Float.round(average_rank, 1)
        }

      _ ->
        %{total_votes: 0}
    end
  end

  defp default_stats_for_system(voting_system) do
    case voting_system do
      "binary" -> %{total_votes: 0, positive_percentage: 0.0}
      "approval" -> %{total_votes: 0, approval_percentage: 0.0}
      "star" -> %{total_votes: 0, average_rating: 0.0, positive_percentage: 0.0}
      "ranked" -> %{total_votes: 0, average_rank: 0.0}
      _ -> %{total_votes: 0}
    end
  end

  defp default_star_breakdown do
    %{
      one_star_percentage: 0.0,
      two_star_percentage: 0.0,
      three_star_percentage: 0.0,
      four_star_percentage: 0.0,
      five_star_percentage: 0.0
    }
  end

  defp safe_percentage(numerator, denominator) when denominator > 0 do
    Float.round((numerator / denominator) * 100, 1)
  end

  defp safe_percentage(_, _), do: 0.0
end