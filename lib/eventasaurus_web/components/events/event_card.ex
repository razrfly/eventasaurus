defmodule EventasaurusWeb.Components.Events.EventCard do
  use EventasaurusWeb, :live_component

  alias EventasaurusWeb.Components.Events.{
    EventCardBadges,
    ParticipantAvatars
  }

  alias EventasaurusApp.DateTimeHelper
  alias EventasaurusWeb.Helpers.PublicEventDisplayHelpers
  import EventasaurusWeb.Helpers.LanguageHelpers

  attr :event, :map, required: true
  attr :context, :atom, required: true, values: [:user_dashboard, :group_events, :profile]
  attr :layout, :atom, default: :desktop, values: [:desktop, :mobile, :compact]
  attr :language, :string, default: "en"

  @impl true
  def render(assigns) do
    # Generate a unique ID based on the component's ID (which includes layout prefix)
    unique_id = assigns.id || "#{assigns.layout}-event-#{assigns.event.id}"
    assigns = assign(assigns, :unique_id, unique_id)

    ~H"""
    <article class="bg-white rounded-lg border shadow-sm hover:shadow-md transition-shadow" role="article" aria-labelledby={"event-title-#{@unique_id}"}>
      <a href={~p"/#{@event.slug}"} class="block" aria-label={"View #{get_event_title(@event, @language || "en")}"}>
        <div class={card_padding(@layout)}>
          <!-- Event Header with Image -->
          <div class={card_layout(@layout)}>
            <!-- Left Content -->
            <div class="flex-1">
              <h4 id={"event-title-#{@unique_id}"} class={title_size(@layout)}>
                <%= get_event_title(@event, @language || "en") %>
              </h4>

              <!-- Event Description -->
              <% description = get_event_description(@event, @language || "en") %>
              <%= if description && description != "" do %>
                <p class="text-sm text-gray-600 line-clamp-2 mb-2">
                  <%= description %>
                </p>
              <% end %>
              
              <!-- Badges -->
              <div class="flex flex-wrap gap-2 mb-2">
                <.live_component
                  module={EventCardBadges}
                  id={"badges-#{@unique_id}"}
                  event={@event}
                  context={@context}
                />
              </div>

              <!-- Event Details -->
              <div class="space-y-1.5 text-sm text-gray-600">
                <!-- Time and Location -->
                <div class="flex gap-4">
                  <!-- Time or Exhibition Date Range -->
                  <div class="flex items-center">
                    <svg class="w-4 h-4 mr-1.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <%= format_event_datetime(@event) %>
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
                  id={"participants-#{@unique_id}"}
                  event={@event}
                />
              </div>
            </div>
            
            <!-- Event Image -->
            <!-- PHASE 2 TODO: Remove resolve() wrapper after database migration normalizes URLs -->
            <div class={image_container_class(@layout)}>
              <%= if @event.cover_image_url do %>
                <img src={resolve(@event.cover_image_url)} alt={"Cover image for #{@event.title}"} class="w-full h-full object-cover" loading="lazy" referrerpolicy="no-referrer">
              <% else %>
                <div class="w-full h-full bg-gray-100 flex items-center justify-center" aria-label="No image available">
                  <svg class="w-12 h-12 text-gray-400" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
                    <path fill-rule="evenodd" d="M4 3a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V5a2 2 0 00-2-2H4zm12 12H4l4-8 3 6 2-4 3 6z" clip-rule="evenodd" />
                  </svg>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </a>

      <!-- Actions (hidden for compact layout) -->
      <div class={[action_padding(@layout), "flex flex-col sm:flex-row sm:items-center sm:justify-between border-t border-gray-100 gap-2 sm:gap-0", @layout == :compact && "hidden"]}>
          <div class="flex items-center flex-wrap gap-2">
            <%= render_action_button(@event) %>
          </div>
          
          <!-- Participant Status Update (for non-organizers in user context) -->
          <%= if @context == :user_dashboard && 
                   not Map.get(@event, :can_manage, false) && 
                   Map.get(@event, :user_role) == "participant" do %>
            <div class="flex items-center space-x-2">
              <label for={"status-select-#{@unique_id}"} class="text-sm text-gray-500">Status:</label>
              <select 
                id={"status-select-#{@unique_id}"}
                phx-change="update_participant_status"
                phx-target={@myself}
                phx-value-event_id={@event.id}
                name="status"
                class="text-sm border-gray-300 rounded-md focus:border-blue-500 focus:ring-blue-500 relative z-10"
                aria-label={"Update your participation status for #{@event.title}"}
                onclick="event.stopPropagation()"
              >
                <option value="interested" selected={@event.user_status == :interested}>Interested</option>
                <option value="accepted" selected={@event.user_status == :accepted}>Going</option>
                <option value="declined" selected={@event.user_status == :declined}>Not Going</option>
              </select>
            </div>
          <% end %>
      </div>
    </article>
    """
  end

  # Helper functions

  defp card_padding(:desktop), do: "p-3"
  defp card_padding(:mobile), do: "p-4"
  defp card_padding(:compact), do: "p-4"

  defp action_padding(:desktop), do: "pt-2 px-3 pb-3"
  defp action_padding(:mobile), do: "pt-2 px-4 pb-3"
  defp action_padding(:compact), do: "pt-2 px-4 pb-3"

  defp card_layout(:desktop), do: "flex flex-col sm:flex-row gap-3"
  defp card_layout(:mobile), do: "flex justify-between items-start mb-3"
  defp card_layout(:compact), do: "flex items-start gap-4"

  defp title_size(:desktop), do: "text-2xl font-semibold text-gray-900 mb-1"
  defp title_size(:mobile), do: "text-lg font-semibold text-gray-900 mb-2"

  defp title_size(:compact),
    do: "text-base font-semibold text-gray-900 group-hover:text-blue-600 transition-colors"

  defp image_container_class(:desktop),
    do: "w-full sm:w-64 h-44 sm:h-44 rounded-lg overflow-hidden flex-shrink-0"

  defp image_container_class(:mobile), do: "w-16 h-16 rounded-lg overflow-hidden flex-shrink-0"
  defp image_container_class(:compact), do: "w-16 h-16 rounded-lg overflow-hidden flex-shrink-0"

  defp render_action_button(event) do
    can_manage = Map.get(event, :can_manage, false)
    assigns = %{event: event, can_manage: can_manage}

    ~H"""
    <%= if @can_manage do %>
      <a 
        href={~p"/events/#{@event.slug}"}
        class="inline-flex items-center px-3 py-2 border border-transparent text-sm font-medium rounded text-blue-700 bg-blue-100 hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-blue-500 relative z-10"
        aria-label={"Manage #{@event.title}"}
        onclick="event.stopPropagation()"
      >
        Manage
      </a>
    <% end %>

    <a 
      href={~p"/#{@event.slug}"}
      class="inline-flex items-center px-3 py-2 border border-gray-300 text-sm font-medium rounded text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 relative z-10"
      aria-label={"View #{@event.title}"}
      onclick="event.stopPropagation()"
    >
      View
    </a>
    """
  end

  # Format event datetime - exhibitions show date range, others show time
  defp format_event_datetime(event) do
    cond do
      # Exhibition type - show date range
      PublicEventDisplayHelpers.is_exhibition?(event) ->
        PublicEventDisplayHelpers.format_exhibition_datetime(event) || "Exhibition"

      # Regular events - show time
      event.start_at ->
        format_time(event.start_at, event.timezone)

      # Fallback
      true ->
        "Time TBD"
    end
  end

  defp format_time(nil, _timezone), do: "Time TBD"

  defp format_time(%DateTime{} = datetime, timezone) do
    timezone = timezone || "UTC"
    converted_dt = DateTimeHelper.utc_to_timezone(datetime, timezone)

    Calendar.strftime(converted_dt, "%I:%M %p")
    |> String.replace(" 0", " ")
  end

  defp format_time(%NaiveDateTime{} = datetime, _timezone) do
    # NaiveDateTime doesn't have timezone info, format as-is
    Calendar.strftime(datetime, "%I:%M %p")
    |> String.replace(" 0", " ")
  end

  defp format_time(_, _), do: "Time TBD"

  @impl true
  def handle_event(
        "update_participant_status",
        %{"event_id" => event_id, "status" => status},
        socket
      ) do
    # Forward the event to the parent LiveView
    send(self(), {:update_participant_status, %{"event_id" => event_id, "status" => status}})
    {:noreply, socket}
  end
end
