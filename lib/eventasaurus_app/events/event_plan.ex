defmodule EventasaurusApp.Events.EventPlan do
  @moduledoc """
  Schema for linking public events with private event plans.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_plans" do
    field(:public_event_id, :id)
    field(:private_event_id, :id)
    field(:created_by, :id)

    belongs_to(:private_event, EventasaurusApp.Events.Event,
      foreign_key: :private_event_id,
      define_field: false
    )

    belongs_to(:public_event, EventasaurusDiscovery.PublicEvents.PublicEvent,
      foreign_key: :public_event_id,
      define_field: false
    )

    belongs_to(:creator, EventasaurusApp.Accounts.User,
      foreign_key: :created_by,
      define_field: false
    )

    timestamps()
  end

  @doc false
  def changeset(event_plan, attrs) do
    event_plan
    |> cast(attrs, [:public_event_id, :private_event_id, :created_by])
    |> validate_required([:public_event_id, :private_event_id, :created_by])
    |> foreign_key_constraint(:public_event_id)
    |> foreign_key_constraint(:private_event_id)
    |> foreign_key_constraint(:created_by)
    |> unique_constraint([:public_event_id, :created_by], name: :unique_user_plan_per_public_event)
  end
end
