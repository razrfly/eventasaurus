defmodule EventasaurusDiscovery.Categories.CategoryBacktestResult do
  @moduledoc """
  Ecto schema for individual ML category classification backtest results.

  Each result represents a single classification attempt comparing
  the ML prediction against the expected category from DB mappings.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusDiscovery.Categories.CategoryBacktestRun

  schema "category_backtest_results" do
    # Parent association
    belongs_to(:backtest_run, CategoryBacktestRun)

    # Input data (from category_mappings)
    field(:source, :string)
    field(:external_term, :string)

    # Expected result (from DB mappings)
    field(:expected_category_slug, :string)

    # ML Prediction
    field(:predicted_category_slug, :string)
    field(:prediction_score, :float)
    field(:all_scores, :map)

    # Result analysis
    field(:is_correct, :boolean)

    # Timing
    field(:classification_time_ms, :integer)

    timestamps(updated_at: false)
  end

  @required_fields [:backtest_run_id, :source, :external_term, :expected_category_slug]
  @optional_fields [
    :predicted_category_slug,
    :prediction_score,
    :all_scores,
    :is_correct,
    :classification_time_ms
  ]

  @doc """
  Creates a changeset for a backtest result.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(result, attrs) do
    result
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:backtest_run_id)
    |> compute_is_correct()
  end

  @doc """
  Creates a result struct from a classification outcome.

  ## Parameters

  - `run_id` - The backtest run ID
  - `mapping` - The category mapping being tested (source, external_term, category_slug)
  - `prediction` - The ML prediction result from CategoryClassifier
  - `time_ms` - Classification time in milliseconds
  """
  @spec from_prediction(integer(), map(), map(), integer()) :: map()
  def from_prediction(run_id, mapping, prediction, time_ms) do
    expected = mapping.category_slug
    predicted = prediction[:category]

    %{
      backtest_run_id: run_id,
      source: mapping.source,
      external_term: mapping.external_term,
      expected_category_slug: expected,
      predicted_category_slug: predicted,
      prediction_score: prediction[:score],
      all_scores: prediction[:all_scores],
      is_correct: expected == predicted,
      classification_time_ms: time_ms
    }
  end

  # Compute is_correct based on expected vs predicted
  defp compute_is_correct(changeset) do
    expected = get_field(changeset, :expected_category_slug)
    predicted = get_field(changeset, :predicted_category_slug)

    if expected && predicted do
      put_change(changeset, :is_correct, expected == predicted)
    else
      changeset
    end
  end
end
