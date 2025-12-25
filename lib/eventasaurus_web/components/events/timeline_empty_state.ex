defmodule EventasaurusWeb.Components.Events.TimelineEmptyState do
  use EventasaurusWeb, :live_component

  attr :context, :atom, required: true, values: [:user_dashboard, :group_events, :profile]
  attr :config, :map, default: %{}
  attr :filters, :map, default: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-center py-16">
      <svg class="mx-auto h-16 w-16 text-gray-400 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
      </svg>
      
      <h3 class="text-xl font-medium text-gray-900 mb-2">
        <%= empty_state_title(@context, @filters) %>
      </h3>
      
      <p class="text-gray-500 mb-6">
        <%= empty_state_description(@context, @filters, @config) %>
      </p>
      
      <%= if show_create_button?(@context, @config) do %>
        <a 
          href={Map.get(@config, :create_button_url, default_create_url(@context))} 
          class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
        >
          <%= Map.get(@config, :create_button_text, default_create_text(@context)) %>
        </a>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp empty_state_title(:user_dashboard, filters) do
    case {Map.get(filters || %{}, :time_filter), Map.get(filters || %{}, :ownership_filter)} do
      {:upcoming, :all} -> "No upcoming events"
      {:past, :all} -> "No past events"
      {:archived, _} -> "No archived events"
      {:upcoming, :created} -> "No upcoming events you've created"
      {:past, :created} -> "No past events you've created"
      {:upcoming, :participating} -> "No upcoming events you're attending"
      {:past, :participating} -> "No past events you attended"
      _ -> "No events found"
    end
  end

  defp empty_state_title(:group_events, _filters) do
    "No events yet"
  end

  defp empty_state_title(:profile, _filters) do
    "No events to display"
  end

  defp empty_state_description(:user_dashboard, filters, config) do
    ownership_filter = Map.get(filters || %{}, :ownership_filter, :all)

    cond do
      ownership_filter == :all ->
        "Get started by creating your first event or joining an existing one."

      Map.get(config, :description) ->
        Map.get(config, :description)

      true ->
        "Try adjusting your filters to see more events."
    end
  end

  defp empty_state_description(:group_events, _filters, config) do
    Map.get(config, :description, "Get started by creating a new event for this group.")
  end

  defp empty_state_description(:profile, _filters, config) do
    Map.get(config, :description, "This user hasn't participated in any public events yet.")
  end

  defp show_create_button?(:user_dashboard, _config), do: true
  defp show_create_button?(:group_events, config), do: Map.get(config, :show_create_button, false)
  defp show_create_button?(:profile, config), do: Map.get(config, :show_create_button, false)

  defp default_create_url(:user_dashboard), do: "/events/new"
  defp default_create_url(:group_events), do: "/events/new"

  defp default_create_text(:user_dashboard), do: "Create Your First Event"
  defp default_create_text(:group_events), do: "Create Event"
end
