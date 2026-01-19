defmodule EventasaurusWeb.EventLive.Edit do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.LiveHelpers
  import EventasaurusWeb.Components.ImagePickerModal
  import EventasaurusWeb.Components.TicketModal
  import EventasaurusWeb.Helpers.CurrencyHelpers
  import EventasaurusWeb.TokenHelpers, only: [get_current_valid_token: 1]

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Validations
  alias EventasaurusApp.Groups
  alias EventasaurusWeb.Services.UnsplashService
  alias EventasaurusWeb.Services.SearchService
  alias EventasaurusWeb.Services.DefaultImagesService
  alias EventasaurusApp.Ticketing
  alias EventasaurusWeb.Helpers.ImageHelpers
  alias EventasaurusWeb.Components.RichDataImportModal
  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusApp.DateTimeHelper
  alias EventasaurusWeb.EventLive.FormHelpers
  alias EventasaurusWeb.Utils.TimezoneUtils

  @valid_setup_paths ~w[polling confirmed threshold]

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    event = Events.get_event_by_slug(slug)

    if event do
      # Ensure we have a proper User struct for authorization
      case ensure_user_struct(socket.assigns[:auth_user]) do
        {:ok, user} ->
          # Check if user can edit this event
          if Events.user_can_manage_event?(user, event) do
            changeset = Events.change_event(event)

            # Convert the event to a changeset
            {start_date, start_time} =
              DateTimeHelper.format_for_form(event.start_at, event.timezone)

            {ends_date, ends_time} = DateTimeHelper.format_for_form(event.ends_at, event.timezone)

            # Check if this is a virtual event
            is_virtual = event.venue_id == nil

            # Load venue data from preloaded venue (already loaded by get_event_by_slug)
            {venue_name, venue_address, venue_city, venue_country, venue_latitude,
             venue_longitude} =
              case event.venue do
                nil ->
                  {nil, nil, nil, nil, nil, nil}

                venue ->
                  {
                    venue.name,
                    venue.address,
                    EventasaurusApp.Venues.Venue.city_name(venue),
                    EventasaurusApp.Venues.Venue.country_name(venue),
                    venue.latitude,
                    venue.longitude
                  }
              end

            # Determine setup path based on event status
            # Note: status may be atom or string, so normalize to string for comparison
            event_status_str = to_string(event.status)

            setup_path =
              cond do
                event_status_str == "threshold" -> "threshold"
                event_status_str == "polling" -> "polling"
                event_status_str == "draft" -> "confirmed"
                true -> "confirmed"
              end

            # Determine participation_type based on event state
            # Reuse event_status_str from above

            participation_type =
              cond do
                # Threshold events - check threshold type
                event_status_str == "threshold" && Map.get(event, :threshold_type) == "revenue" ->
                  "crowdfunding"

                event_status_str == "threshold" &&
                    Map.get(event, :threshold_type) == "attendee_count" ->
                  "interest"

                event_status_str == "threshold" ->
                  # Default threshold type
                  "crowdfunding"

                # Contribution-based events
                event.taxation_type == "contribution_collection" ->
                  "contribution"

                # Ticketed events
                event.is_ticketed == true ->
                  "ticketed"

                # Default to free
                true ->
                  "free"
              end

            # Load existing tickets for the event (needed for form state)
            existing_tickets = Ticketing.list_tickets_for_event(event.id)

            # Fix is_ticketed flag based on actual ticket existence
            actual_is_ticketed = length(existing_tickets) > 0

            # Set up the socket with all required assigns
            # Use assign_async for independent data that can load in parallel
            socket =
              socket
              |> assign(:event, event)
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
                "group_id" => event.group_id,
                "venue_name" => venue_name,
                "venue_address" => venue_address,
                "venue_city" => venue_city,
                "venue_country" => venue_country,
                "venue_latitude" => venue_latitude,
                "venue_longitude" => venue_longitude,
                "polling_deadline" =>
                  if(event.polling_deadline,
                    do: DateTime.to_iso8601(event.polling_deadline),
                    else: ""
                  ),
                "is_ticketed" => actual_is_ticketed,
                "setup_path" => setup_path,
                "requires_threshold" => Map.get(event, :requires_threshold, false),
                "taxation_type" => determine_edit_taxation_default(event),
                "taxation_type_reasoning" => get_taxation_reasoning_for_edit(event),
                "rich_external_data" => event.rich_external_data || %{},
                "participation_type" => participation_type
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
              |> assign(:enable_date_polling, false)
              |> assign(:setup_path, setup_path)
              |> assign(:participation_type, participation_type)
              |> assign(:mode, "compact")
              |> assign(:show_stage_transitions, false)
              |> assign(:selected_category, "general")
              |> assign(:default_categories, DefaultImagesService.get_categories())
              |> assign(:default_images, DefaultImagesService.get_images_for_category("general"))
              # Ticketing assigns
              |> assign(:tickets, existing_tickets)
              |> assign(:show_ticket_modal, false)
              |> assign(:ticket_form_data, %{})
              |> assign(:editing_ticket_id, nil)
              |> assign(:show_additional_options, false)
              # Recent locations - initialize with empty, will be loaded async
              |> assign(:recent_locations, [])
              |> assign(:show_recent_locations, false)
              |> assign(:filtered_recent_locations, [])
              # Rich data import assigns
              |> assign(:show_rich_data_import, false)
              |> assign(:rich_external_data, event.rich_external_data || %{})
              # User groups - load synchronously (fast query, needed for initial render)
              |> assign(:user_groups, Groups.list_user_groups(user))
              # Supabase token - initialize empty, will be loaded async
              |> assign(:supabase_access_token, "")
              |> assign_async(:async_recent_locations, fn ->
                locations =
                  Events.get_recent_locations_for_user(user.id,
                    limit: 5,
                    exclude_event_ids: [event.id]
                  )

                {:ok, %{async_recent_locations: locations}}
              end)
              |> assign_async(:async_supabase_token, fn ->
                token = get_current_valid_token(session)

                if is_nil(token) do
                  require Logger

                  Logger.warning(
                    "Supabase access token is nil for user #{user.id}. Image uploads will not work."
                  )
                end

                {:ok, %{async_supabase_token: token || ""}}
              end)

            {:ok, socket}
          else
            {:ok,
             socket
             |> put_flash(:error, "You don't have permission to edit this event")
             |> redirect(to: ~p"/dashboard")}
          end

        {:error, _} ->
          {:ok,
           socket
           |> put_flash(:error, "You must be logged in to edit events")
           |> redirect(to: ~p"/auth/login")}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "Event not found")
       |> redirect(to: ~p"/dashboard")}
    end
  end

  # ========== Event Handlers ==========

  @impl true
  def handle_event("select_setup_path", %{"path" => path}, socket)
      when path in @valid_setup_paths do
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
    # ignore unknown values
    do: {:noreply, socket}

  @impl true
  def handle_event("show_stage_transitions", _params, socket) do
    {:noreply, assign(socket, :show_stage_transitions, true)}
  end

  @impl true
  def handle_event("hide_stage_transitions", _params, socket) do
    {:noreply, assign(socket, :show_stage_transitions, false)}
  end

  @impl true
  def handle_event("transition_to_stage", %{"stage" => stage}, socket)
      when stage in @valid_setup_paths do
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
    # ignore unknown values
    do: {:noreply, socket}

  @impl true
  def handle_event(
        "update_date_certainty",
        %{"event" => %{"date_certainty" => date_certainty}},
        socket
      ) do
    current_event = socket.assigns.event

    # Validate transition is allowed
    case validate_date_certainty_transition(current_event, date_certainty) do
      :ok ->
        form_data = socket.assigns.form_data |> Map.put("date_certainty", date_certainty)
        changeset = Events.change_event(current_event, form_data) |> Map.put(:action, :validate)

        {:noreply,
         assign(socket,
           form_data: form_data,
           form: to_form(changeset)
         )}

      {:error, message} ->
        changeset =
          Events.change_event(current_event, socket.assigns.form_data)
          |> Ecto.Changeset.add_error(:date_certainty, message)
          |> Map.put(:action, :validate)

        socket =
          socket
          |> assign(form: to_form(changeset))
          |> put_flash(:error, message)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "update_venue_certainty",
        %{"event" => %{"venue_certainty" => venue_certainty}},
        socket
      ) do
    current_event = socket.assigns.event

    # Validate transition is allowed
    case validate_venue_certainty_transition(current_event, venue_certainty) do
      :ok ->
        # Set is_virtual based on venue_certainty selection
        is_virtual = venue_certainty == "virtual"

        form_data =
          socket.assigns.form_data
          |> Map.put("venue_certainty", venue_certainty)
          |> Map.put("is_virtual", is_virtual)

        changeset = Events.change_event(current_event, form_data) |> Map.put(:action, :validate)

        {:noreply,
         assign(socket,
           form_data: form_data,
           form: to_form(changeset),
           is_virtual: is_virtual
         )}

      {:error, message} ->
        changeset =
          Events.change_event(current_event, socket.assigns.form_data)
          |> Ecto.Changeset.add_error(:venue_certainty, message)
          |> Map.put(:action, :validate)

        socket =
          socket
          |> assign(form: to_form(changeset))
          |> put_flash(:error, message)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    changeset =
      socket.assigns.event
      |> Events.change_event(event_params)
      |> Validations.validate_for_draft()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
    # Map participation_type to proper event attributes (status, threshold_type, etc.)
    # This is critical for threshold/crowdfunding events to properly set the status
    participation_attrs = FormHelpers.resolve_event_attributes(event_params)

    # Merge the resolved attributes into event_params
    # participation_attrs contains: status, is_ticketed, taxation_type, threshold_type, etc.
    event_params = Map.merge(event_params, participation_attrs)

    # Map user-friendly threshold field names to database field names
    event_params = map_threshold_fields(event_params)

    # Apply taxation consistency logic before further processing
    event_params = apply_taxation_consistency(event_params)

    # Decode external_image_data if it's a JSON string
    event_params =
      case Map.get(event_params, "external_image_data") do
        nil ->
          event_params

        "" ->
          Map.put(event_params, "external_image_data", nil)

        json_string when is_binary(json_string) ->
          case Jason.decode(json_string) do
            {:ok, decoded_data} -> Map.put(event_params, "external_image_data", decoded_data)
            {:error, _} -> Map.put(event_params, "external_image_data", nil)
          end

        data when is_map(data) ->
          event_params
      end

    # Decode rich_external_data if it's a JSON string
    event_params =
      case Map.get(event_params, "rich_external_data") do
        nil ->
          event_params

        "" ->
          Map.put(event_params, "rich_external_data", %{})

        json_string when is_binary(json_string) ->
          case Jason.decode(json_string) do
            {:ok, decoded_data} -> Map.put(event_params, "rich_external_data", decoded_data)
            {:error, _} -> Map.put(event_params, "rich_external_data", %{})
          end

        data when is_map(data) ->
          event_params
      end

    # Combine date and time fields into proper UTC datetime values
    event_params = combine_date_time_fields(event_params)

    # Process venue data from the form submission params (not form_data)
    # Check if we have venue data in the submitted form params and user is not setting virtual
    venue_name = Map.get(event_params, "venue_name")
    venue_address = Map.get(event_params, "venue_address")
    is_virtual = Map.get(event_params, "is_virtual") == "true"

    params_with_venue =
      if (!is_virtual and venue_name) && venue_name != "" do
        venue_country = Map.get(event_params, "venue_country")

        # Convert country name to ISO code (e.g., "United States" -> "US")
        country_code =
          if venue_country && venue_country != "" do
            EventasaurusDiscovery.Locations.CountryResolver.get_code(venue_country)
          else
            nil
          end

        # Try to find existing venue or create new one using VenueStore normalization
        venue_attrs = %{
          name: venue_name,
          address: venue_address,
          city_name: Map.get(event_params, "venue_city"),
          country_code: country_code,
          latitude:
            case Map.get(event_params, "venue_latitude") do
              lat when is_binary(lat) and lat != "" ->
                case Float.parse(lat) do
                  {float_val, _} -> float_val
                  :error -> nil
                end

              lat ->
                lat
            end,
          longitude:
            case Map.get(event_params, "venue_longitude") do
              lng when is_binary(lng) and lng != "" ->
                case Float.parse(lng) do
                  {float_val, _} -> float_val
                  :error -> nil
                end

              lng ->
                lng
            end,
          venue_type: Map.get(event_params, "venue_type", "venue"),
          place_id: Map.get(event_params, "venue_place_id"),
          source:
            if Map.get(event_params, "venue_place_id") do
              "google"
            else
              "user"
            end
        }

        # Use VenueStore for proper city normalization
        case EventasaurusDiscovery.Locations.VenueStore.find_or_create_venue(venue_attrs) do
          {:ok, venue} ->
            Map.put(event_params, "venue_id", venue.id)

          {:error, reason} ->
            require Logger
            Logger.error("Failed to create venue in edit: #{inspect(reason)}")
            event_params
        end
      else
        # Virtual event or no venue data - clear venue_id
        Map.put(event_params, "venue_id", nil)
      end

    # Clean up venue-related fields that the Event changeset doesn't expect
    # Keep date polling fields for our custom logic
    final_event_params =
      params_with_venue
      |> Map.drop([
        "venue_name",
        "venue_address",
        "venue_city",
        "venue_state",
        "venue_country",
        "venue_latitude",
        "venue_longitude",
        "venue_type",
        "is_virtual",
        "start_date",
        "start_time",
        "ends_date",
        "ends_time"
      ])

    # Legacy status transition based on date polling removed - using generic polling system

    # Authorize group assignment if specified
    case validate_group_assignment(final_event_params, socket.assigns.user) do
      {:ok, authorized_params} ->
        # Apply full publish validations before saving
        validation_changeset =
          socket.assigns.event
          |> Events.change_event(authorized_params)
          |> Validations.validate_for_publish()
          |> Map.put(:action, :validate)

        if validation_changeset.valid? do
          case Events.update_event(socket.assigns.event, authorized_params) do
            {:ok, event} ->
              {:noreply,
               socket
               |> put_flash(:info, "Event updated successfully")
               |> redirect(to: ~p"/events/#{event.slug}")}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:noreply, assign(socket, form: to_form(changeset))}
          end
        else
          {:noreply,
           assign(socket,
             form: to_form(validation_changeset),
             changeset: validation_changeset
           )}
        end

      {:error, message} ->
        socket = put_flash(socket, :error, message)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("venue_selected", venue_data, socket) do
    # Extract venue data with defaults
    venue_name = Map.get(venue_data, "name", "")
    venue_address = Map.get(venue_data, "address", "")

    # Update form data with venue information while preserving existing data
    form_data =
      (socket.assigns.form_data || %{})
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

  # Legacy toggle_date_polling handler removed - using generic polling system

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
     |> do_unified_search()}
  end

  @impl true
  def handle_event("unified_search", %{"search_query" => query}, socket) when query == "" do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, %{unsplash: [], tmdb: []})
     |> assign(:error, nil)
     |> assign(:page, 1)
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("unified_search", %{"search_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:loading, true)
     |> assign(:page, 1)
     |> do_unified_search()}
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    images = DefaultImagesService.get_images_for_category(category)

    {:noreply,
     socket
     |> assign(:selected_category, category)
     |> assign(:default_images, images)}
  end

  @impl true
  def handle_event("select_default_image", params, socket) do
    %{"image_url" => image_url, "filename" => filename, "category" => category} = params

    external_image_data = %{
      "id" => filename,
      "url" => image_url,
      "source" => "default",
      "category" => category,
      "metadata" => %{
        "filename" => filename,
        "category" => category,
        "title" => ImageHelpers.title_from_filename(filename)
      }
    }

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
     |> assign(:show_image_picker, false)}
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
    form_data =
      socket.assigns.form_data
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
    socket =
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:selected_venue_name, name)
      |> assign(:selected_venue_address, address)
      |> assign(:is_virtual, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "image_selected",
        %{"cover_image_url" => cover_image_url, "unsplash_data" => unsplash_data},
        socket
      ) do
    # Track the download as per Unsplash API requirements
    if Map.has_key?(unsplash_data, "download_location") do
      Task.Supervisor.start_child(Eventasaurus.TaskSupervisor, fn ->
        UnsplashService.track_download(unsplash_data["download_location"])
      end)
    end

    # Ensure consistent structure for Unsplash data
    external_image_data = %{
      "id" => Map.get(unsplash_data, "id", "unknown_unsplash_#{System.unique_integer()}"),
      "url" => cover_image_url,
      "source" => "unsplash",
      "metadata" => unsplash_data
    }

    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", external_image_data)
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
     |> assign(:external_image_data, external_image_data)
     |> assign(:show_image_picker, false)}
  end

  @impl true
  def handle_event(
        "image_selected",
        %{"cover_image_url" => cover_image_url, "tmdb_data" => tmdb_data},
        socket
      ) do
    # Ensure consistent structure for TMDB data
    external_image_data = %{
      "id" => Map.get(tmdb_data, "id", "unknown_tmdb_#{System.unique_integer()}"),
      "url" => cover_image_url,
      "source" => "tmdb",
      "metadata" => tmdb_data
    }

    form_data =
      socket.assigns.form_data
      |> Map.put("external_image_data", external_image_data)
      |> Map.put("cover_image_url", cover_image_url)

    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form_data, form_data)
      |> assign(:changeset, changeset)
      |> assign(:cover_image_url, cover_image_url)
      |> assign(:external_image_data, external_image_data)
      |> assign(:show_image_picker, false)

    # NEW: Automatically fetch rich data for TMDB images
    socket = auto_fetch_tmdb_rich_data(socket, tmdb_data)

    {:noreply, socket}
  end

  # ============================================================================
  # Ticketing Event Handlers
  # ============================================================================

  @impl true
  def handle_event(
        "update_participation_type",
        %{"event" => %{"participation_type" => participation_type}},
        socket
      ) do
    form_data = socket.assigns.form_data |> Map.put("participation_type", participation_type)

    changeset =
      socket.assigns.event
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    {:noreply,
     assign(socket,
       form_data: form_data,
       form: to_form(changeset),
       participation_type: participation_type
     )}
  end

  @impl true
  def handle_event("toggle_ticketing", _params, socket) do
    current_value = Map.get(socket.assigns.form_data, "is_ticketed", false)
    # Handle both string and boolean values
    current_bool = current_value in [true, "true"]
    new_value = !current_bool

    # Update form_data with smart taxation type changes
    form_data =
      socket.assigns.form_data
      |> Map.put("is_ticketed", new_value)
      |> update_taxation_for_ticketing_change(new_value)

    # Reset ticketing-related assigns when disabling ticketing
    socket =
      if new_value do
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
    ticket =
      case Integer.parse(ticket_id_str) do
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
        "suggested_price" =>
          format_price_from_cents(
            Map.get(ticket, :suggested_price_cents, ticket.base_price_cents)
          ),
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
    ticket =
      case Integer.parse(ticket_id_str) do
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
      updated_tickets =
        if ticket do
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
    updated_params =
      if Map.has_key?(ticket_params, "tippable") do
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
                  quantity:
                    case Integer.parse(Map.get(ticket_data, "quantity", "0")) do
                      {n, _} when n >= 0 -> n
                      _ -> 0
                    end,
                  starts_at:
                    parse_datetime_input(
                      Map.get(ticket_data, "starts_at"),
                      socket.assigns.event.timezone || TimezoneUtils.default_timezone()
                    ),
                  ends_at:
                    parse_datetime_input(
                      Map.get(ticket_data, "ends_at"),
                      socket.assigns.event.timezone || TimezoneUtils.default_timezone()
                    ),
                  tippable: Map.get(ticket_data, "tippable", false) == true
                }

                # Create or update ticket in the database
                result =
                  case socket.assigns.editing_ticket_id do
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
                        EventasaurusApp.Ticketing.create_ticket(
                          socket.assigns.event,
                          ticket_attrs
                        )
                      end
                  end

                case result do
                  {:ok, _ticket} ->
                    # Reload tickets from database to ensure consistency
                    updated_tickets =
                      EventasaurusApp.Ticketing.list_tickets_for_event(socket.assigns.event.id)

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
                        Enum.map(msgs, &"#{field} #{&1}")
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
  def handle_event("show_recent_places", %{"mode" => _mode}, socket) do
    # Handle the show_recent_places event from the JavaScript hook
    # For now, just return without error - we can expand this later to show actual recent places
    {:noreply, socket}
  end

  @impl true
  def handle_event("location_cleared", %{"mode" => _mode}, socket) do
    # Handle the location_cleared event from the JavaScript hook
    # Clear any location-related state when user clears the location field
    {:noreply, socket}
  end

  @impl true
  def handle_event("enable_google_places", _params, socket) do
    {:noreply, push_event(socket, "enable_google_places", %{})}
  end

  @impl true
  def handle_event("location_selected", %{"place" => place_data, "mode" => "event"}, socket) do
    # Handle Google Places selection for events
    require Logger
    Logger.info("📍 Location selected from Google Places: #{inspect(place_data)}")

    # Update form data with the selected venue information
    form_data =
      (socket.assigns.form_data || %{})
      |> Map.put("venue_name", place_data["name"] || "")
      |> Map.put("venue_address", place_data["formatted_address"] || "")
      |> Map.put("venue_city", place_data["city"] || "")
      |> Map.put("venue_state", place_data["state"] || "")
      |> Map.put("venue_country", place_data["country"] || "")
      |> Map.put("venue_place_id", place_data["place_id"] || "")
      |> Map.put("venue_latitude", place_data["latitude"])
      |> Map.put("venue_longitude", place_data["longitude"])
      |> Map.put("is_virtual", false)

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
      |> assign(:selected_venue_name, place_data["name"])
      |> assign(:selected_venue_address, place_data["formatted_address"])
      |> assign(:is_virtual, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_recent_location", %{"location" => location_json}, socket) do
    # Parse the JSON data with error handling
    location_data =
      case Jason.decode(location_json) do
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
    filtered_locations =
      EventasaurusWeb.Helpers.EventHelpers.filter_locations(
        socket.assigns.recent_locations,
        query
      )

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

  @impl true
  def handle_event("show_rich_data_import", _params, socket) do
    {:noreply, assign(socket, :show_rich_data_import, true)}
  end

  @impl true
  def handle_event("close_rich_data_import", _params, socket) do
    {:noreply, assign(socket, :show_rich_data_import, false)}
  end

  @impl true
  def handle_event("clear_rich_data", _params, socket) do
    socket =
      socket
      |> assign(:rich_external_data, %{})
      |> put_flash(:info, "Rich data has been removed from your event.")

    {:noreply, socket}
  end

  @impl true
  def handle_event("image_upload_error", %{"error" => error_message} = params, socket) do
    require Logger
    Logger.error("Image upload error: #{error_message}")

    # Log additional details if available
    if details = Map.get(params, "details") do
      Logger.error("Upload error details: #{inspect(details)}")
    end

    # Check for specific error types and provide user-friendly messages
    user_message =
      cond do
        error_message == "Invalid Compact JWS" ->
          "Your session has expired. Please refresh the page and try again."

        String.contains?(error_message, "Authentication") ->
          "Authentication failed. Please refresh the page and try again."

        String.contains?(error_message, "File size too large") ->
          error_message

        true ->
          "Failed to upload image. Please try again or choose a different image."
      end

    {:noreply, put_flash(socket, :error, user_message)}
  end

  @impl true
  def handle_event("image_uploaded", %{"path" => path, "publicUrl" => public_url}, socket) do
    require Logger
    Logger.info("Image uploaded successfully: #{path}")
    Logger.info("New public URL: #{public_url}")
    Logger.info("Old cover_image_url: #{inspect(socket.assigns.event.cover_image_url)}")

    # Create external image data for the uploaded image
    external_image_data = %{
      "id" => path,
      "url" => public_url,
      "source" => "upload",
      "filename" => Path.basename(path),
      "title" => "Uploaded Image"
    }

    # DON'T update the event struct directly - this causes the changeset to not detect the change!
    # Instead, create the changeset with the original event
    changeset = Events.change_event(socket.assigns.event, %{"cover_image_url" => public_url})

    # Update the socket with the changeset and form, but keep the original event struct
    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:form, to_form(changeset))
      |> assign(:cover_image_url, public_url)
      |> assign(:external_image_data, external_image_data)
      |> assign(
        :form_data,
        Map.merge(socket.assigns.form_data, %{
          "cover_image_url" => public_url,
          "external_image_data" => external_image_data
        })
      )
      |> assign(:show_image_picker, false)
      |> put_flash(:info, "Cover image uploaded successfully!")

    {:noreply, socket}
  end

  # ========== Helper Functions ==========

  # Automatically fetch rich data when a TMDB image is selected
  defp auto_fetch_tmdb_rich_data(socket, tmdb_data) when is_map(tmdb_data) do
    # Extract TMDB ID and type from the image data
    tmdb_id = Map.get(tmdb_data, "id") || Map.get(tmdb_data, :id)
    tmdb_type = determine_tmdb_type(tmdb_data)

    if tmdb_id && tmdb_type do
      # Start async fetch to avoid blocking
      send(self(), {:auto_fetch_tmdb_rich_data, tmdb_id, tmdb_type})
      socket
    else
      # Missing required data, proceed without rich data
      socket
    end
  end

  # Handle nil or invalid tmdb_data
  defp auto_fetch_tmdb_rich_data(socket, _), do: socket

  # Determine TMDB content type from the image data
  defp determine_tmdb_type(nil), do: nil

  defp determine_tmdb_type(tmdb_data) when is_map(tmdb_data) do
    # Check explicit type field first
    case Map.get(tmdb_data, "type") || Map.get(tmdb_data, :type) do
      "movie" ->
        :movie

      "tv" ->
        :tv

      :movie ->
        :movie

      :tv ->
        :tv

      _ ->
        # Fallback: check for movie-specific fields vs TV-specific fields
        cond do
          Map.has_key?(tmdb_data, "release_date") || Map.has_key?(tmdb_data, :release_date) ->
            :movie

          Map.has_key?(tmdb_data, "first_air_date") || Map.has_key?(tmdb_data, :first_air_date) ->
            :tv

          # Default to movie if uncertain
          true ->
            :movie
        end
    end
  end

  defp determine_tmdb_type(_), do: nil

  defp create_virtual_meeting(socket, meeting_type) do
    {url, label} =
      case meeting_type do
        :zoom ->
          {EventasaurusWeb.Helpers.EventHelpers.generate_zoom_meeting_url(), "Zoom Meeting"}

        :google_meet ->
          {EventasaurusWeb.Helpers.EventHelpers.generate_google_meet_url(), "Google Meet"}
      end

    form_data =
      Map.merge(socket.assigns.form_data || %{}, %{
        "virtual_venue_url" => url,
        "is_virtual" => true,
        "venue_name" => "",
        "venue_address" => "",
        "venue_city" => "",
        "venue_state" => "",
        "venue_country" => "",
        "venue_latitude" => nil,
        "venue_longitude" => nil
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

  # ========== Async Result Handlers ==========
  # Note: The async_user_groups handlers were removed since user groups are now loaded synchronously.
  # The remaining handle_async handlers below are still actively used by assign_async calls in mount/3.

  @impl true
  def handle_async(:async_recent_locations, {:ok, %{async_recent_locations: locations}}, socket) do
    {:noreply,
     socket
     |> assign(:recent_locations, locations)
     |> assign(:filtered_recent_locations, locations)}
  end

  @impl true
  def handle_async(:async_recent_locations, {:exit, _reason}, socket) do
    # On failure, keep the empty lists
    {:noreply, socket}
  end

  @impl true
  def handle_async(:async_supabase_token, {:ok, %{async_supabase_token: token}}, socket) do
    {:noreply, assign(socket, :supabase_access_token, token)}
  end

  @impl true
  def handle_async(:async_supabase_token, {:exit, _reason}, socket) do
    # On failure, keep the empty string - image uploads won't work but page still loads
    {:noreply, socket}
  end

  # ========== Info Handlers ==========

  @impl true
  def handle_info(
        {:image_selected, %{cover_image_url: url, unsplash_data: unsplash_data}},
        socket
      ) do
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
  def handle_info({:rich_data_search, query, provider}, socket) do
    case safe_provider_conversion(provider) do
      {:ok, provider_atom} ->
        case RichDataManager.search(query, %{providers: [provider_atom]}) do
          {:ok, results} ->
            # Flatten the results from the map format to a list
            flattened_results =
              results
              |> Enum.flat_map(fn {_provider_id, result} ->
                case result do
                  {:ok, items} when is_list(items) ->
                    # Add provider information to each item
                    Enum.map(items, fn item ->
                      Map.put(item, :provider, provider_atom)
                    end)

                  {:error, _} ->
                    []

                  _ ->
                    []
                end
              end)

            send_update(RichDataImportModal,
              id: "rich-data-import-modal",
              search_results: flattened_results,
              loading: false,
              error: nil
            )

          {:error, reason} ->
            send_update(RichDataImportModal,
              id: "rich-data-import-modal",
              search_results: [],
              loading: false,
              error: "Search failed: #{reason}"
            )
        end

      {:error, reason} ->
        send_update(RichDataImportModal,
          id: "rich-data-import-modal",
          search_results: [],
          loading: false,
          error: reason
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rich_data_import, id, provider, type}, socket) do
    require Logger

    Logger.debug(
      "handle_info rich_data_import called with id: #{id}, provider: #{provider}, type: #{type}"
    )

    case safe_provider_type_conversion(provider, type) do
      {:ok, provider_atom, type_atom} ->
        case RichDataManager.get_details(provider_atom, id, type_atom, %{}) do
          {:ok, details} ->
            Logger.debug("RichDataManager.get_details returned success, importing data")

            # Call the existing import handler with the fetched data
            send(self(), {:rich_data_import, details})

            {:noreply, socket}

          {:error, reason} ->
            Logger.error("Failed to fetch rich data for import: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Failed to import data: #{reason}")}
        end

      {:error, reason} ->
        Logger.error("Invalid provider or type in import: provider=#{provider}, type=#{type}")
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  @impl true
  def handle_info({:rich_data_import, data}, socket) do
    # Store the imported data in both the assign and form_data
    updated_form_data = Map.put(socket.assigns.form_data, "rich_external_data", data)

    # Update the changeset to reflect the new data
    changeset = Events.change_event(socket.assigns.event, updated_form_data)

    socket =
      socket
      |> assign(:rich_external_data, data)
      |> assign(:form_data, updated_form_data)
      |> assign(:changeset, changeset)
      |> assign(:show_rich_data_import, false)
      |> put_flash(
        :info,
        "Rich data imported successfully! '#{data["metadata"]["title"] || "Content"}' has been added to your event."
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:auto_fetch_tmdb_rich_data, tmdb_id, tmdb_type}, socket) do
    case EventasaurusWeb.Services.RichDataManager.get_details(:tmdb, tmdb_id, tmdb_type, %{}) do
      {:ok, rich_data} ->
        # Update both assigns and form_data for edit page
        updated_form_data = Map.put(socket.assigns.form_data, "rich_external_data", rich_data)

        changeset =
          socket.assigns.event
          |> EventasaurusApp.Events.change_event(updated_form_data)
          |> Map.put(:action, :validate)

        content_type = if tmdb_type == :movie, do: "Movie", else: "TV show"

        socket =
          socket
          |> assign(:rich_external_data, rich_data)
          |> assign(:form_data, updated_form_data)
          |> assign(:changeset, changeset)
          |> put_flash(:info, "#{content_type} data imported automatically with image!")

        {:noreply, socket}

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to auto-fetch TMDB rich data: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:close_rich_data_modal}, socket) do
    {:noreply, assign(socket, :show_rich_data_import, false)}
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

  defp parse_datetime_input(datetime_str, timezone)
  defp parse_datetime_input(nil, _timezone), do: nil
  defp parse_datetime_input("", _timezone), do: nil

  defp parse_datetime_input(datetime_str, timezone) when is_binary(datetime_str) do
    # Use DateTimeHelper for consistent parsing with event timezone
    case DateTimeHelper.parse_datetime_local(datetime_str, timezone) do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime_input(_, _), do: nil

  # These helper functions are now replaced by DateTimeHelper.format_for_form/2

  # Helper function to validate date polling options
  # Legacy validate_date_polling function removed - using generic polling system

  # Helper function to extract address components
  defp get_address_component(components, type) do
    component =
      Enum.find(components, fn comp ->
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
    timezone = Map.get(params, "timezone") || TimezoneUtils.default_timezone()

    # Handle polling deadline if present
    params =
      case {Map.get(params, "polling_deadline_date"), Map.get(params, "polling_deadline_time")} do
        {date_str, time_str}
        when is_binary(date_str) and is_binary(time_str) and date_str != "" and time_str != "" ->
          case DateTimeHelper.parse_user_datetime(date_str, time_str, timezone) do
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
      # Remove helper keys to prevent leakage
      |> Map.drop(["polling_deadline_date", "polling_deadline_time"])

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
            case DateTimeHelper.parse_user_datetime(
                   Date.to_iso8601(middle_date),
                   start_time,
                   timezone
                 ) do
              {:ok, start_datetime} ->
                case DateTimeHelper.parse_user_datetime(
                       Date.to_iso8601(middle_date),
                       end_time,
                       timezone
                     ) do
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
      start_at =
        case {Map.get(params, "start_date"), Map.get(params, "start_time")} do
          {date_str, time_str} when is_binary(date_str) and is_binary(time_str) ->
            case DateTimeHelper.parse_user_datetime(date_str, time_str, timezone) do
              {:ok, datetime} -> datetime
              {:error, _} -> Map.get(params, "start_at")
            end

          _ ->
            Map.get(params, "start_at")
        end

      # Combine end date and time
      ends_at =
        case {Map.get(params, "ends_date"), Map.get(params, "ends_time")} do
          {date_str, time_str} when is_binary(date_str) and is_binary(time_str) ->
            case DateTimeHelper.parse_user_datetime(date_str, time_str, timezone) do
              {:ok, datetime} -> datetime
              {:error, _} -> Map.get(params, "ends_at")
            end

          _ ->
            Map.get(params, "ends_at")
        end

      params
      |> Map.put("start_at", start_at)
      |> Map.put("ends_at", ends_at)
    end
  end

  # Helper function replaced by DateTimeHelper.parse_user_datetime/3

  # Legacy handle_date_polling_update function removed - using generic polling system

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
      # Legacy date polling form data removed
      |> Map.put("is_ticketed", path in ["confirmed", "threshold"])
      |> Map.put("requires_threshold", path == "threshold")

    # Update the socket with the new path and form data
    socket
    |> assign(:setup_path, path)
    # Legacy date polling disabled
    |> assign(:enable_date_polling, false)
    |> assign(:is_ticketed, path in ["confirmed", "threshold"])
    |> assign(:requires_threshold, path == "threshold")
    |> assign(:form_data, form_data)
    |> maybe_reset_ticketing(path)
  end

  # Validation helper for flexible pricing
  defp validate_flexible_pricing(ticket_data, pricing_model, price_cents) do
    case pricing_model do
      "flexible" ->
        minimum_price_cents =
          case parse_currency(Map.get(ticket_data, "minimum_price", "0")) do
            nil -> 0
            cents -> cents
          end

        suggested_price_cents =
          case parse_currency(Map.get(ticket_data, "suggested_price", "")) do
            # Default to base price if not provided
            nil -> price_cents
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
        |> Map.put(
          "taxation_type_reasoning",
          "Changed to ticketed_event because tickets were added"
        )

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
        |> Map.put(
          "taxation_type_reasoning",
          case current_taxation do
            "ticketless" -> "No tickets exist - automatically ticketless"
            "ticketed_event" -> "Standard ticketed event configuration"
            "contribution_collection" -> "Contribution-based event configuration"
            _ -> "Current configuration maintained"
          end
        )
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

  # Helper functions for safe provider/type conversion

  defp safe_provider_conversion(provider) do
    case provider do
      "tmdb" -> {:ok, :tmdb}
      "spotify" -> {:ok, :spotify}
      _ -> {:error, "Invalid provider: #{provider}"}
    end
  end

  defp safe_provider_type_conversion(provider, type) do
    case {provider, type} do
      {"tmdb", "movie"} -> {:ok, :tmdb, :movie}
      {"tmdb", "tv"} -> {:ok, :tmdb, :tv}
      {"spotify", "artist"} -> {:ok, :spotify, :artist}
      {"spotify", "album"} -> {:ok, :spotify, :album}
      {"spotify", "track"} -> {:ok, :spotify, :track}
      _ -> {:error, "Invalid provider/type combination: #{provider}/#{type}"}
    end
  end

  # Helper function to validate group assignment authorization
  defp validate_group_assignment(event_params, user) do
    case Map.get(event_params, "group_id") do
      nil ->
        {:ok, event_params}

      "" ->
        # Empty string means personal event
        {:ok, Map.put(event_params, "group_id", nil)}

      group_id when is_binary(group_id) ->
        # Validate user is member of the group
        case Groups.is_member?(group_id, user.id) do
          true -> {:ok, event_params}
          false -> {:error, "You can only assign events to groups you are a member of"}
        end

      group_id when is_integer(group_id) ->
        # Handle integer group_id
        case Groups.is_member?(group_id, user.id) do
          true -> {:ok, event_params}
          false -> {:error, "You can only assign events to groups you are a member of"}
        end

      _ ->
        {:ok, event_params}
    end
  end

  # ========== Validation Helpers ==========

  defp validate_date_certainty_transition(event, new_date_certainty) do
    case {event.status, event.start_at, new_date_certainty} do
      # Allow all transitions for draft/polling/threshold events
      {:draft, _, _} ->
        :ok

      {:polling, _, _} ->
        :ok

      {:threshold, _, _} ->
        :ok

      # For confirmed events with a set date, don't allow going backwards
      {:confirmed, start_at, "polling"} when not is_nil(start_at) ->
        {:error, "Cannot change to polling - event date is already confirmed"}

      {:confirmed, start_at, "planning"} when not is_nil(start_at) ->
        {:error, "Cannot change to planning - event date is already confirmed"}

      # Allow confirmed events to stay confirmed or change to other confirmed options
      {:confirmed, _, "confirmed"} ->
        :ok

      # Allow any other transitions (canceled events, etc.)
      _ ->
        :ok
    end
  end

  defp validate_venue_certainty_transition(event, new_venue_certainty) do
    case {event.status, event.venue_id, event.is_virtual, new_venue_certainty} do
      # Allow all transitions for draft/polling/threshold events
      {:draft, _, _, _} ->
        :ok

      {:polling, _, _, _} ->
        :ok

      {:threshold, _, _, _} ->
        :ok

      # For confirmed events with a set venue, don't allow going backwards
      {:confirmed, venue_id, false, "polling"} when not is_nil(venue_id) ->
        {:error, "Cannot change to polling - event venue is already confirmed"}

      {:confirmed, venue_id, false, "tbd"} when not is_nil(venue_id) ->
        {:error, "Cannot change to TBD - event venue is already confirmed"}

      # For confirmed virtual events, don't allow going backwards
      {:confirmed, nil, true, "polling"} ->
        {:error, "Cannot change to polling - event is already confirmed as virtual"}

      {:confirmed, nil, true, "tbd"} ->
        {:error, "Cannot change to TBD - event is already confirmed as virtual"}

      # Allow confirmed events to stay in confirmed states
      {:confirmed, _, _, "confirmed"} ->
        :ok

      {:confirmed, _, _, "virtual"} ->
        :ok

      # Allow any other transitions (canceled events, etc.)
      _ ->
        :ok
    end
  end

  # ============================================================================
  # Threshold Field Mapping Helpers
  # ============================================================================

  # Maps user-friendly threshold field names from the form to database field names.
  #
  # Form fields:
  # - funding_goal → threshold_revenue_cents (converted from dollars to cents)
  # - funding_deadline → threshold_deadline
  # - minimum_attendees → threshold_count
  # - decision_deadline → threshold_deadline
  defp map_threshold_fields(params) do
    params
    |> map_funding_goal_to_threshold_revenue()
    |> map_minimum_attendees_to_threshold_count()
    |> map_deadline_fields()
    |> drop_intermediate_threshold_fields()
  end

  # Convert funding_goal (dollars) to threshold_revenue_cents
  defp map_funding_goal_to_threshold_revenue(params) do
    case Map.get(params, "funding_goal") do
      nil ->
        params

      "" ->
        params

      goal_str when is_binary(goal_str) ->
        case parse_currency(goal_str) do
          nil -> params
          cents -> Map.put(params, "threshold_revenue_cents", cents)
        end

      goal when is_number(goal) ->
        # If it's already a number, assume dollars and convert to cents
        Map.put(params, "threshold_revenue_cents", round(goal * 100))
    end
  end

  # Convert minimum_attendees to threshold_count
  defp map_minimum_attendees_to_threshold_count(params) do
    case Map.get(params, "minimum_attendees") do
      nil ->
        params

      "" ->
        params

      count_str when is_binary(count_str) ->
        case Integer.parse(count_str) do
          {count, _} when count > 0 -> Map.put(params, "threshold_count", count)
          _ -> params
        end

      count when is_integer(count) and count > 0 ->
        Map.put(params, "threshold_count", count)

      _ ->
        params
    end
  end

  # Map funding_deadline or decision_deadline to polling_deadline
  # Note: The Event schema uses polling_deadline for all deadline purposes (not threshold_deadline)
  defp map_deadline_fields(params) do
    timezone = Map.get(params, "timezone") || TimezoneUtils.default_timezone()

    # Check for funding_deadline (crowdfunding) or decision_deadline (interest)
    deadline_str = Map.get(params, "funding_deadline") || Map.get(params, "decision_deadline")

    case deadline_str do
      nil ->
        params

      "" ->
        params

      date_str when is_binary(date_str) ->
        # Parse the date and set time to end of day in the event's timezone
        case Date.from_iso8601(date_str) do
          {:ok, date} ->
            # Set deadline to end of day (23:59:59) in event timezone
            case DateTimeHelper.parse_user_datetime(
                   Date.to_iso8601(date),
                   "23:59",
                   timezone
                 ) do
              {:ok, datetime} -> Map.put(params, "polling_deadline", datetime)
              {:error, _} -> params
            end

          {:error, _} ->
            params
        end

      _ ->
        params
    end
  end

  # Remove intermediate form fields that don't exist in the Event schema
  defp drop_intermediate_threshold_fields(params) do
    Map.drop(params, [
      "funding_goal",
      "funding_deadline",
      "minimum_attendees",
      "decision_deadline"
    ])
  end
end
