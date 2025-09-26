defmodule EventasaurusWeb.PublicEventShowLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.EventPlans
  alias EventasaurusWeb.Components.PublicPlanWithFriendsModal
  import Ecto.Query

  @impl true
  def mount(_params, session, socket) do
    # Get language from session (set by LanguagePlug), then connect params, then default to English
    params = get_connect_params(socket) || %{}
    language = session["language"] || params["locale"] || "en"

    socket =
      socket
      |> assign(:language, language)
      |> assign(:event, nil)
      |> assign(:loading, true)
      |> assign(:selected_occurrence, nil)
      |> assign(:show_plan_with_friends_modal, false)
      |> assign(:emails_input, "")
      |> assign(:invitation_message, "")
      |> assign(:selected_users, [])
      |> assign(:selected_emails, [])
      |> assign(:current_email_input, "")
      |> assign(:bulk_email_input, "")
      |> assign(:modal_organizer, nil)
      |> assign(:nearby_events, [])

    {:ok, socket}
  end

  @impl true
  def handle_info({:user_selected, user}, socket) do
    selected_users = socket.assigns.selected_users ++ [user]
    {:noreply, assign(socket, :selected_users, Enum.uniq_by(selected_users, & &1.id))}
  end

  @impl true
  def handle_info({:email_added, email}, socket) do
    selected_emails = socket.assigns.selected_emails ++ [email]
    {:noreply, assign(socket, :selected_emails, Enum.uniq(selected_emails))}
  end

  @impl true
  def handle_info({:remove_user, user_id}, socket) do
    selected_users = Enum.reject(socket.assigns.selected_users, &(&1.id == user_id))
    {:noreply, assign(socket, :selected_users, selected_users)}
  end

  @impl true
  def handle_info({:remove_email, email}, socket) do
    selected_emails = Enum.reject(socket.assigns.selected_emails, &(&1 == email))
    {:noreply, assign(socket, :selected_emails, selected_emails)}
  end

  @impl true
  def handle_info({:message_updated, message}, socket) do
    {:noreply, assign(socket, :invitation_message, message)}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _url, socket) do
    socket =
      socket
      |> fetch_event(slug)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  defp fetch_event(socket, slug) do
    language = socket.assigns.language

    event =
      from(pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        where: pe.slug == ^slug,
        preload: [:venue, :categories, :performers, sources: :source]
      )
      |> Repo.one()

    case event do
      nil ->
        socket
        |> put_flash(:error, gettext("Event not found"))
        |> push_navigate(to: ~p"/activities")

      event ->
        # Get primary category ID once to avoid multiple queries
        primary_category_id = get_primary_category_id(event.id)

        # Check if user has existing plan
        existing_plan =
          case get_current_user_id(socket) do
            nil -> nil
            user_id -> EventPlans.get_user_plan_for_event(user_id, event.id)
          end

        # Enrich with display fields
        enriched_event =
          event
          |> Map.put(:primary_category_id, primary_category_id)
          |> Map.put(:display_title, get_localized_title(event, language))
          |> Map.put(:display_description, get_localized_description(event, language))
          |> Map.put(:cover_image_url, get_cover_image_url(event))
          |> Map.put(:occurrence_list, parse_occurrences(event))

        # Get nearby activities (with fallback)
        nearby_events = EventasaurusDiscovery.PublicEvents.get_nearby_activities_with_fallback(
          event,
          [
            initial_radius: 25,
            max_radius: 50,
            display_count: 4,
            language: language
          ]
        )

        socket
        |> assign(:event, enriched_event)
        |> assign(:selected_occurrence, select_default_occurrence(enriched_event))
        |> assign(:existing_plan, existing_plan)
        |> assign(:nearby_events, nearby_events)
    end
  end

  defp get_localized_title(event, language) do
    case event.title_translations do
      nil ->
        event.title

      translations when is_map(translations) ->
        translations[language] || translations["en"] || event.title

      _ ->
        event.title
    end
  end

  defp get_primary_source_ticket_url(event) do
    # Sort sources by priority and take the first one's source_url
    sorted_sources = get_sorted_sources(event.sources)

    case sorted_sources do
      [primary_source | _] -> primary_source.source_url
      [] -> nil
    end
  end

  defp get_sorted_sources(sources) do
    sources
    |> Enum.sort_by(fn source ->
      priority =
        case source.metadata do
          %{"priority" => p} when is_integer(p) ->
            p

          %{"priority" => p} when is_binary(p) ->
            case Integer.parse(p) do
              {num, _} -> num
              _ -> 10
            end

          _ ->
            10
        end

      # Newer timestamps first (negative for descending sort)
      ts =
        case source.last_seen_at do
          %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
          _ -> 9_223_372_036_854_775_807
        end

      {priority, ts}
    end)
  end

  defp get_localized_description(event, language) do
    # Sort sources by priority and take the first one's description
    sorted_sources = get_sorted_sources(event.sources)

    case sorted_sources do
      [source | _] ->
        case source.description_translations do
          nil ->
            nil

          translations when is_map(translations) ->
            translations[language] || translations["en"] || nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp get_cover_image_url(event) do
    # Sort sources by priority and try to get the first available image
    sorted_sources =
      event.sources
      |> Enum.sort_by(fn source ->
        priority =
          case source.metadata do
            %{"priority" => p} when is_integer(p) ->
              p

            %{"priority" => p} when is_binary(p) ->
              case Integer.parse(p) do
                {num, _} -> num
                _ -> 10
              end

            _ ->
              10
          end

        # Newer timestamps first (negative for descending sort)
        ts =
          case source.last_seen_at do
            %DateTime{} = dt -> -DateTime.to_unix(dt, :second)
            _ -> 9_223_372_036_854_775_807
          end

        {priority, ts}
      end)

    # Try to extract image from sources with URL sanitization
    Enum.find_value(sorted_sources, fn source ->
      url = source.image_url || extract_image_from_metadata(source.metadata)
      normalize_http_url(url)
    end)
  end

  defp extract_image_from_metadata(nil), do: nil

  defp extract_image_from_metadata(metadata) do
    cond do
      # Ticketmaster stores images in an array
      images = get_in(metadata, ["ticketmaster_data", "images"]) ->
        case images do
          [%{"url" => url} | _] when is_binary(url) -> url
          _ -> nil
        end

      # Bandsintown and Karnet store in image_url
      url = metadata["image_url"] ->
        url

      true ->
        nil
    end
  end

  @impl true
  def handle_event("change_language", %{"language" => language}, socket) do
    # Set cookie to persist language preference
    socket =
      socket
      |> assign(:language, language)
      |> fetch_event(socket.assigns.event.slug)
      |> clear_flash()  # Clear any existing flash
      |> Phoenix.LiveView.push_event("set_language_cookie", %{language: language})

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_occurrence", %{"index" => index}, socket) do
    occurrence_index = String.to_integer(index)
    occurrence_list = socket.assigns.event.occurrence_list || []

    selected = Enum.at(occurrence_list, occurrence_index)

    {:noreply, assign(socket, :selected_occurrence, selected)}
  end

  @impl true
  def handle_event("open_plan_modal", _params, socket) do
    # Debug logging
    require Logger
    Logger.debug("Plan with Friends modal - Socket assigns: user=#{inspect(socket.assigns[:user])}, auth_user=#{inspect(socket.assigns[:auth_user])}")

    cond do
      !socket.assigns[:auth_user] ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Please log in to create private events"))
         |> redirect(to: ~p"/auth/login")}

      socket.assigns[:existing_plan] ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Redirecting to your existing private event..."))
         |> redirect(to: ~p"/events/#{socket.assigns.existing_plan.private_event.slug}")}

      true ->
        # Get authenticated user for the modal
        user = get_authenticated_user(socket)

        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, true)
         |> assign(:modal_organizer, user)}
    end
  end

  @impl true
  def handle_event("close_plan_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_plan_with_friends_modal, false)
     |> assign(:invitation_message, "")
     |> assign(:selected_users, [])
     |> assign(:selected_emails, [])
     |> assign(:current_email_input, "")
     |> assign(:bulk_email_input, "")}
  end

  @impl true
  def handle_event("view_existing_plan", _params, socket) do
    case socket.assigns.existing_plan do
      %{private_event: private_event} ->
        {:noreply, redirect(socket, to: ~p"/events/#{private_event.slug}")}

      nil ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("No existing plan found"))
         |> push_navigate(to: ~p"/activities")}
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :invitation_message, message)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_email", _params, socket) do
    email = socket.assigns.current_email_input
    if is_valid_email?(email) do
      selected_emails = [email | socket.assigns.selected_emails] |> Enum.uniq()
      {:noreply,
        socket
        |> assign(:selected_emails, selected_emails)
        |> assign(:current_email_input, "")  # Clear the input field after adding
      }
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_email_on_enter", _params, socket) do
    # Same as add_email - handles Enter key press
    handle_event("add_email", %{}, socket)
  end

  @impl true
  def handle_event("remove_email", %{"index" => index_string}, socket) do
    index = String.to_integer(index_string)
    selected_emails = List.delete_at(socket.assigns.selected_emails, index)
    {:noreply, assign(socket, :selected_emails, selected_emails)}
  end

  @impl true
  def handle_event("email_input_change", %{"email_input" => email_input}, socket) do
    {:noreply, assign(socket, :current_email_input, email_input)}
  end


  @impl true
  def handle_event("clear_all_emails", _params, socket) do
    {:noreply, assign(socket, :selected_emails, [])}
  end

  @impl true
  def handle_event("submit_plan_with_friends", _params, socket) do
    case create_plan_from_public_event(socket) do
      {:ok, {:created, private_event}} ->
        # Send invitations to selected users and emails
        organizer = get_authenticated_user(socket)
        send_invitations(
          private_event,
          socket.assigns.selected_users,
          socket.assigns.selected_emails,
          socket.assigns.invitation_message,
          organizer
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Your private event has been created!"))
         |> redirect(to: ~p"/events/#{private_event.slug}")}

      {:ok, {:existing, private_event}} ->
        # For existing events, show different message and don't send invitations again
        {:noreply,
         socket
         |> put_flash(:info, gettext("Redirecting to your existing private event..."))
         |> redirect(to: ~p"/events/#{private_event.slug}")}

      {:error, :event_in_past} ->
        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, false)
         |> put_flash(
           :error,
           gettext("Cannot create plans for events that have already occurred")
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:show_plan_with_friends_modal, false)
         |> put_flash(
           :error,
           gettext("Sorry, there was an error creating your private event. Please try again.")
         )}
    end
  end

  defp create_plan_from_public_event(socket) do
    user = get_authenticated_user(socket)

    EventPlans.create_from_public_event(
      socket.assigns.event.id,
      user.id
    )
    |> case do
      {:ok, {:created, _event_plan, private_event}} -> {:ok, {:created, private_event}}
      {:ok, {:existing, _event_plan, private_event}} -> {:ok, {:existing, private_event}}
      error -> error
    end
  end

  defp get_current_user_id(socket) do
    cond do
      # Try processed user from database first
      socket.assigns[:user] && socket.assigns.user.id ->
        socket.assigns.user.id

      # Try current_user (might be the correct key)
      socket.assigns[:current_user] && socket.assigns.current_user.id ->
        socket.assigns.current_user.id

      # Try auth_user from Supabase/dev mode
      socket.assigns[:auth_user] ->
        case socket.assigns.auth_user do
          # Dev mode: User struct directly
          %{id: id} when is_integer(id) -> id
          # Supabase auth: map with string id
          %{"id" => id} when is_binary(id) -> String.to_integer(id)
          %{id: id} when is_binary(id) -> String.to_integer(id)
          _ -> nil
        end

      true -> nil
    end
  rescue
    _ -> nil
  end

  defp get_authenticated_user(socket) do
    # First try the processed user from the database
    case socket.assigns[:user] do
      %{id: id} = user when not is_nil(id) ->
        user

      _ ->
        # Fallback to raw auth_user from Supabase/dev mode
        case socket.assigns[:auth_user] do
          # Dev mode: User struct directly
          %{id: id} = user when is_integer(id) ->
            user

          # Supabase auth: map with string id
          %{"id" => id} = auth_user when is_binary(id) ->
            auth_user

          # Handle other possible formats
          %{id: id} = auth_user when is_binary(id) ->
            auth_user

          _ ->
            raise "No authenticated user found"
        end
    end
  end

  defp send_invitations(event, selected_users, selected_emails, message, organizer) do
    # Convert selected users to suggestion structs format expected by process_guest_invitations
    suggestion_structs = Enum.map(selected_users, fn user ->
      %{
        user_id: user.id,
        name: user.name,
        email: user.email,
        username: Map.get(user, :username),
        avatar_url: Map.get(user, :avatar_url)
      }
    end)

    # Process invitations using the same function as the manager area
    # Using :invitation mode since this is from the public event page (not managing existing event)
    EventasaurusApp.Events.process_guest_invitations(
      event,
      organizer,
      suggestion_structs: suggestion_structs,
      manual_emails: selected_emails,
      invitation_message: message || "",
      mode: :invitation  # Use invitation mode for public plan modal
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <%= if @loading do %>
        <div class="flex justify-center py-12">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
        </div>
      <% else %>
        <%= if @event do %>
          <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <!-- Language Switcher -->
            <div class="flex justify-end mb-4">
              <div class="flex bg-gray-100 rounded-lg p-1">
                <button
                  phx-click="change_language"
                  phx-value-language="en"
                  class={"px-3 py-1.5 rounded text-sm font-medium transition-colors #{if @language == "en", do: "bg-white shadow-sm text-blue-600", else: "text-gray-600 hover:text-gray-900"}"}
                  title="English"
                >
                  🇬🇧 EN
                </button>
                <button
                  phx-click="change_language"
                  phx-value-language="pl"
                  class={"px-3 py-1.5 rounded text-sm font-medium transition-colors #{if @language == "pl", do: "bg-white shadow-sm text-blue-600", else: "text-gray-600 hover:text-gray-900"}"}
                  title="Polski"
                >
                  🇵🇱 PL
                </button>
              </div>
            </div>

            <!-- Breadcrumb -->
            <div class="mb-6">
              <nav class="flex items-center space-x-2 text-sm">
                <.link navigate={~p"/activities"} class="text-blue-600 hover:text-blue-800">
                  <%= gettext("All Activities") %>
                </.link>
                <span class="text-gray-500">/</span>
                <%= if @event.categories && @event.categories != [] do %>
                  <% primary_category = get_primary_category(@event) || List.first(@event.categories) %>
                  <.link
                    navigate={~p"/activities?#{[category: primary_category.slug]}"}
                    class="text-blue-600 hover:text-blue-800"
                  >
                    <%= primary_category.name %>
                  </.link>
                  <span class="text-gray-500">/</span>
                <% end %>
                <span class="text-gray-700"><%= @event.display_title %></span>
              </nav>
            </div>

            <!-- Past Event Banner -->
            <%= if event_is_past?(@event) do %>
              <div class="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
                <div class="flex items-start">
                  <Heroicons.clock class="w-6 h-6 text-yellow-600 mr-3 flex-shrink-0 mt-0.5" />
                  <div>
                    <p class="text-yellow-800 font-semibold">
                      <%= gettext("This event has already occurred") %>
                    </p>
                    <p class="text-yellow-700 text-sm mt-1">
                      <%= gettext("This is an archived event page. The event took place on %{date}.",
                          date: format_event_datetime(@event.starts_at)) %>
                    </p>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Event Header -->
            <div class="bg-white rounded-lg shadow-lg overflow-hidden">
              <!-- Cover Image -->
              <%= if @event.cover_image_url do %>
                <div class="h-96 relative">
                  <img
                    src={@event.cover_image_url}
                    alt={@event.display_title}
                    class="w-full h-full object-cover"
                  />
                </div>
              <% end %>

              <div class="p-8">
                <!-- Categories -->
                <%= if @event.categories && @event.categories != [] do %>
                  <div class="mb-4">
                    <!-- Primary Category -->
                    <% primary_category = get_primary_category(@event) %>
                    <% secondary_categories = get_secondary_categories(@event) %>

                    <div class="flex flex-wrap gap-2 items-center">
                      <!-- Primary category - larger and emphasized -->
                      <%= if primary_category do %>
                        <.link
                          navigate={~p"/activities?#{[category: primary_category.slug]}"}
                          class="inline-flex items-center px-4 py-2 rounded-full text-sm font-semibold text-white hover:opacity-90 transition"
                          style={safe_background_style(primary_category.color)}
                        >
                          <%= if primary_category.icon do %>
                            <span class="mr-1"><%= primary_category.icon %></span>
                          <% end %>
                          <%= primary_category.name %>
                        </.link>
                      <% end %>

                      <!-- Secondary categories - smaller and less emphasized -->
                      <%= if secondary_categories != [] do %>
                        <span class="text-gray-400 mx-1">•</span>
                        <%= for category <- secondary_categories do %>
                          <.link
                            navigate={~p"/activities?#{[category: category.slug]}"}
                            class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 transition"
                          >
                            <%= category.name %>
                          </.link>
                        <% end %>
                      <% end %>
                    </div>

                    <!-- Category hint text -->
                    <p class="mt-2 text-xs text-gray-500">
                      <%= if secondary_categories != [] do %>
                        <%= gettext("Also filed under: %{categories}",
                            categories: Enum.map_join(secondary_categories, ", ", & &1.name)) %>
                      <% else %>
                        <%= gettext("Click category to see related events") %>
                      <% end %>
                    </p>
                  </div>
                <% end %>

                <!-- Title -->
                <h1 class="text-4xl font-bold text-gray-900 mb-6">
                  <%= @event.display_title %>
                </h1>

                <!-- Key Details Grid -->
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                  <!-- Date & Time -->
                  <div>
                    <div class="flex items-center text-gray-600 mb-1">
                      <Heroicons.calendar class="w-5 h-5 mr-2" />
                      <span class="font-medium"><%= gettext("Date & Time") %></span>
                    </div>
                    <p class="text-gray-900">
                      <%= if @selected_occurrence do %>
                        <%= format_occurrence_datetime(@selected_occurrence) %>
                      <% else %>
                        <%= format_event_datetime(@event.starts_at) %>
                        <%= if @event.ends_at do %>
                          <br />
                          <span class="text-sm text-gray-600">
                            <%= gettext("Until") %> <%= format_event_datetime(@event.ends_at) %>
                          </span>
                        <% end %>
                      <% end %>
                    </p>
                  </div>

                  <!-- Venue -->
                  <%= if @event.venue do %>
                    <div>
                      <div class="flex items-center text-gray-600 mb-1">
                        <Heroicons.map_pin class="w-5 h-5 mr-2" />
                        <span class="font-medium"><%= gettext("Venue") %></span>
                      </div>
                      <p class="text-gray-900">
                        <%= @event.venue.name %>
                        <%= if @event.venue.address do %>
                          <br />
                          <span class="text-sm text-gray-600">
                            <%= @event.venue.address %>
                          </span>
                        <% end %>
                      </p>
                    </div>
                  <% end %>

                  <%!-- Price display temporarily hidden - no APIs provide price data
                       Infrastructure retained for future API support
                       See GitHub issue #1281 for details
                  <!-- Price -->
                  <div>
                    <div class="flex items-center text-gray-600 mb-1">
                      <Heroicons.currency_dollar class="w-5 h-5 mr-2" />
                      <span class="font-medium"><%= gettext("Price") %></span>
                    </div>
                    <p class="text-gray-900">
                      <%= format_price_range(@event) %>
                    </p>
                  </div>
                  --%>

                  <!-- Ticket Link -->
                  <%= if ticket_url = get_primary_source_ticket_url(@event) do %>
                    <div>
                      <a
                        href={ticket_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
                      >
                        <Heroicons.ticket class="w-5 h-5 mr-2" />
                        <%= gettext("Get Tickets") %>
                      </a>
                    </div>
                  <% end %>

                  <!-- Plan with Friends Button (Only for future events) -->
                  <%= unless event_is_past?(@event) do %>
                    <div>
                      <%= if @existing_plan do %>
                        <!-- User already has a plan - show different button -->
                        <div class="space-y-2">
                          <button
                            phx-click="view_existing_plan"
                            class="inline-flex items-center px-6 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition"
                          >
                            <Heroicons.eye class="w-5 h-5 mr-2" />
                            <%= gettext("View Your Event") %>
                          </button>
                          <!-- Plan status indicator -->
                          <div class="text-sm text-gray-600 flex items-center">
                            <Heroicons.check_circle class="w-4 h-4 mr-1 text-green-500" />
                            <%= gettext("Created %{date}", date: format_plan_date(@existing_plan.inserted_at)) %>
                          </div>
                        </div>
                      <% else %>
                        <!-- No existing plan - show create button -->
                        <button
                          phx-click="open_plan_modal"
                          class="inline-flex items-center px-6 py-3 bg-green-600 text-white font-medium rounded-lg hover:bg-green-700 transition"
                        >
                          <Heroicons.user_group class="w-5 h-5 mr-2" />
                          <%= gettext("Plan with Friends") %>
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <!-- Multiple Occurrences Selection -->
                <%= if @event.occurrence_list && length(@event.occurrence_list) > 1 do %>
                  <div class="mb-8 p-6 bg-gray-50 rounded-lg">
                    <h3 class="text-lg font-semibold text-gray-900 mb-4 flex items-center">
                      <Heroicons.calendar_days class="w-5 h-5 mr-2" />
                      <%= case occurrence_display_type(@event.occurrence_list) do %>
                        <% :daily_show -> %>
                          <%= gettext("Daily Shows Available") %>
                        <% :same_day_multiple -> %>
                          <%= gettext("Select a Time") %>
                        <% :multi_day -> %>
                          <%= gettext("Multiple Dates Available") %>
                        <% _ -> %>
                          <%= gettext("Select Date & Time") %>
                      <% end %>
                    </h3>

                    <%= case occurrence_display_type(@event.occurrence_list) do %>
                      <% :daily_show -> %>
                        <!-- Calendar-like view for events with many dates -->
                        <div class="mb-4">
                          <p class="text-sm text-gray-600 mb-4">
                            <%= gettext("%{count} shows from %{start} to %{end}",
                                count: length(@event.occurrence_list),
                                start: format_date_only(List.first(@event.occurrence_list).datetime),
                                end: format_date_only(List.last(@event.occurrence_list).datetime)) %>
                          </p>
                          <div class="grid grid-cols-7 gap-2 max-h-96 overflow-y-auto">
                            <%= for {occurrence, index} <- Enum.with_index(@event.occurrence_list) do %>
                              <button
                                phx-click="select_occurrence"
                                phx-value-index={index}
                                class={"px-3 py-2 text-sm rounded-lg transition #{if @selected_occurrence == occurrence, do: "bg-blue-600 text-white", else: "bg-white border border-gray-200 hover:bg-gray-50"}"}
                              >
                                <%= format_short_date(occurrence.datetime) %>
                              </button>
                            <% end %>
                          </div>
                        </div>

                      <% :same_day_multiple -> %>
                        <!-- Time selection for same day events -->
                        <div class="space-y-2">
                          <%= for {occurrence, index} <- Enum.with_index(@event.occurrence_list) do %>
                            <button
                              phx-click="select_occurrence"
                              phx-value-index={index}
                              class={"w-full text-left px-4 py-3 rounded-lg border transition #{if @selected_occurrence == occurrence, do: "border-blue-600 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
                            >
                              <span class="font-medium"><%= format_time_only(occurrence.datetime) %></span>
                              <%= if occurrence.label do %>
                                <span class="ml-2 text-sm text-gray-600"><%= occurrence.label %></span>
                              <% end %>
                            </button>
                          <% end %>
                        </div>

                      <% _ -> %>
                        <!-- List view for small number of dates -->
                        <div class="space-y-2">
                          <%= for {occurrence, index} <- Enum.with_index(@event.occurrence_list) do %>
                            <button
                              phx-click="select_occurrence"
                              phx-value-index={index}
                              class={"w-full text-left px-4 py-3 rounded-lg border transition #{if @selected_occurrence == occurrence, do: "border-blue-600 bg-blue-50", else: "border-gray-200 hover:bg-gray-50"}"}
                            >
                              <span class="font-medium"><%= format_occurrence_datetime(occurrence) %></span>
                              <%= if occurrence.label do %>
                                <span class="ml-2 text-sm text-gray-600"><%= occurrence.label %></span>
                              <% end %>
                            </button>
                          <% end %>
                        </div>
                    <% end %>

                    <div class="mt-4 p-3 bg-blue-50 rounded-lg">
                      <p class="text-sm text-blue-900">
                        <span class="font-medium"><%= gettext("Selected:") %></span>
                        <%= format_occurrence_datetime(@selected_occurrence || List.first(@event.occurrence_list)) %>
                      </p>
                    </div>
                  </div>
                <% end %>

                <!-- Description -->
                <%= if @event.display_description do %>
                  <div class="mb-8">
                    <h2 class="text-2xl font-semibold text-gray-900 mb-4">
                      <%= gettext("About This Event") %>
                    </h2>
                    <div class="prose max-w-none text-gray-700">
                      <%= format_description(@event.display_description) %>
                    </div>
                  </div>
                <% end %>

                <!-- Performers -->
                <%= if @event.performers && @event.performers != [] do %>
                  <div class="mb-8">
                    <h2 class="text-2xl font-semibold text-gray-900 mb-4">
                      <%= gettext("Performers") %>
                    </h2>
                    <div class="flex flex-wrap gap-3">
                      <%= for performer <- @event.performers do %>
                        <span class="px-4 py-2 bg-gray-100 rounded-lg text-gray-800 font-medium">
                          <%= performer.name %>
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <!-- Sources -->
                <div class="mt-12 pt-8 border-t border-gray-200">
                  <h3 class="text-sm font-medium text-gray-500 mb-3">
                    <%= gettext("Event Sources") %>
                  </h3>
                  <div class="flex flex-wrap gap-4">
                    <%= for source <- @event.sources do %>
                      <% source_url = get_source_url(source) %>
                      <% source_name = get_source_name(source) %>
                      <div class="text-sm">
                        <%= if source_url do %>
                          <a href={source_url} target="_blank" rel="noopener noreferrer" class="font-medium text-blue-600 hover:text-blue-800">
                            <%= source_name %>
                            <Heroicons.arrow_top_right_on_square class="w-3 h-3 inline ml-1" />
                          </a>
                        <% else %>
                          <span class="font-medium text-gray-700">
                            <%= source_name %>
                          </span>
                        <% end %>
                        <span class="text-gray-500 ml-2">
                          <%= gettext("Last updated") %> <%= format_relative_time(source.last_seen_at) %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <!-- Related Events -->
            <.live_component
              module={EventasaurusWeb.Components.NearbyEventsComponent}
              id="nearby-events"
              events={@nearby_events}
              language={@language}
            />
          </div>
        <% end %>
      <% end %>

      <!-- Plan with Friends Modal -->
      <%= if @show_plan_with_friends_modal do %>
        <PublicPlanWithFriendsModal.modal
          id="plan-with-friends-modal"
          show={@show_plan_with_friends_modal}
          public_event={@event}
          selected_users={@selected_users}
          selected_emails={@selected_emails}
          current_email_input={@current_email_input}
          bulk_email_input={@bulk_email_input}
          invitation_message={@invitation_message}
          organizer={@modal_organizer}
          on_close="close_plan_modal"
          on_submit="submit_plan_with_friends"
        />
      <% end %>
    </div>

    <div id="language-cookie-hook" phx-hook="LanguageCookie"></div>
    """
  end

  # Helper Functions
  defp format_event_datetime(nil), do: gettext("TBD")

  defp format_event_datetime(datetime) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  # Commented out - price display temporarily hidden as no APIs provide price data
  # See GitHub issue #1281 for details
  # defp format_price_range(event) do
  #   symbol = currency_symbol(event.currency)
  #
  #   cond do
  #     event.min_price && event.max_price && event.min_price == event.max_price ->
  #       "#{symbol}#{event.min_price}"
  #
  #     event.min_price && event.max_price ->
  #       "#{symbol}#{event.min_price} - #{symbol}#{event.max_price}"
  #
  #     event.min_price ->
  #       gettext("From %{price}", price: "#{symbol}#{event.min_price}")
  #
  #     event.max_price ->
  #       gettext("Up to %{price}", price: "#{symbol}#{event.max_price}")
  #
  #     true ->
  #       gettext("See details")
  #   end
  # end
  #
  # defp currency_symbol(nil), do: "$"
  # defp currency_symbol("USD"), do: "$"
  # defp currency_symbol("EUR"), do: "€"
  # defp currency_symbol("PLN"), do: "zł"
  # defp currency_symbol(_), do: "$"

  defp format_description(nil), do: Phoenix.HTML.raw("")

  defp format_description(description) do
    # Escapes HTML and converts newlines to <br>, returning Safe HTML
    Phoenix.HTML.Format.text_to_html(description, escape: true)
  end

  defp get_source_url(source) do
    # Guard against nil metadata and sanitize URLs
    md = source.metadata || %{}

    url =
      cond do
        # Ticketmaster stores URL in ticketmaster_data.url
        url = get_in(md, ["ticketmaster_data", "url"]) -> url
        # Bandsintown might have it in event_url or url
        url = md["event_url"] -> url
        url = md["url"] -> url
        # Karnet might have it in a different location
        url = md["link"] -> url
        # Fallback to source_url if it exists
        source.source_url -> source.source_url
        true -> nil
      end

    normalize_http_url(url)
  end

  defp normalize_http_url(nil), do: nil

  defp normalize_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} = uri when scheme in ["http", "https"] -> URI.to_string(uri)
      _ -> nil
    end
  end

  defp get_source_name(source) do
    # Use the associated source name if available
    if source.source do
      source.source.name
    else
      "Unknown"
    end
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 3600 -> gettext("%{count} minutes ago", count: div(diff, 60))
      diff < 86400 -> gettext("%{count} hours ago", count: div(diff, 3600))
      diff < 604_800 -> gettext("%{count} days ago", count: div(diff, 86400))
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp format_plan_date(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> format_relative_time(dt)
      {:error, _} -> gettext("recently")
    end
  end

  # Occurrence helper functions
  defp parse_occurrences(%{occurrences: nil}), do: nil

  defp parse_occurrences(%{occurrences: %{"dates" => dates}}) when is_list(dates) do
    dates
    |> Enum.map(fn date_info ->
      with {:ok, date} <- Date.from_iso8601(date_info["date"]),
           {:ok, time} <- parse_time(date_info["time"]) do
        datetime = DateTime.new!(date, time, "Etc/UTC")

        %{
          datetime: datetime,
          date: date,
          time: time,
          external_id: date_info["external_id"],
          label: date_info["label"]
        }
      else
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.datetime, DateTime)
  end

  defp parse_occurrences(_), do: nil

  defp parse_time(nil), do: {:ok, ~T[20:00:00]}

  defp parse_time(time_str) when is_binary(time_str) do
    case String.split(time_str, ":") do
      [h, m] -> Time.new(String.to_integer(h), String.to_integer(m), 0)
      [h, m, s] -> Time.new(String.to_integer(h), String.to_integer(m), String.to_integer(s))
      _ -> {:ok, ~T[20:00:00]}
    end
  end

  defp parse_time(_), do: {:ok, ~T[20:00:00]}

  defp select_default_occurrence(%{occurrence_list: nil}), do: nil
  defp select_default_occurrence(%{occurrence_list: []}), do: nil

  defp select_default_occurrence(%{occurrence_list: occurrences}) do
    now = DateTime.utc_now()
    # Find the next upcoming occurrence, or the first if all are in the past
    Enum.find(occurrences, List.first(occurrences), fn occ ->
      DateTime.compare(occ.datetime, now) == :gt
    end)
  end

  defp occurrence_display_type(nil), do: :none
  defp occurrence_display_type([]), do: :none

  defp occurrence_display_type(occurrences) do
    cond do
      # More than 20 dates - daily show
      length(occurrences) > 20 ->
        :daily_show

      # All on same day - time selection
      all_same_day?(occurrences) ->
        :same_day_multiple

      # Default - multi day
      true ->
        :multi_day
    end
  end

  defp all_same_day?(occurrences) do
    dates = Enum.map(occurrences, & &1.date) |> Enum.uniq()
    length(dates) == 1
  end

  defp format_occurrence_datetime(nil), do: gettext("Select a date")

  defp format_occurrence_datetime(%{datetime: datetime}) do
    Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p")
  end

  defp format_date_only(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp format_time_only(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp format_short_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d")
  end

  defp event_is_past?(%{starts_at: nil}), do: false

  defp event_is_past?(%{ends_at: ends_at}) when not is_nil(ends_at) do
    DateTime.compare(ends_at, DateTime.utc_now()) == :lt
  end

  defp event_is_past?(%{starts_at: starts_at}) when not is_nil(starts_at) do
    # For events without end dates, consider them active for 24 hours after start
    # This handles single-day events and events where end time wasn't specified
    DateTime.compare(
      DateTime.add(starts_at, 24, :hour),
      DateTime.utc_now()
    ) == :lt
  end

  defp event_is_past?(_), do: false

  defp is_valid_email?(email) do
    email =~ ~r/^[^\s]+@[^\s]+\.[^\s]+$/
  end

  # Category helper functions
  defp get_primary_category(event) do
    case event.primary_category_id do
      nil -> nil
      cat_id -> Enum.find(event.categories, &(&1.id == cat_id))
    end
  end

  defp get_secondary_categories(event) do
    case event.primary_category_id do
      nil ->
        # If no primary found, treat all but first as secondary
        case event.categories do
          [_first | rest] -> rest
          _ -> []
        end
      primary_id ->
        Enum.reject(event.categories, &(&1.id == primary_id))
    end
  end

  defp get_primary_category_id(event_id) do
    Repo.one(
      from pec in "public_event_categories",
      where: pec.event_id == ^event_id and pec.is_primary == true,
      select: pec.category_id,
      limit: 1
    )
  end

  defp safe_background_style(color) do
    color =
      if valid_hex_color?(color) do
        color
      else
        "#6B7280"
      end

    "background-color: #{color}"
  end

  defp valid_hex_color?(color) when is_binary(color) do
    case color do
      <<?#, _::binary>> = hex when byte_size(hex) in [4, 7] ->
        String.match?(hex, ~r/^#(?:[0-9a-fA-F]{3}){1,2}$/)
      _ ->
        false
    end
  end

  defp valid_hex_color?(_), do: false
end
