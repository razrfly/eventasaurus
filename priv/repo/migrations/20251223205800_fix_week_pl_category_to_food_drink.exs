defmodule EventasaurusApp.Repo.Migrations.FixWeekPlCategoryToFoodDrink do
  @moduledoc """
  Fix Week.pl Restaurant Week events to have correct category.

  Problem: Week.pl events were created with category_id 10 (Business) instead of
  category_id 14 (Food & Drink) due to a bug in the transformer.

  This migration:
  1. Updates the junction table (public_event_categories) - used for filtering
  2. Updates the main table (public_events.category_id) - for consistency

  See: https://github.com/razrfly/eventasaurus/issues/2860
  """
  use Ecto.Migration

  # Category IDs
  @wrong_category_id 10  # Business
  @correct_category_id 14  # Food & Drink

  def up do
    # Step 1: Update junction table (this is what filtering actually uses)
    execute("""
    UPDATE public_event_categories pec
    SET category_id = #{@correct_category_id}
    WHERE pec.category_id = #{@wrong_category_id}
      AND pec.event_id IN (
        SELECT DISTINCT pes.event_id
        FROM public_event_sources pes
        WHERE pes.external_id LIKE 'week_pl_%'
      )
    """)

    # Step 2: Update main table category_id for consistency
    execute("""
    UPDATE public_events pe
    SET category_id = #{@correct_category_id}, updated_at = NOW()
    WHERE pe.category_id = #{@wrong_category_id}
      AND pe.id IN (
        SELECT DISTINCT pes.event_id
        FROM public_event_sources pes
        WHERE pes.external_id LIKE 'week_pl_%'
      )
    """)
  end

  def down do
    # Revert junction table
    execute("""
    UPDATE public_event_categories pec
    SET category_id = #{@wrong_category_id}
    WHERE pec.category_id = #{@correct_category_id}
      AND pec.event_id IN (
        SELECT DISTINCT pes.event_id
        FROM public_event_sources pes
        WHERE pes.external_id LIKE 'week_pl_%'
      )
    """)

    # Revert main table
    execute("""
    UPDATE public_events pe
    SET category_id = #{@wrong_category_id}, updated_at = NOW()
    WHERE pe.category_id = #{@correct_category_id}
      AND pe.id IN (
        SELECT DISTINCT pes.event_id
        FROM public_event_sources pes
        WHERE pes.external_id LIKE 'week_pl_%'
      )
    """)
  end
end
