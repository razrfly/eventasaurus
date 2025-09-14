defmodule EventasaurusDiscovery.PublicEvents.PublicEvent.Slug do
  use EctoAutoslugField.Slug, to: :slug

  def get_sources(_changeset, _opts) do
    # Use title as primary source, but also include external_id for uniqueness
    [:title, :external_id]
  end

  def build_slug(sources, changeset) do
    # Get the default slug from title and external_id
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
    field :slug, Slug.Type
    field :description, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :external_id, :string
    field :ticket_url, :string
    field :min_price, :decimal
    field :max_price, :decimal
    field :currency, :string
    field :metadata, :map, default: %{}

    belongs_to :venue, EventasaurusApp.Venues.Venue
    belongs_to :category, EventasaurusDiscovery.Categories.Category

    many_to_many :performers, EventasaurusDiscovery.Performers.Performer,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
      join_keys: [event_id: :id, performer_id: :id]

    timestamps()
  end

  @doc false
  def changeset(public_event, attrs) do
    public_event
    |> cast(attrs, [:title, :description, :starts_at, :ends_at, :venue_id,
                    :external_id, :ticket_url, :min_price,
                    :max_price, :currency, :metadata, :category_id])
    |> validate_required([:title, :starts_at], message: "An event must have both a title and start date - these are non-negotiable")
    |> validate_length(:currency, is: 3)
    |> validate_number(:min_price, greater_than_or_equal_to: 0)
    |> validate_number(:max_price, greater_than_or_equal_to: 0)
    |> validate_price_range()
    |> validate_date_order()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    |> unique_constraint(:external_id)
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