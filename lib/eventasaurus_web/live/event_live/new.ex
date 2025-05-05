defmodule EventasaurusWeb.EventLive.New do
  use EventasaurusWeb, :live_view
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues

  @steps [:basic_info, :date_time, :venue, :details, :confirmation]

  @impl true
  def mount(_params, _session, socket) do
    changeset = Events.change_event(%Event{})

    # Try to safely access the venues or provide an empty list if the module isn't available yet
    venues = try do
      Venues.list_venues()
    rescue
      _ -> []
    end

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:current_step, :basic_info)
      |> assign(:steps, @steps)
      |> assign(:form_data, %{})
      |> assign(:venues, venues)

    {:ok, socket}
  end

  @impl true
  def handle_event("next_step", %{"event" => event_params}, socket) do
    current_step = socket.assigns.current_step
    current_step_index = Enum.find_index(socket.assigns.steps, fn step -> step == current_step end)
    next_step = Enum.at(socket.assigns.steps, current_step_index + 1)

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

  # Helper functions to determine which fields to validate for each step
  defp get_fields_for_step(:basic_info), do: [:title, :tagline, :description, :visibility]
  defp get_fields_for_step(:date_time), do: [:start_at, :ends_at, :timezone]
  defp get_fields_for_step(:venue), do: [:venue_id]
  defp get_fields_for_step(:details), do: [:cover_image_url, :slug]
  defp get_fields_for_step(:confirmation), do: []

  # Helper function to get errors for a specific field
  defp get_error(changeset, field) do
    Keyword.get(changeset.errors, field)
  end
end
