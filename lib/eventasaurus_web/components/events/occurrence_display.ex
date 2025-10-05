defmodule EventasaurusWeb.Components.Events.OccurrenceDisplay do
  @moduledoc """
  Polymorphic component for displaying event occurrences.

  Routes to appropriate display component based on occurrence type:
  - :daily_show -> ShowtimeSelector (movies with many showtimes)
  - :same_day_multiple -> time selection list
  - :recurring_pattern -> pattern display with upcoming dates
  - :multi_day -> standard date selection
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext
  alias EventasaurusWeb.Components.Events.OccurrenceDisplays.ShowtimeSelector

  attr :event, :map, required: true
  attr :occurrence_list, :list, required: true
  attr :selected_occurrence, :map, default: nil
  attr :selected_showtime_date, Date, default: nil
  attr :is_movie_screening, :boolean, default: false

  def occurrence_display(assigns) do
    ~H"""
    <div class="mb-8 p-6 bg-gray-50 rounded-lg">
      <h3 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
        <Heroicons.calendar_days class="w-5 h-5 mr-2" />
        <%= display_title(assigns) %>
      </h3>

      <%= case occurrence_display_type(@occurrence_list, @is_movie_screening) do %>
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

      <div class="mt-4 p-3 bg-blue-50 rounded-lg">
        <p class="text-sm text-blue-900">
          <span class="font-medium"><%= gettext("Selected:") %></span>
          <%= format_occurrence_datetime(@selected_occurrence || List.first(@occurrence_list)) %>
        </p>
      </div>
    </div>
    """
  end

  defp display_title(assigns) do
    case occurrence_display_type(assigns.occurrence_list, assigns.is_movie_screening) do
      :daily_show -> gettext("Daily Shows Available")
      :same_day_multiple -> gettext("Select a Time")
      :multi_day -> gettext("Multiple Dates Available")
      _ -> gettext("Select Date & Time")
    end
  end

  # Recurring pattern display
  attr :occurrence_list, :list, required: true
  attr :selected, :map, default: nil

  defp recurring_pattern_display(assigns) do
    ~H"""
    <div class="mb-4">
      <%= if List.first(@occurrence_list).pattern do %>
        <div class="mb-4 p-4 bg-green-50 border border-green-200 rounded-lg">
          <div class="flex items-center text-green-800">
            <Heroicons.arrow_path class="w-5 h-5 mr-2 flex-shrink-0" />
            <span class="font-semibold text-lg"><%= List.first(@occurrence_list).pattern %></span>
          </div>
        </div>
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
  defp occurrence_display_type(nil, _), do: :none
  defp occurrence_display_type([], _), do: :none

  defp occurrence_display_type(occurrences, is_movie_screening) do
    cond do
      # Pattern-based recurring events
      is_pattern_occurrence?(occurrences) ->
        :recurring_pattern

      # Movies with many showtimes - use showtime selector
      is_movie_screening && length(occurrences) > 10 ->
        :daily_show

      # More than 20 dates for any event - daily show
      length(occurrences) > 20 ->
        :daily_show

      # All on same day - time selection
      all_same_day?(occurrences) ->
        :same_day_multiple

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

  defp format_occurrence_datetime(nil), do: gettext("Select a date")

  defp format_occurrence_datetime(%{datetime: datetime}) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  defp format_time_only(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
