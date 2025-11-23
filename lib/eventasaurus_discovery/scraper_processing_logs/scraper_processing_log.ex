defmodule EventasaurusDiscovery.ScraperProcessingLogs.ScraperProcessingLog do
  @moduledoc """
  Schema for tracking scraper processing outcomes.

  Tracks all processing attempts (success and failure) across all scrapers
  with flexible metadata and error categorization.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "scraper_processing_logs" do
    # Source tracking
    field(:source_id, :integer)
    field(:source_name, :string)

    # Oban job link for debugging
    field(:job_id, :integer)

    # Outcome
    field(:status, :string)

    # Error tracking
    field(:error_type, :string)
    field(:error_message, :string)

    # Flexible metadata
    field(:metadata, :map, default: %{})

    # Timestamps
    field(:processed_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(scraper_processing_log, attrs) do
    scraper_processing_log
    |> cast(attrs, [
      :source_id,
      :source_name,
      :job_id,
      :status,
      :error_type,
      :error_message,
      :metadata,
      :processed_at
    ])
    |> validate_required([:source_id, :source_name, :status])
    |> validate_inclusion(:status, ["success", "failure"])
    |> validate_error_fields()
  end

  # Validate that failure status includes error fields
  defp validate_error_fields(changeset) do
    status = get_field(changeset, :status)

    if status == "failure" do
      changeset
      |> validate_required([:error_type], message: "is required for failure status")
    else
      changeset
    end
  end
end
