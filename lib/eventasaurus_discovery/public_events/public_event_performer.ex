defmodule EventasaurusDiscovery.PublicEvents.PublicEventPerformer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "public_event_performers" do
    field :billing_order, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :event, EventasaurusDiscovery.PublicEvents.PublicEvent
    belongs_to :performer, EventasaurusDiscovery.Performers.Performer

    timestamps()
  end

  @doc false
  def changeset(public_event_performer, attrs) do
    public_event_performer
    |> cast(attrs, [:event_id, :performer_id, :billing_order, :metadata])
    |> validate_required([:event_id, :performer_id])
    |> validate_number(:billing_order, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:performer_id)
    |> unique_constraint([:event_id, :performer_id])
  end
end