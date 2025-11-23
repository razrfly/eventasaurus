defmodule EventasaurusApp.Repo.Migrations.MigrateTriviaToSocialEvent do
  use Ecto.Migration

  def up do
    # Migrate trivia aggregation_type to schema.org SocialEvent
    execute """
    UPDATE sources
    SET aggregation_type = 'SocialEvent'
    WHERE aggregation_type = 'trivia'
    """
  end

  def down do
    # Reverse migration: convert SocialEvent back to trivia
    execute """
    UPDATE sources
    SET aggregation_type = 'trivia'
    WHERE aggregation_type = 'SocialEvent'
    """
  end
end
