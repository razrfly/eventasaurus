defmodule EventasaurusApp.Repo.Migrations.FixSourceSlugs do
  use Ecto.Migration

  @moduledoc """
  Fixes non-canonical slugs in the sources table.

  These slugs don't match their worker module names due to case conversion issues:
  - `waw4free` → `Waw4free` (wrong) vs actual worker `Waw4Free`
  - `pubquiz-pl` → `PubquizPl` (wrong) vs actual worker `Pubquiz`

  This causes health monitoring to fail when converting slug → module pattern,
  resulting in 0% health scores for these sources on city-specific health pages.
  """

  def up do
    # Fix waw4free → waw4-free
    # waw4free → Waw4free (wrong), waw4-free → Waw4Free (correct)
    execute "UPDATE sources SET slug = 'waw4-free' WHERE slug = 'waw4free'"

    # Fix pubquiz-pl → pubquiz
    # pubquiz-pl → PubquizPl (wrong), pubquiz → Pubquiz (correct)
    execute "UPDATE sources SET slug = 'pubquiz' WHERE slug = 'pubquiz-pl'"
  end

  def down do
    # Reverse the changes
    execute "UPDATE sources SET slug = 'waw4free' WHERE slug = 'waw4-free'"
    execute "UPDATE sources SET slug = 'pubquiz-pl' WHERE slug = 'pubquiz'"
  end
end
