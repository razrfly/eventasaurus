defmodule EventasaurusDiscovery.PublicEvents.PublicEvent.Slug do
  use EctoAutoslugField.Slug, to: :slug
  require Logger

  def get_sources(_changeset, _opts) do
    # Use title as primary source for slug generation
    [:title]
  end

  def build_slug(sources, changeset) do
    # Universal UTF-8 protection for all scrapers
    # This ensures that regardless of which scraper (Karnet, Ticketmaster, Bandsintown, etc.)
    # provides the data, we handle UTF-8 issues consistently
    safe_sources = sources |> Enum.map(&ensure_safe_string/1)

    # Only proceed if we have valid content
    case safe_sources do
      ["" | _] ->
        # Fallback slug if title is empty/invalid after cleaning
        # This prevents slug generation errors when UTF-8 cleaning results in empty string
        "event-#{DateTime.utc_now() |> DateTime.to_unix()}-#{random_suffix()}"

      _ ->
        # Get the default slug from cleaned sources
        slug = super(safe_sources, changeset)

        # Add some randomness to ensure uniqueness
        "#{slug}-#{random_suffix()}"
    end
  end

  # Universal UTF-8 safety function used by all scrapers
  defp ensure_safe_string(value) do
    case value do
      # Handle error tuples from failed UTF-8 conversions
      # This catches the {:error, "", <<226>>} type errors from Ticketmaster
      {:error, _, invalid_bytes} ->
        Logger.warning("""
        Invalid UTF-8 detected in slug source
        Error tuple: #{inspect(value)}
        Invalid bytes: #{inspect(invalid_bytes, limit: 50)}
        """)

        ""

      # Handle valid binary strings
      str when is_binary(str) ->
        # Use our universal UTF8 utility to clean the string
        EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8(str)

      # Handle nil values
      nil ->
        ""

      # Convert other types to string and ensure UTF-8
      other ->
        other
        |> to_string()
        |> EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8()
    end
  rescue
    # Catch any conversion errors and return empty string
    error ->
      Logger.error("Error in ensure_safe_string: #{inspect(error)}")
      ""
  end

  defp random_suffix do
    :rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")
  end
end

defmodule EventasaurusDiscovery.PublicEvents.PublicEvent do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.PublicEvents.PublicEvent.Slug

  schema "public_events" do
    field(:title, :string)
    field(:title_translations, :map)
    field(:slug, Slug.Type)
    field(:starts_at, :utc_datetime)
    field(:ends_at, :utc_datetime)
    # external_id moved to public_event_sources table
    # ticket_url moved to public_event_sources table (source-specific)
    # min_price, max_price, currency moved to public_event_sources table (source-specific)
    # metadata moved to public_event_sources table
    field(:occurrences, :map)

    # Virtual field for primary category (populated in queries when needed)
    field(:primary_category_id, :id, virtual: true)

    belongs_to(:venue, EventasaurusApp.Venues.Venue)

    # Keep old relationship for backward compatibility during transition
    belongs_to(:category, EventasaurusDiscovery.Categories.Category)

    # New many-to-many relationship
    many_to_many(:categories, EventasaurusDiscovery.Categories.Category,
      join_through: EventasaurusDiscovery.Categories.PublicEventCategory,
      join_keys: [event_id: :id, category_id: :id],
      on_replace: :delete
    )

    many_to_many(:performers, EventasaurusDiscovery.Performers.Performer,
      join_through: EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
      join_keys: [event_id: :id, performer_id: :id]
    )

    many_to_many(:movies, EventasaurusDiscovery.Movies.Movie,
      join_through: EventasaurusDiscovery.PublicEvents.EventMovie,
      join_keys: [event_id: :id, movie_id: :id],
      on_replace: :delete
    )

    # Association to sources for description_translations access
    has_many(:sources, EventasaurusDiscovery.PublicEvents.PublicEventSource,
      foreign_key: :event_id
    )

    timestamps()
  end

  @doc false
  def changeset(public_event, attrs) do
    public_event
    |> cast(attrs, [
      :title,
      :title_translations,
      :starts_at,
      :ends_at,
      :venue_id,
      :category_id,
      :occurrences
    ])
    |> validate_required([:title, :starts_at, :venue_id],
      message: "Public events must have a venue for proper location and collision detection"
    )
    # PostgreSQL boundary protection
    |> sanitize_utf8()
    |> validate_date_order()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:slug)
    # external_id can collide across sources; uniqueness enforced in PublicEventSource
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:category_id)
  end

  # PostgreSQL boundary protection - validate UTF-8 before DB insertion
  defp sanitize_utf8(changeset) do
    changeset
    |> update_change(:title, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
    |> update_change(
      :title_translations,
      &EventasaurusDiscovery.Utils.UTF8.validate_map_strings/1
    )
    |> update_change(:occurrences, &EventasaurusDiscovery.Utils.UTF8.validate_map_strings/1)
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
      # Single events don't need a label
      count == 1 -> nil
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

  def next_occurrence_date(%__MODULE__{occurrences: %{"dates" => dates}, starts_at: starts_at})
      when is_list(dates) do
    now = DateTime.utc_now()

    # Parse dates and find the next upcoming one
    upcoming =
      dates
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
