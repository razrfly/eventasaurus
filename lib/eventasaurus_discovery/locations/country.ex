defmodule EventasaurusDiscovery.Locations.Country do
  use Ecto.Schema
  import Ecto.Changeset

  schema "countries" do
    field :name, :string
    field :code, :string
    field :slug, :string

    has_many :cities, EventasaurusDiscovery.Locations.City

    timestamps()
  end

  @doc false
  def changeset(country, attrs) do
    country
    |> cast(attrs, [:name, :code, :slug])
    |> validate_required([:name, :code, :slug])
    |> validate_length(:code, is: 2)
    |> unique_constraint(:code)
    |> unique_constraint(:slug)
  end
end