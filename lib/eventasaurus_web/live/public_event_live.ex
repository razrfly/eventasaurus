defmodule EventasaurusWeb.PublicEventLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Accounts
  alias EventasaurusWeb.EventRegistrationComponent
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

          # Apply event theme to layout
          theme = event.theme || :minimal

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
          }
      end
    end
  end

  def handle_event("show_registration_modal", _params, socket) do
    {:noreply, assign(socket, :show_registration_modal, true)}
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
    # Only allow for event organizers
    case socket.assigns.registration_status do
      :organizer ->
        {:noreply,
         socket
         |> redirect(to: ~p"/events/#{socket.assigns.event.slug}/edit")
        }
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Only event organizers can manage events.")
        }
    end
  end

  def handle_info(:close_registration_modal, socket) do
    {:noreply, assign(socket, :show_registration_modal, false)}
  end

  def handle_info({:registration_success, type, _name, email}, socket) do
    message = case type do
      :new_registration ->
        "Welcome! You're now registered for #{socket.assigns.event.title}. Check your email for account verification instructions."
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
        case EventasaurusApp.Accounts.get_user_by_email(email) do
          nil ->
            socket
          user ->
            socket
            |> assign(:registration_status, :registered)
            |> assign(:user, user)
            |> assign(:just_registered, true)  # This is always a new registration
        end
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

  def render(assigns) do
    ~H"""
    <!-- Public Event Show Page with dynamic theming -->
    <div class="container mx-auto px-6 py-4">
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
              <div class="text-lg text-gray-700 mb-3 font-medium">
                <%= Calendar.strftime(@event.start_at, "%A, %B %d · %I:%M %p") |> String.replace(" 0", " ") %>
                <%= if @event.ends_at do %>
                  - <%= Calendar.strftime(@event.ends_at, "%I:%M %p") |> String.replace(" 0", " ") %>
                <% end %>
                <span class="text-gray-500 ml-1"><%= @event.timezone %></span>
              </div>

              <div class="flex items-center gap-2 text-gray-600">
                <span class="text-gray-500">
                  <%= if @event.venue_id == nil do %>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  <% else %>
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                  <% end %>
                </span>
                <span>
                  <%= if @event.venue_id == nil do %>
                    <span class="font-medium">Virtual Event</span>
                  <% else %>
                    <%= if @venue do %>
                      <span class="font-medium"><%= @venue.name %></span>, <%= @venue.city %>
                      <%= if @venue.state && @venue.state != "", do: ", #{@venue.state}" %>
                    <% else %>
                      Location details not available
                    <% end %>
                  <% end %>
                </span>
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

          <!-- Host section -->
          <div class="border-t border-gray-200 pt-8 mt-8">
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
                  Register Now
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

        // Handle theme-specific fonts
        // Remove existing theme fonts (those with Google Fonts for specific themes)
        const existingThemeFonts = document.querySelectorAll('link[href*="fonts.googleapis.com"][data-theme-font="true"]');
        existingThemeFonts.forEach(link => link.remove());

        // Add new theme fonts if needed
        const themeFont = getThemeFontUrl(newTheme);
        if (themeFont) {
          // Add preconnect links
          const preconnect = document.createElement('link');
          preconnect.rel = 'preconnect';
          preconnect.href = 'https://fonts.googleapis.com';
          document.head.appendChild(preconnect);

          const preconnectCrossorigin = document.createElement('link');
          preconnectCrossorigin.rel = 'preconnect';
          preconnectCrossorigin.href = 'https://fonts.gstatic.com';
          preconnectCrossorigin.crossOrigin = 'anonymous';
          document.head.appendChild(preconnectCrossorigin);

          // Add font link
          const fontLink = document.createElement('link');
          fontLink.rel = 'stylesheet';
          fontLink.href = themeFont;
          fontLink.setAttribute('data-theme-font', 'true');
          document.head.appendChild(fontLink);
        }

        // Update body class for theme-specific styling
        document.body.className = document.body.className.replace(/\btheme-\w+\b/g, '');
        if (newTheme !== 'minimal') {
          document.body.classList.add(`theme-${newTheme}`);
        }

        console.log(`Theme switched to: ${newTheme}`);
      });

      // Helper function to get font URL for each theme
      function getThemeFontUrl(theme) {
        const fontUrls = {
          'cosmic': 'https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&display=swap',
          'velocity': 'https://fonts.googleapis.com/css2?family=Rajdhani:wght@400;600;700&display=swap',
          'retro': 'https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&display=swap',
          'celebration': 'https://fonts.googleapis.com/css2?family=Fredoka:wght@400;600&display=swap',
          'nature': 'https://fonts.googleapis.com/css2?family=Merriweather:wght@400;700&display=swap',
          'professional': 'https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700&display=swap'
        };

        return fontUrls[theme] || null;
      }
    </script>
    """
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
