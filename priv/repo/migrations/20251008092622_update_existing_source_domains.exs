defmodule EventasaurusApp.Repo.Migrations.UpdateExistingSourceDomains do
  use Ecto.Migration

  def up do
    # Update existing sources to use standardized domain names
    # This migrates from the old ad-hoc domains to Schema.org-based taxonomy

    # BandsInTown: music, concert -> music
    execute """
    UPDATE sources
    SET domains = ARRAY['music']
    WHERE slug = 'bandsintown'
      AND domains = ARRAY['music', 'concert'];
    """

    # Resident Advisor: music, electronic -> music
    execute """
    UPDATE sources
    SET domains = ARRAY['music']
    WHERE slug = 'resident-advisor'
      AND domains = ARRAY['music', 'electronic'];
    """

    # Cinema City: movies, cinema -> screening
    execute """
    UPDATE sources
    SET domains = ARRAY['screening']
    WHERE slug = 'cinema-city'
      AND domains = ARRAY['movies', 'cinema'];
    """

    # Kino Krakow: movies, cinema -> screening
    execute """
    UPDATE sources
    SET domains = ARRAY['screening']
    WHERE slug = 'kino-krakow'
      AND domains = ARRAY['movies', 'cinema'];
    """

    # PubQuiz: trivia, quiz -> trivia (already correct, but normalize)
    execute """
    UPDATE sources
    SET domains = ARRAY['trivia']
    WHERE slug = 'pubquiz'
      AND domains = ARRAY['trivia', 'quiz'];
    """
  end

  def down do
    # Rollback to previous domain values
    execute """
    UPDATE sources
    SET domains = ARRAY['music', 'concert']
    WHERE slug = 'bandsintown';
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['music', 'electronic']
    WHERE slug = 'resident-advisor';
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['movies', 'cinema']
    WHERE slug = 'cinema-city';
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['movies', 'cinema']
    WHERE slug = 'kino-krakow';
    """

    execute """
    UPDATE sources
    SET domains = ARRAY['trivia', 'quiz']
    WHERE slug = 'pubquiz';
    """
  end
end
