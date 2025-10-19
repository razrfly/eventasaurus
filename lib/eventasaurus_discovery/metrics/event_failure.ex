defmodule EventasaurusDiscovery.Metrics.EventFailure do
  @moduledoc """
  Schema for tracking aggregated event processing failures.

  Failures are grouped by source_id + error_category + error_message,
  maintaining occurrence counts and sample external_ids for debugging.

  ## Fields

  - `source_id` - Reference to the discovery source
  - `error_category` - Standardized error category (see ErrorCategories)
  - `error_message` - The actual error message (truncated to 500 chars)
  - `sample_external_ids` - Up to 5 sample external_ids for debugging
  - `occurrence_count` - Number of times this error has occurred
  - `first_seen_at` - When this error was first observed
  - `last_seen_at` - When this error was most recently observed

  ## Usage

      # Query failures for a source
      from(f in EventFailure,
        where: f.source_id == ^source_id,
        order_by: [desc: f.occurrence_count]
      )

      # Get failure breakdown by category
      from(f in EventFailure,
        where: f.source_id == ^source_id,
        group_by: f.error_category,
        select: {f.error_category, sum(f.occurrence_count)}
      )
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusDiscovery.Sources.Source

  schema "discovery_event_failures" do
    field :error_category, :string
    field :error_message, :string
    field :sample_external_ids, {:array, :string}, default: []
    field :occurrence_count, :integer, default: 1
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    belongs_to :source, Source

    timestamps()
  end

  @doc """
  Changeset for creating or updating an event failure record.

  ## Required fields
  - source_id
  - error_category
  - error_message
  - first_seen_at
  - last_seen_at

  ## Validations
  - error_category must be one of the 9 standard categories
  - occurrence_count must be >= 1
  - sample_external_ids array length <= 5
  """
  def changeset(failure, attrs) do
    failure
    |> cast(attrs, [
      :source_id,
      :error_category,
      :error_message,
      :sample_external_ids,
      :occurrence_count,
      :first_seen_at,
      :last_seen_at
    ])
    |> validate_required([
      :source_id,
      :error_category,
      :error_message,
      :first_seen_at,
      :last_seen_at
    ])
    |> validate_inclusion(:error_category, [
      "validation_error",
      "geocoding_error",
      "venue_error",
      "performer_error",
      "category_error",
      "duplicate_error",
      "network_error",
      "data_quality_error",
      "unknown_error"
    ])
    |> validate_number(:occurrence_count, greater_than_or_equal_to: 1)
    |> validate_sample_ids_length()
    |> foreign_key_constraint(:source_id)
  end

  # Private validations

  defp validate_sample_ids_length(changeset) do
    case get_field(changeset, :sample_external_ids) do
      nil ->
        changeset

      ids when is_list(ids) ->
        if length(ids) > 5 do
          add_error(changeset, :sample_external_ids, "cannot have more than 5 samples")
        else
          changeset
        end

      _ ->
        add_error(changeset, :sample_external_ids, "must be a list")
    end
  end
end
