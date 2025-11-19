defmodule EventasaurusWeb.PublicMovieScreeningsLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
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

        {:noreply,
         socket
         |> assign(:page_title, "#{movie.title} - #{city.name}")
         |> assign(:city, city)
         |> assign(:movie, movie)
         |> assign(:venues_with_info, venues_with_info)
         |> assign(:total_showtimes, total_showtimes)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Breadcrumbs -->
        <nav class="mb-6 flex items-center space-x-2 text-sm text-gray-600">
          <.link navigate={~p"/activities"} class="hover:text-blue-600">
            <%= gettext("All Activities") %>
          </.link>
          <span>/</span>
          <.link navigate={~p"/c/#{@city.slug}"} class="hover:text-blue-600">
            <%= @city.name %>
          </.link>
          <span>/</span>
          <.link navigate={~p"/activities?category=film"} class="hover:text-blue-600">
            <%= gettext("Film") %>
          </.link>
          <span>/</span>
          <span class="text-gray-900 font-medium"><%= @movie.title %></span>
        </nav>

        <!-- Movie Header -->
        <div class="bg-white rounded-lg shadow-lg overflow-hidden mb-8">
          <%= if @movie.backdrop_url do %>
            <div class="h-96 relative">
              <img
                src={@movie.backdrop_url}
                alt={@movie.title}
                class="w-full h-full object-cover"
              />
              <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent"></div>
              <div class="absolute bottom-0 left-0 right-0 p-8 text-white">
                <h1 class="text-4xl font-bold mb-2">
                  <%= @movie.title %>
                  <%= if @movie.release_date do %>
                    <span class="text-2xl font-normal opacity-90">
                      (<%= Calendar.strftime(@movie.release_date, "%Y") %>)
                    </span>
                  <% end %>
                </h1>
                <%= if @movie.original_title && @movie.original_title != @movie.title do %>
                  <p class="text-lg opacity-90 italic">
                    <%= @movie.original_title %>
                  </p>
                <% end %>
              </div>
            </div>
          <% end %>

          <div class="p-8">
            <!-- Movie Metadata -->
            <div class="flex flex-wrap items-center gap-6 mb-6">
              <%= if @movie.runtime do %>
                <div class="flex items-center text-gray-700">
                  <Heroicons.clock class="w-5 h-5 mr-2" />
                  <span><%= format_movie_runtime(@movie.runtime) %></span>
                </div>
              <% end %>

              <%= if genres = get_in(@movie.metadata, ["genres"]) do %>
                <%= if is_list(genres) && length(genres) > 0 do %>
                  <div class="flex flex-wrap gap-2">
                    <%= for genre <- genres do %>
                      <span class="px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm font-medium">
                        <%= genre %>
                      </span>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>

            <!-- Movie Overview -->
            <%= if @movie.overview do %>
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-gray-900 mb-3">
                  <%= gettext("Overview") %>
                </h2>
                <p class="text-gray-700 leading-relaxed">
                  <%= @movie.overview %>
                </p>
              </div>
            <% end %>

            <!-- External Links -->
            <div :if={@movie.tmdb_id} class="flex gap-4">
              <a
                href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
              >
                <Heroicons.globe_alt class="w-5 h-5 mr-2" />
                <%= gettext("View on TMDB") %>
              </a>
            </div>

            <!-- TMDB Attribution -->
            <p class="text-xs text-gray-500 mt-4">
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
      </div>
    </div>
    """
  end

  # Helper functions

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
end
