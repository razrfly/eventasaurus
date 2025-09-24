defmodule EventasaurusWeb.Components.Events.TimelineFilters do
  use EventasaurusWeb, :live_component

  attr :context, :atom, required: true, values: [:user_dashboard, :group_events]
  attr :filters, :map, required: true
  attr :filter_counts, :map, default: %{}
  attr :config, :map, default: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-3" role="region" aria-label="Event filters">
      <div class="flex items-center justify-between">
        <!-- Time Period Filter -->
        <div class="flex items-center gap-0" role="group" aria-label="Time period options">
          <button
            phx-click="filter_time"
            phx-value-filter="upcoming"
            phx-target={@myself}
            class={[
              "px-3 py-1 text-sm font-medium transition-colors focus:outline-none rounded-l border-r border-gray-200",
              if(@filters.time_filter == :upcoming, do: "bg-gray-900 text-white", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-50")
            ]}
            aria-pressed={if @filters.time_filter == :upcoming, do: "true", else: "false"}
            aria-label={filter_button_label(:upcoming, @filter_counts[:upcoming])}
          >
            Upcoming
            <%= if count = @filter_counts[:upcoming] do %>
              <%= if count > 0 do %>
                <span class="ml-1 text-xs opacity-75">
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
              "px-3 py-1 text-sm font-medium transition-colors focus:outline-none rounded-r",
              if(@filters.time_filter == :past, do: "bg-gray-900 text-white", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-50")
            ]}
          >
            Past
            <%= if count = @filter_counts[:past] do %>
              <%= if count > 0 do %>
                <span class="ml-1 text-xs opacity-75">
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
                "px-3 py-1 text-sm font-medium transition-colors focus:outline-none border-l border-gray-200",
                if(@filters.time_filter == :archived, do: "bg-gray-900 text-white", else: "text-gray-600 hover:text-gray-900 hover:bg-gray-50")
              ]}
            >
              Archived
              <%= if count = @filter_counts[:archived] do %>
                <%= if count > 0 do %>
                  <span class="ml-1 text-xs opacity-75">
                    <%= count %>
                  </span>
                <% end %>
              <% end %>
            </button>
          <% end %>
        </div>

        <!-- Ownership Filter - User Dashboard Only -->
        <%= if @context == :user_dashboard do %>
          <div class="ml-auto" id={"ownership-filter-container-#{@id}"}>
            <.form 
              for={%{}} 
              as={:ownership_filter}
              phx-change="filter_ownership" 
              phx-target={@myself}
              class="inline-block"
            >
              <label for={"ownership-filter-#{@id}"} class="sr-only">Ownership filter</label>
              <select 
                id={"ownership-filter-#{@id}"}
                name="filter"
                value={@filters.ownership_filter}
                class="w-auto rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
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
            </.form>
          </div>
        <% end %>
        
        <!-- Create Event Button - Group Events Only -->
        <%= if @context == :group_events and Map.get(@config, :show_create_button, false) do %>
          <a 
            href={Map.get(@config, :create_button_url, "/events/new")} 
            class="inline-flex items-center px-3 py-1 text-sm font-medium text-blue-600 hover:text-blue-700 focus:outline-none"
          >
            <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
            </svg>
            <%= Map.get(@config, :create_button_text, "Create Event") %>
          </a>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("filter_time", %{"filter" => filter}, socket) do
    filter_atom = safe_to_atom(filter, [:upcoming, :past, :archived])
    send(self(), {:filter_time, filter_atom})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_ownership", %{"filter" => filter}, socket) do
    filter_atom = safe_to_atom(filter, [:all, :created, :participating])
    send(self(), {:filter_ownership, filter_atom})
    {:noreply, socket}
  end

  # Helper functions

  defp safe_to_atom(value, allowed_atoms) do
    atom = String.to_existing_atom(value)
    if atom in allowed_atoms, do: atom, else: hd(allowed_atoms)
  rescue
    ArgumentError -> hd(allowed_atoms)
  end

  defp filter_button_label(filter_type, count) do
    base_label =
      case filter_type do
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
