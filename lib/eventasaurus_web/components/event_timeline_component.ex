defmodule EventasaurusWeb.EventTimelineComponent do
  use EventasaurusWeb, :html

  alias EventasaurusWeb.Components.Events.{
    TimelineFilters,
    TimelineContainer,
    TimelineEmptyState
  }

  @doc """
  Renders a reusable event timeline component that displays events in a rich timeline format.

  Supports three contexts:
  - `:user_dashboard` - Shows user's events with role badges, filters, and management actions
  - `:group_events` - Shows group events with simplified display and group-specific actions
  - `:profile` - Shows profile events with past-tense badges (Hosted/Attended) and no filters

  ## Examples

      <.event_timeline 
        events={@events}
        current_user={@user}
        context={:user_dashboard}
        filters=%{time_filter: @time_filter, ownership_filter: @ownership_filter}
        filter_counts={@filter_counts}
        loading={@loading}
        actions=%{
          filter_time: {__MODULE__, :handle_event, ["filter_time"]},
          filter_ownership: {__MODULE__, :handle_event, ["filter_ownership"]}
        }
      />
      
      <.event_timeline
        events={@events}
        current_user={@user}
        context={:group_events}
        empty_state_config=%{
          title: "No events yet",
          description: "Get started by creating a new event for this group.",
          show_create_button: true,
          create_button_text: "Create Event",
          create_button_url: "/events/new"
        }
      />
  """
  attr :events, :list, required: true, doc: "List of event structs to display"

  attr :context, :atom,
    required: true,
    values: [:user_dashboard, :group_events, :profile],
    doc: "Usage context"

  attr :loading, :boolean, default: false, doc: "Loading state"
  attr :filters, :map, default: %{}, doc: "Current filter states"
  attr :filter_counts, :map, default: %{}, doc: "Filter option counts for badges"
  attr :config, :map, default: %{}, doc: "Component configuration"

  def event_timeline(assigns) do
    assigns =
      assigns
      |> assign_new(:filters, fn -> %{} end)
      |> assign_new(:filter_counts, fn -> %{} end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:config, fn -> %{} end)

    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-3 sm:px-6 lg:px-8">
      <!-- Header - Only show for user dashboard -->
      <%= if @context == :user_dashboard do %>
        <div class="mb-6">
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-3xl font-bold text-gray-900">
                <%= Map.get(@config, :title, "Events") %>
              </h1>
              <p class="mt-1 text-sm text-gray-500">
                <%= Map.get(@config, :subtitle, "Your events timeline") %>
              </p>
            </div>
            
            <!-- Create Event Button - Context Dependent -->
            <%= if Map.get(@config, :show_create_button, false) do %>
              <div class="flex items-center">
                <a 
                  href={Map.get(@config, :create_button_url, "/events/new")} 
                  class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                  </svg>
                  <%= Map.get(@config, :create_button_text, "Create Event") %>
                </a>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Filters with integrated Create Button for group events -->
      <%= if (@context == :user_dashboard or @context == :group_events) and not Enum.empty?(@filters) do %>
        <.live_component 
          module={TimelineFilters}
          id="timeline-filters"
          context={@context}
          filters={@filters}
          filter_counts={@filter_counts}
          config={@config}
        />
      <% end %>

      <!-- Loading State -->
      <%= if @loading do %>
        <div class="flex justify-center items-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
          <span class="ml-4 text-gray-600">Loading events...</span>
        </div>
      <% end %>

      <!-- Events Timeline -->
      <%= if not @loading do %>
        <%= if Enum.empty?(@events) do %>
          <.live_component
            module={TimelineEmptyState}
            id="timeline-empty-state"
            context={@context}
            config={@config}
            filters={@filters}
          />
        <% else %>
          <.live_component
            module={TimelineContainer}
            id="timeline-container"
            events={@events}
            context={@context}
          />
        <% end %>
      <% end %>
    </div>
    """
  end
end
