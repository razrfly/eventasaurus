defmodule EventasaurusWeb.PublicEventShowLive do
  use EventasaurusWeb, :live_view
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.EventPlans
  alias EventasaurusWeb.Components.{PublicPlanWithFriendsModal, Breadcrumbs}
  alias EventasaurusWeb.Components.Events.OccurrenceDisplay
  alias EventasaurusWeb.Components.Events.EventScheduleDisplay
  alias EventasaurusWeb.StaticMapComponent
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Helpers.LanguageDiscovery
  alias EventasaurusWeb.Helpers.LanguageHelpers
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.Helpers.SourceAttribution
  alias EventasaurusWeb.JsonLd.PublicEventSchema
  alias EventasaurusWeb.JsonLd.LocalBusinessSchema
  alias EventasaurusWeb.JsonLd.BreadcrumbListSchema
  alias EventasaurusWeb.UrlHelper
  alias Eventasaurus.CDN
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.EventRefresh
  alias EventasaurusWeb.Cache.EventPageCache
  import Ecto.Query

  @impl true
  def mount(_params, session, socket) do
    # Get language from session (set by LanguagePlug), then connect params, then default to English
    params = get_connect_params(socket) || %{}
    language = session["language"] || params["locale"] || "en"

    # Store URI from connect_info for SEO (only available during connected mount)
    raw_uri = get_connect_info(socket, :uri)

    request_uri =
      cond do
        match?(%URI{}, raw_uri) -> raw_uri
        is_binary(raw_uri) -> URI.parse(raw_uri)
        true -> nil
      end

    socket =
      socket
      |> assign(:language, language)
      |> assign(:request_uri, request_uri)
      |> assign(:event, nil)
      |> assign(:loading, true)
      |> assign(:selected_occurrence, nil)
      |> assign(:selected_showtime_date, nil)
      |> assign(:show_plan_with_friends_modal, false)
      |> assign(:emails_input, "")
      |> assign(:invitation_message, "")
      |> assign(:selected_users, [])
      |> assign(:selected_emails, [])
      |> assign(:current_email_input, "")
      |> assign(:bulk_email_input, "")
      |> assign(:modal_organizer, nil)
      |> assign(:nearby_events, [])
      |> assign(:refreshing_availability, false)
      # Flexible planning assigns
      |> assign(:planning_mode, :selection)
      |> assign(:filter_criteria, %{})
      |> assign(:matching_occurrences, [])
      |> assign(:is_movie_event, false)
      |> assign(:is_venue_event, false)

    {:ok, socket}
  end

  @impl true
  def handle_info({:availability_refreshed, data}, socket) do
    # Handle PubSub broadcast from refresh job (source-agnostic)
    Logger.info(
      "[PublicEventShowLive] Received availability refresh for event #{socket.assigns.event.id}"
    )

    # Re-fetch only the sources to preserve enriched event data (venue, categories, etc.)
    fresh_sources =
      from(pes in PublicEventSource,
        where: pes.event_id == ^socket.assigns.event.id,
        preload: :source
      )
      |> Repo.all()

    # Update only the sources field to preserve all other enriched data
    updated_event = %{socket.assigns.event | sources: fresh_sources}

    socket =
      socket
      |> assign(:event, updated_event)
      |> assign(:refreshing_availability, false)
      |> put_flash(
        :info,
        gettext("Availability updated! %{count} timeslots available.",
          count: data.total_timeslots
        )
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_selected, user}, socket) do
    selected_users = socket.assigns.selected_users ++ [user]
    {:noreply, assign(socket, :selected_users, Enum.uniq_by(selected_users, & &1.id))}
  end

  @impl true
  def handle_info({:email_added, email}, socket) do
    selected_emails = socket.assigns.selected_emails ++ [email]
    {:noreply, assign(socket, :selected_emails, Enum.uniq(selected_emails))}
  end

  @impl true
  def handle_info({:remove_user, user_id}, socket) do
    selected_users = Enum.reject(socket.assigns.selected_users, &(&1.id == user_id))
    {:noreply, assign(socket, :selected_users, selected_users)}
  end

  @impl true
  def handle_info({:remove_email, email}, socket) do
    selected_emails = Enum.reject(socket.assigns.selected_emails, &(&1 == email))
    {:noreply, assign(socket, :selected_emails, selected_emails)}
  end

  @impl true
  def handle_info({:message_updated, message}, socket) do
    {:noreply, assign(socket, :invitation_message, message)}
  end

  @impl true
  def handle_info(:load_nearby_events, socket) do
    # Load nearby events asynchronously after initial page render
    event = socket.assigns.event
    language = socket.assigns.language

    nearby_events =
      if event do
        EventPageCache.get_nearby_events(event.id, 25, language, fn ->
          EventasaurusDiscovery.PublicEvents.get_nearby_activities_with_fallback(
            event,
            initial_radius: 25,
            max_radius: 50,
            display_count: 4,
            language: language
          )
          |> PublicEventsEnhanced.preload_for_image_enrichment()
          |> PublicEventsEnhanced.enrich_event_images(strategy: :own_city)
        end)
      else
        []
      end

    {:noreply, assign(socket, :nearby_events, nearby_events)}
  end

  @impl true
  def handle_params(%{"slug" => slug, "date_slug" => date_slug}, _url, socket) do
    # Handle URL with specific date: /activities/slug/oct-10
    socket =
      socket
      |> fetch_event(slug)
      |> assign(:loading, false)

    socket =
      case parse_date_slug(date_slug) do
        {:ok, date} ->
          # Successfully parsed date from URL, verify it exists in occurrences
          if has_occurrence_on_date?(socket.assigns.event, date) do
            assign(socket, :selected_showtime_date, date)
          else
            socket
            |> put_flash(:error, gettext("No events scheduled for this date"))
            |> push_patch(to: ~p"/activities/#{slug}")
          end

        :error ->
          # Invalid date slug, show error and redirect to base URL
          socket
          |> put_flash(:error, gettext("Invalid date in URL"))
          |> push_patch(to: ~p"/activities/#{slug}")
      end

    {:noreply, socket}
  end

  def handle_params(%{"slug" => slug}, _url, socket) do
    # Handle base URL without date: /activities/slug
    socket =
      socket
      |> fetch_event(slug)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  defp fetch_event(socket, slug) do
    language = socket.assigns.language

    # Use cache for event metadata to speed up initial load
    event_metadata =
      EventPageCache.get_event_metadata(slug, language, fn ->
        event =
          from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
            where: pe.slug == ^slug,
            preload: [
              :categories,
              :performers,
              :movies,
              venue: [city_ref: :country],
              sources: :source
            ]
          )
          |> Repo.one()

        if event do
          # Get primary category ID once to avoid multiple queries
          primary_category_id = get_primary_category_id(event.id)

          # Enrich main event with cover image using unified API
          # Use :own_city strategy so event uses its venue's city Unsplash gallery
          enriched_event =
            [event]
            |> PublicEventsEnhanced.preload_for_image_enrichment()
            |> PublicEventsEnhanced.enrich_event_images(strategy: :own_city)
            |> List.first()
            |> Map.put(:primary_category_id, primary_category_id)
            |> Map.put(:display_title, get_localized_title(event, language))
            |> Map.put(:display_description, get_localized_description(event, language))
            |> Map.put(:occurrence_list, parse_occurrences(event))

          enriched_event
        else
          nil
        end
      end)

    case event_metadata do
      nil ->
        socket
        |> put_flash(:error, gettext("Event not found"))
        |> push_navigate(to: ~p"/activities")

      enriched_event ->
        # Subscribe to PubSub for real-time availability updates
        Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "event:#{enriched_event.id}")

        # Check if user has existing plan (not cached as it's user-specific)
        existing_plan =
          case get_current_user_id(socket) do
            nil -> nil
            user_id -> EventPlans.get_user_plan_for_event(user_id, enriched_event.id)
          end

        # Defer nearby events loading to after initial render
        # This allows the page to load quickly with just the main event
        send(self(), :load_nearby_events)
        nearby_events = []

        movie = get_movie_data(enriched_event)
        is_movie = is_movie_screening?(enriched_event)
        city = if enriched_event.venue, do: enriched_event.venue.city_ref, else: nil
        aggregated_url = get_aggregated_movie_url(movie, city)

        # Build breadcrumb items (used for both visual breadcrumbs and JSON-LD)
        breadcrumb_items =
          BreadcrumbBuilder.build_event_breadcrumbs(enriched_event,
            gettext_backend: EventasaurusWeb.Gettext
          )

        # Get the request URI for canonical URL (stored in assigns during mount)
        request_uri = socket.assigns[:request_uri]
        canonical_path = "/activities/#{enriched_event.slug}"

        # Generate base URL for JSON-LD schemas (use UrlHelper to respect request context)
        base_url = UrlHelper.build_url("", request_uri)
        canonical_url_for_schemas = UrlHelper.build_url(canonical_path, request_uri)

        # Generate JSON-LD structured data
        event_json_ld = PublicEventSchema.generate(enriched_event)

        breadcrumb_json_ld =
          BreadcrumbListSchema.from_breadcrumb_builder_items(
            breadcrumb_items,
            canonical_url_for_schemas,
            base_url
          )

        venue_json_ld =
          if enriched_event.venue do
            LocalBusinessSchema.generate(enriched_event.venue)
          else
            nil
          end

        json_ld_schemas =
          [event_json_ld, breadcrumb_json_ld, venue_json_ld]
          |> Enum.reject(&is_nil/1)

        combined_json_ld = combine_json_ld_schemas(json_ld_schemas)

        # Get image URL for social card
        image_url =
          Map.get(enriched_event, :cover_image_url) || get_placeholder_image_url(enriched_event)

        # Build meta description
        description =
          enriched_event.display_description ||
            truncate_for_description(enriched_event.display_title)

        # Get available languages for this activity's city (dynamic based on country + DB translations)
        available_languages =
          if city && city.slug do
            LanguageDiscovery.get_available_languages_for_city(city.slug)
          else
            ["en"]
          end

        socket
        |> assign(:event, enriched_event)
        |> assign(:selected_occurrence, select_default_occurrence(enriched_event))
        |> assign(:existing_plan, existing_plan)
        # Will be populated asynchronously via handle_info
        |> assign(:nearby_events, nearby_events)
        |> assign(:movie, movie)
        |> assign(:is_movie_screening, is_movie)
        |> assign(:aggregated_movie_url, aggregated_url)
        |> assign(:breadcrumb_items, breadcrumb_items)
        |> assign(:available_languages, available_languages)
        |> SEOHelpers.assign_meta_tags(
          title: enriched_event.display_title,
          description: description,
          image: image_url,
          type: "event",
          canonical_path: canonical_path,
          json_ld: combined_json_ld,
          request_uri: request_uri
        )
    end
  end

  defp get_localized_title(event, language) do
    case event.title_translations do
      nil ->
        event.title

      translations when is_map(translations) ->
        translations[language] || translations["en"] || event.title

      _ ->
        event.title
    end
  end

  defp get_primary_source_ticket_url(event) do
    # Sort sources by priority and find the first one with a valid ticket URL
    sorted_sources = get_sorted_sources(event.sources)

    # Find the first source with a valid ticket URL
    sorted_sources
    |> Enum.find_value(fn source ->
      case source.source_url do
        nil -> nil
        "" -> nil
        url -> url
      end
    end)
  end

  defp get_sorted_sources(sources) do
    sources
    |> Enum.sort_by(fn source ->
      priority =
        case source.metadata do
          %{"priority" => p} when is_integer(p) ->
            p

          %{"priority" => p} when is_binary(p) ->
            case Integer.parse(p) do
              {num, _} -> num
              _ -> 10
            end

          _ ->
            10
        end

      # Newer timestamps first (negative for descending sort)
      ts =
        case source.last_seen_at do
          %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
          _ -> 9_223_372_036_854_775_807
        end

      {priority, ts}
    end)
  end

  defp get_localized_description(event, language) do
    # Sort sources by priority and take the first one's description
    sorted_sources = get_sorted_sources(event.sources)

    case sorted_sources do
      [source | _] ->
        case source.description_translations do
          nil ->
            nil

          translations when is_map(translations) ->
            translations[language] || translations["en"] || nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @impl true
  def handle_event("change_language", %{"language" => language}, socket) do
    # Set cookie to persist language preference
    socket =
      socket
      |> assign(:language, language)
      |> fetch_event(socket.assigns.event.slug)
      # Clear any existing flash
      |> clear_flash()
      |> Phoenix.LiveView.push_event("set_language_cookie", %{language: language})

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_occurrence", %{"index" => index}, socket) do
    occurrence_index = String.to_integer(index)
    occurrence_list = socket.assigns.event.occurrence_list || []

    selected = Enum.at(occurrence_list, occurrence_index)

    {:noreply, assign(socket, :selected_occurrence, selected)}
  end

  @impl true
  def handle_event("select_showtime_date", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, selected_date} ->
        # Update URL to include date slug
        date_slug = date_to_url_slug(selected_date)
        event_slug = socket.assigns.event.slug
        path = ~p"/activities/#{event_slug}/#{date_slug}"
        {:noreply, push_patch(socket, to: path)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_plan_modal", _params, socket) do
    # Debug logging
    require Logger

    Logger.info(
      "Plan with Friends modal - Socket assigns: user=#{inspect(socket.assigns[:user])}, auth_user=#{inspect(socket.assigns[:auth_user])}"
    )

    Logger.info("Selected occurrence: #{inspect(socket.assigns[:selected_occurrence])}")

    cond do
      !socket.assigns[:auth_user] ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Please log in to create private events"))
         |> redirect(to: ~p"/auth/login")}

      socket.assigns[:existing_plan] ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Redirecting to your existing private event..."))
         |> redirect(to: ~p"/events/#{socket.assigns.existing_plan.private_event.slug}")}

      true ->
        # Get authenticated user for the modal
        user = get_authenticated_user(socket)

        # Detect event type for flexible planning
        event = socket.assigns.event
        is_movie = is_movie_screening?(event)
        is_venue = !is_nil(event.venue) && is_nil(get_movie_data(event))

        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, true)
         |> assign(:modal_organizer, user)
         |> assign(:is_movie_event, is_movie)
         |> assign(:is_venue_event, is_venue)
         |> assign(:planning_mode, :selection)}
    end
  end

  @impl true
  def handle_event("close_plan_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_plan_with_friends_modal, false)
     |> assign(:invitation_message, "")
     |> assign(:selected_users, [])
     |> assign(:selected_emails, [])
     |> assign(:current_email_input, "")
     |> assign(:bulk_email_input, "")
     # Reset flexible planning state
     |> assign(:planning_mode, :selection)
     |> assign(:filter_criteria, %{})
     |> assign(:matching_occurrences, [])}
  end

  @impl true
  def handle_event("select_planning_mode", %{"mode" => mode}, socket) do
    planning_mode =
      case mode do
        "quick" -> :quick
        "flexible" -> :flexible_filters
        "selection" -> :selection
        "flexible_filters" -> :flexible_filters
        _ -> :selection
      end

    {:noreply, assign(socket, :planning_mode, planning_mode)}
  end

  @impl true
  def handle_event("apply_flexible_filters", params, socket) do
    # Parse selected dates and convert to date range
    selected_dates = Map.get(params, "selected_dates", [])

    {date_from, date_to} =
      if length(selected_dates) > 0 do
        dates = Enum.map(selected_dates, &Date.from_iso8601!/1) |> Enum.sort(Date)
        {List.first(dates), List.last(dates)}
      else
        # Default to next 7 days if no dates selected
        {Date.utc_today(), Date.utc_today() |> Date.add(7)}
      end

    # Parse filter criteria from form
    filter_criteria = %{
      selected_dates: selected_dates,
      date_from: Date.to_iso8601(date_from),
      date_to: Date.to_iso8601(date_to),
      time_preferences: Map.get(params, "time_preferences", []),
      meal_periods: Map.get(params, "meal_periods", []),
      limit: String.to_integer(params["limit"] || "10")
    }

    # Query for matching occurrences
    event = socket.assigns.event
    movie = get_movie_data(event)
    venue = get_venue_data(event)

    matching_occurrences =
      cond do
        movie ->
          query_movie_occurrences(movie.id, filter_criteria)

        venue && !movie ->
          query_venue_occurrences(venue.id, filter_criteria)

        true ->
          []
      end

    {:noreply,
     socket
     |> assign(:filter_criteria, filter_criteria)
     |> assign(:matching_occurrences, matching_occurrences)
     |> assign(:planning_mode, :flexible_review)}
  end

  @impl true
  def handle_event("view_existing_plan", _params, socket) do
    case socket.assigns.existing_plan do
      %{private_event: private_event} ->
        {:noreply, redirect(socket, to: ~p"/events/#{private_event.slug}")}

      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("No existing plan found"))
         |> push_navigate(to: ~p"/activities")}
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :invitation_message, message)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_email", _params, socket) do
    email = socket.assigns.current_email_input

    if is_valid_email?(email) do
      selected_emails = [email | socket.assigns.selected_emails] |> Enum.uniq()

      {:noreply,
       socket
       |> assign(:selected_emails, selected_emails)
       # Clear the input field after adding
       |> assign(:current_email_input, "")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_email_on_enter", _params, socket) do
    # Same as add_email - handles Enter key press
    handle_event("add_email", %{}, socket)
  end

  @impl true
  def handle_event("remove_email", %{"index" => index_string}, socket) do
    index = String.to_integer(index_string)
    selected_emails = List.delete_at(socket.assigns.selected_emails, index)
    {:noreply, assign(socket, :selected_emails, selected_emails)}
  end

  @impl true
  def handle_event("email_input_change", %{"email_input" => email_input}, socket) do
    {:noreply, assign(socket, :current_email_input, email_input)}
  end

  @impl true
  def handle_event("clear_all_emails", _params, socket) do
    {:noreply, assign(socket, :selected_emails, [])}
  end

  @impl true
  def handle_event("refresh_availability", _params, socket) do
    event = socket.assigns.event
    user_id = get_current_user_id(socket)

    case EventRefresh.refresh_event(event.id, user_id: user_id) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:refreshing_availability, true)
         |> put_flash(:info, gettext("Refreshing availability..."))}

      {:error, :no_refreshable_source} ->
        {:noreply,
         put_flash(socket, :error, gettext("This event does not support availability refresh"))}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Please wait a moment before refreshing again")
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to refresh availability"))}
    end
  end

  @impl true
  def handle_event("submit_plan_with_friends", %{"mode" => mode}, socket) do
    case mode do
      "quick" -> handle_quick_plan_submit(socket)
      "flexible" -> handle_flexible_plan_submit(socket)
      _ -> handle_quick_plan_submit(socket)
    end
  end

  @impl true
  def handle_event("submit_plan_with_friends", _params, socket) do
    # Fallback for old submit events without mode parameter
    handle_quick_plan_submit(socket)
  end

  defp handle_quick_plan_submit(socket) do
    case create_plan_from_public_event(socket) do
      {:ok, {:created, private_event}} ->
        # Send invitations to selected users and emails
        organizer = get_authenticated_user(socket)

        send_invitations(
          private_event,
          socket.assigns.selected_users,
          socket.assigns.selected_emails,
          socket.assigns.invitation_message,
          organizer
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Your private event has been created!"))
         |> redirect(to: ~p"/events/#{private_event.slug}")}

      {:ok, {:existing, private_event}} ->
        # For existing events, show different message and don't send invitations again
        {:noreply,
         socket
         |> put_flash(:info, gettext("Redirecting to your existing private event..."))
         |> redirect(to: ~p"/events/#{private_event.slug}")}

      {:error, :event_in_past} ->
        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, false)
         |> put_flash(
           :error,
           gettext("Cannot create plans for events that have already occurred")
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, false)
         |> put_flash(
           :error,
           gettext("Sorry, there was an error creating your private event. Please try again.")
         )}
    end
  end

  defp handle_flexible_plan_submit(socket) do
    alias EventasaurusApp.Planning.OccurrencePlanningWorkflow

    user = get_authenticated_user(socket)
    event = socket.assigns.event
    movie = get_movie_data(event)

    # Ensure we have movie data
    if is_nil(movie) do
      {:noreply,
       socket
       |> assign(:show_plan_with_friends_modal, false)
       |> put_flash(
         :error,
         gettext("This event is not a movie screening. Flexible planning is only available for movies.")
       )}
    else
      # Get friend IDs from selected users
      friend_ids = Enum.map(socket.assigns.selected_users, & &1.id)

      # Convert filter criteria to workflow format
      filter_criteria = %{
        date_range: parse_date_range(socket.assigns.filter_criteria),
        time_preferences: socket.assigns.filter_criteria[:time_preferences] || [],
        limit: socket.assigns.filter_criteria[:limit] || 10
      }

      # Create flexible planning with poll
      case OccurrencePlanningWorkflow.start_flexible_planning(
             "movie",
             movie.id,
             user.id,
             filter_criteria,
             friend_ids,
             event_title: "#{movie.title} - Group Planning",
             poll_title: "Which showtime works best?"
           ) do
      {:ok, result} ->
        # Send email invitations to non-user emails
        if socket.assigns.selected_emails != [] do
          # Note: Would need to implement email invitation logic for polls
          # For now, just log that we would send emails
          require Logger

          Logger.info(
            "Would send poll invitations to emails: #{inspect(socket.assigns.selected_emails)}"
          )
        end

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Poll created! Your friends can now vote on their preferred showtime.")
         )
         |> redirect(to: ~p"/events/#{result.private_event.slug}")}

      {:error, :no_occurrences_found} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("No showtimes found matching your filters. Please try different criteria.")
         )}

        {:error, reason} ->
          require Logger
          Logger.error("Flexible planning failed: #{inspect(reason)}")

          # Show detailed error in development
          error_message =
            if Mix.env() == :dev do
              "Error creating poll: #{inspect(reason)}"
            else
              gettext("Sorry, there was an error creating your poll. Please try again.")
            end

          {:noreply,
           socket
           |> assign(:show_plan_with_friends_modal, false)
           |> put_flash(:error, error_message)}
      end
    end
  end

  defp create_plan_from_public_event(socket) do
    user = get_authenticated_user(socket)

    # Get the datetime from selected occurrence, or fall back to event starts_at
    occurrence_datetime =
      case socket.assigns.selected_occurrence do
        %{datetime: datetime} -> datetime
        _ -> socket.assigns.event.starts_at
      end

    EventPlans.create_from_public_event(
      socket.assigns.event.id,
      user.id,
      %{occurrence_datetime: occurrence_datetime}
    )
    |> case do
      {:ok, {:created, _event_plan, private_event}} -> {:ok, {:created, private_event}}
      {:ok, {:existing, _event_plan, private_event}} -> {:ok, {:existing, private_event}}
      error -> error
    end
  end

  defp get_current_user_id(socket) do
    cond do
      # Try processed user from database first
      socket.assigns[:user] && socket.assigns.user.id ->
        socket.assigns.user.id

      # Try current_user (might be the correct key)
      socket.assigns[:current_user] && socket.assigns.current_user.id ->
        socket.assigns.current_user.id

      # Try auth_user from Supabase/dev mode
      socket.assigns[:auth_user] ->
        case socket.assigns.auth_user do
          # Dev mode: User struct directly
          %{id: id} when is_integer(id) -> id
          # Supabase auth: map with string id
          %{"id" => id} when is_binary(id) -> String.to_integer(id)
          %{id: id} when is_binary(id) -> String.to_integer(id)
          _ -> nil
        end

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  defp get_authenticated_user(socket) do
    # First try the processed user from the database
    case socket.assigns[:user] do
      %{id: id} = user when not is_nil(id) ->
        user

      _ ->
        # Fallback to raw auth_user from Supabase/dev mode
        case socket.assigns[:auth_user] do
          # Dev mode: User struct directly
          %{id: id} = user when is_integer(id) ->
            user

          # Supabase auth: map with string id
          %{"id" => id} = auth_user when is_binary(id) ->
            auth_user

          # Handle other possible formats
          %{id: id} = auth_user when is_binary(id) ->
            auth_user

          _ ->
            raise "No authenticated user found"
        end
    end
  end

  defp send_invitations(event, selected_users, selected_emails, message, organizer) do
    # Convert selected users to suggestion structs format expected by process_guest_invitations
    suggestion_structs =
      Enum.map(selected_users, fn user ->
        %{
          user_id: user.id,
          name: user.name,
          email: user.email,
          username: Map.get(user, :username),
          avatar_url: Map.get(user, :avatar_url)
        }
      end)

    # Process invitations using the same function as the manager area
    # Using :invitation mode since this is from the public event page (not managing existing event)
    EventasaurusApp.Events.process_guest_invitations(
      event,
      organizer,
      suggestion_structs: suggestion_structs,
      manual_emails: selected_emails,
      invitation_message: message || "",
      # Use invitation mode for public plan modal
      mode: :invitation
    )
  end

  # Removed duplicate get_movie_data/1 - see line 1861 for the canonical version

  defp query_movie_occurrences(movie_id, filter_criteria) do
    alias EventasaurusApp.Planning.OccurrenceQuery

    # Convert filter criteria to format expected by OccurrenceQuery
    query_criteria = %{
      date_range: parse_date_range(filter_criteria),
      time_preferences: Map.get(filter_criteria, :time_preferences, []),
      limit: Map.get(filter_criteria, :limit, 10)
    }

    case OccurrenceQuery.find_movie_occurrences(movie_id, query_criteria) do
      {:ok, occurrences} -> occurrences
      {:error, _reason} -> []
    end
  end

  defp get_venue_data(event) do
    # Extract venue data from event's venue association
    case event.venue do
      %{id: _id} = venue ->
        venue

      _ ->
        nil
    end
  end

  defp query_venue_occurrences(venue_id, filter_criteria) do
    alias EventasaurusApp.Planning.OccurrenceQuery

    # Convert filter criteria to format expected by OccurrenceQuery
    query_criteria = %{
      date_range: parse_date_range(filter_criteria),
      meal_periods: Map.get(filter_criteria, :meal_periods, []),
      limit: Map.get(filter_criteria, :limit, 10)
    }

    case OccurrenceQuery.find_venue_occurrences(venue_id, query_criteria) do
      {:ok, occurrences} -> occurrences
      {:error, _reason} -> []
    end
  end

  defp parse_date_range(%{date_from: date_from_str, date_to: date_to_str})
       when is_binary(date_from_str) and is_binary(date_to_str) do
    with {:ok, date_from} <- Date.from_iso8601(date_from_str),
         {:ok, date_to} <- Date.from_iso8601(date_to_str) do
      # Return map format for JSON compatibility
      %{start: date_from, end: date_to}
    else
      _ ->
        # Fallback to default date range (today + 7 days)
        today = Date.utc_today()
        %{start: today, end: Date.add(today, 7)}
    end
  end

  defp parse_date_range(_filter_criteria) do
    # Fallback for missing or invalid date range
    today = Date.utc_today()
    %{start: today, end: Date.add(today, 7)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @loading do %>
        <div class="flex justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
        </div>
      <% else %>
        <%= if @event do %>
          <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <!-- Language Switcher - Dynamic based on city -->
            <div class="flex justify-end mb-4">
              <div class="flex bg-gray-100 rounded-lg p-1">
                <%= for lang <- @available_languages do %>
                  <button
                    phx-click="change_language"
                    phx-value-language={lang}
                    class={"px-3 py-1.5 rounded text-sm font-medium transition-colors #{if @language == lang, do: "bg-white shadow-sm text-blue-600", else: "text-gray-600 hover:text-gray-900"}"}
                    title={LanguageHelpers.language_name(lang)}
                  >
                    <%= LanguageHelpers.language_flag(lang) %> <%= String.upcase(lang) %>
                  </button>
                <% end %>
              </div>
            </div>

            <!-- Breadcrumb -->
            <Breadcrumbs.breadcrumb items={@breadcrumb_items} class="mb-6" />

            <!-- Past Event Banner -->
            <%= if event_is_past?(@event) do %>
              <div class="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
                <div class="flex items-start">
                  <Heroicons.clock class="w-6 h-6 text-yellow-600 mr-3 flex-shrink-0 mt-0.5" />
                  <div>
                    <p class="text-yellow-800 font-semibold">
                      <%= gettext("This event has already occurred") %>
                    </p>
                    <p class="text-yellow-700 text-sm mt-1">
                      <%= gettext("This is an archived event page. The event took place on %{date}.",
                          date: format_event_datetime(@event.starts_at)) %>
                    </p>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Event Header -->
            <div class="bg-white rounded-lg shadow-lg overflow-hidden">
              <!-- Cover Image - for movie screenings, only use movie backdrop; for other events, use event cover -->
              <%= if @is_movie_screening do %>
                <%= if @movie && @movie.backdrop_url do %>
                  <div class="h-96 relative">
                    <img
                      src={CDN.url(@movie.backdrop_url, width: 1200, quality: 90)}
                      alt={@movie.title}
                      class="w-full h-full object-cover"
                    />
                  </div>
                <% end %>
              <% else %>
                <%= if Map.get(@event, :cover_image_url) do %>
                  <div class="h-96 relative">
                    <img
                      src={CDN.url(Map.get(@event, :cover_image_url), width: 1200, quality: 90)}
                      alt={@event.display_title}
                      class="w-full h-full object-cover"
                    />
                  </div>
                <% end %>
              <% end %>

              <div class="p-8">
                <!-- Categories -->
                <%= if @event.categories && @event.categories != [] do %>
                  <div class="mb-4">
                    <!-- Primary Category -->
                    <% primary_category = get_primary_category(@event) %>
                    <% secondary_categories = get_secondary_categories(@event) %>

                    <div class="flex flex-wrap gap-2 items-center">
                      <!-- Primary category - larger and emphasized -->
                      <%= if primary_category do %>
                        <.link
                          navigate={~p"/activities?#{[category: primary_category.slug]}"}
                          class="inline-flex items-center px-4 py-2 rounded-full text-sm font-semibold text-white hover:opacity-90 transition"
                          style={safe_background_style(primary_category.color)}
                        >
                          <%= if primary_category.icon do %>
                            <span class="mr-1"><%= primary_category.icon %></span>
                          <% end %>
                          <%= primary_category.name %>
                        </.link>
                      <% end %>

                      <!-- Secondary categories - smaller and less emphasized -->
                      <%= if secondary_categories != [] do %>
                        <span class="text-gray-400 mx-1">•</span>
                        <%= for category <- secondary_categories do %>
                          <.link
                            navigate={~p"/activities?#{[category: category.slug]}"}
                            class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 transition"
                          >
                            <%= category.name %>
                          </.link>
                        <% end %>
                      <% end %>
                    </div>

                    <!-- Category hint text -->
                    <p class="mt-2 text-xs text-gray-500">
                      <%= if secondary_categories != [] do %>
                        <%= gettext("Also filed under: %{categories}",
                            categories: Enum.map_join(secondary_categories, ", ", & &1.name)) %>
                      <% else %>
                        <%= gettext("Click category to see related events") %>
                      <% end %>
                    </p>
                  </div>
                <% end %>

                <!-- Title -->
                <h1 class="text-4xl font-bold text-gray-900 mb-6">
                  <%= @event.display_title %>
                </h1>

                <!-- Movie Information Section (for movie screenings) -->
                <%= if @is_movie_screening && @movie do %>
                  <div class="mb-8 p-6 bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg border border-blue-100">
                    <div class="flex flex-col md:flex-row gap-6">
                      <!-- Movie Poster -->
                      <%= if @movie.poster_url do %>
                        <div class="flex-shrink-0">
                          <img
                            src={CDN.url(@movie.poster_url, width: 200, height: 300, fit: "cover", quality: 90)}
                            alt={"#{@movie.title} poster"}
                            class="w-32 h-48 object-cover rounded-lg shadow-lg"
                            loading="lazy"
                          />
                        </div>
                      <% end %>

                      <!-- Movie Details -->
                      <div class="flex-1 space-y-4">
                        <div>
                          <h2 class="text-2xl font-bold text-gray-900 mb-2">
                            <%= @movie.title %>
                            <%= if @movie.release_date do %>
                              <span class="text-lg font-normal text-gray-600">
                                (<%= Calendar.strftime(@movie.release_date, "%Y") %>)
                              </span>
                            <% end %>
                          </h2>
                          <%= if @movie.original_title && @movie.original_title != @movie.title do %>
                            <p class="text-sm text-gray-600 italic">
                              <%= gettext("Original title:") %> <%= @movie.original_title %>
                            </p>
                          <% end %>
                        </div>

                        <!-- Movie Metadata -->
                        <div class="flex flex-wrap gap-4 text-sm">
                          <%= if @movie.runtime do %>
                            <div class="flex items-center text-gray-700">
                              <Heroicons.clock class="w-4 h-4 mr-1" />
                              <span><%= format_movie_runtime(@movie.runtime) %></span>
                            </div>
                          <% end %>

                          <%= if genres = get_in(@movie.metadata, ["genres"]) do %>
                            <%= if is_list(genres) && length(genres) > 0 do %>
                              <div class="flex flex-wrap gap-2">
                                <%= for genre <- Enum.take(genres, 3) do %>
                                  <span class="px-2 py-1 bg-blue-100 text-blue-800 rounded-full text-xs font-medium">
                                    <%= genre %>
                                  </span>
                                <% end %>
                              </div>
                            <% end %>
                          <% end %>
                        </div>

                        <!-- Movie Overview -->
                        <%= if @movie.overview do %>
                          <div>
                            <p class="text-gray-700 leading-relaxed line-clamp-3">
                              <%= @movie.overview %>
                            </p>
                          </div>
                        <% end %>

                        <!-- Links Row -->
                        <div class="flex flex-wrap gap-3">
                          <!-- See All Screenings Link -->
                          <%= if @aggregated_movie_url do %>
                            <.link
                              navigate={@aggregated_movie_url}
                              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition"
                            >
                              <Heroicons.film class="w-4 h-4 mr-2" />
                              <%= gettext("See All Screenings") %>
                            </.link>
                          <% end %>

                          <!-- TMDB Link -->
                          <%= if @movie.tmdb_id do %>
                            <a
                              href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center px-4 py-2 bg-white border border-gray-300 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-50 transition"
                            >
                              <svg class="w-4 h-4 mr-2" viewBox="0 0 24 24" fill="#01b4e4">
                                <path d="M11.42 2c-4.05 0-7.34 3.28-7.34 7.33 0 4.05 3.29 7.33 7.34 7.33 4.05 0 7.33-3.28 7.33-7.33C18.75 5.28 15.47 2 11.42 2zM8.85 14.4l-1.34-2.8 2.59-5.4h1.93l-2.17 4.52L12.4 8.4h1.8l-2.59 5.4H9.68l2.17-4.52L9.31 11.6H7.51L8.85 14.4z"/>
                              </svg>
                              <%= gettext("View on TMDB") %>
                            </a>
                          <% end %>
                        </div>

                        <!-- TMDB Attribution -->
                        <p class="text-xs text-gray-500 mt-2">
                          <%= gettext("Movie data provided by") %>
                          <a
                            href="https://www.themoviedb.org/"
                            target="_blank"
                            rel="noopener noreferrer"
                            class="text-blue-600 hover:text-blue-800 underline"
                          >
                            The Movie Database (TMDB)
                          </a>.
                          <%= gettext("This product uses the TMDB API but is not endorsed or certified by TMDB.") %>
                        </p>
                      </div>
                    </div>
                  </div>
                <% end %>

                <!-- Key Details Grid -->
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                  <!-- Event Schedule (Date & Time or Screening Schedule) -->
                  <EventScheduleDisplay.event_schedule_display
                    event={@event}
                    occurrence_list={@event.occurrence_list || []}
                    selected_occurrence={@selected_occurrence}
                    is_movie_screening={@is_movie_screening}
                  />

                  <!-- Venue -->
                  <%= if @event.venue do %>
                    <div>
                      <div class="flex items-center text-gray-600 mb-1">
                        <Heroicons.map_pin class="w-5 h-5 mr-2" />
                        <span class="font-medium"><%= gettext("Venue") %></span>
                      </div>
                      <p class="text-gray-900">
                        <.link
                          navigate={~p"/venues/#{@event.venue.slug}"}
                          class="font-semibold hover:text-indigo-600 transition-colors"
                        >
                          <%= @event.venue.name %>
                        </.link>
                        <%= if @event.venue.address do %>
                          <br />
                          <span class="text-sm text-gray-600">
                            <%= @event.venue.address %>
                          </span>
                        <% end %>
                      </p>
                    </div>
                  <% end %>

                  <!-- Map Display -->
                  <%= if @event.venue do %>
                    <div class="mt-6">
                      <.live_component
                        module={StaticMapComponent}
                        id="event-location-map"
                        venue={@event.venue}
                        theme={:minimal}
                        size={:medium}
                      />
                    </div>
                  <% end %>

                  <%!-- Price display temporarily hidden - no APIs provide price data
                       Infrastructure retained for future API support
                       See GitHub issue #1281 for details
                  <!-- Price -->
                  <div>
                    <div class="flex items-center text-gray-600 mb-1">
                      <Heroicons.currency_dollar class="w-5 h-5 mr-2" />
                      <span class="font-medium"><%= gettext("Price") %></span>
                    </div>
                    <p class="text-gray-900">
                      <%= format_price_range(@event) %>
                    </p>
                  </div>
                  --%>

                  <!-- Ticket Link -->
                  <%= if ticket_url = get_primary_source_ticket_url(@event) do %>
                    <div>
                      <a
                        href={ticket_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
                      >
                        <Heroicons.ticket class="w-5 h-5 mr-2" />
                        <%= gettext("Get Tickets") %>
                      </a>
                    </div>
                  <% end %>

                  <!-- Plan with Friends Button (Only for future events) -->
                  <%= unless event_is_past?(@event) do %>
                    <div>
                      <%= if @existing_plan do %>
                        <!-- User already has a plan - show different button -->
                        <div class="space-y-2">
                          <button
                            phx-click="view_existing_plan"
                            class="inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
                          >
                            <Heroicons.eye class="w-5 h-5 mr-2" />
                            <%= gettext("View Your Event") %>
                          </button>
                          <!-- Plan status indicator -->
                          <div class="text-sm text-gray-600 flex items-center">
                            <Heroicons.check_circle class="w-4 h-4 mr-1 text-green-500" />
                            <%= gettext("Created %{date}", date: format_plan_date(@existing_plan.inserted_at)) %>
                          </div>
                        </div>
                      <% else %>
                        <!-- No existing plan - show create button -->
                        <button
                          phx-click="open_plan_modal"
                          class="inline-flex items-center px-6 py-3 bg-green-600 text-white font-medium rounded-lg hover:bg-green-700 transition"
                        >
                          <Heroicons.user_group class="w-5 h-5 mr-2" />
                          <%= gettext("Plan with Friends") %>
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <!-- Multiple Occurrences Selection -->
                <%= if @event.occurrence_list && length(@event.occurrence_list) > 1 do %>
                  <OccurrenceDisplay.occurrence_display
                    event={@event}
                    occurrence_list={@event.occurrence_list}
                    selected_occurrence={@selected_occurrence}
                    selected_showtime_date={@selected_showtime_date}
                    is_movie_screening={@is_movie_screening}
                  />
                <% end %>

                <!-- Description -->
                <%= if @event.display_description do %>
                  <div class="mb-8">
                    <h2 class="text-2xl font-semibold text-gray-900 mb-4">
                      <%= gettext("About This Event") %>
                    </h2>
                    <div class="prose max-w-none text-gray-700">
                      <%= format_description(@event.display_description) %>
                    </div>
                  </div>
                <% end %>

                <!-- Performers -->
                <%= if @event.performers && @event.performers != [] do %>
                  <div class="mb-8">
                    <h2 class="text-2xl font-semibold text-gray-900 mb-4">
                      <%= gettext("Performers") %>
                    </h2>
                    <div class="flex flex-wrap gap-3">
                      <%= for performer <- @event.performers do %>
                        <a
                          href={~p"/performers/#{performer.slug}"}
                          class="px-4 py-2 bg-gray-100 rounded-lg text-gray-800 font-medium hover:bg-indigo-100 hover:text-indigo-800 transition-colors"
                        >
                          <%= performer.name %>
                        </a>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <!-- Sources -->
                <div class="mt-12 pt-8 border-t border-gray-200">
                  <div class="flex justify-between items-center mb-3">
                    <h3 class="text-sm font-medium text-gray-500">
                      <%= gettext("Event Sources") %>
                    </h3>

                    <%!-- Show refresh button if event supports availability refresh --%>
                    <%= if EventRefresh.refreshable?(@event) do %>
                      <button
                        phx-click="refresh_availability"
                        disabled={@refreshing_availability}
                        class={"inline-flex items-center px-3 py-1.5 text-sm font-medium rounded-lg transition #{if @refreshing_availability, do: "bg-gray-300 text-gray-500 cursor-not-allowed", else: "bg-blue-600 text-white hover:bg-blue-700"}"}
                      >
                        <%= if @refreshing_availability do %>
                          <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-gray-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                          <%= gettext("Refreshing...") %>
                        <% else %>
                          <Heroicons.arrow_path class="w-4 h-4 mr-1.5" />
                          <%= gettext("Refresh Availability") %>
                        <% end %>
                      </button>
                    <% end %>
                  </div>

                  <div class="flex flex-wrap gap-4">
                    <%= for source <- @event.sources do %>
                      <% source_url = SourceAttribution.get_source_url(source) %>
                      <% source_name = SourceAttribution.get_source_name(source) %>
                      <div class="text-sm">
                        <%= if source_url do %>
                          <a href={source_url} target="_blank" rel="noopener noreferrer" class="font-medium text-blue-600 hover:text-blue-800">
                            <%= source_name %>
                            <Heroicons.arrow_top_right_on_square class="w-3 h-3 inline ml-1" />
                          </a>
                        <% else %>
                          <span class="font-medium text-gray-700">
                            <%= source_name %>
                          </span>
                        <% end %>
                        <span class="text-gray-500 ml-2">
                          <%= gettext("Last updated") %> <%= SourceAttribution.format_relative_time(source.last_seen_at) %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <!-- Related Events -->
            <.live_component
              module={EventasaurusWeb.Components.NearbyEventsComponent}
              id="nearby-events"
              events={@nearby_events}
              language={@language}
            />
          </div>
        <% end %>
      <% end %>

      <!-- Plan with Friends Modal -->
      <%= if @show_plan_with_friends_modal do %>
        <PublicPlanWithFriendsModal.modal
          id="plan-with-friends-modal"
          show={@show_plan_with_friends_modal}
          public_event={@event}
          selected_occurrence={@selected_occurrence}
          selected_users={@selected_users}
          selected_emails={@selected_emails}
          current_email_input={@current_email_input}
          bulk_email_input={@bulk_email_input}
          invitation_message={@invitation_message}
          organizer={@modal_organizer}
          on_close="close_plan_modal"
          on_submit="submit_plan_with_friends"
          planning_mode={@planning_mode}
          filter_criteria={@filter_criteria}
          matching_occurrences={@matching_occurrences}
          is_movie_event={@is_movie_event}
          is_venue_event={@is_venue_event}
        />
      <% end %>
    </div>

    <div id="language-cookie-hook" phx-hook="LanguageCookie"></div>
    """
  end

  # Helper Functions
  defp format_event_datetime(nil), do: gettext("TBD")

  defp format_event_datetime(datetime) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  # Commented out - price display temporarily hidden as no APIs provide price data
  # See GitHub issue #1281 for details
  # defp format_price_range(event) do
  #   symbol = currency_symbol(event.currency)
  #
  #   cond do
  #     event.min_price && event.max_price && event.min_price == event.max_price ->
  #       "#{symbol}#{event.min_price}"
  #
  #     event.min_price && event.max_price ->
  #       "#{symbol}#{event.min_price} - #{symbol}#{event.max_price}"
  #
  #     event.min_price ->
  #       gettext("From %{price}", price: "#{symbol}#{event.min_price}")
  #
  #     event.max_price ->
  #       gettext("Up to %{price}", price: "#{symbol}#{event.max_price}")
  #
  #     true ->
  #       gettext("See details")
  #   end
  # end
  #
  # defp currency_symbol(nil), do: "$"
  # defp currency_symbol("USD"), do: "$"
  # defp currency_symbol("EUR"), do: "€"
  # defp currency_symbol("PLN"), do: "zł"
  # defp currency_symbol(_), do: "$"

  defp format_description(nil), do: Phoenix.HTML.raw("")

  defp format_description(description) do
    # Escapes HTML and converts newlines to <br>, returning Safe HTML
    Phoenix.HTML.Format.text_to_html(description, escape: true)
  end

  defp format_plan_date(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> SourceAttribution.format_relative_time(dt)
      {:error, _} -> gettext("recently")
    end
  end

  # Occurrence helper functions
  defp parse_occurrences(%{occurrences: nil}), do: nil

  defp parse_occurrences(%{occurrences: %{"dates" => dates}} = event) when is_list(dates) do
    # Get timezone for this venue (defaults to Poland timezone)
    timezone = get_event_timezone(event)
    require Logger
    Logger.info("Timezone for event: #{inspect(timezone)}")

    now = DateTime.utc_now()

    dates
    |> Enum.map(fn date_info ->
      with {:ok, date} <- Date.from_iso8601(date_info["date"]),
           {:ok, time} <- parse_time(date_info["time"]) do
        # Create datetime in UTC (as stored in database)
        utc_datetime = DateTime.new!(date, time, "Etc/UTC")

        # Convert to local timezone for display
        local_datetime = DateTime.shift_zone!(utc_datetime, timezone)

        %{
          datetime: local_datetime,
          date: DateTime.to_date(local_datetime),
          time: DateTime.to_time(local_datetime),
          external_id: date_info["external_id"],
          label: date_info["label"]
        }
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    # Filter out past occurrences - keep only future events
    |> Enum.filter(fn occurrence ->
      DateTime.compare(occurrence.datetime, now) == :gt
    end)
    |> Enum.sort_by(& &1.datetime, DateTime)
  end

  # Handle pattern-type occurrences (e.g., "every Wednesday at 8pm")
  defp parse_occurrences(%{occurrences: %{"type" => "pattern", "pattern" => pattern}} = event) do
    timezone = get_event_timezone(event)
    calculate_upcoming_from_pattern(pattern, timezone, 4)
  end

  defp parse_occurrences(_), do: nil

  # Calculate upcoming occurrences from a recurring pattern.
  #
  # Pattern structure:
  # %{
  #   "frequency" => "weekly",
  #   "days_of_week" => ["wednesday", "friday"],
  #   "time" => "20:00",
  #   "timezone" => "Europe/Warsaw"
  # }
  defp calculate_upcoming_from_pattern(pattern, timezone, count) do
    # Safe pattern access with defaults
    frequency = Map.fetch!(pattern, "frequency")
    time_str = Map.fetch!(pattern, "time")
    days_of_week = Map.get(pattern, "days_of_week", [])

    # Pattern timezone takes precedence over venue timezone
    tz = pattern["timezone"] || timezone

    # Parse time
    {:ok, time} = parse_time(time_str)

    # Get today's date in the target timezone
    now = DateTime.now!(tz)
    today = DateTime.to_date(now)

    # Convert day names to integers (1 = Monday, 7 = Sunday)
    target_weekdays =
      days_of_week
      |> Enum.map(&day_name_to_number/1)
      |> Enum.sort()

    case frequency do
      "weekly" ->
        # Generate upcoming dates matching target weekdays, take first N future occurrences
        Stream.iterate(today, &Date.add(&1, 1))
        |> Stream.filter(fn d -> Date.day_of_week(d) in target_weekdays end)
        |> Stream.map(fn d ->
          case DateTime.new(d, time, tz) do
            {:ok, dt} ->
              %{
                datetime: dt,
                date: d,
                time: time,
                pattern: format_pattern_description(frequency, days_of_week, time_str)
              }

            {:error, _} ->
              nil
          end
        end)
        |> Stream.reject(&is_nil/1)
        |> Stream.filter(fn occ -> DateTime.compare(occ.datetime, now) == :gt end)
        |> Enum.take(count)

      "daily" ->
        # Generate next N future daily occurrences
        Stream.iterate(today, &Date.add(&1, 1))
        |> Stream.map(fn d ->
          case DateTime.new(d, time, tz) do
            {:ok, dt} ->
              %{
                datetime: dt,
                date: d,
                time: time,
                pattern: format_pattern_description(frequency, days_of_week, time_str)
              }

            {:error, _} ->
              nil
          end
        end)
        |> Stream.reject(&is_nil/1)
        |> Stream.filter(fn occ -> DateTime.compare(occ.datetime, now) == :gt end)
        |> Enum.take(count)

      _ ->
        # Unsupported frequency - return empty list
        []
    end
  end

  # Convert day name string to ISO day number (1 = Monday, 7 = Sunday).
  defp day_name_to_number(day) when is_binary(day) do
    case String.downcase(day) do
      "monday" -> 1
      "tuesday" -> 2
      "wednesday" -> 3
      "thursday" -> 4
      "friday" -> 5
      "saturday" -> 6
      "sunday" -> 7
      _ -> 1
    end
  end

  # Format pattern description for display (e.g., "Every Wednesday at 8:00 PM").
  defp format_pattern_description("weekly", days_of_week, time_str) do
    days =
      days_of_week
      |> Enum.map(&capitalize_day/1)
      |> format_day_list()

    time = format_time_12h(time_str)
    "Every #{days} at #{time}"
  end

  defp format_pattern_description("daily", _days, time_str) do
    time = format_time_12h(time_str)
    "Daily at #{time}"
  end

  defp format_pattern_description(_frequency, _days, time_str) do
    time = format_time_12h(time_str)
    "Regularly at #{time}"
  end

  defp capitalize_day(day), do: String.capitalize(day)

  defp format_day_list([day]), do: day
  defp format_day_list([day1, day2]), do: "#{day1} and #{day2}"

  defp format_day_list(days) when length(days) > 2 do
    [last | rest] = Enum.reverse(days)
    rest_str = rest |> Enum.reverse() |> Enum.join(", ")
    "#{rest_str}, and #{last}"
  end

  # Format time string to 12-hour format with AM/PM.
  defp format_time_12h(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [h, m | _] ->
        hour = String.to_integer(h)
        minute = String.to_integer(m)

        {display_hour, period} =
          cond do
            hour == 0 -> {12, "AM"}
            hour < 12 -> {hour, "AM"}
            hour == 12 -> {12, "PM"}
            true -> {hour - 12, "PM"}
          end

        minute_str = String.pad_leading("#{minute}", 2, "0")
        "#{display_hour}:#{minute_str} #{period}"

      _ ->
        time_str
    end
  end

  defp format_time_12h(_), do: "Time not specified"

  defp get_event_timezone(%{venue: %{latitude: lat, longitude: lng}})
       when not is_nil(lat) and not is_nil(lng) do
    # For now, all venues are in Poland (Kraków coordinates: ~50.06, ~19.95)
    # TODO: Implement proper coordinate-to-timezone lookup using a geo database
    # when we expand to other countries
    cond do
      # Poland (approximate bounding box)
      lat >= 49.0 and lat <= 55.0 and lng >= 14.0 and lng <= 24.5 ->
        "Europe/Warsaw"

      # Default fallback to Warsaw for European coordinates
      lat >= 35.0 and lat <= 71.0 and lng >= -10.0 and lng <= 40.0 ->
        "Europe/Warsaw"

      # Outside Europe - fallback to UTC
      true ->
        "Etc/UTC"
    end
  end

  defp get_event_timezone(_event) do
    # Default to Poland timezone since all current events are there
    "Europe/Warsaw"
  end

  defp parse_time(nil), do: {:ok, ~T[20:00:00]}

  defp parse_time(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [h, m] -> Time.new(String.to_integer(h), String.to_integer(m), 0)
      [h, m, s] -> Time.new(String.to_integer(h), String.to_integer(m), String.to_integer(s))
      _ -> {:ok, ~T[20:00:00]}
    end
  end

  defp parse_time(_), do: {:ok, ~T[20:00:00]}

  defp select_default_occurrence(%{occurrence_list: nil}), do: nil
  defp select_default_occurrence(%{occurrence_list: []}), do: nil

  defp select_default_occurrence(%{occurrence_list: occurrences}) do
    now = DateTime.utc_now()
    # Find the next upcoming occurrence, or the first if all are in the past
    Enum.find(occurrences, List.first(occurrences), fn occ ->
      DateTime.compare(occ.datetime, now) == :gt
    end)
  end

  # Check if event has an occurrence on the specified date
  defp has_occurrence_on_date?(%{occurrence_list: nil}, _date), do: false
  defp has_occurrence_on_date?(%{occurrence_list: []}, _date), do: false

  defp has_occurrence_on_date?(%{occurrence_list: occurrences}, date) do
    Enum.any?(occurrences, fn occ -> occ.date == date end)
  end

  defp event_is_past?(%{starts_at: nil}), do: false

  defp event_is_past?(%{ends_at: ends_at}) when not is_nil(ends_at) do
    DateTime.compare(ends_at, DateTime.utc_now()) == :lt
  end

  defp event_is_past?(%{starts_at: starts_at}) when not is_nil(starts_at) do
    # For events without end dates, consider them active for 24 hours after start
    # This handles single-day events and events where end time wasn't specified
    DateTime.compare(
      DateTime.add(starts_at, 24, :hour),
      DateTime.utc_now()
    ) == :lt
  end

  defp event_is_past?(_), do: false

  defp is_valid_email?(email) do
    email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/
  end

  # Category helper functions
  defp get_primary_category(event) do
    case event.primary_category_id do
      nil -> nil
      cat_id -> Enum.find(event.categories, &(&1.id == cat_id))
    end
  end

  defp get_secondary_categories(event) do
    case event.primary_category_id do
      nil ->
        # If no primary found, treat all but first as secondary
        case event.categories do
          [_first | rest] -> rest
          _ -> []
        end

      primary_id ->
        Enum.reject(event.categories, &(&1.id == primary_id))
    end
  end

  defp get_primary_category_id(event_id) do
    Repo.one(
      from(pec in "public_event_categories",
        where: pec.event_id == ^event_id and pec.is_primary == true,
        select: pec.category_id,
        limit: 1
      )
    )
  end

  defp safe_background_style(color) do
    color =
      if valid_hex_color?(color) do
        color
      else
        "#6B7280"
      end

    "background-color: #{color}"
  end

  defp valid_hex_color?(color) when is_binary(color) do
    case color do
      <<?#, _::binary>> = hex when byte_size(hex) in [4, 7] ->
        String.match?(hex, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/)

      _ ->
        false
    end
  end

  defp valid_hex_color?(_), do: false

  # Movie helper functions

  defp get_movie_data(event) do
    case event.movies do
      [movie | _] when not is_nil(movie) ->
        movie

      _ ->
        nil
    end
  end

  defp is_movie_screening?(event) do
    case event.movies do
      [] -> false
      nil -> false
      [movie | _] when not is_nil(movie) -> true
      _ -> false
    end
  end

  defp get_aggregated_movie_url(movie, city) do
    if movie && city do
      ~p"/c/#{city.slug}/movies/#{movie.slug}"
    else
      nil
    end
  end

  defp format_movie_runtime(nil), do: nil

  defp format_movie_runtime(runtime) when is_integer(runtime) do
    hours = div(runtime, 60)
    minutes = rem(runtime, 60)

    cond do
      hours > 0 && minutes > 0 -> "#{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h"
      minutes > 0 -> "#{minutes}m"
      true -> nil
    end
  end

  defp format_movie_runtime(_), do: nil

  # SEO helper functions - moved inline to use SEOHelpers module

  # Combine multiple JSON-LD schemas into a single script-ready string
  defp combine_json_ld_schemas([single_schema]) do
    # If only one schema, return it as-is
    single_schema
  end

  defp combine_json_ld_schemas(schemas) when is_list(schemas) do
    # Decode each JSON string, combine into array, re-encode
    schemas
    |> Enum.map(&Jason.decode!/1)
    |> Jason.encode!()
  end

  defp get_placeholder_image_url(event) do
    # Use a placeholder service with the event title
    name =
      (event.display_title || event.title || "Event")
      |> to_string()
      |> URI.encode()

    "https://placehold.co/1200x630/4ECDC4/FFFFFF?text=#{name}"
  end

  defp truncate_for_description(text, max_length \\ 155) do
    if String.length(text) <= max_length do
      text
    else
      text
      |> String.slice(0, max_length - 3)
      |> Kernel.<>("...")
    end
  end

  # URL slug helper functions for shareable day URLs
  defp date_to_url_slug(%Date{} = date) do
    # Format: "oct-10" using Calendar.strftime for library-based formatting
    month_abbr = Calendar.strftime(date, "%b") |> String.downcase()
    "#{month_abbr}-#{date.day}"
  end

  defp parse_date_slug(slug) when is_binary(slug) do
    # Try parsing formats in order:
    # 1. New format: "oct-10" (month-day only)
    # 2. Old short format: "fri-oct-10-25" (day-month-day-year)
    # 3. Old long format: "sunday-october-10-2025" (full names)
    with :error <- parse_month_day_slug(slug),
         :error <- parse_short_date_slug(slug) do
      parse_long_date_slug(slug)
    end
  end

  defp parse_date_slug(_), do: :error

  # Parse new format: "oct-10"
  # Handles year boundary intelligently: if date is in the past, try next year
  defp parse_month_day_slug(slug) do
    case Regex.run(~r/^(\w{3})-(\d+)$/, slug) do
      [_, month_abbr, day_str] ->
        with {day, ""} <- Integer.parse(day_str),
             month_num when is_integer(month_num) <- parse_month_abbr(month_abbr) do
          # Try current year first
          current_year = Date.utc_today().year
          today = Date.utc_today()

          case Date.new(current_year, month_num, day) do
            {:ok, date} ->
              # If date is more than 30 days in the past, try next year
              # This handles year boundaries gracefully (e.g., jan-15 accessed in December)
              if Date.diff(today, date) > 30 do
                case Date.new(current_year + 1, month_num, day) do
                  {:ok, next_year_date} -> {:ok, next_year_date}
                  _ -> {:ok, date}
                end
              else
                {:ok, date}
              end

            _ ->
              :error
          end
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Parse old short format: "fri-oct-10-25"
  defp parse_short_date_slug(slug) do
    case Regex.run(~r/^(\w{3})-(\w{3})-(\d+)-(\d{2})$/, slug) do
      [_, _day_abbr, month_abbr, day_str, year_str] ->
        with {day, ""} <- Integer.parse(day_str),
             {year_short, ""} <- Integer.parse(year_str),
             year <- if(year_short < 50, do: 2000 + year_short, else: 1900 + year_short),
             month_num <- parse_month_abbr(month_abbr),
             {:ok, date} <- Date.new(year, month_num, day) do
          {:ok, date}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Parse old long format: "sunday-october-5-2025"
  defp parse_long_date_slug(slug) do
    case Regex.run(~r/^(\w+)-(\w+)-(\d+)-(\d{4})$/, slug) do
      [_, _day_name, month_name, day_str, year_str] ->
        with {day, ""} <- Integer.parse(day_str),
             {year, ""} <- Integer.parse(year_str),
             month_num <- parse_full_month_name(month_name),
             {:ok, date} <- Date.new(year, month_num, day) do
          {:ok, date}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Map month abbreviations to numbers using standard library month names
  defp parse_month_abbr(month_abbr) do
    case String.downcase(month_abbr) do
      "jan" -> 1
      "feb" -> 2
      "mar" -> 3
      "apr" -> 4
      "may" -> 5
      "jun" -> 6
      "jul" -> 7
      "aug" -> 8
      "sep" -> 9
      "oct" -> 10
      "nov" -> 11
      "dec" -> 12
      _ -> nil
    end
  end

  # Map full month names to numbers (for backward compatibility with old URL format)
  defp parse_full_month_name(month_name) do
    case String.downcase(month_name) do
      "january" -> 1
      "february" -> 2
      "march" -> 3
      "april" -> 4
      "may" -> 5
      "june" -> 6
      "july" -> 7
      "august" -> 8
      "september" -> 9
      "october" -> 10
      "november" -> 11
      "december" -> 12
      _ -> nil
    end
  end
end
