defmodule EventasaurusWeb.PublicEventLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Accounts
  alias EventasaurusWeb.EventRegistrationComponent
  alias EventasaurusWeb.AnonymousVoterComponent
  alias EventasaurusWeb.ReservedSlugs

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
          {date_poll, date_options, user_votes} = if event.state == "polling" do
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
           # Meta tag data for social sharing
           |> assign(:meta_title, event.title)
           |> assign(:meta_description, description)
           |> assign(:meta_image, social_image_url)
           |> assign(:meta_url, event_url)
          }
      end
    end
  end

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
            {:noreply,
             socket
             |> assign(:registration_status, :registered)
             |> assign(:just_registered, false)  # Existing users don't need email verification
             |> put_flash(:info, "You're now registered for #{socket.assigns.event.title}!")
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
            {:noreply,
             socket
             |> assign(:registration_status, :cancelled)
             |> assign(:just_registered, false)
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
            {:noreply,
             socket
             |> assign(:registration_status, :registered)
             |> assign(:just_registered, false)  # Existing users don't need email verification
             |> put_flash(:info, "Welcome back! You're now registered for #{socket.assigns.event.title}.")
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
        option = Enum.find(socket.assigns.date_options, &(&1.id == String.to_integer(option_id)))
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
            }

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to cast vote: #{inspect(reason)}")
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
        option = Enum.find(socket.assigns.date_options, &(&1.id == String.to_integer(option_id)))

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

  def handle_info(:close_registration_modal, socket) do
    {:noreply, assign(socket, :show_registration_modal, false)}
  end

  def handle_info({:registration_success, type, _name, email}, socket) do
    message = case type do
      :new_registration ->
        "Registration successful! You're now registered for #{socket.assigns.event.title}. Please check your email for a magic link to create your account."
      :existing_user_registered ->
        "Great! You're now registered for #{socket.assigns.event.title}."
    end

    # Update the user's registration status and local user info
    # Only set just_registered for new registrations (not existing users)
    updated_socket = case ensure_user_struct(socket.assigns.auth_user) do
      {:ok, user} ->
        socket
        |> assign(:registration_status, :registered)
        |> assign(:user, user)
        |> assign(:just_registered, type == :new_registration)

      {:error, _} ->
        # For new users who just registered, try to find them by email
        user = Accounts.get_user_by_email(email)
        socket
        |> assign(:registration_status, :registered)
        |> assign(:user, user)
        |> assign(:just_registered, true)  # This is always a new registration
    end

    {:noreply,
     updated_socket
     |> assign(:show_registration_modal, false)
     |> put_flash(:info, message)
    }
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
          _ -> "Failed to save votes. Please try again."
        end

        {:noreply,
         socket
         |> assign(:show_vote_modal, false)
         |> put_flash(:error, error_message)
        }
    end
  end

  def render(assigns) do
    ~H"""
    <!-- Public Event Show Page with dynamic theming -->
    <div class="container mx-auto px-6 py-12 max-w-7xl">
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 lg:gap-12">
        <div class="lg:col-span-2">
          <!-- Date/time and main info -->
          <div class="flex items-start gap-4 mb-8">
            <div class="bg-white border border-gray-200 rounded-lg p-3 w-16 h-16 flex flex-col items-center justify-center text-center font-medium shadow-sm">
              <div class="text-xs text-gray-500 uppercase tracking-wide"><%= Calendar.strftime(@event.start_at, "%b") %></div>
              <div class="text-xl font-semibold text-gray-900"><%= Calendar.strftime(@event.start_at, "%d") %></div>
            </div>
            <div>
              <h1 class="text-3xl lg:text-4xl font-bold text-gray-900 mb-4 leading-tight"><%= @event.title %></h1>
              <%= if @event.tagline do %>
                <p class="text-lg text-gray-600 mb-4"><%= @event.tagline %></p>
              <% end %>

              <!-- When Section -->
              <div class="mb-4">
                <h3 class="font-semibold text-gray-900 mb-1">When</h3>
                <div class="text-lg text-gray-700 font-medium">
                  <%= Calendar.strftime(@event.start_at, "%A, %B %d · %I:%M %p") |> String.replace(" 0", " ") %>
                  <%= if @event.ends_at do %>
                    - <%= Calendar.strftime(@event.ends_at, "%I:%M %p") |> String.replace(" 0", " ") %>
                  <% end %>
                  <span class="text-gray-500 ml-1"><%= @event.timezone %></span>
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
                    <p class="text-gray-700 font-medium">Virtual Event</p>
                  <% else %>
                    <%= if @venue do %>
                      <p class="text-gray-700 font-medium"><%= @venue.name %></p>
                      <p class="text-gray-600 text-sm">
                        <%= @venue.address %><br>
                        <%= @venue.city %><%= if @venue.state && @venue.state != "", do: ", #{@venue.state}" %>
                      </p>
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
          <%= if @event.state == "polling" and not is_nil(@date_poll) and @date_options != [] do %>
            <div class="bg-white border border-gray-200 rounded-xl p-6 mb-8 shadow-sm" data-testid="voting-interface">
              <div class="flex items-center gap-3 mb-4">
                <div class="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
                  <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
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
                      <div class="flex gap-2">
                        <button
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="yes"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 #{if user_vote && user_vote.vote_type == :yes, do: "bg-green-600 text-white", else: "bg-green-50 text-green-700 hover:bg-green-100 border border-green-200"}"}
                        >
                          Yes
                        </button>
                        <button
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="if_need_be"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 #{if user_vote && user_vote.vote_type == :if_need_be, do: "bg-yellow-500 text-white", else: "bg-yellow-50 text-yellow-700 hover:bg-yellow-100 border border-yellow-200"}"}
                        >
                          If needed
                        </button>
                        <button
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="no"
                          class={"flex-1 py-2 px-3 rounded-lg text-sm font-medium transition-colors duration-200 #{if user_vote && user_vote.vote_type == :no, do: "bg-red-600 text-white", else: "bg-red-50 text-red-700 hover:bg-red-100 border border-red-200"}"}
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
                          class={"px-3 py-2 text-sm font-medium rounded-md transition-colors " <>
                            if temp_vote == :yes do
                              "bg-green-100 text-green-800 border-2 border-green-300"
                            else
                              "bg-gray-50 text-gray-700 border border-gray-300 hover:bg-gray-100"
                            end
                          }
                        >
                          👍 Yes
                        </button>

                        <button
                          type="button"
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="if_need_be"
                          class={"px-3 py-2 text-sm font-medium rounded-md transition-colors " <>
                            if temp_vote == :if_need_be do
                              "bg-yellow-100 text-yellow-800 border-2 border-yellow-300"
                            else
                              "bg-gray-50 text-gray-700 border border-gray-300 hover:bg-gray-100"
                            end
                          }
                        >
                          🤷 If need be
                        </button>

                        <button
                          type="button"
                          phx-click="cast_vote"
                          phx-value-option_id={option.id}
                          phx-value-vote_type="no"
                          class={"px-3 py-2 text-sm font-medium rounded-md transition-colors " <>
                            if temp_vote == :no do
                              "bg-red-100 text-red-800 border-2 border-red-300"
                            else
                              "bg-gray-50 text-gray-700 border border-gray-300 hover:bg-gray-100"
                            end
                          }
                        >
                          👎 No
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
              <%= if @event.users != [] do %>
                <div class="w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center text-lg font-semibold text-gray-600 border border-gray-200">
                  <%= String.first(hd(@event.users).name || "?") %>
                </div>
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
        </div>

        <!-- Right sidebar -->
        <div class="lg:col-span-1">
          <!-- Registration Card -->
          <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm mb-6">
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
                  <div class="w-10 h-10 bg-gray-100 rounded-full flex items-center justify-center text-lg font-semibold text-gray-600 border border-gray-200">
                    <%= String.first(@user.name || "?") %>
                  </div>
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
                          <div class="w-8 h-8 bg-blue-100 rounded-full flex items-center justify-center">
                            <svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
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
          </div>

          <!-- Share buttons -->
          <div class="bg-white border border-gray-200 rounded-xl p-5 shadow-sm mb-4">
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
          <div class="bg-white border border-gray-200 rounded-xl p-5 shadow-sm">
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
  defp social_card_url(socket, event) do
    url(socket, ~p"/events/#{event.id}/social_card.png")
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
end
