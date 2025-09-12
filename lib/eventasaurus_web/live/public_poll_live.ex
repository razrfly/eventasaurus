defmodule EventasaurusWeb.PublicPollLive do
  @moduledoc """
  Individual public poll page for events - displays a single poll
  without requiring authentication.
  """

  use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusApp.Events
  alias EventasaurusWeb.{PublicGenericPollComponent, AnonymousVoterComponent}
  alias EventasaurusWeb.ReservedSlugs

  import EventasaurusWeb.PollView, only: [poll_emoji: 1]
  import EventasaurusWeb.PollHelpers

  @impl true
  def mount(%{"slug" => slug, "poll_id" => poll_id}, _session, socket) do
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
          case get_poll_by_id(event, poll_id) do
            nil ->
              {:ok,
               socket
               |> put_flash(:error, "Poll not found")
               |> redirect(to: ~p"/#{event.slug}/polls")
              }

            poll ->
              {:ok,
               socket
               |> assign(:event, event)
               |> assign(:poll, poll)
               |> assign(:page_title, "#{poll.title} - #{event.title}")
               |> assign(:meta_title, "#{poll.title} - #{event.title}")
               |> assign(:meta_description, poll.description || "Participate in this poll for #{event.title}")
               |> assign(:meta_image, EventasaurusWeb.PollHelpers.generate_social_image_url(event, poll))
               |> assign(:canonical_url, "#{EventasaurusWeb.Endpoint.url()}/#{event.slug}/polls/#{poll.id}")
               # Anonymous voting state
               |> assign(:show_anonymous_voter, false)
               |> assign(:temp_votes, %{})
               |> assign(:loading_polls, [])
              }
          end
      end
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :current_uri, uri)}
  end

  @impl true
  def handle_event("show_anonymous_voter", %{"poll_id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)
    
    if socket.assigns.poll.id == poll_id do
      {:noreply,
       socket
       |> assign(:show_anonymous_voter, true)
      }
    else
      {:noreply, socket}
    end
  end

  def handle_event("hide_anonymous_voter", _, socket) do
    {:noreply,
     socket
     |> assign(:show_anonymous_voter, false)
    }
  end

  def handle_event("vote", params, socket) do
    poll_id = String.to_integer(params["poll_id"])
    
    # Add poll to loading state
    loading_polls = add_poll_to_loading_list(socket.assigns.loading_polls, poll_id)
    socket = assign(socket, :loading_polls, loading_polls)
    
    # Handle voting logic based on whether user is authenticated
    case socket.assigns[:auth_user] do
      nil ->
        # Redirect to anonymous voting component
        if socket.assigns.poll.id == poll_id do
          {:noreply,
           socket
           |> assign(:show_anonymous_voter, true)
          }
        else
          {:noreply, socket}
        end
        
      user ->
        # Handle authenticated user voting - check poll ID first
        if socket.assigns.poll.id == poll_id do
          EventasaurusWeb.PollHelpers.handle_authenticated_vote(socket, poll_id, params, user)
        else
          {:noreply,
           socket
           |> put_flash(:error, "Poll not found")
           |> assign(:loading_polls, remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id))
          }
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
       |> assign(:loading_polls, remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id))
       |> assign(:show_anonymous_voter, false)
       |> put_flash(:info, "Vote submitted successfully!")
      }
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
       |> assign(:loading_polls, remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id))
       |> put_flash(:info, "Vote submitted successfully!")
      }
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

  # Private functions

  defp get_poll_by_id(event, poll_id) do
    case Integer.parse(poll_id) do
      {id, ""} ->
        polls = Events.list_polls(event)
        Enum.find(polls, &(&1.id == id))
      _ ->
        nil
    end
  end








end