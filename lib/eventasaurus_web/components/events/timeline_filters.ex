defmodule EventasaurusWeb.Components.Events.TimelineFilters do
  use EventasaurusWeb, :live_component

  attr :context, :atom, required: true, values: [:user_dashboard, :group_events]
  attr :filters, :map, required: true
  attr :filter_counts, :map, default: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-8 bg-white rounded-lg shadow-sm border p-4" role="region" aria-label="Event filters">
      <div class="flex flex-col sm:flex-row gap-4">
        <!-- Time Period Filter -->
        <fieldset class="flex-1">
          <legend class="sr-only">Time period filter</legend>
          <div class="flex rounded-lg border overflow-hidden" role="group" aria-label="Time period options">
            <button
              phx-click="filter_time"
              phx-value-filter="upcoming"
              phx-target={@myself}
              class={[
                "flex-1 px-4 py-2 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500",
                time_filter_class(@filters.time_filter, :upcoming)
              ]}
              aria-pressed={if @filters.time_filter == :upcoming, do: "true", else: "false"}
              aria-label={filter_button_label(:upcoming, @filter_counts[:upcoming])}
            >
              Upcoming
              <%= if count = @filter_counts[:upcoming] do %>
                <%= if count > 0 do %>
                  <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800" aria-hidden="true">
                    <%= count %>
                  </span>
                <% end %>
              <% end %>
            </button>
            
            <button
              phx-click="filter_time"
              phx-value-filter="past"
              phx-target={@myself}
              class={[
                "flex-1 px-4 py-2 text-sm font-medium transition-colors border-l",
                time_filter_class(@filters.time_filter, :past)
              ]}
            >
              Past
              <%= if count = @filter_counts[:past] do %>
                <%= if count > 0 do %>
                  <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                    <%= count %>
                  </span>
                <% end %>
              <% end %>
            </button>
            
            <!-- Archived filter only for user dashboard -->
            <%= if @context == :user_dashboard do %>
              <button
                phx-click="filter_time"
                phx-value-filter="archived"
                phx-target={@myself}
                class={[
                  "flex-1 px-4 py-2 text-sm font-medium transition-colors border-l",
                  time_filter_class(@filters.time_filter, :archived)
                ]}
              >
                Archived
                <%= if count = @filter_counts[:archived] do %>
                  <%= if count > 0 do %>
                    <span class="ml-2 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                      <%= count %>
                    </span>
                  <% end %>
                <% end %>
              </button>
            <% end %>
          </div>
        </fieldset>

        <!-- Ownership Filter - User Dashboard Only -->
        <%= if @context == :user_dashboard do %>
          <div class="flex-1">
            <label for="ownership-filter" class="sr-only">Ownership filter</label>
            <select 
              id="ownership-filter"
              phx-change="filter_ownership"
              phx-target={@myself}
              name="filter"
              class="w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
              aria-label="Filter events by ownership"
            >
              <option value="all" selected={@filters.ownership_filter == :all}>
                All Events
                <%= if count = @filter_counts[:all] do %>
                  <%= if count > 0, do: " (#{count})" %>
                <% end %>
              </option>
              <option value="created" selected={@filters.ownership_filter == :created}>
                My Events
                <%= if count = @filter_counts[:created] do %>
                  <%= if count > 0, do: " (#{count})" %>
                <% end %>
              </option>
              <option value="participating" selected={@filters.ownership_filter == :participating}>
                Attending
                <%= if count = @filter_counts[:participating] do %>
                  <%= if count > 0, do: " (#{count})" %>
                <% end %>
              </option>
            </select>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("filter_time", %{"filter" => filter}, socket) do
    filter_atom = String.to_existing_atom(filter)
    
    # Send the event to the parent LiveView
    send(self(), {:filter_time, filter_atom})
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_ownership", %{"filter" => filter}, socket) do
    filter_atom = String.to_existing_atom(filter)
    
    # Send the event to the parent LiveView
    send(self(), {:filter_ownership, filter_atom})
    
    {:noreply, socket}
  end

  # Helper functions

  defp time_filter_class(current_filter, target_filter) do
    if current_filter == target_filter do
      "bg-blue-600 text-white"
    else
      "bg-white text-gray-700 hover:bg-gray-50"
    end
  end

  defp filter_button_label(filter_type, count) do
    base_label = case filter_type do
      :upcoming -> "Show upcoming events"
      :past -> "Show past events"
      :archived -> "Show archived events"
    end

    if count && count > 0 do
      "#{base_label} (#{count} available)"
    else
      base_label
    end
  end
end