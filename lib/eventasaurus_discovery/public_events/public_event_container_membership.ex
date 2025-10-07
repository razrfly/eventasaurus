defmodule EventasaurusDiscovery.PublicEvents.PublicEventContainerMembership do
  @moduledoc """
  Schema for container-event associations.

  Tracks which events belong to which containers and how that
  association was determined (confidence scoring).

  ## Association Methods

  - `explicit` - Came from source data (confidence: 1.00)
  - `title_match` - Title contains parent pattern (confidence: ~0.85)
  - `date_range` - Event within container dates (confidence: ~0.60)
  - `artist_overlap` - Artists match container (confidence: ~0.70)
  - `venue_pattern` - Venue matches container pattern (confidence: ~0.75)
  - `manual` - User-created association (confidence: 1.00)

  ## Confidence Scoring

  Confidence scores range from 0.00 to 1.00:
  - 0.90-1.00: Very high confidence (multiple strong signals)
  - 0.70-0.89: High confidence (strong signal match)
  - 0.50-0.69: Medium confidence (weak signal or single match)
  - 0.00-0.49: Low confidence (needs manual review)

  Auto-association threshold: 0.70
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventContainer}

  @association_methods [
    :explicit,
    :title_match,
    :date_range,
    :artist_overlap,
    :venue_pattern,
    :manual
  ]
  @required_fields ~w(container_id event_id association_method)a
  @optional_fields ~w(confidence_score)a

  schema "public_event_container_memberships" do
    field(:association_method, Ecto.Enum, values: @association_methods)
    field(:confidence_score, :decimal, default: Decimal.new("1.00"))

    belongs_to(:container, PublicEventContainer)
    belongs_to(:event, PublicEvent)

    timestamps()
  end

  @doc """
  Changeset for creating a membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:association_method, @association_methods)
    |> validate_number(:confidence_score,
      greater_than_or_equal_to: Decimal.new("0"),
      less_than_or_equal_to: Decimal.new("1")
    )
    |> foreign_key_constraint(:container_id)
    |> foreign_key_constraint(:event_id)
    |> unique_constraint([:container_id, :event_id],
      name: :public_event_container_memberships_container_id_event_id_index
    )
  end

  @doc """
  Get confidence level category.
  """
  def confidence_level(%__MODULE__{confidence_score: score}) do
    score = Decimal.to_float(score)

    cond do
      score >= 0.90 -> :very_high
      score >= 0.70 -> :high
      score >= 0.50 -> :medium
      true -> :low
    end
  end

  @doc """
  Check if confidence meets auto-association threshold.
  """
  def auto_associable?(%__MODULE__{confidence_score: score}) do
    Decimal.compare(score, Decimal.new("0.70")) in [:gt, :eq]
  end

  @doc """
  Get method label for display.
  """
  def method_label(%__MODULE__{association_method: :explicit}), do: "Explicit"
  def method_label(%__MODULE__{association_method: :title_match}), do: "Title Match"
  def method_label(%__MODULE__{association_method: :date_range}), do: "Date Range"
  def method_label(%__MODULE__{association_method: :artist_overlap}), do: "Artist Overlap"
  def method_label(%__MODULE__{association_method: :venue_pattern}), do: "Venue Pattern"
  def method_label(%__MODULE__{association_method: :manual}), do: "Manual"
  def method_label(_), do: "Unknown"
end
