defmodule EventasaurusWeb.EventLive.New do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Storage

  @steps ["basic_info", "datetime", "venue", "image", "review"]

  @impl true
  def mount(_params, _session, socket) do
    changeset = Events.change_event(%Event{})

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:current_step, hd(@steps))
      |> assign(:steps, @steps)
      |> assign(:step_index, 0)
      |> assign(:page_title, "Create Event")
      |> assign(:venue_changeset, Venues.change_venue(%Venue{}))
      |> assign(:venues, Venues.list_venues())
      |> assign(:uploaded_image_url, nil)
      |> allow_upload(:cover_image,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    changeset =
      %Event{}
      |> Events.change_event(event_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("validate_venue", %{"venue" => venue_params}, socket) do
    changeset =
      %Venue{}
      |> Venues.change_venue(venue_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :venue_changeset, changeset)}
  end

  @impl true
  def handle_event("save_venue", %{"venue" => venue_params}, socket) do
    case Venues.create_venue(venue_params) do
      {:ok, venue} ->
        venues = socket.assigns.venues ++ [venue]

        {:noreply,
         socket
         |> assign(:venues, venues)
         |> assign(:venue_changeset, Venues.change_venue(%Venue{}))
         |> put_flash(:info, "Venue created successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :venue_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :cover_image, ref)}
  end

  @impl true
  def handle_event("save_image", _params, socket) do
    uploaded_image_url =
      consume_uploaded_entries(socket, :cover_image, fn %{path: path}, entry ->
        filename = "#{Ecto.UUID.generate()}-#{entry.client_name}"
        bucket = "event-images"

        case Storage.upload(bucket, filename, path) do
          {:ok, url} -> {:ok, url}
          {:error, _} -> {:error, :upload_failed}
        end
      end)
      |> case do
        [url] -> url
        _ -> nil
      end

    {:noreply,
     socket
     |> assign(:uploaded_image_url, uploaded_image_url)}
  end

  @impl true
  def handle_event("reset_image", _params, socket) do
    {:noreply, assign(socket, :uploaded_image_url, nil)}
  end

  @impl true
  def handle_event("save", %{"event" => event_params}, socket) do
    %{current_user: current_user} = socket.assigns
    event_params = Map.put(event_params, "cover_image_url", socket.assigns.uploaded_image_url)

    case Events.create_event(event_params) do
      {:ok, event} ->
        # Associate the current user with the event
        Events.add_user_to_event(event, current_user, "organizer")

        {:noreply,
         socket
         |> put_flash(:info, "Event created successfully")
         |> redirect(to: ~p"/events/#{event.slug}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event("next_step", _params, socket) do
    current_index = Enum.find_index(@steps, &(&1 == socket.assigns.current_step))
    next_index = current_index + 1

    if next_index < length(@steps) do
      next_step = Enum.at(@steps, next_index)

      {:noreply,
       socket
       |> assign(:current_step, next_step)
       |> assign(:step_index, next_index)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_step", _params, socket) do
    current_index = Enum.find_index(@steps, &(&1 == socket.assigns.current_step))
    prev_index = max(current_index - 1, 0)
    prev_step = Enum.at(@steps, prev_index)

    {:noreply,
     socket
     |> assign(:current_step, prev_step)
     |> assign(:step_index, prev_index)}
  end

  @impl true
  def handle_event("goto_step", %{"step" => step}, socket) do
    step_index = Enum.find_index(@steps, &(&1 == step))

    {:noreply,
     socket
     |> assign(:current_step, step)
     |> assign(:step_index, step_index)}
  end

  # Helper function to convert step keys to user-friendly titles
  defp step_title("basic_info"), do: "Basic Info"
  defp step_title("datetime"), do: "Date & Time"
  defp step_title("venue"), do: "Venue"
  defp step_title("image"), do: "Cover Image"
  defp step_title("review"), do: "Review"
  defp step_title(_), do: "Unknown Step"

  # Helper function to provide timezone options for the select input
  defp timezone_options do
    [
      {"UTC", "UTC"},
      {"US Eastern", "America/New_York"},
      {"US Central", "America/Chicago"},
      {"US Mountain", "America/Denver"},
      {"US Pacific", "America/Los_Angeles"},
      {"UK", "Europe/London"},
      {"Central European", "Europe/Berlin"},
      {"Japan", "Asia/Tokyo"},
      {"Australia Eastern", "Australia/Sydney"}
      # Add more timezone options as needed
    ]
  end

  defp error_to_string(:too_large), do: "Image is too large (max 5MB)"
  defp error_to_string(:not_accepted), do: "Invalid file type (must be .jpg, .jpeg, or .png)"
  defp error_to_string(:too_many_files), do: "You can only upload one cover image"
  defp error_to_string(_), do: "Invalid file"
end
