defmodule EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider do
  @moduledoc """
  Schema for venue data provider configuration.

  Stores provider configuration including:
  - name: Provider identifier (e.g., "mapbox", "openstreetmap", "google_places")
  - is_active: Whether provider is enabled
  - metadata: JSONB field containing rate limits and other config
  - capabilities: JSONB field indicating provider capabilities (geocoding, images, reviews, hours)
  - priorities: JSONB field with operation-specific priorities (geocoding, images, etc.)

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

  ## Capabilities Structure

  ```json
  {
    "geocoding": true,
    "images": true,
    "reviews": false,
    "hours": false
  }
  ```

  ## Priorities Structure

  ```json
  {
    "geocoding": 1,
    "images": 8
  }
  ```
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "venue_data_providers" do
    field(:name, :string)
    field(:is_active, :boolean, default: true)
    field(:metadata, :map, default: %{})
    field(:capabilities, :map, default: %{})
    field(:priorities, :map, default: %{})

    timestamps()
  end

  @doc false
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :is_active, :metadata, :capabilities, :priorities])
    |> validate_required([:name])
    |> validate_metadata()
    |> validate_capabilities()
    |> validate_priorities()
    |> unique_constraint(:name)
  end

  defp validate_capabilities(changeset) do
    changeset
    |> validate_change(:capabilities, fn :capabilities, capabilities ->
      capabilities = capabilities || %{}

      if is_map(capabilities) do
        valid_keys = ["geocoding", "images", "reviews", "hours"]
        invalid_keys = Map.keys(capabilities) -- valid_keys

        if Enum.empty?(invalid_keys) do
          []
        else
          [capabilities: "contains invalid keys: #{Enum.join(invalid_keys, ", ")}"]
        end
      else
        [capabilities: "must be a map"]
      end
    end)
  end

  defp validate_priorities(changeset) do
    changeset
    |> validate_change(:priorities, fn :priorities, priorities ->
      priorities = priorities || %{}

      if is_map(priorities) do
        # All values should be positive integers representing priority order
        invalid_priorities =
          Enum.filter(priorities, fn {_key, value} ->
            not (is_integer(value) and value > 0)
          end)

        if Enum.empty?(invalid_priorities) do
          []
        else
          invalid_keys = Enum.map(invalid_priorities, fn {key, _} -> key end)

          [
            priorities:
              "contains invalid priority values for: #{Enum.join(invalid_keys, ", ")} (must be positive integers)"
          ]
        end
      else
        [priorities: "must be a map"]
      end
    end)
  end

  defp validate_metadata(changeset) do
    changeset
    |> validate_change(:metadata, fn :metadata, metadata ->
      metadata = metadata || %{}

      # Validate rate_limits structure if present
      case get_in(metadata, ["rate_limits"]) || get_in(metadata, [:rate_limits]) do
        nil ->
          []

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
    errors =
      case rate_limits["per_second"] || rate_limits[:per_second] do
        nil -> errors
        val when is_integer(val) and val > 0 -> errors
        _ -> [{:metadata, "rate_limits.per_second must be a positive integer"} | errors]
      end

    # Validate per_minute
    errors =
      case rate_limits["per_minute"] || rate_limits[:per_minute] do
        nil -> errors
        val when is_integer(val) and val > 0 -> errors
        _ -> [{:metadata, "rate_limits.per_minute must be a positive integer"} | errors]
      end

    # Validate per_hour
    errors =
      case rate_limits["per_hour"] || rate_limits[:per_hour] do
        nil -> errors
        val when is_integer(val) and val > 0 -> errors
        _ -> [{:metadata, "rate_limits.per_hour must be a positive integer"} | errors]
      end

    errors
  end
end
