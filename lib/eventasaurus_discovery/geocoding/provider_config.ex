defmodule EventasaurusDiscovery.Geocoding.ProviderConfig do
  @moduledoc """
  Context for managing geocoding provider configuration.
  Reads provider settings from database and provides them to the geocoding system.
  """

  require Logger
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider

  @doc """
  Get active providers for geocoding system.
  Returns list of {module, opts} tuples ordered by priority.
  Shuffles providers with equal priority for random selection during testing.
  """
  def list_active_providers do
    from(p in GeocodingProvider,
      where: p.is_active == true,
      order_by: [asc: p.priority]
    )
    |> Repo.all()
    |> group_by_priority()
    |> Enum.flat_map(&shuffle_equal_priority/1)
    |> Enum.map(&provider_to_config/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  List all providers for admin interface (including disabled).
  """
  def list_all_providers do
    from(p in GeocodingProvider, order_by: [asc: p.priority])
    |> Repo.all()
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
  Bulk reorder providers after drag-and-drop.
  Priority map: %{provider_id => new_priority}
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

        from(p in GeocodingProvider, where: p.id == ^id)
        |> Repo.update_all(set: [priority: prio])
      end)
    end)
  end

  # Private functions

  defp group_by_priority(providers) do
    providers
    |> Enum.group_by(& &1.priority)
    |> Enum.sort_by(fn {priority, _providers} -> priority end)
    |> Enum.map(fn {_priority, providers} -> providers end)
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
      {module, [enabled: true, priority: provider.priority]}
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
