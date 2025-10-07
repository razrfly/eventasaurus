defmodule EventasaurusWeb.Admin.CityDiscoveryConfigLive do
  @moduledoc """
  Admin page for configuring automated discovery for individual cities.
  Allows managing sources, settings, and viewing statistics.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Locations.City.DiscoveryConfig
  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager

  import Ecto.Query
  require Logger

  @impl true
  def mount(%{"slug" => city_slug}, _session, socket) do
    city = Repo.get_by!(City, slug: city_slug) |> Repo.preload(:country)

    socket =
      socket
      |> assign(:page_title, "Configure #{city.name}")
      |> assign(:city, city)
      |> assign(:available_sources, DiscoveryConfig.valid_source_names())
      |> assign(:show_add_source_modal, false)
      |> assign(:selected_source, nil)
      |> assign(:source_settings, %{})
      |> assign(:editing_source, false)

    {:ok, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    cities = Repo.all(from c in City, order_by: c.name, preload: :country)

    socket =
      socket
      |> assign(:page_title, "City Discovery Configuration")
      |> assign(:cities, cities)
      |> assign(:selected_city, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("enable_discovery", %{"city_id" => city_id}, socket) do
    city_id = String.to_integer(city_id)

    case DiscoveryConfigManager.enable_city(city_id) do
      {:ok, _city} ->
        city = Repo.get!(City, city_id) |> Repo.preload(:country)

        socket =
          socket
          |> put_flash(:info, "Discovery enabled for #{city.name}")
          |> assign(:city, city)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enable discovery: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("disable_discovery", %{"city_id" => city_id}, socket) do
    city_id = String.to_integer(city_id)

    case DiscoveryConfigManager.disable_city(city_id) do
      {:ok, _city} ->
        city = Repo.get!(City, city_id) |> Repo.preload(:country)

        socket =
          socket
          |> put_flash(:info, "Discovery disabled for #{city.name}")
          |> assign(:city, city)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disable discovery: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("show_add_source", _params, socket) do
    {:noreply, assign(socket, :show_add_source_modal, true)}
  end

  @impl true
  def handle_event("hide_add_source", _params, socket) do
    socket =
      socket
      |> assign(:show_add_source_modal, false)
      |> assign(:selected_source, nil)
      |> assign(:source_settings, %{})
      |> assign(:editing_source, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("form_change", params, socket) do
    source = params["source"]
    editing = socket.assigns.editing_source

    socket = if !editing and source != "" and source != socket.assigns.selected_source do
      # Switching to a new source - load default settings
      default_settings = get_default_settings(source)
      socket
      |> assign(:selected_source, source)
      |> assign(:source_settings, default_settings)
    else
      # Update settings from form (either editing existing source or updating new source settings)
      updated_settings = Enum.reduce(params, socket.assigns.source_settings, fn
        {"setting_" <> key, value}, acc ->
          Map.put(acc, key, parse_setting_value(value))
        _, acc ->
          acc
      end)

      assign(socket, :source_settings, updated_settings)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("add_source", %{"city_id" => city_id}, socket) do
    city_id = String.to_integer(city_id)
    source_name = socket.assigns.selected_source
    settings = socket.assigns.source_settings
    editing = socket.assigns.editing_source

    result = if editing do
      DiscoveryConfigManager.update_source_settings(city_id, source_name, settings)
    else
      DiscoveryConfigManager.enable_source(city_id, source_name, settings)
    end

    case result do
      {:ok, _city} ->
        city = Repo.get!(City, city_id) |> Repo.preload(:country)
        action = if editing, do: "updated", else: "added"

        socket =
          socket
          |> put_flash(:info, "Successfully #{action} #{source_name} source")
          |> assign(:city, city)
          |> assign(:show_add_source_modal, false)
          |> assign(:selected_source, nil)
          |> assign(:source_settings, %{})
          |> assign(:editing_source, false)

        {:noreply, socket}

      {:error, reason} ->
        action = if editing, do: "update", else: "add"
        {:noreply, put_flash(socket, :error, "Failed to #{action} source: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("show_edit_source", %{"source" => source_name}, socket) do
    city = socket.assigns.city
    config = city.discovery_config || %{}
    sources = config["sources"] || []
    source = Enum.find(sources, &(&1["name"] == source_name))

    if source do
      settings = source["settings"] || %{}

      socket =
        socket
        |> assign(:show_add_source_modal, true)
        |> assign(:selected_source, source_name)
        |> assign(:source_settings, settings)
        |> assign(:editing_source, true)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Source not found")}
    end
  end

  @impl true
  def handle_event("toggle_source", %{"city_id" => city_id, "source" => source_name}, socket) do
    city_id = String.to_integer(city_id)

    # Reload city from database to get fresh data
    city = Repo.get!(City, city_id) |> Repo.preload(:country)
    config = city.discovery_config || %{}
    sources = config["sources"] || []
    source = Enum.find(sources, &(&1["name"] == source_name))

    result =
      if source && source["enabled"] do
        DiscoveryConfigManager.disable_source(city_id, source_name)
      else
        # Re-enable with existing settings
        settings = (source && source["settings"]) || %{}
        DiscoveryConfigManager.enable_source(city_id, source_name, settings)
      end

    case result do
      {:ok, _city} ->
        city = Repo.get!(City, city_id) |> Repo.preload(:country)
        action = if source && source["enabled"], do: "disabled", else: "enabled"

        socket =
          socket
          |> put_flash(:info, "Source #{source_name} #{action}")
          |> assign(:city, city)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle source: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_source", %{"city_id" => city_id, "source" => source_name}, socket) do
    city_id = String.to_integer(city_id)

    case DiscoveryConfigManager.delete_source(city_id, source_name) do
      {:ok, _city} ->
        city = Repo.get!(City, city_id) |> Repo.preload(:country)

        socket =
          socket
          |> put_flash(:info, "Successfully deleted #{source_name} source")
          |> assign(:city, city)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete source: #{inspect(reason)}")}
    end
  end

  defp get_default_settings("bandsintown"), do: %{"limit" => 100, "radius" => 50}
  defp get_default_settings("ticketmaster"), do: %{"limit" => 100, "radius" => 50}
  defp get_default_settings("resident-advisor"), do: %{"limit" => 100}
  defp get_default_settings("karnet"), do: %{"limit" => 100, "max_pages" => 10}
  defp get_default_settings("kino-krakow"), do: %{"limit" => 100, "max_pages" => 10}
  defp get_default_settings("cinema-city"), do: %{"limit" => 100}
  defp get_default_settings(_), do: %{"limit" => 100}

  defp parse_setting_value(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> value
    end
  end

  defp format_datetime(nil), do: "Never"

  defp format_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %Y %I:%M %p")
      _ -> "Invalid date"
    end
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %I:%M %p")
  end

  defp source_icon("bandsintown"), do: "🎵"
  defp source_icon("ticketmaster"), do: "🎫"
  defp source_icon("resident-advisor"), do: "🎧"
  defp source_icon("karnet"), do: "🎭"
  defp source_icon("kino-krakow"), do: "🎬"
  defp source_icon("cinema-city"), do: "🍿"
  defp source_icon(_), do: "📅"
end
