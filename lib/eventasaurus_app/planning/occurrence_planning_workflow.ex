defmodule EventasaurusApp.Planning.OccurrencePlanningWorkflow do
  @moduledoc """
  Orchestrates the flexible "Plan with friends" workflow for occurrence-based planning.

  This module handles the complete workflow from filter selection to poll creation:
  1. User selects filters (date range, time, venues)
  2. System finds matching occurrences
  3. System formats occurrences into poll options
  4. System creates private event + poll + occurrence_planning record
  5. System invites friends to vote

  ## Example

      iex> filters = %{
      ...>   date_range: {~D[2024-11-25], ~D[2024-11-30]},
      ...>   time_preferences: ["evening"],
      ...>   city_ids: [1]
      ...> }
      iex> OccurrencePlanningWorkflow.start_flexible_planning(
      ...>   "movie", 123, user_id, filters, friend_ids
      ...> )
      {:ok, %{
        private_event: %Event{...},
        poll: %Poll{...},
        occurrence_planning: %OccurrencePlanning{...}
      }}
  """

  require Logger

  alias EventasaurusApp.{Repo, Events, Accounts}
  alias EventasaurusApp.Planning.{OccurrenceQuery, OccurrenceFormatter, OccurrencePlannings}

  @doc """
  Starts the flexible planning workflow.

  Creates a private event with a poll containing occurrence options.

  ## Parameters

  - `series_type` - Type of series ("movie", "venue", etc.)
  - `series_id` - ID of the series entity
  - `user_id` - ID of the user creating the plan
  - `filter_criteria` - Map with date_range, time_preferences, venue_ids, etc.
  - `friend_ids` - List of user IDs to invite (optional)
  - `opts` - Options:
    - `:event_title` - Custom title for the event
    - `:poll_title` - Custom title for the poll

  ## Returns

  - `{:ok, result}` - Map with :private_event, :poll, :occurrence_planning, :invitations
  - `{:error, reason}` - If workflow fails

  ## Errors

  - `:no_occurrences_found` - No occurrences match the filter criteria
  - `:event_creation_failed` - Failed to create private event
  - `:poll_creation_failed` - Failed to create poll
  - Other errors from underlying modules
  """
  def start_flexible_planning(
        series_type,
        series_id,
        user_id,
        filter_criteria,
        friend_ids \\ [],
        opts \\ []
      ) do
    # Get the organizer user upfront for invitation processing
    organizer = Repo.get!(Accounts.User, user_id)

    Repo.transaction(fn ->
      with {:ok, occurrences} <- find_occurrences(series_type, series_id, filter_criteria),
           _ <-
             Logger.debug(
               "Found #{length(occurrences)} occurrences. First occurrence: #{inspect(List.first(occurrences))}"
             ),
           :ok <- validate_occurrences(occurrences),
           {:ok, private_event} <-
             create_private_event(series_type, series_id, user_id, occurrences, opts),
           {:ok, _membership} <- add_user_as_organizer(private_event, user_id),
           {:ok, poll} <-
             create_occurrence_poll(private_event, user_id, series_type, series_id, opts),
           {:ok, _poll_options} <- create_poll_options(poll, occurrences, user_id),
           {:ok, occurrence_planning} <-
             create_occurrence_planning_record(
               private_event,
               poll,
               series_type,
               series_id,
               filter_criteria
             ),
           {:ok, invitations} <- invite_friends(private_event, friend_ids, organizer) do
        %{
          private_event: private_event,
          poll: poll,
          occurrence_planning: occurrence_planning,
          invitations: invitations
        }
      else
        {:error, reason} ->
          Logger.warning("Flexible planning workflow failed: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Preview occurrences without creating anything.

  Useful for showing users how many options match their filters.

  ## Parameters

  - `series_type` - Type of series
  - `series_id` - ID of the series entity
  - `filter_criteria` - Filter criteria map

  ## Returns

  - `{:ok, occurrences}` - List of matching occurrences
  - `{:error, reason}` - If query fails
  """
  def preview_occurrences(series_type, series_id, filter_criteria) do
    find_occurrences(series_type, series_id, filter_criteria)
  end

  # Private workflow steps

  defp find_occurrences(series_type, series_id, filter_criteria) do
    OccurrenceQuery.find_occurrences(series_type, series_id, filter_criteria)
  end

  defp validate_occurrences([]), do: {:error, :no_occurrences_found}
  defp validate_occurrences(_occurrences), do: :ok

  defp create_private_event(series_type, series_id, _user_id, occurrences, opts) do
    title = Keyword.get(opts, :event_title) || build_default_event_title(series_type, series_id)

    # Extract venue_id from first occurrence
    # For movie polls, all showtimes should be at the same venue typically
    venue_id =
      case occurrences do
        [first | _] -> first.venue_id
        [] -> nil
      end

    attrs = %{
      title: title,
      start_at: DateTime.utc_now() |> DateTime.add(7, :day),
      # TBD - will be set when poll finalizes
      timezone: "UTC",
      visibility: :private,
      status: :draft,
      venue_id: venue_id
    }

    case Events.create_event(attrs) do
      {:ok, event} -> {:ok, event}
      {:error, changeset} -> {:error, {:event_creation_failed, changeset}}
    end
  end

  defp add_user_as_organizer(event, user_id) do
    user = Repo.get!(Accounts.User, user_id)
    Events.add_user_to_event(event, user, "organizer")
  end

  defp create_occurrence_poll(event, user_id, series_type, series_id, opts) do
    title = Keyword.get(opts, :poll_title) || "Which option works best?"

    attrs = %{
      event_id: event.id,
      title: title,
      poll_type: "occurrence_selection",
      voting_system: "binary",
      # or "approval" for multiple selections
      phase: "voting_only",
      status: "active",
      created_by_id: user_id,
      settings: %{
        "occurrence_planning" => true,
        "series_type" => series_type,
        "series_id" => series_id
      }
    }

    case Events.create_poll(attrs) do
      {:ok, poll} -> {:ok, poll}
      {:error, changeset} -> {:error, {:poll_creation_failed, changeset}}
    end
  end

  defp create_poll_options(poll, occurrences, user_id) do
    # Format occurrences into poll option attributes
    option_attrs_list = OccurrenceFormatter.format_options(occurrences)

    # Create all poll options
    results =
      Enum.map(option_attrs_list, fn option_attrs ->
        # Add required fields
        full_attrs =
          Map.merge(option_attrs, %{
            poll_id: poll.id,
            suggested_by_id: user_id,
            status: "active"
          })

        Events.create_poll_option(full_attrs, poll_type: poll.poll_type)
      end)

    # Check if any failed
    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil ->
        # All succeeded
        options = Enum.map(results, fn {:ok, option} -> option end)
        {:ok, options}

      {:error, reason} ->
        {:error, {:poll_option_creation_failed, reason}}
    end
  end

  defp create_occurrence_planning_record(event, poll, series_type, series_id, filter_criteria) do
    attrs = %{
      event_id: event.id,
      poll_id: poll.id,
      series_type: series_type,
      series_id: series_id,
      filter_criteria: filter_criteria
    }

    OccurrencePlannings.create(attrs)
  end

  defp invite_friends(_event, [], _organizer), do: {:ok, %{successful_invitations: 0}}

  defp invite_friends(event, friend_ids, organizer) do
    # Convert friend IDs to suggestion structs format expected by process_guest_invitations
    # This matches the pattern used in public_event_show_live.ex send_invitations/5
    suggestion_structs =
      Enum.map(friend_ids, fn friend_id ->
        user = Repo.get!(Accounts.User, friend_id)

        %{
          user_id: user.id,
          name: user.name,
          email: user.email,
          username: Map.get(user, :username),
          avatar_url: Map.get(user, :avatar_url)
        }
      end)

    # Process invitations using the same function as quick mode and manager area
    # Using :invitation mode to send invitation emails to friends
    result =
      Events.process_guest_invitations(
        event,
        organizer,
        suggestion_structs: suggestion_structs,
        manual_emails: [],
        invitation_message: "",
        mode: :invitation
      )

    # Return success with the invitation results
    {:ok, result}
  end

  defp build_default_event_title("movie", _movie_id) do
    # In a real implementation, fetch movie title from database
    "Movie Night - Group Planning"
  end

  defp build_default_event_title(series_type, _series_id) do
    display_type =
      series_type
      |> String.replace("_", " ")
      |> String.capitalize()

    "#{display_type} - Group Planning"
  end

  @doc """
  Gets metadata about available occurrence options.

  Returns summary statistics about occurrences matching the filter.

  ## Parameters

  - `series_type` - Type of series
  - `series_id` - ID of the series entity
  - `filter_criteria` - Filter criteria map

  ## Returns

  - `{:ok, metadata}` - Map with :count, :date_range, :venues, etc.
  - `{:error, reason}` - If query fails
  """
  def get_occurrence_metadata(series_type, series_id, filter_criteria) do
    case preview_occurrences(series_type, series_id, filter_criteria) do
      {:ok, occurrences} ->
        metadata = %{
          count: length(occurrences),
          date_range: get_date_range(occurrences),
          venues: get_unique_venues(occurrences),
          time_distribution: get_time_distribution(occurrences)
        }

        {:ok, metadata}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_date_range([]), do: nil

  defp get_date_range(occurrences) do
    dates =
      occurrences
      |> Enum.map(& &1.starts_at)
      |> Enum.sort(DateTime)

    %{
      first: List.first(dates),
      last: List.last(dates)
    }
  end

  defp get_unique_venues(occurrences) do
    occurrences
    |> Enum.map(fn occ -> %{id: occ.venue_id, name: occ.venue_name} end)
    |> Enum.uniq_by(& &1.id)
  end

  defp get_time_distribution(occurrences) do
    occurrences
    |> Enum.group_by(fn occ ->
      hour = occ.starts_at.hour

      cond do
        hour < 12 -> "morning"
        hour < 17 -> "afternoon"
        hour < 22 -> "evening"
        true -> "late_night"
      end
    end)
    |> Enum.map(fn {period, occs} -> {period, length(occs)} end)
    |> Map.new()
  end
end
