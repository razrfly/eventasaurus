defmodule EventasaurusWeb.EventLive.New do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.LiveHelpers

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.Services.SearchService

  @impl true
  def mount(_params, _session, socket) do
    # auth_user is already assigned by the on_mount hook
    # Ensure we have a proper User struct for creating events
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        changeset = Events.change_event(%Event{})
        today = Date.utc_today() |> Date.to_iso8601()
        venues = Venues.list_venues()

        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> assign(:venues, venues)
          |> assign(:user, user)
          |> assign(:changeset, changeset)
          |> assign(:form_data, %{
            "start_date" => today,
            "ends_date" => today,
            "enable_date_polling" => false
          })
          |> assign(:is_virtual, false)
          |> assign(:selected_venue_name, nil)
          |> assign(:selected_venue_address, nil)
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
          |> assign(:enable_date_polling, false)

        {:ok, socket}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to create events")
         |> redirect(to: ~p"/auth/login")
        }
    end
  end

  # ========== Handle Info Implementations ==========
  @impl true
  def handle_info({:close_image_picker, _}, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  # ========== Handle Event Implementations ==========

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    require Logger
    Logger.debug("[validate] incoming params: #{inspect(event_params)}")
    # Always preserve cover_image_url if not present in params
    cover_image_url =
      event_params["cover_image_url"] || Map.get(socket.assigns.form_data, "cover_image_url") ||
        socket.assigns.cover_image_url

    event_params =
      if cover_image_url do
        Map.put(event_params, "cover_image_url", cover_image_url)
      else
        event_params
      end

    changeset =
      %Event{}
      |> Events.change_event(event_params)
      |> Map.put(:action, :validate)

    # Update form_data with the validated params
    form_data = Map.merge(socket.assigns.form_data, event_params)
    Logger.debug("[validate] resulting form_data: #{inspect(form_data)}")

    # Check if user wants to show all timezones
    {form_data, show_all_timezones} =
      if event_params["timezone"] == "__show_all__" do
        {Map.put(form_data, "timezone", ""), true}
      else
        {form_data, socket.assigns.show_all_timezones}
      end

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:form_data, form_data)
      |> assign(:show_all_timezones, show_all_timezones)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
    require Logger
    Logger.debug("[submit] incoming params: #{inspect(event_params)}")

    # Process datetime fields - combine date and time into datetime
    event_params = process_datetime_fields(event_params)
    Logger.debug("[submit] processed params: #{inspect(event_params)}")

    # Decode external_image_data if it's a JSON string
    event_params =
      case Map.get(event_params, "external_image_data") do
        nil -> event_params
        "" -> Map.put(event_params, "external_image_data", nil)
        json_string when is_binary(json_string) ->
          case Jason.decode(json_string) do
            {:ok, decoded_data} -> Map.put(event_params, "external_image_data", decoded_data)
            {:error, _} -> Map.put(event_params, "external_image_data", nil)
          end
        data when is_map(data) -> event_params
      end

    # Process venue data from form_data if present
    final_event_params =
      case socket.assigns.form_data do
        form_data when is_map(form_data) ->
          # Check if we have venue data in form_data and user is not setting virtual
          venue_name = Map.get(form_data, "venue_name")
          venue_address = Map.get(form_data, "venue_address")
          is_virtual = Map.get(form_data, "is_virtual", false)

          if !is_virtual and venue_name && venue_name != "" do
            # Try to find existing venue or create new one
            venue_attrs = %{
              "name" => venue_name,
              "address" => venue_address,
              "city" => Map.get(form_data, "venue_city"),
              "state" => Map.get(form_data, "venue_state"),
              "country" => Map.get(form_data, "venue_country"),
              "latitude" => case Map.get(form_data, "venue_latitude") do
                lat when is_binary(lat) ->
                  case Float.parse(lat) do
                    {float_val, _} -> float_val
                    :error -> nil
                  end
                lat -> lat
              end,
              "longitude" => case Map.get(form_data, "venue_longitude") do
                lng when is_binary(lng) ->
                  case Float.parse(lng) do
                    {float_val, _} -> float_val
                    :error -> nil
                  end
                lng -> lng
              end
            }

            # Try to find existing venue by address first
            case EventasaurusApp.Venues.find_venue_by_address(venue_address) do
              nil ->
                # Create new venue
                case EventasaurusApp.Venues.create_venue(venue_attrs) do
                  {:ok, venue} -> Map.put(event_params, "venue_id", venue.id)
                  {:error, _} -> event_params # Fall back to creating without venue
                end
              venue ->
                # Use existing venue
                Map.put(event_params, "venue_id", venue.id)
            end
          else
            # Virtual event or no venue data - clear venue_id
            Map.put(event_params, "venue_id", nil)
          end
        _ ->
          event_params
      end

    case Events.create_event_with_organizer(final_event_params, socket.assigns.user) do
      {:ok, event} ->
        # If date polling is enabled, create the date poll and options
        event_with_poll = if Map.get(event_params, "enable_date_polling", false) do
          case create_date_poll_for_event(event, event_params, socket.assigns.user) do
            {:ok, updated_event} -> updated_event
            {:error, _} -> event # Fall back to original event if poll creation fails
          end
        else
          event
        end

        {:noreply,
         socket
         |> put_flash(:info, "Event created successfully")
         |> redirect(to: ~p"/events/#{event_with_poll.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger
        Logger.error("[submit] Event creation failed with changeset errors: #{inspect(changeset.errors)}")
        {:noreply, assign(socket, form: to_form(changeset))}
    end
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
  def handle_event("toggle_date_polling", _params, socket) do
    enable_date_polling = !socket.assigns.enable_date_polling

    # Update form_data to reflect this change
    form_data =
      socket.assigns.form_data
      |> Map.put("enable_date_polling", enable_date_polling)

    {:noreply,
     socket
     |> assign(:enable_date_polling, enable_date_polling)
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
      |> Enum.find(fn img ->
        (img[:id] || img["id"]) == id
      end)

    case image do
      nil ->
        Logger.error("Image with id #{id} not found in search results")
        {:noreply, socket}

      image when is_map(image) ->
        # Handle Unsplash images
        if image[:urls] || image["urls"] do
          urls = image[:urls] || image["urls"]
          image_url = urls[:regular] || urls["regular"]

          unsplash_data = %{
            "source" => "unsplash",
            "id" => image[:id] || image["id"],
            "url" => image_url,
            "description" => image[:description] || image["description"] || image[:alt_description] || image["alt_description"],
            "photographer" => get_in(image, [:user, :name]) || get_in(image, ["user", "name"]),
            "photographer_url" => get_in(image, [:user, :links, :html]) || get_in(image, ["user", "links", "html"])
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
           |> assign(:cover_image_url, image_url)
           |> assign(:external_image_data, unsplash_data)
           |> assign(:show_image_picker, false)}

        # Handle TMDb images
        else
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
        end
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

  # Helper to extract address components
  defp get_address_component(components, type) do
    component = Enum.find(components, fn comp ->
      comp["types"] && Enum.member?(comp["types"], type)
    end)

    if component, do: component["long_name"], else: ""
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp process_datetime_fields(params) do
    params
    |> process_start_datetime()
    |> process_end_datetime()
  end

  defp process_start_datetime(params) do
    start_date = Map.get(params, "start_date")
    start_time = Map.get(params, "start_time")
    timezone = Map.get(params, "timezone", "UTC")

    case combine_date_time(start_date, start_time, timezone) do
      {:ok, datetime} ->
        Map.put(params, "start_at", datetime)
      {:error, _} ->
        # Keep existing start_at if combination fails
        params
    end
  end

  defp process_end_datetime(params) do
    ends_date = Map.get(params, "ends_date")
    ends_time = Map.get(params, "ends_time")
    timezone = Map.get(params, "timezone", "UTC")

    case combine_date_time(ends_date, ends_time, timezone) do
      {:ok, datetime} ->
        Map.put(params, "ends_at", datetime)
      {:error, _} ->
        # Keep existing ends_at if combination fails
        params
    end
  end

  defp combine_date_time(date_str, time_str, timezone) when is_binary(date_str) and is_binary(time_str) and date_str != "" and time_str != "" do
    try do
      # Parse the date and time
      {:ok, date} = Date.from_iso8601(date_str)
      {:ok, time} = Time.from_iso8601(time_str <> ":00")

      # Create a naive datetime
      naive_datetime = NaiveDateTime.new!(date, time)

      # Convert to timezone-aware datetime
      case DateTime.from_naive(naive_datetime, timezone) do
        {:ok, datetime} ->
          # Convert to UTC for storage
          utc_datetime = DateTime.shift_zone!(datetime, "Etc/UTC")
          {:ok, utc_datetime}
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp combine_date_time(_, _, _), do: {:error, :invalid_input}

  # Helper function to create date poll and options for an event
  defp create_date_poll_for_event(event, form_data, user) do
    start_date_str = Map.get(form_data, "start_date")
    end_date_str = Map.get(form_data, "ends_date")

    start_date = Date.from_iso8601!(start_date_str)
    end_date = Date.from_iso8601!(end_date_str)

    # Create the date poll
    case Events.create_event_date_poll(event, user, %{voting_deadline: nil}) do
      {:ok, poll} ->
        # Create date options for each day in the range
        case Events.create_date_options_from_range(poll, start_date, end_date) do
          {:ok, _options} ->
            # Update event state to 'polling' (use string, not atom)
            case Events.update_event(event, %{state: "polling"}) do
              {:ok, updated_event} ->
                {:ok, updated_event}
              {:error, reason} ->
                {:error, reason}
            end
          {:error, reason} ->
            {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

end
