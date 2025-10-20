defmodule EventasaurusApp.Repo.Migrations.AddTranslationIndexes do
  use Ecto.Migration

  def change do
    # Add GIN index for efficient translation key queries
    # This dramatically speeds up queries that check what translations exist
    execute(
      """
      CREATE INDEX IF NOT EXISTS public_events_title_translations_keys
      ON public_events
      USING GIN (title_translations)
      """,
      """
      DROP INDEX IF EXISTS public_events_title_translations_keys
      """
    )
  end
end
