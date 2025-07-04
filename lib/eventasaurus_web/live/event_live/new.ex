defmodule EventasaurusWeb.EventLive.New do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.LiveHelpers
  import EventasaurusWeb.Components.ImagePickerModal
  import EventasaurusWeb.Components.TicketModal
  import EventasaurusWeb.Helpers.CurrencyHelpers


  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.Services.SearchService

  @valid_setup_paths ~w[polling confirmed threshold]

  @impl true
  def mount(_params, session, socket) do
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        changeset = Events.change_event(%Event{})
        today = Date.utc_today() |> Date.to_iso8601()
        venues = Venues.list_venues()

        # Load recent locations for the user
        recent_locations = Events.get_recent_locations_for_user(user.id, limit: 5)

        # Auto-select a random default image
        random_image = EventasaurusWeb.Services.DefaultImagesService.get_random_image()

        {cover_image_url, external_image_data} = case random_image do
          nil -> {nil, nil}
          image -> {
            image.url,
            %{
              "source" => "default",
              "url" => image.url,
              "filename" => image.filename,
              "category" => image.category,
              "title" => image.title
            }
          }
        end

        # Update form_data with the random image
        initial_form_data = %{
          "start_date" => today,
          "ends_date" => today,
          "enable_date_polling" => false,
          "slug" => Nanoid.generate(10)
        }

        form_data_with_image = case cover_image_url do
          nil -> initial_form_data
          url -> Map.merge(initial_form_data, %{
            "cover_image_url" => url,
            "external_image_data" => external_image_data
          })
        end

        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> assign(:venues, venues)
          |> assign(:user, user)
          |> assign(:changeset, changeset)
          |> assign(:form_data, form_data_with_image)
          |> assign(:is_virtual, false)
          |> assign(:selected_venue_name, nil)
          |> assign(:selected_venue_address, nil)
          |> assign(:show_all_timezones, false)
          |> assign(:cover_image_url, cover_image_url)
          |> assign(:external_image_data, external_image_data)
          |> assign(:show_image_picker, false)
          |> assign(:search_query, "")
          |> assign(:search_results, %{unsplash: [], tmdb: []})
          |> assign(:loading, false)
          |> assign(:error, nil)
          |> assign(:page, 1)
          |> assign(:per_page, 20)
          |> assign(:image_tab, "search") # Changed from "unsplash" to unified search
          |> assign(:enable_date_polling, false)
          |> assign(:setup_path, "confirmed") # default to confirmed for new events
          # New unified picker assigns
          |> assign(:selected_category, "general")
          |> assign(:default_categories, EventasaurusWeb.Services.DefaultImagesService.get_categories())
          |> assign(:default_images, EventasaurusWeb.Services.DefaultImagesService.get_images_for_category("general"))
          |> assign(:supabase_access_token, session["access_token"])
          # Ticketing assigns
          |> assign(:tickets, [])
          |> assign(:show_ticket_modal, false)
          |> assign(:ticket_form_data, %{})
          |> assign(:editing_ticket_id, nil)
          |> assign(:show_additional_options, false)
          # Recent locations assigns
          |> assign(:recent_locations, recent_locations)
          |> assign(:show_recent_locations, false)
          |> assign(:filtered_recent_locations, recent_locations)

        {:ok, socket}

      {:error, reason} ->
        {:ok, put_flash(socket, :error, "Authentication error: #{reason}")}
    end
  end

  # ========== Handle Info Implementations ==========
  @impl true
  def handle_info({:close_image_picker, _}, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
  end

  @impl true
  def handle_info({:start_unified_search, query}, socket) do
    # Perform the unified search
    results = EventasaurusWeb.Services.SearchService.unified_search(query)

    socket =
      socket
      |> assign(:search_results, results)
      |> assign(:loading, false)
      |> assign(:error, nil)
    {:noreply, socket}
  end

    @impl true
  def handle_info({:selected_dates_changed, dates}, socket) do
    # Convert dates to ISO8601 strings for form data
    date_strings = Enum.map(dates, &Date.to_iso8601/1)
    dates_string = Enum.join(date_strings, ",")

    # Update form_data with the new selected dates
    form_data = Map.put(socket.assigns.form_data, "selected_poll_dates", dates_string)

    socket = assign(socket, :form_data, form_data)

    {:noreply, socket}
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
      |> validate_date_polling(event_params)

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

    # Validate date polling before saving
    validation_changeset =
      %Event{}
      |> Events.change_event(final_event_params)
      |> Map.put(:action, :validate)
      |> validate_date_polling(final_event_params)

    if validation_changeset.valid? do
      # No date polling validation errors, proceed normally
      create_event_with_validation(final_event_params, socket)
    else
      # Validation failed, show errors
      {:noreply, assign(socket, form: to_form(validation_changeset))}
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
  def handle_event("select_setup_path", %{"path" => path}, socket) when path in @valid_setup_paths do
    # Update form_data based on the selected path
    form_data =
      socket.assigns.form_data
      |> Map.put("setup_path", path)
      |> Map.put("enable_date_polling", path == "polling")
      |> Map.put("is_ticketed", path in ["confirmed", "threshold"])
      |> Map.put("requires_threshold", path == "threshold")

    # Update the socket with the new path and form data
    socket =
      socket
      |> assign(:setup_path, path)
      |> assign(:enable_date_polling, path == "polling")
      |> assign(:is_ticketed, path in ["confirmed", "threshold"])
      |> assign(:requires_threshold, path == "threshold")
      |> assign(:form_data, form_data)
      |> maybe_reset_ticketing(path)

    {:noreply, socket}
  end

  def handle_event("select_setup_path", _params, socket),
    do: {:noreply, socket}  # ignore unknown values

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
    {:noreply, assign(socket, show_image_picker: true, image_tab: "search")}
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
  def handle_event("calendar_dates_changed", %{"dates" => dates, "component_id" => _id}, socket) do
    selected_dates = Enum.join(dates, ",")
    form_data = Map.put(socket.assigns.form_data, "selected_poll_dates", selected_dates)
    changeset = Events.change_event(%Event{}, form_data)

    {:noreply,
     assign(socket, :form_data, form_data)
     |> assign(:changeset, changeset)}
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
      |> assign(:show_recent_locations, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_recent_locations", _params, socket) do
    {:noreply, assign(socket, :show_recent_locations, !socket.assigns.show_recent_locations)}
  end

  @impl true
  def handle_event("select_recent_location", %{"location" => location_json}, socket) do
    # Parse the JSON data
    location_data = Jason.decode!(location_json)

    # Handle both physical venues and virtual meetings
    {venue_name, venue_address, is_virtual, form_data_updates} =
      case location_data do
        %{"virtual_venue_url" => url} when not is_nil(url) ->
          # Virtual meeting
          {"Virtual Event", nil, true, %{
            "virtual_venue_url" => url,
            "venue_name" => "",
            "venue_address" => "",
            "venue_city" => "",
            "venue_state" => "",
            "venue_country" => "",
            "venue_latitude" => nil,
            "venue_longitude" => nil,
            "is_virtual" => true
          }}

        _ ->
          # Physical venue
          venue_name = Map.get(location_data, "name", "")
          venue_address = Map.get(location_data, "address", "")

          {venue_name, venue_address, false, %{
            "venue_name" => venue_name,
            "venue_address" => venue_address,
            "venue_city" => Map.get(location_data, "city", ""),
            "venue_state" => Map.get(location_data, "state", ""),
            "venue_country" => Map.get(location_data, "country", ""),
            "venue_latitude" => Map.get(location_data, "latitude"),
            "venue_longitude" => Map.get(location_data, "longitude"),
            "virtual_venue_url" => "",
            "is_virtual" => false
          }}
      end

    # Update form data while preserving existing data
    form_data = Map.merge(socket.assigns.form_data || %{}, form_data_updates)

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
      |> assign(:is_virtual, is_virtual)
      |> assign(:show_recent_locations, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_recent_locations", %{"query" => query}, socket) do
    filtered_locations = filter_locations(socket.assigns.recent_locations, query)
    {:noreply, assign(socket, :filtered_recent_locations, filtered_locations)}
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
  def handle_event("select_image", %{"source" => source, "image_url" => image_url, "image_data" => image_data} = params, socket) do
    external_data = %{
      "source" => source,
      "url" => image_url,
      "id" => params["id"] || image_data["id"] || "unknown",
      "metadata" => image_data
    }

    socket =
      socket
      |> assign(:cover_image_url, image_url)
      |> assign(:external_image_data, external_data)
      |> assign(:show_image_picker, false)

    {:noreply, socket}
  end

  def handle_event("select_image", params, socket) do
    require Logger
    Logger.warning("[select_image] Missing required params in: #{inspect(params)}")
    {:noreply, socket}
  end

  # Handle TMDB image selection
  def handle_event("select_tmdb_image", params, socket) do
    handle_event("select_image", Map.put(params, "source", "tmdb"), socket)
  end

  # Handle successful image upload
  def handle_event("image_upload_success", %{"url" => url, "path" => path}, socket) do
    socket =
      socket
      |> assign(:cover_image_url, url)
      |> assign(:external_image_data, %{
        "source" => "upload",
        "url" => url,
        "path" => path
      })
      |> put_flash(:info, "Image uploaded successfully!")

    {:noreply, socket}
  end

  # Handle image selection from UI components (actual event name used by UI)
  @impl true
  def handle_event("image_selected", %{"cover_image_url" => image_url} = params, socket) do
    # Determine source and extract image data based on what's present in params
    {source, image_data} = cond do
      Map.has_key?(params, "unsplash_data") ->
        {"unsplash", Map.get(params, "unsplash_data", %{})}
      Map.has_key?(params, "tmdb_data") ->
        {"tmdb", Map.get(params, "tmdb_data", %{})}
      true ->
        {"unknown", %{}}
    end

    external_data = %{
      "source" => source,
      "url" => image_url,
      "id" => image_data["id"] || "unknown",
      "metadata" => image_data
    }

    # Update form_data with the new image
    form_data = Map.merge(socket.assigns.form_data, %{
      "cover_image_url" => image_url,
      "external_image_data" => external_data
    })

    # Update changeset
    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:cover_image_url, image_url)
      |> assign(:external_image_data, external_data)
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:show_image_picker, false)

    {:noreply, socket}
  end

  # Handle category selection in unified image picker
  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    default_images = EventasaurusWeb.Services.DefaultImagesService.get_images_for_category(category)

    socket =
      socket
      |> assign(:selected_category, category)
      |> assign(:default_images, default_images)
      |> assign(:search_query, "") # Clear search when switching categories
      |> assign(:search_results, %{unsplash: [], tmdb: []}) # Clear search results

    {:noreply, socket}
  end

  # Handle default image selection
  @impl true
  def handle_event("select_default_image", %{"image_url" => image_url, "filename" => filename, "category" => category}, socket) do
    external_data = %{
      "source" => "default",
      "url" => image_url,
      "id" => filename,
      "category" => category
    }

    # Update form_data with the new image
    form_data = Map.merge(socket.assigns.form_data, %{
      "cover_image_url" => image_url,
      "external_image_data" => external_data
    })

    # Update changeset
    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:cover_image_url, image_url)
      |> assign(:external_image_data, external_data)
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:show_image_picker, false)

    {:noreply, socket}
  end

  # Handle unified search (combines Unsplash and TMDB)
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

      # Start both searches concurrently
      send(self(), {:start_unified_search, query})

      {:noreply, socket}
    end
  end

  # ============================================================================
  # Ticketing Event Handlers
  # ============================================================================

  @impl true
  def handle_event("toggle_ticketing", _params, socket) do
    current_value = Map.get(socket.assigns.form_data, "is_ticketed", false)
    # Handle both string and boolean values
    current_bool = current_value in [true, "true"]
    new_value = !current_bool

    form_data = Map.put(socket.assigns.form_data, "is_ticketed", new_value)

    # Reset ticketing-related assigns when disabling ticketing
    socket = if new_value do
      socket
    else
      socket
      |> assign(:tickets, [])
      |> assign(:show_ticket_modal, false)
      |> assign(:ticket_form_data, %{})
      |> assign(:editing_ticket_id, nil)
    end

    socket = assign(socket, :form_data, form_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_ticket_form", _params, socket) do
    default_currency = get_currency_with_fallback(socket.assigns.user)

    socket =
      socket
      |> assign(:show_ticket_modal, true)
      |> assign(:ticket_form_data, %{"currency" => default_currency})
      |> assign(:editing_ticket_id, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_ticket", %{"id" => ticket_id_str} = _params, socket) do
    # Handle both ID-based (for tickets with IDs) and index-based (for temporary tickets)
    tickets = socket.assigns.tickets || []

    {ticket, ticket_id} = cond do
      # Try to find by ID first (for tickets that have been saved)
      String.starts_with?(ticket_id_str, "temp_") ->
        ticket = Enum.find(tickets, &(to_string(Map.get(&1, :id, "")) == ticket_id_str))
        {ticket, ticket_id_str}

      # Handle numeric strings - could be either index or ID
      String.match?(ticket_id_str, ~r/^\d+$/) ->
        case Integer.parse(ticket_id_str) do
          {num, ""} ->
            # Try as index first (for backward compatibility)
            if num >= 0 and num < length(tickets) do
              ticket = Enum.at(tickets, num)
              {ticket, Map.get(ticket, :id, ticket_id_str)}
            else
              # Try as ID
              ticket = Enum.find(tickets, &(Map.get(&1, :id) == num))
              {ticket, ticket_id_str}
            end
          _ ->
            {nil, nil}
        end

      true ->
        # Try to find by ID
        ticket = Enum.find(tickets, &(to_string(Map.get(&1, :id, "")) == ticket_id_str))
        {ticket, ticket_id_str}
    end

    if ticket do
      form_data = %{
        "title" => ticket.title,
        "description" => ticket.description || "",
        "pricing_model" => Map.get(ticket, :pricing_model, "fixed"),
        "price" => format_price_from_cents(ticket.base_price_cents),
        "minimum_price" => format_price_from_cents(Map.get(ticket, :minimum_price_cents, 0)),
        "suggested_price" => format_price_from_cents(Map.get(ticket, :suggested_price_cents, ticket.base_price_cents)),
        "currency" => Map.get(ticket, :currency, get_currency_with_fallback(socket.assigns.user)),
        "quantity" => Integer.to_string(ticket.quantity),
        "starts_at" => format_datetime_for_input(ticket.starts_at),
        "ends_at" => format_datetime_for_input(ticket.ends_at),
        "tippable" => ticket.tippable
      }

              socket =
        socket
        |> assign(:show_ticket_modal, true)
        |> assign(:ticket_form_data, form_data)
        |> assign(:editing_ticket_id, ticket_id)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_ticket", %{"id" => ticket_id_str}, socket) do
    tickets = socket.assigns.tickets || []

    # Find the ticket to remove - handle both ID and index-based removal
    updated_tickets = cond do
      # Handle temporary IDs
      String.starts_with?(ticket_id_str, "temp_") ->
        Enum.reject(tickets, &(to_string(Map.get(&1, :id, "")) == ticket_id_str))

      # Handle numeric strings (could be index or ID)
      String.match?(ticket_id_str, ~r/^\d+$/) ->
        case Integer.parse(ticket_id_str) do
          {num, ""} ->
            # Try removing by index first (for backward compatibility)
            if num >= 0 and num < length(tickets) do
              List.delete_at(tickets, num)
            else
              # Try removing by ID
              Enum.reject(tickets, &(Map.get(&1, :id) == num))
            end
          _ ->
            tickets
        end

      true ->
        # Remove by ID
        Enum.reject(tickets, &(to_string(Map.get(&1, :id, "")) == ticket_id_str))
    end

    socket = assign(socket, :tickets, updated_tickets)
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_ticket_form", _params, socket) do
    socket =
      socket
      |> assign(:show_ticket_modal, false)
      |> assign(:ticket_form_data, %{})
      |> assign(:editing_ticket_id, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_ticket_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_ticket_modal, false)
      |> assign(:ticket_form_data, %{})
      |> assign(:editing_ticket_id, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_additional_options", _params, socket) do
    current_value = Map.get(socket.assigns, :show_additional_options, false)
    socket = assign(socket, :show_additional_options, !current_value)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_ticket", %{"ticket" => ticket_params}, socket) do
    # Update the ticket form data, preserving existing values
    current_data = socket.assigns.ticket_form_data || %{}

    # Handle checkbox properly - if tippable is not in params, it means unchecked
    updated_data = if Map.has_key?(ticket_params, "tippable") do
      Map.merge(current_data, ticket_params)
    else
      # Checkbox was unchecked, so explicitly set tippable to false
      ticket_params_with_tippable = Map.put(ticket_params, "tippable", false)
      Map.merge(current_data, ticket_params_with_tippable)
    end

    socket = assign(socket, :ticket_form_data, updated_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_ticket", %{"ticket" => ticket_params}, socket) do
    ticket_data = ticket_params

    # Validate required fields
    cond do
      Map.get(ticket_data, "title", "") |> String.trim() == "" ->
        socket = put_flash(socket, :error, "Ticket name is required")
        {:noreply, socket}

      Map.get(ticket_data, "price", "") |> String.trim() == "" ->
        socket = put_flash(socket, :error, "Ticket price is required")
        {:noreply, socket}

      Map.get(ticket_data, "quantity", "") |> String.trim() == "" ->
        socket = put_flash(socket, :error, "Ticket quantity is required")
        {:noreply, socket}

      true ->
        # Parse pricing data
        price_cents = parse_currency(Map.get(ticket_data, "price", "0")) || 0
        pricing_model = Map.get(ticket_data, "pricing_model", "fixed")

        # Validate flexible pricing fields
        case validate_flexible_pricing(ticket_data, pricing_model, price_cents) do
          {:ok, minimum_price_cents, suggested_price_cents} ->
            # Create ticket struct
            ticket = %{
              title: Map.get(ticket_data, "title", ""),
              description: Map.get(ticket_data, "description"),
              pricing_model: pricing_model,
              base_price_cents: price_cents,
              minimum_price_cents: minimum_price_cents,
              suggested_price_cents: suggested_price_cents,
              currency: Map.get(ticket_data, "currency", get_currency_with_fallback(socket.assigns.user)),
              quantity: case Integer.parse(Map.get(ticket_data, "quantity", "0")) do
                {n, _} when n >= 0 -> n
                _ -> 0
              end,
              starts_at: parse_datetime(Map.get(ticket_data, "starts_at")),
              ends_at: parse_datetime(Map.get(ticket_data, "ends_at")),
              tippable: Map.get(ticket_data, "tippable", false) == true
            }

            # Add or update ticket in the list
            updated_tickets = case socket.assigns.editing_ticket_id do
              nil ->
                # Adding new ticket - assign a temporary ID for consistency
                ticket_with_id = Map.put(ticket, :id, "temp_#{System.unique_integer([:positive])}")
                socket.assigns.tickets ++ [ticket_with_id]
              ticket_id ->
                # Updating existing ticket - find by ID and replace
                Enum.map(socket.assigns.tickets, fn existing_ticket ->
                  if Map.get(existing_ticket, :id) == ticket_id do
                    Map.put(ticket, :id, ticket_id)
                  else
                    existing_ticket
                  end
                end)
            end

            socket =
              socket
              |> assign(:tickets, updated_tickets)
              |> assign(:show_ticket_modal, false)
              |> assign(:ticket_form_data, %{})
              |> assign(:editing_ticket_id, nil)
              |> put_flash(:info, "Ticket saved successfully")

            {:noreply, socket}

          {:error, message} ->
            socket = put_flash(socket, :error, message)
            {:noreply, socket}
        end
    end
  end

  # Handle ticket form updates
  @impl true
  def handle_event("update_pricing_model", %{"model" => model}, socket) do
    valid_models = ["fixed", "flexible", "donation"]
    validated_model = if model in valid_models, do: model, else: "fixed"

    updated_form_data = Map.put(socket.assigns.ticket_form_data, "pricing_model", validated_model)

    socket = assign(socket, :ticket_form_data, updated_form_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_zoom_meeting", _params, socket) do
    zoom_url = generate_zoom_meeting_url()

    # Update form data for virtual meeting
    form_data = (socket.assigns.form_data || %{})
    |> Map.put("virtual_venue_url", zoom_url)
    |> Map.put("is_virtual", true)
    |> Map.put("venue_name", "")
    |> Map.put("venue_address", "")
    |> Map.put("venue_city", "")
    |> Map.put("venue_state", "")
    |> Map.put("venue_country", "")
    |> Map.put("venue_latitude", nil)
    |> Map.put("venue_longitude", nil)

    # Update the changeset
    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:selected_venue_name, "Zoom Meeting")
      |> assign(:selected_venue_address, zoom_url)
      |> assign(:is_virtual, true)
      |> assign(:show_recent_locations, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_google_meet", _params, socket) do
    meet_url = generate_google_meet_url()

    # Update form data for virtual meeting
    form_data = (socket.assigns.form_data || %{})
    |> Map.put("virtual_venue_url", meet_url)
    |> Map.put("is_virtual", true)
    |> Map.put("venue_name", "")
    |> Map.put("venue_address", "")
    |> Map.put("venue_city", "")
    |> Map.put("venue_state", "")
    |> Map.put("venue_country", "")
    |> Map.put("venue_latitude", nil)
    |> Map.put("venue_longitude", nil)

    # Update the changeset
    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:selected_venue_name, "Google Meet")
      |> assign(:selected_venue_address, meet_url)
      |> assign(:is_virtual, true)
      |> assign(:show_recent_locations, false)

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

  # Validation helper for flexible pricing
  defp validate_flexible_pricing(ticket_data, pricing_model, price_cents) do
    case pricing_model do
      "flexible" ->
        minimum_price_cents = case parse_currency(Map.get(ticket_data, "minimum_price", "0")) do
          nil -> 0
          cents -> cents
        end

        suggested_price_cents = case parse_currency(Map.get(ticket_data, "suggested_price", "")) do
          nil -> price_cents  # Default to base price if not provided
          cents -> cents
        end

        cond do
          minimum_price_cents < 0 ->
            {:error, "Minimum price cannot be negative"}

          minimum_price_cents > price_cents ->
            {:error, "Minimum price cannot be higher than base price"}

          suggested_price_cents < minimum_price_cents ->
            {:error, "Suggested price cannot be lower than minimum price"}

          suggested_price_cents > price_cents ->
            {:error, "Suggested price cannot be higher than base price"}

          true ->
            {:ok, minimum_price_cents, suggested_price_cents}
        end

      _ ->
        # For fixed/dynamic pricing, minimum equals base price
        {:ok, price_cents, price_cents}
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

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
    |> process_date_polling_datetime()
    |> process_start_datetime()
    |> process_end_datetime()
  end

  defp process_date_polling_datetime(params) do
    # If date polling is enabled, calculate average date and set start_at/ends_at
    if Map.get(params, "enable_date_polling", false) do
      case Map.get(params, "selected_poll_dates") do
        dates_string when is_binary(dates_string) and dates_string != "" ->
          # Parse the comma-separated date strings
          selected_dates =
            dates_string
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.filter(&(&1 != ""))
            |> Enum.map(&Date.from_iso8601!/1)
            |> Enum.sort()

          if length(selected_dates) > 0 do
            # Calculate the middle date (median)
            middle_index = div(length(selected_dates), 2)
            middle_date = Enum.at(selected_dates, middle_index)

            # Get start and end times
            start_time = Map.get(params, "start_time", "09:00")
            end_time = Map.get(params, "ends_time", "17:00")
            timezone = Map.get(params, "timezone", "UTC")

            # Create start_at datetime using middle date and start time
            case combine_date_time(Date.to_iso8601(middle_date), start_time, timezone) do
              {:ok, start_datetime} ->
                # Create ends_at datetime using middle date and end time
                case combine_date_time(Date.to_iso8601(middle_date), end_time, timezone) do
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
      params
    end
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
    # Only create date polls if polling is explicitly enabled
    enable_date_polling = Map.get(form_data, "enable_date_polling", false)
    is_polling_enabled = enable_date_polling == true or enable_date_polling == "true"

    unless is_polling_enabled do
      # If polling is not enabled, just return the original event
      {:ok, event}
    else
      # Check if we have selected poll dates (new calendar approach)
      case Map.get(form_data, "selected_poll_dates") do
        dates_string when is_binary(dates_string) and dates_string != "" ->
          # Parse the comma-separated date strings
          selected_dates =
            dates_string
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.filter(&(&1 != ""))
            |> Enum.map(&Date.from_iso8601!/1)
            |> Enum.sort()

          # Create the date poll
          case Events.create_event_date_poll(event, user, %{voting_deadline: nil}) do
            {:ok, poll} ->
              # Create date options for each selected date
                            case Events.create_date_options_from_list(poll, selected_dates) do
                  {:ok, _options} ->
                    # Update event state to 'polling'
                    case Events.update_event(event, %{status: "polling", polling_deadline: DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)}) do
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

        _ ->
          # Fall back to old date range approach if no selected dates
          start_date_str = Map.get(form_data, "start_date")
          end_date_str = Map.get(form_data, "ends_date")

          if start_date_str && end_date_str do
            start_date = Date.from_iso8601!(start_date_str)
            end_date = Date.from_iso8601!(end_date_str)

            # Create the date poll
            case Events.create_event_date_poll(event, user, %{voting_deadline: nil}) do
              {:ok, poll} ->
                # Create date options for each day in the range
                case Events.create_date_options_from_range(poll, start_date, end_date) do
                  {:ok, _options} ->
                    # Update event state to 'polling'
                    case Events.update_event(event, %{status: "polling", polling_deadline: DateTime.add(DateTime.utc_now(), 7 * 24 * 60 * 60, :second)}) do
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
          else
            {:error, :missing_date_data}
          end
      end
    end
  end

  # Helper function to create event with proper error handling
  defp create_event_with_validation(final_event_params, socket) do
    # Set the correct status based on setup path
    setup_path = Map.get(socket.assigns.form_data, "setup_path", "confirmed")
    enable_date_polling = Map.get(final_event_params, "enable_date_polling", false)
    is_polling_enabled = enable_date_polling == true or enable_date_polling == "true"

    # Determine the correct status
    final_status = cond do
      is_polling_enabled or setup_path == "polling" -> "polling"
      setup_path == "threshold" -> "threshold"
      true -> "confirmed"  # Default for confirmed events
    end

    # Ensure the status is correctly set in the event params
    final_event_params_with_status = Map.put(final_event_params, "status", final_status)

    case Events.create_event_with_organizer(final_event_params_with_status, socket.assigns.user) do
      {:ok, event} ->
        # If date polling is enabled, create the date poll and options
        event_with_poll = if Map.get(final_event_params, "enable_date_polling", false) do
          case create_date_poll_for_event(event, final_event_params, socket.assigns.user) do
            {:ok, updated_event} -> updated_event
            {:error, _} -> event # Fall back to original event if poll creation fails
          end
        else
          event
        end

        # If ticketing is enabled, create the tickets
        is_ticketed? = final_event_params["is_ticketed"] in [true, "true"]

        case is_ticketed? and length(socket.assigns.tickets) > 0 do
          true ->
            case create_tickets_for_event(event_with_poll, socket.assigns.tickets, socket.assigns.user) do
              :ok ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Event created successfully")
                 |> redirect(to: ~p"/events/#{event_with_poll.slug}")}
              {:error, changeset} ->
                # Log the error and flash a warning to the user
                require Logger
                Logger.error("Failed to create tickets for event: #{inspect(changeset)}")
                {:noreply,
                 socket
                 |> put_flash(:error, "Event created but tickets could not be created. Please edit the event to add tickets.")
                 |> redirect(to: ~p"/events/#{event_with_poll.slug}")}
            end
          false ->
            {:noreply,
             socket
             |> put_flash(:info, "Event created successfully")
             |> redirect(to: ~p"/events/#{event_with_poll.slug}")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger
        Logger.error("[submit] Event creation failed with changeset errors: #{inspect(changeset.errors)}")
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Helper function to create tickets for an event
  defp create_tickets_for_event(event, tickets, organizer_user) do
    alias EventasaurusApp.Ticketing
    alias EventasaurusApp.Repo

    # Use a transaction to ensure all tickets are created atomically
    Repo.transaction(fn ->
      Enum.each(tickets, fn ticket_data ->
        # Get organizer's default currency as fallback
        # Use the passed organizer_user or fall back to USD
        default_currency = case organizer_user do
          %{default_currency: _} = user -> get_currency_with_fallback(user)
          _ -> "usd"
        end

        ticket_attrs = %{
          title: Map.get(ticket_data, :title),
          description: Map.get(ticket_data, :description),
          pricing_model: Map.get(ticket_data, :pricing_model, "fixed"),
          base_price_cents: Map.get(ticket_data, :base_price_cents),
          minimum_price_cents: Map.get(ticket_data, :minimum_price_cents) || Map.get(ticket_data, :base_price_cents),
          suggested_price_cents: Map.get(ticket_data, :suggested_price_cents),
          currency: Map.get(ticket_data, :currency, default_currency),
          quantity: Map.get(ticket_data, :quantity),
          starts_at: Map.get(ticket_data, :starts_at),
          ends_at: Map.get(ticket_data, :ends_at),
          tippable: Map.get(ticket_data, :tippable)
        }

        case Ticketing.create_ticket(event, ticket_attrs) do
          {:ok, _ticket} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
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

  # ============================================================================
  # Ticketing Helper Functions
  # ============================================================================

  # Helper function to get user's default currency with fallback to USD
  defp get_currency_with_fallback(user) do
    case user.default_currency do
      currency when currency not in [nil, ""] -> currency
      _ -> "usd"
    end
  end

  defp format_datetime_for_input(nil), do: ""
  defp format_datetime_for_input(%DateTime{} = datetime) do
    # Format as local datetime string for input
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
    |> String.replace("Z", "")
    |> String.replace("+00:00", "")
  end
  defp format_datetime_for_input(_), do: ""

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    # Handle different datetime formats more carefully
    cond do
      # If it already looks like a complete ISO8601 string, try parsing as-is
      String.contains?(datetime_str, "T") and (String.contains?(datetime_str, "Z") or String.contains?(datetime_str, "+")) ->
        case DateTime.from_iso8601(datetime_str) do
          {:ok, datetime, _} -> datetime
          {:error, _} -> nil
        end

      # If it's a local datetime format (YYYY-MM-DDTHH:MM), add seconds and Z
      String.contains?(datetime_str, "T") ->
        case DateTime.from_iso8601(datetime_str <> ":00Z") do
          {:ok, datetime, _} -> datetime
          {:error, _} -> nil
        end

      # Otherwise, it's not a valid datetime format
      true -> nil
    end
  end
  defp parse_datetime(_), do: nil

  # Helper — clears ticket state unless the path is ticket-centric
  defp maybe_reset_ticketing(socket, path) when path in ["confirmed", "threshold"], do: socket
  defp maybe_reset_ticketing(socket, _path) do
    socket
    |> assign(:tickets, [])
    |> assign(:show_ticket_modal, false)
    |> assign(:ticket_form_data, %{})
    |> assign(:editing_ticket_id, nil)
  end

  # Helper function to filter locations based on search query
  defp filter_locations(locations, query) when is_binary(query) and byte_size(query) > 0 do
    query_lower = String.downcase(query)

    Enum.filter(locations, fn location ->
      # Check name (handle virtual events)
      name_match = case location do
        %{virtual_venue_url: url} when not is_nil(url) ->
          String.contains?("virtual meeting", query_lower) or
          String.contains?(String.downcase(url), query_lower)
        _ ->
          location.name && String.contains?(String.downcase(location.name), query_lower)
      end

      # Check address
      address_match = location.address &&
        String.contains?(String.downcase(location.address), query_lower)

      # Check city
      city_match = location.city &&
        String.contains?(String.downcase(location.city), query_lower)

      name_match || address_match || city_match
    end)
  end

  defp filter_locations(locations, _query), do: locations

  # Helper functions to generate virtual meeting URLs
  defp generate_zoom_meeting_url do
    meeting_id = generate_random_meeting_id(11) # Zoom meeting IDs are typically 11 digits
    "https://zoom.us/j/#{meeting_id}"
  end

  defp generate_google_meet_url do
    meeting_id = generate_random_meeting_id(10, :alphanum) # Google Meet uses alphanumeric codes
    "https://meet.google.com/#{meeting_id}"
  end

  defp generate_random_meeting_id(length, type \\ :numeric) do
    case type do
      :numeric ->
        1..length
        |> Enum.map(fn _ -> Enum.random(0..9) end)
        |> Enum.join("")

      :alphanum ->
        chars = "abcdefghijklmnopqrstuvwxyz"
        1..length
        |> Enum.map(fn _ ->
          case rem(Enum.random(1..36), 2) do
            0 -> Enum.random(0..9) |> to_string()
            1 -> String.at(chars, Enum.random(0..25))
          end
        end)
        |> Enum.join("")
        |> String.replace(~r/(.{3})(.{4})(.{3})/, "\\1-\\2-\\3") # Add hyphens for Google Meet format
    end
  end

end
