defmodule EventasaurusApp.Repo.Migrations.AddPollVoteIndexes do
  use Ecto.Migration

  def change do
    # Add index for efficient vote counting by poll
    create_if_not_exists index(:poll_votes, [:poll_option_id, :voter_id])
    
    # Add index for counting unique voters per poll (only if doesn't exist)
    create_if_not_exists index(:poll_options, [:poll_id])
    
    # Add index for faster vote queries by poll option
    create_if_not_exists index(:poll_votes, [:poll_option_id], 
      name: "poll_votes_by_option_idx"
    )
  end
end
