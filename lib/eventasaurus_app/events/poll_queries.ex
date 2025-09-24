defmodule EventasaurusApp.Events.PollQueries do
  @moduledoc """
  Optimized database queries for poll operations.

  Provides efficient queries for poll statistics, especially for
  date selection polls with many options and votes.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{PollOption, PollVote}

  @doc """
  Gets poll statistics with a single optimized query.
  Returns aggregated vote counts per option without loading all vote records.
  """
  def get_poll_stats_optimized(poll_id) do
    # Get vote counts per option in a single query
    vote_counts_query =
      from(pv in PollVote,
        join: po in PollOption,
        on: pv.poll_option_id == po.id,
        where: po.poll_id == ^poll_id,
        group_by: [po.id, po.title, po.metadata, po.order_index],
        select: %{
          option_id: po.id,
          option_title: po.title,
          option_metadata: po.metadata,
          order_index: po.order_index,
          vote_count: count(pv.id),
          yes_votes: sum(fragment("CASE WHEN ? = 'yes' THEN 1 ELSE 0 END", pv.vote_value)),
          maybe_votes: sum(fragment("CASE WHEN ? = 'maybe' THEN 1 ELSE 0 END", pv.vote_value)),
          no_votes: sum(fragment("CASE WHEN ? = 'no' THEN 1 ELSE 0 END", pv.vote_value)),
          avg_rating: avg(pv.vote_numeric),
          avg_rank: avg(pv.vote_rank)
        }
      )

    # Get unique voter count in a separate query
    unique_voters_query =
      from(pv in PollVote,
        join: po in PollOption,
        on: pv.poll_option_id == po.id,
        where: po.poll_id == ^poll_id,
        select: count(pv.voter_id, :distinct)
      )

    vote_counts = Repo.all(vote_counts_query)
    unique_voters = Repo.one(unique_voters_query) || 0

    {vote_counts, unique_voters}
  end

  @doc """
  Gets vote statistics for date selection polls with efficient date parsing.
  """
  def get_date_poll_stats_optimized(poll_id) do
    {vote_counts, unique_voters} = get_poll_stats_optimized(poll_id)

    # Process and sort date options
    options_with_dates =
      vote_counts
      |> Enum.map(fn stats ->
        date = extract_date_from_metadata(stats.option_metadata)
        Map.put(stats, :date, date)
      end)
      |> Enum.sort_by(& &1.date)

    %{
      options: options_with_dates,
      unique_voters: unique_voters
    }
  end

  @doc """
  Batch loads vote counts for multiple polls efficiently.
  Useful for event pages showing multiple polls.
  """
  def get_polls_stats_batch(poll_ids) when is_list(poll_ids) do
    vote_counts_query =
      from(pv in PollVote,
        join: po in PollOption,
        on: pv.poll_option_id == po.id,
        where: po.poll_id in ^poll_ids,
        group_by: [po.poll_id, po.id, po.title, po.metadata, po.order_index],
        select: %{
          poll_id: po.poll_id,
          option_id: po.id,
          option_title: po.title,
          option_metadata: po.metadata,
          order_index: po.order_index,
          vote_count: count(pv.id),
          yes_votes: sum(fragment("CASE WHEN ? = 'yes' THEN 1 ELSE 0 END", pv.vote_value)),
          maybe_votes: sum(fragment("CASE WHEN ? = 'maybe' THEN 1 ELSE 0 END", pv.vote_value)),
          no_votes: sum(fragment("CASE WHEN ? = 'no' THEN 1 ELSE 0 END", pv.vote_value)),
          avg_rating: avg(pv.vote_numeric),
          avg_rank: avg(pv.vote_rank)
        }
      )

    unique_voters_query =
      from(pv in PollVote,
        join: po in PollOption,
        on: pv.poll_option_id == po.id,
        where: po.poll_id in ^poll_ids,
        group_by: po.poll_id,
        select: %{
          poll_id: po.poll_id,
          unique_voters: count(pv.voter_id, :distinct)
        }
      )

    vote_counts = Repo.all(vote_counts_query)
    unique_voters = Repo.all(unique_voters_query)

    # Group by poll_id for easy access
    vote_counts_by_poll = Enum.group_by(vote_counts, & &1.poll_id)
    unique_voters_by_poll = Map.new(unique_voters, &{&1.poll_id, &1.unique_voters})

    {vote_counts_by_poll, unique_voters_by_poll}
  end

  @doc """
  Efficiently loads polls with their options and current vote counts.
  """
  def get_polls_with_stats(poll_ids) when is_list(poll_ids) do
    {vote_counts_by_poll, unique_voters_by_poll} = get_polls_stats_batch(poll_ids)

    # Load polls with options
    polls_query =
      from(p in EventasaurusApp.Events.Poll,
        where: p.id in ^poll_ids,
        preload: [:poll_options]
      )

    polls = Repo.all(polls_query)

    # Attach stats to polls
    Enum.map(polls, fn poll ->
      poll_stats = Map.get(vote_counts_by_poll, poll.id, [])
      unique_voters = Map.get(unique_voters_by_poll, poll.id, 0)

      %{poll | stats: poll_stats, unique_voters: unique_voters}
    end)
  end

  # Helper functions

  defp extract_date_from_metadata(metadata) when is_map(metadata) do
    case metadata do
      %{"date" => date_str} when is_binary(date_str) ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> date
          _ -> ~D[2099-12-31]
        end

      _ ->
        ~D[2099-12-31]
    end
  end

  defp extract_date_from_metadata(_), do: ~D[2099-12-31]
end
