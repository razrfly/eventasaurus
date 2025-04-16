defmodule EventasaurusApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :supabase_id, :string

    many_to_many :events, EventasaurusApp.Events.Event,
      join_through: EventasaurusApp.Events.EventUser

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :supabase_id])
    |> validate_required([:email, :name, :supabase_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> unique_constraint(:supabase_id)
  end
end
