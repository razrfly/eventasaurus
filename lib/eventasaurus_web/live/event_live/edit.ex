defmodule EventasaurusWeb.EventLive.Edit do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.Services.UnsplashService
  alias EventasaurusWeb.Services.SearchService

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Load the event and ensure user has access
    case Events.get_event_by_slug(slug) do
      nil ->
        {:ok,
          socket
          |> put_flash(:error, "Event not found")
          |> redirect(to: "/dashboard")}

      event ->
        # Check if current user is an organizer for this event
        case ensure_user_struct(socket.assigns[:current_user]) do
          {:ok, user} ->
            if Events.user_is_organizer?(event, user) do
              # Convert the event to a changeset
              changeset = Events.change_event(event)

              # Parse the datetime values into date and time components
              {start_date, start_time} = parse_datetime(event.start_at)
              {ends_date, ends_time} = parse_datetime(event.ends_at)

              # Check if this is a virtual event
              is_virtual = event.venue_id == nil

              # Prepare form data
              form_data = %{
                "start_date" => start_date,
                "start_time" => start_time,
                "ends_date" => ends_date,
                "ends_time" => ends_time,
                "timezone" => event.timezone,
                "is_virtual" => is_virtual,
                "cover_image_url" => event.cover_image_url,
                "external_image_data" => event.external_image_data
              }

              # Set up the socket with all required assigns
              socket =
                socket
                |> assign(:event, event)
                |> assign(:changeset, changeset)
                |> assign(:form_data, form_data)
                |> assign(:is_virtual, is_virtual)
                |> assign(:selected_venue_name, Map.get(form_data, "venue_name"))
                |> assign(:selected_venue_address, Map.get(form_data, "venue_address"))
                |> assign(:venues, Venues.list_venues())
                |> assign(:show_all_timezones, false)
                |> assign(:cover_image_url, event.cover_image_url)
                |> assign(:external_image_data, event.external_image_data)
                |> assign(:show_image_picker, false)
                |> assign(:search_query, "")
                |> assign(:search_results, %{unsplash: [], tmdb: []})
                |> assign(:loading, false)
                |> assign(:error, nil)
                |> assign(:page, 1)
                |> assign(:per_page, 20)
                |> assign_new(:image_tab, fn -> "unsplash" end)

              {:ok, socket}
            else
              {:ok,
                socket
                |> put_flash(:error, "You are not authorized to edit this event")
                |> redirect(to: "/events/#{slug}")}
            end
          _ ->
            {:ok,
              socket
              |> put_flash(:error, "Invalid user session")
              |> redirect(to: "/dashboard")}
        end
    end
  end

  # ========== Form and Validation ==========
  @impl true
  def handle_event("validate", %{"event" => params}, socket) do
    changeset =
      %Event{}
      |> Events.change_event(params)
      |> Map.put(:action, :validate)

    # Update form_data with the validated params
    form_data = Map.merge(socket.assigns.form_data, params)

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

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
    # Parse the unsplash_data JSON string back to a map if it exists
    event_params =
      if event_params["external_image_data"] && event_params["external_image_data"] != "" and is_binary(event_params["external_image_data"]) do
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
  def handle_event("open_image_picker", _params, socket) do
    {:noreply, assign(socket, show_image_picker: true, image_tab: "unsplash")}
  end

  @impl true
  def handle_event("close_image_picker", _params, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  @impl true
  def handle_event("set_image_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :image_tab, tab)}
  end

  @impl true
  def handle_event("venue_selected", venue_data, socket) do
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

    # Update the socket with full information and the changeset
    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket = socket
    |> assign(:form_data, form_data)
    |> assign(:changeset, changeset)
    |> assign(:selected_venue_name, venue_name)
    |> assign(:selected_venue_address, venue_address)
    |> assign(:is_virtual, false)

    {:noreply, socket}
  end

  # Backward compatibility for older place_selected events
  @impl true
  def handle_event("set_timezone", %{"timezone" => timezone}, socket) do
    IO.puts("DEBUG - Browser detected timezone: #{timezone}")
    # For edit view, we don't auto-set timezone because the event already has one
    # But we log it for debugging purposes
    {:noreply, socket}
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
  def handle_event("search_unsplash", %{"search_query" => query}, socket) when query == "" do
    {:noreply,
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, %{unsplash: [], tmdb: []})
      |> assign(:error, nil)
      |> assign(:page, 1)
      |> assign(:loading, false)
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
  def handle_event("select_image", %{"id" => id}, socket) do
    # Search for the image in both unsplash and tmdb results
    unsplash_results = socket.assigns.search_results[:unsplash] || []
    tmdb_results = socket.assigns.search_results[:tmdb] || []

    case Enum.find(unsplash_results, &(&1.id == id)) do
      nil ->
        # Check if it's a TMDB image
        case Enum.find(tmdb_results, &(&1.id == id)) do
          nil ->
            {:noreply, socket}

          image ->
            # Create the tmdb_data map
            tmdb_data = %{
              "source" => "tmdb",
              "id" => image.id,
              "url" => image.poster_path,
              "title" => image.title
            }

            # Update form_data with the TMDB image info
            form_data =
              socket.assigns.form_data
              |> Map.put("external_image_data", tmdb_data)
              |> Map.put("cover_image_url", image.poster_path)

            # Update the changeset
            changeset =
              socket.assigns.event
              |> Events.change_event(form_data)
              |> Map.put(:action, :validate)

            {:noreply,
              socket
              |> assign(:form_data, form_data)
              |> assign(:changeset, changeset)
              |> assign(:cover_image_url, image.poster_path)
              |> assign(:external_image_data, tmdb_data)
              |> assign(:show_image_picker, false)
            }
        end

      image ->
        # Track the download as per Unsplash API requirements - do this asynchronously
        Task.Supervisor.start_child(Eventasaurus.TaskSupervisor, fn ->
          UnsplashService.track_download(image.download_location)
        end)

        # Create the unsplash_data map to be stored in the database
        unsplash_data = %{
          "source" => "unsplash",
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
          |> Map.put("external_image_data", unsplash_data)
          |> Map.put("cover_image_url", image.urls.regular)

        # Update the changeset
        changeset =
          socket.assigns.event
          |> Events.change_event(form_data)
          |> Map.put(:action, :validate)

        {:noreply,
          socket
          |> assign(:form_data, form_data)
          |> assign(:changeset, changeset)
          |> assign(:cover_image_url, image.urls.regular)
          |> assign(:external_image_data, unsplash_data)
          |> assign(:show_image_picker, false)
        }
    end
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

  # Helper to parse a datetime into date and time strings
  defp parse_datetime(nil), do: {nil, nil}
  defp parse_datetime(datetime) do
    date = datetime |> DateTime.to_date() |> Date.to_iso8601()
    time = datetime |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
    {date, time}
  end

  @impl true
  def handle_info({:image_selected, %{cover_image_url: url, unsplash_data: unsplash_data}}, socket) do
    # We don't need this anymore since we handle image selection directly
    # But keeping it for backward compatibility

    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", unsplash_data)

    changeset =
      socket.assigns.event
      |> Events.change_event(Map.put(socket.assigns.form_data, "cover_image_url", url))
      |> Map.put(:action, :validate)

    {:noreply,
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:cover_image_url, nil)
      |> assign(:external_image_data, unsplash_data)
      |> assign(:show_image_picker, false)}
  end

  @impl true
  def handle_info({:close_image_picker, _}, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
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
end
