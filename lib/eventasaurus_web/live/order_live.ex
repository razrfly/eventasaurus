defmodule EventasaurusWeb.OrderLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Ticketing

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to order updates
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "orders:#{socket.assigns.current_user.id}")
    end

    {:ok,
     socket
     |> assign(:orders, [])
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> load_orders()}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_order", %{"order_id" => order_id}, socket) do
    case Ticketing.get_user_order(socket.assigns.current_user.id, order_id) do
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
             |> load_orders()}

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
  def handle_event("refresh_orders", _params, socket) do
    {:noreply, load_orders(socket)}
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

  defp load_orders(socket) do
    case Ticketing.list_user_orders(socket.assigns.current_user.id) do
      orders when is_list(orders) ->
        socket
        |> assign(:orders, orders)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:orders, [])
        |> assign(:loading, false)
        |> assign(:error, "Failed to load orders: #{inspect(reason)}")
    end
  end

  defp format_currency(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
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
end
