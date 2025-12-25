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
  alias EventasaurusApp.Discovery
  alias EventasaurusApp.Relationships

  # Use external template
  embed_templates "profile_live.html"

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

    # Get suggested people for logged-in users viewing their own profile
    suggested_people =
      if current_user && is_own_profile do
        Discovery.discover(current_user, limit: 6)
      else
        []
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
    |> assign(:suggested_people, suggested_people)
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
    can_show_button =
      connection_degree in [:connected, :pending, :shared_events, :extended_network]

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
      :instagram ->
        "https://instagram.com/#{clean_handle}"

      :x ->
        "https://x.com/#{clean_handle}"

      :youtube ->
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://youtube.com/@#{clean_handle}"
        end

      :tiktok ->
        "https://tiktok.com/@#{clean_handle}"

      :linkedin ->
        if String.starts_with?(handle, ["http://", "https://"]) do
          handle
        else
          "https://linkedin.com/in/#{clean_handle}"
        end

      _ ->
        "#"
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

  # Social platform icons using simple SVG icons for platforms not in Heroicons
  # Returns raw HTML for SVG icons
  defp social_icon(platform) do
    svg_class = "w-5 h-5 mr-3 text-gray-400"

    case platform do
      :instagram ->
        Phoenix.HTML.raw(
          ~s(<svg class="#{svg_class}" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/></svg>)
        )

      :x ->
        Phoenix.HTML.raw(
          ~s(<svg class="#{svg_class}" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>)
        )

      :youtube ->
        Phoenix.HTML.raw(
          ~s(<svg class="#{svg_class}" viewBox="0 0 24 24" fill="currentColor"><path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/></svg>)
        )

      :tiktok ->
        Phoenix.HTML.raw(
          ~s(<svg class="#{svg_class}" viewBox="0 0 24 24" fill="currentColor"><path d="M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>)
        )

      :linkedin ->
        Phoenix.HTML.raw(
          ~s(<svg class="#{svg_class}" viewBox="0 0 24 24" fill="currentColor"><path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/></svg>)
        )

      _ ->
        Phoenix.HTML.raw(
          ~s(<svg class="#{svg_class}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/></svg>)
        )
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
end
