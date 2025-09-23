defmodule EventasaurusApp.Repo.Migrations.AddOtherFallbackCategory do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO categories (name, slug, description, icon, color, display_order, is_active, translations, inserted_at, updated_at)
    VALUES (
      'Other',
      'other',
      'Events that do not fit into standard categories',
      '❓',
      '#808080',
      14,
      true,
      '{"pl": {"name": "Inne", "sources": ["karnet", "general"]}}'::jsonb,
      NOW(),
      NOW()
    )
    ON CONFLICT (slug) DO NOTHING;
    """
  end

  def down do
    execute """
    DELETE FROM categories WHERE slug = 'other';
    """
  end
end