defmodule EventasaurusApp.Repo.Migrations.UpdateExistingSourceDomains do
  use Ecto.Migration

  def up do
    # Update existing sources to use standardized domain names
    # This migrates from the old ad-hoc domains to Schema.org-based taxonomy

    # BandsInTown: music, concert -> music
    execute """
    UPDATE sources
    SET domains = ARRAY['music']::text[]
    WHERE slug = 'bandsintown'
      AND domains @> ARRAY['music','concert']::text[]
      AND domains <@ ARRAY['music','concert']::text[];
    """

    # Resident Advisor: music, electronic -> music
    execute """
    UPDATE sources
    SET domains = ARRAY['music']::text[]
    WHERE slug = 'resident-advisor'
      AND domains @> ARRAY['music','electronic']::text[]
      AND domains <@ ARRAY['music','electronic']::text[];
    """

    # Cinema City: movies, cinema -> screening
    execute """
    UPDATE sources
    SET domains = ARRAY['screening']::text[]
    WHERE slug = 'cinema-city'
      AND domains @> ARRAY['movies','cinema']::text[]
      AND domains <@ ARRAY['movies','cinema']::text[];
    """

    # Kino Krakow: movies, cinema -> screening
    execute """
    UPDATE sources
    SET domains = ARRAY['screening']::text[]
    WHERE slug = 'kino-krakow'
      AND domains @> ARRAY['movies','cinema']::text[]
      AND domains <@ ARRAY['movies','cinema']::text[];
    """

    # PubQuiz: trivia, quiz -> trivia (already correct, but normalize)
    execute """
    UPDATE sources
    SET domains = ARRAY['trivia']::text[]
    WHERE slug = 'pubquiz'
      AND domains @> ARRAY['trivia','quiz']::text[]
      AND domains <@ ARRAY['trivia','quiz']::text[];
    """
  end

  def down do
    # Rollback to previous domain values
    execute """
    UPDATE sources
    SET domains = ARRAY['music','concert']::text[]
    WHERE slug = 'bandsintown'
      AND domains @> ARRAY['music']::text[]
      AND domains <@ ARRAY['music']::text[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['music','electronic']::text[]
    WHERE slug = 'resident-advisor'
      AND domains @> ARRAY['music']::text[]
      AND domains <@ ARRAY['music']::text[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['movies','cinema']::text[]
    WHERE slug = 'cinema-city'
      AND domains @> ARRAY['screening']::text[]
      AND domains <@ ARRAY['screening']::text[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['movies','cinema']::text[]
    WHERE slug = 'kino-krakow'
      AND domains @> ARRAY['screening']::text[]
      AND domains <@ ARRAY['screening']::text[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['trivia','quiz']::text[]
    WHERE slug = 'pubquiz'
      AND domains @> ARRAY['trivia']::text[]
      AND domains <@ ARRAY['trivia']::text[];
    """
  end
end
