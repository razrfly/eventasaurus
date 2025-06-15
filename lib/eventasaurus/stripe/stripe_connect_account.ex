defmodule EventasaurusApp.Stripe.StripeConnectAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stripe_connect_accounts" do
    field :stripe_user_id, :string
    field :connected_at, :utc_datetime
    field :disconnected_at, :utc_datetime

    belongs_to :user, EventasaurusApp.Accounts.User
    has_many :orders, EventasaurusApp.Events.Order, foreign_key: :stripe_connect_account_id

    timestamps()
  end

  @doc false
  def changeset(stripe_connect_account, attrs) do
    stripe_connect_account
    |> cast(attrs, [:stripe_user_id, :connected_at, :disconnected_at, :user_id])
    |> validate_required([:stripe_user_id, :user_id, :connected_at])
    |> unique_constraint(:stripe_user_id)
    |> unique_constraint(:user_id, name: :stripe_connect_accounts_user_id_index, message: "already has an active Stripe Connect account")
    |> foreign_key_constraint(:user_id)
  end

  def connected?(%__MODULE__{disconnected_at: nil}), do: true
  def connected?(_), do: false

  def disconnect_changeset(stripe_connect_account) do
    stripe_connect_account
    |> change(%{disconnected_at: DateTime.utc_now()})
  end
end
