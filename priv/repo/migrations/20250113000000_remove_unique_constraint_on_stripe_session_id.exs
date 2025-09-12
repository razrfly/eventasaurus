defmodule EventasaurusApp.Repo.Migrations.RemoveUniqueConstraintOnStripeSessionId do
  use Ecto.Migration

  def change do
    # Drop the unique constraint on stripe_session_id
    # This allows multiple orders to share the same checkout session
    # (e.g., when purchasing multiple tickets in one transaction)
    drop unique_index(:orders, [:stripe_session_id], where: "stripe_session_id IS NOT NULL")
    
    # Create a regular index for efficient lookups
    # We still want to be able to quickly find orders by session ID
    create index(:orders, [:stripe_session_id])
  end
end