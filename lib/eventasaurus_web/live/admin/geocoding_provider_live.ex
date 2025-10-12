defmodule EventasaurusWeb.Admin.GeocodingProviderLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Geocoding.ProviderConfig

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Geocoding Providers")
      |> assign(:editing_provider_id, nil)
      |> assign(:editing_rate_limit_id, nil)
      |> assign(:validation_error, nil)
      |> load_providers()

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {provider_id, ""} ->
        case ProviderConfig.toggle_active(provider_id) do
          {:ok, _provider} ->
            {:noreply,
             socket
             |> put_flash(:info, "Provider updated successfully")
             |> load_providers()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update provider")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid provider selection")}
    end
  end

  @impl true
  def handle_event("edit_priority", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {provider_id, ""} ->
        {:noreply,
         socket
         |> assign(:editing_provider_id, provider_id)
         |> assign(:validation_error, nil)}

      _ ->
        {:noreply,
         socket
         |> assign(:editing_provider_id, nil)
         |> assign(:validation_error, "Invalid provider selection")
         |> put_flash(:error, "Invalid provider selection")}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_provider_id, nil)
     |> assign(:editing_rate_limit_id, nil)
     |> assign(:validation_error, nil)}
  end

  @impl true
  def handle_event("update_priority", %{"provider_id" => id, "priority" => priority}, socket) do
    with {provider_id, ""} <- Integer.parse(id),
         {:ok, new_priority} <- validate_priority(priority) do
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
      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, :validation_error, message)}

      _ ->
        {:noreply,
         socket
         |> assign(:validation_error, "Invalid provider selection")
         |> put_flash(:error, "Invalid provider selection")}
    end
  end

  @impl true
  def handle_event("edit_rate_limits", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {provider_id, ""} ->
        {:noreply,
         socket
         |> assign(:editing_rate_limit_id, provider_id)
         |> assign(:validation_error, nil)}

      _ ->
        {:noreply,
         socket
         |> assign(:editing_rate_limit_id, nil)
         |> assign(:validation_error, "Invalid provider selection")
         |> put_flash(:error, "Invalid provider selection")}
    end
  end

  @impl true
  def handle_event(
        "update_rate_limits",
        %{"provider_id" => id, "per_second" => per_second, "per_minute" => per_minute},
        socket
      ) do
    with {provider_id, ""} <- Integer.parse(id),
         {:ok, validated_limits} <- validate_rate_limits(per_second, per_minute) do
      case ProviderConfig.update_rate_limits(provider_id, validated_limits) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Rate limits updated successfully")
           |> assign(:editing_rate_limit_id, nil)
           |> assign(:validation_error, nil)
           |> load_providers()}

        {:error, _} ->
          {:noreply,
           socket
           |> assign(:validation_error, "Failed to update rate limits")
           |> put_flash(:error, "Failed to update rate limits")}
      end
    else
      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, :validation_error, message)}

      _ ->
        {:noreply,
         socket
         |> assign(:validation_error, "Invalid input")
         |> put_flash(:error, "Invalid input")}
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

  defp validate_rate_limits(per_second, per_minute) do
    with {:ok, ps} <- parse_rate_limit(per_second, "per_second"),
         {:ok, pm} <- parse_rate_limit(per_minute, "per_minute") do
      cond do
        ps < 1 ->
          {:error, "Per second must be at least 1"}

        pm < ps ->
          {:error, "Per minute must be >= per second (#{ps})"}

        true ->
          # Calculate per_hour as per_minute × 60
          {:ok, %{per_second: ps, per_minute: pm, per_hour: pm * 60}}
      end
    end
  end

  defp parse_rate_limit(value, field_name) when is_binary(value) do
    case Integer.parse(value) do
      {val, ""} when val > 0 ->
        {:ok, val}

      {val, ""} ->
        {:error, "#{field_name} must be positive (got #{val})"}

      _ ->
        {:error, "#{field_name} must be a valid number"}
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
