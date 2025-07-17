defmodule EventasaurusWeb.Helpers.VoteCountHelper do
  @moduledoc "Shared helper for calculating vote counts."

  @doc """
  Calculates vote count from percentage and total votes.
  
  ## Parameters
  - `percentage`: The percentage as a float
  - `total_votes`: The total number of votes as an integer
  
  ## Returns
  The calculated vote count as an integer
  """
  @spec calculate_vote_count(number(), non_neg_integer()) :: non_neg_integer()
  def calculate_vote_count(percentage, total_votes) do
    round(percentage * total_votes / 100)
  end
end