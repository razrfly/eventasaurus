defmodule EventasaurusApp.Venues.Venue do
  use Ecto.Schema
  import Ecto.Changeset

  schema "venues" do
    field :name, :string
    field :address, :string
    field :city, :string
    field :state, :string
    field :country, :string
    field :latitude, :float
    field :longitude, :float
    field :venue_type, :string, default: "venue"

    has_many :events, EventasaurusApp.Events.Event

    timestamps()
  end

  @valid_venue_types ["venue", "city", "region", "online", "tbd"]

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :address, :city, :state, :country, :latitude, :longitude, :venue_type])
    |> validate_required([:name, :venue_type])
    |> validate_inclusion(:venue_type, @valid_venue_types, message: "must be one of: #{Enum.join(@valid_venue_types, ", ")}")
  end

  @doc """
  Returns the list of valid venue types.
  """
  def valid_venue_types, do: @valid_venue_types

  @doc """
  Returns user-friendly labels for venue types.
  """
  def venue_type_options do
    [
      {"Physical Venue", "venue"},
      {"City", "city"},
      {"Region", "region"},
      {"Online", "online"},
      {"To Be Determined", "tbd"}
    ]
  end
end
