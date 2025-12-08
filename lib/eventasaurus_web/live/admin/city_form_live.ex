defmodule EventasaurusWeb.Admin.CityFormLive do
  @moduledoc """
  Admin form for creating and editing cities with auto-geocoding.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusDiscovery.Helpers.AddressGeocoder
  alias EventasaurusDiscovery.Locations.{City, Country}

  @impl true
  def mount(params, _session, socket) do
    city =
      case params["id"] do
        nil -> %City{}
        id -> Repo.get!(City, id) |> Repo.preload(:country)
      end

    changeset = City.changeset(city, %{})
    countries = get_organized_countries()

    socket =
      socket
      |> assign(:page_title, if(city.id, do: "Edit City", else: "New City"))
      |> assign(:city, city)
      |> assign(:form, to_form(changeset))
      |> assign(:countries, countries)
      |> assign(:geocoding, false)
      |> assign(:enable_discovery, false)
      # Alternate name input tracking (fixes nested form bug)
      |> assign(:new_alternate_name, "")
      # Slug editing state
      |> assign(:show_slug_editing, false)
      |> assign(:new_slug, "")
      |> assign(:slug_status, :idle)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"city" => params}, socket) do
    changeset =
      socket.assigns.city
      |> City.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("geocode", %{"name" => name, "country_id" => country_id}, socket)
      when name != "" and country_id != "" do
    country_id_int = String.to_integer(country_id)
    country = Repo.get!(Country, country_id_int)

    socket = assign(socket, :geocoding, true)

    full_address = "#{name}, #{country.name}"

    case AddressGeocoder.geocode_address(full_address) do
      {:ok, {_city, _country, {lat, lng}}} ->
        # Update the changeset with geocoded coordinates while preserving existing form data
        params = %{
          "name" => name,
          "country_id" => country_id,
          "latitude" => Decimal.new(to_string(lat)),
          "longitude" => Decimal.new(to_string(lng))
        }

        changeset =
          socket.assigns.city
          |> City.changeset(params)
          |> Map.put(:action, :validate)

        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> assign(:geocoding, false)
          |> put_flash(:info, "Successfully geocoded #{name}")

        {:noreply, socket}

      {:error, _reason} ->
        socket =
          socket
          |> assign(:geocoding, false)
          |> put_flash(:error, "Could not geocode address. Please enter coordinates manually.")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("geocode", _params, socket) do
    socket =
      socket
      |> put_flash(:error, "Please enter both city name and select a country before geocoding.")

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_discovery", _params, socket) do
    enable_discovery = !socket.assigns.enable_discovery
    {:noreply, assign(socket, :enable_discovery, enable_discovery)}
  end

  @impl true
  def handle_event("update_alternate_name_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_alternate_name, value)}
  end

  @impl true
  def handle_event("add_alternate_name", _params, socket) do
    city = socket.assigns.city
    name = socket.assigns.new_alternate_name

    case CityManager.add_alternate_name(city, name) do
      {:ok, updated_city} ->
        socket =
          socket
          |> assign(:city, updated_city |> Repo.preload(:country))
          |> assign(:new_alternate_name, "")
          |> put_flash(:info, "Alternate name \"#{name}\" added successfully")

        {:noreply, socket}

      {:error, :empty_name} ->
        {:noreply, put_flash(socket, :error, "Alternate name cannot be empty")}

      {:error, :already_exists} ->
        {:noreply, put_flash(socket, :error, "This alternate name already exists")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add alternate name")}
    end
  end

  @impl true
  def handle_event("remove_alternate_name", %{"name" => name}, socket) do
    city = socket.assigns.city

    case CityManager.remove_alternate_name(city, name) do
      {:ok, updated_city} ->
        socket =
          socket
          |> assign(:city, updated_city |> Repo.preload(:country))
          |> put_flash(:info, "Alternate name \"#{name}\" removed successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove alternate name")}
    end
  end

  # Slug editing handlers
  @impl true
  def handle_event("toggle_slug_editing", _params, socket) do
    {:noreply, assign(socket, :show_slug_editing, !socket.assigns.show_slug_editing)}
  end

  @impl true
  def handle_event("validate_slug", %{"value" => value}, socket) do
    city = socket.assigns.city
    slug = normalize_slug(value)

    status =
      cond do
        slug == "" -> :idle
        slug == city.slug -> :unchanged
        not valid_slug_format?(slug) -> :invalid_format
        CityManager.slug_available?(slug, city.id) -> :available
        true -> :taken
      end

    {:noreply, assign(socket, new_slug: slug, slug_status: status)}
  end

  @impl true
  def handle_event("update_slug", _params, socket) do
    city = socket.assigns.city
    new_slug = socket.assigns.new_slug

    case CityManager.update_city_slug(city, new_slug) do
      {:ok, updated_city} ->
        socket =
          socket
          |> assign(:city, updated_city |> Repo.preload(:country))
          |> assign(:new_slug, "")
          |> assign(:slug_status, :idle)
          |> put_flash(:info, "Slug updated successfully to \"#{new_slug}\"")

        {:noreply, socket}

      {:error, :slug_taken} ->
        {:noreply,
         socket
         |> assign(:slug_status, :taken)
         |> put_flash(:error, "This slug is already taken")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update slug")}
    end
  end

  @impl true
  def handle_event("save", %{"city" => params}, socket) do
    save_city(socket, socket.assigns.city.id, params)
  end

  defp save_city(socket, nil, params) do
    case CityManager.create_city(params) do
      {:ok, city} ->
        # Enable discovery if checkbox was checked
        result =
          if socket.assigns.enable_discovery do
            case Repo.update(City.enable_discovery_changeset(city)) do
              {:ok, updated_city} -> {:ok, updated_city}
              {:error, changeset} -> {:error, changeset}
            end
          else
            {:ok, city}
          end

        case result do
          {:ok, _city} ->
            socket =
              socket
              |> put_flash(:info, "City created successfully")
              |> push_navigate(to: ~p"/admin/cities")

            {:noreply, socket}

          {:error, _changeset} ->
            # City was created but discovery enablement failed
            # Navigate to index with warning instead of showing form error
            socket =
              socket
              |> put_flash(:error, "City created successfully, but failed to enable discovery")
              |> push_navigate(to: ~p"/admin/cities")

            {:noreply, socket}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_city(socket, _id, params) do
    case CityManager.update_city(socket.assigns.city, params) do
      {:ok, _city} ->
        socket =
          socket
          |> put_flash(:info, "City updated successfully")
          |> push_navigate(to: ~p"/admin/cities")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # Get countries organized into popular and other groups
  defp get_organized_countries do
    # Popular countries to show first (based on common event locations)
    popular_codes = ["US", "GB", "CA", "AU", "DE", "FR", "ES", "IT", "NL", "PL"]

    # Load countries from database with their IDs
    all_countries = Repo.replica().all(Country)

    # Convert to format compatible with existing code (map with id/code/name keys)
    popular =
      Enum.filter(all_countries, fn c -> c.code in popular_codes end)
      |> Enum.sort_by(fn c -> Enum.find_index(popular_codes, &(&1 == c.code)) end)
      |> Enum.map(&country_to_map/1)

    rest =
      Enum.reject(all_countries, fn c -> c.code in popular_codes end)
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&country_to_map/1)

    %{popular: popular, other: rest}
  end

  defp country_to_map(country) do
    %{
      id: country.id,
      code: country.code,
      name: country.name
    }
  end

  # Slug helper functions
  defp normalize_slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp valid_slug_format?(slug) do
    Regex.match?(~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/, slug)
  end

  # UI helper functions for slug status display
  def slug_input_class(status) do
    case status do
      :available -> "border-green-500 focus:border-green-500 focus:ring-green-500"
      :taken -> "border-red-500 focus:border-red-500 focus:ring-red-500"
      :invalid_format -> "border-red-500 focus:border-red-500 focus:ring-red-500"
      :unchanged -> "border-yellow-500 focus:border-yellow-500 focus:ring-yellow-500"
      _ -> "border-gray-300 focus:border-blue-500 focus:ring-blue-500"
    end
  end

  def slug_status_class(status) do
    case status do
      :available -> "text-green-600"
      :taken -> "text-red-600"
      :invalid_format -> "text-red-600"
      :unchanged -> "text-yellow-600"
      _ -> "text-gray-500"
    end
  end

  def slug_status_message(status, new_slug, current_slug) do
    case status do
      :idle -> "Enter a new slug (lowercase letters, numbers, and hyphens only)"
      :available -> "This slug is available"
      :taken -> "This slug is already taken by another city"
      :invalid_format -> "Invalid format: use only lowercase letters, numbers, and hyphens"
      :unchanged when new_slug == current_slug -> "This is the current slug"
      _ -> ""
    end
  end
end
