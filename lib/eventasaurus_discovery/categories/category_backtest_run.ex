defmodule EventasaurusDiscovery.Categories.CategoryBacktestRun do
  @moduledoc """
  Ecto schema for ML category classification backtest runs.

  A backtest run evaluates ML predictions against existing DB mappings
  to measure accuracy before production integration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EventasaurusDiscovery.Categories.CategoryBacktestResult

  @type status :: :pending | :running | :completed | :failed

  schema "category_backtest_runs" do
    # Run identification
    field :name, :string

    # Model configuration
    field :model_name, :string, default: "facebook/bart-large-mnli"
    field :candidate_labels, :map
    field :threshold, :float, default: 0.5

    # Sample configuration
    field :sample_size, :integer
    field :source_filter, :string

    # Results summary
    field :accuracy, :float
    field :precision_macro, :float
    field :recall_macro, :float
    field :f1_macro, :float

    # Execution status
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :error_message, :string

    # Additional metadata
    field :metadata, :map, default: %{}

    # Associations
    has_many :results, CategoryBacktestResult, foreign_key: :backtest_run_id

    timestamps()
  end

  @required_fields [:name, :candidate_labels, :sample_size]
  @optional_fields [
    :model_name,
    :threshold,
    :source_filter,
    :accuracy,
    :precision_macro,
    :recall_macro,
    :f1_macro,
    :status,
    :started_at,
    :completed_at,
    :error_message,
    :metadata
  ]

  @valid_statuses ["pending", "running", "completed", "failed"]

  @doc """
  Creates a changeset for a new backtest run.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:threshold, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:sample_size, greater_than: 0)
  end

  @doc """
  Creates a changeset for starting a backtest run.
  """
  @spec start_changeset(%__MODULE__{}) :: Ecto.Changeset.t()
  def start_changeset(run) do
    run
    |> change(%{status: "running", started_at: DateTime.utc_now()})
  end

  @doc """
  Creates a changeset for completing a backtest run with results.
  """
  @spec complete_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def complete_changeset(run, metrics) do
    run
    |> change(%{
      status: "completed",
      completed_at: DateTime.utc_now(),
      accuracy: metrics[:accuracy],
      precision_macro: metrics[:precision_macro],
      recall_macro: metrics[:recall_macro],
      f1_macro: metrics[:f1_macro]
    })
  end

  @doc """
  Creates a changeset for failing a backtest run.
  """
  @spec fail_changeset(%__MODULE__{}, String.t()) :: Ecto.Changeset.t()
  def fail_changeset(run, error_message) do
    run
    |> change(%{
      status: "failed",
      completed_at: DateTime.utc_now(),
      error_message: error_message
    })
  end

  @doc """
  Returns true if the run is in a terminal state.
  """
  @spec finished?(%__MODULE__{}) :: boolean()
  def finished?(%__MODULE__{status: status}) do
    status in ["completed", "failed"]
  end

  @doc """
  Calculates the duration of the run in milliseconds.
  """
  @spec duration_ms(%__MODULE__{}) :: integer() | nil
  def duration_ms(%__MODULE__{started_at: nil}), do: nil
  def duration_ms(%__MODULE__{completed_at: nil}), do: nil

  def duration_ms(%__MODULE__{started_at: started, completed_at: completed}) do
    DateTime.diff(completed, started, :millisecond)
  end
end
