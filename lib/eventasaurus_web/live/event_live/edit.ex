defmodule EventasaurusWeb.EventLive.Edit do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.LiveHelpers
  import EventasaurusWeb.Components.ImagePickerModal


  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.Services.UnsplashService
  alias EventasaurusWeb.Services.SearchService
  alias EventasaurusWeb.Services.DefaultImagesService

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
            {start_date, start_time} = parse_datetime_with_timezone(event.start_at, event.timezone)
            {ends_date, ends_time} = parse_datetime_with_timezone(event.ends_at, event.timezone)

            # Check if this is a virtual event
            is_virtual = event.venue_id == nil

            # Load venue data if the event has a venue
            {venue_name, venue_address, venue_city, venue_state, venue_country, venue_latitude, venue_longitude} =
              if event.venue_id do
                case Venues.get_venue(event.venue_id) do
                  nil -> {nil, nil, nil, nil, nil, nil, nil}
                  venue -> {venue.name, venue.address, venue.city, venue.state, venue.country, venue.latitude, venue.longitude}
                end
              else
                {nil, nil, nil, nil, nil, nil, nil}
              end

            # Check if this event has date polling enabled
            date_poll = Events.get_event_date_poll(event)
            enable_date_polling = !is_nil(date_poll)

            # Get existing selected poll dates if date polling is enabled
            selected_poll_dates = if date_poll do
              date_poll.date_options
              |> Enum.map(& &1.date)
              |> Enum.sort(Date)
              |> Enum.map(&Date.to_iso8601/1)
              |> Enum.join(",")
            else
              ""
            end

            # Prepare form data
            form_data = %{
              "start_date" => start_date,
              "start_time" => start_time,
              "ends_date" => ends_date,
              "ends_time" => ends_time,
              "timezone" => event.timezone,
              "is_virtual" => is_virtual,
              "cover_image_url" => event.cover_image_url,
              "external_image_data" => event.external_image_data,
              "venue_name" => venue_name,
              "venue_address" => venue_address,
              "venue_city" => venue_city,
              "venue_state" => venue_state,
              "venue_country" => venue_country,
              "venue_latitude" => venue_latitude,
              "venue_longitude" => venue_longitude,
              "enable_date_polling" => enable_date_polling,
              "selected_poll_dates" => selected_poll_dates
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
              |> assign(:selected_venue_name, venue_name)
              |> assign(:selected_venue_address, venue_address)
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
              |> assign(:enable_date_polling, enable_date_polling)
              |> assign(:selected_category, "general")
              |> assign(:default_categories, DefaultImagesService.get_categories())
              |> assign(:default_images, DefaultImagesService.get_images_for_category("general"))
              |> assign(:supabase_access_token, "edit_token_#{user.id}")

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

  # ========== Event Handlers ==========

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    changeset =
      socket.assigns.event
      |> Events.change_event(event_params)
      |> Map.put(:action, :validate)
      |> validate_date_polling(event_params)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
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

    # Combine date and time fields into proper UTC datetime values
    event_params = combine_date_time_fields(event_params)

    # Process venue data from the form submission params (not form_data)
    # Check if we have venue data in the submitted form params and user is not setting virtual
    venue_name = Map.get(event_params, "venue_name")
    venue_address = Map.get(event_params, "venue_address")
    is_virtual = Map.get(event_params, "is_virtual") == "true"

    final_event_params = if !is_virtual and venue_name && venue_name != "" do
      # Try to find existing venue or create new one
      venue_attrs = %{
        "name" => venue_name,
        "address" => venue_address,
        "city" => Map.get(event_params, "venue_city"),
        "state" => Map.get(event_params, "venue_state"),
        "country" => Map.get(event_params, "venue_country"),
        "latitude" => case Map.get(event_params, "venue_latitude") do
          lat when is_binary(lat) and lat != "" ->
            case Float.parse(lat) do
              {float_val, _} -> float_val
              :error -> nil
            end
          lat -> lat
        end,
        "longitude" => case Map.get(event_params, "venue_longitude") do
          lng when is_binary(lng) and lng != "" ->
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
            {:error, _} -> event_params # Fall back to updating without venue
          end
        venue ->
          # Use existing venue
          Map.put(event_params, "venue_id", venue.id)
      end
    else
      # Virtual event or no venue data - clear venue_id
      Map.put(event_params, "venue_id", nil)
    end

    # Clean up venue-related fields that the Event changeset doesn't expect
    # Keep date polling fields for our custom logic
    final_event_params = final_event_params
    |> Map.drop(["venue_name", "venue_address", "venue_city", "venue_state",
                 "venue_country", "venue_latitude", "venue_longitude", "is_virtual",
                 "start_date", "start_time", "ends_date", "ends_time"])

    # Validate date polling before saving
    validation_changeset =
      socket.assigns.event
      |> Events.change_event(final_event_params)
      |> Map.put(:action, :validate)
      |> validate_date_polling(final_event_params)

    if validation_changeset.valid? do
      case save_event(socket, socket.assigns.event, final_event_params) do
        {:ok, event} ->
          {:noreply,
           socket
           |> put_flash(:info, "Event updated successfully")
           |> redirect(to: ~p"/events/#{event.slug}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}

        {:error, socket_with_error} ->
          {:noreply, socket_with_error}
      end
    else
      {:noreply, assign(socket,
        form: to_form(validation_changeset),
        changeset: validation_changeset
      )}
    end
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
    {:noreply, assign(socket, :show_image_picker, true)}
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
      |> do_unified_search()
    }
  end

  @impl true
  def handle_event("unified_search", %{"search_query" => query}, socket) when query == "" do
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
  def handle_event("unified_search", %{"search_query" => query}, socket) do
    {:noreply,
      socket
      |> assign(:search_query, query)
      |> assign(:loading, true)
      |> assign(:page, 1)
      |> do_unified_search()
    }
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    images = DefaultImagesService.get_images_for_category(category)

    {:noreply,
      socket
      |> assign(:selected_category, category)
      |> assign(:default_images, images)
    }
  end

  @impl true
  def handle_event("select_default_image", params, socket) do
    %{"image_url" => image_url, "filename" => filename, "category" => category} = params

    external_image_data = %{"source" => "default",
                            "url" => image_url,
                            "filename" => filename,
                            "category" => category,
                            "title" => String.replace(filename, ".png", "") |> String.replace("_", " ") |> String.split("-") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")}

    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", external_image_data)
      |> Map.put("cover_image_url", image_url)

    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    {:noreply,
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:cover_image_url, image_url)
      |> assign(:external_image_data, external_image_data)
      |> assign(:show_image_picker, false)
    }
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

  @impl true
  def handle_event("image_selected", %{"cover_image_url" => cover_image_url, "unsplash_data" => unsplash_data}, socket) do
    # Track the download as per Unsplash API requirements
    if Map.has_key?(unsplash_data, "download_location") do
      Task.Supervisor.start_child(Eventasaurus.TaskSupervisor, fn ->
        UnsplashService.track_download(unsplash_data["download_location"])
      end)
    end

    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", unsplash_data)
      |> Map.put("cover_image_url", cover_image_url)

    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    {:noreply,
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:cover_image_url, cover_image_url)
      |> assign(:external_image_data, unsplash_data)
      |> assign(:show_image_picker, false)
    }
  end

  @impl true
  def handle_event("image_selected", %{"cover_image_url" => cover_image_url, "tmdb_data" => tmdb_data}, socket) do
    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", tmdb_data)
      |> Map.put("cover_image_url", cover_image_url)

    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    {:noreply,
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:cover_image_url, cover_image_url)
      |> assign(:external_image_data, tmdb_data)
      |> assign(:show_image_picker, false)
    }
  end

  # ========== Info Handlers ==========

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

      @impl true
  def handle_info({:selected_dates_changed, dates}, socket) do
    # Validate and process dates
    date_strings = case dates do
      dates when is_list(dates) ->
        dates
        |> Enum.uniq()
        |> Enum.map(fn
          %Date{} = date -> Date.to_iso8601(date)
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
      _ ->
        []
    end

    dates_string = Enum.join(date_strings, ",")

    # Update form_data with the new selected dates
    form_data = Map.put(socket.assigns.form_data, "selected_poll_dates", dates_string)

    socket = assign(socket, :form_data, form_data)

    {:noreply, socket}
  end

  # ========== Helper Functions ==========

  defp save_event(socket, event, event_params) do
    # First update the event
    case Events.update_event(event, event_params) do
      {:ok, updated_event} ->
        # Handle date polling updates
        case handle_date_polling_update(updated_event, event_params, socket.assigns.user) do
          {:error, changeset} ->
            require Logger
            Logger.error("Failed to update date polling", changeset: inspect(changeset))
            socket = put_flash(socket, :error, "We couldn't save the poll dates – please try again.")
            {:error, socket}
          _ ->
            {:ok, updated_event}
        end

      {:error, changeset} ->
        require Logger
        Logger.error("Failed to update event", changeset: inspect(changeset))
        socket = put_flash(socket, :error, "We couldn't save the event – please try again.")
        {:error, socket}
    end
  end

  # Helper function to handle date polling updates
  defp handle_date_polling_update(event, params, user) do
    enable_date_polling = Map.get(params, "enable_date_polling", false)
    # Handle string "true"/"false" from form submissions properly
    is_polling_enabled = enable_date_polling == true or enable_date_polling == "true"
    existing_poll = Events.get_event_date_poll(event)

    cond do
      # Case 1: Enabling date polling (create new poll or update existing)
      is_polling_enabled ->
        selected_dates_string = Map.get(params, "selected_poll_dates", "")

        if selected_dates_string != "" do
          # Parse selected dates
          selected_dates =
            selected_dates_string
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.filter(&(&1 != ""))
            |> Enum.map(fn date_str ->
              case Date.from_iso8601(date_str) do
                {:ok, date} -> date
                {:error, _} -> nil
              end
            end)
            |> Enum.filter(&(&1 != nil))

          if existing_poll do
            # Smart update: only add/remove changed date options to preserve existing votes
            case Events.update_event_date_options(existing_poll, selected_dates) do
              {:ok, _updated_options} ->
                # Update event state to polling if not already
                if event.state != "polling" do
                  Events.update_event(event, %{state: "polling"})
                end
              {:error, changeset} ->
                require Logger
                Logger.error("Failed to update date options", changeset: inspect(changeset))
                # Return error to be handled by caller
                {:error, changeset}
            end
          else
            # Create new poll
            case Events.create_event_date_poll(event, user, %{voting_deadline: nil}) do
              {:ok, poll} ->
                Events.create_date_options_from_list(poll, selected_dates)
                Events.update_event(event, %{state: "polling"})
              {:error, _} ->
                # Handle error silently for now
                nil
            end
          end
        end

      # Case 2: Disabling date polling (keep poll but change event state)
      existing_poll && !is_polling_enabled ->
        # Change event state back to published but keep the poll data
        if event.state == "polling" do
          Events.update_event(event, %{state: "published"})
        end

      # Case 3: No changes needed
      true ->
        nil
    end
  end

  # Helper function to combine date and time fields into UTC datetime
  defp combine_date_time_fields(params) do
    timezone = Map.get(params, "timezone", "UTC")

    # Check if date polling is enabled
    if Map.get(params, "enable_date_polling", false) do
      # For date polling, use middle date from selected dates
      case Map.get(params, "selected_poll_dates") do
        dates_string when is_binary(dates_string) and dates_string != "" ->
          # Parse the comma-separated date strings
          selected_dates =
            dates_string
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.filter(&(&1 != ""))
            |> Enum.map(fn date_str ->
              case Date.from_iso8601(date_str) do
                {:ok, date} -> date
                {:error, _} -> nil
              end
            end)
            |> Enum.filter(&(&1 != nil))
            |> Enum.sort()

          if length(selected_dates) > 0 do
            # Calculate the middle date (median)
            middle_index = div(length(selected_dates), 2)
            middle_date = Enum.at(selected_dates, middle_index)

            # Get start and end times
            start_time = Map.get(params, "start_time", "09:00")
            end_time = Map.get(params, "ends_time", "17:00")

            # Create start_at and ends_at using middle date
            case combine_date_time_to_utc(Date.to_iso8601(middle_date), start_time, timezone) do
              {:ok, start_datetime} ->
                case combine_date_time_to_utc(Date.to_iso8601(middle_date), end_time, timezone) do
                  {:ok, end_datetime} ->
                    params
                    |> Map.put("start_at", start_datetime)
                    |> Map.put("ends_at", end_datetime)
                  {:error, _} ->
                    params
                end
              {:error, _} ->
                params
            end
          else
            params
          end
        _ ->
          params
      end
    else
      # Traditional date handling
      # Combine start date and time
      start_at = case {Map.get(params, "start_date"), Map.get(params, "start_time")} do
        {date_str, time_str} when is_binary(date_str) and is_binary(time_str) ->
          case combine_date_time_to_utc(date_str, time_str, timezone) do
            {:ok, datetime} -> datetime
            {:error, _} -> Map.get(params, "start_at")
          end
        _ -> Map.get(params, "start_at")
      end

      # Combine end date and time
      ends_at = case {Map.get(params, "ends_date"), Map.get(params, "ends_time")} do
        {date_str, time_str} when is_binary(date_str) and is_binary(time_str) ->
          case combine_date_time_to_utc(date_str, time_str, timezone) do
            {:ok, datetime} -> datetime
            {:error, _} -> Map.get(params, "ends_at")
          end
        _ -> Map.get(params, "ends_at")
      end

      params
      |> Map.put("start_at", start_at)
      |> Map.put("ends_at", ends_at)
    end
  end

  # Helper function to combine date and time strings into UTC datetime
  defp combine_date_time_to_utc(date_str, time_str, timezone) when is_binary(date_str) and is_binary(time_str) and date_str != "" and time_str != "" do
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

  defp combine_date_time_to_utc(_, _, _), do: {:error, :invalid_input}

  # Helper function to extract address components
  defp get_address_component(components, type) do
    component = Enum.find(components, fn comp ->
      comp["types"] && Enum.member?(comp["types"], type)
    end)

    if component, do: component["long_name"], else: ""
  end

  # Helper function for unified searching (same as new page)
  defp do_unified_search(socket) do
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

  # Helper function to parse a datetime into date and time strings
  defp parse_datetime(nil), do: {nil, nil}
  defp parse_datetime(datetime) do
    date = datetime |> DateTime.to_date() |> Date.to_iso8601()
    time = datetime |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
    {date, time}
  end

  # Helper function to parse a datetime into date and time strings with timezone conversion
  defp parse_datetime_with_timezone(nil, _timezone), do: {nil, nil}
  defp parse_datetime_with_timezone(datetime, timezone) do
    # Convert UTC datetime to the event's timezone for display
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted_datetime} ->
        date = shifted_datetime |> DateTime.to_date() |> Date.to_iso8601()
        time = shifted_datetime |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
        {date, time}
      {:error, _} ->
        # Fallback to UTC if timezone conversion fails
        parse_datetime(datetime)
    end
  end

  # Helper function to validate date polling options
  defp validate_date_polling(changeset, params) do
    enable_date_polling = Map.get(params, "enable_date_polling", false)

    # Handle string "true"/"false" from form submissions
    is_polling_enabled = enable_date_polling == true or enable_date_polling == "true"

    if is_polling_enabled do
      selected_dates_string = Map.get(params, "selected_poll_dates", "")

      if selected_dates_string == "" do
        Ecto.Changeset.add_error(changeset, :selected_poll_dates, "must select at least 2 dates for polling")
      else
        selected_dates =
          selected_dates_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))

        if length(selected_dates) < 2 do
          Ecto.Changeset.add_error(changeset, :selected_poll_dates, "must select at least 2 dates for polling")
        else
          changeset
        end
      end
    else
      changeset
    end
  end
end
