defmodule EventasaurusApp.Repo.Migrations.UpdateExistingSourceDomains do
  use Ecto.Migration

  def up do
    # Update existing sources to use standardized domain names
    # This migrates from the old ad-hoc domains to Schema.org-based taxonomy

    # BandsInTown: music, concert -> music
    execute """
    UPDATE sources
    SET domains = ARRAY['music']::varchar[]
    WHERE slug = 'bandsintown'
      AND domains @> ARRAY['music','concert']::varchar[]
      AND domains <@ ARRAY['music','concert']::varchar[];
    """

    # Resident Advisor: music, electronic -> music
    execute """
    UPDATE sources
    SET domains = ARRAY['music']::varchar[]
    WHERE slug = 'resident-advisor'
      AND domains @> ARRAY['music','electronic']::varchar[]
      AND domains <@ ARRAY['music','electronic']::varchar[];
    """

    # Cinema City: movies, cinema -> screening
    execute """
    UPDATE sources
    SET domains = ARRAY['screening']::varchar[]
    WHERE slug = 'cinema-city'
      AND domains @> ARRAY['movies','cinema']::varchar[]
      AND domains <@ ARRAY['movies','cinema']::varchar[];
    """

    # Kino Krakow: movies, cinema -> screening
    execute """
    UPDATE sources
    SET domains = ARRAY['screening']::varchar[]
    WHERE slug = 'kino-krakow'
      AND domains @> ARRAY['movies','cinema']::varchar[]
      AND domains <@ ARRAY['movies','cinema']::varchar[];
    """

    # PubQuiz: trivia, quiz -> trivia (already correct, but normalize)
    execute """
    UPDATE sources
    SET domains = ARRAY['trivia']::varchar[]
    WHERE slug = 'pubquiz'
      AND domains @> ARRAY['trivia','quiz']::varchar[]
      AND domains <@ ARRAY['trivia','quiz']::varchar[];
    """
  end

  def down do
    # Rollback to previous domain values
    execute """
    UPDATE sources
    SET domains = ARRAY['music','concert']::varchar[]
    WHERE slug = 'bandsintown'
      AND domains @> ARRAY['music']::varchar[]
      AND domains <@ ARRAY['music']::varchar[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['music','electronic']::varchar[]
    WHERE slug = 'resident-advisor'
      AND domains @> ARRAY['music']::varchar[]
      AND domains <@ ARRAY['music']::varchar[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['movies','cinema']::varchar[]
    WHERE slug = 'cinema-city'
      AND domains @> ARRAY['screening']::varchar[]
      AND domains <@ ARRAY['screening']::varchar[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['movies','cinema']::varchar[]
    WHERE slug = 'kino-krakow'
      AND domains @> ARRAY['screening']::varchar[]
      AND domains <@ ARRAY['screening']::varchar[];
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['trivia','quiz']::varchar[]
    WHERE slug = 'pubquiz'
      AND domains @> ARRAY['trivia']::varchar[]
      AND domains <@ ARRAY['trivia']::varchar[];
    """
  end
end
