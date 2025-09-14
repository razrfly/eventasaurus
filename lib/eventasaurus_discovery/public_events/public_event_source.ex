defmodule EventasaurusDiscovery.PublicEvents.PublicEventSource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "public_event_sources" do
    field :source_url, :string
    field :external_id, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :is_primary, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :event, EventasaurusDiscovery.PublicEvents.PublicEvent
    belongs_to :source, EventasaurusDiscovery.Sources.Source

    timestamps()
  end

  @doc false
  def changeset(public_event_source, attrs) do
    public_event_source
    |> cast(attrs, [:event_id, :source_id, :source_url, :external_id,
                    :first_seen_at, :last_seen_at, :is_primary, :metadata])
    |> validate_required([:event_id, :source_id, :first_seen_at, :last_seen_at])
    |> validate_timestamp_order()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:source_id)
    |> unique_constraint([:event_id, :source_id])
  end

  defp validate_timestamp_order(changeset) do
    first = get_field(changeset, :first_seen_at)
    last = get_field(changeset, :last_seen_at)

    cond do
      is_nil(first) or is_nil(last) ->
        changeset
      DateTime.compare(last, first) == :lt ->
        add_error(changeset, :last_seen_at, "must be >= first_seen_at")
      true ->
        changeset
    end
  end
end