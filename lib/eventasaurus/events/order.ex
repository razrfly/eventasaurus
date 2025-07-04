defmodule EventasaurusApp.Events.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(pending confirmed refunded canceled)

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

    belongs_to :user, EventasaurusApp.Accounts.User
    belongs_to :event, EventasaurusApp.Events.Event
    belongs_to :ticket, EventasaurusApp.Events.Ticket
    belongs_to :stripe_connect_account, EventasaurusApp.Stripe.StripeConnectAccount

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :quantity, :subtotal_cents, :tax_cents, :total_cents, :currency, :status,
      :stripe_session_id, :payment_reference, :confirmed_at, :user_id, :event_id,
      :ticket_id, :stripe_connect_account_id, :application_fee_amount, :pricing_snapshot
    ])
    |> validate_required([:quantity, :subtotal_cents, :total_cents, :currency, :status, :user_id, :event_id, :ticket_id])
    |> validate_number(:quantity, greater_than: 0, message: "must be greater than 0")
    |> validate_number(:subtotal_cents, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_number(:tax_cents, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_number(:total_cents, greater_than: 0, message: "must be greater than 0")
    |> validate_number(:application_fee_amount, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_application_fee_amount()
    |> validate_inclusion(:currency, EventasaurusWeb.Helpers.CurrencyHelpers.supported_currency_codes(), message: "must be a supported currency")
    |> validate_inclusion(:status, @valid_statuses, message: "must be a valid status")
    |> validate_total_calculation()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:stripe_connect_account_id)
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
end
