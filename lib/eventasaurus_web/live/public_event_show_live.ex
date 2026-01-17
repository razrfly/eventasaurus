defmodule EventasaurusWeb.PublicEventShowLive do
  use EventasaurusWeb, :live_view
  require Logger

  on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler}

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.EventPlans

  alias EventasaurusWeb.Components.{
    PublicPlanWithFriendsModal,
    Breadcrumbs,
    MovieHeroCard,
    OpenGraphComponent,
    CategoryDisplay
  }

  alias EventasaurusWeb.Components.Activity.{
    ActivityLayout,
    ConcertHeroCard,
    GenericHeroCard,
    TriviaHeroCard,
    VenueLocationCard,
    PlanWithFriendsCard,
    SourceAttributionCard
  }

  alias EventasaurusWeb.Components.Events.OccurrenceDisplay
  alias EventasaurusWeb.Components.Events.EventScheduleDisplay
  alias EventasaurusWeb.Live.Components.CastCarouselComponent
  alias EventasaurusWeb.Helpers.BreadcrumbBuilder
  alias EventasaurusWeb.Helpers.LanguageDiscovery
  alias EventasaurusWeb.Helpers.PlanWithFriendsHelpers
  alias EventasaurusWeb.Helpers.SEOHelpers
  alias EventasaurusWeb.JsonLd.PublicEventSchema
  alias EventasaurusWeb.JsonLd.LocalBusinessSchema
  alias EventasaurusWeb.JsonLd.BreadcrumbListSchema
  alias EventasaurusWeb.UrlHelper
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.EventRefresh
  alias EventasaurusWeb.Cache.EventPageCache
  alias Eventasaurus.SocialCards.HashGenerator
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
      |> assign(:entry_context, :standard_event)
      |> assign(:is_single_occurrence, false)
      |> assign(:filter_preview_count, nil)
      |> assign(:date_availability, %{})
      |> assign(:time_period_availability, %{})

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
  def handle_info({:language_changed, _language}, socket) do
    # Re-fetch event with new language for localized content
    socket =
      socket
      |> fetch_event(socket.assigns.event.slug)
      |> clear_flash()

    {:noreply, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug, "date_slug" => date_slug}, url, socket) do
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

    # Check for open_modal query param (used by AuthProtectedAction hook for cache-bust reload)
    socket = maybe_auto_open_modal(socket, url)

    {:noreply, socket}
  end

  def handle_params(%{"slug" => slug}, url, socket) do
    # Handle base URL without date: /activities/slug
    socket =
      socket
      |> fetch_event(slug)
      |> assign(:loading, false)

    # Check for open_modal query param (used by AuthProtectedAction hook for cache-bust reload)
    # When authenticated user clicks "Plan with Friends" on a cached page, the hook reloads
    # with ?open_modal=open_plan_modal to auto-open the modal once session is restored
    socket = maybe_auto_open_modal(socket, url)

    {:noreply, socket}
  end

  # Auto-open modal based on query param (used for cache-bust reload flow)
  defp maybe_auto_open_modal(socket, url) when is_binary(url) do
    uri = URI.parse(url)

    case uri.query do
      nil ->
        socket

      query ->
        params = URI.decode_query(query)

        case Map.get(params, "open_modal") do
          "open_plan_modal" ->
            # User is authenticated and wants to open Plan with Friends modal
            if socket.assigns[:auth_user] do
              Logger.info("[PublicEventShowLive] Auto-opening Plan with Friends modal via URL param")
              assign(socket, :show_plan_with_friends_modal, true)
            else
              socket
            end

          _ ->
            socket
        end
    end
  end

  defp maybe_auto_open_modal(socket, _url), do: socket

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
        # Subscribe to PubSub for real-time availability updates (only once per LiveView)
        # Guard against duplicate subscriptions when language changes trigger re-fetch
        unless socket.assigns[:pubsub_subscribed] do
          Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "event:#{enriched_event.id}")
        end

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
        is_music = is_music_event?(enriched_event)
        is_trivia = is_trivia_event?(enriched_event)
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
        # For movie screenings with multiple showtimes, generate multiple ScreeningEvents
        event_json_ld =
          if is_movie && enriched_event.occurrence_list &&
               length(enriched_event.occurrence_list) > 0 do
            PublicEventSchema.generate_with_occurrences(
              enriched_event,
              enriched_event.occurrence_list
            )
          else
            PublicEventSchema.generate(enriched_event)
          end

        breadcrumb_json_ld =
          BreadcrumbListSchema.from_breadcrumb_builder_items(
            breadcrumb_items,
            canonical_url_for_schemas,
            base_url
          )

        # Skip LocalBusinessSchema for movie screenings - ScreeningEvent already includes
        # MovieTheater location in the event schema, so separate venue schema is redundant
        venue_json_ld =
          if enriched_event.venue && !is_movie do
            LocalBusinessSchema.generate(enriched_event.venue)
          else
            nil
          end

        json_ld_schemas =
          [event_json_ld, breadcrumb_json_ld, venue_json_ld]
          |> Enum.reject(&is_nil/1)

        combined_json_ld = combine_json_ld_schemas(json_ld_schemas)

        # Generate branded social card URL for OG image
        image_url = generate_activity_social_card_url(enriched_event, request_uri)

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

        # Generate Open Graph meta tags
        og_tags =
          build_event_open_graph(
            enriched_event,
            description,
            image_url,
            canonical_url_for_schemas
          )

        socket
        |> assign(:event, enriched_event)
        |> assign(:selected_occurrence, select_default_occurrence(enriched_event))
        |> assign(:existing_plan, existing_plan)
        # Will be populated asynchronously via handle_info
        |> assign(:nearby_events, nearby_events)
        |> assign(:movie, movie)
        |> assign(:is_movie_screening, is_movie)
        |> assign(:is_music_event, is_music)
        |> assign(:is_trivia_event, is_trivia)
        |> assign(:aggregated_movie_url, aggregated_url)
        |> assign(:breadcrumb_items, breadcrumb_items)
        |> assign(:available_languages, available_languages)
        |> assign(:open_graph, og_tags)
        # Track that we've subscribed to PubSub to avoid duplicate subscriptions
        |> assign(:pubsub_subscribed, true)
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

        # Phase 2: Context Detection System
        # Detect if single occurrence (only one showtime/date)
        occurrence_count = PublicEvent.occurrence_count(event)
        is_single_occurrence = occurrence_count == 1

        # Detect entry context based on event type and user selection
        selected_occurrence = socket.assigns.selected_occurrence

        entry_context =
          cond do
            is_single_occurrence ->
              :single_occurrence

            is_movie && !is_nil(selected_occurrence) ->
              :specific_showtime

            is_movie ->
              :generic_movie

            true ->
              :standard_event
          end

        # Fetch date availability counts based on event type
        date_availability = fetch_date_availability(event, is_movie, is_venue)

        # Fetch time period availability for data-driven time filter
        time_period_availability = fetch_time_period_availability(event, is_movie)

        # Phase 3: Adaptive Modal Behavior
        # - Single-occurrence events → Skip directly to Quick Plan
        # - Multi-showtime events → Show mode selection
        initial_planning_mode =
          if is_single_occurrence do
            :quick
          else
            :selection
          end

        # Get city from venue for venue scope indicator
        # Venue has city_id but city association may not be preloaded, so load it
        city =
          if event.venue && event.venue.city_id do
            EventasaurusApp.Repo.get(EventasaurusDiscovery.Locations.City, event.venue.city_id)
          else
            nil
          end

        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, true)
         |> assign(:modal_organizer, user)
         |> assign(:is_movie_event, is_movie)
         |> assign(:is_venue_event, is_venue)
         |> assign(:entry_context, entry_context)
         |> assign(:is_single_occurrence, is_single_occurrence)
         |> assign(:planning_mode, initial_planning_mode)
         |> assign(:date_availability, date_availability)
         |> assign(:time_period_availability, time_period_availability)
         # Store original unfiltered counts for restoration when filters are cleared
         |> assign(:original_date_availability, date_availability)
         |> assign(:original_time_period_availability, time_period_availability)
         # Venue scope toggle (default to single venue when accessed from specific event page)
         |> assign(:include_all_venues, false)
         # City for venue scope indicator
         |> assign(:city, city)}
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
     |> assign(:matching_occurrences, [])
     # Reset venue scope
     |> assign(:include_all_venues, false)}
  end

  @impl true
  def handle_event("toggle_venue_scope", params, socket) do
    # Toggle between single venue and all venues mode
    # Supports both button-based (scope param) and checkbox-based toggling
    # See: https://github.com/razrfly/eventasaurus/issues/3258
    new_include_all =
      case params do
        %{"scope" => "all"} -> true
        %{"scope" => "single"} -> false
        _ -> !socket.assigns[:include_all_venues]
      end

    # Recalculate availability counts based on new venue scope
    event = socket.assigns.event
    movie = socket.assigns[:movie]
    is_movie = socket.assigns[:is_movie_event]
    city = socket.assigns[:city]

    {new_date_availability, new_time_availability} =
      if new_include_all && movie do
        # Use movie-level queries (all venues IN THIS CITY)
        # Pass city to constrain results to current city only
        date_avail = fetch_movie_date_availability(movie, city)
        time_avail = fetch_movie_time_period_availability(movie, city)
        {date_avail, time_avail}
      else
        # Use event-level queries (specific venue)
        date_avail = fetch_date_availability(event, is_movie, socket.assigns[:is_venue_event])
        time_avail = fetch_time_period_availability(event, is_movie)
        {date_avail, time_avail}
      end

    # Reset filter criteria when changing venue scope to avoid stale selections
    {:noreply,
     socket
     |> assign(:include_all_venues, new_include_all)
     |> assign(:date_availability, new_date_availability)
     |> assign(:time_period_availability, new_time_availability)
     |> assign(:original_date_availability, new_date_availability)
     |> assign(:original_time_period_availability, new_time_availability)
     |> assign(:filter_criteria, %{})
     |> assign(:filter_preview_count, nil)}
  end

  @impl true
  # Threshold for skipping filter UI - if <= this many showtimes, show them all directly
  @small_showtime_threshold 15

  def handle_event("select_planning_mode", %{"mode" => "flexible"}, socket) do
    # Check total showtimes for next 7 days (no time preference filter)
    # This handles both movie events and regular events
    movie = socket.assigns[:movie]
    # Note: In this LiveView, the event is stored under :event, not :public_event
    event = socket.assigns[:event]

    cond do
      # Movie event - check showtimes
      movie != nil ->
        today = Date.utc_today()

        default_criteria = %{
          date_from: Date.to_iso8601(today),
          date_to: Date.to_iso8601(Date.add(today, 7)),
          time_preferences: [],
          limit: 50
        }

        city = socket.assigns[:city]
        all_showtimes = query_movie_occurrences(movie.id, default_criteria, city)
        total_count = length(all_showtimes)

        cond do
          # Single occurrence - skip filters and polls, offer Quick Plan with pre-selected showtime
          # See: https://github.com/razrfly/eventasaurus/issues/3258
          total_count == 1 ->
            [single_occurrence] = all_showtimes

            {:noreply,
             socket
             |> assign(:planning_mode, :quick)
             |> assign(:selected_occurrence, single_occurrence)
             |> assign(:matching_occurrences, all_showtimes)
             |> assign(:filter_criteria, default_criteria)
             |> assign(:filter_preview_count, 1)}

          # Small number of showtimes - skip filters, show them all directly
          total_count <= @small_showtime_threshold and total_count > 0 ->
            {:noreply,
             socket
             |> assign(:planning_mode, :flexible_review)
             |> assign(:matching_occurrences, all_showtimes)
             |> assign(:filter_criteria, default_criteria)
             |> assign(:filter_preview_count, total_count)}

          true ->
            # Many showtimes - show filter UI
            {:noreply,
             socket
             |> assign(:planning_mode, :flexible_filters)
             |> assign(:filter_preview_count, nil)}
        end

      # Event with JSONB occurrences - check occurrences count
      event != nil && Map.has_key?(event, :occurrences) ->
        occurrences = event.occurrences || %{}
        dates = Map.get(occurrences, "dates", [])
        total_count = length(dates)

        today = Date.utc_today()

        default_criteria = %{
          date_from: Date.to_iso8601(today),
          date_to: Date.to_iso8601(Date.add(today, 7)),
          time_preferences: [],
          limit: 50
        }

        cond do
          # Single occurrence - skip filters and polls, offer Quick Plan
          # See: https://github.com/razrfly/eventasaurus/issues/3258
          # Guard against parsing failures - if parsing yields 0 or >1 results, fall back
          total_count == 1 ->
            matching = build_occurrences_from_jsonb(event, dates)

            case matching do
              [single_occurrence] ->
                {:noreply,
                 socket
                 |> assign(:planning_mode, :quick)
                 |> assign(:selected_occurrence, single_occurrence)
                 |> assign(:matching_occurrences, matching)
                 |> assign(:filter_criteria, default_criteria)
                 |> assign(:filter_preview_count, 1)}

              # Parsing failed or returned unexpected count - fall back to filters
              _ ->
                {:noreply,
                 socket
                 |> assign(:planning_mode, :flexible_filters)
                 |> assign(:filter_preview_count, nil)}
            end

          # Small number of showtimes - skip filters, show them all directly
          total_count <= @small_showtime_threshold and total_count > 0 ->
            matching = build_occurrences_from_jsonb(event, dates)

            {:noreply,
             socket
             |> assign(:planning_mode, :flexible_review)
             |> assign(:matching_occurrences, matching)
             |> assign(:filter_criteria, default_criteria)
             |> assign(:filter_preview_count, total_count)}

          true ->
            {:noreply,
             socket
             |> assign(:planning_mode, :flexible_filters)
             |> assign(:filter_preview_count, nil)}
        end

      # Fallback - show filter UI
      true ->
        {:noreply,
         socket
         |> assign(:planning_mode, :flexible_filters)
         |> assign(:filter_preview_count, nil)}
    end
  end

  def handle_event("select_planning_mode", %{"mode" => mode}, socket) do
    planning_mode =
      case mode do
        "quick" -> :quick
        "selection" -> :selection
        "flexible_filters" -> :flexible_filters
        _ -> :selection
      end

    {:noreply,
     socket
     |> assign(:planning_mode, planning_mode)
     |> assign(:filter_preview_count, nil)}
  end

  @impl true
  def handle_event("preview_filter_results", params, socket) do
    # Parse selected dates and convert to date range (same as apply_flexible_filters)
    selected_dates = Map.get(params, "selected_dates", [])

    {date_from, date_to} =
      if length(selected_dates) > 0 do
        dates =
          selected_dates
          |> Enum.map(&Date.from_iso8601/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, d} -> d end)
          |> Enum.sort(Date)

        if dates == [] do
          {Date.utc_today(), Date.utc_today() |> Date.add(7)}
        else
          {List.first(dates), List.last(dates)}
        end
      else
        # Default to next 7 days if no dates selected
        {Date.utc_today(), Date.utc_today() |> Date.add(7)}
      end

    # Parse filter criteria from form
    # Handle empty limit string to prevent String.to_integer("") crash
    limit =
      case params["limit"] do
        nil -> 10
        "" -> 10
        value -> String.to_integer(value)
      end

    time_preferences = Map.get(params, "time_preferences", [])

    filter_criteria = %{
      selected_dates: selected_dates,
      date_from: Date.to_iso8601(date_from),
      date_to: Date.to_iso8601(date_to),
      time_preferences: time_preferences,
      meal_periods: Map.get(params, "meal_periods", []),
      limit: limit
    }

    # Query for matching occurrences count only (not full data)
    event = socket.assigns.event
    movie = get_movie_data(event)
    venue = get_venue_data(event)
    city = socket.assigns[:city]
    is_venue = venue != nil && !movie
    include_all_venues = socket.assigns[:include_all_venues] || false

    # Remove limit for count query - we want total matching, not capped results
    # The limit only applies to how many poll options are created, not the preview count
    count_criteria = Map.delete(filter_criteria, :limit)

    count =
      cond do
        # All venues mode - use movie-level query (constrained to current city)
        include_all_venues && movie != nil ->
          query_movie_occurrences(movie.id, count_criteria, city) |> length()

        # For events with occurrence data, use event.id to constrain to this venue
        has_occurrence_data?(event) ->
          query_event_occurrences(event.id, count_criteria) |> length()

        venue && !movie ->
          query_venue_occurrences(venue.id, count_criteria) |> length()

        true ->
          0
      end

    # === DYNAMIC COUNTS: Recalculate availability counts based on current filters ===
    # When user selects dates, update time period counts for just those dates
    # When user selects time preferences, update date counts for just those periods
    # Use original_* assigns to restore unfiltered counts when filters are cleared

    {updated_date_availability, updated_time_period_availability} =
      if has_occurrence_data?(event) || (include_all_venues && movie != nil) do
        # Get original unfiltered counts (stored when modal opened)
        original_date_availability =
          Map.get(socket.assigns, :original_date_availability, socket.assigns.date_availability)

        original_time_period_availability =
          Map.get(
            socket.assigns,
            :original_time_period_availability,
            socket.assigns.time_period_availability
          )

        # Build filter criteria for dynamic counts
        # Include city_ids when in movie mode on city page to maintain city-scoped filtering
        # See: https://github.com/razrfly/eventasaurus/issues/3252
        city_ids =
          if include_all_venues && movie != nil do
            case socket.assigns[:city] do
              %{id: city_id} when not is_nil(city_id) -> [city_id]
              _ -> []
            end
          else
            []
          end

        date_filter_criteria = %{time_preferences: time_preferences, city_ids: city_ids}
        time_filter_criteria = %{selected_dates: selected_dates, city_ids: city_ids}
        date_list = generate_date_list(is_venue)

        # Determine series type and ID based on venue scope
        {series_type, series_id} =
          if include_all_venues && movie != nil do
            {"movie", movie.id}
          else
            {"event", event.id}
          end

        # Recalculate date availability (filtered by time preferences if any selected)
        new_date_availability =
          if time_preferences != [] do
            case EventasaurusApp.Planning.OccurrenceQuery.get_date_availability_counts(
                   series_type,
                   series_id,
                   date_list,
                   date_filter_criteria
                 ) do
              {:ok, counts} -> counts
              {:error, _} -> original_date_availability
            end
          else
            # No time preferences selected, restore original unfiltered counts
            original_date_availability
          end

        # Recalculate time period availability (filtered by selected dates if any)
        new_time_period_availability =
          if selected_dates != [] do
            case EventasaurusApp.Planning.OccurrenceQuery.get_time_period_availability_counts(
                   series_type,
                   series_id,
                   time_filter_criteria
                 ) do
              {:ok, counts} -> counts
              {:error, _} -> original_time_period_availability
            end
          else
            # No dates selected, restore original unfiltered counts
            original_time_period_availability
          end

        {new_date_availability, new_time_period_availability}
      else
        # Non-occurrence event, keep existing counts
        {socket.assigns.date_availability, socket.assigns.time_period_availability}
      end

    {:noreply,
     socket
     |> assign(:filter_criteria, filter_criteria)
     |> assign(:filter_preview_count, count)
     |> assign(:date_availability, updated_date_availability)
     |> assign(:time_period_availability, updated_time_period_availability)}
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
    # Handle empty limit string to prevent String.to_integer("") crash
    limit =
      case params["limit"] do
        nil -> 10
        "" -> 10
        value -> String.to_integer(value)
      end

    filter_criteria = %{
      selected_dates: selected_dates,
      date_from: Date.to_iso8601(date_from),
      date_to: Date.to_iso8601(date_to),
      time_preferences: Map.get(params, "time_preferences", []),
      meal_periods: Map.get(params, "meal_periods", []),
      limit: limit
    }

    # Query for matching occurrences
    # When include_all_venues is true, use movie.id to get showtimes from ALL venues
    # Otherwise, use event.id to constrain to THIS specific venue (fixes issue #3245)
    event = socket.assigns.event
    venue = get_venue_data(event)
    movie = get_movie_data(event)
    city = socket.assigns[:city]
    include_all_venues = socket.assigns[:include_all_venues] || false

    matching_occurrences =
      cond do
        # All venues mode - use movie-level query (constrained to current city)
        include_all_venues && movie != nil ->
          query_movie_occurrences(movie.id, filter_criteria, city)

        # For events with occurrence data (movies, trivia, etc.), use event.id
        # This constrains results to this specific venue's showtimes
        has_occurrence_data?(event) ->
          query_event_occurrences(event.id, filter_criteria)

        # For venue-based planning (restaurants, etc.)
        venue ->
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

  # Build occurrence maps from JSONB dates for direct display
  defp build_occurrences_from_jsonb(event, dates) do
    venue = event.venue

    Enum.map(dates, fn date_entry ->
      date_str = date_entry["date"]
      time_str = date_entry["time"]

      datetime =
        with {:ok, date} <- Date.from_iso8601(date_str),
             {:ok, time} <- parse_time_string(time_str) do
          DateTime.new!(date, time, "Etc/UTC")
        else
          _ -> nil
        end

      %{
        public_event_id: event.id,
        datetime: datetime,
        date: date_str,
        time: time_str,
        title: event.title,
        venue_id: if(venue, do: venue.id),
        venue_name: if(venue, do: venue.name),
        venue_city_id: if(venue, do: venue.city_id)
      }
    end)
    |> Enum.filter(fn occ -> occ.datetime != nil end)
    |> Enum.sort_by(fn occ -> occ.datetime end, DateTime)
  end

  # Parse time string, handling both HH:MM and HH:MM:SS formats
  defp parse_time_string(time_str) when is_binary(time_str) do
    # If already has seconds (HH:MM:SS), use as-is; otherwise append :00
    normalized =
      case String.split(time_str, ":") do
        [_h, _m, _s] -> time_str
        [_h, _m] -> time_str <> ":00"
        _ -> time_str
      end

    Time.from_iso8601(normalized)
  end

  defp parse_time_string(_), do: {:error, :invalid_time}

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

  # Handle flexible planning submission - delegates to shared helper
  defp handle_flexible_plan_submit(socket) do
    user = get_authenticated_user(socket)
    event = socket.assigns.event
    movie = get_movie_data(event)

    # Ensure we have movie data (flexible planning is movie-specific)
    if is_nil(movie) do
      {:noreply,
       socket
       |> assign(:show_plan_with_friends_modal, false)
       |> put_flash(
         :error,
         gettext(
           "This event is not a movie screening. Flexible planning is only available for movies."
         )
       )}
    else
      PlanWithFriendsHelpers.execute_flexible_plan(socket, movie, user)
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

  defp query_movie_occurrences(movie_id, filter_criteria, city) do
    alias EventasaurusApp.Planning.OccurrenceQuery

    # Convert filter criteria to format expected by OccurrenceQuery
    # Include city_ids to constrain results to current city only
    # See: https://github.com/razrfly/eventasaurus/issues/3252
    city_ids = if city && city.id, do: [city.id], else: []

    # Build base criteria - only include limit if explicitly provided
    # This allows count queries to get full results (no limit) vs display queries (with limit)
    base_criteria = %{
      date_range: PlanWithFriendsHelpers.parse_date_range(filter_criteria),
      time_preferences: Map.get(filter_criteria, :time_preferences, []),
      city_ids: city_ids
    }

    query_criteria =
      case Map.get(filter_criteria, :limit) do
        nil -> base_criteria
        limit -> Map.put(base_criteria, :limit, limit)
      end

    case OccurrenceQuery.find_movie_occurrences(movie_id, query_criteria) do
      {:ok, occurrences} -> occurrences
      {:error, _reason} -> []
    end
  end

  # Query occurrences for a specific event (constrains to this venue's showtimes only)
  # This is used when on a specific event page to avoid showing showtimes from other venues
  defp query_event_occurrences(event_id, filter_criteria) do
    alias EventasaurusApp.Planning.OccurrenceQuery

    # Build base criteria - only include limit if explicitly provided
    # This allows count queries to get full results (no limit) vs display queries (with limit)
    base_criteria = %{
      date_range: PlanWithFriendsHelpers.parse_date_range(filter_criteria),
      time_preferences: Map.get(filter_criteria, :time_preferences, [])
    }

    query_criteria =
      case Map.get(filter_criteria, :limit) do
        nil -> base_criteria
        limit -> Map.put(base_criteria, :limit, limit)
      end

    case OccurrenceQuery.find_occurrences("event", event_id, query_criteria) do
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

    # Build base criteria - only include limit if explicitly provided
    # This allows count queries to get full results (no limit) vs display queries (with limit)
    base_criteria = %{
      date_range: PlanWithFriendsHelpers.parse_date_range(filter_criteria),
      meal_periods: Map.get(filter_criteria, :meal_periods, [])
    }

    query_criteria =
      case Map.get(filter_criteria, :limit) do
        nil -> base_criteria
        limit -> Map.put(base_criteria, :limit, limit)
      end

    case OccurrenceQuery.find_venue_occurrences(venue_id, query_criteria) do
      {:ok, occurrences} -> occurrences
      {:error, _reason} -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <%= if @loading do %>
        <div class="flex justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <%= if @event do %>
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <!-- Breadcrumb + Language Switcher Row -->
            <div class="flex items-center justify-between mb-6">
              <Breadcrumbs.breadcrumb items={@breadcrumb_items} />
              <!-- Language Switcher -->
              <.language_switcher
                available_languages={@available_languages}
                current_language={@language}
                class="flex-shrink-0 ml-4"
              />
            </div>

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

            <!-- Two-Column Layout -->
            <ActivityLayout.activity_layout>
              <:main>
                <!-- Hero Section - Type-specific hero cards -->
                <%= cond do %>
                  <% @is_movie_screening && @movie -> %>
                    <!-- Movie Hero Card -->
                    <MovieHeroCard.movie_hero_card
                      movie={@movie}
                      show_see_all_link={true}
                      aggregated_movie_url={@aggregated_movie_url}
                    />

                    <!-- Cast Carousel for Movie Screenings -->
                    <%= if cast = get_in(@movie.metadata, ["credits", "cast"]) do %>
                      <.live_component
                        module={CastCarouselComponent}
                        id="movie-cast-carousel"
                        cast={cast}
                        variant={:embedded}
                        title={gettext("Cast")}
                        max_cast={15}
                      />
                    <% end %>

                  <% @is_music_event -> %>
                    <!-- Concert Hero Card for music events -->
                    <ConcertHeroCard.concert_hero_card
                      event={@event}
                      performers={@event.performers || []}
                      cover_image_url={Map.get(@event, :cover_image_url)}
                      ticket_url={get_primary_source_ticket_url(@event)}
                    />

                  <% @is_trivia_event -> %>
                    <!-- Trivia Hero Card for quiz/trivia events -->
                    <TriviaHeroCard.trivia_hero_card
                      event={@event}
                      cover_image_url={Map.get(@event, :cover_image_url)}
                      ticket_url={get_primary_source_ticket_url(@event)}
                    />

                  <% true -> %>
                    <!-- Generic Hero Card for all other events -->
                    <GenericHeroCard.generic_hero_card
                      event={@event}
                      cover_image_url={Map.get(@event, :cover_image_url)}
                      ticket_url={get_primary_source_ticket_url(@event)}
                    />
                <% end %>

                <!-- Category Tags Section -->
                <CategoryDisplay.event_category_section event={@event} class="mt-4" />

                <!-- Event Content Card -->
                <div class="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
                  <div class="p-6">
                    <!-- Event Schedule -->
                    <div class="mb-6">
                      <EventScheduleDisplay.event_schedule_display
                        event={@event}
                        occurrence_list={@event.occurrence_list || []}
                        selected_occurrence={@selected_occurrence}
                        is_movie_screening={@is_movie_screening}
                      />
                    </div>

                    <!-- Ticket Link (only for movie screenings - non-movie events have it in hero) -->
                    <%= if @is_movie_screening do %>
                      <%= if ticket_url = get_primary_source_ticket_url(@event) do %>
                        <div class="mb-6">
                          <a
                            href={ticket_url}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="inline-flex items-center px-6 py-3 bg-indigo-600 text-white font-medium rounded-lg hover:bg-indigo-700 transition"
                          >
                            <Heroicons.ticket class="w-5 h-5 mr-2" />
                            <%= gettext("Get Tickets") %>
                          </a>
                        </div>
                      <% end %>
                    <% end %>

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
                      <div class="mb-6">
                        <h2 class="text-xl font-semibold text-gray-900 mb-3">
                          <%= gettext("About This Event") %>
                        </h2>
                        <div class="prose max-w-none text-gray-700">
                          <%= format_description(@event.display_description) %>
                        </div>
                      </div>
                    <% end %>

                    <!-- Performers -->
                    <%= if @event.performers && @event.performers != [] do %>
                      <div class="mb-6">
                        <h2 class="text-xl font-semibold text-gray-900 mb-3">
                          <%= gettext("Performers") %>
                        </h2>
                        <div class="flex flex-wrap gap-2">
                          <%= for performer <- @event.performers do %>
                            <a
                              href={~p"/performers/#{performer.slug}"}
                              class="px-3 py-1.5 bg-gray-100 rounded-lg text-gray-800 text-sm font-medium hover:bg-indigo-100 hover:text-indigo-800 transition-colors"
                            >
                              <%= performer.name %>
                            </a>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </:main>

              <:sidebar>
                <!-- Venue Location Card with Map -->
                <%= if @event.venue do %>
                  <VenueLocationCard.venue_location_card
                    venue={@event.venue}
                    map_id="event-venue-map"
                  />
                <% end %>

                <!-- Plan with Friends Card -->
                <PlanWithFriendsCard.plan_with_friends_card
                  existing_plan={@existing_plan}
                  is_past_event={event_is_past?(@event)}
                />

                <!-- Source Attribution Card -->
                <SourceAttributionCard.source_attribution_card
                  sources={@event.sources}
                  is_refreshable={EventRefresh.refreshable?(@event)}
                  refreshing={@refreshing_availability}
                />
              </:sidebar>
            </ActivityLayout.activity_layout>

            <!-- Related Events (Full Width Below Layout) -->
            <div class="mt-8">
              <.live_component
                module={EventasaurusWeb.Components.NearbyEventsComponent}
                id="nearby-events"
                events={@nearby_events}
                language={@language}
              />
            </div>
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
          filter_preview_count={@filter_preview_count}
          is_movie_event={@is_movie_event}
          is_venue_event={@is_venue_event}
          entry_context={@entry_context}
          is_single_occurrence={@is_single_occurrence}
          date_availability={@date_availability}
          time_period_availability={@time_period_availability}
          include_all_venues={@include_all_venues}
          movie={@movie}
          city={@city}
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

  defp format_description(nil), do: Phoenix.HTML.raw("")

  defp format_description(description) do
    # Escapes HTML and converts newlines to <br>, returning Safe HTML
    Phoenix.HTML.Format.text_to_html(description, escape: true)
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

  # Category helper functions (get_primary_category and get_secondary_categories
  # moved to EventasaurusWeb.Components.CategoryDisplay.event_category_section/1)

  defp get_primary_category_id(event_id) do
    Repo.one(
      from(pec in "public_event_categories",
        where: pec.event_id == ^event_id and pec.is_primary == true,
        select: pec.category_id,
        limit: 1
      )
    )
  end

  # safe_background_style and valid_hex_color? moved to
  # EventasaurusWeb.Components.CategoryDisplay

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

  defp is_music_event?(event) do
    # Check if any category has MusicEvent schema type
    case event.categories do
      categories when is_list(categories) and length(categories) > 0 ->
        Enum.any?(categories, fn category ->
          Map.get(category, :schema_type) == "MusicEvent"
        end)

      _ ->
        false
    end
  end

  defp is_trivia_event?(event) do
    # Check if any category is trivia/quiz (slug-based since it's a SocialEvent subtype)
    case event.categories do
      categories when is_list(categories) and length(categories) > 0 ->
        Enum.any?(categories, fn category ->
          slug = Map.get(category, :slug, "")

          slug == "trivia" || slug == "quiz" || String.contains?(slug, "trivia") ||
            String.contains?(slug, "quiz")
        end)

      _ ->
        false
    end
  end

  defp get_aggregated_movie_url(movie, city) do
    if movie && city do
      ~p"/c/#{city.slug}/movies/#{movie.slug}"
    else
      nil
    end
  end

  # SEO helper functions - moved inline to use SEOHelpers module

  # Combine multiple JSON-LD schemas into a single script-ready string
  defp combine_json_ld_schemas([single_schema]) do
    # If only one schema, return it as-is
    single_schema
  end

  defp combine_json_ld_schemas(schemas) when is_list(schemas) do
    # Decode each JSON string, flatten any nested arrays, combine into @graph format
    # This handles the case where generate_with_occurrences returns an array of ScreeningEvents
    decoded_schemas =
      schemas
      |> Enum.map(&Jason.decode!/1)
      |> Enum.flat_map(fn
        # Flatten arrays (multiple ScreeningEvents)
        list when is_list(list) -> list
        # Wrap single items in a list
        item -> [item]
      end)
      # Remove @context from individual items since we'll have one at the top level
      |> Enum.map(&Map.delete(&1, "@context"))

    # Use @graph format for multiple schemas (valid JSON-LD structure)
    %{"@context" => "https://schema.org", "@graph" => decoded_schemas}
    |> Jason.encode!()
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

  # Helper to fetch date availability counts for a movie across ALL venues
  # Used when "include all venues" toggle is enabled
  defp fetch_movie_date_availability(movie, city) when not is_nil(movie) do
    date_list = generate_date_list(false)

    # Build filter criteria with city_ids if city is provided
    # This constrains "all venues" to only venues within the current city
    filter_criteria =
      if city && city.id do
        %{city_ids: [city.id]}
      else
        %{}
      end

    case EventasaurusApp.Planning.OccurrenceQuery.get_date_availability_counts(
           "movie",
           movie.id,
           date_list,
           filter_criteria
         ) do
      {:ok, counts} -> counts
      {:error, _} -> %{}
    end
  end

  defp fetch_movie_date_availability(_, _), do: %{}

  # Helper to fetch time period availability counts for a movie across venues in a city
  # Used when "include all venues" toggle is enabled
  # When city is provided, constrains results to venues within that city
  defp fetch_movie_time_period_availability(movie, city) when not is_nil(movie) do
    # Build filter criteria with city_ids if city is provided
    # This constrains "all venues" to only venues within the current city
    filter_criteria =
      if city && city.id do
        %{city_ids: [city.id]}
      else
        %{}
      end

    case EventasaurusApp.Planning.OccurrenceQuery.get_time_period_availability_counts(
           "movie",
           movie.id,
           filter_criteria
         ) do
      {:ok, counts} -> counts
      {:error, _} -> %{}
    end
  end

  defp fetch_movie_time_period_availability(_, _), do: %{}

  # Helper to fetch date availability counts based on event type
  # Always uses "event" with event.id to get counts for THIS specific event/venue,
  # not aggregated across all venues showing the same movie (fixes issue #3245)
  defp fetch_date_availability(event, _is_movie, is_venue) do
    date_list = generate_date_list(is_venue)

    cond do
      # For events with occurrence data (movies, trivia, etc.), use event.id
      # This constrains counts to this specific venue's showtimes
      has_occurrence_data?(event) ->
        case EventasaurusApp.Planning.OccurrenceQuery.get_date_availability_counts(
               "event",
               event.id,
               date_list,
               %{}
             ) do
          {:ok, counts} -> counts
          {:error, _} -> %{}
        end

      # For venue-only events (no occurrence data), use venue meal periods
      is_venue ->
        venue = event.venue

        if venue do
          case EventasaurusApp.Planning.OccurrenceQuery.get_date_availability_counts(
                 "venue",
                 venue.id,
                 date_list,
                 %{}
               ) do
            {:ok, counts} -> counts
            {:error, _} -> %{}
          end
        else
          %{}
        end

      true ->
        %{}
    end
  end

  # Check if event has actual occurrence data (dates array or pattern)
  defp has_occurrence_data?(%{occurrences: %{"dates" => dates}}) when is_list(dates), do: true
  defp has_occurrence_data?(%{occurrences: %{"type" => "pattern"}}), do: true
  defp has_occurrence_data?(_), do: false

  # Helper to fetch time period availability counts based on event type
  # Always uses "event" with event.id to get counts for THIS specific event/venue,
  # not aggregated across all venues showing the same movie (fixes issue #3245)
  defp fetch_time_period_availability(event, _is_movie) do
    if has_occurrence_data?(event) do
      case EventasaurusApp.Planning.OccurrenceQuery.get_time_period_availability_counts(
             "event",
             event.id,
             %{}
           ) do
        {:ok, counts} -> counts
        {:error, _} -> %{}
      end
    else
      %{}
    end
  end

  # Helper to generate date list matching modal's generate_date_options logic
  defp generate_date_list(is_venue_event) do
    days = if is_venue_event, do: 14, else: 7
    today = Date.utc_today()

    Enum.map(0..(days - 1), fn offset ->
      Date.add(today, offset)
    end)
  end

  # Generate branded social card URL for activity pages
  # Uses the HashGenerator to create cache-busting URLs that trigger PNG generation
  defp generate_activity_social_card_url(event, request_uri) do
    social_card_path = HashGenerator.generate_url_path(event, :activity)
    UrlHelper.build_url(social_card_path, request_uri)
  end

  # Build Open Graph meta tags for event pages
  defp build_event_open_graph(event, description, image_url, canonical_url) do
    # Social card URLs are already absolute, don't wrap with CDN
    # (social cards are generated server-side and include branding)
    final_image_url = image_url

    # Determine Open Graph type
    og_type = if is_movie_screening?(event), do: "video.movie", else: "event"

    # Generate Open Graph tags
    Phoenix.HTML.Safe.to_iodata(
      OpenGraphComponent.open_graph_tags(%{
        type: og_type,
        title: event.display_title,
        description: description,
        image_url: final_image_url,
        image_width: 1200,
        image_height: 630,
        url: canonical_url,
        site_name: "Wombie",
        locale: "en_US",
        twitter_card: "summary_large_image"
      })
    )
    |> IO.iodata_to_binary()
  end
end
