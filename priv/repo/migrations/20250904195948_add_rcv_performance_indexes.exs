defmodule EventasaurusApp.Repo.Migrations.AddRcvPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite index for ranked choice voting queries
    # This optimizes the main query in get_ranked_votes/1
    create index(:poll_votes, [:poll_option_id, :vote_rank, :deleted_at], 
      where: "vote_rank IS NOT NULL AND deleted_at IS NULL",
      name: :poll_votes_ranked_voting_idx)
    
    # Index for poll-specific RCV queries with voter filtering  
    create index(:poll_votes, [:voter_id, :poll_option_id, :vote_rank],
      where: "vote_rank IS NOT NULL AND deleted_at IS NULL", 
      name: :poll_votes_voter_ranking_idx)
    
    # Index to optimize unique voter counting in RCV - uses poll_option_id + voter_id
    # This works because we join through poll_options to filter by poll_id
    execute("DROP INDEX IF EXISTS poll_votes_unique_voters_idx")
    create index(:poll_votes, [:poll_option_id, :voter_id],
      where: "vote_rank IS NOT NULL AND deleted_at IS NULL",
      name: :poll_votes_unique_voters_idx)
      
    # Index for poll option queries with poll filtering  
    create index(:poll_options, [:poll_id, :deleted_at],
      where: "deleted_at IS NULL",
      name: :poll_options_by_poll_idx)
  end
end
