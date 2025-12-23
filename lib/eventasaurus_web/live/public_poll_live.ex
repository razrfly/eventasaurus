defmodule EventasaurusWeb.PublicPollLive do
  @moduledoc """
  Individual public poll page for events - displays a single poll
  without requiring authentication.
  """

  use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusApp.Events

  alias EventasaurusWeb.{
    PublicGenericPollComponent,
    PublicCocktailPollComponent,
    AnonymousVoterComponent
  }

  alias EventasaurusWeb.ReservedSlugs
  alias EventasaurusWeb.UrlHelper
  alias Eventasaurus.SocialCards.HashGenerator

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.PollHelpers

  @impl true
  def mount(%{"slug" => slug, "number" => number}, _session, socket) do
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
          case get_poll_by_number(event, number) do
            nil ->
              {:ok,
               socket
               |> put_flash(:error, "Poll not found")
               |> redirect(to: ~p"/#{event.slug}/polls")}

            poll ->
              {:ok,
               socket
               |> assign(:event, event)
               |> assign(:poll, poll)
               |> assign(:page_title, "#{poll.title} - #{event.title}")
               |> assign(:meta_title, "#{poll.title} - #{event.title}")
               |> assign(
                 :meta_description,
                 poll.description || "Participate in this poll for #{event.title}"
               )
               |> assign(
                 :meta_image,
                 EventasaurusWeb.PollHelpers.generate_social_image_url(event, poll)
               )
               |> assign(
                 :canonical_url,
                 "#{EventasaurusWeb.Endpoint.url()}/#{event.slug}/polls/#{poll.number}"
               )
               # Anonymous voting state
               |> assign(:show_anonymous_voter, false)
               |> assign(:temp_votes, %{})
               |> assign(:loading_polls, [])}
          end
      end
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Parse URI for consistent URL building with UrlHelper
    request_uri = URI.parse(uri)

    # Update meta_image and canonical_url with correct base URL if poll exists
    socket =
      if socket.assigns[:poll] && socket.assigns[:event] do
        poll = socket.assigns.poll
        event = socket.assigns.event

        social_card_path = HashGenerator.generate_url_path(poll, :poll)
        canonical_path = "/#{event.slug}/polls/#{poll.number}"

        socket
        |> assign(:meta_image, UrlHelper.build_url(social_card_path, request_uri))
        |> assign(:canonical_url, UrlHelper.build_url(canonical_path, request_uri))
      else
        socket
      end

    {:noreply, assign(socket, :current_uri, uri)}
  end

  @impl true
  def handle_event("show_anonymous_voter", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)

    if socket.assigns.poll.id == poll_id do
      {:noreply,
       socket
       |> assign(:show_anonymous_voter, true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hide_anonymous_voter", _, socket) do
    {:noreply,
     socket
     |> assign(:show_anonymous_voter, false)
     |> assign(
       :loading_polls,
       remove_poll_from_loading_list(socket.assigns.loading_polls, socket.assigns.poll.id)
     )}
  end

  def handle_event("vote", params, socket) do
    poll_id = String.to_integer(params["poll_id"])

    # Handle voting logic based on whether user is authenticated
    case socket.assigns[:auth_user] do
      nil ->
        # Redirect to anonymous voting component
        if socket.assigns.poll.id == poll_id do
          {:noreply,
           socket
           |> assign(:show_anonymous_voter, true)}
        else
          {:noreply, socket}
        end

      user ->
        # Handle authenticated user voting - check poll ID first
        if socket.assigns.poll.id == poll_id do
          # Add poll to loading state for authenticated users only
          loading_polls = add_poll_to_loading_list(socket.assigns.loading_polls, poll_id)
          socket = assign(socket, :loading_polls, loading_polls)

          case EventasaurusWeb.PollHelpers.handle_authenticated_vote(
                 socket,
                 poll_id,
                 params,
                 user
               ) do
            {:ok, :vote_processed} ->
              {:noreply, socket}

            {:error, reason, loading_polls} ->
              {:noreply,
               socket
               |> put_flash(:error, reason)
               |> assign(:loading_polls, loading_polls)}
          end
        else
          {:noreply,
           socket
           |> put_flash(:error, "Poll not found")}
        end
    end
  end

  @impl true
  def handle_info({:anonymous_vote_completed, poll_id}, socket) do
    if socket.assigns.poll.id == poll_id do
      # Reload the poll data after anonymous voting
      updated_poll = Events.get_poll!(poll_id)

      {:noreply,
       socket
       |> assign(:poll, updated_poll)
       |> assign(
         :loading_polls,
         remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)
       )
       |> assign(:show_anonymous_voter, false)
       |> put_flash(:info, "Vote submitted successfully!")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:vote_completed, poll_id}, socket) do
    if socket.assigns.poll.id == poll_id do
      # Reload the poll data after voting
      updated_poll = Events.get_poll!(poll_id)

      {:noreply,
       socket
       |> assign(:poll, updated_poll)
       |> assign(
         :loading_polls,
         remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)
       )
       |> put_flash(:info, "Vote submitted successfully!")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:poll_stats_updated, _stats}, socket) do
    # Reload the poll to get fresh data with votes
    updated_poll = Events.get_poll!(socket.assigns.poll.id)
    {:noreply, assign(socket, :poll, updated_poll)}
  end

  def handle_info({:poll_stats_updated, poll_id, _stats}, socket) do
    if socket.assigns.poll.id == poll_id do
      # Reload the poll to get fresh data with votes
      updated_poll = Events.get_poll!(poll_id)
      {:noreply, assign(socket, :poll, updated_poll)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:vote_cast, _poll_option_id, _vote_value}, socket) do
    # Reload the poll to get fresh data with votes
    updated_poll = Events.get_poll!(socket.assigns.poll.id)
    {:noreply, assign(socket, :poll, updated_poll)}
  end

  def handle_info({:temp_votes_updated, poll_id, temp_votes}, socket) do
    if socket.assigns.poll.id == poll_id do
      {:noreply, assign(socket, :temp_votes, temp_votes)}
    else
      {:noreply, socket}
    end
  end

  # Private functions

  defp get_poll_by_number(event, number_str) do
    case Integer.parse(number_str) do
      {number, ""} ->
        try do
          Events.get_poll_by_number!(number, event.id)
        rescue
          Ecto.NoResultsError -> nil
        end

      _ ->
        nil
    end
  end
end
