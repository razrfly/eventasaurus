defmodule EventasaurusWeb.PeopleLive.Index do
  @moduledoc """
  People Discovery LiveView.

  Helps users find and connect with people they've met at events.
  Implements three discovery tabs:

  - "You Know" - People you're already connected with
  - "At Your Events" - People from events you've attended
  - "You Might Know" - Friends of friends (extended network)

  Privacy-first design: respects user privacy preferences and only shows
  people who have opted into being discoverable.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Discovery
  alias EventasaurusApp.Relationships
  alias EventasaurusWeb.RelationshipButtonComponent

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns[:user] do
      nil ->
        {:ok,
         socket
         |> assign(:loading, false)
         |> assign(:active_tab, :you_know)
         |> assign(:people, [])
         |> assign(:upcoming_people, [])
         |> assign(:past_people, [])
         |> assign(:people_cache, %{})
         |> assign(:auth_error, true)}

      user ->
        socket =
          if connected?(socket) do
            start_async_loading(socket, user)
          else
            socket
            |> assign(:loading_tasks, %{})
          end

        {:ok,
         socket
         |> assign(:loading, true)
         |> assign(:active_tab, :you_know)
         |> assign(:people, [])
         |> assign(:upcoming_people, [])
         |> assign(:past_people, [])
         |> assign(:people_cache, %{})
         |> assign(:auth_error, false)
         |> load_people()}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = parse_tab(Map.get(params, "tab", "you_know"))

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> load_people()}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    tab_atom = parse_tab(tab)

    {:noreply,
     socket
     |> assign(:active_tab, tab_atom)
     |> push_patch(to: build_path(tab_atom))}
  end

  @impl true
  def handle_info({:connection_request_sent, _user}, socket) do
    # Show flash message when a connection request is sent
    {:noreply, put_flash(socket, :info, "Connection request sent!")}
  end

  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    loading_tasks = socket.assigns[:loading_tasks] || %{}

    # Find which task completed
    {task_type, updated_tasks} =
      cond do
        loading_tasks[:you_know] && loading_tasks[:you_know].ref == ref ->
          {:you_know, Map.delete(loading_tasks, :you_know)}

        loading_tasks[:at_your_events] && loading_tasks[:at_your_events].ref == ref ->
          {:at_your_events, Map.delete(loading_tasks, :at_your_events)}

        loading_tasks[:you_might_know] && loading_tasks[:you_might_know].ref == ref ->
          {:you_might_know, Map.delete(loading_tasks, :you_might_know)}

        true ->
          {nil, loading_tasks}
      end

    socket =
      if task_type do
        people_cache = Map.put(socket.assigns.people_cache, task_type, result)

        # If this is the current tab, update the displayed people
        socket =
          if socket.assigns.active_tab == task_type do
            case {task_type, result} do
              {:at_your_events, {upcoming, past}} ->
                # For at_your_events, result is a tuple of {upcoming, past}
                socket
                |> assign(:upcoming_people, upcoming)
                |> assign(:past_people, past)
                |> assign(:people, upcoming ++ past)

              _ ->
                assign(socket, :people, result)
            end
          else
            socket
          end

        socket
        |> assign(:people_cache, people_cache)
        |> assign(:loading_tasks, updated_tasks)
        |> assign(:loading, map_size(updated_tasks) > 0)
      else
        socket
      end

    Process.demonitor(ref, [:flush])

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <header class="mb-6">
        <h1 class="text-3xl font-bold text-gray-900">People</h1>
        <p class="mt-2 text-gray-600">
          Discover and connect with people from your events
        </p>
      </header>

      <!-- Section Navigation -->
      <nav class="mb-6 flex gap-4 border-b border-gray-200 pb-4">
        <.link
          navigate={~p"/people/discover"}
          class="inline-flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-sm bg-indigo-100 text-indigo-700"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          Discover
        </.link>
        <.link
          navigate={~p"/people/introductions"}
          class="inline-flex items-center gap-2 px-4 py-2 rounded-lg font-medium text-sm text-gray-600 hover:bg-gray-100"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
          Introductions
        </.link>
      </nav>

      <%= if @auth_error do %>
        <div class="rounded-lg bg-red-50 p-4">
          <p class="text-red-800">Please sign in to discover people.</p>
        </div>
      <% else %>
        <!-- Tab Navigation -->
        <nav class="mb-6 border-b border-gray-200">
          <div class="flex space-x-8">
            <.tab_button
              tab={:you_know}
              active_tab={@active_tab}
              label="You Know"
              icon="users"
            />
            <.tab_button
              tab={:at_your_events}
              active_tab={@active_tab}
              label="At Your Events"
              icon="calendar"
            />
            <.tab_button
              tab={:you_might_know}
              active_tab={@active_tab}
              label="You Might Know"
              icon="user-plus"
            />
          </div>
        </nav>

        <!-- Content -->
        <div class="min-h-[400px]">
          <%= if @loading do %>
            <.loading_state />
          <% else %>
            <%= if Enum.empty?(@people) do %>
              <.empty_state tab={@active_tab} />
            <% else %>
              <%= if @active_tab == :at_your_events do %>
                <!-- At Your Events: Show Upcoming and Past sections -->
                <.at_your_events_content
                  upcoming_people={@upcoming_people}
                  past_people={@past_people}
                  current_user={@user}
                />
              <% else %>
                <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  <%= for person <- @people do %>
                    <.person_card person={person} tab={@active_tab} current_user={@user} />
                  <% end %>
                </div>
              <% end %>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # =============================================================================
  # Components
  # =============================================================================

  attr :tab, :atom, required: true
  attr :active_tab, :atom, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp tab_button(assigns) do
    active? = assigns.active_tab == assigns.tab
    assigns = assign(assigns, :active?, active?)

    ~H"""
    <button
      phx-click="change_tab"
      phx-value-tab={@tab}
      class={[
        "flex items-center gap-2 py-4 px-1 border-b-2 font-medium text-sm transition-colors",
        if(@active?, do: "border-indigo-600 text-indigo-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")
      ]}
    >
      <.tab_icon icon={@icon} />
      <%= @label %>
    </button>
    """
  end

  attr :icon, :string, required: true

  defp tab_icon(%{icon: "users"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>
    """
  end

  defp tab_icon(%{icon: "calendar"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
    </svg>
    """
  end

  defp tab_icon(%{icon: "user-plus"} = assigns) do
    ~H"""
    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
    </svg>
    """
  end

  defp tab_icon(assigns), do: ~H""

  attr :upcoming_people, :list, required: true
  attr :past_people, :list, required: true
  attr :current_user, :map, required: true

  defp at_your_events_content(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= if Enum.any?(@upcoming_people) do %>
        <!-- Upcoming Events Section -->
        <div>
          <div class="flex items-center gap-2 mb-4">
            <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
            <h3 class="text-lg font-semibold text-gray-900">Upcoming Events</h3>
            <span class="bg-green-100 text-green-800 text-xs font-medium px-2 py-0.5 rounded">
              <%= length(@upcoming_people) %> people
            </span>
          </div>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <%= for person <- @upcoming_people do %>
              <.person_card person={person} tab={:at_your_events} current_user={@current_user} />
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if Enum.any?(@past_people) do %>
        <!-- Past Events Section -->
        <div>
          <div class="flex items-center gap-2 mb-4">
            <svg class="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <h3 class="text-lg font-semibold text-gray-900">Past Events</h3>
            <span class="bg-gray-100 text-gray-600 text-xs font-medium px-2 py-0.5 rounded">
              <%= length(@past_people) %> people
            </span>
          </div>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <%= for person <- @past_people do %>
              <.person_card person={person} tab={:at_your_events} current_user={@current_user} />
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if Enum.empty?(@upcoming_people) && Enum.empty?(@past_people) do %>
        <.empty_state tab={:at_your_events} />
      <% end %>
    </div>
    """
  end

  attr :person, :map, required: true
  attr :tab, :atom, required: true
  attr :current_user, :map, required: true

  defp person_card(assigns) do
    # Extract user from different result structures
    user = get_user(assigns.person)
    context = get_context(assigns.person, assigns.tab)
    # Get the first shared event for context on the button
    shared_event = get_first_shared_event(assigns.person)
    # For :you_know tab, don't show the button (already connected)
    show_button = assigns.tab != :you_know

    assigns =
      assign(assigns,
        user: user,
        context: context,
        shared_event: shared_event,
        show_button: show_button
      )

    ~H"""
    <div class="bg-white rounded-lg border border-gray-200 p-4 hover:shadow-md transition-shadow">
      <div class="flex items-start gap-4">
        <.link navigate={~p"/users/#{User.username_slug(@user)}"} class="flex-shrink-0">
          <img
            src={generate_avatar_url(@user)}
            alt={@user.name || "User"}
            class="w-12 h-12 rounded-full hover:ring-2 hover:ring-indigo-300 transition-all"
          />
        </.link>
        <div class="flex-1 min-w-0">
          <.link navigate={~p"/users/#{User.username_slug(@user)}"} class="hover:text-indigo-600 transition-colors">
            <h3 class="font-medium text-gray-900 truncate">
              <%= @user.name || "Anonymous" %>
            </h3>
          </.link>
          <p class="text-sm text-gray-500 mt-1">
            <%= @context %>
          </p>
        </div>
      </div>

      <%= if shared_events = get_shared_events(@person) do %>
        <div class="mt-3 pt-3 border-t border-gray-100">
          <p class="text-xs text-gray-500 mb-2">Events in common:</p>
          <div class="flex flex-wrap gap-1">
            <%= for event <- Enum.take(shared_events, 2) do %>
              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-indigo-50 text-indigo-700">
                <%= truncate_event_title(event.title) %>
              </span>
            <% end %>
            <%= if length(shared_events) > 2 do %>
              <span class="text-xs text-gray-400">
                +<%= length(shared_events) - 2 %> more
              </span>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @show_button do %>
        <div class="mt-3 pt-3 border-t border-gray-100">
          <.live_component
            module={RelationshipButtonComponent}
            id={"connect-user-#{@user.id}"}
            other_user={@user}
            current_user={@current_user}
            event={@shared_event}
            size="sm"
            variant="outline"
            class="w-full justify-center"
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp loading_state(assigns) do
    ~H"""
    <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <%= for _i <- 1..6 do %>
        <div class="bg-white rounded-lg border border-gray-200 p-4 animate-pulse">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-full bg-gray-200"></div>
            <div class="flex-1">
              <div class="h-4 bg-gray-200 rounded w-3/4"></div>
              <div class="h-3 bg-gray-200 rounded w-1/2 mt-2"></div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :tab, :atom, required: true

  defp empty_state(assigns) do
    message = empty_message(assigns.tab)
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="text-center py-12">
      <div class="mx-auto h-12 w-12 text-gray-400">
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
        </svg>
      </div>
      <h3 class="mt-4 text-lg font-medium text-gray-900">No people found</h3>
      <p class="mt-2 text-gray-500"><%= @message %></p>
    </div>
    """
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp start_async_loading(socket, user) do
    you_know_task =
      Task.async(fn ->
        load_you_know(user)
      end)

    at_events_task =
      Task.async(fn ->
        # Return tuple of {upcoming, past} for proper grouping
        upcoming = Discovery.upcoming_event_attendees(user, limit: 10)
        past = Discovery.event_co_attendees(user, limit: 10, timeframe: :past)
        {upcoming, past}
      end)

    might_know_task =
      Task.async(fn ->
        Discovery.friends_of_friends(user, limit: 20, include_mutual_users: true)
      end)

    socket
    |> assign(:loading_tasks, %{
      you_know: you_know_task,
      at_your_events: at_events_task,
      you_might_know: might_know_task
    })
  end

  defp load_people(socket) do
    user = socket.assigns.user
    tab = socket.assigns.active_tab
    cache = socket.assigns.people_cache

    # Check cache first
    if cached = Map.get(cache, tab) do
      case tab do
        :at_your_events ->
          # For at_your_events tab, cache contains {upcoming, past} tuple
          {upcoming, past} = cached

          socket
          |> assign(:upcoming_people, upcoming)
          |> assign(:past_people, past)
          |> assign(:people, upcoming ++ past)
          |> assign(:loading, false)

        _ ->
          socket
          |> assign(:people, cached)
          |> assign(:loading, false)
      end
    else
      case tab do
        :you_know ->
          people = load_you_know(user)

          socket
          |> assign(:people, people)
          |> assign(:people_cache, Map.put(cache, tab, people))
          |> assign(:loading, false)

        :at_your_events ->
          # Load both upcoming and past attendees for proper grouping
          upcoming = Discovery.upcoming_event_attendees(user, limit: 10)
          past = Discovery.event_co_attendees(user, limit: 10, timeframe: :past)

          socket
          |> assign(:upcoming_people, upcoming)
          |> assign(:past_people, past)
          |> assign(:people, upcoming ++ past)
          |> assign(:people_cache, Map.put(cache, tab, {upcoming, past}))
          |> assign(:loading, false)

        :you_might_know ->
          people = Discovery.friends_of_friends(user, limit: 20, include_mutual_users: true)

          socket
          |> assign(:people, people)
          |> assign(:people_cache, Map.put(cache, tab, people))
          |> assign(:loading, false)
      end
    end
  end

  defp load_you_know(user) do
    # Get existing connections (list_relationships already filters to active only)
    Relationships.list_relationships(user, limit: 50)
    |> Enum.map(fn rel ->
      %{
        user: rel.related_user,
        relationship: rel,
        shared_event_count: rel.shared_event_count || 0
      }
    end)
  end

  defp parse_tab("you_know"), do: :you_know
  defp parse_tab("at_your_events"), do: :at_your_events
  defp parse_tab("you_might_know"), do: :you_might_know
  defp parse_tab(_), do: :you_know

  defp build_path(:you_know), do: "/people/discover"
  defp build_path(tab), do: "/people/discover?tab=#{tab}"

  defp get_user(%{user: user}), do: user
  defp get_user(%{related_user: user}), do: user
  defp get_user(_), do: %{name: nil, email: nil}

  defp get_context(person, :you_know) do
    count = Map.get(person, :shared_event_count, 0)

    if count > 0 do
      "#{count} events together"
    else
      "Connected"
    end
  end

  defp get_context(person, :at_your_events) do
    count = Map.get(person, :shared_event_count, 0)
    mutual = Map.get(person, :mutual_count, 0)

    parts = []
    parts = if count > 0, do: ["#{count} shared events" | parts], else: parts
    parts = if mutual > 0, do: ["#{mutual} mutual" | parts], else: parts

    if Enum.empty?(parts), do: "From your events", else: Enum.join(parts, " · ")
  end

  defp get_context(person, :you_might_know) do
    count = Map.get(person, :mutual_count, 0)

    if count > 0 do
      if count == 1, do: "1 mutual friend", else: "#{count} mutual friends"
    else
      "Extended network"
    end
  end

  defp get_shared_events(%{shared_events: events}) when is_list(events), do: events
  defp get_shared_events(%{upcoming_events: events}) when is_list(events), do: events
  defp get_shared_events(_), do: nil

  defp get_first_shared_event(%{shared_events: [event | _]}), do: event
  defp get_first_shared_event(%{upcoming_events: [event | _]}), do: event
  defp get_first_shared_event(_), do: nil

  defp truncate_event_title(title) when byte_size(title) > 20 do
    String.slice(title, 0, 17) <> "..."
  end

  defp truncate_event_title(title), do: title

  defp generate_avatar_url(user) do
    EventasaurusApp.Avatars.generate_user_avatar(user, size: 48)
  end

  defp empty_message(:you_know) do
    "You haven't connected with anyone yet. Attend events to meet people!"
  end

  defp empty_message(:at_your_events) do
    "No other attendees from your events yet."
  end

  defp empty_message(:you_might_know) do
    "We couldn't find any friends-of-friends suggestions. This grows as your network expands!"
  end
end
