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
  def handle_event("add_alternate_name", %{"name" => name}, socket) do
    city = socket.assigns.city

    case CityManager.add_alternate_name(city, name) do
      {:ok, updated_city} ->
        socket =
          socket
          |> assign(:city, updated_city |> Repo.preload(:country))
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
    all_countries = Repo.all(Country)

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
end
