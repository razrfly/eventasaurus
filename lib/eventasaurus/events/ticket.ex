defmodule EventasaurusApp.Events.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tickets" do
    field :title, :string
    field :description, :string
    field :price_cents, :integer
    field :currency, :string, default: "usd"
    field :quantity, :integer
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :tippable, :boolean, default: false

    belongs_to :event, EventasaurusApp.Events.Event
    has_many :orders, EventasaurusApp.Events.Order

    timestamps()
  end

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:title, :description, :price_cents, :currency, :quantity, :starts_at, :ends_at, :tippable, :event_id])
    |> validate_required([:title, :price_cents, :quantity, :event_id])
    |> validate_number(:price_cents, greater_than: 0, message: "must be greater than 0")
    |> validate_number(:quantity, greater_than: 0, message: "must be greater than 0")
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_inclusion(:currency, ["usd", "eur", "gbp", "cad", "aud"], message: "must be a supported currency")
    |> validate_availability_window()
    |> foreign_key_constraint(:event_id)
  end

  defp validate_availability_window(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    cond do
      starts_at && ends_at && DateTime.compare(starts_at, ends_at) != :lt ->
        add_error(changeset, :ends_at, "must be after start time")

      starts_at && DateTime.compare(starts_at, DateTime.utc_now()) == :lt ->
        add_error(changeset, :starts_at, "cannot be in the past")

      true ->
        changeset
    end
  end

  def on_sale?(%__MODULE__{starts_at: nil}), do: true
  def on_sale?(%__MODULE__{starts_at: starts_at, ends_at: nil}) do
    DateTime.compare(DateTime.utc_now(), starts_at) != :lt
  end
  def on_sale?(%__MODULE__{starts_at: starts_at, ends_at: ends_at}) do
    now = DateTime.utc_now()
    DateTime.compare(now, starts_at) != :lt && DateTime.compare(now, ends_at) == :lt
  end
end
