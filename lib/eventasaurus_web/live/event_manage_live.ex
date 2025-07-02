defmodule EventasaurusWeb.EventManageLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Venues, Ticketing}
  alias Eventasaurus.Services.PosthogService
  alias EventasaurusWeb.Helpers.CurrencyHelpers

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    event = Events.get_event_by_slug(slug)

    if event do
      case socket.assigns[:user] do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "You must be logged in to manage events")
           |> redirect(to: "/auth/login")}

        user ->
          if Events.user_can_manage_event?(user, event) do
            # Load all necessary data
            venue = if event.venue_id, do: Venues.get_venue(event.venue_id), else: nil
            organizers = Events.list_event_organizers(event)
            participants = Events.list_event_participants(event)
                          |> Enum.sort_by(& &1.inserted_at, :desc)

            tickets = Ticketing.list_tickets_for_event(event.id)
            orders = Ticketing.list_orders_for_event(event.id)
                    |> EventasaurusApp.Repo.preload([:ticket, :user])

            # Get polling data if event is in polling state
            {date_options, votes_by_date, votes_breakdown} = if event.status == :polling do
              poll = Events.get_event_date_poll(event)
              if poll do
                options = Events.list_event_date_options(poll)
                votes = Events.list_votes_for_poll(poll)

                # Group votes by date
                votes_by_date = Enum.group_by(votes, & &1.event_date_option.date)

                # Pre-compute vote breakdowns
                votes_breakdown =
                  votes_by_date
                  |> Map.new(fn {date, votes} ->
                    breakdown = Enum.frequencies_by(votes, &to_string(&1.vote_type))
                    total = length(votes)
                    {date, %{
                      total: total,
                      yes: Map.get(breakdown, "yes", 0),
                      if_need_be: Map.get(breakdown, "if_need_be", 0),
                      no: Map.get(breakdown, "no", 0)
                    }}
                  end)

                {options, votes_by_date, votes_breakdown}
              else
                {[], %{}, %{}}
              end
            else
              {[], %{}, %{}}
            end

            # Fetch PostHog analytics data
            analytics_data = fetch_analytics_data(event.id)

            registration_status = Events.get_user_registration_status(event, user)

            # Schedule periodic refresh for analytics
            if connected?(socket) do
              Process.send_after(self(), :refresh_analytics, 300_000) # 5 minutes
            end

            {:ok,
             socket
             |> assign(:event, event)
             |> assign(:venue, venue)
             |> assign(:organizers, organizers)
             |> assign(:participants, participants)
             |> assign(:tickets, tickets)
             |> assign(:orders, orders)
             |> assign(:date_options, date_options)
             |> assign(:votes_by_date, votes_by_date)
             |> assign(:votes_breakdown, votes_breakdown)
             |> assign(:analytics_data, analytics_data)
             |> assign(:analytics_loading, false)
             |> assign(:analytics_error, nil)
             |> assign(:registration_status, registration_status)
             |> assign(:user, user)
             |> assign(:active_tab, "overview")
             |> assign(:page_title, "Manage #{event.title}")
             |> assign(:loading, false)}
          else
            {:ok,
             socket
             |> put_flash(:error, "You don't have permission to manage this event")
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
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("refresh_data", _params, socket) do
    # Refresh all data
    participants = Events.list_event_participants(socket.assigns.event)
                  |> Enum.sort_by(& &1.inserted_at, :desc)
    tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)
    orders = Ticketing.list_orders_for_event(socket.assigns.event.id)
            |> EventasaurusApp.Repo.preload([:ticket, :user])

    {:noreply,
     socket
     |> assign(:participants, participants)
     |> assign(:tickets, tickets)
     |> assign(:orders, orders)
     |> put_flash(:info, "Data refreshed")}
  end

  @impl true
  def handle_event("refresh_analytics", _params, socket) do
    socket =
      socket
      |> assign(:analytics_loading, true)
      |> assign(:analytics_error, nil)

    analytics_data = fetch_analytics_data(socket.assigns.event.id)

    {:noreply,
     socket
     |> assign(:analytics_data, analytics_data)
     |> assign(:analytics_loading, false)}
  end

  @impl true
  def handle_info(:refresh_analytics, socket) do
    # Periodic refresh of analytics data
    analytics_data = fetch_analytics_data(socket.assigns.event.id)

    # Schedule next refresh
    Process.send_after(self(), :refresh_analytics, 300_000) # 5 minutes

    {:noreply,
     socket
     |> assign(:analytics_data, analytics_data)}
  end

  # Helper functions

  defp fetch_analytics_data(event_id) do
    try do
      case PosthogService.get_event_analytics(event_id, 30) do
        {:ok, data} -> data
        {:error, reason} ->
          require Logger
          Logger.error("PostHog analytics error: #{inspect(reason)}")

          %{
            unique_visitors: 0,
            registrations: 0,
            votes_cast: 0,
            ticket_checkouts: 0,
            registration_rate: 0.0,
            checkout_conversion_rate: 0.0,
            error: "Analytics temporarily unavailable"
          }
      end
    rescue
      error ->
        # Log error but don't crash the page
        require Logger
        Logger.error("Failed to fetch PostHog analytics: #{inspect(error)}")

        # Return default/empty analytics data
        %{
          unique_visitors: 0,
          registrations: 0,
          votes_cast: 0,
          ticket_checkouts: 0,
          registration_rate: 0.0,
          checkout_conversion_rate: 0.0,
          error: "Analytics temporarily unavailable"
        }
    end
  end

  defp format_event_datetime(event) do
    if event.start_at do
      date = Calendar.strftime(event.start_at, "%A, %B %d, %Y")
      time = Calendar.strftime(event.start_at, "%I:%M %p")
      timezone = event.timezone || "UTC"

      "#{date} at #{time} #{timezone}"
    else
      "Date and time TBA"
    end
  end

  defp calculate_revenue(orders) do
    confirmed_orders = Enum.filter(orders, &(&1.status == "confirmed"))

    Enum.reduce(confirmed_orders, 0, fn order, acc ->
      order_total = order.quantity * order.ticket.base_price_cents
      acc + order_total
    end)
  end

  defp calculate_tickets_sold(orders) do
    confirmed_orders = Enum.filter(orders, &(&1.status == "confirmed"))
    Enum.sum(Enum.map(confirmed_orders, & &1.quantity))
  end

  defp get_ticket_orders(ticket, orders) do
    Enum.filter(orders, &(&1.ticket_id == ticket.id and &1.status == "confirmed"))
  end

  defp get_tickets_sold(ticket, orders) do
    ticket_orders = get_ticket_orders(ticket, orders)
    Enum.sum(Enum.map(ticket_orders, & &1.quantity))
  end

  defp get_tickets_available(ticket, orders) do
    sold = get_tickets_sold(ticket, orders)
    max(0, ticket.quantity - sold)
  end

end
