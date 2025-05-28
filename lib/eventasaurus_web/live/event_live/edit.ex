defmodule EventasaurusWeb.EventLive.Edit do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.LiveHelpers

  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.Services.UnsplashService
  alias EventasaurusWeb.Services.SearchService

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    event = Events.get_event_by_slug(slug)

    if event do
      venues = Venues.list_venues()

      # Ensure we have a proper User struct for authorization
      case ensure_user_struct(socket.assigns[:auth_user]) do
        {:ok, user} ->
          # Check if user can edit this event
          if Events.user_can_manage_event?(user, event) do
            changeset = Events.change_event(event)

            # Convert the event to a changeset
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
              |> assign(:venues, venues)
              |> assign(:form, to_form(changeset))
              |> assign(:changeset, changeset)
              |> assign(:user, user)
              |> assign(:form_data, form_data)
              |> assign(:is_virtual, is_virtual)
              |> assign(:selected_venue_name, Map.get(form_data, "venue_name"))
              |> assign(:selected_venue_address, Map.get(form_data, "venue_address"))
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
             |> put_flash(:error, "You don't have permission to edit this event")
             |> redirect(to: ~p"/dashboard")
            }
          end

        {:error, _} ->
          {:ok,
           socket
           |> put_flash(:error, "You must be logged in to edit events")
           |> redirect(to: ~p"/auth/login")
          }
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "Event not found")
       |> redirect(to: ~p"/dashboard")
      }
    end
  end

  # ========== Form and Validation ==========

  defp save_event(socket, event_params) do
    event = socket.assigns.event

    case Events.update_event(event, event_params) do
      {:ok, event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event updated successfully")
         |> redirect(to: ~p"/events/#{event.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    changeset =
      socket.assigns.event
      |> Events.change_event(event_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"event" => event_params}, socket) do
    save_event(socket, event_params)
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

  # Helper function to extract address components
  defp get_address_component(components, type) do
    component = Enum.find(components, fn comp ->
      comp["types"] && Enum.member?(comp["types"], type)
    end)

    if component, do: component["long_name"], else: ""
  end

  # Helper function for searching
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

  @impl true
  def handle_info({:image_selected, %{cover_image_url: url, unsplash_data: unsplash_data}}, socket) do
    # We don't need this anymore since we handle image selection directly
    # But keeping it for backward compatibility

    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", unsplash_data)

    changeset =
      socket.assigns.event
      |> Events.change_event(Map.put(form_data, "cover_image_url", url))
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

  # Helper function to parse a datetime into date and time strings
  defp parse_datetime(nil), do: {nil, nil}
  defp parse_datetime(datetime) do
    date = datetime |> DateTime.to_date() |> Date.to_iso8601()
    time = datetime |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
    {date, time}
  end
end
