defmodule Eventasaurus.Repo.Migrations.FixPollVotesColumnNames do
  use Ecto.Migration

  def up do
    # Rename columns to match the PollVote schema
    rename table(:poll_votes), :rank_order, to: :vote_rank
    rename table(:poll_votes), :rating_value, to: :vote_numeric
  end

  def down do
    # Reverse the column renames
    rename table(:poll_votes), :vote_rank, to: :rank_order
    rename table(:poll_votes), :vote_numeric, to: :rating_value
  end
end
