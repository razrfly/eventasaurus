defmodule EventasaurusApp.Repo.Migrations.AddDomainsToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :domains, {:array, :string}, default: ["general"], null: false
    end

    # Backfill existing sources with their appropriate domains
    # Using standardized domain names from Schema.org Event taxonomy
    execute """
    UPDATE sources SET domains = ARRAY['music'] WHERE slug = 'bandsintown';
    """, ""

    execute """
    UPDATE sources SET domains = ARRAY['music'] WHERE slug = 'resident-advisor';
    """, ""

    execute """
    UPDATE sources SET domains = ARRAY['screening'] WHERE slug = 'cinema-city';
    """, ""

    execute """
    UPDATE sources SET domains = ARRAY['screening'] WHERE slug = 'kino-krakow';
    """, ""

    execute """
    UPDATE sources SET domains = ARRAY['trivia'] WHERE slug = 'pubquiz';
    """, ""

    execute """
    UPDATE sources SET domains = ARRAY['music', 'theater', 'cultural', 'general'] WHERE slug = 'karnet';
    """, ""

    execute """
    UPDATE sources SET domains = ARRAY['music', 'sports', 'theater', 'general'] WHERE slug = 'ticketmaster';
    """, ""
  end
end
