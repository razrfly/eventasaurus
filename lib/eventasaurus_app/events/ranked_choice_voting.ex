defmodule EventasaurusApp.Events.RankedChoiceVoting do
  @moduledoc """
  Implements Instant Runoff Voting (IRV) algorithm for ranked choice polls.
  
  IRV works by:
  1. Counting first-choice votes
  2. If no candidate has majority (>50%), eliminate the lowest
  3. Redistribute eliminated candidate's votes to next preferences
  4. Repeat until a winner emerges with majority
  """

  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}
  alias EventasaurusApp.Repo
  import Ecto.Query
  
  # Simple in-memory cache for IRV results
  @irv_cache_name :irv_results_cache

  @doc """
  Calculate the IRV winner for a poll with all round-by-round details.
  Uses caching to avoid recalculating unchanged results.
  
  Returns:
    %{
      winner: %PollOption{} | nil,
      rounds: [round_details],
      final_percentages: %{option_id => percentage},
      total_voters: integer,
      majority_threshold: integer
    }
  """
  def calculate_irv_winner(%Poll{id: poll_id} = poll) do
    # Generate cache key based on vote hash for this poll
    cache_key = generate_cache_key(poll_id)
    
    case get_cached_result(cache_key) do
      nil ->
        # Calculate fresh result and cache it
        result = calculate_irv_winner_uncached(poll)
        cache_result(cache_key, result)
        result
      cached_result ->
        cached_result
    end
  end

  # Calculate IRV winner without caching (internal function)
  defp calculate_irv_winner_uncached(%Poll{id: poll_id}) do
    # Get all votes and options
    votes = get_ranked_votes(poll_id)
    options = get_poll_options(poll_id)
    
    total_voters = count_unique_voters(votes)
    majority_threshold = div(total_voters, 2) + 1
    
    if total_voters == 0 do
      %{
        winner: nil,
        rounds: [],
        final_percentages: %{},
        total_voters: 0,
        majority_threshold: 0
      }
    else
      # Run IRV rounds
      rounds = run_irv_rounds(votes, options, nil, [])
      
      # Determine winner and final state
      winner = determine_winner(rounds)
      final_percentages = calculate_final_percentages(rounds, total_voters)
      
      %{
        winner: winner,
        rounds: rounds,
        final_percentages: final_percentages,
        total_voters: total_voters,
        majority_threshold: majority_threshold
      }
    end
  end

  @doc """
  Get a simplified leaderboard for display.
  
  Returns:
    [
      %{
        position: 1,
        option: %PollOption{},
        votes: integer,
        percentage: float,
        status: :winner | :runner_up | :eliminated,
        eliminated_round: integer | nil
      }
    ]
  """
  def get_leaderboard(%Poll{} = poll) do
    result = calculate_irv_winner(poll)
    
    if result.total_voters == 0 do
      []
    else
      build_leaderboard(result)
    end
  end

  # Private functions

  defp get_ranked_votes(poll_id) do
    PollVote
    |> join(:inner, [v], o in PollOption, on: v.poll_option_id == o.id)
    |> where([v, o], o.poll_id == ^poll_id and not is_nil(v.vote_rank))
    |> where([v, o], is_nil(v.deleted_at) and is_nil(o.deleted_at))
    |> select([v, o], %{
      voter_id: v.voter_id,
      vote_rank: v.vote_rank,
      poll_option_id: v.poll_option_id
    })
    |> Repo.all()
  end

  defp get_poll_options(poll_id) do
    PollOption
    |> where([o], o.poll_id == ^poll_id)
    |> where([o], is_nil(o.deleted_at))
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp count_unique_voters(votes) do
    votes
    |> Enum.map(& &1.voter_id)
    |> Enum.uniq()
    |> length()
  end

  defp run_irv_rounds(votes, options, _majority_threshold, rounds) do
    # Group votes by voter to track their full ballot
    ballots = group_votes_by_voter(votes)
    
    # Run elimination rounds - majority threshold now calculated per round based on active ballots
    run_elimination_rounds(ballots, Map.keys(options), options, nil, rounds, 1)
  end

  defp group_votes_by_voter(votes) do
    votes
    |> Enum.group_by(& &1.voter_id)
    |> Enum.map(fn {voter_id, voter_votes} ->
      # Sort by rank to get preference order
      sorted_votes = Enum.sort_by(voter_votes, & &1.vote_rank)
      option_ids = Enum.map(sorted_votes, & &1.poll_option_id)
      {voter_id, option_ids}
    end)
    |> Map.new()
  end

  defp run_elimination_rounds(ballots, active_options, all_options, _majority_threshold, rounds, round_num) do
    # Count first preferences among active options
    vote_counts = count_first_preferences(ballots, active_options)
    
    # Calculate percentages and active majority threshold based on current ballots
    total_votes = Enum.sum(Map.values(vote_counts))
    active_majority_threshold = div(total_votes, 2) + 1
    
    if total_votes == 0 do
      # No more votes, end here
      rounds
    else
      percentages = Map.new(vote_counts, fn {option_id, count} ->
        {option_id, (count / total_votes) * 100}
      end)
      
      # Create round summary
      round = %{
        round_number: round_num,
        vote_counts: vote_counts,
        percentages: percentages,
        active_options: active_options,
        eliminated: nil
      }
      
      # Check for majority winner
      {_leading_option, leading_votes} = Enum.max_by(vote_counts, fn {_, v} -> v end, fn -> {nil, 0} end)
      
      cond do
        # Someone has majority
        leading_votes >= active_majority_threshold ->
          [round | rounds] |> Enum.reverse()
        
        # Only one candidate left
        length(active_options) <= 1 ->
          [round | rounds] |> Enum.reverse()
        
        # Need to eliminate lowest
        true ->
          # Find option(s) with lowest votes
          min_votes = vote_counts |> Map.values() |> Enum.min()
          lowest_options = vote_counts
            |> Enum.filter(fn {_, v} -> v == min_votes end)
            |> Enum.map(fn {k, _} -> k end)
          
          # Eliminate one (in case of tie, eliminate first by ID for deterministic behavior)
          eliminated = Enum.min(lowest_options)
          
          # Update round with elimination
          round = Map.put(round, :eliminated, eliminated)
          
          # Remove eliminated option and continue
          remaining_options = Enum.reject(active_options, & &1 == eliminated)
          
          run_elimination_rounds(
            ballots,
            remaining_options,
            all_options,
            nil,
            [round | rounds],
            round_num + 1
          )
      end
    end
  end

  defp count_first_preferences(ballots, active_options) do
    ballots
    |> Enum.map(fn {_voter_id, preferences} ->
      # Find first preference that's still active
      Enum.find(preferences, & &1 in active_options)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Map.new(fn {option_id, count} -> {option_id, count} end)
    |> ensure_all_options_counted(active_options)
  end

  defp ensure_all_options_counted(vote_counts, active_options) do
    # Ensure all active options have a count (even if 0)
    Enum.reduce(active_options, vote_counts, fn option_id, acc ->
      Map.put_new(acc, option_id, 0)
    end)
  end

  defp determine_winner(rounds) do
    case List.last(rounds) do
      nil -> nil
      %{vote_counts: counts} when map_size(counts) > 0 ->
        {winner_id, _} = Enum.max_by(counts, fn {_, v} -> v end)
        
        # Fetch the actual option
        get_option_by_id(winner_id)
      _ -> nil
    end
  end

  defp calculate_final_percentages(rounds, _total_voters) do
    case List.last(rounds) do
      nil -> %{}
      %{percentages: percentages} -> percentages
      _ -> %{}
    end
  end

  defp build_leaderboard(%{rounds: rounds, winner: winner}) do
    # Get final round for current standings
    final_round = List.last(rounds) || %{vote_counts: %{}, percentages: %{}}
    
    # Track eliminations by round
    eliminations = rounds
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {round, idx}, acc ->
        if round.eliminated do
          Map.put(acc, round.eliminated, idx)
        else
          acc
        end
      end)
    
    # Get all options that participated
    all_option_ids = rounds
      |> Enum.flat_map(& &1.active_options)
      |> Enum.uniq()
    
    # Fetch all options in a single query to avoid N+1
    options_map = get_options_by_ids(all_option_ids)
    
    # Build leaderboard entries
    all_option_ids
    |> Enum.map(fn option_id ->
      option = Map.get(options_map, option_id)
      
      # Determine status and stats
      {status, eliminated_round, votes, percentage} = cond do
        winner && winner.id == option_id ->
          votes = Map.get(final_round.vote_counts, option_id, 0)
          pct = Map.get(final_round.percentages, option_id, 0.0)
          {:winner, nil, votes, pct}
        
        Map.has_key?(eliminations, option_id) ->
          # Get stats from round before elimination
          elim_round = Map.get(eliminations, option_id)
          round_data = Enum.find(rounds, & &1.round_number == elim_round)
          votes = Map.get(round_data.vote_counts, option_id, 0)
          pct = Map.get(round_data.percentages, option_id, 0.0)
          {:eliminated, elim_round, votes, pct}
        
        option_id in Map.keys(final_round.vote_counts) ->
          votes = Map.get(final_round.vote_counts, option_id, 0)
          pct = Map.get(final_round.percentages, option_id, 0.0)
          {:runner_up, nil, votes, pct}
        
        true ->
          {:eliminated, nil, 0, 0.0}
      end
      
      %{
        option: option,
        option_id: option_id,
        votes: votes,
        percentage: Float.round(percentage, 1),
        status: status,
        eliminated_round: eliminated_round
      }
    end)
    |> Enum.sort_by(fn entry ->
      # Sort by: winner first, then runners-up by votes, then eliminated by round
      case entry.status do
        :winner -> {0, -entry.votes, 0}
        :runner_up -> {1, -entry.votes, 0}
        :eliminated -> {2, -entry.votes, entry.eliminated_round || 999}
      end
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, position} ->
      Map.put(entry, :position, position)
    end)
  end

  defp get_option_by_id(option_id) do
    PollOption
    |> where([o], o.id == ^option_id)
    |> Repo.one()
  end

  defp get_options_by_ids(option_ids) do
    PollOption
    |> where([o], o.id in ^option_ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  # Cache management functions
  
  @doc """
  Invalidate IRV cache for a specific poll when votes change.
  """
  def invalidate_cache(poll_id) do
    case ensure_cache_table() do
      :ok ->
        try do
          # Delete all entries for this poll (any vote/options count)
          :ets.match_delete(@irv_cache_name, {{:irv, poll_id, :_, :_}, :_})
        rescue
          ArgumentError -> :ok  # Cache unavailable, silently continue
        end
      :error -> :ok  # Cache unavailable, silently continue
    end
  end

  @doc """
  Clear all IRV cache entries (for maintenance).
  """
  def clear_all_cache do
    case :ets.whereis(@irv_cache_name) do
      :undefined -> :ok
      _table -> 
        try do
          :ets.delete_all_objects(@irv_cache_name)
        rescue
          ArgumentError -> :ok  # Table was destroyed, already cleared
        end
    end
  end

  # Private cache functions

  defp generate_cache_key(poll_id) do
    vote_count =
      from(v in PollVote,
        join: o in assoc(v, :poll_option),
        where: o.poll_id == ^poll_id and not is_nil(v.vote_rank) and is_nil(v.deleted_at),
        select: count(v.id)
      )
      |> Repo.one()

    options_count =
      from(o in PollOption,
        where: o.poll_id == ^poll_id and is_nil(o.deleted_at),
        select: count(o.id)
      )
      |> Repo.one()

    {:irv, poll_id, vote_count, options_count}
  end

  defp get_cached_result(cache_key) do
    case ensure_cache_table() do
      :ok ->
        try do
          case :ets.lookup(@irv_cache_name, cache_key) do
            [{^cache_key, result}] -> result
            [] -> nil
          end
        rescue
          ArgumentError -> nil  # Table doesn't exist, return nil to trigger fresh calculation
        end
      :error -> nil  # Cache unavailable, return nil to trigger fresh calculation
    end
  end

  defp cache_result(cache_key, result) do
    case ensure_cache_table() do
      :ok ->
        try do
          :ets.insert(@irv_cache_name, {cache_key, result})
        rescue
          ArgumentError -> :ok  # Cache unavailable, silently continue
        end
      :error -> :ok  # Cache unavailable, silently continue
    end
  end

  defp ensure_cache_table do
    case :ets.whereis(@irv_cache_name) do
      :undefined ->
        try do
          :ets.new(@irv_cache_name, [:set, :public, :named_table, :read_concurrency, :write_concurrency])
          :ok
        rescue
          ArgumentError -> 
            # Table might already exist, check again
            case :ets.whereis(@irv_cache_name) do
              :undefined -> :error
              _table -> :ok
            end
        end
      _table -> :ok
    end
  end
end