defmodule EventasaurusWeb.EventManageLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Venues, Ticketing}
  alias Eventasaurus.Services.PosthogService
  alias EventasaurusWeb.Helpers.CurrencyHelpers
  import EventasaurusWeb.Components.GuestInvitationModal

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
             |> assign(:loading, false)
             # Guest invitation modal state
             |> assign(:show_guest_invitation_modal, false)
             |> assign(:historical_suggestions, [])
             |> assign(:suggestions_loading, false)
             |> assign(:invitation_message, "")
             |> assign(:manual_emails, "")
             |> assign(:selected_suggestions, [])}
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

  # Guest Invitation Modal Events

  @impl true
  def handle_event("open_guest_invitation_modal", _params, socket) do
    # Load historical suggestions when opening modal
    socket =
      socket
      |> assign(:show_guest_invitation_modal, true)
      |> assign(:suggestions_loading, true)
      |> assign(:selected_suggestions, [])
      |> assign(:invitation_message, "")
      |> assign(:manual_emails, "")

    # Fetch suggestions asynchronously
    send(self(), :load_historical_suggestions)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_guest_invitation_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_guest_invitation_modal, false)
     |> assign(:historical_suggestions, [])
     |> assign(:selected_suggestions, [])
     |> assign(:invitation_message, "")
     |> assign(:manual_emails, "")}
  end

  @impl true
  def handle_event("toggle_suggestion", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    current_selections = socket.assigns.selected_suggestions

    updated_selections = if user_id in current_selections do
      List.delete(current_selections, user_id)
    else
      [user_id | current_selections]
    end

    {:noreply, assign(socket, :selected_suggestions, updated_selections)}
  end

  @impl true
  def handle_event("search_suggestions", _params, socket) do
    socket = assign(socket, :suggestions_loading, true)
    send(self(), :load_historical_suggestions)
    {:noreply, socket}
  end

  @impl true
  def handle_event("invitation_message", %{"value" => message}, socket) do
    {:noreply, assign(socket, :invitation_message, message)}
  end

  @impl true
  def handle_event("manual_emails", %{"value" => emails}, socket) do
    {:noreply, assign(socket, :manual_emails, emails)}
  end

  @impl true
  def handle_event("send_invitations", _params, socket) do
    event = socket.assigns.event
    organizer = socket.assigns.user
    selected_suggestions = socket.assigns.selected_suggestions
    manual_emails = socket.assigns.manual_emails
    invitation_message = socket.assigns.invitation_message

    # Parse manual emails
    parsed_emails = parse_email_list(manual_emails)

    # Get selected suggestion users
    suggested_users = socket.assigns.historical_suggestions
                     |> Enum.filter(&(&1.user_id in selected_suggestions))

    total_invitations = length(suggested_users) + length(parsed_emails)

    if total_invitations > 0 do
      # Process invitations using the new robust function
      result = Events.process_guest_invitations(
        event,
        organizer,
        suggestion_structs: suggested_users,
        manual_emails: parsed_emails,
        invitation_message: invitation_message
      )

      # Build success message
      success_message = build_invitation_success_message(result)

      # Reload participants to show updated list
      updated_participants = Events.list_event_participants(event)
                           |> Enum.sort_by(& &1.inserted_at, :desc)

      # Build error flash if there were failures
      socket_with_errors = if result.failed_invitations > 0 do
        error_message = "#{result.failed_invitations} invitation(s) failed. #{Enum.join(result.errors, "; ")}"
        put_flash(socket, :error, error_message)
      else
        socket
      end

      {:noreply,
       socket_with_errors
       |> assign(:participants, updated_participants)
       |> assign(:show_guest_invitation_modal, false)
       |> assign(:historical_suggestions, [])
       |> assign(:selected_suggestions, [])
       |> assign(:invitation_message, "")
       |> assign(:manual_emails, "")
       |> put_flash(:info, success_message)}
    else
      {:noreply, put_flash(socket, :error, "Please select guests or enter email addresses to invite.")}
    end
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # Prevent modal from closing when clicking inside
    {:noreply, socket}
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

    @impl true
  def handle_info(:load_historical_suggestions, socket) do
    event = socket.assigns.event
    organizer = socket.assigns.user

    try do
      # Get historical participants using our guest invitation module
      suggestions = Events.get_participant_suggestions(organizer, exclude_event_ids: [event.id], limit: 20)

      {:noreply,
       socket
       |> assign(:historical_suggestions, suggestions)
       |> assign(:suggestions_loading, false)}
    rescue
      error ->
        require Logger
        Logger.error("Guest invitation modal crashed while loading suggestions: #{inspect(error)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        Logger.error("Socket assigns: event=#{event.id}, user=#{organizer.id}")

        {:noreply,
         socket
         |> assign(:historical_suggestions, [])
         |> assign(:suggestions_loading, false)
         |> put_flash(:error, "Failed to load suggestions")}
    end
  end

  # Helper functions

  defp fetch_analytics_data(event_id) do
    try do
      case PosthogService.get_analytics(event_id, 30) do
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
            error: "Analytics temporarily unavailable",
            has_error: true
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
          error: "Analytics temporarily unavailable",
          has_error: true
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

  # Guest invitation helper functions

  defp parse_email_list(emails_string) when is_binary(emails_string) do
    emails_string
    |> String.split(~r/[,\n]/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&valid_email?/1)
  end

  defp parse_email_list(_), do: []

  defp valid_email?(email) do
    String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
  end

  defp build_invitation_success_message(result) do
    case {result.successful_invitations, result.skipped_duplicates} do
      {0, 0} ->
        "No invitations processed."

      {successful, 0} when successful > 0 ->
        "🎉 #{successful} invitation(s) sent! Guests have been added to your event."

      {0, skipped} when skipped > 0 ->
        "#{skipped} user(s) were already participating in this event."

      {successful, skipped} ->
        "🎉 #{successful} invitation(s) sent! #{skipped} user(s) were already participating."
    end
  end



end
