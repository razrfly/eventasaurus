defmodule EventasaurusWeb.EventLive.New do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.Services.UnsplashService
  alias EventasaurusWeb.Services.SearchService

  @impl true
  def mount(_params, session, socket) do
    # current_user is already assigned by the on_mount hook
    supabase_access_token = Map.get(session, "access_token")

    changeset = Events.change_event(%Event{})
    today = Date.utc_today() |> Date.to_iso8601()

    socket =
      socket
      |> assign(:supabase_access_token, supabase_access_token)
      |> assign(:changeset, changeset)
      |> assign(:form_data, %{
        "start_date" => today,
        "ends_date" => today
      })
      |> assign(:is_virtual, false)
      |> assign(:selected_venue_name, nil)
      |> assign(:selected_venue_address, nil)
      |> assign(:venues, Venues.list_venues())
      |> assign(:show_all_timezones, false)
      |> assign(:cover_image_url, nil)
      |> assign(:external_image_data, nil)
      |> assign(:show_image_picker, false)
      |> assign(:search_query, "")
      |> assign(:search_results, %{unsplash: [], tmdb: []})
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:page, 1)
      |> assign(:per_page, 20)
      |> assign_new(:image_tab, fn -> "unsplash" end)

    {:ok, socket}
  end

  # ========== Handle Info Implementations ==========
  @impl true
  def handle_info({:close_image_picker, _}, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  # ========== Handle Event Implementations ==========

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    require Logger
    Logger.debug("[validate] incoming params: #{inspect(params)}")
    # Always preserve cover_image_url if not present in params
    cover_image_url =
      params["cover_image_url"] || Map.get(socket.assigns.form_data, "cover_image_url") ||
        socket.assigns.cover_image_url

    params =
      if cover_image_url do
        Map.put(params, "cover_image_url", cover_image_url)
      else
        params
      end

    changeset =
      %Event{}
      |> Events.change_event(params)
      |> Map.put(:action, :validate)

    # Update form_data with the validated params
    form_data = Map.merge(socket.assigns.form_data, params)
    Logger.debug("[validate] resulting form_data: #{inspect(form_data)}")

    # Check if user wants to show all timezones
    {form_data, show_all_timezones} =
      if params["timezone"] == "__show_all__" do
        {Map.put(form_data, "timezone", ""), true}
      else
        {form_data, socket.assigns.show_all_timezones}
      end

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:form_data, form_data)
      |> assign(:show_all_timezones, show_all_timezones)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
    IO.puts("\n======================== SUBMIT EVENT ========================")
    IO.inspect(event_params, label: "DEBUG - Submit event_params")

    # Parse the unsplash_data JSON string back to a map if it exists
    event_params =
      if (event_params["external_image_data"] && event_params["external_image_data"] != "") and
           is_binary(event_params["external_image_data"]) do
        external_image_data =
          event_params["external_image_data"]
          |> Jason.decode!()

        Map.put(event_params, "external_image_data", external_image_data)
      else
        event_params
      end

    # Combine date and time fields if needed
    event_params = combine_date_time_fields(event_params)

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
        IO.puts("DEBUG - Including venue data from form_data")
        Map.merge(event_params, venue_data)
      else
        event_params
      end

    # Process venue data for the database
    event_params = process_venue_data(event_params, socket)

    # Get the user as an Accounts.User struct
    case ensure_user_struct(socket.assigns.current_user) do
      {:ok, user} ->
        # Create the event with the user struct
        case Events.create_event_with_organizer(event_params, user) do
          {:ok, _event} ->
            {:noreply,
             socket
             |> put_flash(:info, "Event created successfully")
             |> redirect(to: ~p"/dashboard")}

          {:error, changeset} ->
            IO.puts("DEBUG - Event creation error:")
            IO.inspect(changeset.errors, label: "Validation errors")
            {:noreply, assign(socket, changeset: changeset)}
        end

      {:error, reason} ->
        IO.puts("ERROR: Failed to get user struct: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Could not create event: User account issue")
         |> assign(changeset: Events.change_event(%Event{}, event_params))}
    end
  end

  @impl true
  def handle_event("toggle_timezone_dropdown", _, socket) do
    {:noreply, assign(socket, :show_all_timezones, !socket.assigns.show_all_timezones)}
  end

  @impl true
  def handle_event("select_timezone", %{"timezone" => timezone}, socket) do
    form_data = Map.put(socket.assigns.form_data, "timezone", timezone)
    changeset = Events.change_event(%Event{}, form_data)

    {:noreply,
     assign(socket, :form_data, form_data)
     |> assign(:changeset, changeset)
     |> assign(:show_all_timezones, false)}
  end

  @impl true
  def handle_event("toggle_image_picker", %{"show" => show}, socket) do
    {:noreply, assign(socket, :show_image_picker, show == "true")}
  end

  @impl true
  def handle_event("set_image_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :image_tab, tab)}
  end

  @impl true
  def handle_event("image_upload_error", %{"error" => error}, socket) do
    {:noreply, assign(socket, :error, "Image upload failed: #{error}")}
  end

  @impl true
  def handle_event("venue_selected", venue_data, socket) do
    IO.puts("\n======================== VENUE SELECTED ========================")
    IO.inspect(venue_data, label: "DEBUG - Received venue data")

    # Extract venue data with defaults
    venue_name = Map.get(venue_data, "name", "")
    venue_address = Map.get(venue_data, "address", "")

    # Update form data with venue information while preserving existing data
    form_data = (socket.assigns.form_data || %{})
    |> Map.put("venue_name", venue_name)
    |> Map.put("venue_address", venue_address)
    |> Map.put("venue_city", Map.get(venue_data, "city", ""))
    |> Map.put("venue_state", Map.get(venue_data, "state", ""))
    |> Map.put("venue_country", Map.get(venue_data, "country", ""))
    |> Map.put("venue_latitude", Map.get(venue_data, "latitude"))
    |> Map.put("venue_longitude", Map.get(venue_data, "longitude"))
    |> Map.put("is_virtual", false)

    # Update the changeset
    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    # Update the socket with full information
    socket =
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:selected_venue_name, venue_name)
      |> assign(:selected_venue_address, venue_address)
      |> assign(:is_virtual, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("place_selected", %{"details" => place_details}, socket) do
    # Extract address components from place details
    address_components = Map.get(place_details, "address_components", [])

    # Extract individual address components
    street_number = get_address_component(address_components, "street_number") || ""
    route = get_address_component(address_components, "route") || ""
    locality = get_address_component(address_components, "locality")

    administrative_area_level_1 =
      get_address_component(address_components, "administrative_area_level_1")

    country = get_address_component(address_components, "country")
    postal_code = get_address_component(address_components, "postal_code")

    # Construct full address
    street_address = [street_number, route] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")

    # Prepare form data with the extracted information
    form_data = %{
      "venue_address" => street_address,
      "venue_city" => locality || "",
      "venue_state" => administrative_area_level_1 || "",
      "venue_country" => country || "",
      "venue_postal_code" => postal_code || "",
      "venue_latitude" => place_details["geometry"]["location"]["lat"],
      "venue_longitude" => place_details["geometry"]["location"]["lng"]
    }

    # Update the changeset
    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    # Update the socket with the new information
    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:changeset, changeset)
     |> assign(:selected_venue_name, place_details["name"])
     |> assign(:selected_venue_address, street_address)
     |> assign(:is_virtual, false)}
  end

  @impl true
  def handle_event("load_more_images", _, socket) do
    {:noreply,
     socket
     |> assign(:page, socket.assigns.page + 1)
     |> assign(:loading, true)
     |> do_search()}
  end

  @impl true
  def handle_event("search_unsplash", %{"search_query" => query}, socket) when query == "" do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, %{unsplash: [], tmdb: []})
     |> assign(:error, nil)
     |> assign(:page, 1)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("search_unsplash", %{"search_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:loading, true)
     |> assign(:page, 1)
     |> do_search()}
  end

  @impl true
  def handle_event("image_uploaded", %{"publicUrl" => image_url, "path" => path}, socket) do
    require Logger
    Logger.debug("[handle_event :image_uploaded] Image uploaded successfully: #{inspect(image_url)}")

    # Create external_image_data for the uploaded image
    external_image_data = %{
      "source" => "upload",
      "url" => image_url,
      "path" => path,
      "uploaded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Update the form with the new image URL and external data
    form_data =
      socket.assigns.form_data
      |> Map.put("cover_image_url", image_url)
      |> Map.put("external_image_data", external_image_data)

    changeset =
      %EventasaurusApp.Events.Event{}
      |> EventasaurusApp.Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:cover_image_url, image_url)
      |> assign(:form_data, form_data)
      |> assign(:external_image_data, external_image_data)
      |> assign(:changeset, changeset)
      |> assign(:show_image_picker, false)
      |> put_flash(:info, "Image uploaded successfully!")

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_image", %{"id" => id}, socket) do
    require Logger
    Logger.debug("[handle_event :select_image] id: #{inspect(id)}")

    # Find the image in the search results
    image =
      socket.assigns.search_results
      |> Map.values()
      |> List.flatten()
      |> Enum.find(fn img -> img.id == id end)

    cond do
      image &&
          (Map.has_key?(image, :download_location) or Map.has_key?(image, "download_location")) ->
        # Unsplash image (atom or string keys)
        download_location = image[:download_location] || image["download_location"]
        user = image[:user] || image["user"] || %{}

        Task.Supervisor.start_child(Eventasaurus.TaskSupervisor, fn ->
          UnsplashService.track_download(download_location)
        end)

        unsplash_data = %{
          "source" => "unsplash",
          "photo_id" => image[:id] || image["id"],
          "url" => get_in(image, [:urls, :regular]) || get_in(image, ["urls", "regular"]),
          "full_url" => get_in(image, [:urls, :full]) || get_in(image, ["urls", "full"]),
          "raw_url" => get_in(image, [:urls, :raw]) || get_in(image, ["urls", "raw"]),
          "photographer_name" => user[:name] || user["name"],
          "photographer_username" => user[:username] || user["username"],
          "photographer_url" => user[:profile_url] || user["profile_url"],
          "download_location" => download_location
        }

        form_data =
          socket.assigns.form_data
          |> Map.put("external_image_data", unsplash_data)

        changeset =
          %Event{}
          |> Events.change_event(form_data)
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:form_data, form_data)
         |> assign(:changeset, changeset)
         |> assign(:cover_image_url, nil)
         |> assign(:external_image_data, unsplash_data)
         |> assign(:show_image_picker, false)}

      image &&
          (image[:poster_path] || image["poster_path"] || image[:profile_path] ||
             image["profile_path"]) ->
        # TMDb image (atom or string keys)
        poster_path =
          image[:poster_path] || image["poster_path"] || image[:profile_path] ||
            image["profile_path"]

        image_url = poster_path && "https://image.tmdb.org/t/p/w500" <> poster_path

        tmdb_data = %{
          "source" => "tmdb",
          "id" => image[:id] || image["id"],
          "url" => image_url,
          "title" => image[:title] || image["title"] || image[:name] || image["name"],
          "media_type" => image[:media_type] || image["media_type"] || "movie"
        }

        form_data =
          socket.assigns.form_data
          |> Map.put("external_image_data", tmdb_data)

        changeset =
          %Event{}
          |> Events.change_event(form_data)
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:form_data, form_data)
         |> assign(:changeset, changeset)
         |> assign(:cover_image_url, image_url)
         |> assign(:external_image_data, tmdb_data)
         |> assign(:show_image_picker, false)}

      true ->
        Logger.error("Image with id #{id} not found in search results")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_image", params, socket) do
    require Logger
    Logger.warning("[select_image] Missing id in params: #{inspect(params)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("image_selected", %{"cover_image_url" => url} = params, socket) do
    require Logger

    Logger.debug(
      "[handle_event :image_selected] url: #{inspect(url)}, params: #{inspect(params)}"
    )

    {external_image_data, _source} =
      cond do
        Map.has_key?(params, "unsplash_data") ->
          data = params["unsplash_data"]
          data = Map.put(data, "source", "unsplash")
          {data, "unsplash"}

        Map.has_key?(params, "tmdb_data") ->
          data = params["tmdb_data"]
          data = Map.put(data, "source", "tmdb")
          {data, "tmdb"}

        true ->
          {nil, nil}
      end

    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", external_image_data)

    changeset =
      %Event{}
      |> Events.change_event(Map.put(socket.assigns.form_data, "cover_image_url", url))
      |> Map.put(:action, :validate)

    IO.puts("DEBUG - Image Selected:")
    IO.inspect(url, label: "Cover image URL")
    IO.inspect(external_image_data, label: "External image data")

    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:changeset, changeset)
     |> assign(:cover_image_url, nil)
     |> assign(:external_image_data, external_image_data)
     |> assign(:show_image_picker, false)}
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => timezone}, socket) do
    IO.puts("DEBUG - Browser detected timezone: #{timezone}")

    # Only set the timezone if it's not already set in the form
    if Map.get(socket.assigns.form_data, "timezone", "") == "" do
      # Update form_data with the detected timezone
      form_data = Map.put(socket.assigns.form_data, "timezone", timezone)

      # Update the changeset with the new timezone
      changeset =
        %Event{}
        |> Events.change_event(form_data)
        |> Map.put(:action, :validate)

      {:noreply,
       socket
       |> assign(:form_data, form_data)
       |> assign(:changeset, changeset)}
    else
      {:noreply, socket}
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
  def handle_event("open_image_picker", _params, socket) do
    {:noreply, assign(socket, show_image_picker: true, image_tab: "unsplash")}
  end

  @impl true
  def handle_event("close_image_picker", _params, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  # Helper to extract address components
  defp get_address_component(components, type) do
    component =
      Enum.find(components, fn comp ->
        comp["types"] && Enum.member?(comp["types"], type)
      end)

    if component, do: component["long_name"], else: ""
  end

  # Process venue data before saving
  defp process_venue_data(params, _socket) do
    is_virtual = Map.get(params, "is_virtual", "false") == "true"

    if is_virtual do
      # For virtual venues, mark it as virtual in the system
      Map.put(params, "is_virtual", true)
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
  defp ensure_user_struct(%EventasaurusApp.Accounts.User{} = user), do: {:ok, user}

  defp ensure_user_struct(%{
         "id" => supabase_id,
         "email" => email,
         "user_metadata" => user_metadata
       }) do
    # Try to find existing user by Supabase ID
    case EventasaurusApp.Accounts.get_user_by_supabase_id(supabase_id) do
      %EventasaurusApp.Accounts.User{} = user ->
        {:ok, user}

      nil ->
        # Create new user if not found
        name = user_metadata["name"] || email |> String.split("@") |> hd()

        user_params = %{
          email: email,
          name: name,
          supabase_id: supabase_id
        }

        case EventasaurusApp.Accounts.create_user(user_params) do
          {:ok, user} -> {:ok, user}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp ensure_user_struct(_), do: {:error, :invalid_user_data}

  # Helper function to combine date and time fields
  defp combine_date_time_fields(params) do
    # Combine start date and time if start_at is empty
    params =
      if params["start_at"] == "" && params["start_date"] && params["start_time"] do
        Map.put(params, "start_at", "#{params["start_date"]}T#{params["start_time"]}:00")
      else
        params
      end

    # Combine end date and time if ends_at is empty
    params =
      if params["ends_at"] == "" && params["ends_date"] && params["ends_time"] do
        Map.put(params, "ends_at", "#{params["ends_date"]}T#{params["ends_time"]}:00")
      else
        params
      end

    params
  end

  # Helper function for searching Unsplash
  defp do_search(socket) do
    # Use the unified search service
    case SearchService.unified_search(
           socket.assigns.search_query,
           page: socket.assigns.page,
           per_page: socket.assigns.per_page
         ) do
      %{
        unsplash: unsplash_results,
        tmdb: tmdb_results
      } ->
        # If this is page 1, replace results, otherwise append for Unsplash; for TMDb, always replace
        updated_unsplash =
          if socket.assigns.page == 1 do
            unsplash_results
          else
            (socket.assigns.search_results[:unsplash] || []) ++ unsplash_results
          end

        updated_tmdb = tmdb_results

        socket
        |> assign(:search_results, %{unsplash: updated_unsplash, tmdb: updated_tmdb})
        |> assign(:loading, false)
        |> assign(:error, nil)

      _ ->
        socket
        |> assign(:loading, false)
        |> assign(:error, "Error searching APIs.")
    end
  end
end
