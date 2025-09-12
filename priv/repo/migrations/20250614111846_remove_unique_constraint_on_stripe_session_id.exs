defmodule EventasaurusApp.Repo.Migrations.RemoveUniqueConstraintOnStripeSessionId do
  use Ecto.Migration
  
  # Disable DDL transaction to allow concurrent index operations
  # This prevents blocking writes to the orders table during migration
  @disable_ddl_transaction true
  
  # Disable migration lock to allow concurrent index operations
  # Required when using concurrently: true on index operations
  @disable_migration_lock true

  def up do
    # Drop the unique constraint on stripe_session_id
    # This allows multiple orders to share the same checkout session
    # (e.g., when purchasing multiple tickets in one transaction)
    
    # Drop old unique (partial) index safely and idempotently
    drop_if_exists index(:orders, [:stripe_session_id],
      name: :orders_stripe_session_id_index,
      concurrently: true
    )
    
    # Recreate as a non-unique partial index for efficient lookups
    # The partial index (WHERE stripe_session_id IS NOT NULL) keeps the index small
    # and aligned with our lookup patterns, as we only query non-null session IDs
    create index(:orders, [:stripe_session_id],
      name: :orders_stripe_session_id_index,
      where: "stripe_session_id IS NOT NULL",
      concurrently: true
    )
  end
  
  def down do
    # Revert to the previous unique partial index
    drop_if_exists index(:orders, [:stripe_session_id],
      name: :orders_stripe_session_id_index,
      concurrently: true
    )
    
    # Restore the original unique constraint on stripe_session_id
    # This was the original state before allowing multi-ticket purchases
    create unique_index(:orders, [:stripe_session_id],
      name: :orders_stripe_session_id_index,
      where: "stripe_session_id IS NOT NULL",
      concurrently: true
    )
  end
end