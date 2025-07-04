defmodule EventasaurusWeb.PublicEventLive do
    use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Ticketing
  alias EventasaurusWeb.EventRegistrationComponent
  alias EventasaurusWeb.AnonymousVoterComponent
  alias EventasaurusWeb.ReservedSlugs

  import EventasaurusWeb.EventComponents, only: [ticket_selection_component: 1]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    IO.puts("=== MOUNT FUNCTION CALLED ===")
    IO.puts("auth_user: #{inspect(socket.assigns.auth_user)}")
    require Logger
    Logger.debug("PublicEventLive.mount called with auth_user: #{inspect(socket.assigns.auth_user)}")

    if ReservedSlugs.reserved?(slug) do
      {:ok,
       socket
       |> put_flash(:error, "Event not found")
       |> redirect(to: ~p"/")
      }
    else
      case Events.get_event_by_slug(slug) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Event not found")
           |> redirect(to: ~p"/")
          }

        event ->
          # Load venue if needed
          venue = if event.venue_id, do: Venues.get_venue(event.venue_id), else: nil
          organizers = Events.list_event_organizers(event)

          # Load participants for social proof
          participants = Events.list_event_participants(event)

          # Load tickets for events that have ticket types (ticketed_event or contribution_collection)
          should_show_tickets = event.taxation_type in ["ticketed_event", "contribution_collection"]
          tickets = if should_show_tickets do
            Ticketing.list_tickets_for_event(event.id)
          else
            []
          end

          # Subscribe to real-time ticket updates for events with tickets
          subscribed_to_tickets = if should_show_tickets do
            Ticketing.subscribe()
            true
          else
            false
          end

          # Determine registration status if user is authenticated
          Logger.debug("PublicEventLive.mount - auth_user: #{inspect(socket.assigns.auth_user)}")
          {registration_status, user} = case ensure_user_struct(socket.assigns.auth_user) do
            {:ok, user} ->
              Logger.debug("PublicEventLive.mount - user found: #{inspect(user)}")
              status = Events.get_user_registration_status(event, user)
              Logger.debug("PublicEventLive.mount - registration status: #{inspect(status)}")
              {status, user}
            {:error, reason} ->
              Logger.debug("PublicEventLive.mount - no user found, reason: #{inspect(reason)}")
              {:not_authenticated, nil}
          end

          # Load date poll data if event has polling enabled
          {date_poll, date_options, user_votes} = if event.status == :polling do
            poll = Events.get_event_date_poll(event)
            if poll do
              options = Events.list_event_date_options(poll)
              votes = case user do
                nil -> []
                user -> Events.list_user_votes_for_poll(poll, user)
              end
              {poll, options, votes}
            else
              {nil, [], []}
            end
          else
            {nil, [], []}
          end

          # Apply event theme to layout
          theme = event.theme || :minimal

          # Prepare meta tag data for social sharing
          event_url = url(socket, ~p"/#{event.slug}")
          social_image_url = social_card_url(socket, event)
          description = truncate_description(event.description || "Join us for #{event.title}")

          {:ok,
           socket
           |> assign(:event, event)
           |> assign(:venue, venue)
           |> assign(:organizers, organizers)
           |> assign(:participants, participants)
           |> assign(:registration_status, registration_status)
           |> assign(:user, user)
           |> assign(:theme, theme)
           |> assign(:show_registration_modal, false)
           |> assign(:just_registered, false)
           |> assign(:page_title, event.title)
           |> assign(:date_poll, date_poll)
           |> assign(:date_options, date_options)
           |> assign(:user_votes, user_votes)
           |> assign(:pending_vote, nil)
           |> assign(:show_vote_modal, false)
           |> assign(:temp_votes, %{})  # Map of option_id => vote_type for anonymous users
           |> assign(:tickets, tickets)
           |> assign(:selected_tickets, %{})  # Map of ticket_id => quantity
           |> assign(:ticket_loading, false)
           |> assign(:subscribed_to_tickets, subscribed_to_tickets)
           |> assign(:should_show_tickets, should_show_tickets)
           # Meta tag data for social sharing
           |> assign(:meta_title, event.title)
           |> assign(:meta_description, description)
           |> assign(:meta_image, social_image_url)
           |> assign(:meta_url, event_url)
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
             })
          }
      end
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

  @impl true
  def handle_event("show_registration_modal", _params, socket) do
    {:noreply, assign(socket, :show_registration_modal, true)}
  end

  def handle_event("close_vote_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_vote_modal, false)
     |> assign(:pending_vote, nil)
    }
  end

  def handle_event("save_all_votes", _params, socket) do
    # Only for anonymous users with temporary votes
    case ensure_user_struct(socket.assigns.auth_user) do
      {:error, _} when map_size(socket.assigns.temp_votes) > 0 ->
        {:noreply, assign(socket, :show_vote_modal, true)}
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("one_click_register", _params, socket) do
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        case Events.one_click_register(socket.assigns.event, user) do
          {:ok, _participant} ->
            # Reload participants to show updated count and list
            updated_participants = Events.list_event_participants(socket.assigns.event)

            {:noreply,
             socket
             |> assign(:registration_status, :registered)
             |> assign(:just_registered, false)  # Existing users don't need email verification
             |> assign(:participants, updated_participants)
             |> put_flash(:info, "You're now registered for #{socket.assigns.event.title}!")
             |> push_event("track_event", %{
                 event: "event_registration_completed",
                 properties: %{
                   event_id: socket.assigns.event.id,
                   event_title: socket.assigns.event.title,
                   event_slug: socket.assigns.event.slug,
                   user_type: "authenticated",
                   registration_method: "one_click"
                 }
               })
            }

          {:error, :already_registered} ->
            {:noreply,
             socket
             |> put_flash(:error, "You're already registered for this event.")
            }

          {:error, :organizer_cannot_register} ->
            {:noreply,
             socket
             |> put_flash(:error, "As an event organizer, you don't need to register for your own event.")
            }

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to register: #{inspect(reason)}")
            }
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please log in to register for this event.")
        }
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
             |> put_flash(:info, "Your registration has been cancelled.")
            }

          {:error, :not_registered} ->
            {:noreply,
             socket
             |> put_flash(:error, "You're not registered for this event.")
            }

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to cancel registration: #{inspect(reason)}")
            }
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please log in to manage your registration.")
        }
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
             |> assign(:just_registered, false)  # Existing users don't need email verification
             |> assign(:participants, updated_participants)
             |> put_flash(:info, "Welcome back! You're now registered for #{socket.assigns.event.title}.")
             |> push_event("track_event", %{
                 event: "event_registration_completed",
                 properties: %{
                   event_id: socket.assigns.event.id,
                   event_title: socket.assigns.event.title,
                   event_slug: socket.assigns.event.slug,
                   user_type: "authenticated",
                   registration_method: "reregister"
                 }
               })
            }

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to register: #{inspect(reason)}")
            }
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please log in to register for this event.")
        }
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
             |> put_flash(:info, "Theme switched to #{String.capitalize(new_theme)}!")
            }

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to switch theme: #{inspect(reason)}")
            }
        end

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Only event organizers can switch themes.")
        }
    end
  end

  def handle_event("manage_event", _params, socket) do
    # Redirect to the event management page
    event_slug = socket.assigns.event.slug
    {:noreply, push_navigate(socket, to: "/events/#{event_slug}/edit")}
  end

  def handle_event("cast_vote", %{"option_id" => option_id, "vote_type" => vote_type}, socket) do
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        # Authenticated user - proceed with normal voting flow
        option_id_int = String.to_integer(option_id)
        option = Enum.find(socket.assigns.date_options, &(&1.id == option_id_int))

                if option do
          vote_type_atom = String.to_atom(vote_type)

          case Events.cast_vote(option, user, vote_type_atom) do
            {:ok, _vote} ->
              # Reload user votes and voting summary
              user_votes = Events.list_user_votes_for_poll(socket.assigns.date_poll, user)
              voting_summary = Events.get_poll_vote_tallies(socket.assigns.date_poll)

              {:noreply,
               socket
               |> assign(:user_votes, user_votes)
               |> assign(:voting_summary, voting_summary)
               |> put_flash(:info, "Your vote has been recorded!")
               |> push_event("track_event", %{
                   event: "event_date_vote_cast",
                   properties: %{
                     event_id: socket.assigns.event.id,
                     event_title: socket.assigns.event.title,
                     event_slug: socket.assigns.event.slug,
                     poll_id: socket.assigns.date_poll.id,
                     option_id: option.id,
                     vote_type: vote_type_atom,
                     user_type: "authenticated"
                   }
                 })
              }

            {:error, reason} ->
              {:noreply,
               socket
               |> put_flash(:error, "Unable to cast vote: #{inspect(reason)}")
              }
          end
        else
          {:noreply,
           socket
           |> put_flash(:error, "Invalid voting option")
          }
        end

      {:error, _} ->
        # Anonymous user - store vote temporarily in assigns
        option_id_int = String.to_integer(option_id)

        # Validate option exists
        unless Enum.any?(socket.assigns.date_options, &(&1.id == option_id_int)) do
          {:noreply, put_flash(socket, :error, "Invalid voting option")}
        else
          vote_type_atom = String.to_atom(vote_type)

          updated_temp_votes = Map.put(socket.assigns.temp_votes, option_id_int, vote_type_atom)

          {:noreply,
           socket
           |> assign(:temp_votes, updated_temp_votes)
          }
        end
    end
  end

  def handle_event("remove_vote", %{"option_id" => option_id}, socket) do
    case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        option_id_int = String.to_integer(option_id)
        option = Enum.find(socket.assigns.date_options, &(&1.id == option_id_int))

        if option do
          case Events.remove_user_vote(option, user) do
            {:ok, _} ->
              # Reload user votes and voting summary
              user_votes = Events.list_user_votes_for_poll(socket.assigns.date_poll, user)
              voting_summary = Events.get_poll_vote_tallies(socket.assigns.date_poll)

              {:noreply,
               socket
               |> assign(:user_votes, user_votes)
               |> assign(:voting_summary, voting_summary)
               |> put_flash(:info, "Your vote has been removed.")
              }

            {:error, reason} ->
              {:noreply,
               socket
               |> put_flash(:error, "Unable to remove vote: #{inspect(reason)}")
              }
          end
        else
          {:noreply,
           socket
           |> put_flash(:error, "Invalid voting option")
          }
        end

      {:error, _} ->
        # Anonymous user - remove from temporary votes
        option_id_int = String.to_integer(option_id)
        updated_temp_votes = Map.delete(socket.assigns.temp_votes, option_id_int)

        {:noreply,
         socket
         |> assign(:temp_votes, updated_temp_votes)
         |> put_flash(:info, "Vote removed from your temporary votes.")
        }
    end
  end

  # ======== TICKET SELECTION HANDLERS ========

  def handle_event("increase_ticket_quantity", %{"ticket_id" => ticket_id}, socket) do
    ticket_id = String.to_integer(ticket_id)
    tickets = socket.assigns.tickets
    ticket = Enum.find(tickets, &(&1.id == ticket_id))

    if ticket do
      current_quantity = Map.get(socket.assigns.selected_tickets, ticket_id, 0)
      available_quantity = Ticketing.available_quantity(ticket)
      max_per_order = 10  # Set reasonable limit

      new_quantity = if current_quantity < available_quantity and current_quantity < max_per_order do
        current_quantity + 1
      else
        current_quantity
      end

      # Only update if quantity actually changed
      if new_quantity != current_quantity do
        updated_selection = Map.put(socket.assigns.selected_tickets, ticket_id, new_quantity)

        socket = socket
        |> assign(:selected_tickets, updated_selection)

        # Show feedback if at limit
        socket = if new_quantity == available_quantity do
          put_flash(socket, :warning, "Maximum available tickets selected for #{ticket.title}")
        else
          socket
        end

        {:noreply, socket}
      else
        # At limit - show feedback
        message = cond do
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
    updated_selection = if new_quantity == 0 do
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

          {:noreply,
           socket
           |> push_event("track_event", %{
               event: "ticket_checkout_initiated",
               properties: %{
                 event_id: socket.assigns.event.id,
                 event_title: socket.assigns.event.title,
                 event_slug: socket.assigns.event.slug,
                 user_type: "anonymous",
                 ticket_selections: selected_tickets,
                 total_tickets: Enum.sum(Map.values(selected_tickets))
               }
             })
           |> redirect(to: "/events/#{socket.assigns.event.slug}/checkout?" <> query)
          }

        user ->
          # User is logged in - create Stripe hosted checkout session directly
          create_authenticated_stripe_checkout(socket, user, selected_tickets)
      end
    end
  end

  def handle_event("show_auth_modal", _params, socket) do
    {:noreply, assign(socket, :show_registration_modal, true)}
  end

  # Authenticated user Stripe hosted checkout
  defp create_authenticated_stripe_checkout(socket, user, selected_tickets) do
    # For now, handle single ticket type only (can be extended for multiple types)
    case get_single_ticket_selection(socket.assigns.tickets, selected_tickets) do
      {:ok, ticket, quantity} ->
        Logger.info("Creating Stripe hosted checkout for authenticated user",
          user_id: user.id,
          event_slug: socket.assigns.event.slug,
          ticket_id: ticket.id,
          quantity: quantity
        )

        case Ticketing.create_checkout_session(user, ticket, %{quantity: quantity}) do
          {:ok, %{checkout_url: checkout_url, session_id: session_id}} ->
            Logger.info("Stripe hosted checkout session created",
              user_id: user.id,
              session_id: session_id
            )

            # Redirect to Stripe hosted checkout
            {:noreply,
             socket
             |> push_event("track_event", %{
                 event: "ticket_checkout_initiated",
                 properties: %{
                   event_id: socket.assigns.event.id,
                   event_title: socket.assigns.event.title,
                   event_slug: socket.assigns.event.slug,
                   user_type: "authenticated",
                   ticket_id: ticket.id,
                   ticket_title: ticket.title,
                   quantity: quantity,
                   session_id: session_id
                 }
               })
             |> redirect(external: checkout_url)}

          {:error, :no_stripe_account} ->
            {:noreply,
             socket
             |> put_flash(:error, "The event organizer has not set up payment processing. Please contact them directly.")}

          {:error, :ticket_unavailable} ->
            {:noreply,
             socket
             |> put_flash(:error, "Sorry, these tickets are no longer available.")}

          {:error, reason} ->
            Logger.error("Failed to create authenticated checkout session",
              user_id: user.id,
              ticket_id: ticket.id,
              reason: inspect(reason)
            )
            {:noreply,
             socket
             |> put_flash(:error, "Unable to process payment. Please try again.")}
        end

      # Multiple ticket types are now supported in both checkout flows

      {:error, :no_tickets_selected} ->
        {:noreply,
         socket
         |> put_flash(:error, "Please select at least one ticket before proceeding.")}
    end
  end

  # TEMPORARY compatibility shim: when multiple tickets are selected, only the first is returned.
  # TODO: Remove once all callers support multi-ticket flows.
  defp get_single_ticket_selection(tickets, selected_tickets) do
    selected_items =
      selected_tickets
      |> Enum.filter(fn {_id, qty} -> qty > 0 end)
      |> Enum.map(fn {ticket_id, quantity} ->
        ticket = Enum.find(tickets, &(&1.id == ticket_id))
        {ticket, quantity}
      end)
      |> Enum.filter(fn {ticket, _qty} -> ticket != nil end)

    case selected_items do
      [] -> {:error, :no_tickets_selected}
      # Multiple ticket types are now supported - we only use this function for legacy compatibility
      [{ticket, quantity}] -> {:ok, ticket, quantity}
      multiple_items ->
        # TEMPORARY: returning only the first ticket for legacy compatibility
        Logger.warning("get_single_ticket_selection called with multiple items; returning first for compatibility")
        {:ok, hd(multiple_items) |> elem(0), hd(multiple_items) |> elem(1)}
    end
  end

  @impl true
  def handle_info(:close_registration_modal, socket) do
    {:noreply, assign(socket, :show_registration_modal, false)}
  end

  # ======== HANDLE_INFO CALLBACKS ========

  def handle_info({:registration_success, type, _name, _email}, socket) do
    message = case type do
      :new_registration -> "Successfully registered for #{socket.assigns.event.title}! Please check your email for a magic link to create your account."
      :existing_user_registered -> "Successfully registered for #{socket.assigns.event.title}!"
      :registered -> "Successfully registered for #{socket.assigns.event.title}!"
      :already_registered -> "You are already registered for this event."
    end

    # Reload participants to show updated count
    updated_participants = Events.list_event_participants(socket.assigns.event)

    # Only show email verification for truly new registrations
    just_registered = case type do
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
     |> assign(:participants, updated_participants)
     |> push_event("track_event", %{
         event: "event_registration_completed",
         properties: %{
           event_id: socket.assigns.event.id,
           event_title: socket.assigns.event.title,
           event_slug: socket.assigns.event.slug,
           user_type: case type do
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

  def handle_info({:registration_error, reason}, socket) do
    error_message = case reason do
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
     |> put_flash(:error, error_message)
    }
  end

  def handle_info(:close_vote_modal, socket) do
    {:noreply,
     socket
     |> assign(:show_vote_modal, false)
     |> assign(:pending_vote, nil)
    }
  end

  def handle_info({:vote_success, type, _name, email}, socket) do
    message = case type do
      :new_voter ->
        "Thanks! Your vote has been recorded. Please check your email for a magic link to create your account."
      :existing_user_voted ->
        "Great! Your vote has been recorded."
    end

    # Reload vote data to show the updated vote
    user_votes = case socket.assigns.auth_user do
      nil ->
        # For anonymous users, try to find the user by email to show their votes
        user = Accounts.get_user_by_email(email)
        if user do
          Events.list_user_votes_for_poll(socket.assigns.date_poll, user)
        else
          []
        end
      auth_user ->
        # For authenticated users, reload their votes normally
        case ensure_user_struct(auth_user) do
          {:ok, user} -> Events.list_user_votes_for_poll(socket.assigns.date_poll, user)
          {:error, _} -> []
        end
    end

    # Reload voting summary as well
    voting_summary = Events.get_poll_vote_tallies(socket.assigns.date_poll)

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
           poll_id: socket.assigns.date_poll.id,
           user_type: case type do
             :new_voter -> "new_user"
             :existing_user_voted -> "existing_user"
           end,
           vote_method: "anonymous_form",
           vote_type: type
         }
       })
    }
  end

  def handle_info({:vote_error, reason}, socket) do
    error_message = case reason do
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
     |> put_flash(:error, error_message)
    }
  end

  def handle_info({:save_all_votes_for_user, event_id, name, email, temp_votes, date_options}, socket) do
    # Convert temp_votes map to the format expected by bulk operations
    votes_data = for {option_id, vote_type} <- temp_votes do
      option = Enum.find(date_options, &(&1.id == option_id))
      %{option: option, vote_type: vote_type}
    end

    # Use bulk vote operation for better performance
    case Events.register_voter_and_bulk_cast_votes(event_id, name, email, votes_data) do
      {:ok, result_type, _participant, _vote_results} ->
        # Get the user from the database to update socket assigns
        user = Accounts.get_user_by_email(email)

        # Reload user votes to show updated state
        user_votes = if user do
          Events.list_user_votes_for_poll(socket.assigns.date_poll, user)
        else
          []
        end

        # Reload voting summary as well
        voting_summary = Events.get_poll_vote_tallies(socket.assigns.date_poll)

        message = case result_type do
          :new_voter ->
            "All #{map_size(temp_votes)} votes saved successfully! You're now registered for #{socket.assigns.event.title}. Please check your email for a magic link to create your account."
          :existing_user_voted ->
            "All #{map_size(temp_votes)} votes saved successfully! You're registered for #{socket.assigns.event.title}."
        end

        {:noreply,
         socket
         |> assign(:show_vote_modal, false)
         |> assign(:temp_votes, %{})
         |> assign(:user_votes, user_votes)
         |> assign(:voting_summary, voting_summary)
         |> assign(:registration_status, :registered)  # Update registration status
         |> assign(:user, user)  # Set the user so they see authenticated UI
         |> assign(:just_registered, result_type == :new_voter)  # Show email verification for new users
         |> put_flash(:info, message)
        }

      {:error, reason} ->
        error_message = case reason do
          :event_not_found -> "Event not found."
          :email_confirmation_required -> "A magic link has been sent to your email. Please click the link to verify your email address, then try voting again."
          _ -> "Failed to save votes. Please try again."
        end

        {:noreply,
         socket
         |> assign(:show_vote_modal, false)
         |> put_flash(:error, error_message)
        }
    end
  end

  # ======== REAL-TIME TICKET UPDATES ========

  def handle_info({:ticket_update, %{ticket: updated_ticket, action: action}}, socket) do
    # Only update if this is for the current event and we're showing tickets
    if updated_ticket.event_id == socket.assigns.event.id and socket.assigns.should_show_tickets do
      # Set loading state
      socket = assign(socket, :ticket_loading, true)

      # Refresh tickets to get updated availability
      updated_tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)

      # Update socket with fresh ticket data
      socket = socket
      |> assign(:tickets, updated_tickets)
      |> assign(:ticket_loading, false)

      # Show user-friendly notification for certain actions
      socket = case action do
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

  def handle_info({:order_update, %{order: _order, action: _action}}, socket) do
    # Handle order updates if needed for this event
    # For now, we mainly care about ticket availability changes
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
         <!-- Public Event Show Page with mobile-first layout -->
     <div class="container mx-auto px-4 sm:px-6 py-6 sm:py-12 max-w-7xl">
       <div class="event-page-grid grid grid-cols-1 lg:grid-cols-3 gap-6 lg:gap-12">
                 <div class="main-content lg:col-span-2">
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
              <div class="mb-3">
                <h3 class="font-semibold text-gray-900 mb-1">When</h3>
                <div class="text-gray-700">
                  <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%a, %b %d") %>
                  <%= if @event.ends_at do %>
                    · <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%I:%M %p") |> String.replace(" 0", " ") %> - <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.ends_at, @event.timezone) |> Calendar.strftime("%I:%M %p") |> String.replace(" 0", " ") %>
                  <% else %>
                    · <%= EventasaurusWeb.TimezoneHelpers.convert_to_timezone(@event.start_at, @event.timezone) |> Calendar.strftime("%I:%M %p") |> String.replace(" 0", " ") %>
                  <% end %>
                  <span class="text-gray-500"><%= @event.timezone %></span>
                </div>
              </div>

              <!-- Where Section -->
              <div class="flex items-start gap-3">
                <div class="flex-shrink-0">
                  <%= if @event.venue_id == nil do %>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  <% else %>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                  <% end %>
                </div>
                <div>
                  <h3 class="font-semibold text-gray-900 mb-1">Where</h3>
                  <%= if @event.venue_id == nil do %>
                    <p class="text-gray-700">Virtual Event</p>
                  <% else %>
                    <%= if @venue do %>
                      <p class="text-gray-700"><%= @venue.address %></p>
                    <% else %>
                      <p class="text-gray-600">Location details not available</p>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <!-- Cover image -->
          <%= if @event.cover_image_url && @event.cover_image_url != "" do %>
            <div class="relative w-full aspect-video rounded-xl overflow-hidden mb-8 shadow-lg border border-gray-200">
              <img src={@event.cover_image_url} alt={@event.title} class="absolute inset-0 w-full h-full object-cover" />
            </div>
          <% end %>

          <!-- Description -->
          <%= if @event.description && @event.description != "" do %>
            <div class="bg-white border border-gray-200 rounded-xl p-6 mb-8 shadow-sm">
              <h2 class="text-xl font-semibold mb-4 text-gray-900">About This Event</h2>
              <div class="prose max-w-none text-gray-700">
                <%= Phoenix.HTML.raw(Earmark.as_html!(@event.description)) %>
              </div>
            </div>
          <% else %>
            <div class="bg-white border border-gray-200 rounded-xl p-6 mb-8 shadow-sm">
              <h2 class="text-xl font-semibold mb-4 text-gray-900">About This Event</h2>
              <p class="text-gray-500">No description provided for this event.</p>
            </div>
          <% end %>

                     <!-- Date Voting Interface (only show for polling events) -->
           <%= if @event.status == :polling and not is_nil(@date_poll) and @date_options != [] do %>
             <div class="mobile-voting-simplified bg-white border border-gray-200 rounded-xl p-6 mb-8 shadow-sm" data-testid="voting-interface">
              <div class="flex items-center gap-3 mb-4">
                <div class="w-10 h-10 bg-blue-600 rounded-full flex items-center justify-center">
                  <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                </div>
                <div>
                  <h2 class="text-xl font-semibold text-gray-900">Vote on Event Date</h2>
                  <p class="text-sm text-gray-600">Help us find the best date that works for everyone</p>
                </div>
              </div>

              <%= if @user do %>
                <!-- Voting interface for authenticated users -->
                <div class="space-y-4">
                  <%= for option <- @date_options do %>
                    <% user_vote = Enum.find(@user_votes, &(&1.event_date_option_id == option.id)) %>
                    <% vote_tally = Events.get_date_option_vote_tally(option) %>

                    <div class="border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                      <div class="flex items-center justify-between mb-3">
                        <div class="flex-1">
                          <h3 class="font-medium text-gray-900">
                            <%= Calendar.strftime(option.date, "%A, %B %d, %Y") %>
                          </h3>
                          <p class="text-sm text-gray-500">
                            <%= vote_tally.total %> <%= if vote_tally.total == 1, do: "vote", else: "votes" %>
                            · <%= vote_tally.percentage %>% positive
                          </p>
                        </div>
                        <%= if user_vote do %>
                          <div class="flex items-center gap-2">
                            <span class="text-sm font-medium text-green-600">
                              Your vote: <%= EventasaurusApp.Events.EventDateVote.vote_type_display(user_vote) %>
                            </span>
                            <button
                              phx-click="remove_vote"
                              phx-value-option_id={option.id}
                              class="text-gray-400 hover:text-gray-600 transition-colors"
                              title="Remove vote"
                            >
                              <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                              </svg>
                            </button>
                          </div>
                        <% end %>
                      </div>

                      <!-- Vote tally visualization -->
                      <div class="mb-3">
                        <div class="flex h-2 bg-gray-100 rounded-full overflow-hidden">
                          <%= if vote_tally.total > 0 do %>
                            <div class="bg-green-500" style={"width: #{(vote_tally.yes / vote_tally.total) * 100}%"}></div>
                            <div class="bg-yellow-400" style={"width: #{(vote_tally.if_need_be / vote_tally.total) * 100}%"}></div>
                            <div class="bg-red-400" style={"width: #{(vote_tally.no / vote_tally.total) * 100}%"}></div>
                          <% end %>
                        </div>
                        <div class="flex justify-between text-xs text-gray-500 mt-1">
                          <span>Yes: <%= vote_tally.yes %></span>
                          <span>If needed: <%= vote_tally.if_need_be %></span>
                          <span>No: <%= vote_tally.no %></span>
                        </div>
                      </div>

                                             <!-- Voting buttons -->
                       <div class="voting-buttons flex gap-2">
                        <button
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="yes"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 " <>
                            if user_vote && user_vote.vote_type == :yes do
                              "bg-green-600 text-white"
                            else
                              "bg-green-50 text-green-700 hover:bg-green-100 border border-green-200"
                            end
                          }
                        >
                          Yes
                        </button>
                        <button
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="if_need_be"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 " <>
                            if user_vote && user_vote.vote_type == :if_need_be do
                              "bg-yellow-500 text-white"
                            else
                              "bg-yellow-50 text-yellow-700 hover:bg-yellow-100 border border-yellow-200"
                            end
                          }
                        >
                          If needed
                        </button>
                        <button
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="no"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 " <>
                            if user_vote && user_vote.vote_type == :no do
                              "bg-red-600 text-white"
                            else
                              "bg-red-50 text-red-700 hover:bg-red-100 border border-red-200"
                            end
                          }
                        >
                          No
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <!-- Anonymous users see voting buttons and can start voting process -->
                <div class="space-y-4">
                  <%= for option <- @date_options do %>
                    <% vote_tally = Events.get_date_option_vote_tally(option) %>
                    <% temp_vote = Map.get(@temp_votes, option.id) %>

                    <div class="border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
                      <div class="flex items-center justify-between mb-3">
                        <div class="flex-1">
                          <h3 class="font-medium text-gray-900">
                            <%= Calendar.strftime(option.date, "%A, %B %d, %Y") %>
                          </h3>
                          <p class="text-sm text-gray-500">
                            All day
                          </p>
                        </div>
                        <div class="text-sm text-gray-500">
                          <%= vote_tally.total %> votes
                        </div>
                      </div>

                      <div class="flex gap-2">
                        <button
                          type="button"
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="yes"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 " <>
                            if temp_vote == :yes do
                              "bg-green-600 text-white"
                            else
                              "bg-green-50 text-green-700 hover:bg-green-100 border border-green-200"
                            end
                          }
                        >
                          Yes
                        </button>

                        <button
                          type="button"
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="if_need_be"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 " <>
                            if temp_vote == :if_need_be do
                              "bg-yellow-500 text-white"
                            else
                              "bg-yellow-50 text-yellow-700 hover:bg-yellow-100 border border-yellow-200"
                            end
                          }
                        >
                          If needed
                        </button>

                        <button
                          type="button"
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="no"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 " <>
                            if temp_vote == :no do
                              "bg-red-600 text-white"
                            else
                              "bg-red-50 text-red-700 hover:bg-red-100 border border-red-200"
                            end
                          }
                        >
                          No
                        </button>
                      </div>
                    </div>
                  <% end %>

                  <%= if map_size(@temp_votes) > 0 do %>
                    <div class="mt-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
                      <h3 class="font-medium text-blue-900 mb-2">Ready to save your votes?</h3>
                      <p class="text-sm text-blue-700 mb-3">
                        You've voted on <%= map_size(@temp_votes) %> date option(s). Click below to save your votes.
                      </p>
                      <button
                        type="button"
                        phx-click="save_all_votes"
                        class="w-full bg-blue-600 text-white px-4 py-2 rounded-md font-medium hover:bg-blue-700 transition-colors"
                      >
                        Save My Votes
                      </button>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>

          <!-- Host section -->
          <div class="border-t border-gray-200 pt-6 mt-6">
            <h3 class="text-lg font-semibold mb-4 text-gray-900">Hosted by</h3>
            <div class="flex items-center space-x-3">
              <%= if Ecto.assoc_loaded?(@event.users) and @event.users != [] do %>
                <%= avatar_img_size(hd(@event.users), :lg, class: "border border-gray-200") %>
                <div>
                  <div class="font-medium text-gray-900"><%= hd(@event.users).name %></div>
                  <a href="#" class="text-blue-600 hover:text-blue-800 text-sm font-medium">View other events</a>
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
          <%
            # Filter valid participants once for consistency across all UI elements
            valid_participants = Enum.filter(@participants, fn participant ->
              participant.user && participant.user.name
            end)
          %>
          <%= if length(valid_participants) > 0 do %>
            <div class="border-t border-gray-200 pt-6 mt-6">
              <%
                displayed_avatars = Enum.take(valid_participants, 10)
                remaining_count = length(valid_participants) - length(displayed_avatars)
              %>

              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold text-gray-900">
                  <%= length(valid_participants) %> Going
                </h3>
              </div>

                                          <!-- Stacked Avatars -->
              <div class="flex items-center mb-3">
                <%!-- Show only the first 10 valid participants --%>
                <%= for {participant, index} <- Enum.with_index(displayed_avatars) do %>
                  <div class={[
                    "relative group",
                    if(index > 0, do: "-ml-2", else: "")
                  ]}
                    role="img"
                    aria-label={participant.user.name}
                    aria-describedby={"tooltip-#{participant.id}"}
                    tabindex="0">
                    <%= avatar_img_size(participant.user, :md,
                          class: "border-2 border-white rounded-full shadow-sm hover:scale-110 transition-transform duration-200 cursor-pointer relative"
                        ) %>

                    <!-- Tooltip on hover -->
                    <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-2 py-1 bg-gray-900 text-white text-xs rounded-md opacity-0 group-hover:opacity-100 group-focus:opacity-100 transition-opacity duration-200 pointer-events-none whitespace-nowrap z-50"
                         role="tooltip"
                         id={"tooltip-#{participant.id}"}
                         aria-hidden="true">
                      <%= participant.user.name %>
                      <div class="absolute top-full left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-gray-900"></div>
                    </div>
                  </div>
                <% end %>

                <%!-- Show overflow indicator only if there are more valid participants than displayed --%>
                <%= if remaining_count > 0 do %>
                  <div class="relative -ml-2 w-10 h-10 bg-gray-100 rounded-full border-2 border-white flex items-center justify-center text-sm font-medium text-gray-600 shadow-sm">
                    +<%= remaining_count %>
                  </div>
                <% end %>
              </div>

              <!-- Participant Names -->
              <%= if length(valid_participants) > 0 do %>
                <div class="text-sm text-gray-600 dark:text-gray-400">
                  <%= format_participant_summary(valid_participants) %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

                 <!-- Right sidebar -->
         <div class="sidebar-content lg:col-span-1">
          <!-- Ticket Selection Section (for events with tickets) -->
          <%= if @should_show_tickets and @event.status in [:confirmed] do %>
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
                <!-- Anonymous user - show current registration modal -->
                <button
                  id="register-now-btn"
                  phx-click="show_registration_modal"
                  class="bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-6 rounded-lg w-full flex items-center justify-center transition-colors duration-200"
                >
                  Register for Event
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 ml-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M14 5l7 7m0 0l-7 7m7-7H3" />
                  </svg>
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
                <button
                  phx-click="one_click_register"
                  class="bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-6 rounded-lg w-full transition-colors duration-200"
                >
                  One-Click Register
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

                  <div class="flex gap-2 mb-4">
                    <button class="flex-1 bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium py-2 px-4 rounded-lg text-sm transition-colors duration-200">
                      Add to Calendar
                    </button>
                    <button class="bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium py-2 px-4 rounded-lg text-sm transition-colors duration-200">
                      Share
                    </button>
                  </div>

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

                  <div class="flex gap-2 mb-4">
                    <button class="flex-1 bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium py-2 px-4 rounded-lg text-sm transition-colors duration-200">
                      Add to Calendar
                    </button>
                    <button class="bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium py-2 px-4 rounded-lg text-sm transition-colors duration-200">
                      Share
                    </button>
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
               <span id="show-more-text">Show sharing options</span>
               <svg id="show-more-icon" xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 inline ml-1 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                 <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
               </svg>
             </button>
           </div>

                     <!-- Share buttons -->
           <div id="mobile-secondary-actions" class="mobile-secondary-actions bg-white border border-gray-200 rounded-xl p-5 shadow-sm mb-4">
            <h3 class="text-base font-semibold mb-3 text-gray-900">Share this event</h3>
            <div class="flex space-x-3">
              <a href={"https://twitter.com/intent/tweet?text=Check out #{@event.title}&url=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" class="bg-gray-100 hover:bg-gray-200 text-gray-600 p-2 rounded-full transition-colors duration-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M22.162 5.656a8.384 8.384 0 0 1-2.402.658A4.196 4.196 0 0 0 21.6 4c-.82.488-1.719.83-2.656 1.015a4.182 4.182 0 0 0-7.126 3.814 11.874 11.874 0 0 1-8.62-4.37 4.168 4.168 0 0 0-.566 2.103c0 1.45.738 2.731 1.86 3.481a4.168 4.168 0 0 1-1.894-.523v.052a4.185 4.185 0 0 0 3.355 4.101 4.21 4.21 0 0 1-1.89.072A4.185 4.185 0 0 0 7.97 16.65a8.394 8.394 0 0 1-6.191 1.732 11.83 11.83 0 0 0 6.41 1.88c7.693 0 11.9-6.373 11.9-11.9 0-.18-.005-.362-.013-.54a8.496 8.496 0 0 0 2.087-2.165z"/></svg>
              </a>
              <a href={"https://www.facebook.com/sharer/sharer.php?u=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" class="bg-gray-100 hover:bg-gray-200 text-gray-600 p-2 rounded-full transition-colors duration-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2.04c-5.5 0-10 4.49-10 10.02 0 5 3.66 9.15 8.44 9.9v-7H7.9v-2.9h2.54V9.85c0-2.51 1.49-3.89 3.78-3.89 1.09 0 2.23.19 2.23.19v2.47h-1.26c-1.24 0-1.63.77-1.63 1.56v1.88h2.78l-.45 2.9h-2.33v7a10 10 0 0 0 8.44-9.9c0-5.53-4.5-10.02-10-10.02z"/></svg>
              </a>
              <a href={"https://www.linkedin.com/sharing/share-offsite/?url=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" class="bg-gray-100 hover:bg-gray-200 text-gray-600 p-2 rounded-full transition-colors duration-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M19 3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14m-.5 15.5v-5.3a3.26 3.26 0 0 0-3.26-3.26c-.85 0-1.84.52-2.32 1.3v-1.11h-2.79v8.37h2.79v-4.93c0-.77.62-1.4 1.39-1.4a1.4 1.4 0 0 1 1.4 1.4v4.93h2.79M6.88 8.56a1.68 1.68 0 0 0 1.68-1.68c0-.93-.75-1.69-1.68-1.69a1.69 1.69 0 0 0-1.69 1.69c0 .93.76 1.68 1.69 1.68m1.39 9.94v-8.37H5.5v8.37h2.77z"/></svg>
              </a>
              <button id="copy-link-btn" class="bg-gray-100 hover:bg-gray-200 text-gray-600 p-2 rounded-full transition-colors duration-200" data-clipboard-text={EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}"}>
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
              </button>
            </div>
          </div>

                     <!-- Add to calendar -->
           <div class="mobile-secondary-actions bg-white border border-gray-200 rounded-xl p-5 shadow-sm">
            <h3 class="text-base font-semibold mb-3 text-gray-900">Add to calendar</h3>
            <div class="flex flex-col space-y-2">
              <a href="#" class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-2 transition-colors duration-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                Google Calendar
              </a>
              <a href="#" class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-2 transition-colors duration-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                Apple Calendar
              </a>
              <a href="#" class="text-sm text-gray-600 hover:text-gray-900 flex items-center gap-2 transition-colors duration-200">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                Outlook
              </a>
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
      />
    <% end %>

    <%= if @show_vote_modal and map_size(@temp_votes) > 0 do %>
      <.live_component
        module={AnonymousVoterComponent}
        id="vote-modal"
        event={@event}
        temp_votes={@temp_votes}
        date_options={@date_options}
      />
    <% end %>

         <script>
       // Simple clipboard functionality
       document.getElementById('copy-link-btn').addEventListener('click', function() {
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
             showMoreText.textContent = isExpanded ? 'Show sharing options' : 'Hide sharing options';
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

  # Helper function to generate social card URL
  defp social_card_url(_socket, event) do
    # Use the new hash-based URL format
    base_url = EventasaurusWeb.Endpoint.url()
    hash_path = EventasaurusWeb.SocialCardView.social_card_url(event)
    base_url <> hash_path
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
  # - `%{"id" => supabase_id, ...}`: Raw Supabase user data
  #
  # ## Returns
  # - `{:ok, %User{}}`: Successfully processed user
  # - `{:error, reason}`: Failed to process or no user
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    # Use shared function to find or create user
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}

  # Helper function to format participant summary consistently
  defp format_participant_summary(participants) when length(participants) <= 3 do
    participants
    |> Enum.filter(fn participant -> participant.user && participant.user.name end)
    |> Enum.map(& &1.user.name)
    |> Enum.join(", ")
  end

  defp format_participant_summary(participants) do
    # Take first 3 for consistency instead of random selection
    valid_participants = Enum.filter(participants, fn participant ->
      participant.user && participant.user.name
    end)

    shown_participants = Enum.take(valid_participants, 3)
    remaining_count = length(valid_participants) - 3

    names = shown_participants |> Enum.map(& &1.user.name) |> Enum.join(", ")

    if remaining_count > 0 do
      "#{names} and #{remaining_count} others"
    else
      names
    end
  end

end
