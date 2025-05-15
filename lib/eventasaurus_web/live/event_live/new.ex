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
  def mount(_params, _session, socket) do
    changeset = Events.change_event(%Event{})

    # Get current date in YYYY-MM-DD format
    today = Date.utc_today() |> Date.to_iso8601()

    socket =
      socket
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
      |> assign(:unsplash_data, nil)
      |> assign(:show_image_picker, false)
      |> assign(:search_query, "")
      |> assign(:search_results, %{unsplash: [], tmdb: []})
      |> assign(:loading, false)
      |> assign(:error, nil)
      |> assign(:page, 1)
      |> assign(:per_page, 20)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    require Logger
    Logger.debug("[validate] incoming params: #{inspect(params)}")
    # Always preserve cover_image_url if not present in params
    cover_image_url =
      params["cover_image_url"] || Map.get(socket.assigns.form_data, "cover_image_url") || socket.assigns.cover_image_url

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

    socket = socket
      |> assign(:changeset, changeset)
      |> assign(:form_data, form_data)
      |> assign(:show_all_timezones, show_all_timezones)

    {:noreply, socket}
  end

  # Handle the timezone detection event from JavaScript hook
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
  def handle_event("submit", %{"event" => event_params}, socket) do
    IO.puts("\n======================== SUBMIT EVENT ========================")
    IO.inspect(event_params, label: "DEBUG - Submit event_params")

    # Parse the unsplash_data JSON string back to a map if it exists
    event_params =
      if event_params["unsplash_data"] && event_params["unsplash_data"] != "" do
        unsplash_data =
          event_params["unsplash_data"]
          |> Jason.decode!()

        Map.put(event_params, "unsplash_data", unsplash_data)
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
    {:noreply, assign(socket, :show_image_picker, true)}
  end

  @impl true
  def handle_event("close_image_picker", _params, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  @impl true
  def handle_event("venue_selected", venue_data, socket) do
    IO.puts("\n======================== VENUE SELECTED ========================")
    IO.inspect(venue_data, label: "DEBUG - Received venue data")

    # Extract data from venue_data with proper defaults
    name = Map.get(venue_data, "name", "") || ""
    address = Map.get(venue_data, "address", "") || ""
    city = Map.get(venue_data, "city", "") || ""
    state = Map.get(venue_data, "state", "") || ""
    country = Map.get(venue_data, "country", "") || ""
    latitude = Map.get(venue_data, "latitude") || nil
    longitude = Map.get(venue_data, "longitude") || nil

    # Debug what we extracted
    IO.puts("DEBUG - Extracted venue data - Name: #{name}, Address: #{address}")
    IO.puts("DEBUG - Location: lat=#{latitude}, lng=#{longitude}")
    IO.puts("DEBUG - Components: city=#{city}, state=#{state}, country=#{country}")

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

    IO.puts("DEBUG - Updated form_data with venue:")
    IO.inspect(form_data, label: "DEBUG - Form data after update")

    # Update the socket with full information and the changeset
    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket = socket
    |> assign(:form_data, form_data)
    |> assign(:changeset, changeset)
    |> assign(:selected_venue_name, name)
    |> assign(:selected_venue_address, address)
    |> assign(:is_virtual, false)

    IO.puts("DEBUG - Socket assigns after update:")
    IO.inspect(socket.assigns.selected_venue_name, label: "DEBUG - selected_venue_name")
    IO.inspect(socket.assigns.selected_venue_address, label: "DEBUG - selected_venue_address")
    IO.puts("======================== END VENUE SELECTED ========================\n")

    {:noreply, socket}
  end

  # Backward compatibility for older place_selected events
  @impl true
  def handle_event("place_selected", %{"details" => place_details}, socket) do
    IO.puts("\n======================== PLACE SELECTED (LEGACY) ========================")
    IO.inspect(place_details, label: "DEBUG - Received place details")

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
      %Event{}
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
  defp ensure_user_struct(%{"id" => supabase_id, "email" => email, "user_metadata" => user_metadata}) do
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
    params = if params["start_at"] == "" && params["start_date"] && params["start_time"] do
      Map.put(params, "start_at", "#{params["start_date"]}T#{params["start_time"]}:00")
    else
      params
    end

    # Combine end date and time if ends_at is empty
    params = if params["ends_at"] == "" && params["ends_date"] && params["ends_time"] do
      Map.put(params, "ends_at", "#{params["ends_date"]}T#{params["ends_time"]}:00")
    else
      params
    end

    params
  end

  @impl true
  def handle_info({:image_selected, %{cover_image_url: url, unsplash_data: unsplash_data}}, socket) do
    # We keep the raw unsplash_data in both places (not pre-encoded)
    # The event_components.ex will handle the encoding when needed
    form_data =
      socket.assigns.form_data
      |> Map.put("cover_image_url", url)
      |> Map.put("unsplash_data", unsplash_data)

    # Update the changeset
    changeset =
      %Event{}
      |> Events.change_event(Map.put(socket.assigns.form_data, "cover_image_url", url))
      |> Map.put(:action, :validate)

    # Debug
    IO.puts("DEBUG - Image Selected:")
    IO.inspect(url, label: "Cover image URL")
    IO.inspect(unsplash_data, label: "Unsplash data")

    {:noreply,
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:cover_image_url, url)
      |> assign(:unsplash_data, unsplash_data)
      |> assign(:show_image_picker, false)}
  end

  @impl true
  def handle_info({:close_image_picker, _}, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  # New handler for Unsplash search
  @impl true
  def handle_event("search_unsplash", %{"search_query" => query}, socket) when query == "" do
    {:noreply,
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, %{unsplash: [], tmdb: []})
      |> assign(:error, nil)
    }
  end

  @impl true
  def handle_event("search_unsplash", %{"search_query" => query}, socket) do
    {:noreply,
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)
      |> assign(:page, 1)
      |> do_search()
    }
  end

  @impl true
  def handle_event("load_more_images", _, socket) do
    {:noreply,
      socket
      |> assign(:page, socket.assigns.page + 1)
      |> assign(:loading, true)
      |> do_search()
    }
  end

  @impl true
  def handle_event("select_image", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.search_results, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      image ->
        # Track the download as per Unsplash API requirements - do this asynchronously
        Task.start(fn ->
          UnsplashService.track_download(image.download_location)
        end)

        # Create the unsplash_data map to be stored in the database
        unsplash_data = %{
          "photo_id" => image.id,
          "url" => image.urls.regular,
          "full_url" => image.urls.full,
          "raw_url" => image.urls.raw,
          "photographer_name" => image.user.name,
          "photographer_username" => image.user.username,
          "photographer_url" => image.user.profile_url,
          "download_location" => image.download_location
        }

        # Update form_data with the Unsplash photo info
        form_data =
          socket.assigns.form_data
          |> Map.put("cover_image_url", image.urls.regular)
          |> Map.put("unsplash_data", unsplash_data)

        # Update the changeset
        changeset =
          %Event{}
          |> Events.change_event(form_data)
          |> Map.put(:action, :validate)

        {:noreply,
          socket
          |> assign(:form_data, form_data)
          |> assign(:changeset, changeset)
          |> assign(:cover_image_url, image.urls.regular)
          |> assign(:unsplash_data, unsplash_data)
          |> assign(:show_image_picker, false)}
    end
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
