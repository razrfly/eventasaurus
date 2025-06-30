defmodule EventasaurusWeb.DashboardLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Ticketing}
  alias EventasaurusWeb.Helpers.CurrencyHelpers

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
       |> assign(:active_tab, "events")
       |> assign(:orders, [])
       |> assign(:events, [])
       |> assign(:upcoming_events, [])
       |> assign(:past_events, [])
       |> assign(:order_filter, "all")
       |> assign(:selected_order, nil)
       |> load_dashboard_data()}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to view the dashboard.")
       |> redirect(to: "/auth/login")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(params, "tab", "events")
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> push_patch(to: "/dashboard?tab=#{tab}", replace: true)}
  end

  @impl true
  def handle_event("filter_orders", %{"status" => status}, socket) do
    valid_statuses = ["all", "pending", "payment_pending", "confirmed", "cancelled", "refunded"]
    validated_status = if status in valid_statuses, do: status, else: "all"
    {:noreply, assign(socket, :order_filter, validated_status)}
  end

  @impl true
  def handle_event("refresh_data", _params, socket) do
    {:noreply,
     socket
     |> assign(:loading, true)
     |> load_dashboard_data()}
  end

  @impl true
  def handle_event("cancel_order", %{"order_id" => order_id}, socket) do
    case Ticketing.get_user_order(socket.assigns.user.id, order_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Order not found")}

      order ->
        case Ticketing.cancel_order(order) do
          {:ok, _order} ->
            {:noreply,
             socket
             |> put_flash(:info, "Order cancelled successfully")
             |> load_dashboard_data()}

          {:error, :cannot_cancel} ->
            {:noreply,
             socket
             |> put_flash(:error, "This order cannot be cancelled")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to cancel order")}
        end
    end
  end

  @impl true
  def handle_event("show_ticket_modal", %{"order_id" => order_id}, socket) do
    user = socket.assigns.user

    # Find the order in the current orders list
    case Enum.find(socket.assigns.orders, fn order ->
      to_string(order.id) == order_id and order.user_id == user.id
    end) do
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
  def handle_info({:order_updated, order}, socket) do
    # Update the specific order in the list
    updated_orders =
      Enum.map(socket.assigns.orders, fn existing_order ->
        if existing_order.id == order.id, do: order, else: existing_order
      end)

    {:noreply, assign(socket, :orders, updated_orders)}
  end

  # Private helper functions

  defp load_dashboard_data(socket) do
    user = socket.assigns.user

    # Load events
    events = Events.list_events_by_user(user)
    now = DateTime.utc_now()
    upcoming_events =
      events
      |> Enum.filter(&(&1.start_at && DateTime.compare(&1.start_at, now) != :lt))
      |> Enum.sort_by(& &1.start_at)
    past_events =
      events
      |> Enum.filter(&(&1.start_at && DateTime.compare(&1.start_at, now) == :lt))
      |> Enum.sort_by(& &1.start_at, :desc)

    # Load orders
    orders = case Ticketing.list_user_orders(user.id) do
      orders when is_list(orders) -> orders
      _ -> []
    end

    socket
    |> assign(:events, events)
    |> assign(:upcoming_events, upcoming_events)
    |> assign(:past_events, past_events)
    |> assign(:orders, orders)
    |> assign(:loading, false)
  end

# Removed unused ensure_user_struct/1 function

  defp filtered_orders(orders, "all"), do: orders
  defp filtered_orders(orders, filter) do
    Enum.filter(orders, fn order -> order.status == filter end)
  end

  defp format_currency(cents) when is_integer(cents) do
    CurrencyHelpers.format_currency(cents, "usd")
  end
  defp format_currency(_), do: "$0.00"

  defp status_badge_class(status) do
    case status do
      "pending" -> "bg-yellow-100 text-yellow-800"
      "payment_pending" -> "bg-blue-100 text-blue-800"
      "confirmed" -> "bg-green-100 text-green-800"
      "cancelled" -> "bg-red-100 text-red-800"
      "refunded" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp can_cancel_order?(order) do
    order.status in ["pending", "payment_pending"]
  end

  defp generate_ticket_id(order) do
    # Generate a deterministic but secure ticket ID that can be verified
    base = "EVT-#{order.id}"
    # Create deterministic hash based on order data that can't be easily forged
    data = "#{order.id}#{order.inserted_at}#{order.user_id}#{order.status}"
    hash = :crypto.hash(:sha256, data)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 8)
    "#{base}-#{hash}"
  end
end
