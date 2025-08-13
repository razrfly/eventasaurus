defmodule EventasaurusApp.Events.Order do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.SoftDelete.Schema

  @valid_statuses ~w(pending confirmed refunded canceled)
  @valid_order_types ~w(ticket contribution)
  @valid_payment_methods ~w(stripe manual)
  @valid_manual_payment_methods ~w(cash check bank_transfer venmo paypal other)

  schema "orders" do
    field :quantity, :integer
    field :subtotal_cents, :integer
    field :tax_cents, :integer, default: 0
    field :total_cents, :integer
    field :currency, :string, default: "usd"
    field :status, :string, default: "pending"
    field :stripe_session_id, :string
    field :payment_reference, :string
    field :confirmed_at, :utc_datetime

    # Pricing snapshot for historical tracking
    field :pricing_snapshot, :map

    # Minimal Stripe Connect fields
    field :application_fee_amount, :integer, default: 0
    
    # Manual payment tracking fields
    field :order_type, :string, default: "ticket"
    field :payment_method, :string, default: "stripe"
    field :manual_payment_method, :string
    field :manual_payment_reference, :string
    field :manual_payment_received_at, :utc_datetime
    field :manual_payment_notes, :string
    field :payment_history, :map, default: %{}
    
    # Contribution fields
    field :contribution_amount_cents, :integer
    field :is_anonymous, :boolean, default: false
    field :privacy_preference, :string, default: "default"

    belongs_to :user, EventasaurusApp.Accounts.User
    belongs_to :event, EventasaurusApp.Events.Event
    belongs_to :ticket, EventasaurusApp.Events.Ticket
    belongs_to :stripe_connect_account, EventasaurusApp.Stripe.StripeConnectAccount
    belongs_to :payment_marked_by, EventasaurusApp.Accounts.User

    # Deletion metadata fields
    field :deletion_reason, :string
    belongs_to :deleted_by_user, EventasaurusApp.Accounts.User, foreign_key: :deleted_by_user_id

    timestamps()
    soft_delete_schema()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :quantity, :subtotal_cents, :tax_cents, :total_cents, :currency, :status,
      :stripe_session_id, :payment_reference, :confirmed_at, :user_id, :event_id,
      :ticket_id, :stripe_connect_account_id, :application_fee_amount, :pricing_snapshot,
      :order_type, :payment_method, :manual_payment_method, :manual_payment_reference,
      :manual_payment_received_at, :manual_payment_notes, :payment_marked_by_id,
      :contribution_amount_cents, :is_anonymous, :payment_history
    ])
    |> validate_required([:quantity, :subtotal_cents, :total_cents, :currency, :status, :user_id, :event_id, :order_type, :payment_method])
    |> validate_number(:quantity, greater_than: 0, message: "must be greater than 0")
    |> validate_number(:subtotal_cents, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_number(:tax_cents, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_number(:total_cents, greater_than: 0, message: "must be greater than 0")
    |> validate_number(:application_fee_amount, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_number(:contribution_amount_cents, greater_than: 0, message: "must be greater than 0")
    |> validate_application_fee_amount()
    |> validate_inclusion(:currency, EventasaurusWeb.Helpers.CurrencyHelpers.supported_currency_codes(), message: "must be a supported currency")
    |> validate_inclusion(:status, @valid_statuses, message: "must be a valid status")
    |> validate_inclusion(:order_type, @valid_order_types, message: "must be a valid order type")
    |> validate_inclusion(:payment_method, @valid_payment_methods, message: "must be a valid payment method")
    |> validate_inclusion(:manual_payment_method, @valid_manual_payment_methods, message: "must be a valid manual payment method")
    |> validate_order_type_fields()
    |> validate_manual_payment_fields()
    |> validate_total_calculation()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:stripe_connect_account_id)
    |> foreign_key_constraint(:payment_marked_by_id)
  end

  defp validate_application_fee_amount(changeset) do
    fee = get_field(changeset, :application_fee_amount)
    total = get_field(changeset, :total_cents)

    if fee && total && fee > total do
      add_error(changeset, :application_fee_amount, "cannot exceed total_cents")
    else
      changeset
    end
  end

  defp validate_total_calculation(changeset) do
    # Note: With Stripe handling tax calculation automatically, we have different validation rules:
    # 1. For new orders (before Stripe processing): total should equal subtotal since tax is 0
    # 2. For processed orders (after Stripe): we trust Stripe's calculations completely
    subtotal = get_field(changeset, :subtotal_cents)
    tax = get_field(changeset, :tax_cents) || 0
    total = get_field(changeset, :total_cents)

    # Only validate for orders that haven't been processed by Stripe yet
    if subtotal && total && tax == 0 && subtotal != total do
      add_error(changeset, :total_cents, "must equal subtotal when tax is not yet calculated")
    else
      # For orders with tax > 0, trust Stripe's calculations
      changeset
    end
  end
  
  defp validate_order_type_fields(changeset) do
    order_type = get_field(changeset, :order_type)
    
    case order_type do
      "ticket" ->
        # For ticket orders, ticket_id is required
        if is_nil(get_field(changeset, :ticket_id)) do
          add_error(changeset, :ticket_id, "is required for ticket orders")
        else
          changeset
        end
        
      "contribution" ->
        # For contribution orders, contribution_amount_cents is required
        if is_nil(get_field(changeset, :contribution_amount_cents)) do
          add_error(changeset, :contribution_amount_cents, "is required for contribution orders")
        else
          changeset
        end
        
      _ ->
        changeset
    end
  end
  
  defp validate_manual_payment_fields(changeset) do
    payment_method = get_field(changeset, :payment_method)
    
    if payment_method == "manual" do
      changeset
      |> validate_required([:manual_payment_method], message: "is required for manual payments")
    else
      changeset
    end
  end

  def pending?(%__MODULE__{status: "pending"}), do: true
  def pending?(_), do: false

  def confirmed?(%__MODULE__{status: "confirmed"}), do: true
  def confirmed?(_), do: false

  def refunded?(%__MODULE__{status: "refunded"}), do: true
  def refunded?(_), do: false

  def canceled?(%__MODULE__{status: "canceled"}), do: true
  def canceled?(_), do: false

  def can_cancel?(%__MODULE__{status: "pending"}), do: true
  def can_cancel?(_), do: false

  def can_refund?(%__MODULE__{status: "confirmed", payment_reference: ref}) when not is_nil(ref), do: true
  def can_refund?(%__MODULE__{status: "canceled", payment_reference: ref}) when not is_nil(ref), do: true
  def can_refund?(_), do: false

  def using_stripe_connect?(%__MODULE__{stripe_connect_account_id: id}) when not is_nil(id), do: true
  def using_stripe_connect?(_), do: false

  @doc """
  Create a pricing snapshot from ticket and order parameters.

  Example snapshot:
  %{
    "base_price_cents" => 1500,
    "minimum_price_cents" => 1000,
    "suggested_price_cents" => 1500,
    "custom_price_cents" => 1800,
    "tip_cents" => 200,
    "pricing_model" => "flexible",
    "ticket_tippable" => true
  }
  """
  def create_pricing_snapshot(ticket, custom_price_cents \\ nil, tip_cents \\ 0) do
    %{
      "base_price_cents" => ticket.base_price_cents,
      "minimum_price_cents" => ticket.minimum_price_cents,
      "suggested_price_cents" => ticket.suggested_price_cents,
      "custom_price_cents" => custom_price_cents,
      "tip_cents" => tip_cents,
      "pricing_model" => ticket.pricing_model || "fixed",
      "ticket_tippable" => ticket.tippable || false
    }
  end

  @doc """
  Get the effective ticket price from pricing snapshot.
  """
  def get_effective_price_from_snapshot(%__MODULE__{pricing_snapshot: snapshot}) when not is_nil(snapshot) do
    case snapshot do
      %{"custom_price_cents" => custom} when not is_nil(custom) -> custom
      %{"base_price_cents" => base} when not is_nil(base) -> base
      _ -> 0
    end
  end
  def get_effective_price_from_snapshot(_), do: 0

  @doc """
  Get the tip amount from pricing snapshot.
  """
  def get_tip_from_snapshot(%__MODULE__{pricing_snapshot: snapshot}) when not is_nil(snapshot) do
    case snapshot do
      %{"tip_cents" => tip} when not is_nil(tip) -> tip
      _ -> 0
    end
  end
  def get_tip_from_snapshot(_), do: 0

  @doc """
  Check if this order used flexible pricing.
  """
  def flexible_pricing?(%__MODULE__{pricing_snapshot: snapshot}) when not is_nil(snapshot) do
    case snapshot do
      %{"pricing_model" => "flexible"} -> true
      _ -> false
    end
  end
  def flexible_pricing?(_), do: false

  @doc """
  Check if this order had tips.
  """
  def has_tip?(%__MODULE__{} = order) do
    get_tip_from_snapshot(order) > 0
  end
  
  @doc """
  Check if this order uses manual payment.
  """
  def manual_payment?(%__MODULE__{payment_method: "manual"}), do: true
  def manual_payment?(_), do: false
  
  @doc """
  Check if manual payment has been received.
  """
  def manual_payment_received?(%__MODULE__{payment_method: "manual", manual_payment_received_at: nil}), do: false
  def manual_payment_received?(%__MODULE__{payment_method: "manual", manual_payment_received_at: _}), do: true
  def manual_payment_received?(_), do: false
  
  @doc """
  Mark manual payment as received.
  """
  def mark_payment_received_changeset(order, attrs, marked_by_user_id) do
    order
    |> changeset(attrs)
    |> put_change(:status, "confirmed")
    |> put_change(:confirmed_at, DateTime.utc_now())
    |> put_change(:manual_payment_received_at, DateTime.utc_now())
    |> put_change(:payment_marked_by_id, marked_by_user_id)
    |> add_payment_history_entry("payment_received", marked_by_user_id)
  end
  
  @doc """
  Mark manual payment as refunded.
  """
  def mark_payment_refunded_changeset(order, attrs, marked_by_user_id) do
    order
    |> changeset(attrs)
    |> put_change(:status, "refunded")
    |> put_change(:payment_marked_by_id, marked_by_user_id)
    |> add_payment_history_entry("payment_refunded", marked_by_user_id)
  end
  
  # Add an entry to the payment history
  defp add_payment_history_entry(changeset, action, user_id) do
    current_history = get_field(changeset, :payment_history) || %{}
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    
    new_entry = %{
      "action" => action,
      "user_id" => user_id,
      "timestamp" => timestamp,
      "details" => %{
        "status" => get_field(changeset, :status),
        "manual_payment_method" => get_field(changeset, :manual_payment_method),
        "manual_payment_reference" => get_field(changeset, :manual_payment_reference),
        "manual_payment_notes" => get_field(changeset, :manual_payment_notes)
      }
    }
    
    # Add entry with timestamp as key
    updated_history = Map.put(current_history, timestamp, new_entry)
    put_change(changeset, :payment_history, updated_history)
  end
  
  @doc """
  Get display name for payment method.
  """
  def payment_method_display_name("cash"), do: "Cash"
  def payment_method_display_name("check"), do: "Check"
  def payment_method_display_name("bank_transfer"), do: "Bank Transfer"
  def payment_method_display_name("venmo"), do: "Venmo"
  def payment_method_display_name("paypal"), do: "PayPal"
  def payment_method_display_name("other"), do: "Other"
  def payment_method_display_name(_), do: "Unknown"
end
