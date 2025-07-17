defmodule EventasaurusApp.Venues.Venue do
  use Ecto.Schema
  import Ecto.Changeset

  schema "venues" do
    field(:name, :string)
    field(:address, :string)
    field(:city, :string)
    field(:state, :string)
    field(:country, :string)
    field(:latitude, :float)
    field(:longitude, :float)

    has_many(:events, EventasaurusApp.Events.Event)

    timestamps()
  end

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :address, :city, :state, :country, :latitude, :longitude])
    |> validate_required([:name])
  end
end
