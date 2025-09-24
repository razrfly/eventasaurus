defmodule EventasaurusWeb.GroupLive.Edit do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.Components.ImagePickerModal
  import EventasaurusWeb.TokenHelpers, only: [get_current_valid_token: 1]

  alias EventasaurusApp.Groups
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Events
  alias EventasaurusApp.Services.UploadService
  alias EventasaurusWeb.Services.SearchService

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    # Check authentication first
    case socket.assigns[:user] do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to edit groups.")
         |> redirect(to: "/auth/login")}

      user ->
        # Try to find the group
        case Groups.get_group_by_slug(slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Group not found.")
             |> redirect(to: "/groups")}

          group ->
            # Check if user can manage the group (creator or admin)
            if not Groups.can_manage?(group, user) do
              {:ok,
               socket
               |> put_flash(:error, "You don't have permission to edit this group.")
               |> redirect(to: "/groups/#{group.slug}")}
            else
              changeset = Groups.change_group(group)
              venues = Venues.list_venues()

              # Load recent locations for the user (reuse Event logic)
              recent_locations = Events.get_recent_locations_for_user(user.id, limit: 5)

              # Determine if venue is selected
              selected_venue_name =
                cond do
                  group.venue && group.venue.name -> group.venue.name
                  group.venue_name -> group.venue_name
                  true -> nil
                end

              selected_venue_address =
                cond do
                  group.venue && group.venue.address -> group.venue.address
                  group.venue_address -> group.venue_address
                  true -> nil
                end

              {:ok,
               socket
               |> assign(:user, user)
               |> assign(:group, group)
               |> assign(:page_title, "Edit #{group.name}")
               |> assign(:changeset, changeset)
               |> assign(:venues, venues)
               |> assign(:uploaded_files, [])
               # Venue/location assigns (reuse from Event)
               |> assign(:is_virtual, false)
               |> assign(:selected_venue_name, selected_venue_name)
               |> assign(:selected_venue_address, selected_venue_address)
               |> assign(:recent_locations, recent_locations)
               |> assign(:show_recent_locations, false)
               |> assign(:filtered_recent_locations, recent_locations)
               # Image picker assigns
               |> assign(:show_image_picker, false)
               |> assign(:search_query, "")
               |> assign(:search_results, %{unsplash: [], tmdb: []})
               |> assign(:loading, false)
               |> assign(:error, nil)
               |> assign(:page, 1)
               |> assign(:per_page, 20)
               |> assign(:selected_category, "general")
               |> assign(
                 :default_categories,
                 EventasaurusWeb.Services.DefaultImagesService.get_categories()
               )
               |> assign(
                 :default_images,
                 EventasaurusWeb.Services.DefaultImagesService.get_images_for_category("general")
               )
               |> assign(:supabase_access_token, get_current_valid_token(session))
               |> allow_upload(:cover_image, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1)
               |> allow_upload(:avatar, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1)}
            end
        end
    end
  end

  @impl true
  def handle_event("validate", %{"group" => group_params}, socket) do
    changeset =
      socket.assigns.group
      |> Groups.change_group(group_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"group" => group_params}, socket) do
    group = socket.assigns.group
    user = socket.assigns.user
    access_token = socket.assigns.supabase_access_token

    # Process file uploads first
    with {:ok, cover_image_url} <- handle_cover_image_upload(socket, access_token, group),
         {:ok, avatar_url} <- handle_avatar_upload(socket, access_token, group) do
      # Build updated params with uploaded image URLs
      updated_params =
        group_params
        |> maybe_put_image_url(:cover_image_url, cover_image_url || group.cover_image_url)
        |> maybe_put_image_url(:avatar_url, avatar_url || group.avatar_url)

      case Groups.update_group(group, updated_params, user.id) do
        {:ok, updated_group} ->
          {:noreply,
           socket
           |> put_flash(:info, "Group updated successfully")
           |> redirect(to: "/groups/#{updated_group.slug}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:error, error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to upload images: #{inspect(error)}")
         |> assign(:changeset, Groups.change_group(group, group_params))}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    {:noreply, redirect(socket, to: "/groups/#{socket.assigns.group.slug}")}
  end

  # ========== Image Picker Event Handlers ==========

  @impl true
  def handle_event("open_cover_image_picker", _params, socket) do
    {:noreply, assign(socket, :show_image_picker, true)}
  end

  @impl true
  def handle_event("close_image_picker", _params, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    default_images =
      EventasaurusWeb.Services.DefaultImagesService.get_images_for_category(category)

    socket =
      socket
      |> assign(:selected_category, category)
      |> assign(:default_images, default_images)
      # Clear search when switching categories
      |> assign(:search_query, "")
      # Clear search results
      |> assign(:search_results, %{unsplash: [], tmdb: []})

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "select_default_image",
        %{"image_url" => image_url, "filename" => filename, "category" => category},
        socket
      ) do
    _external_data = %{
      "id" => filename,
      "url" => image_url,
      "source" => "default",
      "category" => category,
      "metadata" => %{
        "filename" => filename,
        "category" => category,
        "title" => EventasaurusWeb.Helpers.ImageHelpers.title_from_filename(filename)
      }
    }

    # Update group with the new image
    updated_group = %{socket.assigns.group | cover_image_url: image_url}

    socket =
      socket
      |> assign(:group, updated_group)
      |> assign(:show_image_picker, false)
      |> put_flash(:info, "Cover image updated!")

    {:noreply, socket}
  end

  @impl true
  def handle_event("unified_search", %{"search_query" => query}, socket) do
    socket = assign(socket, :search_query, query)

    if String.trim(query) == "" do
      socket =
        socket
        |> assign(:search_results, %{unsplash: [], tmdb: []})
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:noreply, socket}
    else
      socket = assign(socket, :loading, true)

      # Start the search asynchronously
      send(self(), {:start_unified_search, query})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("image_selected", %{"cover_image_url" => image_url} = params, socket) do
    # Determine source and extract image data based on what's present in params
    {source, image_data} =
      cond do
        Map.has_key?(params, "unsplash_data") ->
          {"unsplash", Map.get(params, "unsplash_data", %{})}

        Map.has_key?(params, "tmdb_data") ->
          {"tmdb", Map.get(params, "tmdb_data", %{})}

        true ->
          {"unknown", %{}}
      end

    # Ensure consistent structure
    _external_data = %{
      "id" => Map.get(image_data, "id", "unknown_#{source}_#{System.unique_integer()}"),
      "url" => image_url,
      "source" => source,
      "metadata" => image_data
    }

    # Update group with the new image
    updated_group = %{socket.assigns.group | cover_image_url: image_url}

    socket =
      socket
      |> assign(:group, updated_group)
      |> assign(:show_image_picker, false)
      |> put_flash(:info, "Cover image updated!")

    {:noreply, socket}
  end

  # ========== Venue/Location Event Handlers (reuse from Event) ==========

  @impl true
  def handle_event("toggle_recent_locations", _params, socket) do
    {:noreply, assign(socket, :show_recent_locations, !socket.assigns.show_recent_locations)}
  end

  @impl true
  def handle_event("show_recent_locations", _params, socket) do
    {:noreply, assign(socket, :show_recent_locations, true)}
  end

  @impl true
  def handle_event("hide_recent_locations", _params, socket) do
    {:noreply, assign(socket, :show_recent_locations, false)}
  end

  @impl true
  def handle_event("filter_recent_locations", %{"query" => query}, socket) do
    filtered_locations =
      EventasaurusWeb.Helpers.EventHelpers.filter_locations(
        socket.assigns.recent_locations,
        query
      )

    {:noreply, assign(socket, :filtered_recent_locations, filtered_locations)}
  end

  @impl true
  def handle_event("select_recent_location", %{"location" => location_json}, socket) do
    case Jason.decode(location_json) do
      {:ok, location} ->
        venue_name = Map.get(location, "name", "")
        venue_address = Map.get(location, "address", "")

        changeset =
          socket.assigns.changeset
          |> Map.put(
            :changes,
            Map.merge(socket.assigns.changeset.changes, %{
              venue_name: venue_name,
              venue_address: venue_address,
              venue_city: Map.get(location, "city", ""),
              venue_state: Map.get(location, "state", ""),
              venue_country: Map.get(location, "country", ""),
              venue_latitude: Map.get(location, "latitude"),
              venue_longitude: Map.get(location, "longitude")
            })
          )

        socket =
          socket
          |> assign(:changeset, changeset)
          |> assign(:selected_venue_name, venue_name)
          |> assign(:selected_venue_address, venue_address)
          |> assign(:is_virtual, false)
          |> assign(:show_recent_locations, false)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("venue_selected", %{"place_details" => place_details}, socket) do
    # Extract address components
    street_address = place_details["formatted_address"] || place_details["name"] || ""

    changeset =
      socket.assigns.changeset
      |> Map.put(
        :changes,
        Map.merge(socket.assigns.changeset.changes, %{
          venue_name: place_details["name"],
          venue_address: street_address,
          venue_city: place_details["city"] || "",
          venue_state: place_details["state"] || "",
          venue_country: place_details["country"] || "",
          venue_latitude: place_details["latitude"],
          venue_longitude: place_details["longitude"]
        })
      )

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:selected_venue_name, place_details["name"])
     |> assign(:selected_venue_address, street_address)
     |> assign(:is_virtual, false)}
  end

  # ========== Supabase Image Upload Event Handlers ==========

  @impl true
  def handle_event("image_upload_error", %{"error" => error_message} = params, socket) do
    # Log the error details for debugging
    error_code = Map.get(params, "code", "")
    details = Map.get(params, "details", %{})
    timestamp = Map.get(params, "timestamp", "")

    # Log structured error data
    require Logger

    Logger.error("Image upload failed in GroupLive.Edit",
      error: error_message,
      code: error_code,
      details: details,
      timestamp: timestamp,
      group_id: socket.assigns.group.id
    )

    # Provide user-friendly error message based on error type
    user_message =
      case error_code do
        "AUTH_ERROR" ->
          "Your session has expired. Please refresh the page and try again."

        "FILE_TOO_LARGE" ->
          "The selected file is too large. Please choose a file smaller than 5MB."

        "BUCKET_NOT_FOUND" ->
          "Image storage is currently unavailable. Please try again later."

        "" ->
          cond do
            String.contains?(error_message, "Invalid Compact JWS") ->
              "Your session has expired. Please refresh the page and try again."

            String.contains?(error_message, "401") ->
              "Authentication failed. Please refresh the page and try again."

            String.contains?(error_message, "413") ->
              "The selected file is too large. Please choose a smaller file."

            true ->
              error_message
          end

        _ ->
          error_message
      end

    {:noreply, put_flash(socket, :error, "Image upload failed: #{user_message}")}
  end

  @impl true
  def handle_event("image_uploaded", %{"path" => path, "publicUrl" => public_url}, socket) do
    # Update the group with the new cover image URL
    updated_group = %{socket.assigns.group | cover_image_url: public_url}

    # Update the changeset to reflect the new image URL
    changeset = Groups.change_group(updated_group, %{"cover_image_url" => public_url})

    # Log successful upload
    require Logger

    Logger.info("Image uploaded successfully in GroupLive.Edit",
      path: path,
      public_url: public_url,
      group_id: socket.assigns.group.id
    )

    socket =
      socket
      |> assign(:group, updated_group)
      |> assign(:changeset, changeset)
      |> assign(:show_image_picker, false)
      |> put_flash(:info, "Cover image uploaded successfully!")

    {:noreply, socket}
  end

  # ========== Handle Info Implementations ==========

  @impl true
  def handle_info({:start_unified_search, query}, socket) do
    # Perform the unified search
    results = SearchService.unified_search(query)

    socket =
      socket
      |> assign(:search_results, results)
      |> assign(:loading, false)
      |> assign(:error, nil)

    {:noreply, socket}
  end

  # ========== Helper Functions ==========

  # ========== File Upload Handlers ==========

  defp handle_cover_image_upload(socket, access_token, group) do
    case uploaded_entries(socket, :cover_image) do
      {[_ | _] = _entries, []} ->
        # Delete old cover image first if it exists
        if group.cover_image_url do
          UploadService.delete_file(group.cover_image_url, access_token)
        end

        # Process new uploaded cover image
        id_prefix = "group_#{group.id}"

        results =
          UploadService.upload_liveview_files(
            socket,
            :cover_image,
            "groups",
            id_prefix,
            access_token
          )

        case results do
          {:ok, [url]} -> {:ok, url}
          {:ok, []} -> {:ok, nil}
          error -> error
        end

      {[], []} ->
        # No file uploaded, keep existing
        {:ok, nil}

      {[], errors} ->
        # Upload errors
        error_msg = Enum.map_join(errors, ", ", & &1.ref)
        {:error, "Upload errors: #{error_msg}"}
    end
  end

  defp handle_avatar_upload(socket, access_token, group) do
    case uploaded_entries(socket, :avatar) do
      {[_ | _] = _entries, []} ->
        # Delete old avatar first if it exists
        if group.avatar_url do
          UploadService.delete_file(group.avatar_url, access_token)
        end

        # Process new uploaded avatar
        id_prefix = "group_#{group.id}"

        results =
          UploadService.upload_liveview_files(
            socket,
            :avatar,
            "groups",
            id_prefix,
            access_token
          )

        case results do
          {:ok, [url]} -> {:ok, url}
          {:ok, []} -> {:ok, nil}
          error -> error
        end

      {[], []} ->
        # No file uploaded, keep existing
        {:ok, nil}

      {[], errors} ->
        # Upload errors
        error_msg = Enum.map_join(errors, ", ", & &1.ref)
        {:error, "Upload errors: #{error_msg}"}
    end
  end

  defp maybe_put_image_url(params, _key, nil), do: params

  defp maybe_put_image_url(params, key, url) when is_binary(url) do
    Map.put(params, Atom.to_string(key), url)
  end
end
