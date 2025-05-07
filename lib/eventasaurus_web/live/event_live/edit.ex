defmodule EventasaurusWeb.EventLive.Edit do
  use EventasaurusWeb, :live_view
  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Venues

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok,
          socket
          |> put_flash(:error, "Event not found")
          |> redirect(to: ~p"/dashboard")}

      event ->
        # First ensure we have a proper User struct
        case ensure_user_struct(socket.assigns.current_user) do
          {:ok, user} ->
            # Check if user is an organizer of this event
            if Events.user_is_organizer?(event, user) do
              # Create form_data from event
              form_data = %{
                "title" => event.title,
                "tagline" => event.tagline,
                "description" => event.description,
                "start_at" => event.start_at,
                "ends_at" => event.ends_at,
                "timezone" => event.timezone,
                "visibility" => Atom.to_string(event.visibility),
                "cover_image_url" => event.cover_image_url,
                "is_virtual" => event.venue_id == nil
              }

              # Extract date and time components for the separate fields
              form_data = if event.start_at do
                date = event.start_at |> DateTime.to_date() |> Date.to_iso8601()
                time = event.start_at
                      |> DateTime.to_time()
                      |> Time.to_iso8601()
                      |> String.slice(0, 5)  # Get HH:MM format

                form_data
                |> Map.put("start_date", date)
                |> Map.put("start_time", time)
              else
                form_data
              end

              # Extract end date and time if present
              form_data = if event.ends_at do
                date = event.ends_at |> DateTime.to_date() |> Date.to_iso8601()
                time = event.ends_at
                      |> DateTime.to_time()
                      |> Time.to_iso8601()
                      |> String.slice(0, 5)  # Get HH:MM format

                form_data
                |> Map.put("ends_date", date)
                |> Map.put("ends_time", time)
              else
                form_data
              end

              # Include venue info if there's a venue
              form_data = if event.venue do
                venue = event.venue
                form_data
                |> Map.put("venue_id", venue.id)
                |> Map.put("venue_name", venue.name)
                |> Map.put("venue_address", venue.address)
                |> Map.put("venue_city", venue.city)
                |> Map.put("venue_state", venue.state)
                |> Map.put("venue_country", venue.country)
                |> Map.put("venue_latitude", venue.latitude)
                |> Map.put("venue_longitude", venue.longitude)
              else
                form_data
              end

              changeset = Events.change_event(event)

              socket =
                socket
                |> assign(:event, event)
                |> assign(:changeset, changeset)
                |> assign(:form_data, form_data)
                |> assign(:is_virtual, event.venue_id == nil)
                |> assign(:selected_venue_name, if(event.venue, do: event.venue.name, else: nil))
                |> assign(:selected_venue_address, if(event.venue, do: event.venue.address, else: nil))
                |> assign(:venues, Venues.list_venues())

              {:ok, socket}
            else
              {:ok,
                socket
                |> put_flash(:error, "You do not have permission to edit this event")
                |> redirect(to: ~p"/events/#{slug}")}
            end
          {:error, _} ->
            {:ok,
              socket
              |> put_flash(:error, "Invalid user structure")
              |> redirect(to: ~p"/dashboard")}
        end
    end
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset =
      socket.assigns.event
      |> Events.change_event(params)
      |> Map.put(:action, :validate)

    # Update form_data with the validated params
    form_data = Map.merge(socket.assigns.form_data, params)

    socket = socket
      |> assign(:changeset, changeset)
      |> assign(:form_data, form_data)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
    # Include venue data from form_data as a fallback
    venue_data = %{
      "venue_name" => Map.get(socket.assigns.form_data, "venue_name", ""),
      "venue_address" => Map.get(socket.assigns.form_data, "venue_address", ""),
      "venue_city" => Map.get(socket.assigns.form_data, "venue_city", ""),
      "venue_state" => Map.get(socket.assigns.form_data, "venue_state", ""),
      "venue_country" => Map.get(socket.assigns.form_data, "venue_country", ""),
      "venue_latitude" => Map.get(socket.assigns.form_data, "venue_latitude"),
      "venue_longitude" => Map.get(socket.assigns.form_data, "venue_longitude")
    }

    # Ensure venue data is properly included
    event_params =
      if Map.get(event_params, "venue_name", "") == "" && venue_data["venue_name"] != "" do
        Map.merge(event_params, venue_data)
      else
        event_params
      end

    # Process venue data for the database
    event_params = process_venue_data(event_params, socket)

    # First ensure we have a proper User struct
    case ensure_user_struct(socket.assigns.current_user) do
      {:ok, user} ->
        # Check if user is an organizer of this event
        if Events.user_is_organizer?(socket.assigns.event, user) do
          # Update the event
          case Events.update_event(socket.assigns.event, event_params) do
            {:ok, updated_event} ->
              {:noreply,
                socket
                |> put_flash(:info, "Event updated successfully")
                |> redirect(to: ~p"/events/#{updated_event.slug}")}

            {:error, changeset} ->
              {:noreply, assign(socket, changeset: changeset)}
          end
        else
          {:noreply,
            socket
            |> put_flash(:error, "You do not have permission to edit this event")
            |> redirect(to: ~p"/dashboard")}
        end

      {:error, _} ->
        {:noreply,
          socket
          |> put_flash(:error, "Invalid user session")
          |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("toggle_virtual", _params, socket) do
    is_virtual = !socket.assigns.is_virtual

    # Reset selected venue if toggling to virtual
    socket =
      if is_virtual do
        socket
        |> assign(:selected_venue_name, nil)
        |> assign(:selected_venue_address, nil)
      else
        socket
      end

    # Update form_data to reflect this change
    form_data =
      socket.assigns.form_data
      |> Map.put("is_virtual", is_virtual)

    {:noreply,
      socket
      |> assign(:is_virtual, is_virtual)
      |> assign(:form_data, form_data)}
  end

  @impl true
  def handle_event("venue_selected", venue_data, socket) do
    # Extract data from venue_data with proper defaults
    name = Map.get(venue_data, "name", "") || ""
    address = Map.get(venue_data, "address", "") || ""
    city = Map.get(venue_data, "city", "") || ""
    state = Map.get(venue_data, "state", "") || ""
    country = Map.get(venue_data, "country", "") || ""
    latitude = Map.get(venue_data, "latitude") || nil
    longitude = Map.get(venue_data, "longitude") || nil

    # Update the form_data with the selected venue
    form_data = socket.assigns.form_data
    |> Map.put("venue_name", name)
    |> Map.put("venue_address", address)
    |> Map.put("venue_city", city)
    |> Map.put("venue_state", state)
    |> Map.put("venue_country", country)
    |> Map.put("venue_latitude", latitude)
    |> Map.put("venue_longitude", longitude)
    |> Map.put("is_virtual", false)

    # Update the socket with full information and the changeset
    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket = socket
    |> assign(:form_data, form_data)
    |> assign(:changeset, changeset)
    |> assign(:selected_venue_name, name)
    |> assign(:selected_venue_address, address)
    |> assign(:is_virtual, false)

    {:noreply, socket}
  end

  # Backward compatibility for older place_selected events
  @impl true
  def handle_event("place_selected", %{"details" => place_details}, socket) do
    # Extract data from place_details, handling potential structure issues
    name = Map.get(place_details, "name", "")
    address = Map.get(place_details, "formatted_address", "")

    # Extract lat/lng carefully with fallbacks
    lat = get_in(place_details, ["geometry", "location", "lat"]) || nil
    lng = get_in(place_details, ["geometry", "location", "lng"]) || nil

    # Extract address components
    components = Map.get(place_details, "address_components", [])
    city = get_address_component(components, "locality")
    state = get_address_component(components, "administrative_area_level_1")
    country = get_address_component(components, "country")

    # Update the form_data with the selected venue
    form_data = socket.assigns.form_data
    |> Map.put("venue_name", name)
    |> Map.put("venue_address", address)
    |> Map.put("venue_city", city)
    |> Map.put("venue_state", state)
    |> Map.put("venue_country", country)
    |> Map.put("venue_latitude", lat)
    |> Map.put("venue_longitude", lng)
    |> Map.put("is_virtual", false)

    # Update the changeset
    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    # Update the socket with full information
    socket = socket
    |> assign(:form_data, form_data)
    |> assign(:changeset, changeset)
    |> assign(:selected_venue_name, name)
    |> assign(:selected_venue_address, address)
    |> assign(:is_virtual, false)

    {:noreply, socket}
  end

  # Helper to extract address components
  defp get_address_component(components, type) do
    component = Enum.find(components, fn comp ->
      comp["types"] && Enum.member?(comp["types"], type)
    end)

    if component, do: component["long_name"], else: ""
  end

  # Process venue data before saving
  defp process_venue_data(params, _socket) do
    is_virtual = Map.get(params, "is_virtual", "false") == "true"

    if is_virtual do
      # For virtual venues, clear venue_id
      Map.put(params, "venue_id", nil)
    else
      # Create or find venue and link it to the event
      venue_params = %{
        name: Map.get(params, "venue_name", ""),
        address: Map.get(params, "venue_address", ""),
        city: Map.get(params, "venue_city", ""),
        state: Map.get(params, "venue_state", ""),
        country: Map.get(params, "venue_country", ""),
        latitude: Map.get(params, "venue_latitude"),
        longitude: Map.get(params, "venue_longitude")
      }

      # Only create venue if we have sufficient data
      if venue_params.name != "" && venue_params.address != "" do
        case create_or_find_venue(venue_params) do
          {:ok, venue} ->
            Map.put(params, "venue_id", venue.id)
          _ ->
            params
        end
      else
        params
      end
    end
  end

  # Create or find an existing venue
  defp create_or_find_venue(venue_params) do
    # First try to find an existing venue with the same address
    case Venues.find_venue_by_address(venue_params.address) do
      nil ->
        # If not found, create a new venue
        Venues.create_venue(venue_params)
      venue ->
        # If found, return the existing venue
        {:ok, venue}
    end
  end

  # Ensure we have a proper User struct for the current user
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => supabase_id, "email" => email, "user_metadata" => user_metadata}) do
    # Try to find existing user by Supabase ID
    case Accounts.get_user_by_supabase_id(supabase_id) do
      %Accounts.User{} = user ->
        {:ok, user}
      nil ->
        # Create new user if not found
        name = user_metadata["name"] || email |> String.split("@") |> hd()

        user_params = %{
          email: email,
          name: name,
          supabase_id: supabase_id
        }

        case Accounts.create_user(user_params) do
          {:ok, user} -> {:ok, user}
          {:error, reason} -> {:error, reason}
        end
    end
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
