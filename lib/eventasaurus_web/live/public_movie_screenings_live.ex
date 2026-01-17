defmodule EventasaurusWeb.PublicMovieScreeningsLive do
  use EventasaurusWeb, :live_view

  on_mount {EventasaurusWeb.Live.LanguageHooks, :attach_language_handler}

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusWeb.Components.{Breadcrumbs, PublicPlanWithFriendsModal}
  alias EventasaurusWeb.Live.Components.MovieHeroComponent
  alias EventasaurusWeb.Live.Components.CastCarouselComponent
  alias EventasaurusWeb.Live.Components.CityScreeningsSection
  alias EventasaurusWeb.Helpers.{BreadcrumbBuilder, LanguageDiscovery, PlanWithFriendsHelpers}
  alias EventasaurusWeb.Services.TmdbService
  alias EventasaurusWeb.JsonLd.MovieSchema
  alias Eventasaurus.SocialCards.HashGenerator
  alias EventasaurusWeb.UrlHelper
  alias EventasaurusApp.Images.MovieImages
  import Ecto.Query

  require Logger

  @impl true
  def mount(_params, session, socket) do
    # Get language from session (set by LanguagePlug), then connect params, then default to English
    params = get_connect_params(socket) || %{}
    language = session["language"] || params["locale"] || "en"

    # Get request URI for building absolute URLs (supports ngrok, localhost, production)
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
      |> assign(:show_plan_with_friends_modal, false)
      |> assign(:selected_users, [])
      |> assign(:selected_emails, [])
      |> assign(:current_email_input, "")
      |> assign(:bulk_email_input, "")
      |> assign(:invitation_message, "")
      |> assign(:planning_mode, :flexible_filters)
      |> assign(:filter_criteria, %{})
      |> assign(:matching_occurrences, [])
      |> assign(:filter_preview_count, nil)
      |> assign(:modal_organizer, nil)
      |> assign(:date_availability, %{})
      |> assign(:time_period_availability, %{})
      |> assign(:entry_context, :generic_movie)
      |> assign(:is_single_occurrence, false)
      |> assign(:selected_occurrence, nil)
      # View mode toggle state for By Venue / By Day switching
      |> assign(:view_mode, :by_venue)
      |> assign(:selected_day, nil)
      |> assign(:showtimes_by_day, %{})
      |> assign(:available_days, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"city_slug" => city_slug, "movie_slug" => movie_slug}, _url, socket) do
    # Fetch city
    city =
      from(c in City,
        where: c.slug == ^city_slug,
        preload: [:country]
      )
      |> Repo.one()

    # Fetch movie by slug, legacy_slug, or TMDB ID
    movie = find_movie(movie_slug)

    case {city, movie} do
      {nil, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("City not found"))
         |> redirect(to: ~p"/activities")}

      {_, nil} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Movie not found"))
         |> redirect(to: ~p"/activities")}

      {city, movie} ->
        # Redirect to canonical URL if not already there
        if movie_slug != movie.slug do
          {:noreply, redirect(socket, to: ~p"/c/#{city.slug}/movies/#{movie.slug}")}
        else
          handle_movie_screenings(socket, city, movie)
        end
    end
  end

  # Handle the movie screenings page rendering
  defp handle_movie_screenings(socket, city, movie) do
    # Fetch upcoming screenings for this movie in this city
    _now = DateTime.utc_now()

    screenings =
      from(pe in PublicEvent,
        join: em in "event_movies",
        on: pe.id == em.event_id,
        join: v in assoc(pe, :venue),
        on: v.city_id == ^city.id,
        where: em.movie_id == ^movie.id,
        order_by: [asc: pe.starts_at],
        preload: [:categories, :performers, venue: :city_ref, sources: :source]
      )
      |> Repo.all()

    # Group by venue and extract detailed information from ALL occurrences
    # Separates into upcoming and recent past for better UX
    venues_with_info =
      screenings
      |> Enum.group_by(& &1.venue.id)
      |> Enum.map(fn {_venue_id, events} ->
        first_event = List.first(events)

        # Extract occurrences separated by time (upcoming vs recent past)
        {upcoming_occurrences, recent_past_occurrences} = extract_occurrences_by_time(events)

        # Count showtimes in each category
        upcoming_count = length(upcoming_occurrences)
        recent_past_count = length(recent_past_occurrences)

        # Get date range from upcoming occurrences (primary display)
        # Fall back to recent past if no upcoming
        date_range =
          cond do
            upcoming_count > 0 ->
              extract_occurrence_date_range(upcoming_occurrences)

            recent_past_count > 0 ->
              extract_occurrence_date_range(recent_past_occurrences)

            true ->
              format_date_short(Date.utc_today())
          end

        # Extract unique formats from all occurrences (both upcoming and past)
        all_occurrences = upcoming_occurrences ++ recent_past_occurrences
        formats = extract_occurrence_formats(all_occurrences)

        # Extract unique dates for optional display (upcoming first)
        unique_dates =
          all_occurrences
          |> Enum.map(& &1.date)
          |> Enum.uniq()
          |> Enum.sort()

        # Calculate past date range separately (for recently missed section)
        past_date_range =
          if recent_past_count > 0 do
            extract_occurrence_date_range(recent_past_occurrences)
          else
            nil
          end

        {first_event.venue,
         %{
           # New fields for upcoming vs recent past separation
           upcoming_count: upcoming_count,
           recent_past_count: recent_past_count,
           upcoming_occurrences: upcoming_occurrences,
           recent_past_occurrences: recent_past_occurrences,
           # Keep count for backwards compatibility (now shows upcoming only for display)
           count: upcoming_count,
           slug: first_event.slug,
           date_range: date_range,
           past_date_range: past_date_range,
           formats: formats,
           dates: unique_dates
         }}
      end)
      # Filter out venues with no data in either category
      |> Enum.filter(fn {_venue, info} ->
        info.upcoming_count > 0 or info.recent_past_count > 0
      end)
      # Sort: venues with upcoming first (by name), then recent-past-only venues (by name)
      |> Enum.sort_by(fn {venue, info} ->
        # Primary sort: has upcoming (0) vs only past (1)
        # Secondary sort: venue name
        has_upcoming = if info.upcoming_count > 0, do: 0, else: 1
        {has_upcoming, venue.name}
      end)

    # Sum up all showtime counts from all venues
    total_showtimes =
      venues_with_info
      |> Enum.map(fn {_venue, info} -> info.count end)
      |> Enum.sum()

    # Transform data for "By Day" view - group all showtimes chronologically by date
    {showtimes_by_day, available_days} = transform_to_by_day_view(venues_with_info)

    # Auto-select first available day for By Day view
    first_available_day = List.first(available_days)

    # Get available languages for this city (dynamic based on country + DB translations)
    available_languages =
      if city && city.slug do
        LanguageDiscovery.get_available_languages_for_city(city.slug)
      else
        ["en"]
      end

    # Extract primary category from first screening (all movie screenings should have same category)
    primary_category =
      case screenings do
        [first_screening | _] -> get_primary_category(first_screening)
        _ -> nil
      end

    # Build breadcrumb navigation using BreadcrumbBuilder
    breadcrumb_items = BreadcrumbBuilder.build_movie_screenings_breadcrumbs(movie, city)

    # Build rich_data map for movie components
    rich_data = build_rich_data_from_movie(movie)

    # Fetch cast/crew from TMDB if we have a tmdb_id
    {cast, crew} = fetch_cast_and_crew(movie.tmdb_id)

    # Enrich movie with TMDB metadata for JSON-LD generation
    # This populates the virtual tmdb_metadata field with credits data
    movie_with_metadata = enrich_movie_for_json_ld(movie, cast, crew)

    # Generate JSON-LD structured data for movie page
    json_ld = MovieSchema.generate(movie_with_metadata, city, venues_with_info)

    # Generate Open Graph meta tags with branded social card
    og_tags = build_movie_open_graph(movie, city, total_showtimes, socket.assigns.request_uri)

    {:noreply,
     socket
     |> assign(:page_title, "#{movie.title} - #{city.name}")
     |> assign(:city, city)
     |> assign(:movie, movie)
     |> assign(:venues_with_info, venues_with_info)
     |> assign(:total_showtimes, total_showtimes)
     |> assign(:breadcrumb_items, breadcrumb_items)
     |> assign(:available_languages, available_languages)
     |> assign(:primary_category, primary_category)
     |> assign(:json_ld, json_ld)
     |> assign(:open_graph, og_tags)
     |> assign(:rich_data, rich_data)
     |> assign(:cast, cast)
     |> assign(:crew, crew)
     # By Day view data
     |> assign(:showtimes_by_day, showtimes_by_day)
     |> assign(:available_days, available_days)
     |> assign(:selected_day, first_available_day)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Breadcrumbs and Language Switcher (same line) -->
        <div class="flex items-center justify-between mb-6">
          <Breadcrumbs.breadcrumb items={@breadcrumb_items} />
          <.language_switcher
            available_languages={@available_languages}
            current_language={@language}
          />
        </div>

        <!-- Category Display -->
        <%= if @primary_category do %>
          <div class="mb-6">
            <div class="flex items-center">
              <.link
                navigate={~p"/activities?#{[category: @primary_category.slug]}"}
                class="inline-flex items-center px-4 py-2 rounded-full text-sm font-semibold text-white hover:opacity-90 transition"
                style={safe_background_style(@primary_category.color)}
              >
                <%= if @primary_category.icon do %>
                  <span class="mr-1"><%= @primary_category.icon %></span>
                <% end %>
                <%= @primary_category.name %>
              </.link>
            </div>
            <p class="mt-2 text-xs text-gray-500">
              <%= gettext("Click category to see related events") %>
            </p>
          </div>
        <% end %>

        <!-- Movie Hero Section (Cinegraph-style with backdrop, overview, and links inline) -->
        <.live_component
          module={MovieHeroComponent}
          id="movie-hero"
          rich_data={@rich_data}
          variant={:card}
          show_overview={true}
          show_links={true}
          tmdb_id={@movie.tmdb_id}
        />

        <!-- Plan with Friends Button -->
        <div class="my-8">
          <button
            phx-click="open_plan_modal"
            class="inline-flex items-center px-6 py-3 bg-green-600 text-white font-medium rounded-lg hover:bg-green-700 transition"
          >
            <Heroicons.user_group class="w-5 h-5 mr-2" />
            <%= gettext("Plan with Friends") %>
          </button>
          <p class="mt-2 text-sm text-gray-600">
            <%= gettext("Coordinate with friends to pick a screening time") %>
          </p>
        </div>

        <!-- Cast Section -->
        <%= if length(@cast) > 0 do %>
          <div class="mt-8 bg-white rounded-2xl border border-gray-200 p-6 shadow-sm">
            <.live_component
              module={CastCarouselComponent}
              id="movie-cast"
              cast={@cast}
              variant={:embedded}
              max_cast={10}
            />
          </div>
        <% end %>

        <!-- Screenings Section -->
        <div class="mt-8">
          <.live_component
            module={CityScreeningsSection}
            id="city-screenings"
            city={@city}
            venues_with_info={@venues_with_info}
            total_showtimes={@total_showtimes}
            variant={:card}
            compact={false}
            show_empty_state={true}
            view_mode={@view_mode}
            selected_day={@selected_day}
            showtimes_by_day={@showtimes_by_day}
            available_days={@available_days}
          />
        </div>

        <!-- Plan with Friends Modal -->
        <%= if @show_plan_with_friends_modal do %>
          <PublicPlanWithFriendsModal.modal
            id="plan-with-friends-modal"
            show={@show_plan_with_friends_modal}
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
            is_movie_event={true}
            is_venue_event={false}
            entry_context={@entry_context}
            is_single_occurrence={@is_single_occurrence}
            selected_occurrence={@selected_occurrence}
            movie_id={@movie.id}
            city_id={@city.id}
            movie={@movie}
            city={@city}
            date_availability={@date_availability}
            time_period_availability={@time_period_availability}
          />
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("open_plan_modal", _params, socket) do
    # Check authentication first to prevent crashes
    if is_nil(socket.assigns[:auth_user]) do
      {:noreply,
       socket
       |> put_flash(:info, "Please log in to create private events")
       |> redirect(to: ~p"/auth/login")}
    else
      # Get authenticated user for the modal
      user = get_authenticated_user(socket)

      # Fetch date availability counts for the movie
      movie = socket.assigns.movie
      # false = movie event (7 days)
      date_list = generate_date_list(false)

      # Build filter criteria with city_ids to constrain results to current city
      # Without this, counts would include venues from ALL cities globally
      # See: https://github.com/razrfly/eventasaurus/issues/3252
      city_ids =
        case socket.assigns[:city] do
          %{id: city_id} when not is_nil(city_id) -> [city_id]
          _ -> []
        end

      filter_criteria = %{city_ids: city_ids}

      date_availability =
        case EventasaurusApp.Planning.OccurrenceQuery.get_date_availability_counts(
               "movie",
               movie.id,
               date_list,
               filter_criteria
             ) do
          {:ok, counts} -> counts
          {:error, _} -> %{}
        end

      # Fetch time period availability counts for the movie
      time_period_availability =
        case EventasaurusApp.Planning.OccurrenceQuery.get_time_period_availability_counts(
               "movie",
               movie.id,
               filter_criteria
             ) do
          {:ok, counts} -> counts
          {:error, _} -> %{}
        end

      {:noreply,
       socket
       |> assign(:show_plan_with_friends_modal, true)
       |> assign(:modal_organizer, user)
       |> assign(:date_availability, date_availability)
       |> assign(:time_period_availability, time_period_availability)
       # Store original unfiltered counts for dynamic count restoration
       # See: https://github.com/razrfly/eventasaurus/issues/3258
       |> assign(:original_date_availability, date_availability)
       |> assign(:original_time_period_availability, time_period_availability)}
    end
  end

  @impl true
  def handle_event("close_plan_modal", _params, socket) do
    {:noreply, assign(socket, :show_plan_with_friends_modal, false)}
  end

  @impl true
  def handle_event("apply_flexible_filters", params, socket) do
    # Parse selected dates and convert to date range
    selected_dates = Map.get(params, "selected_dates", [])

    {date_from, date_to} =
      if length(selected_dates) > 0 do
        # Use safe date parsing to prevent crashes on invalid input
        dates =
          selected_dates
          |> Enum.map(&Date.from_iso8601/1)
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, d} -> d end)
          |> Enum.sort(Date)

        if dates == [] do
          # All dates were invalid, use default
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

    filter_criteria = %{
      selected_dates: selected_dates,
      date_from: Date.to_iso8601(date_from),
      date_to: Date.to_iso8601(date_to),
      time_preferences: Map.get(params, "time_preferences", []),
      limit: limit
    }

    # Query for matching movie occurrences (constrained to current city)
    movie = socket.assigns.movie
    city = socket.assigns[:city]
    matching_occurrences = query_movie_occurrences(movie.id, filter_criteria, city)

    {:noreply,
     socket
     |> assign(:filter_criteria, filter_criteria)
     |> assign(:matching_occurrences, matching_occurrences)
     |> assign(:planning_mode, :flexible_review)}
  end

  @impl true
  def handle_event("submit_plan_with_friends", %{"mode" => mode}, socket) do
    case mode do
      "flexible" -> handle_flexible_plan_submit(socket)
      _ -> handle_flexible_plan_submit(socket)
    end
  end

  @impl true
  def handle_event("submit_plan_with_friends", _params, socket) do
    # Default to flexible planning
    handle_flexible_plan_submit(socket)
  end

  @impl true
  # Threshold for skipping filter UI - if <= this many showtimes, show them all directly
  @small_showtime_threshold 15

  def handle_event("select_planning_mode", %{"mode" => "flexible"}, socket) do
    # Check total showtimes for next 7 days (no time preference filter)
    movie = socket.assigns.movie

    if movie do
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
        # This provides a streamlined experience when there's only one option
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
    else
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

    filter_criteria = %{
      selected_dates: selected_dates,
      date_from: Date.to_iso8601(date_from),
      date_to: Date.to_iso8601(date_to),
      time_preferences: Map.get(params, "time_preferences", []),
      meal_periods: Map.get(params, "meal_periods", []),
      limit: limit
    }

    # Query for matching occurrences count only (not full data)
    # Use a separate query WITHOUT the limit to get the true total count
    # The limit only applies to how many poll options are created, not the preview count
    movie = socket.assigns.movie
    city = socket.assigns[:city]

    count =
      if movie do
        # Remove limit for count query - we want total matching, not capped results
        count_criteria = Map.delete(filter_criteria, :limit)
        query_movie_occurrences(movie.id, count_criteria, city) |> length()
      else
        0
      end

    # === Dynamic Count Updates ===
    # Recalculate availability counts based on current filters
    # This enables the "cross-filter" UX where selecting dates updates time period counts
    # and selecting time preferences updates date counts
    # When filters are cleared, restore original unfiltered counts
    # See: https://github.com/razrfly/eventasaurus/issues/3258

    # Get original unfiltered counts (stored when modal opened)
    original_date_availability =
      Map.get(socket.assigns, :original_date_availability, socket.assigns.date_availability)

    original_time_period_availability =
      Map.get(socket.assigns, :original_time_period_availability, socket.assigns.time_period_availability)

    # Build filter criteria with city_ids
    city_ids =
      case socket.assigns[:city] do
        %{id: city_id} when not is_nil(city_id) -> [city_id]
        _ -> []
      end

    date_list = generate_date_list(false)
    time_preferences = filter_criteria.time_preferences
    selected_dates = filter_criteria.selected_dates

    # Recalculate date availability with time_preferences filter
    # When user selects "evening", date pills should show only evening showtimes per date
    # When no time preferences selected, restore original unfiltered counts
    date_availability =
      if time_preferences != [] do
        date_filter_criteria = %{
          city_ids: city_ids,
          time_preferences: time_preferences
        }

        case EventasaurusApp.Planning.OccurrenceQuery.get_date_availability_counts(
               "movie",
               movie.id,
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

    # Recalculate time period availability with selected_dates filter
    # When user selects specific dates, time period buttons should show only those dates' distribution
    # When no dates selected, restore original unfiltered counts
    time_period_availability =
      if selected_dates != [] do
        time_filter_criteria = %{
          city_ids: city_ids,
          selected_dates: selected_dates
        }

        case EventasaurusApp.Planning.OccurrenceQuery.get_time_period_availability_counts(
               "movie",
               movie.id,
               time_filter_criteria
             ) do
          {:ok, counts} -> counts
          {:error, _} -> original_time_period_availability
        end
      else
        # No dates selected, restore original unfiltered counts
        original_time_period_availability
      end

    {:noreply,
     socket
     |> assign(:filter_criteria, filter_criteria)
     |> assign(:filter_preview_count, count)
     |> assign(:date_availability, date_availability)
     |> assign(:time_period_availability, time_period_availability)}
  end

  # View mode toggle handlers for By Venue / By Day switching
  @impl true
  def handle_event("change_view_mode", %{"mode" => "by_day"}, socket) do
    # When switching to By Day, auto-select first available day if none selected
    selected_day =
      socket.assigns.selected_day || List.first(socket.assigns.available_days)

    {:noreply,
     socket
     |> assign(:view_mode, :by_day)
     |> assign(:selected_day, selected_day)}
  end

  @impl true
  def handle_event("change_view_mode", %{"mode" => "by_venue"}, socket) do
    {:noreply, assign(socket, :view_mode, :by_venue)}
  end

  @impl true
  def handle_event("select_day", %{"date" => date_string}, socket) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        {:noreply, assign(socket, :selected_day, date)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:language_changed, _language}, socket) do
    # Language is already updated by the hook, no need to reload data
    # since movie screenings data doesn't change by language
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

  # Helper functions

  # Handle flexible planning submission - delegates to shared helper
  defp handle_flexible_plan_submit(socket) do
    user = get_authenticated_user(socket)
    movie = socket.assigns.movie

    # Ensure we have movie data
    if is_nil(movie) do
      {:noreply,
       socket
       |> assign(:show_plan_with_friends_modal, false)
       |> put_flash(:error, gettext("Movie not found. Please try again."))}
    else
      PlanWithFriendsHelpers.execute_flexible_plan(socket, movie, user, default_limit: 50)
    end
  end

  # Transform venues_with_info to a day-grouped view for "By Day" toggle
  # Returns {showtimes_by_day_map, sorted_available_days_list}
  defp transform_to_by_day_view(venues_with_info) do
    # Flatten all upcoming occurrences and attach venue info
    all_showtimes =
      venues_with_info
      |> Enum.flat_map(fn {venue, info} ->
        info.upcoming_occurrences
        |> Enum.map(fn occ ->
          Map.merge(occ, %{
            venue: venue,
            slug: info.slug,
            formats: info.formats
          })
        end)
      end)

    # Group by date
    by_day =
      all_showtimes
      |> Enum.group_by(& &1.date)
      |> Enum.map(fn {date, showtimes} ->
        # Sort showtimes by time within each day
        sorted = Enum.sort_by(showtimes, & &1.datetime, {:asc, DateTime})
        {date, sorted}
      end)
      |> Map.new()

    # Get sorted list of available days (only days with showtimes)
    available_days =
      by_day
      |> Map.keys()
      |> Enum.sort(Date)

    {by_day, available_days}
  end

  defp query_movie_occurrences(movie_id, filter_criteria, city) do
    alias EventasaurusApp.Planning.OccurrenceQuery

    # Convert filter criteria to format expected by OccurrenceQuery
    # Include city_ids to constrain results to current city only
    # See: https://github.com/razrfly/eventasaurus/issues/3252
    city_ids = if city && city.id, do: [city.id], else: []

    # Build base query criteria
    # Only include limit if explicitly provided - omitting it means no limit (for counting)
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

  # Find movie by identifier, trying multiple lookup strategies:
  # 1. Direct slug match (canonical: "home-alone-771")
  # 2. Legacy slug match (old format: "home-alone-499")
  # 3. TMDB ID only ("771")
  defp find_movie(identifier) when is_binary(identifier) do
    # Try canonical slug first
    movie = Repo.one(from(m in Movie, where: m.slug == ^identifier))

    cond do
      movie != nil ->
        movie

      # Try legacy slug (backwards compatibility)
      true ->
        movie = Repo.one(from(m in Movie, where: m.legacy_slug == ^identifier))

        if movie do
          movie
        else
          # Try parsing as TMDB ID
          case parse_tmdb_id(identifier) do
            nil -> nil
            tmdb_id -> Repo.one(from(m in Movie, where: m.tmdb_id == ^tmdb_id))
          end
        end
    end
  end

  defp find_movie(_), do: nil

  # Parse TMDB ID from identifier:
  # - "157336" -> 157336 (TMDB ID only)
  # - "interstellar-157336" -> 157336 (slug-tmdb_id format, extracts trailing ID)
  defp parse_tmdb_id(identifier) when is_binary(identifier) do
    cond do
      # Pure numeric - just TMDB ID
      Regex.match?(~r/^\d+$/, identifier) ->
        case Integer.parse(identifier) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      # slug-tmdb_id format (e.g., "interstellar-157336")
      # Extract the TMDB ID from the end after the last hyphen
      Regex.match?(~r/^.+-\d+$/, identifier) ->
        parts = String.split(identifier, "-")
        tmdb_part = List.last(parts)

        case Integer.parse(tmdb_part) do
          {id, ""} when id > 0 -> id
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp parse_tmdb_id(_), do: nil

  # Helper functions

  # Extract ALL occurrences from all events and parse them into structured data
  # Returns {upcoming, recent_past} tuple where:
  # - upcoming: occurrences with DateTime > now
  # - recent_past: occurrences within the last `past_days` days (default 7)
  @default_recent_past_days 7

  defp extract_occurrences_by_time(events, past_days \\ @default_recent_past_days) do
    now = DateTime.utc_now()
    today = Date.utc_today()
    cutoff_date = Date.add(today, -past_days)

    all_occurrences =
      events
      |> Enum.flat_map(fn event ->
        case get_in(event.occurrences, ["dates"]) do
          dates when is_list(dates) ->
            dates
            |> Enum.map(fn date_info ->
              with {:ok, date} <- Date.from_iso8601(date_info["date"]),
                   {:ok, time} <- parse_time_string(date_info["time"]) do
                # Create datetime in UTC
                utc_datetime = DateTime.new!(date, time, "Etc/UTC")

                %{
                  date: date,
                  datetime: utc_datetime,
                  label: date_info["label"]
                }
              else
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          _ ->
            []
        end
      end)

    # Separate into upcoming and recent past
    {upcoming, past} =
      Enum.split_with(all_occurrences, fn occ ->
        DateTime.compare(occ.datetime, now) == :gt
      end)

    # Filter past to only include recent (within past_days)
    recent_past =
      past
      |> Enum.filter(fn occ ->
        Date.compare(occ.date, cutoff_date) != :lt
      end)

    # Sort both lists
    upcoming_sorted = Enum.sort_by(upcoming, & &1.datetime, {:asc, DateTime})
    recent_past_sorted = Enum.sort_by(recent_past, & &1.datetime, {:desc, DateTime})

    {upcoming_sorted, recent_past_sorted}
  end

  # Parse time string to Time struct
  defp parse_time_string(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [hour_str, minute_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str) do
          Time.new(hour, minute, 0)
        else
          _ -> {:ok, ~T[20:00:00]}
        end

      _ ->
        {:ok, ~T[20:00:00]}
    end
  end

  defp parse_time_string(_), do: {:ok, ~T[20:00:00]}

  # Extract date range from list of occurrences
  defp extract_occurrence_date_range([]), do: ""

  defp extract_occurrence_date_range(occurrences) do
    first_date = List.first(occurrences).date
    last_date = List.last(occurrences).date

    if Date.compare(first_date, last_date) == :eq do
      format_date_short(first_date)
    else
      "#{format_date_short(first_date)}-#{format_date_short(last_date)}"
    end
  end

  # Extract unique formats from occurrence labels
  defp extract_occurrence_formats(occurrences) do
    occurrences
    |> Enum.map(& &1.label)
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&parse_formats_from_label/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Parse format information from label strings
  defp parse_formats_from_label(label) when is_binary(label) do
    label_lower = String.downcase(label)

    formats = []
    formats = if String.contains?(label_lower, "imax"), do: ["IMAX" | formats], else: formats
    formats = if String.contains?(label_lower, "4dx"), do: ["4DX" | formats], else: formats
    formats = if String.contains?(label_lower, "3d"), do: ["3D" | formats], else: formats

    formats =
      if String.contains?(label_lower, ["2d", "standard"]), do: ["2D" | formats], else: formats

    formats
  end

  defp parse_formats_from_label(_), do: []

  # Format date in short form: "oct 5"
  defp format_date_short(date) do
    month_abbr = Calendar.strftime(date, "%b") |> String.capitalize()
    "#{month_abbr} #{date.day}"
  end

  # Category helper functions
  defp get_primary_category(event) do
    case event.primary_category_id do
      nil -> nil
      cat_id -> Enum.find(event.categories, &(&1.id == cat_id))
    end
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

  # Helper to generate date list matching modal's generate_date_options logic
  defp generate_date_list(is_venue_event) do
    days = if is_venue_event, do: 14, else: 7
    today = Date.utc_today()

    Enum.map(0..(days - 1), fn offset ->
      Date.add(today, offset)
    end)
  end

  # Helper to get authenticated user from socket assigns
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

  # Build Open Graph meta tags for movie page with branded social card
  defp build_movie_open_graph(movie, city, total_showtimes, request_uri) do
    # Build absolute canonical URL using UrlHelper
    canonical_path = "/c/#{city.slug}/movies/#{movie.slug}"
    canonical_url = UrlHelper.build_url(canonical_path, request_uri)

    # Build description
    description =
      "Watch #{movie.title} in #{city.name}. #{total_showtimes} #{pluralize_showtime(total_showtimes)} available at multiple cinemas."

    # Build movie data for social card hash generation
    # Use cached URLs for consistent hash generation (matches what's displayed)
    poster_url = MovieImages.get_poster_url(movie.id, movie.poster_url)
    backdrop_url = MovieImages.get_backdrop_url(movie.id, movie.backdrop_url)

    movie_data = %{
      title: movie.title,
      slug: movie.slug,
      city: %{
        name: city.name,
        slug: city.slug
      },
      poster_url: poster_url,
      backdrop_url: backdrop_url,
      total_showtimes: total_showtimes,
      updated_at: movie.updated_at
    }

    # Generate branded social card URL path
    social_card_path = HashGenerator.generate_url_path(movie_data, :movie)

    # Build absolute image URL
    social_card_url = UrlHelper.build_url(social_card_path, request_uri)

    # Render Open Graph component with branded social card
    Phoenix.HTML.Safe.to_iodata(
      EventasaurusWeb.Components.OpenGraphComponent.open_graph_tags(%{
        type: "video.movie",
        title: "#{movie.title} - #{city.name}",
        description: description,
        image_url: social_card_url,
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

  defp pluralize_showtime(1), do: "showtime"
  defp pluralize_showtime(_), do: "showtimes"

  # Build rich_data map from movie for use with movie components
  # Uses actual movie fields (poster_url, backdrop_url, etc.) and metadata map
  defp build_rich_data_from_movie(movie) do
    metadata = movie.metadata || %{}

    # Extract poster_path from full URL if present
    # movie.poster_url is like "https://image.tmdb.org/t/p/w500/onTSipZ8R3bliBdKfPtsDuHTdlL.jpg"
    # We need "/onTSipZ8R3bliBdKfPtsDuHTdlL.jpg" for the components
    poster_path = extract_tmdb_path(movie.poster_url)
    backdrop_path = extract_tmdb_path(movie.backdrop_url)

    # Build external links map
    external_links =
      %{}
      |> maybe_add_link(:tmdb_url, movie.tmdb_id, &"https://www.themoviedb.org/movie/#{&1}")

    %{
      "title" => movie.title,
      "overview" => movie.overview,
      "poster_path" => poster_path,
      "backdrop_path" => backdrop_path,
      "release_date" => format_release_date_for_rich_data(movie.release_date),
      "runtime" => movie.runtime,
      "vote_average" => metadata["vote_average"],
      "vote_count" => metadata["vote_count"],
      "genres" => build_genres_list(metadata["genres"]),
      "director" => nil,
      "crew" => [],
      "external_links" => external_links
    }
  end

  # Extract the path portion from a full TMDB image URL
  # "https://image.tmdb.org/t/p/w500/abc123.jpg" -> "/abc123.jpg"
  defp extract_tmdb_path(nil), do: nil
  defp extract_tmdb_path(""), do: nil

  defp extract_tmdb_path(url) when is_binary(url) do
    case Regex.run(~r{/t/p/w\d+(/[^/]+\.\w+)$}, url) do
      [_, path] -> path
      _ -> nil
    end
  end

  # Format release_date for display
  defp format_release_date_for_rich_data(nil), do: nil
  defp format_release_date_for_rich_data(%Date{} = date), do: Date.to_iso8601(date)
  defp format_release_date_for_rich_data(date) when is_binary(date), do: date

  # Build genres list - metadata may have string list or map list
  defp build_genres_list(nil), do: []

  defp build_genres_list(genres) when is_list(genres) do
    Enum.map(genres, fn
      %{"name" => name} -> %{"name" => name}
      name when is_binary(name) -> %{"name" => name}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_genres_list(_), do: []

  defp maybe_add_link(map, _key, nil, _builder), do: map
  defp maybe_add_link(map, _key, "", _builder), do: map

  defp maybe_add_link(map, key, value, builder) do
    Map.put(map, key, builder.(value))
  end

  # Fetch cast and crew from TMDB API
  # Returns {cast, crew} tuple where each is a list of maps with string keys
  # (CastCarouselComponent expects string keys like "name", "character", "profile_path")
  defp fetch_cast_and_crew(nil), do: {[], []}

  defp fetch_cast_and_crew(tmdb_id) do
    case TmdbService.get_cached_movie_details(tmdb_id) do
      {:ok, movie_data} ->
        cast =
          (movie_data[:cast] || [])
          |> Enum.map(&stringify_keys/1)

        crew =
          (movie_data[:crew] || [])
          |> Enum.map(&stringify_keys/1)

        {cast, crew}

      {:error, _reason} ->
        # If TMDB fetch fails, return empty arrays
        {[], []}
    end
  end

  # Convert map with atom keys to string keys for component compatibility
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  # Enrich movie struct with TMDB metadata for JSON-LD generation
  # This populates the virtual tmdb_metadata field with credits data
  # so that director/actor fields can be extracted by MovieSchema
  defp enrich_movie_for_json_ld(movie, cast, crew) do
    # Build tmdb_metadata map with credits data for JSON-LD extraction
    tmdb_metadata = %{
      "credits" => %{
        "cast" => cast,
        "crew" => crew
      },
      "release_date" =>
        if(movie.release_date, do: Date.to_iso8601(movie.release_date), else: nil),
      "runtime" => movie.runtime
    }

    %{movie | tmdb_metadata: tmdb_metadata}
  end
end
