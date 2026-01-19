defmodule EventasaurusWeb.EventManageLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Ticketing, Accounts}
  alias EventasaurusApp.Events.PollOption
  alias EventasaurusApp.EventStateMachine
  alias Eventasaurus.Services.PosthogService
  alias Eventasaurus.Jobs.ThresholdAnnouncementJob
  alias EventasaurusWeb.Helpers.CurrencyHelpers
  alias EventasaurusApp.DateTimeHelper
  alias EventasaurusWeb.Utils.TimezoneUtils
  import EventasaurusWeb.Components.GuestInvitationModal
  import EventasaurusWeb.EmailStatusComponents
  import EventasaurusWeb.EventHTML, only: [movie_rich_data_display: 1]
  import EventasaurusWeb.EventComponents, only: [threshold_progress: 1]

  require Logger

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
              initial_participants =
                Events.list_event_participants(event, limit: 20, offset: 0)
                |> Enum.sort_by(& &1.inserted_at, :desc)

              tickets = Ticketing.list_tickets_for_event(event.id)

              orders =
                Ticketing.list_orders_for_event(event.id)
                |> EventasaurusApp.Repo.preload([:ticket, :user])

              # Fetch analytics data for insights tab
              analytics_data = fetch_analytics_data(event.id)

              # Load event organizers
              organizers = Events.list_event_organizers(event)

              # Calculate threshold status for threshold events
              threshold_met =
                if event.status == :threshold do
                  EventStateMachine.threshold_met?(event)
                else
                  false
                end

              # Check if announcement has been sent (for threshold events)
              announcement_sent = check_announcement_sent(event)

              {:ok,
               socket
               |> assign(:event, event)
               |> assign(:user, user)
               |> assign(:page_title, "Manage Event")
               # Add missing venue assign
               |> assign(:venue, event.venue)
               # Threshold tracking for organizer dashboard
               |> assign(:threshold_met, threshold_met)
               |> assign(:announcement_sent, announcement_sent)
               |> assign_participants_with_stats(initial_participants)
               |> assign(:participants_count, total_participants)
               |> assign(:participants_loaded, length(initial_participants))
               |> assign(:participants_loading, false)
               # Guest filtering state
               |> assign(:guests_source_filter, nil)
               # Smart combined status filtering state
               |> assign(:guests_status_filter, nil)
               |> assign(:tickets, tickets)
               |> assign(:orders, orders)
               # Required for insights tab
               |> assign(:analytics_data, analytics_data)
               # Required for insights tab
               |> assign(:analytics_loading, false)
               # Required for insights tab
               |> assign(:analytics_error, nil)
               |> assign(:show_guest_invitation_modal, false)
               |> assign(:historical_suggestions, [])
               |> assign(:suggestions_loading, false)
               |> assign(:selected_suggestions, [])
               |> assign(:manual_emails, [])
               |> assign(:current_email_input, "")
               |> assign(:bulk_email_input, "")
               |> assign(:invitation_message, "")
               |> assign(:add_mode, "invite")
               # Track which dropdown is open
               |> assign(:open_participant_menu, nil)
               # Track which status dropdown is open
               |> assign(:open_status_menu, nil)
               # Organizer management state
               |> assign(:organizers, organizers)
               |> assign(:show_organizer_search_modal, false)
               |> assign(:organizer_search_query, "")
               |> assign(:organizer_search_results, [])
               |> assign(:organizer_search_loading, false)
               |> assign(:organizer_search_error, nil)
               |> assign(:selected_organizer_results, [])
               |> assign(:organizer_search_offset, 0)
               |> assign(:organizer_search_has_more, false)
               |> assign(:organizer_search_total_shown, 0)
               # Poll management state
               |> assign(:polls, [])
               # Load just the count for tab display
               |> assign(:polls_count, load_poll_count(event))
               |> assign(:total_poll_participants, 0)
               |> assign(:total_votes, 0)
               |> assign(:polls_loading, false)
               |> assign(:editing_poll, nil)
               |> assign(:selected_poll, nil)
               |> assign(:show_poll_details, false)
               # Deletion state
               |> assign(:show_delete_modal, false)
               |> assign(:deletion_reason, "")
               |> assign(:can_hard_delete, false)
               |> assign(:deletion_ineligibility_reason, nil)
               # Threshold confirmation modal state
               |> assign(:show_confirm_threshold_modal, false)
               |> subscribe_to_threshold_updates(event)}
            end
        end
    end
  end

  # Subscribe to PubSub for real-time threshold updates (orders affect threshold progress)
  defp subscribe_to_threshold_updates(socket, event) do
    if connected?(socket) and event.status == :threshold do
      # Subscribe to ticketing updates for order changes
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "ticketing_updates")
      # Subscribe to event organizers channel for participant updates
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "event_organizers:#{event.id}")
    end

    socket
  end

  @impl true
  def handle_params(_params, _url, socket) do
    # Determine active tab based on the live action
    active_tab =
      case socket.assigns.live_action do
        :overview -> "overview"
        :guests -> "guests"
        :registrations -> "registrations"
        :polls -> "polls"
        :insights -> "insights"
        :history -> "history"
        _ -> "overview"
      end

    socket =
      socket
      |> assign(:active_tab, active_tab)
      |> maybe_load_poll_data(active_tab)

    {:noreply, socket}
  end

  defp maybe_load_poll_data(socket, "polls") do
    socket
    |> assign(:polls_loading, true)
    |> load_poll_data()
  end

  defp maybe_load_poll_data(socket, _), do: socket

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    # Navigate to the tab-specific URL instead of just switching state
    event_slug = socket.assigns.event.slug

    path =
      case tab do
        "overview" -> ~p"/events/#{event_slug}"
        "guests" -> ~p"/events/#{event_slug}/guests"
        "registrations" -> ~p"/events/#{event_slug}/registrations"
        "polls" -> ~p"/events/#{event_slug}/polls"
        "insights" -> ~p"/events/#{event_slug}/insights"
        "history" -> ~p"/events/#{event_slug}/history"
        _ -> ~p"/events/#{event_slug}"
      end

    {:noreply, push_navigate(socket, to: path)}
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
      |> assign(:manual_emails, [])
      |> assign(:current_email_input, "")

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
     |> assign(:manual_emails, [])
     |> assign(:current_email_input, "")}
  end

  @impl true
  def handle_event("toggle_suggestion", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    current_selections = socket.assigns.selected_suggestions

    updated_selections =
      if user_id in current_selections do
        List.delete(current_selections, user_id)
      else
        # Track analytics event when adding a historical participant
        organizer = socket.assigns.user
        event = socket.assigns.event

        # Find the suggestion being selected for metadata
        suggestion =
          socket.assigns.historical_suggestions
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
  def handle_event("email_input_change", %{"email_input" => input}, socket) do
    {:noreply, assign(socket, :current_email_input, input)}
  end

  @impl true
  def handle_event("add_email", _params, socket) do
    email =
      socket.assigns.current_email_input
      |> String.trim()
      |> String.downcase()

    existing_emails_lower = Enum.map(socket.assigns.manual_emails, fn e -> String.downcase(e) end)

    if email != "" && valid_email?(email) && !(email in existing_emails_lower) do
      updated_emails = socket.assigns.manual_emails ++ [email]

      {:noreply,
       socket
       |> assign(:manual_emails, updated_emails)
       |> assign(:current_email_input, "")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_email_on_enter", _params, socket) do
    handle_event("add_email", %{}, socket)
  end

  @impl true
  def handle_event("remove_email", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    updated_emails = List.delete_at(socket.assigns.manual_emails, index)

    {:noreply, assign(socket, :manual_emails, updated_emails)}
  end

  @impl true
  def handle_event("clear_all_emails", _params, socket) do
    {:noreply, assign(socket, :manual_emails, [])}
  end

  @impl true
  def handle_event("bulk_email_input", %{"bulk_email_input" => bulk_input}, socket) do
    {:noreply, assign(socket, :bulk_email_input, bulk_input)}
  end

  @impl true
  def handle_event("add_bulk_emails", _params, socket) do
    bulk_input = Map.get(socket.assigns, :bulk_email_input, "")

    existing_set = MapSet.new(Enum.map(socket.assigns.manual_emails, &normalize_email/1))

    new_emails =
      bulk_input
      |> String.split(~r/[,\n]/, trim: true)
      |> Enum.reduce({[], existing_set}, fn piece, {acc, set} ->
        email = String.trim(piece)

        cond do
          email == "" or not valid_email?(email) ->
            {acc, set}

          MapSet.member?(set, normalize_email(email)) ->
            {acc, set}

          true ->
            {[email | acc], MapSet.put(set, normalize_email(email))}
        end
      end)
      |> elem(0)
      |> Enum.reverse()

    updated_emails = socket.assigns.manual_emails ++ new_emails

    {:noreply,
     socket
     |> assign(:manual_emails, updated_emails)
     |> assign(:bulk_email_input, "")}
  end

  @impl true
  def handle_event("toggle_add_mode", %{"mode" => mode}, socket)
      when mode in ["invite", "direct"] do
    {:noreply, assign(socket, :add_mode, mode)}
  end

  @impl true
  def handle_event("send_invitations", _params, socket) do
    event = socket.assigns.event
    organizer = socket.assigns.user
    selected_suggestions = socket.assigns.selected_suggestions
    manual_emails = socket.assigns.manual_emails
    invitation_message = socket.assigns.invitation_message

    # Use manual emails directly (already in list format)
    parsed_emails = manual_emails

    # Get selected suggestion users
    suggested_users =
      socket.assigns.historical_suggestions
      |> Enum.filter(&(&1.user_id in selected_suggestions))

    total_invitations = length(suggested_users) + length(parsed_emails)

    if total_invitations > 0 do
      # Determine mode and process invitations
      mode = if socket.assigns.add_mode == "direct", do: :direct_add, else: :invitation

      result =
        Events.process_guest_invitations(
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
      updated_participants =
        Events.list_event_participants(event)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      # Build error flash if there were failures
      socket_with_errors =
        if result.failed_invitations > 0 do
          error_message =
            "#{result.failed_invitations} invitation(s) failed. #{Enum.join(result.errors, "; ")}"

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
       |> assign(:manual_emails, [])
       |> assign(:current_email_input, "")
       |> put_flash(:info, success_message)}
    else
      {:noreply,
       put_flash(socket, :error, "Please select guests or enter email addresses to invite.")}
    end
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # Prevent modal from closing when clicking inside
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_guests", params, socket) do
    source_filter =
      case Map.get(params, "source_filter") do
        "" -> nil
        source -> source
      end

    status_filter =
      case Map.get(params, "status_filter") do
        "" -> nil
        # Keep as string for combined filtering
        status -> status
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
  def handle_event("toggle_status_menu", %{"participant_id" => participant_id}, socket) do
    case safe_string_to_integer(participant_id) do
      {:ok, participant_id_int} ->
        current_open = socket.assigns.open_status_menu
        new_open = if current_open == participant_id_int, do: nil, else: participant_id_int
        {:noreply, assign(socket, :open_status_menu, new_open)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_status_menu", _params, socket) do
    {:noreply, assign(socket, :open_status_menu, nil)}
  end

  @impl true
  def handle_event(
        "change_participant_status",
        %{"participant_id" => participant_id, "status" => status},
        socket
      ) do
    with {:ok, participant_id_int} <- safe_string_to_integer(participant_id),
         participant when not is_nil(participant) <-
           EventasaurusApp.Repo.get(EventasaurusApp.Events.EventParticipant, participant_id_int),
         {:ok, :same_event} <-
           if(participant.event_id == socket.assigns.event.id,
             do: {:ok, :same_event},
             else: {:error, :wrong_event}
           ),
         {:ok, status_atom} <- EventasaurusApp.Events.EventParticipant.parse_status(status) do
      case Events.admin_update_participant_status(participant, status_atom, socket.assigns.user) do
        {:ok, _updated_participant} ->
          updated_participants =
            Events.list_event_participants(socket.assigns.event,
              limit: socket.assigns.participants_loaded
            )
            |> Enum.sort_by(& &1.inserted_at, :desc)

          {:noreply,
           socket
           |> assign_participants_with_stats(updated_participants)
           |> assign(:open_status_menu, nil)
           |> put_flash(:info, "Participant status updated to #{status}")}

        {:error, :permission_denied} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "You don't have permission to change this participant's status"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update participant status")}
      end
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Participant not found")}

      {:error, :invalid_format} ->
        {:noreply, put_flash(socket, :error, "Invalid participant ID")}

      {:error, :invalid_input} ->
        {:noreply, put_flash(socket, :error, "Invalid participant ID")}

      {:error, :wrong_event} ->
        {:noreply, put_flash(socket, :error, "Participant does not belong to this event")}

      {:error, :invalid_status} ->
        {:noreply, put_flash(socket, :error, "Invalid status")}
    end
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
                 # Close any open dropdown menus
                 |> assign(:open_participant_menu, nil)
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
          updated_participants =
            Events.list_event_participants(event, limit: socket.assigns.participants_loaded)
            |> Enum.sort_by(& &1.inserted_at, :desc)

          {:noreply,
           socket
           |> assign_participants_with_stats(updated_participants)
           |> put_flash(
             :info,
             "Email retry initiated for #{participant.user.name || participant.user.email}"
           )}

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
  def handle_event("send_participant_email", %{"participant_id" => participant_id}, socket) do
    with {:ok, participant_id} <- safe_string_to_integer(participant_id) do
      event = socket.assigns.event
      organizer = socket.assigns.user

      # Find the participant
      participant = Enum.find(socket.assigns.participants, &(&1.id == participant_id))

      if participant && participant.user do
        case Events.queue_single_participant_email(participant, event, organizer) do
          {:ok, _job} ->
            updated_participants =
              Events.list_event_participants(event, limit: socket.assigns.participants_loaded)
              |> Enum.sort_by(& &1.inserted_at, :desc)

            {:noreply,
             socket
             |> assign_participants_with_stats(updated_participants)
             |> assign(:open_participant_menu, nil)
             |> put_flash(
               :info,
               "Email queued for #{participant.user.name || participant.user.email}"
             )}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:open_participant_menu, nil)
             |> put_flash(:error, "Failed to queue email: #{reason}")}
        end
      else
        {:noreply,
         socket
         |> assign(:open_participant_menu, nil)
         |> put_flash(:error, "Participant not found or has no email")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid participant ID")}
    end
  end

  @impl true
  def handle_event("add_guests_directly", _params, socket) do
    event = socket.assigns.event
    organizer = socket.assigns.user
    selected_suggestions = socket.assigns.selected_suggestions
    manual_emails = socket.assigns.manual_emails

    # Use manual emails directly (already in list format)
    parsed_emails = manual_emails

    # Get selected suggestion users
    suggested_users =
      socket.assigns.historical_suggestions
      |> Enum.filter(&(&1.user_id in selected_suggestions))

    total_guests = length(suggested_users) + length(parsed_emails)

    if total_guests > 0 do
      # Use our guest invitation processing but set mode to direct
      result =
        Events.process_guest_invitations(event, organizer,
          suggestion_structs: suggested_users,
          manual_emails: parsed_emails,
          # No message for direct adds
          invitation_message: nil,
          mode: :direct_add
        )

      # Build success message
      success_message = build_direct_add_success_message(result)

      # Reload participants to show updated list
      updated_participants =
        Events.list_event_participants(event)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      # Build error flash if there were failures
      socket_with_errors =
        if result.failed_invitations > 0 do
          error_message =
            "#{result.failed_invitations} addition(s) failed. #{Enum.join(result.errors, "; ")}"

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
       |> assign(:manual_emails, [])
       |> assign(:current_email_input, "")
       |> assign(:invitation_message, "")
       |> put_flash(:info, success_message)}
    else
      {:noreply,
       put_flash(socket, :error, "Please select guests or enter email addresses to add.")}
    end
  end

  @impl true
  def handle_event("load_more_participants", _params, socket) do
    if socket.assigns.participants_loaded < socket.assigns.participants_count do
      socket = assign(socket, :participants_loading, true)

      # Load next batch of participants
      next_batch =
        Events.list_event_participants(
          socket.assigns.event,
          limit: 20,
          offset: socket.assigns.participants_loaded
        )
        |> Enum.sort_by(& &1.inserted_at, :desc)

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

  # Organizer Search Modal Events

  @impl true
  def handle_event("open_organizer_search_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_organizer_search_modal, true)
     |> assign(:organizer_search_query, "")
     |> assign(:organizer_search_results, [])
     |> assign(:organizer_search_loading, false)
     |> assign(:organizer_search_error, nil)
     |> assign(:selected_organizer_results, [])
     |> assign(:organizer_search_offset, 0)
     |> assign(:organizer_search_has_more, false)
     |> assign(:organizer_search_total_shown, 0)}
  end

  @impl true
  def handle_event("close_organizer_search_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_organizer_search_modal, false)
     |> assign(:organizer_search_query, "")
     |> assign(:organizer_search_results, [])
     |> assign(:organizer_search_error, nil)
     |> assign(:selected_organizer_results, [])
     |> assign(:organizer_search_offset, 0)
     |> assign(:organizer_search_has_more, false)
     |> assign(:organizer_search_total_shown, 0)}
  end

  @impl true
  def handle_event("search_organizers", %{"value" => query}, socket) do
    if String.length(String.trim(query)) >= 2 do
      socket =
        socket
        |> assign(:organizer_search_query, query)
        |> assign(:organizer_search_loading, true)
        |> assign(:organizer_search_error, nil)
        # Reset pagination for new search
        |> assign(:organizer_search_offset, 0)
        |> assign(:organizer_search_has_more, false)
        |> assign(:organizer_search_total_shown, 0)

      # Make HTTP request to user search API
      send(self(), {:search_users_for_organizers, query})
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:organizer_search_query, query)
       |> assign(:organizer_search_results, [])
       |> assign(:organizer_search_loading, false)
       |> assign(:organizer_search_offset, 0)
       |> assign(:organizer_search_has_more, false)
       |> assign(:organizer_search_total_shown, 0)}
    end
  end

  @impl true
  def handle_event("toggle_organizer_selection", %{"user_id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    current_selections = socket.assigns.selected_organizer_results

    updated_selections =
      if user_id in current_selections do
        List.delete(current_selections, user_id)
      else
        [user_id | current_selections]
      end

    {:noreply, assign(socket, :selected_organizer_results, updated_selections)}
  end

  @impl true
  def handle_event("load_more_organizers", _params, socket) do
    query = socket.assigns.organizer_search_query

    if String.length(String.trim(query)) >= 2 do
      socket =
        socket
        |> assign(:organizer_search_loading, true)
        |> assign(:organizer_search_error, nil)

      # Load more results with current offset
      send(self(), {:search_users_for_organizers, query, :load_more})
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_selected_organizers", _params, socket) do
    event = socket.assigns.event
    selected_user_ids = socket.assigns.selected_organizer_results

    if length(selected_user_ids) > 0 do
      # Use the new bulk addition function from Events context
      case Events.add_organizers_to_event(event, selected_user_ids) do
        count when count > 0 ->
          # Reload organizers
          updated_organizers = Events.list_event_organizers(event)

          {:noreply,
           socket
           |> assign(:organizers, updated_organizers)
           |> assign(:show_organizer_search_modal, false)
           |> assign(:organizer_search_results, [])
           |> assign(:selected_organizer_results, [])
           |> put_flash(:info, "Successfully added #{count} organizer(s)")}

        0 ->
          {:noreply, put_flash(socket, :info, "All selected users are already organizers")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Please select at least one user to add as an organizer.")}
    end
  end

  @impl true
  def handle_event("remove_organizer", %{"user_id" => user_id}, socket) do
    event = socket.assigns.event
    current_user = socket.assigns.user

    user_id_int = String.to_integer(user_id)

    if user_id_int == current_user.id do
      # Prevent user from removing themselves
      {:noreply, put_flash(socket, :error, "You cannot remove yourself as an organizer.")}
    else
      case EventasaurusApp.Accounts.get_user(user_id_int) do
        nil ->
          {:noreply, put_flash(socket, :error, "User not found.")}

        user ->
          case Events.remove_user_from_event(event, user) do
            {1, _} ->
              # Successfully removed
              updated_organizers = Events.list_event_organizers(event)

              {:noreply,
               socket
               |> assign(:organizers, updated_organizers)
               |> put_flash(
                 :info,
                 "Successfully removed #{user.name || user.email} as an organizer."
               )}

            {0, _} ->
              {:noreply, put_flash(socket, :error, "User is not an organizer of this event.")}

            _ ->
              {:noreply, put_flash(socket, :error, "Failed to remove organizer.")}
          end
      end
    end
  end

  @impl true
  def handle_event("show_poll_creation_modal", _params, socket) do
    # Update the poll integration component to show the creation modal
    send_update(EventasaurusWeb.EventPollIntegrationComponent,
      id: "event-poll-integration",
      showing_creation_modal: true,
      editing_poll: nil
    )

    {:noreply, socket}
  end

  # Event Deletion Handlers

  @impl true
  def handle_event("open_delete_modal", _params, socket) do
    event = socket.assigns.event
    user = socket.assigns.user

    # Check if event can be hard deleted
    can_hard_delete =
      case Events.eligible_for_hard_delete?(event.id, user.id) do
        {:ok, _} -> true
        {:error, _} -> false
      end

    # Get ineligibility reason if applicable
    ineligibility_reason =
      if not can_hard_delete do
        Events.get_hard_delete_ineligibility_reason(event.id, user.id)
      end

    {:noreply,
     socket
     |> assign(:show_delete_modal, true)
     |> assign(:can_hard_delete, can_hard_delete)
     |> assign(:deletion_ineligibility_reason, ineligibility_reason)
     |> assign(:deletion_reason, "")}
  end

  @impl true
  def handle_event("close_delete_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:deletion_reason, "")}
  end

  @impl true
  def handle_event("update_deletion_reason", %{"value" => reason}, socket) do
    {:noreply, assign(socket, :deletion_reason, reason)}
  end

  # Threshold confirmation modal handlers
  @impl true
  def handle_event("open_confirm_threshold_modal", _params, socket) do
    {:noreply, assign(socket, :show_confirm_threshold_modal, true)}
  end

  @impl true
  def handle_event("close_confirm_threshold_modal", _params, socket) do
    {:noreply, assign(socket, :show_confirm_threshold_modal, false)}
  end

  @impl true
  def handle_event("confirm_threshold_event", _params, socket) do
    event = socket.assigns.event

    # Verify the event is in threshold status and threshold is met
    if event.status == :threshold and EventStateMachine.threshold_met?(event) do
      case Events.transition_event(event, :confirmed) do
        {:ok, updated_event} ->
          Logger.info("Event confirmed from threshold status",
            event_id: event.id,
            event_slug: event.slug
          )

          {:noreply,
           socket
           |> assign(:event, updated_event)
           |> assign(:threshold_met, false)
           |> assign(:show_confirm_threshold_modal, false)
           |> put_flash(:info, "Event has been confirmed! Your attendees will be notified.")}

        {:error, reason} ->
          Logger.error("Failed to confirm threshold event",
            event_id: event.id,
            error: inspect(reason)
          )

          {:noreply,
           socket
           |> assign(:show_confirm_threshold_modal, false)
           |> put_flash(:error, "Failed to confirm event. Please try again.")}
      end
    else
      {:noreply,
       socket
       |> assign(:show_confirm_threshold_modal, false)
       |> put_flash(:error, "Event cannot be confirmed - threshold not met or invalid status.")}
    end
  end

  @impl true
  def handle_event("send_threshold_announcement", _params, socket) do
    event = socket.assigns.event
    user = socket.assigns.user

    # Verify the event is in threshold status and threshold is met
    if event.status == :threshold and socket.assigns.threshold_met do
      case ThresholdAnnouncementJob.enqueue(event, user) do
        {:ok, _job} ->
          Logger.info("Threshold announcement job enqueued",
            event_id: event.id,
            organizer_id: user.id
          )

          {:noreply,
           socket
           |> assign(:announcement_sent, true)
           |> put_flash(:info, "We Made It! announcement is being sent to all attendees.")}

        {:error, reason} ->
          Logger.error("Failed to enqueue threshold announcement",
            event_id: event.id,
            error: inspect(reason)
          )

          {:noreply,
           socket
           |> put_flash(:error, "Failed to send announcement. Please try again.")}
      end
    else
      {:noreply,
       socket
       |> put_flash(
         :error,
         "Cannot send announcement - threshold not met or invalid event status."
       )}
    end
  end

  @impl true
  def handle_event("delete_event", _params, socket) do
    event = socket.assigns.event
    user = socket.assigns.user
    deletion_reason = socket.assigns.deletion_reason

    case String.trim(deletion_reason) do
      "" ->
        {:noreply, put_flash(socket, :error, "Please provide a reason for deletion")}

      reason ->
        case Events.delete_event(event.id, user.id, reason) do
          {:ok, :hard_deleted} ->
            # TODO: Re-enable when PosthogService.capture/3 is implemented
            # PosthogService.capture(
            #   to_string(user.id),
            #   "event_deleted",
            #   %{
            #     "event_id" => to_string(event.id),
            #     "event_slug" => event.slug,
            #     "deletion_type" => "hard",
            #     "deletion_reason" => reason
            #   }
            # )

            {:noreply,
             socket
             |> put_flash(:info, "Event has been permanently deleted")
             |> redirect(to: ~p"/dashboard")}

          {:ok, :soft_deleted} ->
            # TODO: Re-enable when PosthogService.capture/3 is implemented
            # PosthogService.capture(
            #   to_string(user.id),
            #   "event_deleted",
            #   %{
            #     "event_id" => to_string(event.id),
            #     "event_slug" => event.slug,
            #     "deletion_type" => "soft",
            #     "deletion_reason" => reason
            #   }
            # )

            {:noreply,
             socket
             |> put_flash(
               :info,
               "Event has been archived and can be restored by an administrator"
             )
             |> redirect(to: ~p"/dashboard")}

          {:error, :permission_denied} ->
            {:noreply,
             put_flash(socket, :error, "You don't have permission to delete this event")}

          {:error, :event_not_found} ->
            {:noreply, put_flash(socket, :error, "Event not found")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete event: #{reason}")}
        end
    end
  end

  # Handle PubSub messages for real-time threshold updates

  @impl true
  def handle_info({:order_update, %{order: order, action: _action}}, socket) do
    # Only update if this order is for our event and we're in threshold status
    event = socket.assigns.event

    if event.status == :threshold and order.event_id == event.id do
      # Refresh threshold status - dashboard updates in real-time
      # Note: Announcement emails to attendees are organizer-triggered via "Announce to Attendees" button
      threshold_met = EventStateMachine.threshold_met?(event)

      {:noreply,
       socket
       |> assign(:threshold_met, threshold_met)
       |> maybe_refresh_orders(event)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:ticket_update, _data}, socket) do
    # Ticket updates may affect availability but not threshold directly
    # Just acknowledge the message
    {:noreply, socket}
  end

  @impl true
  def handle_info({:poll_activity, _activity_type, _poll, _user}, socket) do
    # Poll activity doesn't affect threshold - just acknowledge
    {:noreply, socket}
  end

  @impl true
  def handle_info({:participant_update, _data}, socket) do
    # Participant updates may affect attendee-based thresholds
    # Dashboard updates in real-time; announcement emails are organizer-triggered
    event = socket.assigns.event

    if event.status == :threshold do
      threshold_met = EventStateMachine.threshold_met?(event)
      {:noreply, assign(socket, :threshold_met, threshold_met)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:poll_saved, poll, %{action: action, message: message}}, socket) do
    # Reload polls data to include the new poll with consistent ordering
    polls = Events.list_polls(socket.assigns.event)

    # Update the poll integration component to close the modal
    send_update(EventasaurusWeb.EventPollIntegrationComponent,
      id: "event-poll-integration",
      showing_creation_modal: false,
      editing_poll: nil
    )

    # Smart redirect: For new poll creation, redirect to poll details view
    # For poll edits, just close the modal
    if action == :created do
      {:noreply,
       socket
       |> assign(:polls, polls)
       |> assign(:editing_poll, nil)
       |> assign(:selected_poll, poll)
       |> assign(:show_poll_details, true)
       |> put_flash(:info, "Poll created successfully! Add options to get started.")}
    else
      {:noreply,
       socket
       |> assign(:polls, polls)
       |> assign(:editing_poll, nil)
       |> assign(:selected_poll, nil)
       |> assign(:show_poll_details, false)
       |> put_flash(:info, message)}
    end
  end

  # Fallback for old message format (backward compatibility)
  @impl true
  def handle_info({:poll_saved, poll, message}, socket) when is_binary(message) do
    # Use pattern matching instead of String.contains for better performance and safety
    action = if message =~ ~r/created/i, do: :created, else: :updated
    handle_info({:poll_saved, poll, %{action: action, message: message}}, socket)
  end

  @impl true
  def handle_info({:view_poll_details, poll}, socket) do
    # Handle poll viewing/editing - MUST set active_tab to "polls"
    {:noreply,
     socket
     |> assign(:selected_poll, poll)
     |> assign(:show_poll_details, true)
     |> assign(:active_tab, "polls")}
  end

  @impl true
  def handle_info({:edit_poll, poll}, socket) do
    # Handle poll editing (similar to view_poll for now)
    {:noreply,
     socket
     |> assign(:selected_poll, poll)
     |> assign(:show_poll_details, true)
     |> assign(:editing_poll, poll)}
  end

  @impl true
  def handle_info({:delete_poll, poll}, socket) do
    case Events.delete_poll(poll) do
      {:ok, _deleted_poll} ->
        # Reload event data to refresh polls list
        event =
          Events.get_event!(socket.assigns.event.id)
          |> EventasaurusApp.Repo.preload([:polls])

        {:noreply,
         socket
         |> assign(:event, event)
         |> put_flash(:info, "Poll deleted successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete poll")}
    end
  end

  @impl true
  def handle_info({:show_error, message}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, message)}
  end

  @impl true
  def handle_info({:poll_deleted, _poll}, socket) do
    # Reload event data to refresh polls list
    event =
      Events.get_event!(socket.assigns.event.id)
      |> EventasaurusApp.Repo.preload([:polls])

    {:noreply,
     socket
     |> assign(:event, event)
     |> assign(:show_poll_details, false)
     |> assign(:selected_poll, nil)
     |> put_flash(:info, "Poll deleted successfully")}
  end

  @impl true
  def handle_info({:close_poll_editing}, socket) do
    {:noreply,
     socket
     |> assign(:editing_poll, nil)}
  end

  @impl true
  def handle_info({:show_create_poll_modal, _event}, socket) do
    # Handle poll creation modal request from component
    send_update(EventasaurusWeb.EventPollIntegrationComponent,
      id: "event-poll-integration",
      showing_creation_modal: true,
      editing_poll: nil,
      template_data: nil
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:show_create_poll_modal_with_template, _event, template}, socket) do
    # Handle poll creation modal with template pre-fill
    send_update(EventasaurusWeb.EventPollIntegrationComponent,
      id: "event-poll-integration",
      showing_creation_modal: true,
      editing_poll: nil,
      template_data: template
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:open_template_editor, suggestion}, socket) do
    # Forward the template editor request to the EventPollIntegrationComponent
    send_update(EventasaurusWeb.EventPollIntegrationComponent,
      id: "event-poll-integration",
      showing_template_editor: true,
      template_suggestion: suggestion
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:create_poll_from_template, poll_data}, socket) do
    # Create the poll from template
    event = socket.assigns.event
    user = socket.assigns.user

    # Debug: Log first option to see what data we're receiving
    first_option = List.first(poll_data.options)

    if first_option do
      IO.puts("\n=== DEBUG: First option in create_poll_from_template ===")

      cond do
        is_map(first_option) ->
          IO.puts("Title: #{inspect(first_option["title"] || first_option[:title])}")
          IO.puts("Image URL: #{inspect(first_option["image_url"] || first_option[:image_url])}")

          IO.puts(
            "Description: #{inspect(first_option["description"] || first_option[:description])}"
          )

        is_binary(first_option) ->
          IO.puts("Title (string option): #{inspect(first_option)}")

        true ->
          IO.puts("First option (unexpected type): #{inspect(first_option, pretty: true)}")
      end

      IO.puts("Full option: #{inspect(first_option, pretty: true)}")
    end

    poll_attrs = %{
      title: poll_data.title,
      poll_type: poll_data.poll_type,
      voting_system: poll_data.voting_system,
      phase: :setup,
      event_id: event.id,
      created_by_id: user.id
    }

    case Events.create_poll(poll_attrs) do
      {:ok, poll} ->
        # Create poll options separately with full metadata preservation
        option_results =
          poll_data.options
          |> Enum.with_index()
          |> Enum.map(fn {option_data, index} ->
            # Handle both old string format and new map format
            option_attrs =
              if is_binary(option_data) do
                %{
                  title: option_data,
                  poll_id: poll.id,
                  suggested_by_id: user.id,
                  order_index: index
                }
              else
                # New format - full metadata map
                %{
                  title: option_data["title"] || option_data[:title],
                  poll_id: poll.id,
                  suggested_by_id: user.id,
                  order_index: index,
                  description: option_data["description"] || option_data[:description],
                  image_url: option_data["image_url"] || option_data[:image_url],
                  external_id: option_data["external_id"] || option_data[:external_id],
                  external_data: option_data["external_data"] || option_data[:external_data],
                  metadata: option_data["metadata"] || option_data[:metadata]
                }
                # Remove nil values
                |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
                |> Enum.into(%{})
              end

            Events.create_poll_option(option_attrs)
          end)

        # Check if all options were created successfully
        failed_options =
          Enum.filter(option_results, fn
            {:error, _} -> true
            _ -> false
          end)

        if Enum.empty?(failed_options) do
          # Success - reload polls and update the component
          polls = Events.list_polls(event)

          send_update(EventasaurusWeb.EventPollIntegrationComponent,
            id: "event-poll-integration",
            polls: polls,
            showing_template_editor: false,
            template_suggestion: nil
          )

          {:noreply,
           socket
           |> put_flash(:info, "Poll created from template successfully!")
           |> assign(:polls, polls)}
        else
          # Some options failed to create
          {:noreply,
           put_flash(
             socket,
             :error,
             "Poll created but some options failed to save. Please add them manually."
           )}
        end

      {:error, changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, "Failed to create poll: #{errors}")}
    end
  end

  @impl true
  def handle_info({:close_poll_creation_modal}, socket) do
    # Update the poll integration component to close the modal
    send_update(EventasaurusWeb.EventPollIntegrationComponent,
      id: "event-poll-integration",
      showing_creation_modal: false,
      editing_poll: nil
    )

    {:noreply,
     socket
     |> assign(:editing_poll, nil)
     |> assign(:selected_poll, nil)
     |> assign(:show_poll_details, false)}
  end

  @impl true
  def handle_info({:close_poll_details}, socket) do
    # Close poll details view and go back to overview
    {:noreply,
     socket
     |> assign(:selected_poll, nil)
     |> assign(:show_poll_details, false)}
  end

  @impl true
  def handle_info({:hide_dropdown, _id}, socket) do
    # Handle dropdown hide events from components
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{type: :option_suggested} = _message, socket) do
    # Option was successfully added (from PubSub) - refresh poll data
    {:noreply,
     socket
     |> load_poll_data()
     |> put_flash(:info, "Option added successfully")}
  end

  @impl true
  def handle_info({:option_updated, _option}, socket) do
    # Option was successfully updated (from component) - refresh poll data
    {:noreply,
     socket
     |> load_poll_data()
     |> put_flash(:info, "Option updated successfully")}
  end

  @impl true
  def handle_info({:option_removed, _option_id}, socket) do
    # Option was successfully removed (from component) - refresh poll data
    {:noreply,
     socket
     |> load_poll_data()
     |> put_flash(:info, "Option removed successfully")}
  end

  @impl true
  def handle_info({:edit_option, option_id}, socket) do
    # Edit option action triggered (from component) - trigger edit mode in component
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        case Events.get_poll_option(option_id_int) do
          %PollOption{} = option ->
            # Send update to the component to enable edit mode for this option
            send_update(EventasaurusWeb.OptionSuggestionComponent,
              id: "poll-options-#{option.poll_id}",
              editing_option_id: option.id
            )

            {:noreply, socket}

          nil ->
            {:noreply, put_flash(socket, :error, "Option not found")}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Invalid option ID")}
    end
  end

  @impl true
  def handle_info({:poll_phase_changed, _poll, message}, socket) do
    # Poll phase changed (from component) - refresh poll data and show message
    {:noreply,
     socket
     |> load_poll_data()
     |> put_flash(:info, message)}
  end

  @impl true
  def handle_info({:option_reordered, message}, socket) do
    # Options were reordered (from component) - refresh poll data and show message
    {:noreply,
     socket
     |> load_poll_data()
     |> put_flash(:info, message)}
  end

  @impl true
  def handle_info({:search_results, _query, _results}, socket) do
    # Search results from component - just acknowledge for now
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{type: :duplicate_detected} = _message, socket) do
    # Duplicate option detected - just acknowledge for now
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{type: :poll_counters_updated} = _message, socket) do
    # Poll counters updated - just acknowledge for now
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{type: :participant_joined} = _message, socket) do
    # New participant joined - just acknowledge for now
    {:noreply, socket}
  end

  @impl true
  def handle_info({:js_push, _command, _params, _id}, socket) do
    # Handle JavaScript push commands - for now just acknowledge
    {:noreply, socket}
  end

  # Handle RichDataSearchComponent selection messages and forward to ActivityCreationComponent
  def handle_info(
        {EventasaurusWeb.RichDataSearchComponent, :selection_made, event_name, data},
        socket
      ) do
    require Logger

    Logger.debug(
      "EventManageLive: Received selection_made event: #{event_name} for #{Map.get(data, :title, "unknown")}"
    )

    # Forward the selection to the ActivityCreationComponent
    send_update(EventasaurusWeb.ActivityCreationComponent,
      id: "activity-creation-#{socket.assigns.event.id}",
      action: event_name,
      data: data
    )

    Logger.debug("EventManageLive: Forwarded to ActivityCreationComponent")
    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_historical_suggestions, socket) do
    event = socket.assigns.event
    organizer = socket.assigns.user

    try do
      # Get current participants' user IDs to exclude them from suggestions
      current_participant_user_ids =
        socket.assigns.participants
        |> Enum.map(& &1.user_id)

      # Get historical participants using our guest invitation module
      suggestions =
        Events.get_participant_suggestions(organizer,
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

        Logger.error(
          "Guest invitation modal crashed while loading suggestions: #{inspect(error)}"
        )

        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        Logger.error("Socket assigns: event=#{event.id}, user=#{organizer.id}")

        {:noreply,
         socket
         |> assign(:historical_suggestions, [])
         |> assign(:suggestions_loading, false)
         |> put_flash(:error, "Failed to load suggestions")}
    end
  end

  # Generic handler for poll data refresh events (catch-all)
  @impl true
  def handle_info(message, socket) when is_map(message) or is_tuple(message) do
    case extract_event_info(message) do
      {:poll_data_refresh, flash_message} ->
        {:noreply,
         socket
         |> load_poll_data()
         |> put_flash(:info, flash_message)}

      {:poll_data_refresh_no_flash} ->
        {:noreply, load_poll_data(socket)}

      {:error_flash, error_message} ->
        {:noreply, put_flash(socket, :error, error_message)}

      :acknowledge_only ->
        {:noreply, socket}

      :unhandled ->
        # Fallback for unhandled messages - call original handlers
        handle_specific_message(message, socket)
    end
  end

  # Helper functions

  # Helper to optionally refresh orders data
  defp maybe_refresh_orders(socket, event) do
    orders =
      Ticketing.list_orders_for_event(event.id)
      |> EventasaurusApp.Repo.preload([:ticket, :user])

    assign(socket, :orders, orders)
  end

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

  # Helper function to extract flash message info from event types

  defp count_by_source(participants, "direct_add") do
    Enum.count(
      participants,
      &(is_binary(&1.source) && String.starts_with?(&1.source, "direct_add"))
    )
  end

  defp count_by_source(participants, source) do
    Enum.count(participants, &(&1.source == source))
  end

  defp count_invited(participants) do
    Enum.count(
      participants,
      &(&1.invited_at != nil &&
          !(is_binary(&1.source) && String.starts_with?(&1.source, "direct_add")))
    )
  end

  defp count_by_status(participants, status) do
    Enum.count(participants, &(&1.status == status))
  end

  defp fetch_analytics_data(event_id) do
    try do
      case PosthogService.get_analytics(event_id, 30) do
        {:ok, data} ->
          data

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
      timezone = event.timezone || TimezoneUtils.default_timezone()
      # Convert UTC time to event's timezone for display
      shifted_datetime = DateTimeHelper.utc_to_timezone(event.start_at, timezone)

      date = Calendar.strftime(shifted_datetime, "%A, %B %d, %Y")
      time = Calendar.strftime(shifted_datetime, "%H:%M")

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

  defp valid_email?(email) do
    String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
  end

  defp normalize_email(email), do: String.downcase(email)

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
        (p.invited_at != nil && is_binary(p.source) &&
           !String.starts_with?(p.source, "direct_add"))
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

      :interested ->
        {"Interested", "bg-sky-100 text-sky-800"}

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

      diff_seconds < 2_592_000 ->
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
      %{user: %{name: name}} when is_binary(name) ->
        name

      _ ->
        # Fallback to direct database lookup if inviter not in participant list
        case EventasaurusApp.Accounts.get_user(inviter_id) do
          %{name: name} when is_binary(name) -> name
          _ -> "Unknown"
        end
    end
  end

  # Poll data loading function
  defp load_poll_data(socket) do
    event = socket.assigns.event

    try do
      # Load all polls for the event safely with order_index ordering from database
      polls =
        case Events.list_polls(event) do
          polls when is_list(polls) ->
            # Keep the order_index ordering from the database query
            polls

          _ ->
            []
        end

      # Get poll statistics safely
      poll_stats =
        case Events.get_event_poll_stats(event) do
          %{total_participants: total_participants} when is_integer(total_participants) ->
            %{total_participants: total_participants}

          _ ->
            %{total_participants: 0}
        end

      socket
      |> assign(:polls, polls)
      |> assign(:polls_count, length(polls))
      |> assign(:total_poll_participants, poll_stats.total_participants)
      |> assign(:total_votes, count_total_votes(polls))
      |> assign(:polls_loading, false)
    rescue
      error ->
        Logger.error("Failed to load poll data: #{inspect(error)}")

        socket
        |> assign(:polls, [])
        |> assign(:polls_count, 0)
        |> assign(:total_poll_participants, 0)
        |> assign(:total_votes, 0)
        |> assign(:polls_loading, false)
        |> put_flash(:error, "Failed to load poll data")
    end
  end

  defp load_poll_count(event) do
    try do
      # Use efficient count query instead of loading all polls
      Events.count_polls_for_event(event)
    rescue
      _ -> 0
    end
  end

  defp count_total_votes(polls) when is_list(polls) do
    try do
      polls
      |> Enum.flat_map(fn poll ->
        case Map.get(poll, :poll_options) do
          options when is_list(options) -> options
          _ -> []
        end
      end)
      |> Enum.flat_map(fn option ->
        case Map.get(option, :votes) do
          votes when is_list(votes) -> votes
          _ -> []
        end
      end)
      |> length()
    rescue
      _ -> 0
    end
  end

  defp count_total_votes(_), do: 0

  defp safe_string_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_format}
    end
  end

  defp safe_string_to_integer(_), do: {:error, :invalid_input}

  # Helper to extract event information from messages
  defp extract_event_info({:option_suggested, _}),
    do: {:poll_data_refresh, "Option added successfully"}

  defp extract_event_info(%{type: :option_suggested}),
    do: {:poll_data_refresh, "Option added successfully"}

  defp extract_event_info({:option_updated, _}),
    do: {:poll_data_refresh, "Option updated successfully"}

  defp extract_event_info({:option_removed, _}),
    do: {:poll_data_refresh, "Option removed successfully"}

  defp extract_event_info({:poll_phase_changed, _, message}), do: {:poll_data_refresh, message}
  defp extract_event_info({:option_reordered, message}), do: {:poll_data_refresh, message}

  defp extract_event_info(%{type: :option_visibility_changed}),
    do: {:poll_data_refresh, "Option updated successfully"}

  defp extract_event_info(%{type: :poll_phase_changed}),
    do: {:poll_data_refresh, "Poll phase updated"}

  defp extract_event_info(%{type: :options_reordered}),
    do: {:poll_data_refresh, "Options reordered successfully"}

  defp extract_event_info(%{type: :bulk_moderation_action}),
    do: {:poll_data_refresh, "Options updated successfully"}

  defp extract_event_info({:show_error, message}), do: {:error_flash, message}
  defp extract_event_info({:search_results, _, _}), do: :acknowledge_only
  defp extract_event_info(%{type: :duplicate_detected}), do: :acknowledge_only
  defp extract_event_info(%{type: :poll_counters_updated}), do: :acknowledge_only
  defp extract_event_info(%{type: :participant_joined}), do: :acknowledge_only
  defp extract_event_info({:js_push, _, _, _}), do: :acknowledge_only
  defp extract_event_info({:perform_external_search, _, _}), do: :acknowledge_only
  defp extract_event_info({:hide_dropdown, _}), do: :acknowledge_only
  defp extract_event_info(_), do: :unhandled

  # Handle organizer search functionality
  defp handle_organizer_search(query, socket, mode) do
    event = socket.assigns.event
    current_user = socket.assigns.user

    # Determine offset based on mode
    offset =
      case mode do
        :new_search -> 0
        :load_more -> socket.assigns[:organizer_search_offset] || 0
      end

    # Search for users
    search_opts = [
      limit: 20,
      offset: offset,
      exclude_user_id: current_user.id,
      event_id: event.id
    ]

    case Accounts.search_users_for_organizers(query, search_opts) do
      users when is_list(users) ->
        # Format users for display
        formatted_users =
          Enum.map(users, fn user ->
            %{
              "id" => user.id,
              "name" => user.name,
              "email" => user.email,
              "username" => user.username,
              "avatar_url" => EventasaurusApp.Avatars.generate_user_avatar(user, size: 40)
            }
          end)

        # Update results based on mode
        updated_results =
          case mode do
            :new_search -> formatted_users
            :load_more -> (socket.assigns[:organizer_search_results] || []) ++ formatted_users
          end

        {:noreply,
         socket
         |> assign(:organizer_search_results, updated_results)
         |> assign(:organizer_search_loading, false)
         |> assign(:organizer_search_offset, offset + length(users))
         |> assign(:organizer_search_has_more, length(users) == 20)
         |> assign(:organizer_search_total_shown, length(updated_results))}

      _ ->
        {:noreply,
         socket
         |> assign(:organizer_search_loading, false)
         |> assign(:organizer_search_error, "Failed to search users")}
    end
  end

  # Handle specific messages that need custom logic
  defp handle_specific_message({:edit_option, option_id}, socket) do
    # Delegate to the existing handle_info implementation to avoid duplication
    handle_info({:edit_option, option_id}, socket)
  end

  defp handle_specific_message({:selected_dates_changed, _dates}, socket) do
    # Calendar date changes in suggestion forms - just acknowledge
    # The OptionSuggestionComponent handles the dates internally
    {:noreply, socket}
  end

  defp handle_specific_message(
         {:save_date_time_slots, %{date: _date, time_slots: _time_slots}},
         socket
       ) do
    # Time slot changes from TimeSlotPickerComponent - just acknowledge
    # The component handles the time slots internally
    {:noreply, socket}
  end

  defp handle_specific_message({:search_users_for_organizers, query}, socket) do
    # Perform the organizer search
    handle_organizer_search(query, socket, :new_search)
  end

  defp handle_specific_message({:activity_deleted, _activity}, socket) do
    # Activity deletion handled by the component, just acknowledge
    {:noreply, socket}
  end

  defp handle_specific_message({:search_users_for_organizers, query, :load_more}, socket) do
    # Load more results for organizer search
    handle_organizer_search(query, socket, :load_more)
  end

  defp handle_specific_message({:reload_activities}, socket) do
    # Reload activities when a new activity is added
    send_update(EventasaurusWeb.EventHistoryComponent,
      id: "event-history-#{socket.assigns.event.id}",
      event: socket.assigns.event,
      # Reset modal state
      show_activity_creation: false,
      # Clear any editing state to prevent edit form from showing on next open
      editing_activity: nil
    )

    {:noreply, socket}
  end

  defp handle_specific_message(
         %{type: :polls_reordered, event_id: event_id, updated_polls: _updated_polls},
         socket
       ) do
    # Reload polls from the database to get the updated order
    event = socket.assigns.event

    if event.id == event_id do
      # Reload polls with the new order
      polls = Events.list_polls(event)

      {:noreply, assign(socket, :polls, polls)}
    else
      {:noreply, socket}
    end
  end

  # Status validation now handled by EventParticipant.parse_status/1
  # This eliminates duplication and uses schema as single source of truth

  # Check if a threshold announcement has already been sent for this event
  # by looking for completed or pending announcement jobs in Oban
  defp check_announcement_sent(event) do
    import Ecto.Query

    # Check for any threshold announcement jobs for this event (completed, available, or executing)
    # This prevents duplicate announcements
    query =
      from(j in Oban.Job,
        where:
          j.worker == "Eventasaurus.Jobs.ThresholdAnnouncementJob" and
            fragment("?->>'event_id' = ?", j.args, ^to_string(event.id)) and
            fragment("?->>'notification_type' = ?", j.args, "threshold_announcement") and
            j.state in ["completed", "available", "executing", "scheduled", "retryable"],
        limit: 1
      )

    case EventasaurusApp.Repo.one(query) do
      nil -> false
      _job -> true
    end
  end
end
