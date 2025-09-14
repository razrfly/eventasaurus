defmodule EventasaurusDiscovery.Locations.City do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cities" do
    field :name, :string
    field :slug, :string
    field :latitude, :decimal
    field :longitude, :decimal

    belongs_to :country, EventasaurusDiscovery.Locations.Country
    has_many :venues, EventasaurusApp.Venues.Venue

    timestamps()
  end

  @doc false
  def changeset(city, attrs) do
    city
    |> cast(attrs, [:name, :slug, :country_id, :latitude, :longitude])
    |> validate_required([:name, :slug, :country_id])
    |> foreign_key_constraint(:country_id)
    |> unique_constraint([:country_id, :slug])
  end
end