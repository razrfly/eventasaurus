defmodule EventasaurusDiscovery.Performers.Performer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "performers" do
    field :name, :string
    field :slug, :string
    field :metadata, :map, default: %{}

    many_to_many :public_events, EventasaurusDiscovery.PublicEvents.PublicEvent,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer

    timestamps()
  end

  @doc false
  def changeset(performer, attrs) do
    performer
    |> cast(attrs, [:name, :slug, :metadata])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end