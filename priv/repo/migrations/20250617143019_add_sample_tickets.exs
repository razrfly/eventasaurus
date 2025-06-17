defmodule Eventasaurus.Repo.Migrations.AddSampleTickets do
  use Ecto.Migration

  def up do
    # Add sample tickets for testing - only if there are confirmed events with ticketing enabled
    execute """
    INSERT INTO tickets (event_id, title, description, pricing_model, base_price_cents, minimum_price_cents, suggested_price_cents, quantity, tippable, inserted_at, updated_at)
    SELECT
      e.id,
      'General Admission',
      'Standard entry ticket for the event',
      'fixed',
      2500, -- $25.00
      0,
      NULL,
      100,
      false,
      NOW(),
      NOW()
    FROM events e
    WHERE e.is_ticketed = true
    AND e.status = 'confirmed'
    AND NOT EXISTS (
      SELECT 1 FROM tickets t WHERE t.event_id = e.id AND t.title = 'General Admission'
    )
    LIMIT 5;
    """

    execute """
    INSERT INTO tickets (event_id, title, description, pricing_model, base_price_cents, minimum_price_cents, suggested_price_cents, quantity, tippable, inserted_at, updated_at)
    SELECT
      e.id,
      'VIP Access',
      'Premium ticket with exclusive benefits and early access',
      'fixed',
      7500, -- $75.00
      0,
      NULL,
      20,
      false,
      NOW(),
      NOW()
    FROM events e
    WHERE e.is_ticketed = true
    AND e.status = 'confirmed'
    AND NOT EXISTS (
      SELECT 1 FROM tickets t WHERE t.event_id = e.id AND t.title = 'VIP Access'
    )
    LIMIT 5;
    """

    execute """
    INSERT INTO tickets (event_id, title, description, pricing_model, base_price_cents, minimum_price_cents, suggested_price_cents, quantity, tippable, inserted_at, updated_at)
    SELECT
      e.id,
      'Student Discount',
      'Discounted ticket for students with valid ID',
      'fixed',
      1500, -- $15.00
      0,
      NULL,
      50,
      false,
      NOW(),
      NOW()
    FROM events e
    WHERE e.is_ticketed = true
    AND e.status = 'confirmed'
    AND NOT EXISTS (
      SELECT 1 FROM tickets t WHERE t.event_id = e.id AND t.title = 'Student Discount'
    )
    LIMIT 5;
    """
  end

  def down do
    # Remove sample tickets
    execute "DELETE FROM tickets WHERE title IN ('General Admission', 'VIP Access', 'Student Discount')"
  end
end
