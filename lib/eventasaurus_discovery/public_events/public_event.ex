defmodule EventasaurusDiscovery.PublicEvents.PublicEvent.Slug do
  use EctoAutoslugField.Slug, to: :slug

  def get_sources(_changeset, _opts) do
    # Use title as primary source for slug generation
    [:title]
  end

  def build_slug(sources, changeset) do
    # Get the default slug from title
    slug = super(sources, changeset)

    # Add some randomness to ensure uniqueness even for identical titles + external_ids
    random_suffix = :rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")

    # Combine with random suffix
    "#{slug}-#{random_suffix}"
  end
end

defmodule EventasaurusDiscovery.PublicEvents.PublicEvent do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.PublicEvents.PublicEvent.Slug

  schema "public_events" do
    field :title, :string
    field :title_translations, :map
    field :slug, Slug.Type
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    # external_id moved to public_event_sources table
    field :ticket_url, :string
    field :min_price, :decimal
    field :max_price, :decimal
    field :currency, :string
    # metadata moved to public_event_sources table
    field :occurrences, :map

    belongs_to :venue, EventasaurusApp.Venues.Venue

    # Keep old relationship for backward compatibility during transition
    belongs_to :category, EventasaurusDiscovery.Categories.Category

    # New many-to-many relationship
    many_to_many :categories, EventasaurusDiscovery.Categories.Category,
      join_through: EventasaurusDiscovery.Categories.PublicEventCategory,
      join_keys: [event_id: :id, category_id: :id],
      on_replace: :delete

    many_to_many :performers, EventasaurusDiscovery.Performers.Performer,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
      join_keys: [event_id: :id, performer_id: :id]

    # Association to sources for description_translations access
    has_many :sources, EventasaurusDiscovery.PublicEvents.PublicEventSource,
      foreign_key: :event_id

    timestamps()
  end

  @doc false
  def changeset(public_event, attrs) do
    public_event
    |> cast(attrs, [:title, :title_translations, :starts_at, :ends_at, :venue_id,
                    :ticket_url, :min_price,
                    :max_price, :currency, :category_id, :occurrences])
    |> validate_required([:title, :starts_at], message: "An event must have both a title and start date - these are non-negotiable")
    |> validate_length(:currency, is: 3)
    |> validate_number(:min_price, greater_than_or_equal_to: 0)
    |> validate_number(:max_price, greater_than_or_equal_to: 0)
    |> validate_price_range()
    |> validate_date_order()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    # external_id can collide across sources; uniqueness enforced in PublicEventSource
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:category_id)
  end

  defp validate_price_range(changeset) do
    min_price = get_field(changeset, :min_price)
    max_price = get_field(changeset, :max_price)

    if min_price && max_price && Decimal.compare(max_price, min_price) == :lt do
      add_error(changeset, :max_price, "must be greater than or equal to min_price")
    else
      changeset
    end
  end

  defp validate_date_order(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    cond do
      is_nil(starts_at) or is_nil(ends_at) ->
        changeset
      DateTime.compare(ends_at, starts_at) == :lt ->
        add_error(changeset, :ends_at, "must be after start date")
      true ->
        changeset
    end
  end
end