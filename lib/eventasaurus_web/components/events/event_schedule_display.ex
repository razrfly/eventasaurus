defmodule EventasaurusWeb.Components.Events.EventScheduleDisplay do
  @moduledoc """
  Polymorphic component for displaying event schedule information.

  Routes to appropriate display based on event type and occurrence pattern:
  - Movie screenings with multiple dates -> "Screening Schedule"
  - Single occurrence events -> "Date & Time"
  - Recurring events with pattern -> "Date & Time" with pattern
  - Other multi-occurrence events -> "Schedule" with date range
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  attr :event, :map, required: true
  attr :occurrence_list, :list, required: true
  attr :selected_occurrence, :map, default: nil
  attr :is_movie_screening, :boolean, default: false

  def event_schedule_display(assigns) do
    ~H"""
    <%= if should_show_schedule?(@occurrence_list, @is_movie_screening) do %>
      <div>
        <%= case schedule_display_type(@is_movie_screening, @occurrence_list) do %>
          <% :movie_screening -> %>
            <.movie_screening_schedule
              occurrence_list={@occurrence_list}
              event={@event}
            />

          <% :single_datetime -> %>
            <.single_datetime_display
              event={@event}
              selected_occurrence={@selected_occurrence}
            />

          <% :multi_day_schedule -> %>
            <.multi_day_schedule_display
              occurrence_list={@occurrence_list}
            />
        <% end %>
      </div>
    <% end %>
    """
  end

  # Movie screening with multiple occurrences - show screening schedule
  defp movie_screening_schedule(assigns) do
    assigns = assign(assigns, :schedule_info, extract_schedule_info(assigns.occurrence_list))

    ~H"""
    <div class="flex items-center text-gray-600 mb-1">
      <Heroicons.film class="w-5 h-5 mr-2" />
      <span class="font-medium"><%= gettext("Screening Schedule") %></span>
    </div>
    <p class="text-gray-900">
      <%= @schedule_info.date_range %>
    </p>
    <p class="text-sm text-gray-600 mt-1">
      <%= ngettext("1 showtime", "%{count} showtimes", @schedule_info.showtime_count) %>
    </p>
    <%= if length(@schedule_info.formats) > 0 do %>
      <div class="flex flex-wrap gap-1 mt-2">
        <%= for format <- @schedule_info.formats do %>
          <span class="px-2 py-0.5 bg-purple-100 text-purple-800 rounded text-xs font-semibold">
            <%= format %>
          </span>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Single occurrence or simple recurring event - show traditional date/time
  defp single_datetime_display(assigns) do
    ~H"""
    <div class="flex items-center text-gray-600 mb-1">
      <Heroicons.calendar class="w-5 h-5 mr-2" />
      <span class="font-medium"><%= gettext("Date & Time") %></span>
    </div>
    <p class="text-gray-900">
      <%= if @selected_occurrence do %>
        <%= format_occurrence_datetime(@selected_occurrence) %>
      <% else %>
        <%= format_event_datetime(@event.starts_at) %>
        <%= if @event.ends_at do %>
          <br />
          <span class="text-sm text-gray-600">
            <%= gettext("Until") %> <%= format_event_datetime(@event.ends_at) %>
          </span>
        <% end %>
      <% end %>
    </p>
    """
  end

  # Multi-day events (not movies) - show schedule summary
  defp multi_day_schedule_display(assigns) do
    assigns = assign(assigns, :schedule_info, extract_schedule_info(assigns.occurrence_list))

    ~H"""
    <div class="flex items-center text-gray-600 mb-1">
      <Heroicons.calendar_days class="w-5 h-5 mr-2" />
      <span class="font-medium"><%= gettext("Schedule") %></span>
    </div>
    <p class="text-gray-900">
      <%= @schedule_info.date_range %>
    </p>
    <p class="text-sm text-gray-600 mt-1">
      <%= ngettext("1 date", "%{count} dates", length(@schedule_info.unique_dates)) %>
    </p>
    """
  end

  # Determine if we should show any schedule information
  defp should_show_schedule?(nil, _), do: false
  defp should_show_schedule?([], _), do: false
  defp should_show_schedule?(_occurrences, _is_movie), do: true

  # Determine which type of schedule display to use
  defp schedule_display_type(is_movie_screening, occurrence_list) do
    cond do
      # Movie screenings with multiple occurrences
      is_movie_screening && length(occurrence_list) > 1 ->
        :movie_screening

      # Single occurrence - traditional date/time
      length(occurrence_list) == 1 ->
        :single_datetime

      # Multiple dates but not a movie - could be conference, festival, etc.
      length(occurrence_list) > 1 ->
        :multi_day_schedule

      # Default - single datetime
      true ->
        :single_datetime
    end
  end

  # Extract schedule information from occurrence list
  defp extract_schedule_info(occurrences) when is_list(occurrences) do
    unique_dates =
      occurrences
      |> Enum.map(& &1.date)
      |> Enum.uniq()
      |> Enum.sort()

    date_range =
      if length(unique_dates) > 0 do
        first_date = List.first(unique_dates)
        last_date = List.last(unique_dates)

        if Date.compare(first_date, last_date) == :eq do
          format_date_medium(first_date)
        else
          "#{format_date_medium(first_date)} - #{format_date_medium(last_date)}"
        end
      else
        ""
      end

    formats = extract_formats_from_occurrences(occurrences)

    %{
      date_range: date_range,
      showtime_count: length(occurrences),
      unique_dates: unique_dates,
      formats: formats
    }
  end

  # Extract unique formats from occurrence labels
  defp extract_formats_from_occurrences(occurrences) do
    occurrences
    |> Enum.map(&Map.get(&1, :label))
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

  # Format helpers
  defp format_occurrence_datetime(%{datetime: datetime}) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  defp format_occurrence_datetime(_), do: ""

  defp format_event_datetime(nil), do: ""

  defp format_event_datetime(datetime) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  defp format_date_medium(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end
