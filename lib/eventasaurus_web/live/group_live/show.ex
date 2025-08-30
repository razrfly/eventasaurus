defmodule EventasaurusWeb.GroupLive.Show do
  use EventasaurusWeb, :live_view
  
  alias EventasaurusApp.Groups
  alias EventasaurusApp.Events
  
  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Check authentication first
    case socket.assigns[:user] do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to view groups.")
         |> redirect(to: "/auth/login")}
      
      user ->
        # Try to find the group
        case Groups.get_group_by_slug(slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Group not found.")
             |> redirect(to: "/groups")}
          
          group ->
            # Check if user is a member
            if not Groups.user_in_group?(group, user) do
              {:ok,
               socket
               |> assign(:user, user)
               |> assign(:group, group)
               |> assign(:page_title, group.name)
               |> assign(:is_member, false)
               |> assign(:is_creator, group.created_by_id == user.id)
               |> assign(:members, [])
               |> assign(:member_count, 0)
               |> assign(:events, [])
               |> assign(:event_count, 0)
               |> assign(:active_tab, "events")}
            else
              # Load full group data for members
              members = Groups.list_group_members_with_roles(group)
              member_count = length(members)
              
              # Load group events using unified function with proper ordering
              time_filter = :upcoming  # Default to upcoming events
              events = Events.list_events_for_group(group, user, [
                time_filter: time_filter,
                limit: 100
              ])
              
              # Calculate filter counts by fetching all events once
              all_events = Events.list_events_for_group(group, user, [
                time_filter: :all,
                limit: 1000
              ])
              filter_counts = calculate_filter_counts(all_events)
              event_count = length(events)
              
              {:ok,
               socket
               |> assign(:user, user)
               |> assign(:group, group)
               |> assign(:page_title, group.name)
               |> assign(:is_member, true)
               |> assign(:is_creator, group.created_by_id == user.id)
               |> assign(:members, members)
               |> assign(:member_count, member_count)
               |> assign(:events, events)
               |> assign(:event_count, event_count)
               |> assign(:time_filter, time_filter)
               |> assign(:filter_counts, filter_counts)
               |> assign(:active_tab, "events")
               |> assign(:search_query, "")
               |> assign(:role_filter, "all")
               |> assign(:paginated_members, [])
               |> assign(:total_pages, 1)
               |> assign(:current_page, 1)
               |> assign(:show_add_modal, false)
               |> assign(:potential_members, [])
               |> assign(:add_member_search, "")
               |> assign(:selected_user_id, nil)
               |> assign(:open_member_menu, nil)}
            end
        end
    end
  end
  
  @impl true
  def handle_event("join_group", _params, socket) do
    group = socket.assigns.group
    user = socket.assigns.user
    
    case Groups.add_user_to_group(group, user) do
      {:ok, _} ->
        # Reload group data after joining
        members = Groups.list_group_members_with_roles(group)
        member_count = length(members)
        
        # Load group events using unified function with proper ordering
        time_filter = :upcoming
        events = Events.list_events_for_group(group, user, [
          time_filter: time_filter,
          limit: 100
        ])
        
        # Calculate filter counts
        all_events = Events.list_events_for_group(group, user, [
          time_filter: :all,
          limit: 1000
        ])
        filter_counts = calculate_filter_counts(all_events)
        event_count = length(events)
        
        {:noreply,
         socket
         |> put_flash(:info, "Successfully joined the group!")
         |> assign(:is_member, true)
         |> assign(:members, members)
         |> assign(:member_count, member_count)
         |> assign(:events, events)
         |> assign(:event_count, event_count)
         |> assign(:time_filter, time_filter)
         |> assign(:filter_counts, filter_counts)
         |> assign(:active_tab, "events")
         |> assign(:search_query, "")
         |> assign(:role_filter, "all")
         |> assign(:paginated_members, [])
         |> assign(:total_pages, 1)
         |> assign(:current_page, 1)
         |> assign(:show_add_modal, false)
         |> assign(:potential_members, [])
         |> assign(:add_member_search, "")
         |> assign(:selected_user_id, nil)
         |> assign(:open_member_menu, nil)}
      
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to join group")}
    end
  end
  
  @impl true
  def handle_event("leave_group", _params, socket) do
    group = socket.assigns.group
    user = socket.assigns.user
    
    # Don't allow creator to leave
    if socket.assigns.is_creator do
      {:noreply,
       socket
       |> put_flash(:error, "Group creator cannot leave the group")}
    else
      case Groups.remove_user_from_group(group, user) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "You have left the group")
           |> redirect(to: "/groups")}
        
        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to leave group")}
      end
    end
  end
  
  @impl true
  def handle_event("delete_group", _params, socket) do
    if socket.assigns.is_creator do
      case Groups.delete_group(socket.assigns.group) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Group deleted successfully")
           |> redirect(to: "/groups")}
        
        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to delete group")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Only the group creator can delete the group")}
    end
  end
  
  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket = assign(socket, :active_tab, tab)
    
    # Load members data when switching to members tab
    socket = if tab == "members" do
      load_members_page(socket, 1)
    else
      socket
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("search_members", %{"query" => query}, socket) do
    socket = socket
             |> assign(:search_query, query)
             |> assign(:current_page, 1)
    
    socket = load_members_page(socket, 1)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("filter_by_role", %{"role" => role}, socket) do
    socket = socket
             |> assign(:role_filter, role)
             |> assign(:current_page, 1)
    
    socket = load_members_page(socket, 1)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("filter_members", %{"role_filter" => role}, socket) do
    socket = socket
             |> assign(:role_filter, role)
             |> assign(:current_page, 1)
    
    socket = load_members_page(socket, 1)
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_member_filters", _params, socket) do
    socket = socket
             |> assign(:role_filter, "all")
             |> assign(:search_query, "")
             |> assign(:current_page, 1)
    
    socket = load_members_page(socket, 1)
    {:noreply, socket}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page_num = String.to_integer(page)
    socket = load_members_page(socket, page_num)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("open_add_modal", _params, socket) do
    # Load potential members when opening modal
    potential_members = Groups.list_potential_group_members(socket.assigns.group, limit: 10)
    
    {:noreply,
     socket
     |> assign(:show_add_modal, true)
     |> assign(:potential_members, potential_members)
     |> assign(:add_member_search, "")
     |> assign(:selected_user_id, nil)}
  end
  
  @impl true
  def handle_event("close_add_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> assign(:potential_members, [])
     |> assign(:add_member_search, "")
     |> assign(:selected_user_id, nil)}
  end
  
  @impl true
  def handle_event("search_potential_members", %{"search" => search}, socket) do
    potential_members = if String.trim(search) == "" do
      Groups.list_potential_group_members(socket.assigns.group, limit: 10)
    else
      Groups.list_potential_group_members(socket.assigns.group, search: search, limit: 10)
    end
    
    {:noreply,
     socket
     |> assign(:add_member_search, search)
     |> assign(:potential_members, potential_members)}
  end
  
  @impl true
  def handle_event("select_user", %{"user_id" => user_id}, socket) do
    case Integer.parse(user_id) do
      {parsed_id, _} ->
        {:noreply, assign(socket, :selected_user_id, parsed_id)}
      :error ->
        {:noreply, socket |> put_flash(:error, "Invalid user ID")}
    end
  end
  
  @impl true
  def handle_event("add_member", %{"role" => role}, socket) do
    if socket.assigns.selected_user_id do
      case EventasaurusApp.Accounts.get_user(socket.assigns.selected_user_id) do
        nil ->
          {:noreply, socket |> put_flash(:error, "User not found")}
        user ->
          case Groups.add_user_to_group(socket.assigns.group, user, role, socket.assigns.user) do
            {:ok, _} ->
              # Reload members
              socket = load_members_page(socket, 1)
              member_count = Groups.count_group_members(socket.assigns.group)
              
              {:noreply,
               socket
               |> assign(:show_add_modal, false)
               |> assign(:potential_members, [])
               |> assign(:add_member_search, "")
               |> assign(:selected_user_id, nil)
               |> assign(:member_count, member_count)
               |> put_flash(:info, "Member added successfully")}
               
            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "Failed to add member")}
          end
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please select a user to add")}
    end
  end
  
  @impl true
  def handle_event("toggle_member_menu", %{"user_id" => user_id}, socket) do
    case Integer.parse(user_id) do
      {parsed_id, _} ->
        # Toggle menu - if same user clicked, close it; otherwise open new one
        open_menu = if socket.assigns.open_member_menu == parsed_id, do: nil, else: parsed_id
        {:noreply, assign(socket, :open_member_menu, open_menu)}
      :error ->
        {:noreply, socket |> put_flash(:error, "Invalid user ID")}
    end
  end
  
  @impl true
  def handle_event("close_member_menu", _params, socket) do
    {:noreply, assign(socket, :open_member_menu, nil)}
  end

  @impl true
  def handle_event("remove_member", %{"user_id" => user_id}, socket) do
    case Integer.parse(user_id) do
      {parsed_id, _} ->
        # Only creators and the member themselves can remove
        if socket.assigns.is_creator or socket.assigns.user.id == parsed_id do
          case EventasaurusApp.Accounts.get_user(parsed_id) do
            nil ->
              {:noreply, socket |> put_flash(:error, "User not found")}
            user ->
              case Groups.remove_user_from_group(socket.assigns.group, user, socket.assigns.user) do
                {:ok, _} ->
                  # Reload members
                  socket = load_members_page(socket, socket.assigns.current_page)
                  
                  # Update member count
                  member_count = Groups.count_group_members(socket.assigns.group)
                  
                  {:noreply,
                   socket
                   |> assign(:member_count, member_count)
                   |> put_flash(:info, "Member removed successfully")}
                   
                {:error, _} ->
                  {:noreply,
                   socket
                   |> put_flash(:error, "Failed to remove member")}
              end
          end
        else
          {:noreply,
           socket
           |> put_flash(:error, "You don't have permission to remove this member")}
        end
      :error ->
        {:noreply, socket |> put_flash(:error, "Invalid user ID")}
    end
  end
  
  # Helper functions
  
  def format_relative_time(datetime) do
    # Convert to DateTime if it's a NaiveDateTime, return fallback for invalid types
    datetime = case datetime do
      %NaiveDateTime{} = ndt -> 
        DateTime.from_naive!(ndt, "Etc/UTC")
      %DateTime{} = dt -> 
        dt
      _ -> 
        # Return fallback for unsupported types (nil, string, integer, etc.)
        nil
    end
    
    # Handle nil case - return fallback string
    if datetime == nil do
      "unknown"
    else
      now = DateTime.utc_now()
      diff_seconds = DateTime.diff(now, datetime)
      diff_minutes = div(diff_seconds, 60)
      diff_hours = div(diff_minutes, 60)
      diff_days = div(diff_hours, 24)
      
      cond do
        diff_seconds < 60 -> "just now"
        diff_minutes < 60 -> "#{diff_minutes} minute#{if diff_minutes != 1, do: "s"} ago"
        diff_hours < 24 -> "#{diff_hours} hour#{if diff_hours != 1, do: "s"} ago"
        diff_days < 7 -> "#{diff_days} day#{if diff_days != 1, do: "s"} ago"
        true -> Calendar.strftime(datetime, "%b %d, %Y")
      end
    end
  end
  
  def role_badge_class(role) do
    base = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
    
    case role do
      "admin" -> "#{base} bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"
      "member" -> "#{base} bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
      _ -> "#{base} bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
    end
  end
  
  defp load_members_page(socket, page) do
    opts = [
      page: page,
      per_page: 20,
      search: socket.assigns[:search_query] || ""
    ]
    
    # Add role filter if not "all"
    role_filter = socket.assigns[:role_filter] || "all"
    opts = if role_filter != "all" do
      Keyword.put(opts, :role, role_filter)
    else
      opts
    end
    
    result = Groups.list_group_members_paginated(socket.assigns.group, opts)
    
    socket
    |> assign(:paginated_members, result.entries)
    |> assign(:total_pages, result.total_pages)
    |> assign(:current_page, result.page)
  end

  # Handle time filter changes from EventTimelineComponent
  @impl true
  def handle_info({:filter_time, time_filter}, socket) do
    # Validate time_filter for group events (only upcoming and past are supported)
    time_filter = if time_filter in [:upcoming, :past], do: time_filter, else: :upcoming
    
    group = socket.assigns.group
    user = socket.assigns.user
    
    # Use unified function for filtered events with proper ordering
    events = Events.list_events_for_group(group, user, [
      time_filter: time_filter,
      limit: 100
    ])
    
    # Get all events for filter counts
    all_events = Events.list_events_for_group(group, user, [
      time_filter: :all,
      limit: 1000
    ])
    filter_counts = calculate_filter_counts(all_events)
    
    {:noreply,
     socket
     |> assign(:time_filter, time_filter)
     |> assign(:events, events)
     |> assign(:filter_counts, filter_counts)}
  end

  # Helper functions

  defp calculate_filter_counts(events) do
    now = DateTime.utc_now()
    
    upcoming_count = events
    |> Enum.count(fn event ->
      case event.start_at do
        nil -> true
        start_at -> DateTime.compare(start_at, now) in [:gt, :eq]
      end
    end)
    
    past_count = events
    |> Enum.count(fn event ->
      case event.start_at do
        nil -> false
        start_at -> DateTime.compare(start_at, now) == :lt
      end
    end)
    
    %{
      upcoming: upcoming_count,
      past: past_count
    }
  end
end