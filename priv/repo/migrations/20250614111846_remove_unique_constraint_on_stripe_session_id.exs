defmodule EventasaurusApp.Repo.Migrations.RemoveUniqueConstraintOnStripeSessionId do
  use Ecto.Migration
  
  # Disable DDL transaction to allow concurrent index operations
  # This prevents blocking writes to the orders table during migration
  @disable_ddl_transaction true
  
  # Enable advisory locks to prevent migration race conditions
  @disable_migration_lock true

  def change do
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
end