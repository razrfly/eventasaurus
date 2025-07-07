defmodule EventasaurusWeb.EventManageLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Ticketing}
  alias Eventasaurus.Services.PosthogService
  alias EventasaurusWeb.Helpers.CurrencyHelpers
  import EventasaurusWeb.Components.GuestInvitationModal
  import EventasaurusWeb.EmailStatusComponents
  import EventasaurusWeb.EventHTML, only: [movie_rich_data_display: 1]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Check authentication first
    case socket.assigns[:user] do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to manage events.")
         |> redirect(to: "/auth/login")}

      user ->
        # Try to find the event
        case Events.get_event_by_slug(slug) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Event not found.")
             |> redirect(to: "/dashboard")}

          event ->
            # Ensure user is authorized to manage this event
            if not Events.user_is_organizer?(event, user) do
              {:ok,
               socket
               |> put_flash(:error, "You don't have permission to manage this event.")
               |> redirect(to: "/dashboard")}
            else
              # Implement lazy loading with pagination
              total_participants = Events.count_event_participants(event)

              # Load initial batch of participants (first 20)
              initial_participants = Events.list_event_participants(event, limit: 20, offset: 0)
                                   |> Enum.sort_by(& &1.inserted_at, :desc)

              tickets = Ticketing.list_tickets_for_event(event.id)
              orders = Ticketing.list_orders_for_event(event.id)
                      |> EventasaurusApp.Repo.preload([:ticket, :user])

              # Fetch analytics data for insights tab
              analytics_data = fetch_analytics_data(event.id)

              {:ok,
               socket
               |> assign(:event, event)
               |> assign(:user, user)
               |> assign(:page_title, "Manage Event")
               |> assign(:active_tab, "overview")  # Default tab
               |> assign(:venue, event.venue)  # Add missing venue assign
               |> assign_participants_with_stats(initial_participants)
               |> assign(:participants_count, total_participants)
               |> assign(:participants_loaded, length(initial_participants))
               |> assign(:participants_loading, false)
               |> assign(:guests_source_filter, nil)  # Guest filtering state
               |> assign(:guests_status_filter, nil)  # Smart combined status filtering state
               |> assign(:tickets, tickets)
               |> assign(:orders, orders)
               |> assign(:analytics_data, analytics_data)  # Required for insights tab
               |> assign(:analytics_loading, false)  # Required for insights tab
               |> assign(:analytics_error, nil)  # Required for insights tab
               |> assign(:show_guest_invitation_modal, false)
               |> assign(:historical_suggestions, [])
               |> assign(:suggestions_loading, false)
               |> assign(:selected_suggestions, [])
               |> assign(:manual_emails, "")
               |> assign(:invitation_message, "")
               |> assign(:add_mode, "invite")
               |> assign(:open_participant_menu, nil)}  # Track which dropdown is open
            end
        end
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("refresh_data", _params, socket) do
    # Refresh all data with lazy loading
    total_participants = Events.count_event_participants(socket.assigns.event)

    # Reload initial batch
    initial_participants = Events.list_event_participants(socket.assigns.event, limit: 20, offset: 0)
                         |> Enum.sort_by(& &1.inserted_at, :desc)

    tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)
    orders = Ticketing.list_orders_for_event(socket.assigns.event.id)
            |> EventasaurusApp.Repo.preload([:ticket, :user])

    {:noreply,
     socket
     |> assign_participants_with_stats(initial_participants)
     |> assign(:participants_count, total_participants)
     |> assign(:participants_loaded, length(initial_participants))
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
    # Track analytics event
    user = socket.assigns.user
    event = socket.assigns.event
    PosthogService.track_guest_invitation_modal_opened(
      to_string(user.id),
      to_string(event.id),
      %{
        "event_slug" => event.slug,
        "event_title" => event.title
      }
    )

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
      # Track analytics event when adding a historical participant
      organizer = socket.assigns.user
      event = socket.assigns.event

      # Find the suggestion being selected for metadata
      suggestion = socket.assigns.historical_suggestions
                  |> Enum.find(&(&1.user_id == user_id))

      if suggestion do
        PosthogService.track_historical_participant_selected(
          to_string(organizer.id),
          to_string(event.id),
          %{
            "event_slug" => event.slug,
            "participant_user_id" => user_id,
            "participant_email" => suggestion.email,
            "recommendation_level" => suggestion.recommendation_level,
            "participation_count" => suggestion.participation_count,
            "total_selections" => length(current_selections) + 1
          }
        )
      end

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
  def handle_event("invitation_message", %{"invitation_message" => message}, socket) do
    {:noreply, assign(socket, :invitation_message, message)}
  end

  @impl true
  def handle_event("manual_emails", %{"manual_emails" => emails}, socket) do
    {:noreply, assign(socket, :manual_emails, emails)}
  end

  @impl true
  def handle_event("toggle_add_mode", %{"mode" => mode}, socket) when mode in ["invite", "direct"] do
    {:noreply, assign(socket, :add_mode, mode)}
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
      # Determine mode and process invitations
      mode = if socket.assigns.add_mode == "direct", do: :direct_add, else: :invitation

      result = Events.process_guest_invitations(
        event,
        organizer,
        suggestion_structs: suggested_users,
        manual_emails: parsed_emails,
        invitation_message: invitation_message,
        mode: mode
      )

      # Track direct guest additions
      if mode == :direct_add and result.successful_invitations > 0 do
        PosthogService.track_guest_added_directly(
          to_string(organizer.id),
          to_string(event.id),
          %{
            "event_slug" => event.slug,
            "guest_count" => result.successful_invitations,
            "suggested_guests" => length(suggested_users),
            "manual_emails" => length(parsed_emails),
            "total_guests_added" => result.successful_invitations
          }
        )
      end

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
       |> assign_participants_with_stats(updated_participants)
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
  def handle_event("filter_guests", params, socket) do
    source_filter = case Map.get(params, "source_filter") do
      "" -> nil
      source -> source
    end

    status_filter = case Map.get(params, "status_filter") do
      "" -> nil
      status -> status  # Keep as string for combined filtering
    end

    {:noreply,
     socket
     |> assign(:guests_source_filter, source_filter)
     |> assign(:guests_status_filter, status_filter)}
  end

  @impl true
  def handle_event("clear_guest_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:guests_source_filter, nil)
     |> assign(:guests_status_filter, nil)}
  end

  @impl true
  def handle_event("toggle_participant_menu", %{"participant_id" => participant_id}, socket) do
    participant_id = String.to_integer(participant_id)
    current_open = socket.assigns.open_participant_menu

    new_open = if current_open == participant_id, do: nil, else: participant_id

    {:noreply, assign(socket, :open_participant_menu, new_open)}
  end

  @impl true
  def handle_event("close_participant_menu", _params, socket) do
    {:noreply, assign(socket, :open_participant_menu, nil)}
  end

  @impl true
    def handle_event("remove_participant", %{"participant_id" => participant_id}, socket) do
    case Integer.parse(participant_id) do
      {participant_id, _} ->
        case EventasaurusApp.Repo.get(EventasaurusApp.Events.EventParticipant, participant_id) do
          nil ->
            {:noreply, put_flash(socket, :error, "Participant not found")}

          participant ->
            case Events.delete_event_participant(participant) do
              {:ok, _} ->
                # Reload participants
                updated_participants = Events.list_event_participants(socket.assigns.event)
                {:noreply,
                 socket
                 |> assign_participants_with_stats(updated_participants)
                 |> assign(:open_participant_menu, nil)  # Close any open dropdown menus
                 |> put_flash(:info, "Participant removed successfully")}

              {:error, _changeset} ->
                {:noreply, put_flash(socket, :error, "Failed to remove participant")}
            end
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid participant ID")}
    end
  end

  @impl true
  def handle_event("retry_participant_email", %{"participant_id" => participant_id}, socket) do
    participant_id = String.to_integer(participant_id)
    event = socket.assigns.event

    # Find the participant
    participant = Enum.find(socket.assigns.participants, &(&1.id == participant_id))

    if participant do
      case Events.retry_single_email(participant, event) do
        :ok ->
          # Refresh participants to show updated email status
          updated_participants = Events.list_event_participants(event, limit: socket.assigns.participants_loaded)
                               |> Enum.sort_by(& &1.inserted_at, :desc)

          {:noreply,
           socket
           |> assign_participants_with_stats(updated_participants)
           |> put_flash(:info, "Email retry initiated for #{participant.user.name || participant.user.email}")}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to retry email: #{reason}")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Participant not found")}
    end
  end

  @impl true
  def handle_event("add_guests_directly", _params, socket) do
    event = socket.assigns.event
    organizer = socket.assigns.user
    selected_suggestions = socket.assigns.selected_suggestions
    manual_emails = socket.assigns.manual_emails

    # Parse manual emails
    parsed_emails = parse_email_list(manual_emails)

    # Get selected suggestion users
    suggested_users = socket.assigns.historical_suggestions
                     |> Enum.filter(&(&1.user_id in selected_suggestions))

    total_guests = length(suggested_users) + length(parsed_emails)

    if total_guests > 0 do
      # Use our guest invitation processing but set mode to direct
      result = Events.process_guest_invitations(event, organizer,
        suggestion_structs: suggested_users,
        manual_emails: parsed_emails,
        invitation_message: nil,  # No message for direct adds
        mode: :direct_add
      )

      # Build success message
      success_message = build_direct_add_success_message(result)

      # Reload participants to show updated list
      updated_participants = Events.list_event_participants(event)
                           |> Enum.sort_by(& &1.inserted_at, :desc)

      # Build error flash if there were failures
      socket_with_errors = if result.failed_invitations > 0 do
        error_message = "#{result.failed_invitations} addition(s) failed. #{Enum.join(result.errors, "; ")}"
        put_flash(socket, :error, error_message)
      else
        socket
      end

      # Close modal and show success message
      {:noreply,
       socket_with_errors
       |> assign_participants_with_stats(updated_participants)
       |> assign(:show_guest_invitation_modal, false)
       |> assign(:selected_suggestions, [])
       |> assign(:manual_emails, "")
       |> assign(:invitation_message, "")
       |> put_flash(:info, success_message)}
    else
      {:noreply, put_flash(socket, :error, "Please select guests or enter email addresses to add.")}
    end
  end

  @impl true
  def handle_event("load_more_participants", _params, socket) do
    if socket.assigns.participants_loaded < socket.assigns.participants_count do
      socket = assign(socket, :participants_loading, true)

      # Load next batch of participants
      next_batch = Events.list_event_participants(
        socket.assigns.event,
        limit: 20,
        offset: socket.assigns.participants_loaded
      ) |> Enum.sort_by(& &1.inserted_at, :desc)

      # Combine with existing participants
      updated_participants = socket.assigns.participants ++ next_batch

      {:noreply,
       socket
       |> assign_participants_with_stats(updated_participants)
       |> assign(:participants_loaded, socket.assigns.participants_loaded + length(next_batch))
       |> assign(:participants_loading, false)}
    else
      {:noreply, socket}
    end
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
      # Get current participants' user IDs to exclude them from suggestions
      current_participant_user_ids = socket.assigns.participants
                                   |> Enum.map(& &1.user_id)

      # Get historical participants using our guest invitation module
      suggestions = Events.get_participant_suggestions(organizer,
        exclude_event_ids: [event.id],
        exclude_user_ids: current_participant_user_ids,
        limit: 20
      )

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

  # Pre-compute participant statistics to avoid repeated Enum.count operations
  defp assign_participants_with_stats(socket, participants) do
    participant_stats = calculate_participant_stats(participants)

    socket
    |> assign(:participants, participants)
    |> assign(:participant_stats, participant_stats)
  end



  defp calculate_participant_stats(participants) do
    %{
      direct_adds: count_by_source(participants, "direct_add"),
      self_registered: count_by_source(participants, "public_registration"),
      invited: count_invited(participants),
      ticket_holders: count_by_status(participants, :confirmed_with_order)
    }
  end

  defp count_by_source(participants, "direct_add") do
    Enum.count(participants, &(is_binary(&1.source) && String.starts_with?(&1.source, "direct_add")))
  end

  defp count_by_source(participants, source) do
    Enum.count(participants, &(&1.source == source))
  end

  defp count_invited(participants) do
    Enum.count(participants, &(&1.invited_at != nil && !(is_binary(&1.source) && String.starts_with?(&1.source, "direct_add"))))
  end

  defp count_by_status(participants, status) do
    Enum.count(participants, &(&1.status == status))
  end

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

  defp build_direct_add_success_message(result) do
    case {result.successful_invitations, result.skipped_duplicates} do
      {0, 0} ->
        "No guests were added."

      {successful, 0} when successful > 0 ->
        "🎉 #{successful} guest(s) added directly to your event!"

      {0, skipped} when skipped > 0 ->
        "#{skipped} user(s) were already participating in this event."

      {successful, skipped} ->
        "🎉 #{successful} guest(s) added! #{skipped} user(s) were already participating."
    end
  end

# Guest filtering and UI helper functions

  # Helper function to filter participants by source and combined status
  defp get_filtered_participants(participants, source_filter, status_filter) do
    participants
    |> filter_by_source(source_filter)
    |> filter_by_combined_status(status_filter)
  end

  defp filter_by_source(participants, nil), do: participants
  defp filter_by_source(participants, "direct_add") do
    Enum.filter(participants, fn p ->
      is_binary(p.source) && String.starts_with?(p.source, "direct_add")
    end)
  end
  defp filter_by_source(participants, "invitation") do
    Enum.filter(participants, fn p ->
      p.source in ["historical_suggestion", "manual_email"] ||
      (p.invited_at != nil && is_binary(p.source) && !String.starts_with?(p.source, "direct_add"))
    end)
  end
  defp filter_by_source(participants, source) do
    Enum.filter(participants, fn p ->
      case p.source do
        ^source -> true
        source_string when is_binary(source_string) -> source_string == source
        _ -> false
      end
    end)
  end

  defp filter_by_combined_status(participants, nil), do: participants
  defp filter_by_combined_status(participants, combined_status) do
    alias EventasaurusApp.Events.EventParticipant

    case combined_status do
      "pending_email_sent" ->
        participants
        |> Enum.filter(&(&1.status == :pending))
        |> Enum.filter(&email_was_sent?/1)

      "pending_no_email" ->
        participants
        |> Enum.filter(&(&1.status == :pending))
        |> Enum.filter(&email_not_sent?/1)

      "failed_email" ->
        Enum.filter(participants, &email_failed?/1)

      "accepted" ->
        Enum.filter(participants, fn p -> p.status == :accepted end)
      "declined" ->
        Enum.filter(participants, fn p -> p.status == :declined end)
      "cancelled" ->
        Enum.filter(participants, fn p -> p.status == :cancelled end)
      "confirmed_with_order" ->
        Enum.filter(participants, fn p -> p.status == :confirmed_with_order end)

      _ ->
        participants
    end
  end

  # Helper functions for email status checks
  defp email_was_sent?(participant) do
    alias EventasaurusApp.Events.EventParticipant
    email_status = EventParticipant.get_email_status(participant).status
    email_status in ["sent", "delivered", "bounced"]
  end

  defp email_not_sent?(participant) do
    alias EventasaurusApp.Events.EventParticipant
    email_status = EventParticipant.get_email_status(participant).status
    email_status in ["not_sent", "sending", "retrying"]
  end

  defp email_failed?(participant) do
    alias EventasaurusApp.Events.EventParticipant
    email_status = EventParticipant.get_email_status(participant).status
    email_status in ["failed", "bounced"]
  end

  # Helper functions to get badge data (safer than Phoenix.HTML.raw)
  defp get_source_badge_data(participant) do
    cond do
      is_binary(participant.source) and String.starts_with?(participant.source, "direct_add") ->
        {"Direct Add", "bg-blue-100 text-blue-800"}
      participant.source == "public_registration" ->
        {"Self Registered", "bg-green-100 text-green-800"}
      participant.source == "ticket_purchase" ->
        {"Ticket Purchase", "bg-orange-100 text-orange-800"}
      participant.source in ["historical_suggestion", "manual_email"] ->
        {"Invited", "bg-purple-100 text-purple-800"}
      participant.source == "voting_registration" ->
        {"Poll Voter", "bg-indigo-100 text-indigo-800"}
      participant.source == "bulk_voting_registration" ->
        {"Bulk Voter", "bg-indigo-100 text-indigo-800"}
      true ->
        {"Unknown", "bg-gray-100 text-gray-800"}
    end
  end

  defp get_status_badge_data(status) do
    case status do
      :pending ->
        {"Pending", "bg-yellow-100 text-yellow-800"}
      :accepted ->
        {"Accepted", "bg-green-100 text-green-800"}
      :declined ->
        {"Declined", "bg-red-100 text-red-800"}
      :cancelled ->
        {"Cancelled", "bg-gray-100 text-gray-800"}
      :confirmed_with_order ->
        {"Confirmed", "bg-emerald-100 text-emerald-800"}
      _ ->
        {"Unknown", "bg-gray-100 text-gray-800"}
    end
  end

  # Helper function to format relative time
  defp format_relative_time(datetime) when is_nil(datetime), do: "never"
  defp format_relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 ->
        "just now"
      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes} minute#{if minutes == 1, do: "", else: "s"} ago"
      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        "#{hours} hour#{if hours == 1, do: "", else: "s"} ago"
      diff_seconds < 2592000 ->
        days = div(diff_seconds, 86400)
        "#{days} day#{if days == 1, do: "", else: "s"} ago"
      true ->
        Calendar.strftime(datetime, "%m/%d/%Y")
    end
  end

  # Helper function to get inviter name by finding the inviter among participants
  defp get_inviter_name(nil, _), do: "Unknown"
  defp get_inviter_name(inviter_id, participants) do
    participants
    |> Enum.find(fn p -> p.user && p.user.id == inviter_id end)
    |> case do
      %{user: %{name: name}} when is_binary(name) -> name
      _ ->
        # Fallback to direct database lookup if inviter not in participant list
        case EventasaurusApp.Accounts.get_user(inviter_id) do
          %{name: name} when is_binary(name) -> name
          _ -> "Unknown"
        end
    end
  end

end
