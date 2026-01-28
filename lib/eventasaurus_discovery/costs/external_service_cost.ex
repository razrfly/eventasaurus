defmodule EventasaurusDiscovery.Costs.ExternalServiceCost do
  @moduledoc """
  Schema for tracking costs from external services.

  Provides unified cost tracking across all external services:
  - Geocoding (Google Places, Google Maps)
  - Web scraping (Crawlbase, Zyte)
  - ML inference (Hugging Face, planned)
  - LLM providers (Anthropic, OpenAI, planned)

  ## Service Types

  - `:geocoding` - Address resolution and place lookup
  - `:scraping` - Web page fetching with anti-bot bypass
  - `:ml_inference` - Machine learning model inference
  - `:llm` - Large language model API calls

  ## Usage

      alias EventasaurusDiscovery.Costs.ExternalServiceCost

      # Record a scraping cost
      ExternalServiceCost.record(%{
        service_type: "scraping",
        provider: "crawlbase",
        operation: "javascript",
        cost_usd: Decimal.new("0.002"),
        units: 2,
        unit_type: "credits",
        reference_type: "oban_job",
        reference_id: 12345,
        metadata: %{url: "https://example.com", mode: "javascript"}
      })

  ## Cost Calculation

  Costs are calculated based on provider-specific pricing:

  - **Crawlbase**: 1 credit = normal, 2 credits = JavaScript mode
  - **Zyte**: Usage-based, varies by render type
  - **Google Places**: $0.032 per text search, $0.005 per details
  - **Hugging Face**: Per 1K input/output tokens (planned)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type service_type :: :geocoding | :scraping | :ml_inference | :llm
  @type t :: %__MODULE__{}

  @service_types ~w(geocoding scraping ml_inference llm)
  @unit_types ~w(request credit input_token output_token)

  schema "external_service_costs" do
    # Service identification
    field(:service_type, :string)
    field(:provider, :string)
    field(:operation, :string)

    # Cost data
    field(:cost_usd, :decimal)
    field(:units, :integer, default: 1)
    field(:unit_type, :string)

    # Reference to source entity (polymorphic)
    field(:reference_type, :string)
    field(:reference_id, :integer)

    # Flexible metadata
    field(:metadata, :map, default: %{})

    # When the cost occurred
    field(:occurred_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating/updating external service cost records.
  """
  def changeset(cost, attrs) do
    cost
    |> cast(attrs, [
      :service_type,
      :provider,
      :operation,
      :cost_usd,
      :units,
      :unit_type,
      :reference_type,
      :reference_id,
      :metadata,
      :occurred_at
    ])
    |> validate_required([:service_type, :provider, :cost_usd])
    |> validate_inclusion(:service_type, @service_types)
    |> validate_unit_type_if_present(@unit_types)
    |> validate_number(:cost_usd, greater_than_or_equal_to: 0)
    |> validate_number(:units, greater_than: 0)
    |> put_occurred_at_if_missing()
  end

  @doc """
  Convenience function to record a cost entry.
  Returns {:ok, cost} or {:error, changeset}.

  ## Examples

      ExternalServiceCost.record(%{
        service_type: "scraping",
        provider: "crawlbase",
        operation: "javascript",
        cost_usd: Decimal.new("0.002"),
        units: 2,
        unit_type: "credits"
      })
  """
  def record(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> EventasaurusApp.Repo.insert()
  end

  @doc """
  Records a cost entry asynchronously (fire-and-forget).
  Logs errors but doesn't block the calling process.

  Useful for recording costs without impacting request latency.
  """
  def record_async(attrs) do
    Task.start(fn ->
      case record(attrs) do
        {:ok, _cost} ->
          :ok

        {:error, changeset} ->
          require Logger

          Logger.warning("Failed to record external service cost: #{inspect(changeset.errors)}",
            attrs: attrs
          )
      end
    end)

    :ok
  end

  # Private functions

  # Only validate unit_type inclusion when it's present (not nil)
  defp validate_unit_type_if_present(changeset, valid_types) do
    case get_field(changeset, :unit_type) do
      nil ->
        changeset

      _ ->
        validate_inclusion(changeset, :unit_type, valid_types,
          message: "must be one of: #{Enum.join(valid_types, ", ")}"
        )
    end
  end

  defp put_occurred_at_if_missing(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  # Helper to get valid service types
  def service_types, do: @service_types

  # Helper to get valid unit types
  def unit_types, do: @unit_types
end
