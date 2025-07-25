defmodule EventasaurusWeb.GroupLive.Index do
  use EventasaurusWeb, :live_view
  
  alias EventasaurusApp.Groups
  
  @impl true
  def mount(_params, _session, socket) do
    # Get user from socket assigns (set by auth hook)
    user = socket.assigns[:user]
    
    if user do
      {:ok,
       socket
       |> assign(:user, user)
       |> assign(:page_title, "Groups")
       |> assign(:search_query, "")
       |> assign(:show_my_groups_only, false)
       |> load_groups()}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to view groups.")
       |> redirect(to: "/auth/login")}
    end
  end
  
  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> load_groups()}
  end

  @impl true
  def handle_event("filter_my_groups", %{"show_my_groups_only" => show_my_groups}, socket) do
    show_my_groups_only = show_my_groups == "true"
    
    {:noreply,
     socket
     |> assign(:show_my_groups_only, show_my_groups_only)
     |> load_groups()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:show_my_groups_only, false)
     |> load_groups()}
  end

  @impl true
  def handle_event("join_group", %{"id" => id}, socket) do
    group = Groups.get_group!(id)
    user = socket.assigns.user
    
    case Groups.add_user_to_group(group, user, "member", user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Successfully joined #{group.name}")
         |> load_groups()}
      
      {:error, :already_member} ->
        {:noreply,
         socket
         |> put_flash(:info, "You are already a member of this group")
         |> load_groups()}
      
      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to join group")}
    end
  end

  @impl true
  def handle_event("delete_group", %{"id" => id}, socket) do
    group = Groups.get_group!(id)
    
    # Check if user is the creator
    if group.created_by_id == socket.assigns.user.id do
      case Groups.delete_group(group) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Group deleted successfully")
           |> load_groups()}
        
        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to delete group")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You can only delete groups you created")}
    end
  end
  
  defp load_groups(socket) do
    user = socket.assigns.user
    search_query = socket.assigns.search_query
    show_my_groups_only = socket.assigns.show_my_groups_only
    
    # Use the new batch query method to avoid N+1 queries
    groups_with_info = Groups.list_groups_with_user_info(user, search_query, show_my_groups_only)
    
    assign(socket, :groups, groups_with_info)
  end
end