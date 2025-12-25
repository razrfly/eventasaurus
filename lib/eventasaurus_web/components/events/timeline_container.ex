defmodule EventasaurusWeb.Components.Events.TimelineContainer do
  use EventasaurusWeb, :live_component

  alias EventasaurusWeb.Components.Events.{
    TimelineDateMarker,
    EventCard
  }

  attr :events, :list, required: true
  attr :context, :atom, required: true, values: [:user_dashboard, :group_events, :profile]

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :grouped_events, group_events_by_date(assigns.events))

    ~H"""
    <div role="main" aria-label="Events timeline">
      <!-- Desktop Timeline -->
      <div class="space-y-4 hidden sm:block" role="list" aria-label="Timeline events by date">
        <%= for {date, date_events} <- @grouped_events do %>
          <div class="relative flex items-start space-x-3" role="listitem">
            <!-- Date Section -->
            <.live_component
              module={TimelineDateMarker}
              id={"#{@id}-date-marker-#{date_to_string(date)}"}
              date={date}
              is_last={is_last_date?(date, @grouped_events)}
            />
            
            <!-- Timeline Line and Dot -->
            <div class="flex flex-col items-center">
              <!-- Timeline Dot -->
              <div class="w-4 h-4 bg-blue-600 rounded-full border-2 border-white shadow flex-shrink-0 mt-1.5"></div>
              
              <!-- Timeline Line (except for last item) -->
              <%= unless is_last_date?(date, @grouped_events) do %>
                <div class="w-0.5 bg-gray-300 flex-1 mt-2" style="min-height: 13rem; border-left: 2px dashed #d1d5db; background: none;"></div>
              <% end %>
            </div>
              
            <!-- Events for this date -->
            <div class="flex-1 space-y-3 pb-6">
              <%= for event <- date_events do %>
                <.live_component
                  module={EventCard}
                  id={"#{@id}-desktop-event-card-#{event.id}"}
                  event={event}
                  context={@context}
                  layout={:desktop}
                />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Mobile Version (no timeline visual) -->
      <div class="space-y-4 sm:hidden" role="list" aria-label="Events by date (mobile view)">
        <%= for {date, date_events} <- @grouped_events do %>
          <div role="listitem">
            <!-- Date Header -->
            <div class="mb-2">
              <%= if date == :no_date do %>
                <div class="text-lg font-semibold text-gray-900">Date TBD</div>
              <% else %>
                <div class="text-xl font-semibold text-gray-900">
                  <%= Calendar.strftime(date, "%B %d, %Y") %>
                </div>
                <div class="text-sm text-gray-500">
                  <%= Calendar.strftime(date, "%A") %>
                </div>
              <% end %>
            </div>
            
            <!-- Events for this date -->
            <div class="space-y-2">
              <%= for event <- date_events do %>
                <.live_component
                  module={EventCard}
                  id={"#{@id}-mobile-event-card-#{event.id}"}
                  event={event}
                  context={@context}
                  layout={:mobile}
                />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp group_events_by_date(events) do
    # Group events by date while preserving the order they came in
    # The events are already sorted correctly from the database
    events
    |> Enum.reduce([], fn event, acc ->
      date =
        if event.start_at do
          event.start_at |> DateTime.to_date()
        else
          :no_date
        end

      # Find if we already have this date in our accumulator
      case Enum.find_index(acc, fn {d, _} -> d == date end) do
        nil ->
          # New date, add it to the list
          acc ++ [{date, [event]}]

        index ->
          # Existing date, add event to that date's list
          List.update_at(acc, index, fn {d, events_list} ->
            {d, events_list ++ [event]}
          end)
      end
    end)
  end

  defp is_last_date?(date, grouped_events) do
    case List.last(grouped_events) do
      {last_date, _} -> date == last_date
      _ -> false
    end
  end

  defp date_to_string(:no_date), do: "no-date"
  defp date_to_string(date), do: Date.to_string(date)
end
