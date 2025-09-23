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

  @doc """
  Returns the count of occurrences for an event.
  """
  def occurrence_count(%__MODULE__{occurrences: nil}), do: 0
  def occurrence_count(%__MODULE__{occurrences: %{"dates" => dates}}) when is_list(dates) do
    length(dates)
  end
  def occurrence_count(_), do: 0

  @doc """
  Checks if an event is recurring (has multiple occurrences).
  """
  def recurring?(%__MODULE__{} = event) do
    occurrence_count(event) > 1
  end

  @doc """
  Returns a human-readable description of the event frequency.
  """
  def frequency_label(%__MODULE__{} = event) do
    count = occurrence_count(event)

    cond do
      count == 0 -> nil
      count == 1 -> nil  # Single events don't need a label
      count <= 7 -> "#{count} dates available"
      count <= 30 -> "Multiple dates"
      count <= 60 -> "Daily event"
      true -> "#{count} dates available"
    end
  end

  @doc """
  Returns the next upcoming date for an event with occurrences.
  """
  def next_occurrence_date(%__MODULE__{occurrences: nil, starts_at: starts_at}), do: starts_at
  def next_occurrence_date(%__MODULE__{occurrences: %{"dates" => dates}, starts_at: starts_at}) when is_list(dates) do
    now = DateTime.utc_now()

    # Parse dates and find the next upcoming one
    upcoming = dates
      |> Enum.map(fn %{"date" => date_str, "time" => time_str} ->
        with {:ok, date} <- Date.from_iso8601(date_str),
             {:ok, time} <- Time.from_iso8601(time_str <> ":00") do
          DateTime.new!(date, time, "Etc/UTC")
        else
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
      |> Enum.sort(&(DateTime.compare(&1, &2) == :lt))
      |> List.first()

    upcoming || starts_at
  end
  def next_occurrence_date(%__MODULE__{starts_at: starts_at}), do: starts_at
end