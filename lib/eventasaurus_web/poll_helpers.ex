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
    case Events.get_poll_voting_stats(poll) do
      %{total_unique_voters: count} when is_integer(count) and count > 0 ->
        word = if count == 1, do: "participant", else: "participants"
        "#{count} #{word}"

      %{total_unique_voters: _} ->
        "No participants yet"

      _ ->
        "Loading..."
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
  Returns result tuple that calling LiveView should handle.
  """
  def handle_authenticated_vote(socket, poll_id, params, user) do
    polls = get_polls_from_socket(socket)
    poll = Enum.find(polls, &(&1.id == poll_id))

    case poll do
      nil ->
        {:error, "Poll not found",
         remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)}

      poll ->
        # Process the vote based on poll type and voting system
        case process_vote(poll, params, user) do
          {:ok, _result} ->
            send(self(), {:vote_completed, poll_id})
            {:ok, :vote_processed}

          {:error, reason} ->
            {:error, reason, remove_poll_from_loading_list(socket.assigns.loading_polls, poll_id)}
        end
    end
  end

  @doc """
  Processes a vote for a poll option.
  """
  def process_vote(poll, params, user) do
    # Guard: enforce phase, deadline, and participation rules
    unless Events.can_user_vote?(poll, user) do
      {:error, "Voting is closed or you are not allowed to vote"}
    else
      # Safely parse option id
      option_id =
        case params["option_id"] || params["option-id"] do
          option_id_str when is_binary(option_id_str) ->
            case Integer.parse(option_id_str) do
              {id, ""} -> id
              _ -> nil
            end

          option_id_int when is_integer(option_id_int) ->
            option_id_int

          _ ->
            nil
        end

      if is_nil(option_id) do
        {:error, "Invalid option id"}
      else
        # Get the poll option and validate it belongs to the poll
        case Events.get_poll_option(option_id) do
          nil ->
            {:error, "Option not found"}

          poll_option ->
            # Ensure option belongs to this poll and is active
            cond do
              poll_option.poll_id != poll.id ->
                {:error, "Option does not belong to this poll"}

              Map.get(poll_option, :deleted_at) != nil or poll_option.status != "active" ->
                {:error, "Option is inactive"}

              true ->
                process_vote_by_system(poll, poll_option, user, params)
            end
        end
      end
    end
  end

  # Process vote based on voting system
  defp process_vote_by_system(poll, poll_option, user, params) do
    case poll.voting_system do
      "binary" ->
        vote_value = String.downcase(to_string(params["vote_value"] || params["vote"] || "yes"))

        if vote_value in ["yes", "maybe", "no"] do
          case Events.cast_binary_vote(poll, poll_option, user, vote_value) do
            {:ok, _vote} -> {:ok, :voted}
            {:error, reason} -> {:error, "Failed to submit vote: #{inspect(reason)}"}
          end
        else
          {:error, "Invalid vote value for binary voting. Use 'yes', 'maybe', or 'no'."}
        end

      "approval" ->
        selected =
          case params["vote_value"] || params["vote"] do
            val when val in ["true", "1", "yes", "selected"] -> true
            val when val in ["false", "0", "no", "unselected"] -> false
            # Default to selected for approval voting
            _ -> true
          end

        case Events.cast_approval_vote(poll, poll_option, user, selected) do
          {:ok, _vote} -> {:ok, :voted}
          {:error, reason} -> {:error, "Failed to submit vote: #{inspect(reason)}"}
        end

      "star" ->
        rating =
          case params["rating"] || params["vote_value"] || params["vote"] do
            rating_str when is_binary(rating_str) ->
              case Float.parse(rating_str) do
                {rating, _} when rating >= 1.0 and rating <= 5.0 -> rating
                _ -> nil
              end

            rating_num when is_number(rating_num) and rating_num >= 1 and rating_num <= 5 ->
              rating_num

            _ ->
              nil
          end

        if is_nil(rating) do
          {:error, "Invalid rating for star voting. Use rating between 1 and 5."}
        else
          case Events.cast_star_vote(poll, poll_option, user, rating) do
            {:ok, _vote} -> {:ok, :voted}
            {:error, reason} -> {:error, "Failed to submit vote: #{inspect(reason)}"}
          end
        end

      "ranked" ->
        rank =
          case params["rank"] || params["vote_rank"] || params["vote"] do
            rank_str when is_binary(rank_str) ->
              case Integer.parse(rank_str) do
                {rank, ""} when rank > 0 -> rank
                _ -> nil
              end

            rank_int when is_integer(rank_int) and rank_int > 0 ->
              rank_int

            _ ->
              nil
          end

        if is_nil(rank) do
          {:error, "Invalid rank for ranked voting. Use positive integer."}
        else
          case Events.cast_ranked_vote(poll, poll_option, user, rank) do
            {:ok, _vote} -> {:ok, :voted}
            {:error, reason} -> {:error, "Failed to submit vote: #{inspect(reason)}"}
          end
        end

      unknown_system ->
        {:error, "Unsupported voting system: #{unknown_system}"}
    end
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
      nil ->
        nil

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
    loading_polls = loading_polls || []
    [poll_id | loading_polls] |> Enum.uniq()
  end

  @doc """
  Returns updated loading_polls list with poll_id removed.
  """
  def remove_poll_from_loading_list(loading_polls, poll_id) do
    loading_polls = loading_polls || []
    Enum.reject(loading_polls, &(&1 == poll_id))
  end

  @doc """
  Checks if a poll is currently in loading state.
  """
  def is_poll_loading?(loading_polls, poll_id) do
    poll_id in loading_polls
  end
end
