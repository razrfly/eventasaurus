defmodule EventasaurusWeb.ProfileLive do
  @moduledoc """
  LiveView for user profile pages.

  Shows a user's public profile with:
  - Avatar and basic info
  - Event statistics
  - Recent events
  - Mutual events (for logged-in users viewing others)
  - Connection panel showing relationship context and "Stay in Touch" button
  """

  use EventasaurusWeb, :live_view

  import EventasaurusWeb.Helpers.AvatarHelper

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Relationships

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_user_by_username_or_id(username) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "User not found")
         |> redirect(to: ~p"/")}

      profile_user ->
        canonical_username = User.username_slug(profile_user)

        # Redirect to canonical URL if accessed via ID or different username format
        if username != canonical_username do
          {:ok, redirect(socket, to: ~p"/users/#{canonical_username}")}
        else
          current_user = socket.assigns[:user]
          is_own_profile = current_user && current_user.id == profile_user.id

          if profile_user.profile_public == true || is_own_profile do
            {:ok, load_profile_data(socket, profile_user, current_user, is_own_profile)}
          else
            # Profile is private and not viewing own profile
            {:ok,
             socket
             |> put_flash(:error, "User not found")
             |> redirect(to: ~p"/")}
          end
        end
    end
  end

  defp load_profile_data(socket, profile_user, current_user, is_own_profile) do
    canonical_username = User.username_slug(profile_user)

    # Get profile data
    stats = Accounts.get_user_event_stats(profile_user)

    # Filter to public events only for public profiles viewing others
    recent_events =
      Accounts.get_user_recent_events(profile_user,
        limit: 10,
        public_only: !is_own_profile
      )

    # Get mutual events if user is logged in and different from profile user
    mutual_events =
      if current_user && current_user.id != profile_user.id do
        Accounts.get_mutual_events(current_user, profile_user, limit: 6)
      else
        []
      end

    # Get connection context for the connection panel
    connection_context =
      if current_user && current_user.id != profile_user.id do
        build_connection_context(current_user, profile_user, mutual_events)
      else
        nil
      end

    page_title =
      if is_own_profile do
        "Your Profile (@#{canonical_username})"
      else
        "#{User.display_name(profile_user)} (@#{canonical_username})"
      end

    socket
    |> assign(:profile_user, profile_user)
    |> assign(:page_title, page_title)
    |> assign(:stats, stats)
    |> assign(:recent_events, recent_events)
    |> assign(:mutual_events, mutual_events)
    |> assign(:connection_context, connection_context)
    |> assign(:is_own_profile, is_own_profile)
  end

  # Build connection context for the relationship panel
  defp build_connection_context(current_user, profile_user, mutual_events) do
    # Check current relationship status
    relationship = Relationships.get_relationship_between(current_user, profile_user)
    is_connected = relationship && relationship.status == :active

    # Check if there's a pending request
    has_pending = Relationships.has_pending_request?(current_user, profile_user)

    # Check if users share event history
    share_events = Relationships.share_event_history?(current_user, profile_user)

    # Check if within network (friends of friends)
    within_network = Relationships.within_network?(current_user, profile_user, degrees: 2)

    # Determine connection degree
    connection_degree =
      cond do
        is_connected -> :connected
        has_pending -> :pending
        share_events -> :shared_events
        within_network -> :extended_network
        true -> :no_connection
      end

    # Only allow connection button if there's a valid basis
    # No random connections - must have mutual events or be in extended network
    can_show_button = connection_degree in [:connected, :pending, :shared_events, :extended_network]

    # Get target's permission level to determine if connection is possible
    can_connect_result =
      cond do
        is_connected ->
          :already_connected

        !can_show_button ->
          :no_connection

        true ->
          case Relationships.can_connect?(current_user, profile_user) do
            {:ok, result} -> result
            {:error, reason} -> reason
          end
      end

    %{
      is_connected: is_connected,
      relationship: relationship,
      has_pending_request: has_pending,
      mutual_event_count: length(mutual_events),
      share_events: share_events,
      within_network: within_network,
      connection_degree: connection_degree,
      can_connect: can_connect_result,
      can_show_button: can_show_button
    }
  end

  # Handle messages from RelationshipButtonComponent
  @impl true
  def handle_info({:connection_request_sent, _other_user}, socket) do
    {:noreply, put_flash(socket, :info, "Introduction request sent!")}
  end

  @impl true
  def handle_info({:connection_created, _other_user}, socket) do
    {:noreply, put_flash(socket, :info, "You're now connected!")}
  end

  @impl true
  def handle_info({:show_auth_modal, _action}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Please log in to connect with this user")
     |> redirect(to: ~p"/auth/login")}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper functions for the template
  defp display_name(user), do: User.display_name(user)

  defp format_join_date(%DateTime{} = datetime) do
    date = DateTime.to_date(datetime)
    month_name = Calendar.strftime(date, "%B")
    "Joined #{month_name} #{date.year}"
  end

  defp format_join_date(%NaiveDateTime{} = naive_datetime) do
    date = NaiveDateTime.to_date(naive_datetime)
    month_name = Calendar.strftime(date, "%B")
    "Joined #{month_name} #{date.year}"
  end

  defp format_join_date(nil), do: ""

  defp format_event_date(datetime, timezone \\ nil)

  defp format_event_date(%DateTime{} = datetime, timezone) do
    case timezone do
      tz when is_binary(tz) ->
        try do
          datetime
          |> DateTime.shift_zone!(tz)
          |> Calendar.strftime("%a, %b %d, %I:%M %p")
        rescue
          _ -> Calendar.strftime(datetime, "%a, %b %d, %I:%M %p UTC")
        end

      _ ->
        Calendar.strftime(datetime, "%a, %b %d, %I:%M %p UTC")
    end
  end

  defp format_event_date(nil, _timezone), do: "Date TBD"

  defp event_cover_image_url(event) do
    cond do
      event.cover_image_url && event.cover_image_url != "" ->
        event.cover_image_url

      event.external_image_data && Map.get(event.external_image_data, "url") ->
        Map.get(event.external_image_data, "url")

      true ->
        seed = :erlang.phash2(event.title || "event")
        "https://api.dicebear.com/9.x/shapes/svg?seed=#{seed}&backgroundColor=gradient"
    end
  end

  defp event_status_color(status) do
    case status do
      :confirmed -> "bg-green-100 text-green-800"
      :draft -> "bg-gray-100 text-gray-800"
      :polling -> "bg-blue-100 text-blue-800"
      :threshold -> "bg-yellow-100 text-yellow-800"
      :canceled -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp event_status_text(status) do
    case status do
      :confirmed -> "Confirmed"
      :draft -> "Draft"
      :polling -> "Polling"
      :threshold -> "Threshold"
      :canceled -> "Canceled"
      _ -> to_string(status)
    end
  end

  defp format_event_location(event) do
    cond do
      event.venue && event.venue.name ->
        event.venue.name

      Map.get(event, :virtual_venue_url) && event.virtual_venue_url != "" ->
        "Virtual Event"

      Map.get(event, :is_virtual) == true ->
        "Virtual Event"

      true ->
        "Location TBD"
    end
  end

  defp social_links(user) do
    [
      {:instagram, user.instagram_handle},
      {:x, user.x_handle},
      {:youtube, user.youtube_handle},
      {:tiktok, user.tiktok_handle},
      {:linkedin, user.linkedin_handle}
    ]
    |> Enum.filter(fn {_platform, handle} ->
      handle && String.trim(handle) != ""
    end)
  end

  defp social_url(handle, platform) when is_binary(handle) and handle != "" do
    clean_handle = String.replace(handle, ~r/^@/, "")

    case platform do
      :instagram -> "https://instagram.com/#{clean_handle}"
      :x -> "https://x.com/#{clean_handle}"
      :youtube ->
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://youtube.com/@#{clean_handle}"
        end
      :tiktok -> "https://tiktok.com/@#{clean_handle}"
      :linkedin ->
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://linkedin.com/in/#{clean_handle}"
        end
      _ -> "#"
    end
  end

  defp social_url(_, _), do: nil

  defp platform_name(platform) do
    case platform do
      :instagram -> "Instagram"
      :x -> "X"
      :youtube -> "YouTube"
      :tiktok -> "TikTok"
      :linkedin -> "LinkedIn"
      _ -> to_string(platform)
    end
  end

  defp format_website_url(url) when is_binary(url) and url != "" do
    if String.starts_with?(url, ["http://", "https://"]) do
      url
    else
      "https://#{url}"
    end
  end

  defp format_website_url(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Profile Header -->
        <div class="bg-white shadow-sm rounded-lg overflow-hidden">
          <div class="px-6 py-8">
            <div class="flex flex-col sm:flex-row items-start sm:items-center space-y-6 sm:space-y-0 sm:space-x-8">
              <!-- Avatar -->
              <div class="flex-shrink-0">
                <div class="relative">
                  <%= avatar_img_size(@profile_user, :xl, class: "rounded-full object-cover border-4 border-white shadow-lg") %>
                  <!-- Status indicator -->
                  <div class="absolute bottom-2 right-2 h-6 w-6 rounded-full bg-green-400 border-2 border-white"></div>
                </div>
              </div>

              <!-- User Info -->
              <div class="flex-1 min-w-0">
                <div class="flex flex-col lg:flex-row lg:items-start lg:justify-between">
                  <div class="flex-1">
                    <h1 class="text-3xl font-bold text-gray-900 mb-1">
                      <%= display_name(@profile_user) %>
                    </h1>
                    <p class="text-lg text-gray-600 mb-3">@<%= User.username_slug(@profile_user) %></p>

                    <!-- Join Date -->
                    <div class="flex items-center text-sm text-gray-500 mb-4">
                      <Heroicons.calendar class="w-4 h-4 mr-2" />
                      <%= format_join_date(@profile_user.inserted_at) %>
                    </div>

                    <!-- Stats Row -->
                    <div class="flex flex-wrap gap-6 mb-4">
                      <div class="flex flex-col">
                        <span class="text-2xl font-bold text-gray-900"><%= @stats.hosted %></span>
                        <span class="text-sm text-gray-600">Hosted</span>
                      </div>
                      <div class="flex flex-col">
                        <span class="text-2xl font-bold text-gray-900"><%= @stats.attended %></span>
                        <span class="text-sm text-gray-600">Attended</span>
                      </div>
                      <div class="flex flex-col">
                        <span class="text-2xl font-bold text-gray-900"><%= @stats.together %></span>
                        <span class="text-sm text-gray-600">Together</span>
                      </div>
                    </div>

                    <!-- Bio -->
                    <%= if @profile_user.bio && @profile_user.bio != "" do %>
                      <p class="text-gray-700 leading-relaxed mb-4">
                        <%= @profile_user.bio %>
                      </p>
                    <% end %>
                  </div>

                  <!-- Profile Actions -->
                  <div class="mt-6 lg:mt-0 lg:ml-6 flex flex-col gap-3">
                    <%= if @is_own_profile do %>
                      <.link
                        href={~p"/settings"}
                        class="inline-flex items-center px-6 py-2 border border-gray-300 rounded-full shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
                      >
                        <Heroicons.pencil_square class="w-4 h-4 mr-2" />
                        Edit Profile
                      </.link>
                    <% else %>
                      <!-- Share Button -->
                      <button
                        onclick={"navigator.share ? navigator.share({title: '#{display_name(@profile_user)}', url: window.location.href}) : navigator.clipboard.writeText(window.location.href)"}
                        class="inline-flex items-center px-6 py-2 border border-gray-300 rounded-full shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
                      >
                        <Heroicons.share class="w-4 h-4 mr-2" />
                        Share Profile
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Content Grid -->
        <div class="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-8">
          <!-- Main Content -->
          <div class="lg:col-span-2 space-y-8">
            <!-- Mutual Events Section -->
            <%= if match?([_|_], @mutual_events) do %>
              <div class="bg-white shadow-sm rounded-lg overflow-hidden">
                <div class="px-6 py-4 border-b border-gray-200">
                  <h2 class="text-lg font-semibold text-gray-900">Mutual Events</h2>
                </div>
                <div class="p-6">
                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                    <%= for event <- @mutual_events do %>
                      <.link href={~p"/#{event.slug}"} class="group block">
                        <div class="aspect-w-16 aspect-h-9 rounded-lg overflow-hidden bg-gray-100 mb-3">
                          <img
                            src={event_cover_image_url(event)}
                            alt={event.title}
                            class="w-full h-32 object-cover group-hover:opacity-90 transition-opacity"
                          />
                        </div>
                        <h3 class="font-semibold text-gray-900 group-hover:text-blue-600 transition-colors line-clamp-2">
                          <%= event.title %>
                        </h3>
                        <p class="text-sm text-gray-600 mt-1">
                          <%= format_event_date(event.start_at, event.timezone) %>
                        </p>
                      </.link>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <!-- Recent Events Section -->
            <div class="bg-white shadow-sm rounded-lg overflow-hidden">
              <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
                <h2 class="text-lg font-semibold text-gray-900">
                  <%= if @is_own_profile, do: "Your Events", else: "Recent Events" %>
                </h2>
                <%= if Enum.count(@recent_events || []) > 6 do %>
                  <button class="text-sm text-blue-600 hover:text-blue-800 font-medium">View All</button>
                <% end %>
              </div>

              <%= if match?([_|_], @recent_events) do %>
                <div class="divide-y divide-gray-200">
                  <%= for event <- Enum.take(@recent_events || [], 6) do %>
                    <div class="p-6 hover:bg-gray-50 transition-colors">
                      <.link href={~p"/#{event.slug}"} class="flex items-start space-x-4 group">
                        <div class="flex-shrink-0">
                          <img
                            src={event_cover_image_url(event)}
                            alt={event.title}
                            class="w-16 h-16 rounded-lg object-cover"
                          />
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="flex items-start justify-between">
                            <div class="flex-1">
                              <h3 class="font-semibold text-gray-900 group-hover:text-blue-600 transition-colors">
                                <%= event.title %>
                              </h3>
                              <%= if event.tagline && event.tagline != "" do %>
                                <p class="text-sm text-gray-600 mt-1 line-clamp-2">
                                  <%= event.tagline %>
                                </p>
                              <% end %>
                              <div class="flex items-center mt-2 space-x-4 text-sm text-gray-500">
                                <span>
                                  <Heroicons.calendar class="w-4 h-4 inline mr-1" />
                                  <%= format_event_date(event.start_at, event.timezone) %>
                                </span>
                                <span>
                                  <Heroicons.map_pin class="w-4 h-4 inline mr-1" />
                                  <%= format_event_location(event) %>
                                </span>
                              </div>
                            </div>
                            <div class="flex flex-col items-end space-y-2">
                              <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{event_status_color(event.status)}"}>
                                <%= event_status_text(event.status) %>
                              </span>
                              <span class={[
                                "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
                                if(event.user_role == "organizer", do: "bg-blue-100 text-blue-800", else: "bg-green-100 text-green-800")
                              ]}>
                                <%= if event.user_role == "organizer", do: "Hosted", else: "Attended" %>
                              </span>
                            </div>
                          </div>
                        </div>
                      </.link>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="text-center py-12">
                  <Heroicons.calendar class="w-12 h-12 mx-auto mb-4 text-gray-400" />
                  <p class="text-gray-500">
                    <%= if @is_own_profile, do: "You haven't participated in any events yet.", else: "No events to display yet." %>
                  </p>
                  <%= if @is_own_profile do %>
                    <.link href={~p"/events/new"} class="mt-4 inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-blue-600 bg-blue-50 hover:bg-blue-100 transition-colors">
                      Create your first event
                    </.link>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Sidebar -->
          <div class="space-y-6">
            <!-- Events Together Panel - Only shown to logged-in users viewing others -->
            <%= if @connection_context do %>
              <div class="bg-white shadow-sm rounded-lg p-6">
                <h3 class="text-sm font-semibold text-gray-900 uppercase tracking-wide mb-4">Events Together</h3>

                <!-- Connection Degree Display -->
                <div class="mb-4">
                  <%= case @connection_context.connection_degree do %>
                    <% :connected -> %>
                      <div class="flex items-center text-green-700 bg-green-50 rounded-lg px-4 py-3">
                        <Heroicons.check_circle class="w-5 h-5 mr-3" />
                        <div>
                          <p class="font-medium">Keeping Up</p>
                          <p class="text-sm text-green-600">You'll see when they're going to events</p>
                        </div>
                      </div>

                    <% :pending -> %>
                      <div class="flex items-center text-amber-700 bg-amber-50 rounded-lg px-4 py-3">
                        <Heroicons.clock class="w-5 h-5 mr-3" />
                        <div>
                          <p class="font-medium">Request Pending</p>
                          <p class="text-sm text-amber-600">Waiting for response</p>
                        </div>
                      </div>

                    <% :shared_events -> %>
                      <div class="flex items-center text-blue-700 bg-blue-50 rounded-lg px-4 py-3">
                        <Heroicons.calendar class="w-5 h-5 mr-3" />
                        <div>
                          <p class="font-medium">Shared Events</p>
                          <p class="text-sm text-blue-600">
                            You've attended <%= @connection_context.mutual_event_count %> event<%= if @connection_context.mutual_event_count != 1, do: "s" %> together
                          </p>
                        </div>
                      </div>

                    <% :extended_network -> %>
                      <div class="flex items-center text-purple-700 bg-purple-50 rounded-lg px-4 py-3">
                        <Heroicons.user_group class="w-5 h-5 mr-3" />
                        <div>
                          <p class="font-medium">Extended Network</p>
                          <p class="text-sm text-purple-600">Connected through mutual friends</p>
                        </div>
                      </div>

                    <% :no_connection -> %>
                      <div class="flex items-center text-gray-500 bg-gray-50 rounded-lg px-4 py-3">
                        <Heroicons.user class="w-5 h-5 mr-3" />
                        <div>
                          <p class="font-medium">No Connection</p>
                          <p class="text-sm text-gray-400">No shared events or mutual friends</p>
                        </div>
                      </div>
                  <% end %>
                </div>

                <!-- Keep Up Button - Only shown when there's a valid basis -->
                <%= if @connection_context.can_show_button do %>
                  <div class="space-y-3">
                    <.live_component
                      module={EventasaurusWeb.RelationshipButtonComponent}
                      id={"relationship-button-#{@profile_user.id}"}
                      current_user={@user}
                      other_user={@profile_user}
                      event={List.first(@mutual_events)}
                      size={:large}
                      variant={:primary}
                    />
                    <!-- Helper text explaining what Keep Up does -->
                    <%= if !@connection_context.is_connected do %>
                      <p class="text-xs text-gray-500 text-center">
                        See when they're going to events you might like
                      </p>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

            <!-- Social Links -->
            <%= if @profile_user.website_url || Enum.any?(social_links(@profile_user)) do %>
              <div class="bg-white shadow-sm rounded-lg p-6">
                <h3 class="text-sm font-semibold text-gray-900 uppercase tracking-wide mb-4">Connect</h3>
                <div class="space-y-3">
                  <%= if @profile_user.website_url && @profile_user.website_url != "" do %>
                    <a
                      href={format_website_url(@profile_user.website_url)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="flex items-center text-gray-700 hover:text-blue-600 transition-colors"
                    >
                      <Heroicons.arrow_top_right_on_square class="w-5 h-5 mr-3 text-gray-400" />
                      <span class="font-medium">Website</span>
                    </a>
                  <% end %>

                  <%= for {platform, handle} <- social_links(@profile_user) do %>
                    <a
                      href={social_url(handle, platform)}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="flex items-center text-gray-700 hover:text-blue-600 transition-colors"
                    >
                      <div class="w-5 h-5 mr-3 flex items-center justify-center">
                        <span class="text-sm">🔗</span>
                      </div>
                      <span class="font-medium"><%= platform_name(platform) %></span>
                    </a>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Quick Stats Card -->
            <div class="bg-white shadow-sm rounded-lg p-6">
              <h3 class="text-sm font-semibold text-gray-900 uppercase tracking-wide mb-4">Activity</h3>
              <div class="space-y-3">
                <div class="flex justify-between items-center">
                  <span class="text-sm text-gray-600">Events hosted</span>
                  <span class="font-semibold text-gray-900"><%= @stats.hosted %></span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-sm text-gray-600">Events attended</span>
                  <span class="font-semibold text-gray-900"><%= @stats.attended %></span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-sm text-gray-600">People met</span>
                  <span class="font-semibold text-gray-900"><%= @stats.together %></span>
                </div>
                <%= if @stats.hosted > 0 || @stats.attended > 0 do %>
                  <div class="pt-3 border-t border-gray-200">
                    <div class="flex justify-between items-center">
                      <span class="text-sm text-gray-600">Total events</span>
                      <span class="font-bold text-blue-600"><%= @stats.hosted + @stats.attended %></span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <!-- Member Since -->
            <div class="bg-white shadow-sm rounded-lg p-6">
              <h3 class="text-sm font-semibold text-gray-900 uppercase tracking-wide mb-4">Member Since</h3>
              <div class="flex items-center">
                <Heroicons.calendar class="w-5 h-5 mr-3 text-gray-400" />
                <span class="text-gray-900"><%= format_join_date(@profile_user.inserted_at) %></span>
              </div>
            </div>
          </div>
        </div>

        <!-- Footer Note for Private Profiles -->
        <%= if @is_own_profile && !@profile_user.profile_public do %>
          <div class="mt-8 bg-amber-50 border border-amber-200 rounded-lg p-4">
            <div class="flex items-start">
              <Heroicons.exclamation_triangle class="w-5 h-5 text-amber-600 mr-3 mt-0.5" />
              <div>
                <p class="text-sm text-amber-800">
                  <strong>Private Profile:</strong> Only you can see this profile page.
                  <.link href={~p"/settings"} class="underline hover:no-underline font-medium">
                    Make it public
                  </.link>
                  so others can discover your events and connect with you.
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
