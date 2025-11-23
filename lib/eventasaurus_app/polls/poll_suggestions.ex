defmodule EventasaurusApp.Polls.PollSuggestions do
  @moduledoc """
  Generates poll suggestions based on a user's historical polling patterns.

  This module analyzes previous polls created by the user (either from the same
  group or all their events) to suggest common poll templates when creating new polls.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{Poll, EventUser}

  @doc """
  Generates poll suggestions for a user creating a poll for a specific event.

  The algorithm:
  1. Finds all events where the user is an organizer
  2. If the current event has a group_id, filters to events in the same group
  3. Gets all polls from those events
  4. Analyzes patterns (most common poll types, titles, and options)
  5. Returns up to 3 suggestions ordered by usage frequency

  ## Parameters

    - user_id: The ID of the user creating the poll
    - event: The event struct for which the poll is being created

  ## Returns

  A list of suggestion maps, each containing:
  - `poll_type`: The type of poll (e.g., "movie", "places", "custom")
  - `voting_system`: The voting system used (e.g., "binary", "approval")
  - `suggested_title`: A common title used for this type of poll
  - `common_options`: A list of enriched option maps with metadata
  - `usage_count`: Number of times this pattern was used
  - `confidence`: A 0-1 score indicating how confident we are in this suggestion

  ## Examples

      iex> generate_suggestions(user_id, event)
      [
        %{
          poll_type: "places",
          voting_system: "approval",
          suggested_title: "Where should we go?",
          common_options: [
            %{
              title: "Coffee Shop",
              image_url: "https://...",
              metadata: %{...},
              original_recommender: %{id: 1, name: "John Doe"}
            }
          ],
          usage_count: 5,
          confidence: 0.85
        }
      ]
  """
  def generate_suggestions(user_id, event) when is_integer(user_id) do
    # Step 1: Find events where user is an organizer
    event_ids = get_organizer_event_ids(user_id, event)

    # Step 2: Get all polls from those events
    polls = get_polls_from_events(event_ids)

    # Step 3: If no historical polls, return empty list
    if Enum.empty?(polls) do
      []
    else
      # Step 4: Analyze patterns and generate suggestions
      polls
      |> group_by_type_and_voting_system()
      |> calculate_suggestions()
      |> sort_by_confidence()
      |> Enum.take(3)
    end
  end

  # Fallback for nil user_id
  def generate_suggestions(nil, _event), do: []

  # Private functions

  defp get_organizer_event_ids(user_id, event) do
    query =
      from(eu in EventUser,
        join: e in assoc(eu, :event),
        where: eu.user_id == ^user_id and eu.role == "organizer" and is_nil(e.deleted_at),
        select: eu.event_id
      )

    query =
      if event.group_id do
        # Filter to same group if event has a group
        from([eu, e] in query,
          where: e.group_id == ^event.group_id
        )
      else
        query
      end

    Repo.all(query)
  end

  defp get_polls_from_events(event_ids) when is_list(event_ids) do
    if Enum.empty?(event_ids) do
      []
    else
      from(p in Poll,
        where: p.event_id in ^event_ids and is_nil(p.deleted_at),
        preload: [poll_options: :suggested_by, event: []]
      )
      |> Repo.all()
      |> Enum.map(fn poll ->
        # Filter out soft-deleted options after loading
        active_options = Enum.filter(poll.poll_options, &is_nil(&1.deleted_at))
        %{poll | poll_options: active_options}
      end)
    end
  end

  defp group_by_type_and_voting_system(polls) do
    polls
    |> Enum.group_by(fn poll ->
      {poll.poll_type, poll.voting_system || "binary"}
    end)
  end

  defp calculate_suggestions(grouped_polls) do
    Enum.map(grouped_polls, fn {{poll_type, voting_system}, polls} ->
      usage_count = length(polls)

      # Find most common title (mode)
      title_frequencies =
        polls
        |> Enum.map(& &1.title)
        |> Enum.frequencies()

      suggested_title =
        if map_size(title_frequencies) > 0 do
          title_frequencies
          |> Enum.max_by(fn {_title, count} -> count end)
          |> elem(0)
        else
          format_default_title(poll_type)
        end

      # Aggregate all options with full metadata and find most common
      # Group by title to find the most recent/best version of each option
      all_options_with_metadata =
        polls
        |> Enum.flat_map(fn poll ->
          Enum.map(poll.poll_options, fn option ->
            %{
              option: option,
              poll: poll
            }
          end)
        end)
        |> Enum.group_by(fn %{option: option} -> option.title end)
        |> Enum.map(fn {title, option_instances} ->
          # Count frequency
          count = length(option_instances)

          # Get the most recent instance (based on poll creation)
          best_instance =
            option_instances
            |> Enum.sort_by(fn %{poll: poll} -> poll.inserted_at end, :desc)
            |> List.first()

          {title, count, best_instance}
        end)
        |> Enum.sort_by(fn {_title, count, _instance} -> count end, :desc)
        |> Enum.take(6)

      # Build enriched option data
      common_options =
        Enum.map(all_options_with_metadata, fn {_title, _count,
                                                %{option: option, poll: source_poll}} ->
          # Build recommender info
          recommender_info =
            case option.suggested_by do
              %{id: id, full_name: name} when not is_nil(name) ->
                %{id: id, name: name}

              %{id: id, username: username} when not is_nil(username) ->
                %{id: id, name: username}

              %{id: id} ->
                %{id: id, name: "User ##{id}"}

              _ ->
                nil
            end

          # Build source event info
          source_event_info =
            case source_poll.event do
              %{id: event_id, title: event_title} ->
                %{id: event_id, title: event_title}

              _ ->
                %{id: source_poll.event_id, title: nil}
            end

          %{
            title: option.title,
            description: option.description,
            image_url: option.image_url,
            external_id: option.external_id,
            external_data: option.external_data,
            metadata: option.metadata,
            original_recommender: recommender_info,
            source_event: source_event_info,
            source_poll_id: source_poll.id
          }
        end)

      # Calculate confidence based on usage count and consistency
      total_polls = Enum.sum(Enum.map(grouped_polls, fn {_k, v} -> length(v) end))
      confidence = min(usage_count / max(total_polls, 1), 1.0)

      %{
        poll_type: poll_type,
        voting_system: voting_system,
        suggested_title: suggested_title,
        common_options: common_options,
        usage_count: usage_count,
        confidence: confidence
      }
    end)
  end

  defp sort_by_confidence(suggestions) do
    suggestions
    |> Enum.sort_by(
      fn suggestion ->
        {suggestion.confidence, suggestion.usage_count}
      end,
      :desc
    )
  end

  defp format_default_title(poll_type) do
    case poll_type do
      "movie" -> "What movie should we watch?"
      "places" -> "Where should we go?"
      "music_track" -> "What music should we play?"
      "venue" -> "Where should we meet?"
      "date_selection" -> "When should we meet?"
      "time" -> "What time works best?"
      "general" -> "What should we do?"
      _ -> "Poll"
    end
  end
end
