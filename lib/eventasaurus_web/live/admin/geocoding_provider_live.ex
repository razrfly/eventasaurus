defmodule EventasaurusWeb.Admin.GeocodingProviderLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Geocoding.ProviderConfig

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Geocoding Providers")
      |> load_providers()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    case ProviderConfig.toggle_active(String.to_integer(id)) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider updated")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update provider")}
    end
  end

  @impl true
  def handle_event("set_priority", %{"id" => id, "priority" => priority}, socket) do
    provider_id = String.to_integer(id)
    new_priority = String.to_integer(priority)

    case ProviderConfig.reorder_providers(%{provider_id => new_priority}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Priority updated")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update priority")}
    end
  end

  defp load_providers(socket) do
    providers = ProviderConfig.list_all_providers()
    assign(socket, :providers, providers)
  end

  # Display name helper
  @display_names %{
    "here" => "HERE",
    "openstreetmap" => "OpenStreetMap",
    "locationiq" => "LocationIQ",
    "geoapify" => "Geoapify",
    "mapbox" => "Mapbox",
    "photon" => "Photon",
    "google_maps" => "Google Maps",
    "google_places" => "Google Places"
  }

  defp display_name(name) do
    Map.get(@display_names, name, String.capitalize(name))
  end
end
