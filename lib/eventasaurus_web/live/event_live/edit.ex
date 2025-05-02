defmodule EventasaurusWeb.EventLive.Edit do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Storage

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    event = Events.get_event!(id)
    changeset = Events.change_event(event)

    socket =
      socket
      |> assign(:event, event)
      |> assign(:changeset, changeset)
      |> assign(:page_title, "Edit #{event.title}")
      |> assign(:venue_changeset, Venues.change_venue(%Venue{}))
      |> assign(:venues, Venues.list_venues())
      |> assign(:uploaded_image_url, event.cover_image_url)
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
      socket.assigns.event
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
        _ -> socket.assigns.event.cover_image_url
      end

    {:noreply, assign(socket, :uploaded_image_url, uploaded_image_url)}
  end

  @impl true
  def handle_event("reset_image", _params, socket) do
    {:noreply, assign(socket, :uploaded_image_url, nil)}
  end

  @impl true
  def handle_event("save", %{"event" => event_params}, socket) do
    event_params = Map.put(event_params, "cover_image_url", socket.assigns.uploaded_image_url)

    case Events.update_event(socket.assigns.event, event_params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event updated successfully")
         |> redirect(to: ~p"/events/#{event.slug}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp error_to_string(:too_large), do: "Image is too large (max 5MB)"
  defp error_to_string(:not_accepted), do: "Invalid file type (must be .jpg, .jpeg, or .png)"
  defp error_to_string(:too_many_files), do: "You can only upload one cover image"
  defp error_to_string(_), do: "Invalid file"

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
    ]
  end
end
