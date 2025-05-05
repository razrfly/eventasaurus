defmodule EventasaurusWeb.EventLive.New do
  use EventasaurusWeb, :live_view
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Venues.Venue

  @steps [:basic_info, :date_time, :venue, :details, :confirmation]

  @impl true
  def mount(_params, _session, socket) do
    changeset = Events.change_event(%Event{})

    # Create a simple script that triggers the global loader
    script = Phoenix.HTML.raw("""
    <script>
      if (window.loadGoogleMapsAPI) {
        window.loadGoogleMapsAPI();
      } else {
        console.log("Google Maps loader not found. Maps features may not work correctly.");
      }
    </script>
    """)

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:current_step, :basic_info)
      |> assign(:steps, @steps)
      |> assign(:form_data, %{})
      |> assign(:is_virtual, false)
      |> assign(:selected_venue_name, nil)
      |> assign(:selected_venue_address, nil)
      |> assign(:scripts, script)
      |> assign(:venues, Venues.list_venues())

    {:ok, socket}
  end

  @impl true
  def handle_event("next_step", %{"event" => event_params}, socket) do
    current_step = socket.assigns.current_step
    current_step_index = Enum.find_index(socket.assigns.steps, fn step -> step == current_step end)
    next_step = Enum.at(socket.assigns.steps, current_step_index + 1)

    # Process venue data if this is the venue step
    event_params = process_venue_data(current_step, event_params, socket)

    # Merge the form data with the existing form data
    updated_form_data = Map.merge(socket.assigns.form_data, event_params)

    # Validate the current step
    changeset = Event.changeset(%Event{}, updated_form_data)

    # Get the fields for the current step
    fields_for_validation = get_fields_for_step(current_step)

    # Check if the current step is valid
    step_valid? = Enum.all?(fields_for_validation, fn field ->
      is_nil(get_error(changeset, field))
    end)

    socket =
      if step_valid? do
        socket
        |> assign(:form_data, updated_form_data)
        |> assign(:current_step, next_step)
      else
        socket
        |> assign(:changeset, Map.put(changeset, :action, :validate))
        |> put_flash(:error, "Please fix the errors before continuing")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("prev_step", _params, socket) do
    current_step = socket.assigns.current_step
    current_step_index = Enum.find_index(socket.assigns.steps, fn step -> step == current_step end)
    prev_step = Enum.at(socket.assigns.steps, current_step_index - 1)

    {:noreply, assign(socket, :current_step, prev_step)}
  end

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
    # Process venue data if needed
    event_params = process_venue_data(:confirmation, event_params, socket)

    # Merge all form data
    complete_params = Map.merge(socket.assigns.form_data, event_params)

    # Create the event
    case Events.create_event_with_organizer(complete_params, socket.assigns.current_user) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event created successfully")
         |> redirect(to: ~p"/events/#{event.slug}")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset =
      %Event{}
      |> Events.change_event(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("go_to_step", %{"step" => step}, socket) do
    # Only allow navigation to completed steps or the current step
    requested_step = String.to_existing_atom(step)
    current_step_index = Enum.find_index(@steps, &(&1 == socket.assigns.current_step))
    requested_step_index = Enum.find_index(@steps, &(&1 == requested_step))

    # Only allow going to steps that have been reached before
    socket =
      if requested_step_index <= current_step_index do
        assign(socket, :current_step, requested_step)
      else
        socket
      end

    {:noreply, socket}
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

    {:noreply, assign(socket, :is_virtual, is_virtual)}
  end

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

    # Update the socket
    {:noreply, socket
              |> assign(:form_data, form_data)
              |> assign(:selected_venue_name, name)
              |> assign(:selected_venue_address, address)}
  end

  # Helper to extract address components
  defp get_address_component(components, type) do
    component = Enum.find(components, fn comp ->
      comp["types"] && Enum.member?(comp["types"], type)
    end)

    if component, do: component["long_name"], else: ""
  end

  # Helper functions to determine which fields to validate for each step
  defp get_fields_for_step(:basic_info), do: [:title, :tagline, :description, :visibility]
  defp get_fields_for_step(:date_time), do: [:start_at, :ends_at, :timezone]

  defp get_fields_for_step(:venue) do
    if assigns = %{assigns: %{is_virtual: is_virtual}} = __ENV__.context_modules,
      do: (if is_virtual, do: [:virtual_venue_url], else: []),
      else: []
  end

  defp get_fields_for_step(:details), do: [:cover_image_url, :slug]
  defp get_fields_for_step(:confirmation), do: []

  # Helper function to get errors for a specific field
  defp get_error(changeset, field) do
    Keyword.get(changeset.errors, field)
  end

  # Process venue data before saving
  defp process_venue_data(:venue, params, socket) do
    is_virtual = Map.get(params, "is_virtual", "false") == "true"

    # Update the is_virtual in the socket
    send(self(), {:update_is_virtual, is_virtual})

    if is_virtual do
      # For virtual venues, no further processing needed
      params
    else
      # For physical venues, pass through the params
      params
    end
  end

  defp process_venue_data(:confirmation, params, socket) do
    is_virtual = Map.get(socket.assigns.form_data, "is_virtual", false) ||
                Map.get(params, "is_virtual", "false") == "true"

    if is_virtual do
      # For virtual venues, mark it as virtual in the system
      Map.put(params, "is_virtual", true)
    else
      # Create or find venue and link it to the event
      venue_params = %{
        name: Map.get(socket.assigns.form_data, "venue_name", ""),
        address: Map.get(socket.assigns.form_data, "venue_address", ""),
        city: Map.get(socket.assigns.form_data, "venue_city", ""),
        state: Map.get(socket.assigns.form_data, "venue_state", ""),
        country: Map.get(socket.assigns.form_data, "venue_country", ""),
        latitude: Map.get(socket.assigns.form_data, "venue_latitude"),
        longitude: Map.get(socket.assigns.form_data, "venue_longitude")
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

  defp process_venue_data(_step, params, _socket), do: params

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

  @impl true
  def handle_info({:update_is_virtual, is_virtual}, socket) do
    {:noreply, assign(socket, :is_virtual, is_virtual)}
  end
end
