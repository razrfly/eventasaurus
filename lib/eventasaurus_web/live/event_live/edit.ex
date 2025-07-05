defmodule EventasaurusWeb.EventLive.Edit do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.LiveHelpers
  import EventasaurusWeb.Components.ImagePickerModal
  import EventasaurusWeb.Components.TicketModal
  import EventasaurusWeb.Helpers.CurrencyHelpers


  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.Services.UnsplashService
  alias EventasaurusWeb.Services.SearchService
  alias EventasaurusWeb.Services.DefaultImagesService
  alias EventasaurusApp.Ticketing

  @valid_setup_paths ~w[polling confirmed threshold]

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

            # Extract polling deadline date and time if date polling is enabled
            {polling_deadline_date, polling_deadline_time} =
              if enable_date_polling do
                if event.polling_deadline do
                  parse_datetime_with_timezone(event.polling_deadline, event.timezone)
                else
                  # Default to one week from today at 22:00 in the event's timezone
                  default_date = Date.add(Date.utc_today(), 7) |> Date.to_iso8601()
                  {default_date, "22:00"}
                end
              else
                {nil, nil}
              end

            # Determine setup path based on existing event properties
            setup_path = cond do
              enable_date_polling -> "polling"
              event.is_ticketed && Map.get(event, :requires_threshold, false) -> "threshold"
              event.is_ticketed && !Map.get(event, :requires_threshold, false) -> "confirmed"
              true -> "confirmed"
            end

            # Load existing tickets for the event
            existing_tickets = Ticketing.list_tickets_for_event(event.id)

            # Fix is_ticketed flag based on actual ticket existence
            actual_is_ticketed = length(existing_tickets) > 0

            # Load recent locations for the user (excluding current event)
            recent_locations = Events.get_recent_locations_for_user(user.id,
              limit: 5,
              exclude_event_ids: [event.id]
            )

            # Set up the socket with all required assigns
            socket =
              socket
              |> assign(:event, event)
              |> assign(:venues, venues)
              |> assign(:form, to_form(changeset))
              |> assign(:changeset, changeset)
              |> assign(:user, user)
              |> assign(:form_data, %{
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
                "selected_poll_dates" => selected_poll_dates,
                "polling_deadline" => if(event.polling_deadline, do: DateTime.to_iso8601(event.polling_deadline), else: ""),
                "polling_deadline_date" => polling_deadline_date,
                "polling_deadline_time" => polling_deadline_time,
                "is_ticketed" => actual_is_ticketed,
                "setup_path" => setup_path,
                "requires_threshold" => Map.get(event, :requires_threshold, false),
                "taxation_type" => determine_edit_taxation_default(event),
                "taxation_type_reasoning" => get_taxation_reasoning_for_edit(event)
              })
              |> assign(:is_virtual, is_virtual)
              |> assign(:selected_venue_name, venue_name)
              |> assign(:selected_venue_address, venue_address)
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
              |> assign(:setup_path, setup_path)
              |> assign(:mode, "compact")
              |> assign(:show_stage_transitions, false)
              |> assign(:selected_category, "general")
              |> assign(:default_categories, DefaultImagesService.get_categories())
              |> assign(:default_images, DefaultImagesService.get_images_for_category("general"))
              |> assign(:supabase_access_token, "edit_token_#{user.id}")
              # Ticketing assigns
              |> assign(:tickets, existing_tickets)
              |> assign(:show_ticket_modal, false)
              |> assign(:ticket_form_data, %{})
              |> assign(:editing_ticket_id, nil)
              |> assign(:show_additional_options, false)
              # Recent locations assigns
              |> assign(:recent_locations, recent_locations)
              |> assign(:show_recent_locations, false)
              |> assign(:filtered_recent_locations, recent_locations)

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
  def handle_event("select_setup_path", %{"path" => path}, socket) when path in @valid_setup_paths do
    socket = apply_setup_path(socket, path) |> assign(:show_stage_transitions, false)

    # Update the changeset with the new form data to ensure the form component reflects the changes
    changeset =
      socket.assigns.event
      |> Events.change_event(socket.assigns.form_data)
      |> Map.put(:action, :validate)

    socket = assign(socket, form: to_form(changeset))
    {:noreply, socket}
  end

  def handle_event("select_setup_path", _params, socket),
    do: {:noreply, socket}  # ignore unknown values

  @impl true
  def handle_event("show_stage_transitions", _params, socket) do
    {:noreply, assign(socket, :show_stage_transitions, true)}
  end

  @impl true
  def handle_event("hide_stage_transitions", _params, socket) do
    {:noreply, assign(socket, :show_stage_transitions, false)}
  end

  @impl true
  def handle_event("transition_to_stage", %{"stage" => stage}, socket) when stage in @valid_setup_paths do
    socket = apply_setup_path(socket, stage) |> assign(:show_stage_transitions, false)

    # Update the changeset with the new form data to ensure the form component reflects the changes
    changeset =
      socket.assigns.event
      |> Events.change_event(socket.assigns.form_data)
      |> Map.put(:action, :validate)

    socket = assign(socket, form: to_form(changeset))
    {:noreply, socket}
  end

  def handle_event("transition_to_stage", _params, socket),
    do: {:noreply, socket}  # ignore unknown values

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
    require Logger
    Logger.info("=== SUBMIT EVENT HANDLER CALLED ===")
    Logger.info("Event params keys: #{inspect(Map.keys(event_params))}")

    # Apply taxation consistency logic before further processing
    event_params = apply_taxation_consistency(event_params)
    Logger.info("Taxation consistency applied: #{inspect(Map.take(event_params, ["taxation_type", "is_ticketed"]))}")

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

    # Handle status transition based on enable_date_polling
    final_event_params = case Map.get(final_event_params, "enable_date_polling") do
      polling when polling == true or polling == "true" ->
        # Switching to or staying in polling mode
        Map.put(final_event_params, "status", "polling")
      _ ->
        # Switching to or staying in confirmed mode
        # Remove polling-specific fields that are no longer needed
        final_event_params
        |> Map.put("status", "confirmed")
        |> Map.put("polling_deadline", nil)
        |> Map.delete("selected_poll_dates")  # Remove form-only field from params
    end

    # Validate date polling before saving
    validation_changeset =
      socket.assigns.event
      |> Events.change_event(final_event_params)
      |> Map.put(:action, :validate)
      |> validate_date_polling(final_event_params)
      # Add validation to prevent ticketless when tickets exist
      |> Events.Event.validate_tickets_taxation_consistency(length(socket.assigns.tickets || []))

    Logger.info("=== VALIDATION STEP ===")
    Logger.info("Validation changeset valid?: #{validation_changeset.valid?}")
    Logger.info("Validation errors: #{inspect(validation_changeset.errors)}")

    if validation_changeset.valid? do
      Logger.info("Validation passed, calling Events.update_event")

      # Handle date polling updates if needed - early return on error
      case handle_date_polling_update(socket, final_event_params) do
        {:ok, socket} ->
          # Continue with event update
          case Events.update_event(socket.assigns.event, final_event_params) do
            {:ok, event} ->
              {:noreply,
               socket
               |> put_flash(:info, "Event updated successfully")
               |> redirect(to: ~p"/events/#{event.slug}")}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:noreply, assign(socket, form: to_form(changeset))}
          end

        {:error, error_socket} ->
          # Early return on date polling error
          {:noreply, error_socket}
      end
    else
      Logger.info("Validation failed, not calling Events.update_event")
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
    |> assign(:show_recent_locations, false)

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

  # ============================================================================
  # Ticketing Event Handlers
  # ============================================================================

  @impl true
  def handle_event("toggle_ticketing", _params, socket) do
    current_value = Map.get(socket.assigns.form_data, "is_ticketed", false)
    # Handle both string and boolean values
    current_bool = current_value in [true, "true"]
    new_value = !current_bool

    # Update form_data with smart taxation type changes
    form_data = socket.assigns.form_data
    |> Map.put("is_ticketed", new_value)
    |> update_taxation_for_ticketing_change(new_value)

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
    require Logger
    Logger.debug("Setting show_ticket_modal to true")

    socket =
      socket
      |> assign(:show_ticket_modal, true)
      |> assign(:ticket_form_data, %{"currency" => "usd"})
      |> assign(:editing_ticket_id, nil)

    Logger.debug("show_ticket_modal is now: #{socket.assigns.show_ticket_modal}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("edit_ticket", %{"id" => ticket_id_str}, socket) do
    ticket = case Integer.parse(ticket_id_str) do
      {id, ""} -> Enum.find(socket.assigns.tickets, &(&1.id == id))
      _ -> Enum.find(socket.assigns.tickets, &(to_string(&1.id) == ticket_id_str))
    end

    if ticket do
      form_data = %{
        "title" => ticket.title,
        "description" => ticket.description || "",
        "pricing_model" => Map.get(ticket, :pricing_model, "fixed"),
        "price" => format_price_from_cents(ticket.base_price_cents),
        "minimum_price" => format_price_from_cents(Map.get(ticket, :minimum_price_cents, 0)),
        "suggested_price" => format_price_from_cents(Map.get(ticket, :suggested_price_cents, ticket.base_price_cents)),
        "currency" => Map.get(ticket, :currency, "usd"),
        "quantity" => Integer.to_string(ticket.quantity),
        "starts_at" => format_datetime_for_input(ticket.starts_at),
        "ends_at" => format_datetime_for_input(ticket.ends_at),
        "tippable" => ticket.tippable
      }

      socket =
        socket
        |> assign(:show_ticket_modal, true)
        |> assign(:ticket_form_data, form_data)
        |> assign(:editing_ticket_id, ticket.id)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_ticket", %{"id" => ticket_id_str}, socket) do
    ticket = case Integer.parse(ticket_id_str) do
      {id, ""} -> Enum.find(socket.assigns.tickets, &(&1.id == id))
      _ -> Enum.find(socket.assigns.tickets, &(to_string(&1.id) == ticket_id_str))
    end

    if ticket && Map.has_key?(ticket, :id) do
      # This is an existing ticket in the database, delete it
      case Ticketing.delete_ticket(ticket) do
        {:ok, _} ->
          # Reload tickets from database to ensure consistency
          updated_tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)
          socket =
            socket
            |> assign(:tickets, updated_tickets)
            |> put_flash(:info, "🗑️ Ticket deleted successfully")
          {:noreply, socket}
        {:error, _} ->
          socket = put_flash(socket, :error, "❌ Failed to delete ticket")
          {:noreply, socket}
      end
    else
      # This is a new ticket not yet saved, just remove from list (shouldn't happen with ID-based approach)
      updated_tickets = if ticket do
        Enum.reject(socket.assigns.tickets, &(&1 == ticket))
      else
        socket.assigns.tickets
      end
      socket = assign(socket, :tickets, updated_tickets)
      {:noreply, socket}
    end
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
  def handle_event("validate_ticket", %{"_target" => ["ticket", "tippable"]}, socket) do
    # Handle checkbox unchecked case - when checkbox is unchecked, only _target is sent
    current_data = socket.assigns.ticket_form_data || %{}
    updated_data = Map.put(current_data, "tippable", false)

    socket = assign(socket, :ticket_form_data, updated_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_ticket", %{"ticket" => ticket_params}, socket) do
    # Update the ticket form data, preserving existing values
    current_data = socket.assigns.ticket_form_data || %{}

    # Handle checkbox properly - normalize the value based on what's actually sent
    updated_params = if Map.has_key?(ticket_params, "tippable") do
      # Checkbox is checked - normalize various truthy values
      tippable_value = Map.get(ticket_params, "tippable")
      normalized_tippable = tippable_value in [true, "true", "on"]
      Map.put(ticket_params, "tippable", normalized_tippable)
    else
      # Checkbox key is missing - preserve existing value
      Map.put(ticket_params, "tippable", Map.get(current_data, "tippable", false))
    end

    updated_data = Map.merge(current_data, updated_params)
    socket = assign(socket, :ticket_form_data, updated_data)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_ticket", _params, socket) do
    # Catch-all for any other validate_ticket events
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
        case parse_currency(Map.get(ticket_data, "price", "0")) do
          nil ->
            socket = put_flash(socket, :error, "Invalid price format")
            {:noreply, socket}

          price_cents ->
            pricing_model = Map.get(ticket_data, "pricing_model", "fixed")

            # Validate flexible pricing fields
            case validate_flexible_pricing(ticket_data, pricing_model, price_cents) do
              {:ok, minimum_price_cents, suggested_price_cents} ->
                ticket_attrs = %{
                  title: Map.get(ticket_data, "title", ""),
                  description: Map.get(ticket_data, "description"),
                  pricing_model: pricing_model,
                  base_price_cents: price_cents,
                  minimum_price_cents: minimum_price_cents,
                  suggested_price_cents: suggested_price_cents,
                  currency: Map.get(ticket_data, "currency", "usd"),
                  quantity: case Integer.parse(Map.get(ticket_data, "quantity", "0")) do
                    {n, _} when n >= 0 -> n
                    _ -> 0
                  end,
                  starts_at: parse_datetime_input(Map.get(ticket_data, "starts_at")),
                  ends_at: parse_datetime_input(Map.get(ticket_data, "ends_at")),
                  tippable: Map.get(ticket_data, "tippable", false) == true
                }

                # Create or update ticket in the database
                result = case socket.assigns.editing_ticket_id do
                  nil ->
                    # Creating new ticket - persist to database immediately
                    EventasaurusApp.Ticketing.create_ticket(socket.assigns.event, ticket_attrs)
                  ticket_id ->
                    # Updating existing ticket - find it by ID and update it
                    existing_ticket = Enum.find(socket.assigns.tickets, &(&1.id == ticket_id))
                    if existing_ticket && Map.has_key?(existing_ticket, :id) do
                      # This is a persisted ticket, update it in the database
                      EventasaurusApp.Ticketing.update_ticket(existing_ticket, ticket_attrs)
                    else
                      # This shouldn't happen with ID-based approach, but create as fallback
                      EventasaurusApp.Ticketing.create_ticket(socket.assigns.event, ticket_attrs)
                    end
                end

                case result do
                  {:ok, _ticket} ->
                    # Reload tickets from database to ensure consistency
                    updated_tickets = EventasaurusApp.Ticketing.list_tickets_for_event(socket.assigns.event.id)

                    socket =
                      socket
                      |> assign(:tickets, updated_tickets)
                      |> assign(:show_ticket_modal, false)
                      |> assign(:ticket_form_data, %{})
                      |> assign(:editing_ticket_id, nil)
                      |> put_flash(:info, "🎉 Success! Ticket saved successfully")

                    {:noreply, socket}

                  {:error, changeset} ->
                    error_message =
                      changeset
                      |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
                        Enum.reduce(opts, msg, fn {key, value}, acc ->
                          String.replace(acc, "%{#{key}}", to_string(value))
                        end)
                      end)
                      |> Enum.flat_map(fn {field, msgs} ->
                        Enum.map(msgs, &("#{field} #{&1}"))
                      end)
                      |> case do
                        [] -> "Failed to save ticket"
                        errors -> Enum.join(errors, ", ")
                      end

                    socket = put_flash(socket, :error, "❌ Error: #{error_message}")
                    {:noreply, socket}
                end

              {:error, message} ->
                socket = put_flash(socket, :error, message)
                {:noreply, socket}
            end
        end
    end
  end

  @impl true
  def handle_event("update_pricing_model", %{"model" => model}, socket) do
    updated_form_data = Map.put(socket.assigns.ticket_form_data, "pricing_model", model)

    socket = assign(socket, :ticket_form_data, updated_form_data)
    {:noreply, socket}
  end

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
  def handle_event("enable_google_places", _params, socket) do
    {:noreply, push_event(socket, "enable_google_places", %{})}
  end

  @impl true
  def handle_event("select_recent_location", %{"location" => location_json}, socket) do
    # Parse the JSON data with error handling
    location_data = case Jason.decode(location_json) do
      {:ok, data} -> data
      {:error, _} -> %{}
    end

    # Handle physical venue (virtual events are excluded from recent locations)
    venue_name = Map.get(location_data, "name", "")
    venue_address = Map.get(location_data, "address", "")

    form_data_updates = %{
      "venue_name" => venue_name,
      "venue_address" => venue_address,
      "venue_city" => Map.get(location_data, "city", ""),
      "venue_state" => Map.get(location_data, "state", ""),
      "venue_country" => Map.get(location_data, "country", ""),
      "venue_latitude" => Map.get(location_data, "latitude"),
      "venue_longitude" => Map.get(location_data, "longitude"),
      "virtual_venue_url" => "",
      "is_virtual" => false
    }

    # Update form data while preserving existing data
    form_data = Map.merge(socket.assigns.form_data || %{}, form_data_updates)

    # Update the changeset
    changeset =
      socket.assigns.event
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
  def handle_event("filter_recent_locations", %{"query" => query}, socket) do
    filtered_locations = EventasaurusWeb.Helpers.EventHelpers.filter_locations(socket.assigns.recent_locations, query)
    {:noreply, assign(socket, :filtered_recent_locations, filtered_locations)}
  end

  @impl true
  def handle_event("create_zoom_meeting", _params, socket) do
    {:noreply, create_virtual_meeting(socket, :zoom)}
  end

  @impl true
  def handle_event("create_google_meet", _params, socket) do
    {:noreply, create_virtual_meeting(socket, :google_meet)}
  end

  defp create_virtual_meeting(socket, meeting_type) do
    {url, label} = case meeting_type do
      :zoom ->
        {EventasaurusWeb.Helpers.EventHelpers.generate_zoom_meeting_url(), "Zoom Meeting"}
      :google_meet ->
        {EventasaurusWeb.Helpers.EventHelpers.generate_google_meet_url(), "Google Meet"}
    end

    form_data = Map.merge(socket.assigns.form_data || %{}, %{
      "virtual_venue_url" => url,
      "is_virtual"        => true,
      "venue_name"        => "",
      "venue_address"     => "",
      "venue_city"        => "",
      "venue_state"       => "",
      "venue_country"     => "",
      "venue_latitude"    => nil,
      "venue_longitude"   => nil
    })

    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket
    |> assign(:form_data, form_data)
    |> assign(:changeset, changeset)
    |> assign(:selected_venue_name, label)
    |> assign(:selected_venue_address, url)
    |> assign(:is_virtual, true)
    |> assign(:show_recent_locations, false)
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



  # ============================================================================
  # Ticketing Helper Functions
  # ============================================================================

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

  defp parse_datetime_input(nil), do: nil
  defp parse_datetime_input(""), do: nil
  defp parse_datetime_input(datetime_str) when is_binary(datetime_str) do
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
  defp parse_datetime_input(_), do: nil

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
    require Logger
    Logger.info("=== VALIDATE DATE POLLING START ===")

    enable_date_polling = Map.get(params, "enable_date_polling", false)
    Logger.info("Raw enable_date_polling: #{inspect(enable_date_polling)}")

    # Handle string "true"/"false" from form submissions
    is_polling_enabled = enable_date_polling == true or enable_date_polling == "true"
    Logger.info("Is polling enabled: #{is_polling_enabled}")

    if is_polling_enabled do
      selected_dates_string = Map.get(params, "selected_poll_dates", "")
      Logger.info("Selected dates string: #{inspect(selected_dates_string)}")

      if selected_dates_string == "" do
        Logger.info("No dates selected, adding error")
        Ecto.Changeset.add_error(changeset, :selected_poll_dates, "must select at least 2 dates for polling")
      else
        selected_dates =
          selected_dates_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))

        Logger.info("Parsed selected dates: #{inspect(selected_dates)}")
        Logger.info("Number of dates: #{length(selected_dates)}")

        if length(selected_dates) < 2 do
          Logger.info("Less than 2 dates, adding error")
          Ecto.Changeset.add_error(changeset, :selected_poll_dates, "must select at least 2 dates for polling")
        else
          Logger.info("Validation passed")
          changeset
        end
      end
    else
      Logger.info("Polling not enabled, skipping validation")
      changeset
    end
  end

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

  # Helper function to combine date and time fields into UTC datetime
  defp combine_date_time_fields(params) do
    timezone = Map.get(params, "timezone", "UTC")

    # Handle polling deadline if present
    params = case {Map.get(params, "polling_deadline_date"), Map.get(params, "polling_deadline_time")} do
      {date_str, time_str} when is_binary(date_str) and is_binary(time_str) and date_str != "" and time_str != "" ->
        case combine_date_time_to_utc(date_str, time_str, timezone) do
          {:ok, datetime} -> Map.put(params, "polling_deadline", datetime)
          {:error, _} -> params
        end
      _ ->
        # Only clear polling deadline if date polling is explicitly disabled
        if Map.get(params, "enable_date_polling") == "false" do
          Map.put(params, "polling_deadline", nil)
        else
          params
        end
    end
    |> Map.drop(["polling_deadline_date", "polling_deadline_time"])  # Remove helper keys to prevent leakage

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

  defp handle_date_polling_update(socket, final_event_params) do
    event = socket.assigns.event
    enable_date_polling = Map.get(final_event_params, "enable_date_polling", false)

    # Handle string "true"/"false" from form submissions
    is_polling_enabled = enable_date_polling == true or enable_date_polling == "true"

    if is_polling_enabled do
      # Get selected dates and polling deadline
      selected_dates_string = Map.get(final_event_params, "selected_poll_dates", "")
      polling_deadline = Map.get(final_event_params, "polling_deadline")

      if selected_dates_string != "" and polling_deadline do
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

        if length(selected_dates) >= 2 do
          # Create or update date poll
          case Events.get_event_date_poll(event) do
            nil ->
              # Create new date poll
              case Events.create_event_date_poll(event, socket.assigns.user, %{
                voting_deadline: polling_deadline
              }) do
                {:ok, poll} ->
                  # Add date options
                  case Events.create_date_options_from_list(poll, selected_dates) do
                    {:ok, _options} -> {:ok, socket}
                    {:error, _} ->
                      socket = put_flash(socket, :error, "Failed to create date options")
                      {:error, socket}
                  end
                {:error, _} ->
                  socket = put_flash(socket, :error, "Failed to create date poll")
                  {:error, socket}
              end

            existing_poll ->
              # Update existing poll
              case Events.update_event_date_poll(existing_poll, %{
                voting_deadline: polling_deadline
              }) do
                {:ok, updated_poll} ->
                  # Update date options
                  case Events.update_event_date_options(updated_poll, selected_dates) do
                    {:ok, _options} -> {:ok, socket}
                    {:error, _} ->
                      socket = put_flash(socket, :error, "Failed to update date options")
                      {:error, socket}
                  end
                {:error, _} ->
                  socket = put_flash(socket, :error, "Failed to update date poll")
                  {:error, socket}
              end
          end
        else
          socket = put_flash(socket, :error, "Please select at least 2 dates for polling")
          {:error, socket}
        end
      else
        {:ok, socket}
      end
    else
      # Date polling is disabled, remove any existing poll
      case Events.get_event_date_poll(event) do
        nil -> {:ok, socket}
        existing_poll ->
          case Events.delete_event_date_poll(existing_poll) do
            {:ok, _} -> {:ok, socket}
            {:error, _} ->
              socket = put_flash(socket, :error, "Failed to remove date poll")
              {:error, socket}
          end
      end
    end
  end

  # Helper — clears ticket state unless the path is ticket-centric
  defp maybe_reset_ticketing(socket, path) when path in ["confirmed", "threshold"], do: socket
  defp maybe_reset_ticketing(socket, _path) do
    socket
    |> assign(:tickets, [])
    |> assign(:show_ticket_modal, false)
    |> assign(:ticket_form_data, %{})
    |> assign(:editing_ticket_id, nil)
  end

  # Helper function to apply setup path changes to both form_data and socket assigns
  defp apply_setup_path(socket, path) do
    # Update form_data based on the selected path
    form_data =
      socket.assigns.form_data
      |> Map.put("setup_path", path)
      |> Map.put("enable_date_polling", path == "polling")
      |> Map.put("is_ticketed", path in ["confirmed", "threshold"])
      |> Map.put("requires_threshold", path == "threshold")

    # Update the socket with the new path and form data
    socket
    |> assign(:setup_path, path)
    |> assign(:enable_date_polling, path == "polling")
    |> assign(:is_ticketed, path in ["confirmed", "threshold"])
    |> assign(:requires_threshold, path == "threshold")
    |> assign(:form_data, form_data)
    |> maybe_reset_ticketing(path)
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
  # Smart Default Value Helpers for Edit Mode
  # ============================================================================

  # Determines smart default for taxation_type when editing existing events
  defp determine_edit_taxation_default(event) do
    # If event already has a taxation_type, use it
    if event.taxation_type && event.taxation_type != "" do
      event.taxation_type
    else
      # For existing events without taxation_type, infer from other characteristics
      cond do
        # If event has ticketing enabled, default to ticketed_event
        event.is_ticketed == true ->
          "ticketed_event"
        # If event has paid elements, still suggest ticketed_event
        has_paid_elements?(event) ->
          "ticketed_event"
        # Default fallback to ticketless
        true ->
          "ticketless"
      end
    end
  end

  # Provides reasoning for taxation type selection in edit mode
  defp get_taxation_reasoning_for_edit(event) do

    cond do
      # Event already has taxation_type set
      event.taxation_type && event.taxation_type != "" ->
        case event.taxation_type do
          "ticketless" -> "Currently ticketless - no payment processing needed"
          "ticketed_event" -> "Configured for standard ticketed events"
          "contribution_collection" -> "Configured for contribution-based events"
          _ -> "Custom taxation configuration"
        end

      # Inferred from event characteristics
      event.is_ticketed == true ->
        "Recommended because ticketing is enabled for this event"

      has_paid_elements?(event) ->
        "Suggested due to paid elements in this event"

      # Default reasoning
      true ->
        "Default setting for events without specific taxation requirements"
    end
  end

  # Helper to check if event has paid elements
  defp has_paid_elements?(event) do
    # Check if event has tickets or other paid components
    event.is_ticketed == true
  end



  # Updates taxation type when ticketing status changes
  # Note: With the new UX, this is less relevant since taxation is only shown when tickets exist
  defp update_taxation_for_ticketing_change(form_data, is_ticketed) do
    current_taxation = Map.get(form_data, "taxation_type", "ticketless")

    case {is_ticketed, current_taxation} do
      # If enabling ticketing and currently ticketless, change to ticketed_event
      {true, "ticketless"} ->
        form_data
        |> Map.put("taxation_type", "ticketed_event")
        |> Map.put("taxation_type_reasoning", "Changed to ticketed_event because tickets were added")

      # If disabling ticketing and currently ticketed_event, revert to ticketless
      {false, "ticketed_event"} ->
        form_data
        |> Map.put("taxation_type", "ticketless")
        |> Map.put("taxation_type_reasoning", "Reverted to ticketless since no tickets exist")

      # For contribution_collection, keep it even if ticketing disabled (donations don't require formal ticketing)
      {false, "contribution_collection"} ->
        form_data
        |> Map.put("taxation_type_reasoning", "Maintained contribution collection configuration")

      # Otherwise, keep current selection
      _ ->
        form_data
        |> Map.put("taxation_type_reasoning",
          case current_taxation do
            "ticketless" -> "No tickets exist - automatically ticketless"
            "ticketed_event" -> "Standard ticketed event configuration"
            "contribution_collection" -> "Contribution-based event configuration"
            _ -> "Current configuration maintained"
          end)
    end
  end

  defp apply_taxation_consistency(event_params) do
    taxation_type = Map.get(event_params, "taxation_type", "ticketless")
    is_ticketed = Map.get(event_params, "is_ticketed", false)

    # Normalize is_ticketed to boolean
    is_ticketed_bool = is_ticketed in [true, "true", "on"]

    case {taxation_type, is_ticketed_bool} do
      # Force is_ticketed to false for contribution_collection and ticketless
      {"contribution_collection", _} ->
        Map.put(event_params, "is_ticketed", false)
      {"ticketless", _} ->
        Map.put(event_params, "is_ticketed", false)
      # For ticketed_event, preserve the original value
      {"ticketed_event", _} ->
        Map.put(event_params, "is_ticketed", is_ticketed_bool)
      # Default case
      _ ->
        Map.put(event_params, "is_ticketed", is_ticketed_bool)
    end
  end

end
