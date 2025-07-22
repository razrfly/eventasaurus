defmodule EventasaurusWeb.Components.Events.EventCard do
  use EventasaurusWeb, :live_component
  
  alias EventasaurusWeb.Components.Events.{
    EventCardBadges,
    ParticipantAvatars
  }

  attr :event, :map, required: true
  attr :context, :atom, required: true, values: [:user_dashboard, :group_events]
  attr :layout, :atom, default: :desktop, values: [:desktop, :mobile]

  @impl true
  def render(assigns) do
    ~H"""
    <article class="bg-white rounded-lg border shadow-sm hover:shadow-md transition-shadow" role="article" aria-labelledby={"event-title-#{@event.id}"}>
      <div class={card_padding(@layout)}>
        <!-- Event Header with Image -->
        <div class={card_layout(@layout)}>
          <!-- Left Content -->
          <div class="flex-1">
            <h4 id={"event-title-#{@event.id}"} class={title_size(@layout)}>
              <%= @event.title %>
            </h4>
            
            <!-- Event Description -->
            <%= if @event.description && @event.description != "" do %>
              <p class="text-sm text-gray-600 line-clamp-2 mb-2">
                <%= @event.description %>
              </p>
            <% end %>
            
            <!-- Badges -->
            <div class="flex flex-wrap gap-2 mb-2">
              <.live_component
                module={EventCardBadges}
                id={"badges-#{@layout}-#{@event.id}"}
                event={@event}
                context={@context}
              />
            </div>

            <!-- Event Details -->
            <div class="space-y-1.5 text-sm text-gray-600">
              <!-- Time and Location -->
              <div class="flex gap-4">
                <!-- Time -->
                <div class="flex items-center">
                  <svg class="w-4 h-4 mr-1.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <%= format_time(@event.start_at, @event.timezone) %>
                </div>
                
                <!-- Location -->
                <div class="flex items-center">
                  <svg class="w-4 h-4 mr-1.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                  </svg>
                  <%= if @event.venue do %>
                    <%= @event.venue.name %>
                  <% else %>
                    Virtual Event
                  <% end %>
                </div>
              </div>
              
              <!-- Participants with Avatars -->
              <.live_component
                module={ParticipantAvatars}
                id={"participants-#{@layout}-#{@event.id}"}
                event={@event}
              />
            </div>
          </div>
          
          <!-- Event Image -->
          <div class={image_container_class(@layout)}>
            <%= if @event.cover_image_url do %>
              <img src={@event.cover_image_url} alt={"Cover image for #{@event.title}"} class="w-full h-full object-cover" loading="lazy">
            <% else %>
              <div class="w-full h-full bg-gray-100 flex items-center justify-center" aria-label="No image available">
                <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
                  <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
                </svg>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Actions -->
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between pt-2 border-t border-gray-100 gap-2 sm:gap-0">
          <div class="flex items-center flex-wrap gap-2">
            <%= render_action_button(@event, @context) %>
            
            <!-- Ticket Status -->
            <%= if @event.taxation_type == "ticketed_event" do %>
              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                🎫 Ticketed
              </span>
            <% end %>
          </div>
          
          <!-- Participant Status Update (for non-organizers in user context) -->
          <%= if @context == :user_dashboard && 
                   not Map.get(@event, :can_manage, false) && 
                   Map.get(@event, :user_role) == "participant" do %>
            <div class="flex items-center space-x-2">
              <label for={"status-#{@event.id}"} class="text-sm text-gray-500">Status:</label>
              <select 
                id={"status-#{@event.id}"}
                phx-change="update_participant_status"
                phx-value-event_id={@event.id}
                name="status"
                class="text-sm border-gray-300 rounded-md focus:border-blue-500 focus:ring-blue-500"
                aria-label={"Update your participation status for #{@event.title}"}
              >
                <option value="interested" selected={@event.user_status == :interested}>Interested</option>
                <option value="accepted" selected={@event.user_status == :accepted}>Going</option>
                <option value="declined" selected={@event.user_status == :declined}>Not Going</option>
              </select>
            </div>
          <% end %>
        </div>
      </div>
    </article>
    """
  end

  # Helper functions

  defp card_padding(:desktop), do: "p-3"
  defp card_padding(:mobile), do: "p-4"

  defp card_layout(:desktop), do: "flex flex-col sm:flex-row gap-3"
  defp card_layout(:mobile), do: "flex justify-between items-start mb-3"

  defp title_size(:desktop), do: "text-2xl font-semibold text-gray-900 mb-1"
  defp title_size(:mobile), do: "text-lg font-semibold text-gray-900 mb-2"

  defp image_container_class(:desktop), do: "w-full sm:w-64 h-44 sm:h-44 rounded-lg overflow-hidden flex-shrink-0"
  defp image_container_class(:mobile), do: "w-16 h-16 rounded-lg overflow-hidden flex-shrink-0"

  defp render_action_button(event, context) do
    case {context, Map.get(event, :can_manage, false)} do
      {:user_dashboard, true} ->
        assigns = %{event: event}
        ~H"""
        <a 
          href={~p"/events/#{@event.slug}"}
          class="inline-flex items-center px-3 py-2 border border-transparent text-sm font-medium rounded text-blue-700 bg-blue-100 hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-blue-500"
          aria-label={"Manage #{@event.title}"}
        >
          Manage
        </a>
        """
      
      {_, _} ->
        assigns = %{event: event}
        ~H"""
        <a 
          href={~p"/#{@event.slug}"}
          class="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500"
          aria-label={"View #{@event.title}"}
        >
          View
        </a>
        """
    end
  end

  defp format_time(nil, _timezone), do: "Time TBD"
  defp format_time(datetime, _timezone) do
    # This is a simplified version - in reality you'd want proper timezone handling
    case datetime do
      %DateTime{} -> Calendar.strftime(datetime, "%I:%M %p")
      %NaiveDateTime{} -> Calendar.strftime(datetime, "%I:%M %p")
      _ -> "Time TBD"
    end
  end
end