defmodule EventasaurusApp.Repo.Migrations.AddPollVoteIndexes do
  use Ecto.Migration

  def change do
    # Add index for efficient vote counting by poll
    create index(:poll_votes, [:poll_option_id, :voter_id])
    
    # Add index for counting unique voters per poll
    create index(:poll_options, [:poll_id])
    
    # Add partial index for active votes (where deleted_at is null if soft delete is used)
    # This improves queries that filter out deleted votes
    create index(:poll_votes, [:poll_option_id], 
      where: "deleted_at IS NULL",
      name: "poll_votes_active_by_option_idx"
    )
  end
end