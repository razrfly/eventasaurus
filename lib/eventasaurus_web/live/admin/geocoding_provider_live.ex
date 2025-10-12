defmodule EventasaurusWeb.Admin.GeocodingProviderLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Geocoding.ProviderConfig

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Geocoding Providers")
      |> assign(:editing_provider_id, nil)
      |> assign(:validation_error, nil)
      |> load_providers()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    case ProviderConfig.toggle_active(String.to_integer(id)) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider updated successfully")
         |> load_providers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update provider")}
    end
  end

  @impl true
  def handle_event("edit_priority", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:editing_provider_id, String.to_integer(id))
     |> assign(:validation_error, nil)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_provider_id, nil)
     |> assign(:validation_error, nil)}
  end

  @impl true
  def handle_event("update_priority", %{"provider_id" => id, "priority" => priority}, socket) do
    provider_id = String.to_integer(id)

    with {:ok, new_priority} <- validate_priority(priority) do
      case ProviderConfig.reorder_providers(%{provider_id => new_priority}) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Priority updated successfully")
           |> assign(:editing_provider_id, nil)
           |> assign(:validation_error, nil)
           |> load_providers()}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:validation_error, "Failed to update priority")
           |> put_flash(:error, "Failed to update priority")}
      end
    else
      {:error, message} ->
        {:noreply, assign(socket, :validation_error, message)}
    end
  end

  defp validate_priority(priority) when is_binary(priority) do
    case Integer.parse(priority) do
      {val, ""} when val >= 1 and val <= 99 ->
        {:ok, val}

      {val, ""} ->
        {:error, "Priority must be between 1 and 99 (got #{val})"}

      _ ->
        {:error, "Priority must be a valid number"}
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
