defmodule EventasaurusWeb.PublicEventLive do
  use EventasaurusWeb, :live_view

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]

  require Logger

  alias EventasaurusWeb.NotFoundError
  alias EventasaurusApp.Events
  alias EventasaurusApp.Groups
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Ticketing
  alias EventasaurusWeb.EventRegistrationComponent
  alias EventasaurusWeb.AnonymousVoterComponent
  alias EventasaurusWeb.PublicGenericPollComponent
  alias EventasaurusWeb.PresentedByComponent
  alias EventasaurusWeb.StaticMapComponent

  alias EventasaurusWeb.ReservedSlugs
  alias EventasaurusWeb.EventAttendeesModalComponent
  alias EventasaurusWeb.ConnectWithContextModalComponent

  import EventasaurusWeb.EventComponents, only: [ticket_selection_component: 1]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    IO.puts("=== MOUNT FUNCTION CALLED ===")
    IO.puts("auth_user: #{inspect(socket.assigns.auth_user)}")
    require Logger

    Logger.debug(
      "PublicEventLive.mount called with auth_user: #{inspect(socket.assigns.auth_user)}"
    )

    if ReservedSlugs.reserved?(slug) do
      raise NotFoundError, "Event not found"
    else
      case Events.get_event_by_slug(slug) do
        nil ->
          raise NotFoundError, "Event not found"

        event ->
          # Load venue if needed
          venue = if event.venue_id, do: Venues.get_venue(event.venue_id), else: nil

          # Load group if event belongs to one
          group = if event.group_id, do: Groups.get_group(event.group_id), else: nil

          organizers = Events.list_event_organizers(event)

          # Load participants for social proof
          participants = Events.list_event_participants(event)

          # Load tickets for events that have ticket types (ticketed_event or contribution_collection)
          should_show_tickets =
            event.taxation_type in ["ticketed_event", "contribution_collection"]

          tickets =
            if should_show_tickets do
              Ticketing.list_tickets_for_event(event.id)
            else
              []
            end

          # Subscribe to real-time ticket updates for events with tickets
          subscribed_to_tickets =
            if should_show_tickets do
              Ticketing.subscribe()
              true
            else
              false
            end

          # Determine registration status if user is authenticated
          Logger.debug("PublicEventLive.mount - auth_user: #{inspect(socket.assigns.auth_user)}")

          {registration_status, user, user_participant_status} =
            case ensure_user_struct(socket.assigns.auth_user) do
              {:ok, user} ->
                Logger.debug("PublicEventLive.mount - user found: #{inspect(user)}")
                status = Events.get_user_registration_status(event, user)
                participant_status = Events.get_user_participant_status(event, user)

                Logger.debug(
                  "PublicEventLive.mount - registration status: #{inspect(status)}, participant status: #{inspect(participant_status)}"
                )

                {status, user, participant_status}

              {:error, reason} ->
                Logger.debug("PublicEventLive.mount - no user found, reason: #{inspect(reason)}")
                {:not_authenticated, nil, nil}
            end

          # Legacy date polling removed - now using generic polling system

          # Apply event theme to layout
          theme = event.theme || :minimal

          # Prepare meta tag data for social sharing
          event_url = url(socket, ~p"/#{event.slug}")

          # Use movie backdrop as social image if available, otherwise use default
          social_image_url =
            if event.rich_external_data && event.rich_external_data["metadata"] &&
                 event.rich_external_data["metadata"]["backdrop_path"] do
              backdrop_path = event.rich_external_data["metadata"]["backdrop_path"]

              if is_binary(backdrop_path) && backdrop_path != "" do
                EventasaurusWeb.Live.Components.RichDataDisplayComponent.tmdb_image_url(
                  backdrop_path,
                  "w1280"
                )
              else
                social_card_url(socket, event)
              end
            else
              social_card_url(socket, event)
            end

          # Enhanced description with movie data
          description =
            if event.rich_external_data && event.rich_external_data["title"] do
              movie_title = event.rich_external_data["title"]
              movie_overview = event.rich_external_data["metadata"]["overview"]

              base_description = event.description || "Join us for #{event.title}"

              movie_description =
                if movie_overview && String.length(movie_overview) > 0 do
                  truncated_overview = String.slice(movie_overview, 0, 200)

                  if String.length(movie_overview) > 200,
                    do: truncated_overview <> "...",
                    else: truncated_overview
                else
                  "A special screening of #{movie_title}"
                end

              "#{base_description} - #{movie_description}"
            else
              truncate_description(event.description || "Join us for #{event.title}")
            end

          {:ok,
           socket
           |> assign(:event, event)
           |> assign(:venue, venue)
           |> assign(:group, group)
           |> assign(:organizers, organizers)
           |> assign(:participants, participants)
           |> assign(:registration_status, registration_status)
           |> assign(:user, user)
           |> assign(:user_participant_status, user_participant_status)
           |> assign(:theme, theme)
           |> assign(:show_registration_modal, false)
           |> assign(:just_registered, false)
           |> assign(:page_title, event.title)
           # Legacy date polling assigns removed
           |> assign(:pending_vote, nil)
           |> assign(:show_vote_modal, false)
           # Legacy temp_votes removed
           # Map of poll_id => temp_votes for generic polls
           |> assign(:poll_temp_votes, %{})
           # Show generic poll vote modal
           |> assign(:show_generic_vote_modal, false)
           # Current poll for modal
           |> assign(:modal_poll, nil)
           # Temp votes for modal
           |> assign(:modal_temp_votes, %{})
           |> assign(:show_interest_modal, false)
           # Attendees modal for viewing fellow attendees and connecting
           |> assign(:show_attendees_modal, false)
           # Version counter to force re-render when relationships change
           |> assign(:relationships_version, 0)
           # Connect modal for adding context when connecting
           |> assign(:show_connect_modal, false)
           |> assign(:connect_modal_user, nil)
           |> assign(:connect_modal_context, nil)
           |> assign(:tickets, tickets)
           # Map of ticket_id => quantity
           |> assign(:selected_tickets, %{})
           |> assign(:ticket_loading, false)
           |> assign(:subscribed_to_tickets, subscribed_to_tickets)
           |> assign(:should_show_tickets, should_show_tickets)
           # Meta tag data for social sharing
           |> assign(:meta_title, event.title)
           |> assign(:meta_description, description)
           |> assign(:meta_image, social_image_url)
           |> assign(:meta_url, event_url)
           |> assign(:structured_data, generate_structured_data(event, event_url))
           # Load event polls for display
           |> load_event_polls()
           # Subscribe to poll statistics updates for real-time voting stats
           |> subscribe_to_poll_stats()
           # Track event page view
           |> push_event("track_event", %{
             event: "event_page_viewed",
             properties: %{
               event_id: event.id,
               event_title: event.title,
               event_slug: event.slug,
               is_ticketed: event.is_ticketed,
               has_date_polling: event.status == :polling,
               user_type: if(user, do: "authenticated", else: "anonymous"),
               registration_status: registration_status,
               theme: theme
             }
           })}
      end
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Extract base URL from the current request URI for Open Graph tags
    base_url = get_base_url_from_uri(uri)

    # Update meta_image and canonical_url with correct base URL if event exists
    socket =
      if socket.assigns[:event] do
        event = socket.assigns.event

        # Regenerate social card URL with actual base URL
        hash_path = EventasaurusWeb.SocialCardView.social_card_url(event)

        socket
        |> assign(:meta_image, "#{base_url}#{hash_path}")
        |> assign(:canonical_url, "#{base_url}/#{event.slug}")
      else
        socket
      end

    {:noreply, assign(socket, :current_uri, uri)}
  end

  # Extract base URL from URI, forcing HTTPS for non-localhost hosts
  # This works with ngrok, Cloudflare, and other proxies that terminate SSL
  defp get_base_url_from_uri(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    if parsed.scheme && parsed.host do
      # Force HTTPS for external domains (ngrok, production), allow HTTP for localhost
      scheme = if parsed.host in ["localhost", "127.0.0.1"], do: parsed.scheme, else: "https"
      port_part = if parsed.port && parsed.port not in [80, 443], do: ":#{parsed.port}", else: ""
      "#{scheme}://#{parsed.host}#{port_part}"
    else
      # Fallback to endpoint URL
      EventasaurusWeb.Endpoint.url()
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Clean up PubSub subscription when LiveView terminates
    if socket.assigns[:subscribed_to_tickets] do
      Ticketing.unsubscribe()
    end

    :ok
  end

  # ==================== EVENT HANDLERS ====================
  # All handle_event/3 functions grouped together to avoid compilation issues

  @impl true
  def handle_event("save_all_votes", _params, socket) do
    # Only for anonymous users with temporary votes
    case ensure_user_struct(socket.assigns.auth_user) do
      {:error, _} when map_size(socket.assigns.temp_votes) > 0 ->
        {:noreply, assign(socket, :show_vote_modal, true)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("poll_location_cleared", _params, socket) do
    # Handle location clearing for poll suggestions - no action needed, just acknowledge
    {:noreply, socket}
  end

  def handle_event("one_click_register", _params, socket) do
    handle_event("register_with_status", %{"status" => "accepted"}, socket)
  end

  def handle_event("register_with_status", %{"status" => status}, socket) do
    status_atom = String.to_atom(status)

    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        # Check if user wants to remove existing status (toggle off)
        current_status = socket.assigns.user_participant_status

        action_result =
          if current_status == status_atom do
            # User has this status already, remove it
            Events.remove_user_participant_status(socket.assigns.event, user)
          else
            # User either has no status or different status, set new one
            Events.update_user_participant_status(socket.assigns.event, user, status_atom)
          end

        case action_result do
          {:ok, _} ->
            # Reload participants to show updated count and list
            updated_participants = Events.list_event_participants(socket.assigns.event)
            new_user_status = Events.get_user_participant_status(socket.assigns.event, user)

            message =
              if current_status == status_atom do
                case status_atom do
                  :accepted -> "Registration cancelled."
                  :interested -> "Interest removed."
                  _ -> "Status removed."
                end
              else
                case status_atom do
                  :accepted -> "You're now registered for #{socket.assigns.event.title}!"
                  :interested -> "Thanks for your interest in #{socket.assigns.event.title}!"
                  _ -> "Your status has been updated!"
                end
              end

            {:noreply,
             socket
             |> assign(
               :registration_status,
               Events.get_user_registration_status(socket.assigns.event, user)
             )
             |> assign(:user_participant_status, new_user_status)
             |> assign(:just_registered, false)
             |> assign(:participants, updated_participants)
             |> put_flash(:info, message)
             |> push_event("track_event", %{
               event: "participant_status_updated",
               properties: %{
                 event_id: socket.assigns.event.id,
                 event_title: socket.assigns.event.title,
                 event_slug: socket.assigns.event.slug,
                 user_type: "authenticated",
                 status: if(current_status == status_atom, do: :removed, else: status_atom),
                 registration_method: "one_click"
               }
             })}

          {:error, :not_found} when current_status == status_atom ->
            {:noreply,
             socket
             |> put_flash(:info, "Status already removed.")}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to update status: #{inspect(reason)}")}
        end

      {:error, _} ->
        # For unauthenticated users, show the registration modal with intended status
        {:noreply,
         socket |> assign(:show_registration_modal, true) |> assign(:intended_status, status_atom)}
    end
  end

  def handle_event("cancel_registration", _params, socket) do
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        case Events.cancel_user_registration(socket.assigns.event, user) do
          {:ok, _participant} ->
            # Reload participants to show updated count and list
            updated_participants = Events.list_event_participants(socket.assigns.event)

            {:noreply,
             socket
             |> assign(:registration_status, :cancelled)
             |> assign(:just_registered, false)
             |> assign(:participants, updated_participants)
             |> put_flash(:info, "Your registration has been cancelled.")}

          {:error, :not_registered} ->
            {:noreply,
             socket
             |> put_flash(:error, "You're not registered for this event.")}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to cancel registration: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please log in to manage your registration.")}
    end
  end

  def handle_event("reregister", _params, socket) do
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        case Events.reregister_user_for_event(socket.assigns.event, user) do
          {:ok, _participant} ->
            # Reload participants to show updated count and list
            updated_participants = Events.list_event_participants(socket.assigns.event)

            {:noreply,
             socket
             |> assign(:registration_status, :registered)
             # Existing users don't need email verification
             |> assign(:just_registered, false)
             |> assign(:participants, updated_participants)
             |> put_flash(
               :info,
               "Welcome back! You're now registered for #{socket.assigns.event.title}."
             )
             |> push_event("track_event", %{
               event: "event_registration_completed",
               properties: %{
                 event_id: socket.assigns.event.id,
                 event_title: socket.assigns.event.title,
                 event_slug: socket.assigns.event.slug,
                 user_type: "authenticated",
                 registration_method: "reregister"
               }
             })}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to register: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please log in to register for this event.")}
    end
  end

  def handle_event("switch_theme", %{"theme" => new_theme}, socket) do
    # Only allow theme switching for event organizers
    case socket.assigns.registration_status do
      :organizer ->
        # Convert string to atom for the theme - use String.to_atom to allow new themes
        theme_atom = String.to_atom(new_theme)

        # Update the event with the new theme
        case Events.update_event_theme(socket.assigns.event, theme_atom) do
          {:ok, updated_event} ->
            {:noreply,
             socket
             |> assign(:event, updated_event)
             |> assign(:theme, theme_atom)
             |> push_event("switch-theme-css", %{theme: new_theme})
             |> put_flash(:info, "Theme switched to #{String.capitalize(new_theme)}!")}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to switch theme: #{inspect(reason)}")}
        end

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Only event organizers can switch themes.")}
    end
  end

  def handle_event("manage_event", _params, socket) do
    # Redirect to the event management page
    event_slug = socket.assigns.event.slug
    {:noreply, push_navigate(socket, to: "/events/#{event_slug}/edit")}
  end

  def handle_event("toggle_participant_status", %{"status" => status}, socket) do
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        status_atom = String.to_atom(status)

        # Check if user already has this status
        current_status = Events.get_user_participant_status(socket.assigns.event, user)

        case current_status do
          ^status_atom ->
            # User already has this status, remove it
            case Events.remove_user_participant_status(socket.assigns.event, user) do
              {:ok, _} ->
                updated_participants = Events.list_event_participants(socket.assigns.event)
                new_status = Events.get_user_participant_status(socket.assigns.event, user)

                {:noreply,
                 socket
                 |> assign(:participants, updated_participants)
                 |> assign(:user_participant_status, new_status)
                 |> put_flash(:info, "Status updated successfully!")}

              {:error, reason} ->
                {:noreply,
                 socket
                 |> put_flash(:error, "Unable to update status: #{inspect(reason)}")}
            end

          _ ->
            # User doesn't have this status, set it
            case Events.update_user_participant_status(socket.assigns.event, user, status_atom) do
              {:ok, _participant} ->
                updated_participants = Events.list_event_participants(socket.assigns.event)
                new_status = Events.get_user_participant_status(socket.assigns.event, user)

                {:noreply,
                 socket
                 |> assign(:participants, updated_participants)
                 |> assign(:user_participant_status, new_status)
                 |> put_flash(:info, "Status updated successfully!")
                 |> push_event("track_event", %{
                   event: "participant_status_updated",
                   properties: %{
                     event_id: socket.assigns.event.id,
                     event_slug: socket.assigns.event.slug,
                     status: status_atom,
                     user_type: "authenticated"
                   }
                 })}

              {:error, reason} ->
                {:noreply,
                 socket
                 |> put_flash(:error, "Unable to update status: #{inspect(reason)}")}
            end
        end

      {:error, _} ->
        # For unauthenticated users trying to express interest, show modal
        if status == "interested" do
          {:noreply, assign(socket, :show_interest_modal, true)}
        else
          {:noreply,
           socket
           |> put_flash(:error, "Please log in to update your status.")}
        end
    end
  end

  def handle_event("increase_ticket_quantity", %{"ticket_id" => ticket_id}, socket) do
    ticket_id = String.to_integer(ticket_id)
    tickets = socket.assigns.tickets
    ticket = Enum.find(tickets, &(&1.id == ticket_id))

    if ticket do
      current_quantity = Map.get(socket.assigns.selected_tickets, ticket_id, 0)
      available_quantity = Ticketing.available_quantity(ticket)
      # Set reasonable limit
      max_per_order = 10

      new_quantity =
        if current_quantity < available_quantity and current_quantity < max_per_order do
          current_quantity + 1
        else
          current_quantity
        end

      # Only update if quantity actually changed
      if new_quantity != current_quantity do
        updated_selection = Map.put(socket.assigns.selected_tickets, ticket_id, new_quantity)

        socket =
          socket
          |> assign(:selected_tickets, updated_selection)

        # Show feedback if at limit
        socket =
          if new_quantity == available_quantity do
            put_flash(socket, :warning, "Maximum available tickets selected for #{ticket.title}")
          else
            socket
          end

        {:noreply, socket}
      else
        # At limit - show feedback
        message =
          cond do
            current_quantity >= available_quantity -> "No more #{ticket.title} tickets available"
            current_quantity >= max_per_order -> "Maximum #{max_per_order} tickets per order"
            true -> "Cannot increase quantity"
          end

        {:noreply, put_flash(socket, :warning, message)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("decrease_ticket_quantity", %{"ticket_id" => ticket_id}, socket) do
    ticket_id = String.to_integer(ticket_id)
    current_quantity = Map.get(socket.assigns.selected_tickets, ticket_id, 0)

    new_quantity = max(0, current_quantity - 1)

    updated_selection =
      if new_quantity == 0 do
        Map.delete(socket.assigns.selected_tickets, ticket_id)
      else
        Map.put(socket.assigns.selected_tickets, ticket_id, new_quantity)
      end

    {:noreply, assign(socket, :selected_tickets, updated_selection)}
  end

  def handle_event("proceed_to_checkout", _params, socket) do
    # Check if any tickets are selected
    selected_tickets = socket.assigns.selected_tickets

    if map_size(selected_tickets) == 0 do
      {:noreply,
       socket
       |> put_flash(:error, "Please select at least one ticket before proceeding to checkout.")}
    else
      # Check if user is logged in - if so, skip checkout page and go directly to Stripe
      case socket.assigns.user do
        nil ->
          # User not logged in - redirect to checkout page as before
          query =
            selected_tickets
            |> Enum.map(fn {id, qty} -> {Integer.to_string(id), qty} end)
            |> URI.encode_query()

          path = "/events/#{socket.assigns.event.slug}/checkout?#{query}"
          {:noreply, push_navigate(socket, to: path)}

        _user ->
          # User is logged in - proceed directly to payment
          socket = assign(socket, :ticket_loading, true)

          # Convert selected tickets to the format expected by Stripe checkout
          ticket_items =
            selected_tickets
            |> Enum.map(fn {ticket_id, quantity} ->
              ticket = Enum.find(socket.assigns.tickets, &(&1.id == ticket_id))
              %{ticket_id: ticket_id, quantity: quantity, ticket: ticket}
            end)

          case Ticketing.create_multi_ticket_checkout_session(
                 socket.assigns.user,
                 ticket_items
               ) do
            {:ok, %{checkout_url: checkout_url}} ->
              {:noreply,
               socket
               |> assign(:ticket_loading, false)
               |> redirect(external: checkout_url)}

            {:error, reason} ->
              {:noreply,
               socket
               |> assign(:ticket_loading, false)
               |> put_flash(:error, "Unable to proceed to payment: #{reason}")}
          end
      end
    end
  end

  def handle_event("show_auth_modal", _params, socket) do
    {:noreply, assign(socket, :show_registration_modal, true)}
  end

  def handle_event("show_interest_modal", _params, socket) do
    {:noreply, assign(socket, :show_interest_modal, true)}
  end

  def handle_event("close_interest_modal", _params, socket) do
    {:noreply, assign(socket, :show_interest_modal, false)}
  end

  def handle_event("show_attendees_modal", _params, socket) do
    {:noreply, assign(socket, :show_attendees_modal, true)}
  end

  def handle_event("close_attendees_modal", _params, socket) do
    {:noreply, assign(socket, :show_attendees_modal, false)}
  end

  def handle_event("show_registration_modal", _params, socket) do
    {:noreply, assign(socket, :show_registration_modal, true)}
  end

  def handle_event("close_vote_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_vote_modal, false)
     |> assign(:show_generic_vote_modal, false)
     |> assign(:pending_vote, nil)
     |> assign(:modal_poll, nil)
     |> assign(:modal_temp_votes, %{})}
  end

  def handle_event("close_generic_vote_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_generic_vote_modal, false)
     |> assign(:modal_poll, nil)
     |> assign(:modal_temp_votes, %{})}
  end

  # Legacy cast_vote handler removed - using generic polling system

  # Legacy remove_vote handler removed - using generic polling system

  # ==================== INFO HANDLERS ====================

  @impl true
  def handle_info({:participant_status_toggle, status}, socket) do
    handle_event("toggle_participant_status", %{"status" => Atom.to_string(status)}, socket)
  end

  @impl true
  def handle_info({:magic_link_sent, email}, socket) do
    {:noreply,
     socket
     |> assign(:show_interest_modal, false)
     |> put_flash(
       :info,
       "Magic link sent to #{email}! Check your email to complete registration and express interest."
     )
     |> push_event("track_event", %{
       event: "interest_magic_link_sent",
       properties: %{
         event_id: socket.assigns.event.id,
         event_slug: socket.assigns.event.slug,
         email_domain: email |> String.split("@") |> List.last()
       }
     })}
  end

  @impl true
  def handle_info({:magic_link_error, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Failed to send magic link: #{reason}")}
  end

  @impl true
  def handle_info({:close_interest_modal}, socket) do
    {:noreply, assign(socket, :show_interest_modal, false)}
  end

  @impl true
  def handle_info({:registration_success, type, _name, _email, intended_status}, socket) do
    action_text =
      case intended_status do
        :interested -> "expressed interest in"
        _ -> "registered for"
      end

    message =
      case type do
        :new_registration ->
          "Successfully #{action_text} #{socket.assigns.event.title}! Please check your email for a magic link to create your account."

        :existing_user_registered ->
          "Successfully #{action_text} #{socket.assigns.event.title}!"

        :registered ->
          "Successfully #{action_text} #{socket.assigns.event.title}!"

        :already_registered ->
          "You are already registered for this event."
      end

    # Reload participants to show updated count
    updated_participants = Events.list_event_participants(socket.assigns.event)

    # Only show email verification for truly new registrations
    just_registered =
      case type do
        :new_registration -> true
        :existing_user_registered -> false
        :registered -> true
        :already_registered -> false
      end

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> assign(:just_registered, just_registered)
     |> assign(:show_registration_modal, false)
     # Update registration status to show success UI
     |> assign(:registration_status, :registered)
     |> assign(:participants, updated_participants)
     |> push_event("track_event", %{
       event: "event_registration_completed",
       properties: %{
         event_id: socket.assigns.event.id,
         event_title: socket.assigns.event.title,
         event_slug: socket.assigns.event.slug,
         user_type:
           case type do
             :new_registration -> "new_user"
             :existing_user_registered -> "existing_user"
             :registered -> "authenticated"
             :already_registered -> "returning_user"
           end,
         registration_method: "form_submission",
         registration_type: type
       }
     })}
  end

  # Backward compatibility for old format without intended_status
  @impl true
  def handle_info({:registration_success, type, name, email}, socket) do
    handle_info({:registration_success, type, name, email, :accepted}, socket)
  end

  @impl true
  def handle_info({:registration_error, reason}, socket) do
    error_message =
      case reason do
        :already_registered ->
          "You're already registered for this event! Check your email for details."

        %{message: msg} ->
          msg

        %{status: 422} ->
          "This email address is already in use. Please try logging in instead."

        %{status: _} ->
          "We're having trouble creating your account. Please try again in a moment."

        _ ->
          "Something went wrong. Please try again or contact the event organizer."
      end

    {:noreply,
     socket
     |> assign(:show_registration_modal, false)
     |> put_flash(:error, error_message)}
  end

  @impl true
  def handle_info(:close_vote_modal, socket) do
    {:noreply,
     socket
     |> assign(:show_vote_modal, false)
     |> assign(:show_generic_vote_modal, false)
     |> assign(:pending_vote, nil)
     |> assign(:modal_poll, nil)
     |> assign(:modal_temp_votes, %{})}
  end

  @impl true
  def handle_info(:close_generic_vote_modal, socket) do
    {:noreply,
     socket
     |> assign(:show_generic_vote_modal, false)
     |> assign(:modal_poll, nil)
     |> assign(:modal_temp_votes, %{})}
  end

  @impl true
  def handle_info(:close_registration_modal, socket) do
    {:noreply, assign(socket, :show_registration_modal, false)}
  end

  # Handle attendees modal
  @impl true
  def handle_info(:close_attendees_modal, socket) do
    {:noreply, assign(socket, :show_attendees_modal, false)}
  end

  # Handle connect modal - triggered by RelationshipButtonComponent
  @impl true
  def handle_info({:show_connect_modal, other_user, suggested_context, event}, socket) do
    {:noreply,
     socket
     |> assign(:show_connect_modal, true)
     |> assign(:connect_modal_user, other_user)
     |> assign(:connect_modal_context, suggested_context)
     |> assign(:connect_modal_event, event)}
  end

  @impl true
  def handle_info(:close_connect_modal, socket) do
    {:noreply,
     socket
     |> assign(:show_connect_modal, false)
     |> assign(:connect_modal_user, nil)
     |> assign(:connect_modal_context, nil)}
  end

  # Handle successful connection creation
  @impl true
  def handle_info({:connection_created, other_user}, socket) do
    {:noreply,
     socket
     |> assign(:show_connect_modal, false)
     |> assign(:connect_modal_user, nil)
     |> assign(:connect_modal_context, nil)
     # Increment version to force EventAttendeesModalComponent to re-query relationships
     |> update(:relationships_version, &(&1 + 1))
     |> put_flash(:info, "#{other_user.name} added to your people!")}
  end

  # Handle auth modal request from RelationshipButtonComponent
  @impl true
  def handle_info({:show_auth_modal, :connect}, socket) do
    event = socket.assigns.event
    return_to = ~p"/#{event.slug}"

    {:noreply,
     socket
     |> put_flash(:info, "Please log in to stay in touch with other attendees")
     |> redirect(to: ~p"/auth/login?return_to=#{return_to}")}
  end

  @impl true
  def handle_info({:vote_success, type, _name, email}, socket) do
    message =
      case type do
        :new_voter ->
          "Thanks! Your vote has been recorded. Please check your email for a magic link to create your account."

        :existing_user_voted ->
          "Great! Your vote has been recorded."
      end

    # Reload vote data to show the updated vote
    # Find the date selection poll from the generic polls collection
    date_poll = Enum.find(socket.assigns.event_polls || [], &(&1.poll_type == "date_selection"))

    user_votes =
      case socket.assigns.auth_user do
        nil ->
          # For anonymous users, try to find the user by email to show their votes
          user = Accounts.get_user_by_email(email)

          if user && date_poll do
            Events.list_user_poll_votes(date_poll, user)
          else
            []
          end

        auth_user ->
          # For authenticated users, reload their votes normally
          case ensure_user_struct(auth_user) do
            {:ok, user} when not is_nil(date_poll) -> Events.list_user_poll_votes(date_poll, user)
            {:error, _} -> []
            _ -> []
          end
      end

    # Reload voting summary as well
    voting_summary =
      if date_poll do
        Events.get_enhanced_poll_vote_tallies(date_poll)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:show_vote_modal, false)
     |> assign(:pending_vote, nil)
     |> assign(:user_votes, user_votes)
     |> assign(:voting_summary, voting_summary)
     |> put_flash(:info, message)
     |> push_event("track_event", %{
       event: "event_date_vote_cast",
       properties: %{
         event_id: socket.assigns.event.id,
         event_title: socket.assigns.event.title,
         event_slug: socket.assigns.event.slug,
         poll_id: date_poll && date_poll.id,
         user_type:
           case type do
             :new_voter -> "new_user"
             :existing_user_voted -> "existing_user"
           end,
         vote_method: "anonymous_form",
         vote_type: type
       }
     })}
  end

  @impl true
  def handle_info({:vote_error, reason}, socket) do
    error_message =
      case reason do
        :event_not_found ->
          "Event not found. Please refresh the page and try again."

        %{message: msg} ->
          msg

        %{status: 422} ->
          "This email address is already in use. Please try logging in instead."

        %{status: _} ->
          "We're having trouble saving your vote. Please try again in a moment."

        _ ->
          "Something went wrong. Please try again or contact the event organizer."
      end

    {:noreply,
     socket
     |> assign(:show_vote_modal, false)
     |> assign(:pending_vote, nil)
     |> put_flash(:error, error_message)}
  end

  @impl true
  def handle_info(
        {:save_all_poll_votes_for_user, poll_id, name, email, temp_votes, _poll_options},
        socket
      ) do
    # Handle bulk anonymous poll votes submission
    alias EventasaurusApp.{Events, Accounts}

    # First, register the user properly to ensure they get a magic link
    case Events.register_user_for_event(socket.assigns.event.id, name, email) do
      {:ok, registration_type, _participant} ->
        # User is now registered, find them to cast votes
        case Accounts.get_user_by_email(email) do
          nil ->
            # This shouldn't happen, but handle it gracefully
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Unable to find user account after registration. Please try again."
             )
             |> assign(:show_generic_vote_modal, false)
             |> assign(:modal_poll, nil)
             |> assign(:modal_temp_votes, %{})}

          user ->
            vote_results = cast_poll_votes(poll_id, temp_votes, user)

            # Check if all votes were successful
            case Enum.find(vote_results, &match?({:error, _}, &1)) do
              nil ->
                # All votes successful
                socket = load_event_polls(socket)
                socket = assign(socket, :user, user)

                # Reload participants to show updated count
                updated_participants = Events.list_event_participants(socket.assigns.event)

                message =
                  case registration_type do
                    :new_registration ->
                      "All votes saved successfully! You're now registered for #{socket.assigns.event.title}. Please check your email for a magic link to create your account."

                    :existing_user_registered ->
                      "All votes saved successfully! You're registered for #{socket.assigns.event.title}."

                    _ ->
                      "All votes saved successfully!"
                  end

                {:noreply,
                 socket
                 |> assign(:show_generic_vote_modal, false)
                 |> assign(:modal_poll, nil)
                 |> assign(:modal_temp_votes, %{})
                 |> assign(:poll_temp_votes, %{})
                 |> assign(:registration_status, :registered)
                 |> assign(:just_registered, registration_type == :new_registration)
                 |> assign(:participants, updated_participants)
                 |> put_flash(:info, message)}

              {:error, reason} ->
                error_message =
                  case reason do
                    :option_not_found ->
                      "One or more poll options not found."

                    :unsupported_voting_system ->
                      "Unsupported voting system."

                    _ ->
                      "Unable to save votes. Please try again."
                  end

                {:noreply,
                 socket
                 |> put_flash(:error, error_message)
                 |> assign(:show_generic_vote_modal, false)
                 |> assign(:modal_poll, nil)
                 |> assign(:modal_temp_votes, %{})}
            end
        end

      {:error, :already_registered} ->
        # User is already registered, just cast their votes
        case Accounts.get_user_by_email(email) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to find user account. Please try again.")
             |> assign(:show_generic_vote_modal, false)
             |> assign(:modal_poll, nil)
             |> assign(:modal_temp_votes, %{})}

          user ->
            vote_results = cast_poll_votes(poll_id, temp_votes, user)

            # Check if all votes were successful
            case Enum.find(vote_results, &match?({:error, _}, &1)) do
              nil ->
                # All votes successful
                socket = load_event_polls(socket)
                socket = assign(socket, :user, user)

                # Reload participants to show updated count
                updated_participants = Events.list_event_participants(socket.assigns.event)

                {:noreply,
                 socket
                 |> assign(:show_generic_vote_modal, false)
                 |> assign(:modal_poll, nil)
                 |> assign(:modal_temp_votes, %{})
                 |> assign(:poll_temp_votes, %{})
                 |> assign(:registration_status, :registered)
                 |> assign(:participants, updated_participants)
                 |> put_flash(:info, "All votes saved successfully!")}

              {:error, _reason} ->
                {:noreply,
                 socket
                 |> put_flash(:error, "Unable to save some votes. Please try again.")
                 |> assign(:show_generic_vote_modal, false)
                 |> assign(:modal_poll, nil)
                 |> assign(:modal_temp_votes, %{})}
            end
        end

      {:error, reason} ->
        error_message =
          case reason do
            :event_not_found ->
              "Event not found. Please refresh the page and try again."

            _ ->
              "Unable to register for event. Please try again."
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)
         |> assign(:show_generic_vote_modal, false)
         |> assign(:modal_poll, nil)
         |> assign(:modal_temp_votes, %{})}
    end
  end

  # Legacy save_all_votes_for_user handler removed - using generic polling system

  @impl true
  def handle_info({:ticket_update, %{ticket: updated_ticket, action: action}}, socket) do
    # Only update if this is for the current event and we're showing tickets
    if updated_ticket.event_id == socket.assigns.event.id and socket.assigns.should_show_tickets do
      # Set loading state
      socket = assign(socket, :ticket_loading, true)

      # Refresh tickets to get updated availability
      updated_tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)

      # Update socket with fresh ticket data
      socket =
        socket
        |> assign(:tickets, updated_tickets)
        |> assign(:ticket_loading, false)

      # Show user-friendly notification for certain actions
      socket =
        case action do
          :order_confirmed ->
            # Find the ticket name for better UX
            ticket_name = updated_ticket.title
            put_flash(socket, :info, "🎫 #{ticket_name} availability updated!")

          :order_created ->
            # Someone else is purchasing, show subtle update
            socket

          _ ->
            socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:order_update, %{order: order, action: _action}}, socket) do
    # Refresh event data for this event while it's in threshold status
    # This handles all order changes (confirmations, cancellations, refunds)
    # to keep threshold progress in sync with the organizer dashboard
    event = socket.assigns.event

    if event.status == :threshold and order.event_id == event.id do
      # Reload event to get fresh threshold calculations
      updated_event = Events.get_event!(event.id)
      {:noreply, assign(socket, :event, updated_event)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:ranked_votes_submitted}, socket) do
    # Reload poll user votes to show updated rankings
    socket = load_event_polls(socket)

    {:noreply,
     socket
     |> put_flash(:info, "Your ranking has been saved!")}
  end

  @impl true
  def handle_info({:vote_cast, _option_id, _rating}, socket) do
    # Reload poll user votes to show updated star ratings
    socket = load_event_polls(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:all_votes_cleared}, socket) do
    # Reload poll user votes to show cleared state
    socket = load_event_polls(socket)

    {:noreply,
     socket
     |> put_flash(:info, "All votes cleared successfully!")}
  end

  @impl true
  def handle_info({:votes_cleared}, socket) do
    # Reload poll user votes to show cleared state
    socket = load_event_polls(socket)

    {:noreply,
     socket
     |> put_flash(:info, "All votes cleared successfully!")}
  end

  @impl true
  def handle_info({:vote_cleared, _option_id}, socket) do
    # Reload poll user votes to show updated state
    socket = load_event_polls(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:temp_votes_updated, poll_id, temp_votes}, socket) do
    # Update temp votes for a specific poll
    updated_poll_temp_votes = Map.put(socket.assigns.poll_temp_votes, poll_id, temp_votes)

    {:noreply, assign(socket, :poll_temp_votes, updated_poll_temp_votes)}
  end

  @impl true
  def handle_info({:votes_updated, %{poll_id: _poll_id}}, socket) do
    # Reload all polls to get fresh data with votes
    socket = load_event_polls(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:poll_stats_updated, _stats}, socket) do
    # Reload all polls to get fresh data with votes
    socket = load_event_polls(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:poll_stats_updated, _poll_id, _stats}, socket) do
    # Reload all polls to get fresh data with votes
    socket = load_event_polls(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:poll_option_added, _poll_id}, socket) do
    # Reload all polls to get fresh data with new options
    socket = load_event_polls(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:music_track_selected, track_data, option_data}, socket) do
    # Handle music track selection from the music poll component
    Logger.info("Music track selected: #{track_data["title"]} (ID: #{track_data["id"]})")

    # Create the poll option using the Events context
    case Events.create_poll_option(option_data) do
      {:ok, _option} ->
        # Reload polls to show the new option
        socket = load_event_polls(socket)
        {:noreply, put_flash(socket, :info, "Music track added successfully!")}

      {:error, changeset} ->
        Logger.error("Failed to add music track: #{inspect(changeset.errors)}")
        {:noreply, put_flash(socket, :error, "Failed to add music track. Please try again.")}
    end
  end

  @impl true
  def handle_info({:show_anonymous_voter_modal, poll_id, temp_votes}, socket) do
    # Show the anonymous voter modal for saving votes
    # First, find the poll to get its info
    poll = Enum.find(socket.assigns.event_polls || [], &(&1.id == poll_id))

    if poll && map_size(temp_votes) > 0 do
      # Update the temp votes and show the modal
      updated_poll_temp_votes = Map.put(socket.assigns.poll_temp_votes, poll_id, temp_votes)

      {:noreply,
       socket
       |> assign(:poll_temp_votes, updated_poll_temp_votes)
       |> assign(:show_generic_vote_modal, true)
       |> assign(:modal_poll, poll)
       |> assign(:modal_temp_votes, temp_votes)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Public Event Show Page with enhanced movie display -->



    <!-- Enhanced Movie Hero Section (when TMDB data is available) -->
    <%= if @event.rich_external_data && @event.rich_external_data["title"] && @event.rich_external_data["type"] == "movie" do %>
      <.live_component
        module={EventasaurusWeb.Live.Components.PublicMovieHeroComponent}
        id="public-movie-hero"
        rich_data={@event.rich_external_data}
        event={@event}
        venue={@venue}
      />

      <!-- Cast Carousel Section -->
      <%= if @event.rich_external_data["cast"] do %>
        <.live_component
          module={EventasaurusWeb.Live.Components.CastCarouselComponent}
          id="public-cast-carousel"
          cast={@event.rich_external_data["cast"]}
          variant={:standalone}
        />
      <% end %>
    <% end %>

    <div class="container mx-auto py-3 sm:py-6 max-w-7xl">
      <div class="event-page-grid grid grid-cols-1 lg:grid-cols-3 gap-6 lg:gap-12">
        <div class="main-content lg:col-span-2">

          <!-- Fallback Event Display (when no TMDB data) -->
          <%= if !@event.rich_external_data || !@event.rich_external_data["title"] || @event.rich_external_data["type"] != "movie" do %>
            <!-- Date/time and main info -->
            <div class="flex items-start gap-4 mb-8">
              <div class="bg-white border border-gray-200 rounded-lg p-3 w-16 h-16 flex flex-col items-center justify-center text-center font-medium shadow-sm">
                <div class="text-xs text-gray-500 uppercase tracking-wide"><%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%b") %></div>
                <div class="text-xl font-semibold text-gray-900"><%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%d") %></div>
              </div>
              <div>
                <h1 class="text-3xl lg:text-4xl font-bold text-gray-900 mb-4 leading-tight"><%= @event.title %></h1>
                <%= if @event.tagline do %>
                  <p class="text-lg text-gray-600 mb-4"><%= @event.tagline %></p>
                <% end %>

                <!-- When Section -->
                <div class="flex items-start gap-3 mb-3">
                  <div class="flex-shrink-0 w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                    <svg class="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                    </svg>
                  </div>
                  <div>
                    <h3 class="font-semibold text-gray-900 mb-1">When</h3>
                    <div class="text-gray-700">
                      <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%a, %b %d") %>
                      <%= if @event.ends_at do %>
                        · <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%I:%M %p") |> String.replace(~r/^0(\d):/, "\\1:") %> - <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.ends_at, @event.timezone) |> Calendar.strftime("%I:%M %p") |> String.replace(~r/^0(\d):/, "\\1:") %>
                      <% else %>
                        · <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%I:%M %p") |> String.replace(~r/^0(\d):/, "\\1:") %>
                      <% end %>
                      <span class="text-gray-500"><%= @event.timezone %></span>
                    </div>
                  </div>
                </div>

                <!-- Where Section -->
                <div class="flex items-start gap-3 mb-3">
                  <div class="flex-shrink-0 w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
                    <svg class="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"></path>
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"></path>
                    </svg>
                  </div>
                  <div>
                    <h3 class="font-semibold text-gray-900 mb-1">Where</h3>
                    <%= if @event.venue_id == nil do %>
                      <p class="text-gray-700">Virtual Event</p>
                    <% else %>
                      <%= if @venue do %>
                        <div class="text-gray-700">
                          <div><%= @venue.name %></div>
                          <div class="text-sm text-gray-600"><%= @venue.address %></div>
                        </div>
                      <% else %>
                        <p class="text-gray-600">Location details not available</p>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <!-- Event Type Section -->
                <div class="flex items-start gap-3 mb-3">
                  <div class="flex-shrink-0 w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
                    <svg class="w-4 h-4 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z"></path>
                    </svg>
                  </div>
                  <div>
                    <h3 class="font-semibold text-gray-900 mb-1">Event</h3>
                    <div class="text-gray-700">
                      <%= case @event.taxation_type do %>
                        <% "ticketed_event" -> %>
                          <div>Ticketed Event</div>
                          <div class="text-sm text-gray-600">Requires ticket purchase</div>
                        <% "contribution_collection" -> %>
                          <div>Contribution Collection</div>
                          <div class="text-sm text-gray-600">Free with optional contributions</div>
                        <% _ -> %>
                          <div>Free Event</div>
                          <div class="text-sm text-gray-600">Free registration</div>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Cover image -->
            <!-- PHASE 2 TODO: Remove resolve() wrapper after database migration normalizes URLs -->
            <%= if @event.cover_image_url && @event.cover_image_url != "" do %>
              <div class="relative w-full aspect-video rounded-xl overflow-hidden mb-8 shadow-lg border border-gray-200">
                <img src={resolve(@event.cover_image_url)} alt={@event.title} class="absolute inset-0 w-full h-full object-cover" />
              </div>
              <!-- Image attribution -->
            <EventasaurusWeb.EventComponents.image_attribution external_image_data={@event.external_image_data} class="text-xs text-gray-500 -mt-6 mb-6 px-1" />
          <% end %>

          <!-- Description -->
          <%= if @event.description && @event.description != "" do %>
            <div class="bg-white border border-gray-200 rounded-xl p-4 sm:p-6 mb-8 shadow-sm">
              <h2 class="text-xl font-semibold mb-4 text-gray-900">About This Event</h2>
              <div class="prose max-w-none text-gray-700">
                <%= Phoenix.HTML.raw(Earmark.as_html!(@event.description)) %>
              </div>
            </div>
          <% else %>
            <div class="bg-white border border-gray-200 rounded-xl p-4 sm:p-6 mb-8 shadow-sm">
              <h2 class="text-xl font-semibold mb-4 text-gray-900">About This Event</h2>
              <p class="text-gray-500">No description provided for this event.</p>
            </div>
          <% end %>

          <!-- Event Location Map -->
          <%= if @venue do %>
            <.live_component
              module={StaticMapComponent}
              id="event-location-map"
              venue={@venue}
              theme={@theme}
              size={:medium}
            />
          <% end %>

          <% end %>

          <!-- About section (shared for all events) -->

          <!-- Legacy date voting interface removed - using generic polling system -->

          <!-- Host section -->
          <div class="border-t border-gray-200 pt-6 mt-6">
            <h3 class="text-lg font-semibold mb-4 text-gray-900">Hosted by</h3>
            <div class="flex items-center space-x-3">
              <%= if Ecto.assoc_loaded?(@event.users) and @event.users != [] do %>
                <.link navigate={EventasaurusApp.Accounts.User.profile_url(hd(@event.users))} 
                      class="hover:opacity-80 transition-opacity">
                  <%= avatar_img_size(hd(@event.users), :lg, class: "border border-gray-200") %>
                </.link>
                <div class="flex-1">
                  <.link navigate={EventasaurusApp.Accounts.User.profile_url(hd(@event.users))} 
                        class="font-medium text-gray-900 hover:text-blue-600 transition-colors">
                    <%= hd(@event.users).name %>
                  </.link>
                  <.link navigate={EventasaurusApp.Accounts.User.profile_url(hd(@event.users))} 
                        class="text-blue-600 hover:text-blue-800 text-sm font-medium block">
                    View profile
                  </.link>

                  <!-- Social Media Links -->
                  <%= if Enum.any?(EventasaurusWeb.ProfileHTML.social_links(hd(@event.users))) do %>
                    <div class="flex items-center gap-2 mt-2">
                      <%= for {platform, handle} <- EventasaurusWeb.ProfileHTML.social_links(hd(@event.users)) do %>
                        <a
                          href={EventasaurusWeb.ProfileHTML.social_url(handle, platform)}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="inline-flex items-center justify-center w-6 h-6 bg-gray-100 hover:bg-gray-200 text-gray-600 hover:text-gray-800 rounded-full transition-colors"
                          title={EventasaurusWeb.ProfileHTML.platform_name(platform)}
                        >
                          <%= case platform do %>
                            <% :instagram -> %>
                              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zM12 0C8.741 0 8.333.014 7.053.072 2.695.272.273 2.69.073 7.052.014 8.333 0 8.741 0 12c0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98C8.333 23.986 8.741 24 12 24c3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947C23.728 2.695 21.31.273 16.948.073 15.668.014 15.259 0 12 0zm0 5.838a6.162 6.162 0 100 12.324 6.162 6.162 0 000-12.324zM12 16a4 4 0 110-8 4 4 0 010 8zm6.406-11.845a1.44 1.44 0 100 2.881 1.44 1.44 0 000-2.881z"/>
                              </svg>
                            <% :x -> %>
                              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
                              </svg>
                            <% :youtube -> %>
                              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
                              </svg>
                            <% :tiktok -> %>
                              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/>
                              </svg>
                            <% :linkedin -> %>
                              <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/>
                              </svg>
                            <% _ -> %>
                              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                              </svg>
                          <% end %>
                        </a>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center text-lg font-semibold text-gray-600 border border-gray-200">
                  ?
                </div>
                <div>
                  <div class="font-medium text-gray-900">Event Organizer</div>
                  <a href="#" class="text-blue-600 hover:text-blue-800 text-sm font-medium">View other events</a>
                </div>
              <% end %>
            </div>
          </div>

                    <!-- Participants section -->
          <%= if length(@participants) > 0 do %>
            <div class="border-t border-gray-200 pt-6 mt-6">
              <div class="flex items-center justify-between mb-4">
                <.live_component
                  module={EventasaurusWeb.ParticipantStatusDisplayComponent}
                  id="participant-status-display"
                  participants={@participants}
                  show_avatars={true}
                  max_avatars={10}
                  avatar_size={:md}
                  show_counts={true}
                  show_status_labels={true}
                  layout={:horizontal}
                  class=""
                />
                <%= if length(@participants) > 3 do %>
                  <button
                    type="button"
                    phx-click="show_attendees_modal"
                    class="text-sm text-blue-600 hover:text-blue-800 font-medium flex items-center gap-1"
                  >
                    View all
                    <Heroicons.chevron_right class="w-4 h-4" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Event Polls Section -->
          <%= if length(@event_polls || []) > 0 do %>
            <div class="space-y-6 mt-12">
              <!-- Polls Section Header -->
              <div class="flex items-center justify-between mb-6">
                <h2 class="text-2xl font-bold text-gray-900">Event Polls</h2>
                <.link
                  navigate={~p"/#{@event.slug}/polls"}
                  class="inline-flex items-center px-4 py-2 text-sm font-medium text-blue-600 hover:text-blue-700 hover:bg-blue-50 rounded-lg transition-colors duration-200"
                >
                  View All Polls
                  <svg class="ml-2 w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                  </svg>
                </.link>
              </div>

              <%= for poll <- @event_polls do %>
                <div class="bg-white border border-gray-200 rounded-xl p-4 sm:p-6 mb-8 shadow-sm">
                  <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
                    <div class="flex flex-wrap items-center gap-3 flex-1">
                      <div class="text-2xl">
                        <%= poll_emoji(poll.poll_type) %>
                      </div>
                      <h2 class="text-xl font-semibold text-gray-900">
                        <.link navigate={~p"/#{@event.slug}/polls/#{poll.number}"} class="hover:text-blue-600 transition-colors">
                          <%= poll.title %>
                        </.link>
                      </h2>
                      <div class={"px-3 py-1 rounded-full text-sm font-medium #{poll_phase_class(poll.phase)}"}>
                        <%= case poll.phase do %>
                          <% "list_building" -> %>Building Options
                          <% "voting" -> %>Voting Open
                          <% "voting_with_suggestions" -> %>Voting Open
                          <% "voting_only" -> %>Voting Only
                          <% "closed" -> %>Voting Closed
                          <% _ -> %>Active
                        <% end %>
                      </div>
                    </div>
                    <.link
                      navigate={~p"/#{@event.slug}/polls/#{poll.number}"}
                      class="inline-flex items-center px-3 py-1.5 text-sm font-medium text-gray-700 hover:text-blue-600 hover:bg-gray-50 rounded-lg transition-colors duration-200 border border-gray-300"
                    >
                      View Poll
                      <svg class="ml-1.5 w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                      </svg>
                    </.link>
                  </div>

                  <%= cond do %>
                    <% poll.poll_type == "movie" -> %>
                      <!-- Special handling for movie polls -->
                      <.live_component
                        module={EventasaurusWeb.PublicMoviePollComponent}
                        id={"movie-poll-#{poll.id}"}
                        poll={poll}
                        event={@event}
                        current_user={@user}
                        temp_votes={Map.get(@poll_temp_votes || %{}, poll.id, %{})}
                      />

                    <% poll.poll_type == "cocktail" -> %>
                      <!-- Special handling for cocktail polls -->
                      <.live_component
                        module={EventasaurusWeb.PublicCocktailPollComponent}
                        id={"cocktail-poll-#{poll.id}"}
                        poll={poll}
                        event={@event}
                        current_user={@user}
                        temp_votes={Map.get(@poll_temp_votes || %{}, poll.id, %{})}
                      />

                    <% poll.poll_type == "music_track" -> %>
                      <!-- Special handling for music track polls -->
                      <.live_component
                        module={EventasaurusWeb.PublicMusicTrackPollComponent}
                        id={"music-track-poll-#{poll.id}"}
                        poll={poll}
                        event={@event}
                        current_user={@user}
                        temp_votes={Map.get(@poll_temp_votes || %{}, poll.id, %{})}
                      />

                    <% poll.poll_type == "date_selection" -> %>
                      <!-- Date selection polls have their own component -->
                      <.live_component
                        module={EventasaurusWeb.DateSelectionPollComponent}
                        id={"date-poll-#{poll.id}"}
                        poll={poll}
                        event={@event}
                        current_user={@user}
                        temp_votes={Map.get(@poll_temp_votes || %{}, poll.id, %{})}
                        anonymous_mode={is_nil(@user)}
                        mode={:content}
                      />

                    <% poll.phase in ["list_building", "voting", "voting_with_suggestions", "voting_only"] -> %>
                      <!-- Generic polls (places, time, custom, etc) -->
                      <.live_component
                        module={PublicGenericPollComponent}
                        id={"public-generic-poll-#{poll.id}"}
                        event={@event}
                        current_user={@user}
                        poll={poll}
                        mode={:content}
                      />

                    <% poll.phase == "closed" -> %>
                      <!-- Show results for closed polls -->
                      <.live_component
                        module={EventasaurusWeb.ResultsDisplayComponent}
                        id={"results-display-#{poll.id}"}
                        poll={poll}
                        show_percentages={true}
                        show_vote_counts={true}
                      />

                                      <% true -> %>
                    <!-- Fallback for other poll phases -->
                    <div class="text-center py-4 text-gray-500">
                      <p>Poll details will be available soon.</p>
                    </div>
                <% end %>

                </div>
              <% end %>
            </div>
          <% end %>
        </div>

                 <!-- Right sidebar -->
         <div class="sidebar-content lg:col-span-1">
          <!-- Threshold Progress Section (for events in threshold status) -->
          <%= if @event.status == :threshold do %>
            <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm mb-6">
              <h3 class="text-lg font-semibold mb-4 text-gray-900">Event Progress</h3>
              <EventasaurusWeb.EventComponents.threshold_progress event={@event} />

              <!-- Deadline Countdown -->
              <%= if @event.polling_deadline do %>
                <div class="mt-4 pt-4 border-t border-gray-100">
                  <EventasaurusWeb.EventComponents.countdown_timer
                    deadline={@event.polling_deadline}
                    label="Campaign ends in:"
                    variant="compact"
                  />
                </div>
              <% end %>

              <p class="text-sm text-gray-500 mt-3">
                This event needs to reach its goal before it's confirmed. Help make it happen!
              </p>
            </div>
          <% end %>

          <!-- Ticket Selection Section (for events with tickets) -->
          <%= if @should_show_tickets and @event.status in [:confirmed, :threshold] do %>
            <.ticket_selection_component
              tickets={@tickets}
              selected_tickets={@selected_tickets}
              event={@event}
              user={@user}
              loading={@ticket_loading}
            />
          <% end %>


                     <!-- Registration Card -->
           <div class="mobile-register-card bg-white border border-gray-200 rounded-xl p-6 shadow-sm mb-6">
            <h3 class="text-lg font-semibold mb-4 text-gray-900">
              <%= case @registration_status do %>
                <% :registered -> %>Registration
                <% :cancelled -> %>Registration
                <% :organizer -> %>Event Management
                <% _ -> %>Register for this event
              <% end %>
            </h3>

            <%= case @registration_status do %>
              <% :not_authenticated -> %>
                <!-- Anonymous user - show registration and interest options -->
                <button
                  id="register-now-btn"
                  phx-click="register_with_status"
                  phx-value-status="accepted"
                  class="bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-6 rounded-lg w-full flex items-center justify-center transition-colors duration-200 mb-3"
                >
                  Register for Event
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 ml-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M14 5l7 7m0 0l-7 7m7-7H3" />
                  </svg>
                </button>

                <!-- Interest Button for Anonymous Users -->
                <button
                  phx-click="register_with_status"
                  phx-value-status="interested"
                  class="bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium py-2 px-4 rounded-lg w-full flex items-center justify-center transition-colors duration-200"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
                  </svg>
                  Interested
                </button>

              <% :not_registered -> %>
                <!-- Authenticated user - not registered -->
                <div class="flex items-center gap-3 mb-4">
                  <%= avatar_img_size(@user, :md, class: "border border-gray-200") %>
                  <div>
                    <div class="font-medium text-gray-900"><%= @user.name %></div>
                    <div class="text-sm text-gray-500"><%= @user.email %></div>
                  </div>
                </div>

                <!-- Primary Registration Button -->
                <button
                  phx-click="register_with_status"
                  phx-value-status="accepted"
                  class="bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-6 rounded-lg w-full transition-colors duration-200 mb-3"
                >
                  One-Click Register
                </button>

                <!-- Secondary Interest Button -->
                <button
                  phx-click="register_with_status"
                  phx-value-status="interested"
                  class="bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium py-2 px-4 rounded-lg w-full flex items-center justify-center transition-colors duration-200"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
                  </svg>
                  Interested
                </button>

              <% :registered -> %>
                <!-- Authenticated user - registered -->
                <div class="text-center">
                  <div class="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-3">
                    <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <h4 class="text-lg font-semibold text-gray-900 mb-2">You're In</h4>
                  <p class="text-sm text-gray-600 mb-4">You're registered for this event</p>

                  <%= if @just_registered do %>
                    <!-- Email verification notice for newly registered users only -->
                    <div class="border-t border-gray-200 pt-4 mt-4 mb-4">
                      <div class="bg-blue-50 border border-blue-200 rounded-lg p-3">
                        <div class="flex items-center justify-center mb-2">
                          <div class="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center">
                            <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                            </svg>
                          </div>
                        </div>
                        <p class="text-sm text-blue-800 text-center mb-3">
                          Please verify your email to manage your registration and see more event details.
                        </p>
                        <button class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg text-sm transition-colors duration-200 flex items-center justify-center gap-2">
                          Verify Email
                          <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3" />
                          </svg>
                        </button>
                      </div>
                    </div>
                  <% end %>

                  <button
                    phx-click="cancel_registration"
                    phx-confirm="Are you sure you want to cancel your registration?"
                    class="text-sm text-gray-500 hover:text-gray-700 transition-colors duration-200"
                  >
                    Can't attend? Cancel registration
                  </button>
                </div>

              <% :cancelled -> %>
                <!-- Authenticated user - previously registered but cancelled -->
                <div class="text-center">
                  <h4 class="text-lg font-semibold text-gray-900 mb-2">You're Not Going</h4>
                  <p class="text-sm text-gray-500 mb-4">We hope to see you next time!</p>

                  <button
                    phx-click="reregister"
                    class="bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-6 rounded-lg w-full mb-2 transition-colors duration-200"
                  >
                    Register Again
                  </button>

                  <p class="text-xs text-gray-500">Changed your mind? You can register again.</p>
                </div>

              <% :organizer -> %>
                <!-- User is an organizer/admin for this event -->
                <div class="text-center">
                  <div class="w-12 h-12 bg-purple-100 rounded-full flex items-center justify-center mx-auto mb-3">
                    <svg xmlns="http://www.w3.org/2000/svg" class="w-6 h-6 text-purple-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4M7.835 4.697a3.42 3.42 0 001.946-.806 3.42 3.42 0 014.438 0 3.42 3.42 0 001.946.806 3.42 3.42 0 013.138 3.138 3.42 3.42 0 00.806 1.946 3.42 3.42 0 010 4.438 3.42 3.42 0 00-.806 1.946 3.42 3.42 0 01-3.138 3.138 3.42 3.42 0 00-1.946.806 3.42 3.42 0 01-4.438 0 3.42 3.42 0 00-1.946-.806 3.42 3.42 0 01-3.138-3.138 3.42 3.42 0 00-.806-1.946 3.42 3.42 0 010-4.438 3.42 3.42 0 00.806-1.946 3.42 3.42 0 013.138-3.138z" />
                    </svg>
                  </div>
                  <h4 class="text-lg font-semibold text-gray-900 mb-2">Event Organizer</h4>
                  <p class="text-sm text-gray-600 mb-4">You're hosting this event</p>

                  <!-- Theme Switcher for Organizers -->
                  <div class="mb-4 text-left">
                    <label for="theme-select" class="block text-sm font-medium text-gray-700 mb-1">Event Theme</label>
                    <form phx-change="switch_theme">
                      <select
                        id="theme-select"
                        name="theme"
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-purple-500 focus:border-purple-500"
                      >
                        <%= for theme <- EventasaurusWeb.ThemeComponents.available_themes() do %>
                          <option
                            value={theme.value}
                            selected={@theme == theme.value || @theme == String.to_atom(theme.value)}
                          >
                            <%= theme.label %> - <%= theme.description %>
                          </option>
                        <% end %>
                      </select>
                    </form>
                  </div>


                  <button
                    phx-click="manage_event"
                    class="text-sm text-purple-600 hover:text-purple-700 transition-colors duration-200 font-medium"
                  >
                    Manage Event →
                  </button>
                </div>
            <% end %>

                         <%= if @registration_status in [:not_authenticated, :not_registered] do %>
               <div class="mt-3 text-center text-sm text-gray-500">
                 <div>Limited spots available</div>
               </div>
             <% end %>

                          <!-- Mobile Show More Button -->
                          <button
               id="mobile-toggle-btn"
               class="lg:hidden w-full mt-2 py-2 px-4 text-sm text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors duration-200 border border-gray-200"
               aria-expanded="false"
               aria-controls="mobile-secondary-actions"
               aria-label="Toggle sharing and calendar options"
             >
               <span id="show-more-text">Share & Calendar</span>
               <svg id="show-more-icon" xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 inline ml-1 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                 <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
               </svg>
             </button>
           </div>

          <!-- Presented by -->
          <%= if @group do %>
            <.live_component
              module={PresentedByComponent}
              id="presented-by"
              group={@group}
            />
          <% end %>

                     <!-- Combined Share & Calendar Section -->
           <div id="mobile-secondary-actions" class="mobile-secondary-actions bg-white border border-gray-200 rounded-xl p-5 shadow-sm">
            <h3 class="text-base font-semibold mb-4 text-gray-900">Share & Calendar</h3>
            
            <!-- Share Section -->
            <div class="mb-6">
              <h4 class="text-sm font-medium text-gray-700 mb-3">Share this event</h4>
              <div class="flex space-x-3">
                <a href={"https://twitter.com/intent/tweet?#{URI.encode_query([text: "Check out #{@event.title}", url: EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}"])}"} target="_blank" rel="noopener noreferrer" class="w-10 h-10 bg-gray-100 hover:bg-gray-200 text-gray-600 rounded-full flex items-center justify-center transition-colors duration-200">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M22.162 5.656a8.384 8.384 0 0 1-2.402.658A4.196 4.196 0 0 0 21.6 4c-.82.488-1.719.83-2.656 1.015a4.182 4.182 0 0 0-7.126 3.814 11.874 11.874 0 0 1-8.62-4.37 4.168 4.168 0 0 0-.566 2.103c0 1.45.738 2.731 1.86 3.481a4.168 4.168 0 0 1-1.894-.523v.052a4.185 4.185 0 0 0 3.355 4.101 4.21 4.21 0 0 1-1.89.072A4.185 4.185 0 0 0 7.97 16.65a8.394 8.394 0 0 1-6.191 1.732 11.83 11.83 0 0 0 6.41 1.88c7.693 0 11.9-6.373 11.9-11.9 0-.18-.005-.362-.013-.54a8.496 8.496 0 0 0 2.087-2.165z"/></svg>
                </a>
                <a href={"https://www.facebook.com/sharer/sharer.php?u=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" rel="noopener noreferrer" class="w-10 h-10 bg-gray-100 hover:bg-gray-200 text-gray-600 rounded-full flex items-center justify-center transition-colors duration-200">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2.04c-5.5 0-10 4.49-10 10.02 0 5 3.66 9.15 8.44 9.9v-7H7.9v-2.9h2.54V9.85c0-2.51 1.49-3.89 3.78-3.89 1.09 0 2.23.19 2.23.19v2.47h-1.26c-1.24 0-1.63.77-1.63 1.56v1.88h2.78l-.45 2.9h-2.33v7a10 10 0 0 0 8.44-9.9c0-5.53-4.5-10.02-10-10.02z"/></svg>
                </a>
                <a href={"https://www.linkedin.com/sharing/share-offsite/?url=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" rel="noopener noreferrer" class="w-10 h-10 bg-gray-100 hover:bg-gray-200 text-gray-600 rounded-full flex items-center justify-center transition-colors duration-200">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M19 3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14m-.5 15.5v-5.3a3.26 3.26 0 0 0-3.26-3.26c-.85 0-1.84.52-2.32 1.3v-1.11h-2.79v8.37h2.79v-4.93c0-.77.62-1.4 1.39-1.4a1.4 1.4 0 0 1 1.4 1.4v4.93h2.79M6.88 8.56a1.68 1.68 0 0 0 1.68-1.68c0-.93-.75-1.69-1.68-1.69a1.69 1.69 0 0 0-1.69 1.69c0 .93.76 1.68 1.69 1.68m1.39 9.94v-8.37H5.5v8.37h2.77z"/></svg>
                </a>
                <a href="#" id="copy-link-btn" aria-label="Copy event link" class="w-10 h-10 bg-gray-100 hover:bg-gray-200 text-gray-600 rounded-full flex items-center justify-center transition-colors duration-200" data-clipboard-text={EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}"}>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                </a>
              </div>
            </div>

            <!-- Calendar Section -->
            <div>
              <h4 class="text-sm font-medium text-gray-700 mb-3">Add to calendar</h4>
              <div class="flex flex-col space-y-2">
                <a href={~p"/events/#{@event.slug}/calendar/google"} target="_blank" rel="noopener noreferrer" class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-2 transition-colors duration-200">
                  <!-- Google Calendar Icon -->
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M19 3h-1V1h-2v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V8h14v11zM7 10h5v5H7z"/>
                  </svg>
                  Google Calendar
                </a>
                <a href={~p"/events/#{@event.slug}/calendar/ics"} download={"#{@event.slug}.ics"} class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-2 transition-colors duration-200">
                  <!-- Apple Calendar Icon -->
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M17.75 3A3.25 3.25 0 0121 6.25v11.5A3.25 3.25 0 0117.75 21H6.25A3.25 3.25 0 013 17.75V6.25A3.25 3.25 0 016.25 3h11.5zm1.75 5.5h-15v9.25c0 .966.784 1.75 1.75 1.75h11.5a1.75 1.75 0 001.75-1.75V8.5zm-11.75 6a1.25 1.25 0 110 2.5 1.25 1.25 0 010-2.5zm4 0a1.25 1.25 0 110 2.5 1.25 1.25 0 010-2.5zm4 0a1.25 1.25 0 110 2.5 1.25 1.25 0 010-2.5zm-8-4a1.25 1.25 0 110 2.5 1.25 1.25 0 010-2.5zm4 0a1.25 1.25 0 110 2.5 1.25 1.25 0 010-2.5zm4 0a1.25 1.25 0 110 2.5 1.25 1.25 0 010-2.5zm2-6H6.25A1.75 1.75 0 004.5 6.25V7h15v-.75a1.75 1.75 0 00-1.75-1.75z"/>
                  </svg>
                  Apple Calendar
                </a>
                <a href={~p"/events/#{@event.slug}/calendar/outlook"} target="_blank" rel="noopener noreferrer" class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-2 transition-colors duration-200">
                  <!-- Outlook Icon -->
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10h5v-2h-5c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8v1.43c0 .79-.71 1.57-1.5 1.57s-1.5-.78-1.5-1.57V12c0-2.76-2.24-5-5-5s-5 2.24-5 5 2.24 5 5 5c1.38 0 2.64-.56 3.54-1.47.65.89 1.77 1.47 2.96 1.47 1.97 0 3.5-1.6 3.5-3.57V12c0-5.52-4.48-10-10-10zm0 13c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3z"/>
                  </svg>
                  Outlook
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <%= if @show_registration_modal do %>
      <.live_component
        module={EventRegistrationComponent}
        id="registration-modal"
        event={@event}
        show={@show_registration_modal}
        intended_status={Map.get(assigns, :intended_status, :accepted)}
      />
    <% end %>

    <!-- Legacy vote modal removed - using generic polling system -->

    <%= if @show_generic_vote_modal and @modal_poll && map_size(@modal_temp_votes) > 0 do %>
      <.live_component
        module={AnonymousVoterComponent}
        id="generic-vote-modal"
        event={@event}
        poll={@modal_poll}
        poll_options={@modal_poll.poll_options}
        temp_votes={@modal_temp_votes}
        show={@show_generic_vote_modal}
      />
    <% end %>

    <%= if @show_interest_modal do %>
      <.live_component
        module={EventasaurusWeb.InterestAuthModal}
        id="interest-auth-modal"
        event={@event}
        show={@show_interest_modal}
        on_close="close_interest_modal"
      />
    <% end %>

    <!-- Attendees Modal -->
    <%= if @show_attendees_modal do %>
      <.live_component
        module={EventAttendeesModalComponent}
        id={"attendees-modal-#{@relationships_version}"}
        event={@event}
        participants={@participants}
        current_user={@user}
        show={@show_attendees_modal}
      />
    <% end %>

    <!-- Connect with Context Modal -->
    <%= if @show_connect_modal && @connect_modal_user do %>
      <.live_component
        module={ConnectWithContextModalComponent}
        id="connect-modal"
        other_user={@connect_modal_user}
        current_user={@user}
        event={@event}
        suggested_context={@connect_modal_context}
        show={@show_connect_modal}
      />
    <% end %>

    <!-- Structured Data for SEO -->
    <script type="application/ld+json">
      <%= case Jason.encode(@structured_data) do %>
        <% {:ok, json} -> %>
          <%= raw json %>
        <% {:error, _reason} -> %>
          <!-- Structured data encoding failed -->
      <% end %>
    </script>

         <script>
       // Simple clipboard functionality
       document.getElementById('copy-link-btn').addEventListener('click', function(e) {
         e.preventDefault();
         const url = this.getAttribute('data-clipboard-text');
         navigator.clipboard.writeText(url).then(function() {
           alert('Link copied to clipboard!');
         }).catch(function(err) {
           console.error('Could not copy text: ', err);
         });
       });

              // Mobile secondary actions toggle
       document.addEventListener('DOMContentLoaded', function() {
         const toggleBtn = document.getElementById('mobile-toggle-btn');

         if (toggleBtn) {
           toggleBtn.addEventListener('click', function() {
             const secondaryActions = document.querySelectorAll('.mobile-secondary-actions');
             const showMoreText = document.getElementById('show-more-text');
             const showMoreIcon = document.getElementById('show-more-icon');

             // Check if all required elements exist
             if (!secondaryActions.length || !showMoreText || !showMoreIcon) {
               console.warn('Mobile toggle: Missing required DOM elements');
               return;
             }

             const isExpanded = toggleBtn.getAttribute('aria-expanded') === 'true';

             // Toggle visibility with proper animation
             secondaryActions.forEach(action => {
               if (isExpanded) {
                 action.classList.remove('show');
               } else {
                 action.classList.add('show');
               }
             });

             // Update accessibility attributes and UI
             toggleBtn.setAttribute('aria-expanded', !isExpanded);
             showMoreText.textContent = isExpanded ? 'Share & Calendar' : 'Hide';
             showMoreIcon.style.transform = isExpanded ? 'rotate(0deg)' : 'rotate(180deg)';
           });
         }
       });

      // Theme switching functionality
      window.addEventListener("phx:switch-theme-css", (e) => {
        const newTheme = e.detail.theme;

        // Find existing theme CSS link
        const existingThemeLink = document.querySelector('link[href*="/themes/"][href$=".css"]');

        if (newTheme === 'minimal') {
          // For minimal theme, just remove any existing theme CSS
          if (existingThemeLink) {
            existingThemeLink.remove();
          }
        } else {
          // For other themes, create or update the theme CSS link
          const newHref = `/themes/${newTheme}.css`;

          if (existingThemeLink) {
            // Update existing link
            existingThemeLink.href = newHref;
          } else {
            // Create new link
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = newHref;
            document.head.appendChild(link);
          }
        }

        // Handle dark/light mode for navbar and protected UI elements
        const htmlElement = document.documentElement;
        const darkThemes = ['cosmic']; // Only cosmic is currently a dark theme

        if (darkThemes.includes(newTheme)) {
          htmlElement.classList.add('dark');
        } else {
          htmlElement.classList.remove('dark');
        }

        // Update body class for theme-specific styling
        document.body.className = document.body.className.replace(/\btheme-\w+\b/g, '');
        if (newTheme !== 'minimal') {
          document.body.classList.add(`theme-${newTheme}`);
        }

        console.log(`Theme switched to: ${newTheme}`);
      });
    </script>
    """
  end

  # Helper function to generate structured data (JSON-LD) for SEO
  defp generate_structured_data(event, event_url) do
    base_schema = %{
      "@context" => "https://schema.org",
      "@type" => "Event",
      "name" => event.title,
      "startDate" => event.start_at,
      "endDate" => event.ends_at,
      "url" => event_url,
      "description" => event.description,
      "eventStatus" => "https://schema.org/EventScheduled"
    }

    # Add movie schema if TMDB data is available
    if event.rich_external_data && event.rich_external_data["title"] &&
         event.rich_external_data["type"] == "movie" do
      movie_data = event.rich_external_data
      metadata = movie_data["metadata"] || %{}

      movie_schema = %{
        "@type" => "Movie",
        "name" => movie_data["title"],
        "description" => metadata["overview"],
        "datePublished" => metadata["release_date"],
        "genre" => metadata["genres"] || [],
        "aggregateRating" =>
          if metadata["vote_average"] do
            %{
              "@type" => "AggregateRating",
              "ratingValue" => metadata["vote_average"],
              "ratingCount" => metadata["vote_count"],
              "bestRating" => 10
            }
          end,
        "image" =>
          if metadata["poster_path"] do
            EventasaurusWeb.Live.Components.RichDataDisplayComponent.tmdb_image_url(
              metadata["poster_path"],
              "w500"
            )
          end
      }

      # Add cast information if available
      cast_schema =
        if movie_data["cast"] do
          Enum.take(movie_data["cast"], 5)
          |> Enum.map(fn cast_member ->
            %{
              "@type" => "Person",
              "name" => cast_member["name"],
              "image" =>
                if cast_member["profile_path"] do
                  EventasaurusWeb.Live.Components.RichDataDisplayComponent.tmdb_image_url(
                    cast_member["profile_path"],
                    "w185"
                  )
                end
            }
          end)
        end

      movie_schema =
        if cast_schema, do: Map.put(movie_schema, "actor", cast_schema), else: movie_schema

      # Combine event and movie schemas
      Map.merge(base_schema, %{
        "workFeatured" => movie_schema,
        "about" => movie_schema,
        "image" =>
          if metadata["backdrop_path"] do
            EventasaurusWeb.Live.Components.RichDataDisplayComponent.tmdb_image_url(
              metadata["backdrop_path"],
              "w1280"
            )
          end
      })
    else
      base_schema
    end
  end

  # Helper function to generate social card URL
  defp social_card_url(_socket, event) do
    # Use the new hash-based URL format with external domain
    hash_path = EventasaurusWeb.SocialCardView.social_card_url(event)
    EventasaurusWeb.UrlHelper.build_url(hash_path)
  end

  # Helper function to truncate description for meta tags
  defp truncate_description(description, max_length \\ 160) do
    if String.length(description) > max_length do
      String.slice(description, 0, max_length - 3) <> "..."
    else
      description
    end
  end

  # Ensures we have a proper User struct for the current user.
  #
  # This function processes the raw authentication data from `@auth_user`
  # into a local database User struct for use in business logic and templates.
  #
  # ## Parameters
  # - `nil`: No authenticated user
  # - `%User{}`: Already a local User struct
  # - Clerk JWT claims map (with "sub" key)
  #
  # ## Returns
  # - `{:ok, %User{}}`: Successfully processed user
  # - `{:error, reason}`: Failed to process or no user
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}

  # Handle Clerk JWT claims (has "sub" key for Clerk user ID)
  defp ensure_user_struct(%{"sub" => _clerk_id} = clerk_claims) do
    alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync
    ClerkSync.sync_user(clerk_claims)
  end

  defp ensure_user_struct(_), do: {:error, :invalid_user_data}

  # Helper function for poll phase CSS classes
  defp poll_phase_class(phase) do
    case phase do
      "list_building" -> "bg-yellow-100 text-yellow-800"
      "voting" -> "bg-green-100 text-green-800"
      "voting_with_suggestions" -> "bg-green-100 text-green-800"
      "voting_only" -> "bg-blue-100 text-blue-800"
      "closed" -> "bg-gray-100 text-gray-800"
      _ -> "bg-blue-100 text-blue-800"
    end
  end

  # Subscribe to poll statistics updates for real-time voting updates
  defp subscribe_to_poll_stats(socket) do
    if socket.assigns[:event_polls] && length(socket.assigns.event_polls) > 0 do
      # Subscribe to each poll's statistics updates
      Enum.each(socket.assigns.event_polls, fn poll ->
        Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "polls:#{poll.id}:stats")
      end)

      # Also subscribe to the event's general poll updates
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "events:#{socket.assigns.event.id}:polls")
    end

    socket
  end

  # Load event polls for display on public event page
  defp load_event_polls(socket) do
    event = socket.assigns.event
    user = socket.assigns[:user]

    try do
      # Load polls for all events on public pages with hidden options filtered out
      event_polls =
        Events.list_polls(event)
        |> Enum.map(fn poll ->
          # Filter out hidden poll options (status != "active") for public display
          # Handle both loaded associations and NotLoaded structs
          visible_options =
            case poll.poll_options do
              %Ecto.Association.NotLoaded{} -> []
              options when is_list(options) -> Enum.filter(options, &(&1.status == "active"))
              _ -> []
            end

          %{poll | poll_options: visible_options}
        end)

      # Load user votes for each poll if user is authenticated
      poll_user_votes =
        if user && length(event_polls) > 0 do
          event_polls
          |> Enum.map(fn poll ->
            votes = Events.list_user_poll_votes(poll, user)
            {poll.id, votes}
          end)
          |> Map.new()
        else
          %{}
        end

      socket
      |> assign(:event_polls, event_polls)
      |> assign(:poll_user_votes, poll_user_votes)
    rescue
      error ->
        Logger.error("Failed to load event polls: #{inspect(error)}")

        socket
        |> assign(:event_polls, [])
        |> assign(:poll_user_votes, %{})
    end
  end

  # Private function to handle poll vote casting for different voting systems
  defp cast_poll_votes(poll_id, temp_votes, user) do
    # Get the poll to determine voting system
    poll = Events.get_poll!(poll_id)

    # Cast votes based on the voting system
    # Handle different temp_votes structures
    votes_to_cast =
      case temp_votes do
        %{votes: votes, poll_type: :ranked} ->
          # Convert ranked structure to expected format
          Enum.map(votes, fn %{rank: rank, option_id: option_id} ->
            {option_id, rank}
          end)

        map when is_map(map) ->
          # Regular map structure
          Enum.to_list(map)

        _ ->
          []
      end

    # Short-circuit empty submissions
    if votes_to_cast == [] do
      [{:error, :no_votes}]
    else
      # Handle ranked voting separately (needs all votes at once)
      if poll.voting_system == "ranked" do
        # For ranked voting, submit all votes at once
        # cast_ranked_votes properly clears existing votes first in a transaction
        case Events.cast_ranked_votes(poll, votes_to_cast, user) do
          {:ok, votes} -> Enum.map(votes, fn v -> {:ok, v} end)
          {:error, reason} -> [{:error, reason}]
        end
      else
        # For other voting systems, process votes individually
        for {option_id, vote_value} <- votes_to_cast do
          case Events.get_poll_option(option_id) do
            nil ->
              {:error, :option_not_found}

            poll_option ->
              case poll.voting_system do
                "binary" ->
                  Events.cast_binary_vote(poll, poll_option, user, vote_value)

                "approval" when vote_value == "selected" ->
                  Events.cast_approval_vote(poll, poll_option, user, true)

                "star" ->
                  # Safely parse and clamp rating to 1–5
                  case vote_value do
                    i when is_integer(i) ->
                      Events.cast_star_vote(poll, poll_option, user, i |> min(5) |> max(1))

                    s when is_binary(s) ->
                      case Integer.parse(s) do
                        {i, ""} ->
                          Events.cast_star_vote(poll, poll_option, user, i |> min(5) |> max(1))

                        _ ->
                          {:error, :invalid_rating}
                      end

                    _ ->
                      {:error, :invalid_rating}
                  end

                _ ->
                  {:error, :unsupported_voting_system}
              end
          end
        end
      end
    end
  end
end
