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
    field :place_id, :string
    field :source, :string, default: "user"
    field :metadata, :map, default: %{}

    belongs_to :city_ref, EventasaurusDiscovery.Locations.City, foreign_key: :city_id
    has_many :events, EventasaurusApp.Events.Event
    has_many :public_events, EventasaurusDiscovery.PublicEvents.PublicEvent

    timestamps()
  end

  @valid_venue_types ["venue", "city", "region", "online", "tbd"]

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :address, :city, :state, :country, :latitude, :longitude,
                    :venue_type, :place_id, :source, :city_id, :metadata])
    |> validate_required([:name, :venue_type])
    |> validate_inclusion(:venue_type, @valid_venue_types, message: "must be one of: #{Enum.join(@valid_venue_types, ", ")}")
    |> validate_inclusion(:source, ["user", "scraper", "google"])
    |> foreign_key_constraint(:city_id)
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
