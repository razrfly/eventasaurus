defmodule EventasaurusApp.Repo.Migrations.FixGetEntityImageUrlSchemaQualification do
  use Ecto.Migration

  @moduledoc """
  Fixes the get_entity_image_url function to use fully qualified table names.

  The function was referencing `cached_images` without the `public.` schema prefix,
  which caused issues when the function was called during materialized view creation.

  PostgreSQL's search_path during view creation may not include `public`, causing
  the "relation cached_images does not exist" error.
  """

  def up do
    # Drop and recreate the function with fully qualified table reference
    execute """
    CREATE OR REPLACE FUNCTION public.get_entity_image_url(
      p_entity_type text,
      p_entity_id integer,
      p_position integer DEFAULT 0
    )
    RETURNS text
    LANGUAGE plpgsql
    STABLE
    AS $function$
    BEGIN
      RETURN (
        SELECT COALESCE(cdn_url, original_url)
        FROM public.cached_images
        WHERE entity_type = p_entity_type
          AND entity_id = p_entity_id
          AND position = p_position
          AND status = 'cached'
        LIMIT 1
      );
    END;
    $function$
    """
  end

  def down do
    # Revert to original function without schema qualification
    execute """
    CREATE OR REPLACE FUNCTION public.get_entity_image_url(
      p_entity_type text,
      p_entity_id integer,
      p_position integer DEFAULT 0
    )
    RETURNS text
    LANGUAGE plpgsql
    STABLE
    AS $function$
    BEGIN
      RETURN (
        SELECT COALESCE(cdn_url, original_url)
        FROM cached_images
        WHERE entity_type = p_entity_type
          AND entity_id = p_entity_id
          AND position = p_position
          AND status = 'cached'
        LIMIT 1
      );
    END;
    $function$
    """
  end
end
