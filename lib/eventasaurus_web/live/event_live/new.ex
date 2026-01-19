defmodule EventasaurusWeb.EventLive.New do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.EventComponents
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.Components.ImagePickerModal
  import EventasaurusWeb.Components.TicketModal
  import EventasaurusWeb.Helpers.CurrencyHelpers

  alias EventasaurusWeb.Components.RichDataImportModal
  alias EventasaurusWeb.Services.RichDataManager
  alias EventasaurusWeb.EventLive.FormHelpers

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Events.Validations
  alias EventasaurusApp.Groups
  alias EventasaurusWeb.Services.SearchService
  alias EventasaurusWeb.Helpers.ImageHelpers
  alias EventasaurusApp.DateTimeHelper
  alias EventasaurusWeb.Utils.TimezoneUtils

  @valid_setup_paths ~w[polling confirmed threshold]

  @impl true
  def mount(params, session, socket) do
    # Use the user already assigned by the auth hook (require_authenticated_user)
    # The hook handles Clerk claims -> User struct conversion
    user = socket.assigns[:user]

    if user do
      changeset = Events.change_event(%Event{})
      default_date = Date.utc_today() |> Date.add(5) |> Date.to_iso8601()
      # Load groups that the user is a member of or created
      user_groups = Groups.list_user_groups(user)

      # Load recent locations for the user
      recent_locations = Events.get_recent_locations_for_user(user.id, limit: 5)

      # Auto-select a random default image
      random_image = EventasaurusWeb.Services.DefaultImagesService.get_random_image()

      {cover_image_url, external_image_data} =
        case random_image do
          nil ->
            {nil, nil}

          image ->
            {
              image.url,
              %{
                "source" => "default",
                "url" => image.url,
                "filename" => image.filename,
                "category" => image.category,
                "title" => ImageHelpers.title_from_filename(image.filename)
              }
            }
        end

      # Enhanced default value logic for taxation_type
      # Smart default based on event characteristics
      default_taxation_type =
        determine_smart_taxation_default(%{
          # New events default to no ticketing
          "is_ticketed" => false,
          "setup_path" => "confirmed"
        })

      # Update form_data with the random image and smart defaults
      initial_form_data = %{
        "start_date" => default_date,
        "ends_date" => default_date,
        # Legacy date polling field removed
        "slug" => Nanoid.generate(10),
        "taxation_type" => default_taxation_type,
        "taxation_type_reasoning" => get_taxation_reasoning(default_taxation_type, false)
      }

      form_data_with_image =
        case cover_image_url do
          nil ->
            initial_form_data

          url ->
            Map.merge(initial_form_data, %{
              "cover_image_url" => url,
              "external_image_data" => external_image_data
            })
        end

      # Check if group_id was provided in params
      selected_group_id = Map.get(params, "group_id")

      # Update form_data and changeset with selected group if provided and user is a member
      {final_form_data, changeset} =
        with group_id_str when is_binary(group_id_str) <- selected_group_id,
             {group_id_int, ""} <- Integer.parse(group_id_str),
             true <- Enum.any?(user_groups, &(&1.id == group_id_int)) do
          # Update both form_data and changeset
          updated_form_data = Map.put(form_data_with_image, "group_id", group_id_str)
          updated_changeset = Events.change_event(%Event{group_id: group_id_int})
          {updated_form_data, updated_changeset}
        else
          _ -> {form_data_with_image, changeset}
        end

      socket =
        socket
        |> assign(:form, to_form(changeset))
        |> assign(:user_groups, user_groups)
        |> assign(:user, user)
        |> assign(:changeset, changeset)
        |> assign(:form_data, final_form_data)
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
        # Changed from "unsplash" to unified search
        |> assign(:image_tab, "search")
        # Legacy date polling disabled
        |> assign(:enable_date_polling, false)
        # default to confirmed for new events
        |> assign(:setup_path, "confirmed")
        # New three-question dropdown assigns
        |> assign(:date_certainty, "confirmed")
        |> assign(:venue_certainty, "confirmed")
        |> assign(:participation_type, "free")
        # New unified picker assigns
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
        # Rich data import assigns
        |> assign(:rich_external_data, %{})
        |> assign(:show_rich_data_import, false)

      {:ok, socket}
    else
      # User not available - this shouldn't happen as the route requires auth,
      # but redirect to login as a fallback
      {:ok,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
       |> Phoenix.LiveView.redirect(to: ~p"/auth/login")}
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
  def handle_info({:rich_data_search, query, provider}, socket) do
    # Convert provider string to atom safely
    case provider do
      "tmdb" ->
        perform_rich_data_search(query, :tmdb, socket)

      "spotify" ->
        perform_rich_data_search(query, :spotify, socket)

      _ ->
        require Logger
        Logger.error("Invalid provider in search: #{provider}")

        send_update(RichDataImportModal,
          id: "rich-data-import-modal",
          search_results: [],
          loading: false,
          error: "Invalid provider specified"
        )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:rich_data_preview, id, provider, type}, socket) do
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger

      Logger.debug(
        "handle_info rich_data_preview called with id: #{id}, provider: #{provider}, type: #{type}"
      )
    end

    # Convert provider string to atom safely
    {provider_atom, type_atom} =
      case {provider, type} do
        {"tmdb", "movie"} ->
          {:tmdb, :movie}

        {"tmdb", "tv"} ->
          {:tmdb, :tv}

        {"spotify", "artist"} ->
          {:spotify, :artist}

        {"spotify", "album"} ->
          {:spotify, :album}

        {"spotify", "track"} ->
          {:spotify, :track}

        _ ->
          require Logger
          Logger.error("Invalid provider or type: provider=#{provider}, type=#{type}")

          send_update(RichDataImportModal,
            id: "rich-data-import-modal",
            search_results: [],
            loading: false,
            error: "Invalid provider or type specified"
          )

          {:noreply, socket}
      end

    case RichDataManager.get_details(provider_atom, id, type_atom, %{}) do
      {:ok, details} ->
        if Application.get_env(:eventasaurus, :env) == :dev do
          require Logger

          Logger.debug(
            "RichDataManager.get_details returned success, details keys: #{inspect(Map.keys(details))}"
          )
        end

        send_update(RichDataImportModal,
          id: "rich-data-import-modal",
          preview_data: details,
          loading: false,
          error: nil
        )

        if Application.get_env(:eventasaurus, :env) == :dev do
          require Logger
          Logger.debug("send_update called for RichDataImportModal with preview_data")
        end

      {:error, reason} ->
        require Logger
        Logger.error("RichDataManager.get_details failed with reason: #{inspect(reason)}")

        send_update(RichDataImportModal,
          id: "rich-data-import-modal",
          preview_data: nil,
          loading: false,
          error: "Preview failed: #{reason}"
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:rich_data_import, id, provider, type}, socket) do
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger

      Logger.debug(
        "handle_info rich_data_import called with id: #{id}, provider: #{provider}, type: #{type}"
      )
    end

    # Convert provider string to atom safely
    case {provider, type} do
      {"tmdb", "movie"} ->
        handle_rich_data_details(:tmdb, id, :movie, socket)

      {"tmdb", "tv"} ->
        handle_rich_data_details(:tmdb, id, :tv, socket)

      {"spotify", "artist"} ->
        handle_rich_data_details(:spotify, id, :artist, socket)

      {"spotify", "album"} ->
        handle_rich_data_details(:spotify, id, :album, socket)

      {"spotify", "track"} ->
        handle_rich_data_details(:spotify, id, :track, socket)

      _ ->
        require Logger
        Logger.error("Invalid provider or type in import: provider=#{provider}, type=#{type}")
        {:noreply, put_flash(socket, :error, "Invalid provider or type specified")}
    end
  end

  @impl true
  def handle_info({:rich_data_import, data}, socket) do
    # Store the imported data
    socket =
      socket
      |> assign(:rich_external_data, data)
      |> assign(:show_rich_data_import, false)
      |> put_flash(
        :info,
        "Rich data imported successfully! '#{data.title}' has been added to your event."
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:auto_fetch_tmdb_rich_data, tmdb_id, tmdb_type}, socket) do
    case EventasaurusWeb.Services.RichDataManager.get_details(:tmdb, tmdb_id, tmdb_type, %{}) do
      {:ok, rich_data} ->
        # Update form_data with the fetched rich data
        form_data = Map.put(socket.assigns.form_data, "rich_external_data", rich_data)

        changeset =
          %Event{}
          |> Events.change_event(form_data)
          |> Map.put(:action, :validate)

        content_type = if tmdb_type == :movie, do: "Movie", else: "TV show"

        socket =
          socket
          |> assign(:rich_external_data, rich_data)
          |> assign(:form_data, form_data)
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

  # ========== Private Helper Functions ==========

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

  defp perform_rich_data_search(query, provider_atom, socket) do
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

    {:noreply, socket}
  end

  defp handle_rich_data_details(provider_atom, id, type_atom, socket) do
    case RichDataManager.get_details(provider_atom, id, type_atom, %{}) do
      {:ok, details} ->
        if Application.get_env(:eventasaurus, :env) == :dev do
          require Logger
          Logger.debug("RichDataManager.get_details returned success, importing data")
        end

        # Call the existing import handler with the fetched data
        send(self(), {:rich_data_import, details})

        {:noreply, socket}

      {:error, reason} ->
        require Logger
        Logger.error("Failed to fetch rich data for import: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to import data: #{reason}")}
    end
  end

  # ========== Handle Event Implementations ==========

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("[validate] incoming params: #{inspect(event_params)}")
      Logger.debug("[validate] current socket is_virtual: #{inspect(socket.assigns.is_virtual)}")

      Logger.debug(
        "[validate] current form_data is_virtual: #{inspect(Map.get(socket.assigns.form_data, "is_virtual"))}"
      )
    end

    # Always preserve cover_image_url if not present in params
    cover_image_url =
      event_params["cover_image_url"] || Map.get(socket.assigns.form_data, "cover_image_url") ||
        socket.assigns.cover_image_url

    # Always preserve rich_external_data if not present in params
    rich_external_data =
      event_params["rich_external_data"] ||
        Map.get(socket.assigns.form_data, "rich_external_data") ||
        socket.assigns.rich_external_data

    # Preserve is_virtual unless it's explicitly in the event_params (from form submission, not toggle)
    is_virtual_value =
      if Map.has_key?(event_params, "is_virtual") do
        event_params["is_virtual"]
      else
        # Preserve current state
        Map.get(socket.assigns.form_data, "is_virtual", socket.assigns.is_virtual)
      end

    event_params =
      event_params
      |> (fn params ->
            if cover_image_url,
              do: Map.put(params, "cover_image_url", cover_image_url),
              else: params
          end).()
      |> (fn params ->
            if rich_external_data,
              do: Map.put(params, "rich_external_data", rich_external_data),
              else: params
          end).()
      |> Map.put("is_virtual", is_virtual_value)

    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger

      Logger.debug(
        "[validate] final is_virtual in params: #{inspect(event_params["is_virtual"])}"
      )
    end

    # Merge all params with current form_data, preserving existing values
    form_data = Map.merge(socket.assigns.form_data, event_params)

    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger

      Logger.debug(
        "[validate] final form_data is_virtual: #{inspect(Map.get(form_data, "is_virtual"))}"
      )
    end

    changeset =
      %Event{}
      |> Events.change_event(event_params)
      |> Validations.validate_for_draft()
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:changeset, changeset)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("submit", %{"event" => event_params}, socket) do
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("[submit] incoming params: #{inspect(event_params)}")
    end

    # Process datetime fields - combine date and time into datetime
    event_params = process_datetime_fields(event_params)

    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("[submit] processed params: #{inspect(event_params)}")
    end

    # Apply taxation consistency logic before further processing
    event_params = apply_taxation_consistency(event_params)

    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("[submit] taxation consistency applied: #{inspect(event_params)}")
    end

    # Resolve intent-based answers to event attributes
    resolved_attributes = FormHelpers.resolve_event_attributes(event_params)
    event_params = Map.merge(event_params, resolved_attributes)

    # Map user-friendly threshold fields to schema fields
    # funding_goal → threshold_revenue_cents, funding_deadline → polling_deadline, etc.
    event_params = map_threshold_fields(event_params)

    # Validate venue requirement when venue_certainty is "confirmed"
    # Check event_params first, then fall back to form_data
    venue_certainty =
      Map.get(
        event_params,
        "venue_certainty",
        Map.get(socket.assigns.form_data || %{}, "venue_certainty", "confirmed")
      )

    # Check if it's a virtual event (from either event_params or form_data)
    is_virtual =
      Map.get(
        event_params,
        "is_virtual",
        Map.get(socket.assigns.form_data || %{}, "is_virtual", false)
      ) in [true, "true"]

    # Get venue fields from event_params first, then form_data, and trim whitespace
    venue_name =
      (Map.get(
         event_params,
         "venue_name",
         Map.get(socket.assigns.form_data || %{}, "venue_name", "")
       ) || "")
      |> String.trim()

    _venue_address =
      (Map.get(
         event_params,
         "venue_address",
         Map.get(socket.assigns.form_data || %{}, "venue_address", "")
       ) || "")
      |> String.trim()

    # Only validate venue if it's not virtual and venue_certainty is "confirmed"
    # Require at least venue_name (consistent with venue creation logic below)
    if !is_virtual && venue_certainty == "confirmed" && venue_name == "" do
      require Logger
      Logger.debug("[submit] Venue validation failed - 'confirmed' certainty without venue name")

      {:noreply,
       put_flash(
         socket,
         :error,
         "Please provide a venue location or select 'Still planning - venue TBD' or 'Virtual event'"
       )}
    else
      if Application.get_env(:eventasaurus, :env) == :dev do
        require Logger
        Logger.debug("[submit] resolved attributes: #{inspect(resolved_attributes)}")
        Logger.debug("[submit] final event_params after resolution: #{inspect(event_params)}")
      end

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

      # Process venue data from form_data if present
      final_event_params =
        case socket.assigns.form_data do
          form_data when is_map(form_data) ->
            # Check if we have venue data in form_data and user is not setting virtual
            venue_name = Map.get(form_data, "venue_name")
            venue_address = Map.get(form_data, "venue_address")
            is_virtual = Map.get(form_data, "is_virtual", false)

            if (!is_virtual and venue_name) && venue_name != "" do
              # Try to find existing venue or create new one
              venue_attrs = %{
                name: venue_name,
                address: venue_address,
                city_name: Map.get(form_data, "venue_city"),
                country_code: Map.get(form_data, "venue_country"),
                latitude:
                  case Map.get(form_data, "venue_latitude") do
                    lat when is_binary(lat) ->
                      case Float.parse(lat) do
                        {float_val, _} -> float_val
                        :error -> nil
                      end

                    lat ->
                      lat
                  end,
                longitude:
                  case Map.get(form_data, "venue_longitude") do
                    lng when is_binary(lng) ->
                      case Float.parse(lng) do
                        {float_val, _} -> float_val
                        :error -> nil
                      end

                    lng ->
                      lng
                  end,
                venue_type: Map.get(form_data, "venue_type", "venue"),
                # Include Google Places ID
                place_id: Map.get(form_data, "venue_place_id"),
                source:
                  case Map.get(form_data, "venue_place_id") do
                    nil -> "user"
                    "" -> "user"
                    _ -> "google"
                  end
              }

              # Try to find existing venue by address first
              case EventasaurusApp.Venues.find_venue_by_address(venue_address) do
                nil ->
                  # Create new venue using VenueStore for proper city_id lookup
                  case EventasaurusDiscovery.Locations.VenueStore.find_or_create_venue(
                         venue_attrs
                       ) do
                    {:ok, venue} ->
                      Map.put(event_params, "venue_id", venue.id)

                    # Fall back to creating without venue
                    {:error, reason} ->
                      require Logger
                      Logger.error("Failed to create venue: #{inspect(reason)}")
                      event_params
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

      # Authorize group assignment if specified
      case validate_group_assignment(final_event_params, socket.assigns.user) do
        {:ok, authorized_params} ->
          require Logger

          Logger.debug("Event creation params authorized",
            user_id: socket.assigns.user.id,
            has_group: Map.has_key?(authorized_params, "group_id"),
            status: Map.get(authorized_params, "status")
          )

          # Validate with publish requirements before saving
          validation_changeset =
            %Event{}
            |> Events.change_event(authorized_params)
            |> Validations.validate_for_publish()
            |> Map.put(:action, :validate)

          if validation_changeset.valid? do
            # No date polling validation errors, proceed normally
            create_event_with_validation(authorized_params, socket)
          else
            # Validation failed, show errors
            require Logger
            # Sanitize errors for logging (messages only, no raw values)
            # Whitelist safe placeholder keys to avoid leaking sensitive data
            safe_keys = [
              :count,
              :min,
              :max,
              :validation,
              :constraint,
              :type,
              :limit,
              :kind,
              :field,
              :enum
            ]

            sanitized_errors =
              Ecto.Changeset.traverse_errors(validation_changeset, fn {msg, opts} ->
                safe_opts =
                  opts
                  |> Enum.into(%{})
                  |> Map.take(safe_keys)

                Enum.reduce(safe_opts, msg, fn {key, value}, acc ->
                  String.replace(acc, "%{#{key}}", to_string(value))
                end)
              end)

            Logger.error("Event validation failed",
              errors: sanitized_errors,
              user_id: socket.assigns.user.id,
              action: validation_changeset.action,
              valid?: validation_changeset.valid?
            )

            {:noreply, assign(socket, form: to_form(validation_changeset))}
          end

        {:error, message} ->
          socket = put_flash(socket, :error, message)
          {:noreply, socket}
      end
    end

    # Close the venue validation else block
  end

  @impl true
  def handle_event("set_timezone", %{"timezone" => timezone}, socket) do
    IO.puts("DEBUG - Browser detected timezone: #{timezone}")

    # Only set timezone if it's not already set
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
       |> assign(:changeset, changeset)
       |> assign(:form, to_form(changeset))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_virtual", params, socket) do
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("toggle_virtual called with params: #{inspect(params)}")
    end

    # Determine the new state based on the params
    is_virtual =
      case params do
        %{"value" => value} -> value == "true"
        _ -> !socket.assigns.is_virtual
      end

    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("Setting is_virtual to: #{inspect(is_virtual)}")
    end

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

    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger
      Logger.debug("Updated form_data is_virtual: #{inspect(Map.get(form_data, "is_virtual"))}")
    end

    {:noreply,
     socket
     |> assign(:is_virtual, is_virtual)
     |> assign(:form_data, form_data)}
  end

  @impl true
  def handle_event("select_setup_path", %{"path" => path}, socket)
      when path in @valid_setup_paths do
    # Update form_data based on the selected path
    form_data =
      socket.assigns.form_data
      |> Map.put("setup_path", path)
      # Legacy date polling setup removed
      |> Map.put("is_ticketed", path in ["confirmed", "threshold"])
      |> Map.put("requires_threshold", path == "threshold")

    # Update the socket with the new path and form data
    socket =
      socket
      |> assign(:setup_path, path)
      # Legacy date polling disabled
      |> assign(:enable_date_polling, false)
      |> assign(:is_ticketed, path in ["confirmed", "threshold"])
      |> assign(:requires_threshold, path == "threshold")
      |> assign(:form_data, form_data)
      |> maybe_reset_ticketing(path)

    {:noreply, socket}
  end

  def handle_event("select_setup_path", _params, socket),
    # ignore unknown values
    do: {:noreply, socket}

  # New handlers for unified dropdown-based event creation
  @impl true
  def handle_event(
        "update_date_certainty",
        %{"event" => %{"date_certainty" => date_certainty}},
        socket
      ) do
    form_data = socket.assigns.form_data |> Map.put("date_certainty", date_certainty)
    changeset = Events.change_event(%Event{}, form_data)

    {:noreply,
     assign(socket,
       form_data: form_data,
       changeset: changeset,
       date_certainty: date_certainty
     )}
  end

  @impl true
  def handle_event(
        "update_venue_certainty",
        %{"event" => %{"venue_certainty" => venue_certainty}},
        socket
      ) do
    # Set is_virtual based on venue_certainty selection
    is_virtual = venue_certainty == "virtual"

    form_data =
      socket.assigns.form_data
      |> Map.put("venue_certainty", venue_certainty)
      |> Map.put("is_virtual", is_virtual)

    changeset = Events.change_event(%Event{}, form_data)

    {:noreply,
     assign(socket,
       form_data: form_data,
       changeset: changeset,
       venue_certainty: venue_certainty,
       is_virtual: is_virtual
     )}
  end

  @impl true
  def handle_event(
        "update_participation_type",
        %{"event" => %{"participation_type" => participation_type}},
        socket
      ) do
    form_data = socket.assigns.form_data |> Map.put("participation_type", participation_type)
    changeset = Events.change_event(%Event{}, form_data)

    {:noreply,
     assign(socket,
       form_data: form_data,
       changeset: changeset,
       participation_type: participation_type
     )}
  end

  # Legacy toggle_date_polling handler removed - using generic polling system

  @impl true
  def handle_event("open_image_picker", _params, socket) do
    {:noreply, assign(socket, show_image_picker: true, image_tab: "search")}
  end

  @impl true
  def handle_event("close_image_picker", _params, socket) do
    {:noreply, assign(socket, :show_image_picker, false)}
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
      %Event{}
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
  def handle_event("location_cleared", %{"mode" => _mode}, socket) do
    # Handle when a location is cleared
    form_data =
      Map.drop(socket.assigns.form_data || %{}, [
        "venue_name",
        "venue_address",
        "venue_city",
        "venue_state",
        "venue_country",
        "venue_place_id",
        "venue_latitude",
        "venue_longitude"
      ])

    changeset =
      %Event{}
      |> Events.change_event(form_data)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form_data, form_data)
     |> assign(:changeset, changeset)
     |> assign(:selected_venue_name, nil)
     |> assign(:selected_venue_address, nil)}
  end

  @impl true
  def handle_event("enable_google_places", _params, socket) do
    {:noreply, push_event(socket, "enable_google_places", %{})}
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
  def handle_event("filter_recent_locations", %{"query" => query}, socket) do
    filtered_locations =
      EventasaurusWeb.Helpers.EventHelpers.filter_locations(
        socket.assigns.recent_locations,
        query
      )

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
    if Application.get_env(:eventasaurus, :env) == :dev do
      require Logger

      Logger.debug(
        "[handle_event :image_uploaded] Image uploaded successfully: #{inspect(image_url)}"
      )
    end

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
  def handle_event(
        "select_image",
        %{"source" => source, "image_url" => image_url, "image_data" => image_data} = params,
        socket
      ) do
    external_data = %{
      "id" =>
        Map.get(params, "id") ||
          Map.get(image_data, "id", "unknown_#{source}_#{System.unique_integer()}"),
      "url" => image_url,
      "source" => source,
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
    external_data = %{
      "id" => Map.get(image_data, "id", "unknown_#{source}_#{System.unique_integer()}"),
      "url" => image_url,
      "source" => source,
      "metadata" => image_data
    }

    # Update form_data with the new image
    form_data =
      Map.merge(socket.assigns.form_data, %{
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

    # NEW: Automatically fetch rich data for TMDB images
    socket =
      if source == "tmdb" do
        auto_fetch_tmdb_rich_data(socket, image_data)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle category selection in unified image picker
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

  # Handle default image selection
  @impl true
  def handle_event(
        "select_default_image",
        %{"image_url" => image_url, "filename" => filename, "category" => category},
        socket
      ) do
    external_data = %{
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

    # Update form_data with the new image
    form_data =
      Map.merge(socket.assigns.form_data, %{
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

    {ticket, ticket_id} =
      cond do
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
        "suggested_price" =>
          format_price_from_cents(
            Map.get(ticket, :suggested_price_cents, ticket.base_price_cents)
          ),
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
    updated_tickets =
      cond do
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

    # If no tickets remain, update ticketing status
    {updated_form_data, setup_path, is_ticketed} =
      if length(updated_tickets) == 0 do
        form_data =
          socket.assigns.form_data
          |> Map.put("is_ticketed", false)
          # Update taxation type to match non-ticketed status
          |> Map.put("taxation_type", "ticketless")
          # Keep as confirmed but without ticketing
          |> Map.put("setup_path", "confirmed")

        {form_data, "confirmed", false}
      else
        # Keep current ticketing status if tickets still exist
        {socket.assigns.form_data, socket.assigns.setup_path, socket.assigns.is_ticketed}
      end

    socket =
      socket
      |> assign(:tickets, updated_tickets)
      |> assign(:form_data, updated_form_data)
      |> assign(:is_ticketed, is_ticketed)
      |> assign(:setup_path, setup_path)

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
    updated_data =
      if Map.has_key?(ticket_params, "tippable") do
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
            # Determine timezone for ticket date parsing from form data
            tz = Map.get(socket.assigns.form_data || %{}, "timezone") || TimezoneUtils.default_timezone()

            # Create ticket struct
            ticket = %{
              title: Map.get(ticket_data, "title", ""),
              description: Map.get(ticket_data, "description"),
              pricing_model: pricing_model,
              base_price_cents: price_cents,
              minimum_price_cents: minimum_price_cents,
              suggested_price_cents: suggested_price_cents,
              currency:
                Map.get(ticket_data, "currency", get_currency_with_fallback(socket.assigns.user)),
              quantity:
                case Integer.parse(Map.get(ticket_data, "quantity", "0")) do
                  {n, _} when n >= 0 -> n
                  _ -> 0
                end,
              starts_at: parse_datetime_input(Map.get(ticket_data, "starts_at"), tz),
              ends_at: parse_datetime_input(Map.get(ticket_data, "ends_at"), tz),
              tippable: Map.get(ticket_data, "tippable", false) == true
            }

            # Add or update ticket in the list
            updated_tickets =
              case socket.assigns.editing_ticket_id do
                nil ->
                  # Adding new ticket - assign a temporary ID for consistency
                  ticket_with_id =
                    Map.put(ticket, :id, "temp_#{System.unique_integer([:positive])}")

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

            # Update form_data to reflect ticketing is enabled
            updated_form_data =
              socket.assigns.form_data
              |> Map.put("is_ticketed", true)
              # Update taxation type to match ticketed status
              |> Map.put("taxation_type", "ticketed_event")
              # Default to confirmed when tickets are added
              |> Map.put("setup_path", "confirmed")

            socket =
              socket
              |> assign(:tickets, updated_tickets)
              |> assign(:form_data, updated_form_data)
              |> assign(:is_ticketed, true)
              |> assign(:setup_path, "confirmed")
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
    zoom_url = EventasaurusWeb.Helpers.EventHelpers.generate_zoom_meeting_url()

    # Update form data for virtual meeting
    form_data =
      (socket.assigns.form_data || %{})
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
    meet_url = EventasaurusWeb.Helpers.EventHelpers.generate_google_meet_url()

    # Update form data for virtual meeting
    form_data =
      (socket.assigns.form_data || %{})
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
      "venue_longitude" => place_details["geometry"]["location"]["lng"],
      # Store Google Places ID
      "venue_place_id" => Map.get(place_details, "place_id")
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
    component =
      Enum.find(components, fn comp ->
        comp["types"] && Enum.member?(comp["types"], type)
      end)

    if component, do: component["long_name"], else: ""
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp process_datetime_fields(params) do
    params
    # Legacy date polling processing removed
    |> process_start_datetime()
    |> process_end_datetime()
  end

  # Legacy process_date_polling_datetime function removed - using generic polling system

  defp process_start_datetime(params) do
    start_date = Map.get(params, "start_date")
    start_time = Map.get(params, "start_time")
    timezone = Map.get(params, "timezone") || TimezoneUtils.default_timezone()

    case DateTimeHelper.parse_user_datetime(start_date, start_time, timezone) do
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
    timezone = Map.get(params, "timezone") || TimezoneUtils.default_timezone()

    case DateTimeHelper.parse_user_datetime(ends_date, ends_time, timezone) do
      {:ok, datetime} ->
        Map.put(params, "ends_at", datetime)

      {:error, _} ->
        # Keep existing ends_at if combination fails
        params
    end
  end

  # Helper function replaced by DateTimeHelper.parse_user_datetime/3

  # Legacy create_date_poll_for_event function removed - using generic polling system

  # Helper function to create event with proper error handling
  defp create_event_with_validation(final_event_params, socket) do
    # Set the correct status based on setup path
    setup_path = Map.get(socket.assigns.form_data, "setup_path", "confirmed")
    # Legacy date polling logic removed - using generic polling system

    # Determine the correct status
    final_status =
      cond do
        setup_path == "polling" -> "polling"
        setup_path == "threshold" -> "threshold"
        # Default for confirmed events
        true -> "confirmed"
      end

    # Ensure the status is correctly set in the event params
    final_event_params_with_status = Map.put(final_event_params, "status", final_status)

    case Events.create_event_with_organizer(final_event_params_with_status, socket.assigns.user) do
      {:ok, event} ->
        # Legacy date polling creation removed - using generic polling system
        event_with_poll = event

        # If ticketing is enabled, create the tickets
        is_ticketed? = final_event_params["is_ticketed"] in [true, "true"]

        case is_ticketed? and length(socket.assigns.tickets) > 0 do
          true ->
            case create_tickets_for_event(
                   event_with_poll,
                   socket.assigns.tickets,
                   socket.assigns.user
                 ) do
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
                 |> put_flash(
                   :error,
                   "Event created but tickets could not be created. Please edit the event to add tickets."
                 )
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

        Logger.error(
          "[submit] Event creation failed with changeset errors: #{inspect(changeset.errors)}"
        )

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
        default_currency =
          case organizer_user do
            %{default_currency: _} = user -> get_currency_with_fallback(user)
            _ -> "usd"
          end

        ticket_attrs = %{
          title: Map.get(ticket_data, :title),
          description: Map.get(ticket_data, :description),
          pricing_model: Map.get(ticket_data, :pricing_model, "fixed"),
          base_price_cents: Map.get(ticket_data, :base_price_cents),
          minimum_price_cents:
            Map.get(ticket_data, :minimum_price_cents) || Map.get(ticket_data, :base_price_cents),
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

  # Legacy validate_date_polling function removed - using generic polling system

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

  # Helper — clears ticket state unless the path is ticket-centric
  defp maybe_reset_ticketing(socket, path) when path in ["confirmed", "threshold"], do: socket

  defp maybe_reset_ticketing(socket, _path) do
    socket
    |> assign(:tickets, [])
    |> assign(:show_ticket_modal, false)
    |> assign(:ticket_form_data, %{})
    |> assign(:editing_ticket_id, nil)
  end

  # ============================================================================
  # Smart Default Value Helpers
  # ============================================================================

  # Determines smart default for taxation_type based on event characteristics
  defp determine_smart_taxation_default(event_attrs) do
    is_ticketed = Map.get(event_attrs, "is_ticketed", false)

    cond do
      # If ticketing is explicitly enabled, default to ticketed_event
      is_ticketed == true or is_ticketed == "true" ->
        "ticketed_event"

      # For new events with no ticketing, default to ticketless
      # But this will be hidden until tickets are added
      true ->
        "ticketless"
    end
  end

  # Provides reasoning for why a taxation type was selected as default
  defp get_taxation_reasoning(taxation_type, is_existing_event) do
    case {taxation_type, is_existing_event} do
      {"ticketless", false} ->
        "Recommended for most events as they don't collect money"

      {"ticketed_event", false} ->
        "Recommended for events with admission fees or ticket sales"

      {"contribution_collection", false} ->
        "Suggested for donation-based or fundraising events"

      {"ticketless", true} ->
        "Currently configured as a free event with no payment processing"

      {"ticketed_event", true} ->
        "Currently configured for standard ticketed events"

      {"contribution_collection", true} ->
        "Currently configured for contribution-based events"

      _ ->
        "Standard configuration for event taxation"
    end
  end

  # Updates taxation type when ticketing status changes
  defp update_taxation_for_ticketing_change(form_data, is_ticketed) do
    current_taxation = Map.get(form_data, "taxation_type", "ticketless")

    case {is_ticketed, current_taxation} do
      # If enabling ticketing and currently non-revenue type, change to ticketed_event
      {true, taxation_type} when taxation_type in ["ticketless", "contribution_collection"] ->
        form_data
        |> Map.put("taxation_type", "ticketed_event")
        |> Map.put(
          "taxation_type_reasoning",
          "Changed to ticketed_event because ticketing was enabled"
        )

      # If disabling ticketing and currently ticketed_event, suggest ticketless (most common case)
      {false, "ticketed_event"} ->
        form_data
        |> Map.put("taxation_type", "ticketless")
        |> Map.put("taxation_type_reasoning", "Changed to ticketless for non-ticketed events")

      # Otherwise, keep current selection but update reasoning
      _ ->
        Map.put(
          form_data,
          "taxation_type_reasoning",
          get_taxation_reasoning(current_taxation, true)
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

  # ============================================================================
  # Threshold Field Mapping Helpers
  # ============================================================================

  # Maps user-friendly threshold field names from the form to database field names.
  #
  # Form fields:
  # - funding_goal → threshold_revenue_cents (converted from dollars to cents)
  # - funding_deadline → polling_deadline
  # - minimum_attendees → threshold_count
  # - decision_deadline → polling_deadline
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
  # Note: The Event schema uses polling_deadline for all deadline purposes
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
