defmodule EventasaurusApp.Repo.Migrations.AddAggregationFieldsToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :aggregate_on_index, :boolean, default: false, null: false
      add :aggregation_type, :string
    end

    # Enable aggregation for PubQuiz Poland source (create if it doesn't exist)
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM sources WHERE slug = 'pubquiz-pl') THEN
        UPDATE sources
        SET aggregate_on_index = true, aggregation_type = 'trivia'
        WHERE slug = 'pubquiz-pl';
      END IF;
    END
    $$;
    """, ""
  end
end
