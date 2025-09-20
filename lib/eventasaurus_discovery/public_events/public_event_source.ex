defmodule EventasaurusDiscovery.PublicEvents.PublicEventSource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "public_event_sources" do
    field :source_url, :string
    field :external_id, :string
    field :last_seen_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :description_translations, :map
    field :image_url, :string

    belongs_to :event, EventasaurusDiscovery.PublicEvents.PublicEvent
    belongs_to :source, EventasaurusDiscovery.Sources.Source

    timestamps()
  end

  @doc false
  def changeset(public_event_source, attrs) do
    public_event_source
    |> cast(attrs, [:event_id, :source_id, :source_url, :external_id,
                    :last_seen_at, :metadata, :description_translations, :image_url])
    |> validate_required([:event_id, :source_id, :last_seen_at])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:source_id)
    |> unique_constraint([:event_id, :source_id])
    |> unique_constraint([:source_id, :external_id])
  end
end