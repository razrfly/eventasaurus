defmodule EventasaurusDiscovery.Sources.Source do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sources" do
    field(:name, :string)
    field(:slug, :string)
    field(:website_url, :string)
    field(:priority, :integer, default: 50)
    field(:is_active, :boolean, default: true)
    field(:metadata, :map, default: %{})
    field(:aggregate_on_index, :boolean, default: false)
    field(:aggregation_type, :string)

    has_many(:public_event_sources, EventasaurusDiscovery.PublicEvents.PublicEventSource)

    timestamps()
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :slug, :website_url, :priority, :is_active, :metadata, :aggregate_on_index, :aggregation_type])
    |> validate_required([:name, :slug])
    |> update_change(:slug, &(&1 && String.downcase(&1)))
    |> validate_format(:website_url, ~r/^https?:\/\/\S+$/i,
      message: "must start with http:// or https://"
    )
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> unique_constraint(:slug)
  end
end
