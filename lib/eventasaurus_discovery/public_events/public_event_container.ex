defmodule EventasaurusDiscovery.PublicEvents.PublicEventContainer.Slug do
  use EctoAutoslugField.Slug, from: :title, to: :slug

  def build_slug(sources, changeset) do
    # Get the default slug from sources
    slug = super(sources, changeset)

    # Add randomness to ensure uniqueness (same pattern as Movie)
    "#{slug}-#{random_suffix()}"
  end

  defp random_suffix do
    :rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")
  end
end

defmodule EventasaurusDiscovery.PublicEvents.PublicEventContainer do
  @moduledoc """
  Schema for event containers (festivals, conferences, tours, etc.)

  A container represents a parent event that encompasses multiple sub-events.
  Examples:
  - Festival: "Unsound Kraków 2025" contains multiple performances
  - Conference: "TechCrunch Disrupt 2025" contains multiple sessions
  - Tour: "Taylor Swift Eras Tour" contains multiple city stops
  - Series: "Monthly Trivia" contains multiple occurrences

  ## Container Types

  - `festival` - Music, cultural, or film festivals
  - `conference` - Tech conferences, academic conferences
  - `tour` - Concert tours, theater tours
  - `series` - Recurring event series
  - `exhibition` - Art exhibitions, museum shows
  - `tournament` - Sports tournaments
  - `unknown` - Not yet classified

  ## Pattern Matching

  Containers store pattern matching data to enable automatic association
  of sub-events that might be imported before the container itself:

  - `title_pattern` - Extracted base title ("Unsound Kraków 2025")
  - `venue_pattern` - Venue name pattern ("Various venues - Kraków")
  - `start_date` / `end_date` - Temporal scope for matching
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventContainerMembership}
  alias EventasaurusDiscovery.PublicEvents.PublicEventContainer.Slug
  alias EventasaurusDiscovery.Sources.Source

  @container_types [:festival, :conference, :tour, :series, :exhibition, :tournament, :unknown]
  @required_fields ~w(title container_type start_date)a
  @optional_fields ~w(description end_date source_event_id source_id title_pattern venue_pattern metadata)a

  schema "public_event_containers" do
    field(:title, :string)
    field(:slug, Slug.Type)
    field(:container_type, Ecto.Enum, values: @container_types)
    field(:description, :string)

    field(:start_date, :utc_datetime)
    field(:end_date, :utc_datetime)

    # Pattern matching fields
    field(:title_pattern, :string)
    field(:venue_pattern, :string)

    # Metadata
    field(:metadata, :map, default: %{})

    # Associations
    belongs_to(:source_event, PublicEvent)
    belongs_to(:source, Source)

    has_many(:memberships, PublicEventContainerMembership, foreign_key: :container_id)
    many_to_many(:events, PublicEvent, join_through: PublicEventContainerMembership)

    timestamps()
  end

  @doc """
  Changeset for creating or updating a container.
  """
  def changeset(container, attrs) do
    container
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> Slug.maybe_generate_slug()
    |> validate_required(@required_fields)
    |> validate_inclusion(:container_type, @container_types)
    |> validate_date_range()
    |> maybe_extract_title_pattern()
    |> unique_constraint(:slug)
  end

  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && DateTime.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end

  defp maybe_extract_title_pattern(changeset) do
    # If title_pattern not provided, extract from title
    case get_change(changeset, :title_pattern) do
      nil ->
        title = get_field(changeset, :title)

        if title do
          # Extract base pattern (remove year, location indicators)
          pattern = extract_pattern_from_title(title)
          put_change(changeset, :title_pattern, pattern)
        else
          changeset
        end

      _pattern ->
        changeset
    end
  end

  @doc """
  Extract title pattern from full title.

  Examples:
    - "Unsound Kraków 2025" → "Unsound Kraków 2025"
    - "TechCrunch Disrupt 2025" → "TechCrunch Disrupt 2025"
    - "Taylor Swift: Eras Tour - Warsaw" → "Taylor Swift: Eras Tour"

  For now, just use the full title. Can be refined later.
  """
  def extract_pattern_from_title(title) when is_binary(title) do
    title
    |> String.trim()
  end

  def extract_pattern_from_title(_), do: nil

  @doc """
  Get container type as string.
  """
  def container_type_string(%__MODULE__{container_type: type}), do: to_string(type)

  @doc """
  Get user-facing container type label.
  """
  def container_type_label(%__MODULE__{container_type: :festival}), do: "Festival"
  def container_type_label(%__MODULE__{container_type: :conference}), do: "Conference"
  def container_type_label(%__MODULE__{container_type: :tour}), do: "Tour"
  def container_type_label(%__MODULE__{container_type: :series}), do: "Event Series"
  def container_type_label(%__MODULE__{container_type: :exhibition}), do: "Exhibition"
  def container_type_label(%__MODULE__{container_type: :tournament}), do: "Tournament"
  def container_type_label(%__MODULE__{container_type: :unknown}), do: "Unknown"
  def container_type_label(_), do: "Unknown"

  @doc """
  Check if container is active (current or upcoming).
  """
  def active?(%__MODULE__{end_date: nil, start_date: start_date}) do
    DateTime.compare(start_date, DateTime.utc_now()) in [:gt, :eq]
  end

  def active?(%__MODULE__{end_date: end_date}) do
    DateTime.compare(end_date, DateTime.utc_now()) in [:gt, :eq]
  end

  @doc """
  Get duration in days.
  """
  def duration_days(%__MODULE__{start_date: _start_date, end_date: nil}), do: 1

  def duration_days(%__MODULE__{start_date: start_date, end_date: end_date}) do
    DateTime.diff(end_date, start_date, :day) + 1
  end

  @doc """
  Get plural form of container type for routing.

  Examples:
    - :festival → "festivals"
    - :conference → "conferences"
  """
  def container_type_plural(:festival), do: "festivals"
  def container_type_plural(:conference), do: "conferences"
  def container_type_plural(:tour), do: "tours"
  def container_type_plural(:series), do: "series"
  def container_type_plural(:exhibition), do: "exhibitions"
  def container_type_plural(:tournament), do: "tournaments"
  def container_type_plural(:unknown), do: "containers"
  def container_type_plural(_), do: "containers"

  @doc """
  Get ring color class for container type.

  Examples:
    - :festival → "ring-purple-500"
    - :conference → "ring-orange-500"
  """
  def container_type_ring_color(:festival), do: "ring-purple-500"
  def container_type_ring_color(:conference), do: "ring-orange-500"
  def container_type_ring_color(:tour), do: "ring-red-500"
  def container_type_ring_color(:series), do: "ring-indigo-500"
  def container_type_ring_color(:exhibition), do: "ring-yellow-500"
  def container_type_ring_color(:tournament), do: "ring-pink-500"
  def container_type_ring_color(:unknown), do: "ring-gray-500"
  def container_type_ring_color(_), do: "ring-gray-500"
end
