defmodule EventasaurusWeb.PublicPollsLive do
  @moduledoc """
  Public polls page for events - displays both active and historical polls
  without requiring authentication.
  """

  use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusApp.Events
  alias EventasaurusWeb.PublicGenericPollComponent
  alias EventasaurusWeb.ReservedSlugs
  alias EventasaurusWeb.UrlHelper

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.PollHelpers

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    if ReservedSlugs.reserved?(slug) do
      {:ok,
       socket
       |> put_flash(:error, "Event not found")
       |> redirect(to: ~p"/")}
    else
      case Events.get_event_by_slug(slug) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Event not found")
           |> redirect(to: ~p"/")}

        event ->
          # Load polls for the event
          polls = Events.list_polls(event)

          # Separate active and historical polls
          {active_polls, historical_polls} = separate_polls_by_status(polls)

          {:ok,
           socket
           |> assign(:event, event)
           |> assign(:polls, polls)
           |> assign(:active_polls, active_polls)
           |> assign(:historical_polls, historical_polls)
           |> assign(:page_title, "#{event.title} - Polls")
           |> assign(:meta_title, "#{event.title} - Polls")
           |> assign(:meta_description, "View and participate in polls for #{event.title}")
           |> assign(:meta_image, EventasaurusWeb.PollHelpers.generate_social_image_url(event))
           # canonical_url will be updated in handle_params with request URI for ngrok support
           |> assign(:canonical_url, UrlHelper.build_url("/#{event.slug}/polls"))
           # Anonymous voting state
           |> assign(:show_anonymous_voter, false)
           |> assign(:selected_poll_for_voting, nil)
           |> assign(:poll_temp_votes, %{})
           |> assign(:loading_polls, [])}
      end
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Parse URI for consistent URL building with UrlHelper (ngrok support)
    request_uri = URI.parse(uri)

    # Update canonical_url with correct base URL if event exists
    socket =
      if socket.assigns[:event] do
        event = socket.assigns.event
        canonical_path = "/#{event.slug}/polls"

        assign(socket, :canonical_url, UrlHelper.build_url(canonical_path, request_uri))
      else
        socket
      end

    {:noreply, assign(socket, :current_uri, uri)}
  end

  @impl true
  def handle_event("show_anonymous_voter", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

    {:noreply,
     socket
     |> assign(:show_anonymous_voter, true)
     |> assign(:selected_poll_for_voting, poll)}
  end

  def handle_event("hide_anonymous_voter", _, socket) do
    loading_polls =
      case socket.assigns.selected_poll_for_voting do
        %{id: id} -> remove_poll_from_loading_list(socket.assigns.loading_polls, id)
        _ -> socket.assigns.loading_polls
      end

    {:noreply,
     socket
     |> assign(:show_anonymous_voter, false)
     |> assign(:selected_poll_for_voting, nil)
     |> assign(:loading_polls, loading_polls)}
  end

  def handle_event("vote", params, socket) do
    poll_id = String.to_integer(params["poll_id"])

    # Handle voting logic based on whether user is authenticated
    case socket.assigns[:auth_user] do
      nil ->
        # Redirect to anonymous voting component
        poll = Enum.find(socket.assigns.polls, &(&1.id == poll_id))

        {:noreply,
         socket
         |> assign(:show_anonymous_voter, true)
         |> assign(:selected_poll_for_voting, poll)}

      user ->
        # Add poll to loading state for authenticated users only
        loading_polls = add_poll_to_loading_list(socket.assigns.loading_polls, poll_id)
        socket = assign(socket, :loading_polls, loading_polls)

        # Handle authenticated user voting
        case EventasaurusWeb.PollHelpers.handle_authenticated_vote(socket, poll_id, params, user) do
          {:ok, :vote_processed} ->
            {:noreply, socket}

          {:error, reason, loading_polls} ->
            {:noreply,
             socket
             |> put_flash(:error, reason)
             |> assign(:loading_polls, loading_polls)}
        end
    end
  end

  @impl true
  def handle_info({:anonymous_vote_completed, poll_id}, socket) do
    # Reload the poll data after anonymous voting
    updated_polls = Events.list_polls(socket.assigns.event)
    {active_polls, historical_polls} = separate_polls_by_status(updated_polls)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:active_polls, active_polls)
     |> assign(:historical_polls, historical_polls)
     |> assign(
       :loading_polls,
       remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)
     )
     |> assign(:show_anonymous_voter, false)
     |> assign(:selected_poll_for_voting, nil)
     |> put_flash(:info, "Vote submitted successfully!")}
  end

  def handle_info({:vote_completed, poll_id}, socket) do
    # Reload the poll data after voting
    updated_polls = Events.list_polls(socket.assigns.event)
    {active_polls, historical_polls} = separate_polls_by_status(updated_polls)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:active_polls, active_polls)
     |> assign(:historical_polls, historical_polls)
     |> assign(
       :loading_polls,
       remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)
     )
     |> put_flash(:info, "Vote submitted successfully!")}
  end

  @impl true
  def handle_info({:poll_stats_updated, _stats}, socket) do
    # Reload all polls to get fresh data with votes
    updated_polls = Events.list_polls(socket.assigns.event)
    {active_polls, historical_polls} = separate_polls_by_status(updated_polls)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:active_polls, active_polls)
     |> assign(:historical_polls, historical_polls)}
  end

  def handle_info({:poll_stats_updated, _poll_id, _stats}, socket) do
    # Reload all polls to get fresh data with votes
    updated_polls = Events.list_polls(socket.assigns.event)
    {active_polls, historical_polls} = separate_polls_by_status(updated_polls)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:active_polls, active_polls)
     |> assign(:historical_polls, historical_polls)}
  end

  def handle_info({:vote_cast, _poll_option_id, _vote_value}, socket) do
    # Reload all polls to get fresh data with votes
    updated_polls = Events.list_polls(socket.assigns.event)
    {active_polls, historical_polls} = separate_polls_by_status(updated_polls)

    {:noreply,
     socket
     |> assign(:polls, updated_polls)
     |> assign(:active_polls, active_polls)
     |> assign(:historical_polls, historical_polls)}
  end

  def handle_info({:temp_votes_updated, poll_id, temp_votes}, socket) do
    votes = Map.put(socket.assigns[:poll_temp_votes] || %{}, poll_id, temp_votes)
    {:noreply, assign(socket, :poll_temp_votes, votes)}
  end

  # Private functions
end
