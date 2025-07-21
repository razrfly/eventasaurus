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
               |> assign(:event_count, 0)}
            else
              # Load full group data for members
              members = Groups.list_group_members(group)
              member_count = length(members)
              
              # Load group events
              events = Events.list_events_for_group(group)
                      |> Enum.sort_by(& &1.date_time, {:desc, DateTime})
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
               |> assign(:event_count, event_count)}
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
        members = Groups.list_group_members(group)
        member_count = length(members)
        
        events = Events.list_events_for_group(group)
                |> Enum.sort_by(& &1.date_time, {:desc, DateTime})
        event_count = length(events)
        
        {:noreply,
         socket
         |> put_flash(:info, "Successfully joined the group!")
         |> assign(:is_member, true)
         |> assign(:members, members)
         |> assign(:member_count, member_count)
         |> assign(:events, events)
         |> assign(:event_count, event_count)}
      
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
end