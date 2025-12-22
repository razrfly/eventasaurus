defmodule EventasaurusDiscovery.Performers.Performer.Slug do
  use EctoAutoslugField.Slug, from: :name, to: :slug
end

defmodule EventasaurusDiscovery.Performers.Performer do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.Performers.Performer.Slug

  schema "performers" do
    field(:name, :string)
    field(:slug, Slug.Type)
    field(:image_url, :string)
    field(:metadata, :map, default: %{})
    # Reference to scraping source
    field(:source_id, :integer)

    many_to_many(:public_events, EventasaurusDiscovery.PublicEvents.PublicEvent,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
      join_keys: [performer_id: :id, event_id: :id],
      on_replace: :delete
    )

    # PostHog popularity tracking (synced by PostHogPopularitySyncWorker)
    field(:posthog_view_count, :integer, default: 0)
    field(:posthog_synced_at, :utc_datetime)

    timestamps()
  end

  @doc false
  def changeset(performer, attrs) do
    performer
    |> cast(attrs, [:name, :image_url, :metadata, :source_id])
    |> validate_required([:name])
    |> sanitize_utf8()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
  end

  defp sanitize_utf8(changeset) do
    changeset
    |> update_change(:name, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
  end
end
