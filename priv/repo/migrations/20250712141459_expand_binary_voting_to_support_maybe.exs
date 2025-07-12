defmodule Eventasaurus.Repo.Migrations.ExpandBinaryVotingToSupportMaybe do
  use Ecto.Migration

  def up do
    # This migration prepares the database for Yes/No/Maybe binary voting
    #
    # No schema changes are needed - the existing vote_value string field
    # already supports storing "yes", "no", and the new "maybe" values
    #
    # Existing binary votes ("yes", "no") remain valid and functional
    # The application layer will be updated to:
    # 1. Accept "maybe" as a valid binary vote value
    # 2. Update UI to show Yes/No/Maybe buttons
    # 3. Update results display for 3-way breakdown
    #
    # No database constraint is added to avoid interfering with other
    # voting systems (approval, ranked, star) that use the same field

    # This is a no-op migration for documentation purposes
    :ok
  end

  def down do
    # No changes to rollback
    :ok
  end
end
