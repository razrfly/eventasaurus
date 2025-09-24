defmodule EventasaurusWeb.GroupLive.New do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.Components.ImagePickerModal

  alias EventasaurusApp.Groups
  alias EventasaurusApp.Groups.Group
  alias EventasaurusApp.Events
  alias EventasaurusApp.Services.UploadService
  alias EventasaurusWeb.Services.SearchService

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns[:user]

    if user do
      changeset = Groups.change_group(%Group{})

      # Load recent locations for the user (reuse Event logic)
      recent_locations = Events.get_recent_locations_for_user(user.id, limit: 5)

      {:ok,
       socket
       |> assign(:user, user)
       |> assign(:page_title, "Create Group")
       |> assign(:changeset, changeset)
       |> assign(:uploaded_files, [])
       |> assign(:cover_image_url, nil)
       # Venue/location assigns (reuse from Event)
       |> assign(:is_virtual, false)
       |> assign(:selected_venue_name, nil)
       |> assign(:selected_venue_address, nil)
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
       |> assign(:supabase_access_token, session["access_token"])
       |> allow_upload(:cover_image, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1)
       |> allow_upload(:avatar, accept: ~w(.jpg .jpeg .png .gif), max_entries: 1)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to create a group.")
       |> redirect(to: "/auth/login")}
    end
  end

  @impl true
  def handle_event("validate", %{"group" => group_params}, socket) do
    changeset =
      %Group{}
      |> Groups.change_group(group_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"group" => group_params}, socket) do
    user = socket.assigns.user
    access_token = socket.assigns.supabase_access_token

    # Process file uploads first
    with {:ok, cover_image_url} <- handle_cover_image_upload(socket, access_token),
         {:ok, avatar_url} <- handle_avatar_upload(socket, access_token) do
      # Build updated params with uploaded image URLs
      updated_params =
        group_params
        |> maybe_put_image_url(
          :cover_image_url,
          cover_image_url || socket.assigns.cover_image_url
        )
        |> maybe_put_image_url(:avatar_url, avatar_url)

      case Groups.create_group_with_creator(updated_params, user) do
        {:ok, group} ->
          {:noreply,
           socket
           |> put_flash(:info, "Group created successfully")
           |> redirect(to: "/groups/#{group.slug}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:error, error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to upload images: #{inspect(error)}")
         |> assign(:changeset, Groups.change_group(%Group{}, group_params))}
    end
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

    socket =
      socket
      |> assign(:cover_image_url, image_url)
      |> assign(:show_image_picker, false)
      |> put_flash(:info, "Cover image selected!")

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

    socket =
      socket
      |> assign(:cover_image_url, image_url)
      |> assign(:show_image_picker, false)
      |> put_flash(:info, "Cover image selected!")

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

  # ========== File Upload Handlers ==========

  defp handle_cover_image_upload(socket, access_token) do
    case uploaded_entries(socket, :cover_image) do
      {[_ | _] = _entries, []} ->
        # Process uploaded cover image
        results =
          UploadService.upload_liveview_files(
            socket,
            :cover_image,
            "groups",
            "group_new",
            access_token
          )

        case results do
          {:ok, [url]} -> {:ok, url}
          {:ok, []} -> {:ok, nil}
          error -> error
        end

      {[], []} ->
        # No file uploaded
        {:ok, nil}

      {[], errors} ->
        # Upload errors
        error_msg = Enum.map_join(errors, ", ", & &1.ref)
        {:error, "Upload errors: #{error_msg}"}
    end
  end

  defp handle_avatar_upload(socket, access_token) do
    case uploaded_entries(socket, :avatar) do
      {[_ | _] = _entries, []} ->
        # Process uploaded avatar
        results =
          UploadService.upload_liveview_files(
            socket,
            :avatar,
            "groups",
            "group_new",
            access_token
          )

        case results do
          {:ok, [url]} -> {:ok, url}
          {:ok, []} -> {:ok, nil}
          error -> error
        end

      {[], []} ->
        # No file uploaded
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

  defp error_to_string(:too_large), do: "File too large (max 5MB)"
  defp error_to_string(:not_accepted), do: "Invalid file type. Please use PNG, JPG, or GIF."
  defp error_to_string(:too_many_files), do: "Too many files selected"
  defp error_to_string(:external_client_failure), do: "Upload failed"
  defp error_to_string(_), do: "Unknown error"
end
