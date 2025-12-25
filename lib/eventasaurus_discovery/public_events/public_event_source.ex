defmodule EventasaurusDiscovery.PublicEvents.PublicEventSource do
  @moduledoc """
  Represents the relationship between a PublicEvent and its Source.

  Each PublicEvent can come from multiple sources, and each source tracks:
  - external_id: The source's unique identifier for this event
  - last_seen_at: When the scraper last saw this event
  - source-specific metadata and pricing

  ## External ID Conventions

  The external_id must follow patterns defined in docs/EXTERNAL_ID_CONVENTIONS.md.
  Use `EventasaurusDiscovery.ExternalIdGenerator` to generate and validate external_ids.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusDiscovery.ExternalIdGenerator

  schema "public_event_sources" do
    field(:source_url, :string)
    field(:external_id, :string)
    field(:last_seen_at, :utc_datetime)
    field(:metadata, :map, default: %{})
    field(:description_translations, :map)
    field(:image_url, :string)
    field(:min_price, :decimal)
    field(:max_price, :decimal)
    field(:currency, :string)
    field(:is_free, :boolean, default: false)
    # Pre-computed translation count (updated by database trigger on insert/update)
    field(:description_translation_count, :integer, default: 0)

    belongs_to(:event, EventasaurusDiscovery.PublicEvents.PublicEvent)
    belongs_to(:source, EventasaurusDiscovery.Sources.Source)

    timestamps()
  end

  @doc false
  def changeset(public_event_source, attrs) do
    public_event_source
    |> cast(attrs, [
      :event_id,
      :source_id,
      :source_url,
      :external_id,
      :last_seen_at,
      :metadata,
      :description_translations,
      :image_url,
      :min_price,
      :max_price,
      :currency,
      :is_free
    ])
    |> validate_required([:event_id, :source_id, :last_seen_at])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:source_id)
    |> unique_constraint([:source_id, :external_id])
  end

  @doc """
  Changeset with event type validation for external_id.

  Use this when you know the event type (e.g., from recurrence_rule presence).
  This validates that the external_id follows the correct pattern for the event type.

  ## Parameters

  - `public_event_source` - The struct to update
  - `attrs` - Attributes to cast
  - `event_type` - One of `:single`, `:multi_date`, `:showtime`, or `:recurring`

  ## Example

      changeset_with_type(source, attrs, :recurring)
  """
  def changeset_with_type(public_event_source, attrs, event_type) do
    public_event_source
    |> changeset(attrs)
    |> validate_external_id_for_type(event_type)
  end

  @doc """
  Validates that an external_id matches the expected pattern for an event type.

  This is called automatically by `changeset_with_type/3`, but can also be
  added to a changeset manually.

  ## Example

      changeset
      |> validate_external_id_for_type(:recurring)
  """
  def validate_external_id_for_type(changeset, event_type) do
    validate_change(changeset, :external_id, fn :external_id, external_id ->
      case ExternalIdGenerator.validate(event_type, external_id) do
        :ok ->
          []

        {:error, reason} ->
          [external_id: reason]
      end
    end)
  end

  @doc """
  Detects if an external_id has a date suffix that may indicate a convention violation.

  This is a lightweight check useful for auditing. It doesn't know the event type,
  so it can only flag potential issues for manual review.

  ## Returns

  - `{:ok, :no_date}` - No date suffix found
  - `{:warning, :has_date}` - Date suffix found (may or may not be valid depending on event type)
  """
  def check_external_id_date_suffix(external_id) when is_binary(external_id) do
    if ExternalIdGenerator.has_date_suffix?(external_id) do
      {:warning, :has_date}
    else
      {:ok, :no_date}
    end
  end

  def check_external_id_date_suffix(_), do: {:ok, :no_date}
end
