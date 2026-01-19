defmodule EventasaurusWeb.AdminOrderLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Ticketing}
  alias EventasaurusWeb.Helpers.CurrencyHelpers
  alias EventasaurusApp.DateTimeHelper

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    event = Events.get_event_by_slug(slug)

    if event do
      case socket.assigns[:user] do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "You must be logged in to view orders")
           |> redirect(to: "/auth/login")}

        user ->
          if Events.user_can_manage_event?(user, event) do
            orders = Ticketing.list_orders_for_event(event.id)

            {:ok,
             socket
             |> assign(:event, event)
             |> assign(:orders, orders)
             |> assign(:filtered_orders, orders)
             |> assign(:user, user)
             |> assign(:loading, false)
             |> assign(:status_filter, "all")
             |> assign(:date_filter, "all")
             |> assign(:page_title, "Orders - #{event.title}")}
          else
            {:ok,
             socket
             |> put_flash(:error, "You don't have permission to view this event's orders")
             |> redirect(to: "/dashboard")}
          end
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "Event not found")
       |> redirect(to: "/dashboard")}
    end
  end

  @impl true
  def handle_event("filter_orders", %{"status" => status}, socket) do
    filtered_orders = filter_orders_by_status(socket.assigns.orders, status)

    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:filtered_orders, filtered_orders)}
  end

  @impl true
  def handle_event("filter_by_date", %{"date_range" => date_range}, socket) do
    current_status_filter = socket.assigns.status_filter
    status_filtered_orders = filter_orders_by_status(socket.assigns.orders, current_status_filter)
    date_filtered_orders = filter_orders_by_date(status_filtered_orders, date_range)

    {:noreply,
     socket
     |> assign(:date_filter, date_range)
     |> assign(:filtered_orders, date_filtered_orders)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    orders = Ticketing.list_orders_for_event(socket.assigns.event.id)
    current_status_filter = socket.assigns.status_filter
    current_date_filter = socket.assigns.date_filter

    # Reapply current filters
    filtered_orders =
      orders
      |> filter_orders_by_status(current_status_filter)
      |> filter_orders_by_date(current_date_filter)

    {:noreply,
     socket
     |> assign(:orders, orders)
     |> assign(:filtered_orders, filtered_orders)
     |> put_flash(:info, "Orders refreshed")}
  end

  # Helper functions

  defp filter_orders_by_status(orders, "all"), do: orders

  defp filter_orders_by_status(orders, status) do
    Enum.filter(orders, &(&1.status == status))
  end

  defp filter_orders_by_date(orders, "all"), do: orders

  defp filter_orders_by_date(orders, "today") do
    today = Date.utc_today()

    Enum.filter(orders, fn order ->
      case order.inserted_at do
        # Exclude orders with nil timestamps
        nil ->
          false

        timestamp ->
          order_date = extract_date(timestamp)
          Date.compare(order_date, today) == :eq
      end
    end)
  end

  defp filter_orders_by_date(orders, "week") do
    week_ago = Date.add(Date.utc_today(), -7)

    Enum.filter(orders, fn order ->
      case order.inserted_at do
        # Exclude orders with nil timestamps
        nil ->
          false

        timestamp ->
          order_date = extract_date(timestamp)
          Date.compare(order_date, week_ago) != :lt
      end
    end)
  end

  defp filter_orders_by_date(orders, "month") do
    today = Date.utc_today()
    days_in_month = Calendar.ISO.days_in_month(today.year, today.month)
    month_ago = Date.add(today, -days_in_month)

    Enum.filter(orders, fn order ->
      case order.inserted_at do
        # Exclude orders with nil timestamps
        nil ->
          false

        timestamp ->
          order_date = extract_date(timestamp)
          Date.compare(order_date, month_ago) != :lt
      end
    end)
  end

  defp extract_date(%NaiveDateTime{} = naive_datetime), do: NaiveDateTime.to_date(naive_datetime)
  defp extract_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)

  defp format_order_total(order) do
    total_cents = order.quantity * order.ticket.base_price_cents
    CurrencyHelpers.format_currency(total_cents, order.ticket.currency)
  end

  defp format_order_date(nil, _event), do: "N/A"

  defp format_order_date(%NaiveDateTime{} = naive_datetime, event) do
    # Convert NaiveDateTime to DateTime assuming UTC, then convert to event timezone
    {:ok, datetime} = DateTime.from_naive(naive_datetime, "UTC")
    format_order_date(datetime, event)
  end

  defp format_order_date(%DateTime{} = datetime, event) do
    timezone = if event && event.timezone, do: event.timezone, else: "UTC"

    datetime
    |> DateTimeHelper.utc_to_timezone(timezone)
    |> Calendar.strftime("%m/%d/%Y at %H:%M %Z")
  end

  defp status_badge_class("confirmed"), do: "bg-green-100 text-green-800"
  defp status_badge_class("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class("cancelled"), do: "bg-red-100 text-red-800"
  defp status_badge_class("refunded"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp calculate_summary(orders) do
    %{
      total_orders: length(orders),
      confirmed_orders: Enum.count(orders, &(&1.status == "confirmed")),
      pending_orders: Enum.count(orders, &(&1.status == "pending")),
      total_revenue: calculate_total_revenue(orders),
      total_tickets: Enum.sum(Enum.map(orders, & &1.quantity))
    }
  end

  defp calculate_total_revenue(orders) do
    confirmed_orders = Enum.filter(orders, &(&1.status == "confirmed"))

    Enum.reduce(confirmed_orders, 0, fn order, acc ->
      order_total = order.quantity * order.ticket.base_price_cents
      acc + order_total
    end)
  end
end
