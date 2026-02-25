defmodule EventasaurusWeb.Components.Events.OccurrenceDisplay do
  @moduledoc """
  Polymorphic component for displaying event occurrences.

  Routes to appropriate display component based on occurrence type:
  - :exhibition -> date range display (no time selection)
  - :daily_show -> ShowtimeSelector (movies with many showtimes)
  - :same_day_multiple -> time selection list
  - :recurring_pattern -> pattern display with upcoming dates
  - :multi_day -> standard date selection
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext
  alias EventasaurusWeb.Components.Events.OccurrenceDisplays.ShowtimeSelector
  alias EventasaurusWeb.Helpers.PublicEventDisplayHelpers
  alias EventasaurusWeb.Utils.TimeUtils

  attr :event, :map, required: true
  attr :occurrence_list, :list, required: true
  attr :selected_occurrence, :map, default: nil
  attr :selected_showtime_date, :any, default: nil
  attr :is_movie_screening, :boolean, default: false

  def occurrence_display(assigns) do
    ~H"""
    <div class="mb-8 p-6 bg-gray-50 rounded-lg">
      <h3 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
        <Heroicons.calendar_days class="w-5 h-5 mr-2" />
        <%= display_title(assigns) %>
      </h3>

      <%= case occurrence_display_type(@occurrence_list, @is_movie_screening, @event) do %>
        <% :exhibition -> %>
          <.exhibition_display event={@event} />

        <% :daily_show -> %>
          <ShowtimeSelector.showtime_selector
            event={@event}
            occurrence_list={@occurrence_list}
            selected_occurrence={@selected_occurrence}
            selected_showtime_date={@selected_showtime_date}
          />

        <% :recurring_pattern -> %>
          <.recurring_pattern_display occurrence_list={@occurrence_list} selected={@selected_occurrence} />

        <% :same_day_multiple -> %>
          <.time_selection_display occurrence_list={@occurrence_list} selected={@selected_occurrence} />

        <% _ -> %>
          <.multi_day_display occurrence_list={@occurrence_list} selected={@selected_occurrence} />
      <% end %>

      <%= unless PublicEventDisplayHelpers.is_exhibition?(@event) do %>
        <div class="mt-4 p-3 bg-blue-50 rounded-lg">
          <p class="text-sm text-blue-900">
            <span class="font-medium"><%= gettext("Selected:") %></span>
            <%= format_occurrence_datetime(@selected_occurrence || List.first(@occurrence_list)) %>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp display_title(assigns) do
    case occurrence_display_type(
           assigns.occurrence_list,
           assigns.is_movie_screening,
           assigns.event
         ) do
      :exhibition -> gettext("Exhibition Dates")
      :daily_show -> gettext("Daily Shows Available")
      :same_day_multiple -> gettext("Select a Time")
      :multi_day -> gettext("Multiple Dates Available")
      _ -> gettext("Select Date & Time")
    end
  end

  # Exhibition display - shows date range without time selection
  attr :event, :map, required: true

  defp exhibition_display(assigns) do
    ~H"""
    <div class="p-4 bg-purple-50 border border-purple-200 rounded-lg">
      <div class="flex items-start">
        <Heroicons.calendar class="w-6 h-6 mr-3 text-purple-600 flex-shrink-0 mt-0.5" />
        <div>
          <p class="text-lg font-semibold text-purple-900 mb-1">
            <%= gettext("Open Exhibition") %>
          </p>
          <p class="text-purple-800">
            <%= PublicEventDisplayHelpers.format_exhibition_datetime(@event) || gettext("Ongoing") %>
          </p>
          <p class="text-sm text-purple-700 mt-2">
            <%= gettext("Visit anytime during exhibition hours") %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Recurring pattern display
  attr :occurrence_list, :list, required: true
  attr :selected, :map, default: nil

  defp recurring_pattern_display(assigns) do
    ~H"""
    <div class="mb-4">
      <%= case List.first(@occurrence_list) do %>
        <% %{pattern: pattern} when not is_nil(pattern) -> %>
          <div class="mb-4 p-4 bg-green-50 border border-green-200 rounded-lg">
            <div class="flex items-center text-green-800">
              <Heroicons.arrow_path class="w-5 h-5 mr-2 flex-shrink-0" />
              <span class="font-semibold text-lg"><%= pattern %></span>
            </div>
          </div>
        <% _ -> %>
      <% end %>

      <p class="text-sm text-gray-600 mb-4">
        <%= gettext("Next %{count} upcoming dates:", count: length(@occurrence_list)) %>
      </p>

      <div class="space-y-2">
        <%= for {occurrence, index} <- Enum.with_index(@occurrence_list) do %>
          <button
            phx-click="select_occurrence"
            phx-value-index={index}
            class={"w-full text-left px-4 py-3 rounded-lg border transition #{if @selected == occurrence, do: "border-green-600 bg-green-50", else: "border-gray-200 hover:bg-gray-50"}"}
          >
            <span class="font-medium"><%= format_occurrence_datetime(occurrence) %></span>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  # Time selection for same-day events
  defp time_selection_display(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= for {occurrence, index} <- Enum.with_index(@occurrence_list) do %>
        <button
          phx-click="select_occurrence"
          phx-value-index={index}
          class={"w-full text-left px-4 py-3 rounded-lg border transition #{if @selected == occurrence, do: "border-blue-600 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
        >
          <span class="font-medium"><%= format_time_only(occurrence.datetime) %></span>
          <%= if occurrence.label do %>
            <span class="ml-2 text-sm text-gray-600"><%= occurrence.label %></span>
          <% end %>
        </button>
      <% end %>
    </div>
    """
  end

  # Multi-day display
  defp multi_day_display(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= for {occurrence, index} <- Enum.with_index(@occurrence_list) do %>
        <button
          phx-click="select_occurrence"
          phx-value-index={index}
          class={"w-full text-left px-4 py-3 rounded-lg border transition #{if @selected == occurrence, do: "border-blue-600 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
        >
          <span class="font-medium"><%= format_occurrence_datetime(occurrence) %></span>
          <%= if occurrence.label do %>
            <span class="ml-2 text-sm text-gray-600"><%= occurrence.label %></span>
          <% end %>
        </button>
      <% end %>
    </div>
    """
  end

  # Determine display type based on occurrences and event type
  defp occurrence_display_type(nil, _, _), do: :none
  defp occurrence_display_type([], _, _), do: :none

  defp occurrence_display_type(occurrences, is_movie_screening, event) do
    cond do
      # Exhibition type - show date range without time selection
      PublicEventDisplayHelpers.is_exhibition?(event) ->
        :exhibition

      # Pattern-based recurring events
      is_pattern_occurrence?(occurrences) ->
        :recurring_pattern

      # All on same day - time selection
      all_same_day?(occurrences) ->
        :same_day_multiple

      # Movies spanning multiple days - use showtime selector
      is_movie_screening && !all_same_day?(occurrences) ->
        :daily_show

      # More than 20 dates for any event - daily show
      length(occurrences) > 20 ->
        :daily_show

      # Default - multi day
      true ->
        :multi_day
    end
  end

  defp is_pattern_occurrence?([first | _rest]) do
    Map.has_key?(first, :pattern)
  end

  defp is_pattern_occurrence?(_), do: false

  defp all_same_day?(occurrences) do
    dates = Enum.map(occurrences, & &1.date) |> Enum.uniq()
    length(dates) == 1
  end

  # Occurrence datetimes are already in local venue time (constructed via
  # DateTime.new(date, time, timezone) from parsed occurrence data).
  # No timezone conversion needed — converting would double-shift.
  defp format_occurrence_datetime(nil), do: gettext("Select a date")

  defp format_occurrence_datetime(%{datetime: datetime}) do
    date_part = Calendar.strftime(datetime, "%A, %B %d, %Y")
    time_part = TimeUtils.format_time(datetime)
    "#{date_part} at #{time_part}"
  end

  defp format_time_only(%DateTime{} = datetime) do
    TimeUtils.format_time(datetime)
  end
end
