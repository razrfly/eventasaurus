defmodule EventasaurusWeb.PollHelpers do
  @moduledoc """
  Centralized helper functions for poll-related functionality.
  
  This module consolidates common poll helper functions to eliminate duplication
  across multiple LiveView modules (PublicPollLive, PublicPollsLive, PublicEventLive).
  """

  alias EventasaurusApp.Events

  @doc """
  Returns human-readable display text for poll phases.
  """
  def poll_phase_display_text(phase) do
    case phase do
      "list_building" -> "Open for Suggestions"
      "voting" -> "Voting Open"
      "voting_with_suggestions" -> "Voting Open (+ Suggestions)"
      "voting_only" -> "Voting Open"
      "closed" -> "Closed"
      _ -> "Unknown"
    end
  end

  @doc """
  Determines if a poll is currently active (accepting votes or suggestions).
  """
  def is_poll_active?(poll) do
    poll.phase in ["list_building", "voting", "voting_with_suggestions", "voting_only"]
  end

  @doc """
  Returns CSS classes for poll status badges based on activity state.
  """
  def poll_status_class(poll) do
    if is_poll_active?(poll) do
      "bg-green-100 text-green-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  @doc """
  Returns a formatted participation summary for a poll.
  """
  def poll_participation_summary(poll) do
    try do
      stats = Events.get_poll_voting_stats(poll)
      participant_count = stats.total_unique_voters || 0
      
      if participant_count > 0 do
        participant_word = if participant_count == 1, do: "participant", else: "participants"
        "#{participant_count} #{participant_word}"
      else
        "No participants yet"
      end
    rescue
      _ -> "Loading..."
    end
  end

  @doc """
  Converts datetime to relative time display (e.g., "in 2 days", "3 hours ago").
  """
  def relative_datetime(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(datetime, now, :second)

    cond do
      diff > 86400 -> "in #{div(diff, 86400)} days"
      diff > 3600 -> "in #{div(diff, 3600)} hours"
      diff > 60 -> "in #{div(diff, 60)} minutes"
      diff > 0 -> "in #{diff} seconds"
      diff > -60 -> "just now"
      diff > -3600 -> "#{div(-diff, 60)} minutes ago"
      diff > -86400 -> "#{div(-diff, 3600)} hours ago"
      true -> "#{div(-diff, 86400)} days ago"
    end
  end

  def relative_datetime(%NaiveDateTime{} = naive_datetime) do
    datetime = DateTime.from_naive!(naive_datetime, "Etc/UTC")
    relative_datetime(datetime)
  end

  def relative_datetime(_), do: "unknown"

  @doc """
  Handles authenticated user voting logic.
  """
  def handle_authenticated_vote(socket, poll_id, params, user) do
    polls = get_polls_from_socket(socket)
    poll = Enum.find(polls, &(&1.id == poll_id))
    
    case poll do
      nil ->
        loading_polls = remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)
        {:noreply, 
         socket
         |> Phoenix.LiveView.put_flash(:error, "Poll not found")
         |> Phoenix.LiveView.assign(:loading_polls, loading_polls)
        }
        
      poll ->
        # Process the vote based on poll type and voting system
        case process_vote(poll, params, user) do
          {:ok, _result} ->
            send(self(), {:vote_completed, poll_id})
            {:noreply, socket}
            
          {:error, reason} ->
            loading_polls = remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)
            {:noreply,
             socket
             |> Phoenix.LiveView.put_flash(:error, reason)
             |> Phoenix.LiveView.assign(:loading_polls, loading_polls)
            }
        end
    end
  end


  @doc """
  Processes a vote for a poll option.
  """
  def process_vote(poll, params, user) do
    # This would delegate to appropriate voting logic based on poll type
    # For now, handle generic voting
    option_id = String.to_integer(params["option_id"])
    vote_value = params["vote_value"] || "yes"
    
    # Get the poll option
    case Events.get_poll_option(option_id) do
      nil -> {:error, "Option not found"}
      poll_option ->
        case Events.cast_binary_vote(poll, poll_option, user, vote_value) do
          {:ok, _vote} -> {:ok, :voted}
          {:error, _reason} -> {:error, "Failed to submit vote"}
        end
    end
  rescue
    _ -> {:error, "Failed to submit vote"}
  end

  @doc """
  Separates polls into active and historical lists based on their phases.
  """
  def separate_polls_by_status(polls) do
    Enum.split_with(polls, fn poll ->
      poll.phase in ["list_building", "voting", "voting_with_suggestions", "voting_only"]
    end)
  end

  @doc """
  Generates social image URL for polls.
  """
  def generate_social_image_url(event, poll \\ nil) do
    case Map.get(event, :hash) do
      nil -> nil
      hash when is_nil(poll) -> 
        "#{EventasaurusWeb.Endpoint.url()}/events/#{event.slug}/social-card-#{hash}/polls.png"
      hash -> 
        "#{EventasaurusWeb.Endpoint.url()}/events/#{event.slug}/social-card-#{hash}/poll-#{poll.id}.png"
    end
  end

  # Private helper functions

  defp get_polls_from_socket(socket) do
    # Handle different socket structures - some have single poll, some have multiple
    cond do
      Map.has_key?(socket.assigns, :polls) -> socket.assigns.polls
      Map.has_key?(socket.assigns, :poll) -> [socket.assigns.poll]
      true -> []
    end
  end

  @doc """
  Returns updated loading_polls list with poll_id added.
  """
  def add_poll_to_loading_list(loading_polls, poll_id) do
    [poll_id | loading_polls]
  end

  @doc """
  Returns updated loading_polls list with poll_id removed.
  """
  def remove_poll_from_loading_list(loading_polls, poll_id) do
    List.delete(loading_polls, poll_id)
  end

  @doc """
  Checks if a poll is currently in loading state.
  """
  def is_poll_loading?(loading_polls, poll_id) do
    poll_id in loading_polls
  end
end