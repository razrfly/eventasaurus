defmodule EventasaurusWeb.PublicEventLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Themes
  alias EventasaurusWeb.EventRegistrationComponent
  alias EventasaurusWeb.ReservedSlugs

  def mount(%{"slug" => slug}, _session, socket) do
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

          # Get theme and customizations
          theme = try do
            case event.theme do
              theme when is_atom(theme) -> theme
              theme when is_binary(theme) -> String.to_existing_atom(theme)
              nil -> :minimal
            end
          rescue
            ArgumentError -> :minimal
          end

          theme_customizations = event.theme_customizations || %{}

          # Get CSS class for the theme
          theme_class = Themes.get_theme_css_class(theme)

          # Generate CSS variables for customizations
          css_variables = generate_css_variables(theme, theme_customizations)

          {:ok,
           socket
           |> assign(:event, event)
           |> assign(:venue, venue)
           |> assign(:organizers, organizers)
           |> assign(:show_registration_modal, false)
           |> assign(:page_title, event.title)
           |> assign(:theme, theme)
           |> assign(:theme_class, theme_class)
           |> assign(:css_variables, css_variables)
          }
      end
    end
  end

  # Generate CSS custom properties from theme customizations
  defp generate_css_variables(theme, customizations) do
    # Validate customizations first to prevent injection
    case Themes.validate_customizations(customizations || %{}) do
      {:ok, validated_customizations} ->
        # Merge default theme customizations with validated user customizations
        merged = Themes.merge_customizations(theme, validated_customizations)

        # Use the sanitized function from ThemeHelpers
        EventasaurusWeb.ThemeHelpers.theme_css_variables(merged)

      {:error, _} ->
        # Fall back to default theme only if validation fails
        EventasaurusWeb.ThemeHelpers.theme_css_variables(%{})
    end
  end

  def handle_event("show_registration_modal", _params, socket) do
    {:noreply, assign(socket, :show_registration_modal, true)}
  end

  def handle_info(:close_registration_modal, socket) do
    {:noreply, assign(socket, :show_registration_modal, false)}
  end

  def handle_info({:registration_success, type, _name, _email}, socket) do
    message = case type do
      :new_registration ->
        "Welcome! You're now registered for #{socket.assigns.event.title}. Check your email for account verification instructions."
      :existing_user_registered ->
        "Great! You're now registered for #{socket.assigns.event.title}."
    end

    {:noreply,
     socket
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
    <div class={["theme-container", @theme_class]} style={@css_variables}>
      <div class="public-event-container py-10 lg:py-16">
        <div class="public-event-layout">
          <div class="event-details-section">
            <!-- Date/time and main info -->
            <div class="flex items-start gap-4 mb-8">
              <div class="event-date-badge">
                <div class="month"><%= Calendar.strftime(@event.start_at, "%b") %></div>
                <div class="day"><%= Calendar.strftime(@event.start_at, "%d") %></div>
              </div>
              <div>
                <h1 class="event-title"><%= @event.title %></h1>
                <div class="event-datetime">
                  <%= Calendar.strftime(@event.start_at, "%A, %B %d · %I:%M %p") |> String.replace(" 0", " ") %>
                  <%= if @event.ends_at do %>
                    - <%= Calendar.strftime(@event.ends_at, "%I:%M %p") |> String.replace(" 0", " ") %>
                  <% end %>
                  <span class="text-gray-500 ml-1"><%= @event.timezone %></span>
                </div>

                <div class="event-location">
                  <span class="event-location-icon">
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
              <div class="event-cover-wrapper mb-8">
                <img src={@event.cover_image_url} alt={@event.title} class="event-cover-image" />
              </div>
            <% end %>

            <!-- Description -->
            <%= if @event.description && @event.description != "" do %>
              <div class="theme-card p-6 rounded-xl mb-8">
                <h2 class="text-xl font-semibold mb-4">About This Event</h2>
                <div class="prose max-w-none">
                  <%= Phoenix.HTML.raw(Earmark.as_html!(@event.description || "")) %>
                </div>
              </div>
            <% else %>
              <div class="theme-card p-6 rounded-xl mb-8">
                <h2 class="text-xl font-semibold mb-4">About This Event</h2>
                <p class="text-gray-500">No description provided for this event.</p>
              </div>
            <% end %>

            <!-- Host section -->
            <div class="host-section">
              <h3 class="text-lg font-semibold mb-4">Hosted by</h3>
              <div class="flex items-center space-x-3">
                <div class="host-avatar">
                  <%= String.first(hd(@event.users).name || "?") %>
                </div>
                <div>
                  <div class="host-name"><%= hd(@event.users).name %></div>
                  <a href="#" class="host-action">View other events</a>
                </div>
              </div>
            </div>
          </div>

          <!-- Right sidebar -->
          <div class="sidebar-section">
            <div class="registration-section">
              <h3 class="registration-title">Register for this event</h3>
              <button
                id="register-now-btn"
                phx-click="show_registration_modal"
                class="theme-button-primary registration-button block text-center w-full"
              >
                Register Now
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 ml-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M14 5l7 7m0 0l-7 7m7-7H3" />
                </svg>
              </button>
              <div class="mt-3 text-center text-sm text-gray-500">
                <div>Limited spots available</div>
              </div>
            </div>

            <!-- Share buttons -->
            <div class="theme-card rounded-xl p-5 mb-4">
              <h3 class="text-base font-semibold mb-3">Share this event</h3>
              <div class="flex space-x-3">
                <a href={"https://twitter.com/intent/tweet?text=Check out #{@event.title}&url=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" class="theme-button-secondary p-2 rounded-full">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M22.162 5.656a8.384 8.384 0 0 1-2.402.658A4.196 4.196 0 0 0 21.6 4c-.82.488-1.719.83-2.656 1.015a4.182 4.182 0 0 0-7.126 3.814 11.874 11.874 0 0 1-8.62-4.37 4.168 4.168 0 0 0-.566 2.103c0 1.45.738 2.731 1.86 3.481a4.168 4.168 0 0 1-1.894-.523v.052a4.185 4.185 0 0 0 3.355 4.101 4.21 4.21 0 0 1-1.89.072A4.185 4.185 0 0 0 7.97 16.65a8.394 8.394 0 0 1-6.191 1.732 11.83 11.83 0 0 0 6.41 1.88c7.693 0 11.9-6.373 11.9-11.9 0-.18-.005-.362-.013-.54a8.496 8.496 0 0 0 2.087-2.165z"/></svg>
                </a>
                <a href={"https://www.facebook.com/sharer/sharer.php?u=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" class="theme-button-secondary p-2 rounded-full">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M12 2.04c-5.5 0-10 4.49-10 10.02 0 5 3.66 9.15 8.44 9.9v-7H7.9v-2.9h2.54V9.85c0-2.51 1.49-3.89 3.78-3.89 1.09 0 2.23.19 2.23.19v2.47h-1.26c-1.24 0-1.63.77-1.63 1.56v1.88h2.78l-.45 2.9h-2.33v7a10 10 0 0 0 8.44-9.9c0-5.53-4.5-10.02-10-10.02z"/></svg>
                </a>
                <a href={"https://www.linkedin.com/sharing/share-offsite/?url=#{URI.encode_www_form(EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}")}"} target="_blank" class="theme-button-secondary p-2 rounded-full">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 24 24"><path fill="currentColor" d="M19 3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14m-.5 15.5v-5.3a3.26 3.26 0 0 0-3.26-3.26c-.85 0-1.84.52-2.32 1.3v-1.11h-2.79v8.37h2.79v-4.93c0-.77.62-1.4 1.39-1.4a1.4 1.4 0 0 1 1.4 1.4v4.93h2.79M6.88 8.56a1.68 1.68 0 0 0 1.68-1.68c0-.93-.75-1.69-1.68-1.69a1.69 1.69 0 0 0-1.69 1.69c0 .93.76 1.68 1.69 1.68m1.39 9.94v-8.37H5.5v8.37h2.77z"/></svg>
                </a>
                <button id="copy-link-btn" class="theme-button-secondary p-2 rounded-full" data-clipboard-text={EventasaurusWeb.Endpoint.url() <> "/#{@event.slug}"}>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                  </svg>
                </button>
              </div>
            </div>

            <!-- Add to calendar -->
            <div class="theme-card rounded-xl p-5">
              <h3 class="text-base font-semibold mb-3">Add to calendar</h3>
              <div class="flex flex-col space-y-2">
                <a href="#" class="text-sm text-gray-600 hover:text-black flex items-center gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                  Google Calendar
                </a>
                <a href="#" class="text-sm text-gray-600 hover:text-black flex items-center gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                  </svg>
                  Apple Calendar
                </a>
                <a href="#" class="text-sm text-gray-600 hover:text-black flex items-center gap-2">
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
    </script>
    """
  end
end
