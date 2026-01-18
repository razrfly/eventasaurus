defmodule EventasaurusWeb.Components.Events.OccurrenceDisplays.ShowtimeSelector do
  @moduledoc """
  Movie showtime selector component with industry-standard day/time pattern.

  Displays showtimes in a familiar cinema-style interface:
  - Horizontal day tabs (Today, Mon, Tue, etc.)
  - Time buttons grouped by screening format
  - Format and language badges

  Based on patterns from Cinema City, AMC, and other major cinema chains.
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  attr :event, :map, required: true
  attr :occurrence_list, :list, required: true
  attr :selected_occurrence, :map, default: nil
  attr :selected_showtime_date, :any, default: nil

  def showtime_selector(assigns) do
    # Group showtimes by date
    assigns =
      assign(assigns, :showtimes_by_date, group_showtimes_by_date(assigns.occurrence_list))

    # Get list of dates for tabs (limit to next 7 days)
    assigns = assign(assigns, :available_dates, get_available_dates(assigns.showtimes_by_date))
    # Set selected date (default to today or first available)
    assigns = assign(assigns, :selected_date, get_selected_date(assigns))
    # Get the index of the selected occurrence for highlighting
    assigns =
      assign(
        assigns,
        :selected_index,
        selected_occurrence_index(assigns.occurrence_list, assigns.selected_occurrence)
      )

    ~H"""
    <div class="showtime-selector">
      <!-- Summary -->
      <p class="text-sm text-gray-600 mb-4">
        <%= gettext("%{count} shows from %{start} to %{end}",
            count: length(@occurrence_list),
            start: format_date_only(List.first(@occurrence_list).datetime),
            end: format_date_only(List.last(@occurrence_list).datetime)) %>
      </p>

      <!-- Day Tabs -->
      <div class="mb-6 border-b border-gray-200 overflow-x-auto">
        <div class="flex space-x-1 min-w-max">
          <%= for date <- @available_dates do %>
            <.day_tab
              date={date}
              selected={@selected_date == date}
              has_showtimes={Map.has_key?(@showtimes_by_date, date)}
              count={count_showtimes_for_date(@showtimes_by_date, date)}
            />
          <% end %>
        </div>
      </div>

      <!-- Venue Info (if available) -->
      <%= if @event.venue do %>
        <div class="mb-4 text-sm text-gray-700">
          <div class="font-semibold"><%= @event.venue.name %></div>
          <%= if @event.venue.address do %>
            <div class="text-gray-600"><%= @event.venue.address %></div>
          <% end %>
        </div>
      <% end %>

      <!-- Showtimes for Selected Date -->
      <div class="space-y-6">
        <%= if @selected_date && Map.has_key?(@showtimes_by_date, @selected_date) do %>
          <%  showtimes = Map.get(@showtimes_by_date, @selected_date) %>
          <%= render_showtimes_by_format(assigns, showtimes) %>
        <% else %>
          <div class="text-center py-8 text-gray-500">
            <%= gettext("No showtimes available for this date") %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Day tab component
  attr :date, Date, required: true
  attr :selected, :boolean, default: false
  attr :has_showtimes, :boolean, default: true
  attr :count, :integer, default: 0

  defp day_tab(assigns) do
    ~H"""
    <button
      phx-click="select_showtime_date"
      phx-value-date={Date.to_iso8601(@date)}
      disabled={!@has_showtimes}
      class={[
        "flex-shrink-0 flex flex-col items-center px-4 py-3 border-b-2 font-medium text-sm transition-colors whitespace-nowrap min-w-[70px]",
        if(@selected,
          do: "border-blue-600 text-blue-600",
          else: "border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300"
        ),
        if(!@has_showtimes, do: "opacity-50 cursor-not-allowed")
      ]}
    >
      <span><%= day_label(@date) %></span>
      <span class={[
        "text-xs mt-0.5",
        if(@selected, do: "text-blue-500", else: "text-gray-400")
      ]}>
        <%= @count %> <%= if(@count == 1, do: gettext("show"), else: gettext("shows")) %>
      </span>
    </button>
    """
  end

  # Render showtimes grouped by format
  defp render_showtimes_by_format(assigns, showtimes) do
    formats = group_showtimes_by_format(showtimes)

    assigns = assign(assigns, :formats, formats)

    ~H"""
    <%= for {format, format_showtimes} <- @formats do %>
      <div class="showtime-format-group">
        <!-- Format Header -->
        <div class="mb-3">
          <h4 class="font-semibold text-gray-900 mb-1">
            <%= format_display_name(format) %>
          </h4>
          <%= if format_language = get_format_language(format_showtimes) do %>
            <p class="text-xs text-gray-600">(<%= format_language %>)</p>
          <% end %>
        </div>

        <!-- Time Buttons -->
        <div class="flex flex-wrap gap-2">
          <%= for {showtime, _index} <- Enum.with_index(format_showtimes) do %>
            <.showtime_button
              showtime={showtime}
              index={showtime.index}
              selected={not is_nil(@selected_index) and @selected_index == showtime.index}
            />
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  # Individual showtime button
  attr :showtime, :map, required: true
  attr :index, :integer, required: true
  attr :selected, :boolean, default: false

  defp showtime_button(assigns) do
    # Check if showtime is in the past
    assigns = assign(assigns, :is_past, is_past_showtime?(assigns.showtime))

    ~H"""
    <button
      phx-click="select_occurrence"
      phx-value-index={@index}
      disabled={@is_past}
      class={[
        "px-4 py-2 rounded-lg font-medium text-sm transition-all",
        if(@selected,
          do: "bg-blue-600 text-white shadow-md",
          else: "bg-white border border-gray-300 text-gray-700 hover:bg-gray-50 hover:border-gray-400"
        ),
        if(@is_past, do: "opacity-40 cursor-not-allowed line-through")
      ]}
    >
      <%= format_showtime(@showtime.datetime) %>
    </button>
    """
  end

  # Helper Functions

  defp group_showtimes_by_date(occurrences) do
    occurrences
    |> Enum.with_index()
    |> Enum.group_by(
      fn {occurrence, _index} -> occurrence.date end,
      fn {occurrence, index} -> Map.put(occurrence, :index, index) end
    )
  end

  # Count showtimes for a specific date
  defp count_showtimes_for_date(showtimes_by_date, date) do
    case Map.get(showtimes_by_date, date) do
      nil -> 0
      showtimes -> length(showtimes)
    end
  end

  defp get_available_dates(showtimes_by_date) do
    today = Date.utc_today()

    # Get dates from showtimes, limit to next 7 days
    showtimes_by_date
    |> Map.keys()
    |> Enum.filter(fn date ->
      Date.compare(date, today) != :lt &&
        Date.diff(date, today) < 7
    end)
    |> Enum.sort_by(& &1, Date)
    |> Enum.take(7)
    |> case do
      [] ->
        # If no dates in next 7 days, show all available dates up to 14 days
        showtimes_by_date
        |> Map.keys()
        |> Enum.filter(fn date -> Date.diff(date, today) < 14 end)
        |> Enum.sort_by(& &1, Date)
        |> Enum.take(7)

      dates ->
        dates
    end
  end

  # Priority: explicit showtime date selection > selected occurrence date > first available > today
  defp get_selected_date(%{selected_showtime_date: date}) when not is_nil(date), do: date

  defp get_selected_date(%{selected_occurrence: %{date: date}}), do: date

  defp get_selected_date(%{available_dates: [first | _]}), do: first

  defp get_selected_date(_), do: Date.utc_today()

  defp group_showtimes_by_format(showtimes) do
    showtimes
    |> Enum.group_by(fn showtime ->
      # Get format from metadata or label
      get_showtime_format(showtime)
    end)
    |> Enum.sort_by(fn {format, _} -> format_priority(format) end)
  end

  defp get_showtime_format(%{label: label}) when is_binary(label) do
    cond do
      String.contains?(String.downcase(label), ["vip", "premium"]) -> :vip
      String.contains?(String.downcase(label), ["imax"]) -> :imax
      String.contains?(String.downcase(label), ["3d"]) -> :"3d"
      String.contains?(String.downcase(label), ["4dx"]) -> :"4dx"
      true -> :"2d"
    end
  end

  defp get_showtime_format(_), do: :"2d"

  defp format_priority(:imax), do: 1
  defp format_priority(:"4dx"), do: 2
  defp format_priority(:"3d"), do: 3
  defp format_priority(:vip), do: 4
  defp format_priority(:"2d"), do: 5
  defp format_priority(_), do: 99

  defp format_display_name(:imax), do: "IMAX"
  defp format_display_name(:"3d"), do: "3D"
  defp format_display_name(:"4dx"), do: "4DX"
  defp format_display_name(:vip), do: "VIP 2D"
  defp format_display_name(:"2d"), do: "2D"
  defp format_display_name(other), do: String.upcase(to_string(other))

  defp get_format_language(showtimes) do
    # Extract language info from first showtime's label
    case List.first(showtimes) do
      %{label: label} when is_binary(label) ->
        cond do
          String.contains?(String.downcase(label), ["dubbed", "pl", "polish"]) ->
            gettext("DUBBED FILM PL")

          String.contains?(String.downcase(label), ["subtitled", "napisy"]) ->
            gettext("SUBTITLED")

          String.contains?(String.downcase(label), ["original", "oryginał"]) ->
            gettext("ORIGINAL VERSION")

          true ->
            nil
        end

      _ ->
        nil
    end
  end

  defp day_label(date) do
    today = Date.utc_today()

    case Date.diff(date, today) do
      0 -> gettext("Today")
      1 -> gettext("Tomorrow")
      _ -> Calendar.strftime(date, "%a %d")
    end
  end

  defp format_showtime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp format_date_only(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp is_past_showtime?(%{datetime: datetime}) do
    DateTime.compare(datetime, DateTime.utc_now()) == :lt
  end

  defp selected_occurrence_index(list, selected) when is_list(list) and is_map(selected) do
    Enum.find_index(list, &(&1 == selected))
  end

  defp selected_occurrence_index(_list, _selected), do: nil
end
