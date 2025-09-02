defmodule EventasaurusWeb.DashboardLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Ticketing}
  alias EventasaurusWeb.Helpers.TicketCrypto

  @impl true
  def mount(_params, _session, socket) do
    # Get user from socket assigns (set by auth hook)
    user = socket.assigns[:user]

    if user do
      # Subscribe to order updates for real-time notifications
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "orders:#{user.id}")
      end

      # Start async tasks to preload all tabs
      socket_with_tasks = if connected?(socket) do
        upcoming_task = Task.async(fn ->
          Events.list_unified_events_for_user_optimized(user, [
            time_filter: :upcoming,
            ownership_filter: :all,
            limit: 50
          ])
        end)
        
        past_task = Task.async(fn ->
          Events.list_unified_events_for_user_optimized(user, [
            time_filter: :past,
            ownership_filter: :all,
            limit: 50
          ])
        end)
        
        archived_task = Task.async(fn ->
          Events.list_deleted_events_by_user(user)
          |> Enum.map(fn event ->
            # Transform to match unified events structure
            event
            |> Map.put(:user_role, "organizer")
            |> Map.put(:user_status, "confirmed")
            |> Map.put(:can_manage, true)
            |> Map.put(:participant_count, 0)
            |> Map.put(:participants, [])
          end)
        end)
        
        socket
        |> assign(:loading_tasks, %{
          upcoming: upcoming_task,
          past: past_task,
          archived: archived_task
        })
      else
        socket
        |> assign(:loading_tasks, %{})
      end

      {:ok,
       socket_with_tasks
       |> assign(:user, user)
       |> assign(:loading, true)
       |> assign(:time_filter, :upcoming)
       |> assign(:ownership_filter, :all)
       |> assign(:events, [])
       |> assign(:events_cache, %{})
       |> assign(:filter_counts, %{})
       |> assign(:selected_order, nil)
       |> load_unified_events()}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to view the dashboard.")
       |> redirect(to: "/auth/login")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    time_filter = safe_to_atom(Map.get(params, "time", "upcoming"), [:upcoming, :past, :archived])
    ownership_filter = safe_to_atom(Map.get(params, "ownership", "all"), [:all, :created, :participating])
    
    {:noreply,
     socket
     |> assign(:time_filter, time_filter)
     |> assign(:ownership_filter, ownership_filter)
     |> load_unified_events()}
  end

  @impl true
  def handle_event("filter_time", %{"filter" => filter}, socket) do
    time_filter = safe_to_atom(filter, [:upcoming, :past, :archived])
    socket = apply_time_filter_change(socket, time_filter)
    
    {:noreply,
     socket
     |> push_patch(to: build_dashboard_path(time_filter, socket.assigns.ownership_filter))}
  end

  @impl true
  def handle_event("filter_ownership", %{"filter" => filter}, socket) do
    ownership_filter = safe_to_atom(filter, [:all, :created, :participating])
    socket = apply_ownership_filter_change(socket, ownership_filter)
    
    {:noreply,
     socket
     |> push_patch(to: build_dashboard_path(socket.assigns.time_filter, ownership_filter))}
  end

  @impl true
  def handle_event("refresh_events", _params, socket) do
    user = socket.assigns.user
    
    # Clear cache and restart all async tasks
    socket = if connected?(socket) do
      upcoming_task = Task.async(fn ->
        Events.list_unified_events_for_user_optimized(user, [
          time_filter: :upcoming,
          ownership_filter: :all,
          limit: 50
        ])
      end)
      
      past_task = Task.async(fn ->
        Events.list_unified_events_for_user_optimized(user, [
          time_filter: :past,
          ownership_filter: :all,
          limit: 50
        ])
      end)
      
      archived_task = Task.async(fn ->
        Events.list_deleted_events_by_user(user)
        |> Enum.map(fn event ->
          event
          |> Map.put(:user_role, "organizer")
          |> Map.put(:user_status, "confirmed")
          |> Map.put(:can_manage, true)
          |> Map.put(:participant_count, 0)
          |> Map.put(:participants, [])
        end)
      end)
      
      socket
      |> assign(:loading_tasks, %{
        upcoming: upcoming_task,
        past: past_task,
        archived: archived_task
      })
      |> assign(:events_cache, %{})
      |> assign(:loading, true)
    else
      socket
      |> assign(:loading, true)
      |> load_unified_events()
    end
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_ticket_modal", %{"order_id" => order_id}, socket) do
    user = socket.assigns.user

    case Ticketing.get_user_order(user.id, order_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Ticket not found")}

      order ->
        {:noreply, assign(socket, :selected_order, order)}
    end
  end

  @impl true
  def handle_event("close_ticket_modal", _params, socket) do
    {:noreply, assign(socket, :selected_order, nil)}
  end

  @impl true
  def handle_event("update_participant_status", %{"event_id" => event_id, "status" => status}, socket) do
    user = socket.assigns.user
    status_atom = safe_to_atom(status, [:interested, :accepted, :declined])
    
    case Events.get_event(event_id) do
      nil -> 
        {:noreply, put_flash(socket, :error, "Event not found")}
      event ->
        case Events.update_participant_status(event, user, status_atom) do
          {:ok, _participant} ->
            {:noreply,
             socket
             |> put_flash(:info, "Status updated successfully")
             |> load_unified_events()}
          
          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to update status")}
        end
    end
  end

  # Handle filter changes from EventTimelineComponent
  @impl true
  def handle_info({:filter_time, time_filter}, socket) do
    handle_event("filter_time", %{"filter" => Atom.to_string(time_filter)}, socket)
  end

  @impl true
  def handle_info({:filter_ownership, ownership_filter}, socket) do
    handle_event("filter_ownership", %{"filter" => Atom.to_string(ownership_filter)}, socket)
  end

  @impl true
  def handle_info({:order_updated, _order}, socket) do
    # Reload events to reflect any ticket changes
    {:noreply, load_unified_events(socket)}
  end

  @impl true
  def handle_info({:update_participant_status, %{"event_id" => event_id, "status" => status}}, socket) do
    # Forward to the existing handle_event
    handle_event("update_participant_status", %{"event_id" => event_id, "status" => status}, socket)
  end

  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    # Handle async task completion
    loading_tasks = socket.assigns[:loading_tasks] || %{}
    
    # Find which task completed
    {task_type, updated_tasks} = cond do
      loading_tasks[:upcoming] && loading_tasks[:upcoming].ref == ref ->
        {:upcoming, Map.delete(loading_tasks, :upcoming)}
      loading_tasks[:past] && loading_tasks[:past].ref == ref ->
        {:past, Map.delete(loading_tasks, :past)}
      loading_tasks[:archived] && loading_tasks[:archived].ref == ref ->
        {:archived, Map.delete(loading_tasks, :archived)}
      true ->
        {nil, loading_tasks}
    end
    
    # Update cache with result if task was found
    socket = if task_type do
      events_cache = Map.put(socket.assigns.events_cache, task_type, result)
      
      # Calculate filter counts from cached data
      filter_counts = calculate_filter_counts_from_cache(events_cache, socket.assigns.user)
      
      # If this is the current tab, update the displayed events
      socket = if socket.assigns.time_filter == task_type do
        assign(socket, :events, apply_ownership_filter(result, socket.assigns.ownership_filter))
      else
        socket
      end
      
      socket
      |> assign(:events_cache, events_cache)
      |> assign(:filter_counts, filter_counts)
      |> assign(:loading_tasks, updated_tasks)
      |> assign(:loading, map_size(updated_tasks) > 0)
    else
      socket
    end
    
    # Clean up the task reference
    Process.demonitor(ref, [:flush])
    
    {:noreply, socket}
  end

  # Private helper functions

  defp apply_time_filter_change(socket, time_filter) do
    time_filter = if time_filter in [:upcoming, :past, :archived], do: time_filter, else: :upcoming
    
    if cached_events = socket.assigns.events_cache[time_filter] do
      socket
      |> assign(:time_filter, time_filter)
      |> assign(:events, apply_ownership_filter(cached_events, socket.assigns.ownership_filter))
      |> assign(:loading, false)
    else
      socket
      |> assign(:time_filter, time_filter)
      |> assign(:loading, true)
      |> load_unified_events()
    end
  end

  defp apply_ownership_filter_change(socket, ownership_filter) do
    ownership_filter = if ownership_filter in [:all, :created, :participating], do: ownership_filter, else: :all
    
    if cached_events = socket.assigns.events_cache[socket.assigns.time_filter] do
      socket
      |> assign(:ownership_filter, ownership_filter)
      |> assign(:events, apply_ownership_filter(cached_events, ownership_filter))
      |> assign(:loading, false)
    else
      socket
      |> assign(:ownership_filter, ownership_filter)
      |> assign(:loading, true)
      |> load_unified_events()
    end
  end

  defp load_unified_events(socket) do
    user = socket.assigns.user
    time_filter = socket.assigns.time_filter
    ownership_filter = socket.assigns.ownership_filter

    events = if time_filter == :archived do
      # For archived events, use the dedicated function
      Events.list_deleted_events_by_user(user)
      |> Enum.map(fn event ->
        # Transform to match unified events structure
        event
        |> Map.put(:user_role, "organizer")
        |> Map.put(:user_status, "confirmed")
        |> Map.put(:can_manage, true)
        |> Map.put(:participant_count, 0)
        |> Map.put(:participants, [])
      end)
    else
      # For active events, use the unified function
      Events.list_unified_events_for_user_optimized(user, [
        time_filter: time_filter,
        ownership_filter: ownership_filter,
        limit: 50
      ])
    end

    # Calculate filter counts for badges
    filter_counts = %{
      upcoming: count_events_by_filter(user, :upcoming, :all),
      past: count_events_by_filter(user, :past, :all),
      archived: count_archived_events(user),
      created: count_events_by_filter(user, :all, :created),
      participating: count_events_by_filter(user, :all, :participating)
    }

    socket
    |> assign(:events, events)
    |> assign(:filter_counts, filter_counts)
    |> assign(:loading, false)
  end

  defp count_events_by_filter(user, time_filter, ownership_filter) do
    Events.list_unified_events_for_user_optimized(user, [
      time_filter: time_filter,
      ownership_filter: ownership_filter,
      limit: 1000
    ])
    |> length()
  end

  defp count_archived_events(user) do
    Events.list_deleted_events_by_user(user)
    |> length()
  end

  defp build_dashboard_path(time_filter, ownership_filter) do
    query_params = []
    query_params = if time_filter != :upcoming, do: [{"time", Atom.to_string(time_filter)} | query_params], else: query_params
    query_params = if ownership_filter != :all, do: [{"ownership", Atom.to_string(ownership_filter)} | query_params], else: query_params
    
    case query_params do
      [] -> "/dashboard"
      params -> "/dashboard?" <> URI.encode_query(params)
    end
  end

  defp generate_ticket_id(order) do
    # Generate a cryptographically secure ticket ID using HMAC
    base = "EVT-#{order.id}"
    # Use HMAC with server secret for secure hash generation
    secret_key = TicketCrypto.get_ticket_secret_key()
    data = "#{order.id}#{order.inserted_at}#{order.user_id}#{order.status}"
    hash = :crypto.mac(:hmac, :sha256, secret_key, data)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 16)
    "#{base}-#{hash}"
  end

  defp safe_to_atom(value, allowed_atoms) do
    atom = String.to_existing_atom(value)
    if atom in allowed_atoms, do: atom, else: hd(allowed_atoms)
  rescue
    ArgumentError -> hd(allowed_atoms)
  end

  defp apply_ownership_filter(events, ownership_filter) do
    case ownership_filter do
      :created ->
        Enum.filter(events, &(&1.user_role == "organizer"))
      :participating ->
        Enum.filter(events, &(&1.user_role == "participant"))
      :all ->
        events
    end
  end

  defp calculate_filter_counts_from_cache(events_cache, _user) do
    # Calculate counts from cached data
    upcoming_events = Map.get(events_cache, :upcoming, [])
    past_events = Map.get(events_cache, :past, [])
    archived_events = Map.get(events_cache, :archived, [])
    
    all_events = upcoming_events ++ past_events
    
    %{
      upcoming: length(upcoming_events),
      past: length(past_events),
      archived: length(archived_events),
      created: all_events |> Enum.filter(&(&1.user_role == "organizer")) |> length(),
      participating: all_events |> Enum.filter(&(&1.user_role == "participant")) |> length()
    }
  end

end