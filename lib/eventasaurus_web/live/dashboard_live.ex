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

      {:ok,
       socket
       |> assign(:user, user)
       |> assign(:loading, true)
       |> assign(:time_filter, :upcoming)
       |> assign(:ownership_filter, :all)
       |> assign(:events, [])
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
    
    {:noreply,
     socket
     |> assign(:time_filter, time_filter)
     |> push_patch(to: build_dashboard_path(time_filter, socket.assigns.ownership_filter))
     |> load_unified_events()}
  end

  @impl true
  def handle_event("filter_ownership", %{"filter" => filter}, socket) do
    ownership_filter = safe_to_atom(filter, [:all, :created, :participating])
    
    {:noreply,
     socket
     |> assign(:ownership_filter, ownership_filter)
     |> push_patch(to: build_dashboard_path(socket.assigns.time_filter, ownership_filter))
     |> load_unified_events()}
  end

  @impl true
  def handle_event("refresh_events", _params, socket) do
    {:noreply,
     socket
     |> assign(:loading, true)
     |> load_unified_events()}
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

  @impl true
  def handle_info({:order_updated, _order}, socket) do
    # Reload events to reflect any ticket changes
    {:noreply, load_unified_events(socket)}
  end

  # Private helper functions

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
      Events.list_unified_events_for_user(user, [
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
    Events.list_unified_events_for_user(user, [
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

  defp format_time(datetime, timezone) do
    if datetime do
      datetime
      |> DateTime.shift_zone!(timezone || "UTC")
      |> Calendar.strftime("%I:%M %p")
      |> String.trim()
    else
      "TBD"
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

  defp group_events_by_date(events) do
    events
    |> Enum.group_by(fn event ->
      if event.start_at do
        event.start_at |> DateTime.to_date()
      else
        :no_date
      end
    end)
    |> Enum.sort_by(fn {date, _events} ->
      case date do
        :no_date -> ~D[9999-12-31]  # Sort no_date events last
        date -> date
      end
    end, :desc)
  end

  defp safe_to_atom(value, allowed_atoms) do
    atom = String.to_existing_atom(value)
    if atom in allowed_atoms, do: atom, else: hd(allowed_atoms)
  rescue
    ArgumentError -> hd(allowed_atoms)
  end

end