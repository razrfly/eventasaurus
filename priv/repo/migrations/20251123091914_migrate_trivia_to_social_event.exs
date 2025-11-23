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
    # Only affects sources that were originally trivia (identified by slug)
    execute """
    UPDATE sources
    SET aggregation_type = 'trivia'
    WHERE aggregation_type = 'SocialEvent'
      AND slug IN (
        'question-one',
        'geeks-who-drink',
        'quizmeisters',
        'pubquiz-pl',
        'inquizition',
        'speed-quizzing'
      )
    """
  end
end
