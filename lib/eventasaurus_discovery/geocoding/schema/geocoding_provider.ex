defmodule EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider do
  @moduledoc """
  Schema for geocoding provider configuration.

  Stores provider configuration including:
  - name: Provider identifier (e.g., "mapbox", "openstreetmap")
  - priority: Lower = higher priority (1 is highest)
  - is_active: Whether provider is enabled
  - metadata: JSONB field containing rate limits and other config

  ## Metadata Structure

  ```json
  {
    "rate_limits": {
      "per_second": 10,
      "per_minute": 600,
      "per_hour": 36000
    },
    "timeout_ms": 5000
  }
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "geocoding_providers" do
    field :name, :string
    field :priority, :integer
    field :is_active, :boolean, default: true
    field :metadata, :map, default: %{}

    timestamps()
  end

  @doc false
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :priority, :is_active, :metadata])
    |> validate_required([:name, :priority])
    |> validate_number(:priority, greater_than: 0, less_than: 100)
    |> validate_metadata()
    |> unique_constraint(:name)
  end

  defp validate_metadata(changeset) do
    changeset
    |> validate_change(:metadata, fn :metadata, metadata ->
      metadata = metadata || %{}

      # Validate rate_limits structure if present
      case get_in(metadata, ["rate_limits"]) || get_in(metadata, [:rate_limits]) do
        nil -> []
        rate_limits when is_map(rate_limits) ->
          validate_rate_limits(rate_limits)
        _ ->
          [metadata: "rate_limits must be a map"]
      end
    end)
  end

  defp validate_rate_limits(rate_limits) do
    errors = []

    # Validate per_second
    errors = case rate_limits["per_second"] || rate_limits[:per_second] do
      nil -> errors
      val when is_integer(val) and val > 0 -> errors
      _ -> [{:metadata, "rate_limits.per_second must be a positive integer"} | errors]
    end

    # Validate per_minute
    errors = case rate_limits["per_minute"] || rate_limits[:per_minute] do
      nil -> errors
      val when is_integer(val) and val > 0 -> errors
      _ -> [{:metadata, "rate_limits.per_minute must be a positive integer"} | errors]
    end

    # Validate per_hour
    errors = case rate_limits["per_hour"] || rate_limits[:per_hour] do
      nil -> errors
      val when is_integer(val) and val > 0 -> errors
      _ -> [{:metadata, "rate_limits.per_hour must be a positive integer"} | errors]
    end

    errors
  end
end
