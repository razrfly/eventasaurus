defmodule EventasaurusDiscovery.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :icon, :string
    field :color, :string
    field :display_order, :integer, default: 0

    has_many :public_events, EventasaurusDiscovery.PublicEvents.PublicEvent

    timestamps()
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description, :icon, :color, :display_order])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> validate_format(:color, ~r/^#[0-9A-Fa-f]{6}$/, message: "must be a valid hex color")
  end
end