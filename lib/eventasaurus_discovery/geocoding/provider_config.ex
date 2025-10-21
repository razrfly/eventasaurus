defmodule EventasaurusDiscovery.Geocoding.ProviderConfig do
  @moduledoc """
  Context for managing venue data provider configuration.
  Reads provider settings from database and provides them to the geocoding system.

  Supports multi-provider operations including geocoding, images, reviews, and hours.
  """

  require Logger
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider

  @doc """
  Get active providers for geocoding system.
  Returns list of {module, opts} tuples ordered by priority.
  Shuffles providers with equal priority for random selection during testing.

  Uses priorities.geocoding from the JSONB priorities map.
  """
  def list_active_providers do
    list_active_providers_for_operation("geocoding")
  end

  @doc """
  Get active providers for a specific operation (geocoding, images, reviews, hours).
  Returns list of {module, opts} tuples ordered by operation-specific priority.
  Filters to only providers that support the operation via capabilities field.
  """
  def list_active_providers_for_operation(operation) when is_binary(operation) do
    from(p in GeocodingProvider, where: p.is_active == true)
    |> Repo.all()
    |> filter_by_capability(operation)
    |> sort_by_operation_priority(operation)
    |> group_by_priority()
    |> Enum.flat_map(&shuffle_equal_priority/1)
    |> Enum.map(&provider_to_config/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  List all providers for admin interface (including disabled).
  Ordered by geocoding priority (from priorities map) for backwards compatibility.
  """
  def list_all_providers do
    from(p in GeocodingProvider, order_by: [asc: p.name])
    |> Repo.all()
    |> Enum.sort_by(fn provider ->
      get_operation_priority(provider, "geocoding")
    end)
  end

  @doc """
  Toggle provider active/inactive status.
  """
  def toggle_active(provider_id) do
    provider = Repo.get!(GeocodingProvider, provider_id)

    provider
    |> GeocodingProvider.changeset(%{is_active: !provider.is_active})
    |> Repo.update()
  end

  @doc """
  Update rate limits for a provider.

  Merges new rate limits into existing metadata.
  """
  def update_rate_limits(provider_id, rate_limits) do
    provider = Repo.get!(GeocodingProvider, provider_id)

    # Merge rate limits into existing metadata
    metadata = provider.metadata || %{}

    updated_metadata =
      metadata
      |> Map.put("rate_limits", %{
        "per_second" => rate_limits.per_second,
        "per_minute" => rate_limits.per_minute,
        "per_hour" => rate_limits.per_hour
      })

    provider
    |> GeocodingProvider.changeset(%{metadata: updated_metadata})
    |> Repo.update()
  end

  @doc """
  Get rate limit configuration for a provider.

  Returns rate_limits map from metadata or nil if not configured.

  ## Examples

      iex> ProviderConfig.get_rate_limit("openstreetmap")
      %{"per_second" => 1, "per_minute" => 60, "per_hour" => 3600}

      iex> ProviderConfig.get_rate_limit("unknown_provider")
      nil
  """
  def get_rate_limit(provider_name) when is_binary(provider_name) do
    case Repo.get_by(GeocodingProvider, name: provider_name) do
      nil ->
        nil

      provider ->
        metadata = provider.metadata || %{}

        # Extract rate_limits from metadata (handle both string and atom keys)
        get_in(metadata, ["rate_limits"]) ||
          get_in(metadata, [:rate_limits])
    end
  end

  @doc """
  Bulk reorder providers after drag-and-drop.
  Priority map: %{provider_id => new_priority}
  Updates the geocoding priority in the priorities JSONB field.
  """
  def reorder_providers(priority_map) when is_map(priority_map) do
    Repo.transaction(fn ->
      Enum.each(priority_map, fn {provider_id, new_priority} ->
        id =
          case Integer.parse(to_string(provider_id)) do
            {i, ""} -> i
            _ -> raise ArgumentError, "invalid provider_id: #{inspect(provider_id)}"
          end

        prio =
          case Integer.parse(to_string(new_priority)) do
            {i, ""} when i > 0 and i < 100 ->
              i

            _ ->
              raise ArgumentError, "invalid priority: #{inspect(new_priority)}"
          end

        # Get the provider and update priorities map
        provider = Repo.get!(GeocodingProvider, id)
        priorities = provider.priorities || %{}
        updated_priorities = Map.put(priorities, "geocoding", prio)

        provider
        |> GeocodingProvider.changeset(%{priorities: updated_priorities})
        |> Repo.update!()
      end)
    end)
  end

  # Private functions

  # Filter providers to only those that support the given operation
  defp filter_by_capability(providers, operation) do
    Enum.filter(providers, fn provider ->
      capabilities = provider.capabilities || %{}

      # Check both string and atom keys for capability
      # If no capabilities field exists, assume "geocoding" is supported for backwards compatibility
      case capabilities do
        %{} when map_size(capabilities) == 0 ->
          operation == "geocoding"

        capabilities ->
          Map.get(capabilities, operation) == true ||
            Map.get(capabilities, String.to_atom(operation)) == true
      end
    end)
  end

  # Sort providers by operation-specific priority with fallback to legacy priority field
  # Returns list of {provider, effective_priority} tuples to preserve priority info for grouping
  defp sort_by_operation_priority(providers, operation) do
    providers
    |> Enum.map(fn provider ->
      priority = get_operation_priority(provider, operation)
      {provider, priority}
    end)
    |> Enum.sort_by(fn {_provider, priority} -> priority end)
  end

  # Get priority for a specific operation
  defp get_operation_priority(provider, operation) do
    priorities = provider.priorities || %{}

    # Try to get operation-specific priority (check both string and atom keys)
    operation_priority =
      Map.get(priorities, operation) || Map.get(priorities, String.to_atom(operation))

    # Default to 99 if operation-specific priority not found
    operation_priority || 99
  end

  defp group_by_priority(provider_tuples) do
    # Group by the effective priority value (second element of tuple)
    provider_tuples
    |> Enum.group_by(fn {_provider, priority} -> priority end)
    |> Enum.sort_by(fn {priority, _providers} -> priority end)
    |> Enum.map(fn {_priority, tuples} ->
      # Extract just the providers from the tuples
      Enum.map(tuples, fn {provider, _priority} -> provider end)
    end)
  end

  defp shuffle_equal_priority(providers) when length(providers) > 1 do
    Enum.shuffle(providers)
  end

  defp shuffle_equal_priority(providers), do: providers

  defp provider_to_config(provider) do
    module =
      provider.name
      |> String.trim()
      |> String.downcase()
      |> name_to_module()

    if Code.ensure_loaded?(module) and function_exported?(module, :geocode, 1) do
      # Get geocoding priority from priorities map
      geocoding_priority = get_operation_priority(provider, "geocoding")
      {module, [enabled: true, priority: geocoding_priority]}
    else
      Logger.warning(
        "Skipping unknown geocoding provider: #{inspect(provider.name)} -> #{inspect(module)}"
      )

      nil
    end
  end

  defp name_to_module("mapbox"), do: EventasaurusDiscovery.Geocoding.Providers.Mapbox
  defp name_to_module("here"), do: EventasaurusDiscovery.Geocoding.Providers.Here
  defp name_to_module("geoapify"), do: EventasaurusDiscovery.Geocoding.Providers.Geoapify
  defp name_to_module("locationiq"), do: EventasaurusDiscovery.Geocoding.Providers.LocationIQ

  defp name_to_module("openstreetmap"),
    do: EventasaurusDiscovery.Geocoding.Providers.OpenStreetMap

  defp name_to_module("photon"), do: EventasaurusDiscovery.Geocoding.Providers.Photon
  defp name_to_module("google_maps"), do: EventasaurusDiscovery.Geocoding.Providers.GoogleMaps

  defp name_to_module("google_places"),
    do: EventasaurusDiscovery.Geocoding.Providers.GooglePlaces

  defp name_to_module("foursquare"),
    do: EventasaurusDiscovery.Geocoding.Providers.Foursquare

  # Fallback for any future providers
  defp name_to_module(name) do
    module_name =
      name
      |> String.split("_")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("")

    Module.concat([EventasaurusDiscovery.Geocoding.Providers, module_name])
  end
end
