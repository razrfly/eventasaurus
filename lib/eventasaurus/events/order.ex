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

    belongs_to :user, EventasaurusApp.Accounts.User
    belongs_to :event, EventasaurusApp.Events.Event
    belongs_to :ticket, EventasaurusApp.Events.Ticket

    timestamps()
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:quantity, :subtotal_cents, :tax_cents, :total_cents, :currency, :status, :stripe_session_id, :payment_reference, :confirmed_at, :user_id, :event_id, :ticket_id])
    |> validate_required([:quantity, :subtotal_cents, :total_cents, :currency, :status, :user_id, :event_id, :ticket_id])
    |> validate_number(:quantity, greater_than: 0, message: "must be greater than 0")
    |> validate_number(:subtotal_cents, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_number(:tax_cents, greater_than_or_equal_to: 0, message: "cannot be negative")
    |> validate_number(:total_cents, greater_than: 0, message: "must be greater than 0")
    |> validate_inclusion(:currency, ["usd", "eur", "gbp", "cad", "aud"], message: "must be a supported currency")
    |> validate_inclusion(:status, @valid_statuses, message: "must be a valid status")
    |> validate_total_calculation()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:ticket_id)
  end

  defp validate_total_calculation(changeset) do
    subtotal = get_field(changeset, :subtotal_cents)
    tax = get_field(changeset, :tax_cents) || 0
    total = get_field(changeset, :total_cents)

    if subtotal && total && (subtotal + tax) != total do
      add_error(changeset, :total_cents, "must equal subtotal plus tax")
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

  def can_refund?(%__MODULE__{status: "confirmed"}), do: true
  def can_refund?(%__MODULE__{status: "canceled"}), do: true
  def can_refund?(_), do: false
end
