defmodule EventasaurusApp.Repo.Migrations.FixWaw4freeSlug do
  use Ecto.Migration

  @moduledoc """
  Fix waw4free source slug to match module name Waw4free.

  This reverts the migration 20260129145213_fix_source_slugs which changed
  the slug from "waw4free" to "waw4-free". The module has been renamed from
  Waw4Free to Waw4free, so the slug derived via Macro.underscore() is now
  "waw4free" (no hyphen needed).

  Related: GitHub Issue #3482
  """

  def up do
    # Fix waw4free slug: waw4-free -> waw4free
    execute """
    UPDATE sources
    SET slug = 'waw4free', name = 'Waw4free'
    WHERE slug = 'waw4-free'
    """
  end

  def down do
    # Revert to waw4-free if needed (not recommended)
    execute """
    UPDATE sources
    SET slug = 'waw4-free', name = 'Waw4Free'
    WHERE slug = 'waw4free'
    """
  end
end
