defmodule EventasaurusApp.Repo.Migrations.AddManualPaymentTrackingToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      # Type of order: "ticket" or "contribution"
      add :order_type, :string, default: "ticket"
      
      # Payment method used
      add :payment_method, :string, default: "stripe"
      
      # Manual payment tracking fields
      add :manual_payment_method, :string # cash, check, bank_transfer, other
      add :manual_payment_reference, :string # check number, transfer ID, etc
      add :manual_payment_received_at, :utc_datetime
      add :manual_payment_notes, :text
      
      # User who marked the payment as received
      add :payment_marked_by_id, references(:users, on_delete: :nilify_all)
      
      # For contributions without tickets
      add :contribution_amount_cents, :integer
      add :is_anonymous, :boolean, default: false
      
      # History tracking
      add :payment_history, :map, default: %{}
    end
    
    # Add indexes for common queries
    create index(:orders, [:event_id, :order_type])
    create index(:orders, [:event_id, :status])
    create index(:orders, [:event_id, :payment_method])
    create index(:orders, [:manual_payment_received_at])
  end
end
