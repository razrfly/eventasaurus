defmodule EventasaurusWeb.PublicMovieScreeningsLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusWeb.Components.{MovieDetailsCard, Breadcrumbs, PublicPlanWithFriendsModal}
  alias EventasaurusWeb.Helpers.{LanguageDiscovery, LanguageHelpers}
  import Ecto.Query

  @impl true
  def mount(_params, session, socket) do
    # Get language from session (set by LanguagePlug), then connect params, then default to English
    params = get_connect_params(socket) || %{}
    language = session["language"] || params["locale"] || "en"

    socket =
      socket
      |> assign(:language, language)
      |> assign(:show_plan_with_friends_modal, false)
      |> assign(:selected_users, [])
      |> assign(:selected_emails, [])
      |> assign(:current_email_input, "")
      |> assign(:bulk_email_input, "")
      |> assign(:invitation_message, "")
      |> assign(:planning_mode, :flexible_filters)
      |> assign(:filter_criteria, %{})
      |> assign(:matching_occurrences, [])
      |> assign(:filter_preview_count, 0)
      |> assign(:modal_organizer, nil)
      |> assign(:date_availability, %{})

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"city_slug" => city_slug, "movie_slug" => movie_slug}, _url, socket) do
    # Fetch city
    city =
      from(c in City,
        where: c.slug == ^city_slug
      )
      |> Repo.one()

    # Fetch movie
    movie =
      from(m in Movie,
        where: m.slug == ^movie_slug
      )
      |> Repo.one()

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
        # Fetch upcoming screenings for this movie in this city
        now = DateTime.utc_now()

        screenings =
          from(pe in PublicEvent,
            join: em in "event_movies",
            on: pe.id == em.event_id,
            join: v in assoc(pe, :venue),
            on: v.city_id == ^city.id,
            where: em.movie_id == ^movie.id,
            where: pe.starts_at >= ^now,
            order_by: [asc: pe.starts_at],
            preload: [:categories, :performers, venue: :city_ref, sources: :source]
          )
          |> Repo.all()

        # Group by venue and extract detailed information from ALL occurrences
        venues_with_info =
          screenings
          |> Enum.group_by(& &1.venue.id)
          |> Enum.map(fn {_venue_id, events} ->
            first_event = List.first(events)

            # Extract ALL occurrences from ALL events for this venue
            all_occurrences = extract_all_occurrences(events)

            # Count actual showtimes (occurrences), not events
            showtime_count = length(all_occurrences)

            # Get date range from occurrences
            date_range =
              if length(all_occurrences) > 0 do
                extract_occurrence_date_range(all_occurrences)
              else
                format_date_short(Date.utc_today())
              end

            # Extract unique formats from occurrence labels
            formats = extract_occurrence_formats(all_occurrences)

            # Extract unique dates for optional display
            unique_dates =
              all_occurrences
              |> Enum.map(& &1.date)
              |> Enum.uniq()
              |> Enum.sort()

            {first_event.venue,
             %{
               count: showtime_count,
               slug: first_event.slug,
               date_range: date_range,
               formats: formats,
               dates: unique_dates
             }}
          end)
          |> Enum.sort_by(fn {venue, _info} -> venue.name end)

        # Sum up all showtime counts from all venues
        total_showtimes =
          venues_with_info
          |> Enum.map(fn {_venue, info} -> info.count end)
          |> Enum.sum()

        # Build breadcrumb navigation
        breadcrumb_items = [
          %{label: gettext("Home"), path: ~p"/"},
          %{label: gettext("All Activities"), path: ~p"/activities"},
          %{label: city.name, path: ~p"/c/#{city.slug}"},
          %{label: gettext("Film"), path: ~p"/activities?category=film"},
          %{label: movie.title, path: nil}
        ]

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

        {:noreply,
         socket
         |> assign(:page_title, "#{movie.title} - #{city.name}")
         |> assign(:city, city)
         |> assign(:movie, movie)
         |> assign(:venues_with_info, venues_with_info)
         |> assign(:total_showtimes, total_showtimes)
         |> assign(:breadcrumb_items, breadcrumb_items)
         |> assign(:available_languages, available_languages)
         |> assign(:primary_category, primary_category)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
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

        <!-- Breadcrumbs -->
        <Breadcrumbs.breadcrumb items={@breadcrumb_items} class="mb-6" />

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

        <!-- Movie Header -->
        <MovieDetailsCard.movie_details_card
          movie={@movie}
          show_see_all_link={false}
        />

        <!-- Plan with Friends Button -->
        <div class="mb-8">
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

        <!-- Screenings Section -->
        <div class="bg-white rounded-lg shadow-lg p-8">
          <h2 class="text-2xl font-bold text-gray-900 mb-6">
            <%= gettext("Screenings in %{city}", city: @city.name) %>
            <span class="text-lg font-normal text-gray-600">
              (<%= ngettext("1 showtime", "%{count} showtimes", @total_showtimes) %>)
            </span>
          </h2>

          <%= if @venues_with_info == [] do %>
            <div class="text-center py-12">
              <Heroicons.film class="w-16 h-16 text-gray-400 mx-auto mb-4" />
              <p class="text-gray-600 text-lg">
                <%= gettext("No screenings found for this movie in %{city}", city: @city.name) %>
              </p>
            </div>
          <% else %>
            <div class="space-y-4">
              <%= for {venue, info} <- @venues_with_info do %>
                <.link
                  navigate={~p"/activities/#{info.slug}"}
                  class="block p-6 border border-gray-200 rounded-lg hover:border-blue-400 hover:shadow-md transition"
                >
                  <div class="flex justify-between items-start">
                    <div class="flex-1">
                      <h3 class="text-lg font-semibold text-gray-900 mb-2">
                        <%= venue.name %>
                      </h3>

                      <%= if venue.address do %>
                        <p class="text-sm text-gray-600 mb-3">
                          <Heroicons.map_pin class="w-4 h-4 inline mr-1" />
                          <%= venue.address %>
                        </p>
                      <% end %>

                      <!-- Date range and showtime count -->
                      <div class="flex items-center text-gray-700 mb-2">
                        <Heroicons.calendar_days class="w-5 h-5 mr-2 flex-shrink-0" />
                        <span class="font-medium">
                          <%= info.date_range %> • <%= ngettext("1 showtime", "%{count} showtimes", info.count) %>
                        </span>
                      </div>

                      <!-- Format badges -->
                      <%= if length(info.formats) > 0 do %>
                        <div class="flex flex-wrap gap-2 mb-2">
                          <%= for format <- info.formats do %>
                            <span class="px-2 py-1 bg-purple-100 text-purple-800 rounded text-xs font-semibold">
                              <%= format %>
                            </span>
                          <% end %>
                        </div>
                      <% end %>

                      <!-- Specific dates (if limited) -->
                      <%= if length(info.dates) <= 7 do %>
                        <div class="text-sm text-gray-600">
                          <%= info.dates
                              |> Enum.take(4)
                              |> Enum.map(&format_date_label/1)
                              |> Enum.join(", ") %>
                          <%= if length(info.dates) > 4 do %>
                            <span class="text-gray-500">+<%= length(info.dates) - 4 %> more</span>
                          <% end %>
                        </div>
                      <% end %>
                    </div>

                    <div class="ml-4">
                      <div class="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition">
                        <%= gettext("View Showtimes") %>
                        <Heroicons.arrow_right class="w-4 h-4 ml-2" />
                      </div>
                    </div>
                  </div>
                </.link>
              <% end %>
            </div>
          <% end %>
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
            movie_id={@movie.id}
            city_id={@city.id}
            movie={@movie}
            city={@city}
            date_availability={@date_availability}
          />
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("change_language", %{"language" => language}, socket) do
    # Set cookie to persist language preference
    socket =
      socket
      |> assign(:language, language)
      |> Phoenix.LiveView.push_event("set_language_cookie", %{language: language})

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_plan_modal", _params, socket) do
    # Get authenticated user for the modal
    user = get_authenticated_user(socket)

    # Fetch date availability counts for the movie
    movie = socket.assigns.movie
    date_list = generate_date_list(false)  # false = movie event (7 days)

    date_availability =
      case EventasaurusApp.Planning.OccurrenceQuery.get_date_availability_counts(
             "movie",
             movie.id,
             date_list,
             %{}
           ) do
        {:ok, counts} -> counts
        {:error, _} -> %{}
      end

    {:noreply,
     socket
     |> assign(:show_plan_with_friends_modal, true)
     |> assign(:modal_organizer, user)
     |> assign(:date_availability, date_availability)}
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
      limit: limit
    }

    # Query for matching movie occurrences
    movie = socket.assigns.movie
    matching_occurrences = query_movie_occurrences(movie.id, filter_criteria)

    {:noreply,
     socket
     |> assign(:filter_criteria, filter_criteria)
     |> assign(:matching_occurrences, matching_occurrences)
     |> assign(:planning_mode, :flexible_review)}
  end

  @impl true
  def handle_event("submit_plan_with_friends", %{"mode" => _mode}, socket) do
    # Handle plan submission
    # For now, just close the modal
    # Full implementation would create the plan and redirect
    {:noreply, assign(socket, :show_plan_with_friends_modal, false)}
  end

  @impl true
  def handle_event("submit_plan_with_friends", _params, socket) do
    {:noreply, assign(socket, :show_plan_with_friends_modal, false)}
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
    movie = socket.assigns.movie

    count =
      if movie do
        query_movie_occurrences(movie.id, filter_criteria) |> length()
      else
        0
      end

    {:noreply,
     socket
     |> assign(:filter_criteria, filter_criteria)
     |> assign(:filter_preview_count, count)}
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

  # Helper functions

  # Extract ALL occurrences from all events and parse them into structured data
  defp extract_all_occurrences(events) do
    now = DateTime.utc_now()

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

              # Only include future occurrences
              if DateTime.compare(utc_datetime, now) == :gt do
                %{
                  date: date,
                  datetime: utc_datetime,
                  label: date_info["label"]
                }
              else
                nil
              end
            else
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end
    end)
    |> Enum.sort_by(& &1.datetime, {:asc, DateTime})
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

  # Format date with Today/Tomorrow labels
  defp format_date_label(date) do
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    case date do
      ^today -> gettext("Today")
      ^tomorrow -> gettext("Tomorrow")
      _ -> format_date_short(date)
    end
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
end
