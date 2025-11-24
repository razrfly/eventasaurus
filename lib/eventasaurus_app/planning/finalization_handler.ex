defmodule EventasaurusApp.Planning.FinalizationHandler do
  @moduledoc """
  Handles finalization of occurrence-based polls into event_plan records.

  When a poll with poll_type="occurrence_selection" is finalized, this handler:
  1. Extracts the winning poll option's occurrence metadata
  2. Creates a private event and event_plan using the occurrence details
  3. Updates the occurrence_planning record with the event_plan_id

  This bridges the gap between flexible polling (occurrence selection) and
  the final event planning (event_plan creation).

  ## Workflow

  ```
  Poll finalized → Get winning option → Extract occurrence metadata →
  Create event_plan from occurrence → Update occurrence_planning → Done
  ```

  ## Example

      iex> poll = %Poll{poll_type: "occurrence_selection", ...}
      iex> FinalizationHandler.handle_poll_finalization(poll, user_id)
      {:ok, %{
        event_plan: %EventPlan{...},
        private_event: %Event{...},
        occurrence_planning: %OccurrencePlanning{event_plan_id: 123}
      }}
  """

  require Logger

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventPlans
  alias EventasaurusApp.Events.Poll
  alias EventasaurusApp.Planning.{OccurrencePlanning, OccurrencePlannings}

  @doc """
  Handles finalization of an occurrence-selection poll.

  Called after a poll is finalized to convert the winning occurrence option
  into an event_plan.

  ## Parameters

  - `poll` - The finalized Poll struct (must be poll_type "occurrence_selection")
  - `user_id` - ID of the user finalizing the poll

  ## Returns

  - `{:ok, result}` - Map with :event_plan, :private_event, :occurrence_planning
  - `{:error, reason}` - If finalization fails

  ## Errors

  - `:not_occurrence_poll` - Poll is not type "occurrence_selection"
  - `:not_finalized` - Poll has not been finalized yet
  - `:no_occurrence_planning` - No occurrence_planning record found for poll
  - `:no_winning_option` - Poll has no winning option
  - `:missing_metadata` - Winning option missing occurrence metadata
  - Other errors from EventPlans.create_from_public_event/3
  """
  def handle_poll_finalization(%Poll{} = poll, user_id) do
    with :ok <- validate_poll_type(poll),
         :ok <- validate_poll_finalized(poll),
         {:ok, occurrence_planning} <- get_occurrence_planning(poll.id),
         {:ok, winning_option} <- get_winning_option(poll),
         {:ok, occurrence_metadata} <- extract_occurrence_metadata(winning_option),
         {:ok, result} <- create_event_plan_from_occurrence(occurrence_metadata, user_id),
         {:ok, updated_planning} <-
           link_occurrence_planning(occurrence_planning, result.event_plan.id) do
      {:ok, Map.put(result, :occurrence_planning, updated_planning)}
    else
      {:error, reason} = error ->
        Logger.warning(
          "Failed to finalize occurrence poll: poll_id=#{poll.id}, reason=#{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Creates an event_plan from occurrence metadata.

  This is a lower-level function that can be used independently of poll finalization.
  Handles both movie showtimes (with public_event_id) and venue time slots (synthetic).

  ## Parameters

  - `occurrence_metadata` - Map with occurrence details:
    - Movie: `:occurrence_type`, `:public_event_id`, `:starts_at`
    - Venue: `:occurrence_type`, `:venue_id`, `:starts_at`, `:ends_at`
  - `user_id` - ID of the user creating the plan

  ## Returns

  - `{:ok, %{event_plan: ..., private_event: ...}}` - Created records
  - `{:error, reason}` - If creation fails
  """
  def create_event_plan_from_occurrence(occurrence_metadata, user_id) do
    case occurrence_metadata.occurrence_type do
      "movie_showtime" ->
        create_movie_event_plan(occurrence_metadata, user_id)

      "venue_time_slot" ->
        create_venue_event_plan(occurrence_metadata, user_id)

      unknown_type ->
        {:error, "Unsupported occurrence type: #{unknown_type}"}
    end
  end

  defp create_movie_event_plan(occurrence_metadata, user_id) do
    public_event_id = occurrence_metadata.public_event_id
    starts_at_iso = occurrence_metadata.starts_at

    # Parse ISO8601 datetime
    {:ok, occurrence_datetime, _offset} = DateTime.from_iso8601(starts_at_iso)

    # Create event plan with occurrence datetime
    attrs = %{
      occurrence_datetime: occurrence_datetime
    }

    case EventPlans.create_from_public_event(public_event_id, user_id, attrs) do
      {:ok, {:created, event_plan, private_event}} ->
        {:ok, %{event_plan: event_plan, private_event: private_event}}

      {:ok, {:existing, event_plan, private_event}} ->
        # User already has a plan for this occurrence
        {:ok, %{event_plan: event_plan, private_event: private_event}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_venue_event_plan(occurrence_metadata, user_id) do
    # For venue time slots, create a private event directly
    # No public_event exists for synthetic time slots

    {:ok, starts_at, _offset} = DateTime.from_iso8601(occurrence_metadata.starts_at)
    {:ok, ends_at, _offset} = DateTime.from_iso8601(occurrence_metadata.ends_at)

    # Get venue details
    venue = EventasaurusApp.Repo.get!(EventasaurusApp.Venues.Venue, occurrence_metadata.venue_id)

    # Create private event for the venue time slot
    event_attrs = %{
      title: "#{venue.name} - #{String.capitalize(occurrence_metadata.meal_period || "visit")}",
      start_at: starts_at,
      end_at: ends_at,
      timezone: "UTC",
      visibility: :private,
      status: :confirmed,
      venue_id: venue.id
    }

    case EventasaurusApp.Events.create_event(event_attrs) do
      {:ok, private_event} ->
        # Create event_plan linking to this private event
        plan_attrs = %{
          private_event_id: private_event.id,
          user_id: user_id,
          occurrence_datetime: starts_at
        }

        case EventasaurusApp.Events.EventPlans.create_event_plan(plan_attrs) do
          {:ok, event_plan} ->
            {:ok, %{event_plan: event_plan, private_event: private_event}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private validation and extraction functions

  defp validate_poll_type(%Poll{poll_type: "occurrence_selection"}), do: :ok

  defp validate_poll_type(%Poll{poll_type: type}) do
    {:error, {:not_occurrence_poll, type}}
  end

  defp validate_poll_finalized(%Poll{finalized_date: nil}) do
    {:error, :not_finalized}
  end

  defp validate_poll_finalized(%Poll{finalized_date: _}), do: :ok

  defp get_occurrence_planning(poll_id) do
    case OccurrencePlannings.get_by_poll(poll_id) do
      %OccurrencePlanning{} = planning ->
        {:ok, planning}

      nil ->
        {:error, :no_occurrence_planning}
    end
  end

  defp get_winning_option(%Poll{} = poll) do
    # Get poll with options using Events.get_poll_with_options/1
    case Events.get_poll_with_options(poll.id) do
      %Poll{poll_options: options} ->
        # Preload votes for each option
        options_with_votes =
          Enum.map(options, fn option ->
            Events.get_poll_option!(option.id)
            |> EventasaurusApp.Repo.preload(:votes)
          end)

        # Find option with most votes
        winning_option =
          options_with_votes
          |> Enum.max_by(&length(&1.votes), fn -> nil end)

        case winning_option do
          nil ->
            {:error, :no_winning_option}

          option ->
            {:ok, option}
        end

      nil ->
        {:error, :poll_not_found}
    end
  end

  defp extract_occurrence_metadata(poll_option) do
    case poll_option.metadata do
      # Movie showtime with public_event_id
      %{
        "occurrence_type" => "movie_showtime",
        "public_event_id" => public_event_id,
        "starts_at" => starts_at
      } ->
        {:ok,
         %{
           occurrence_type: "movie_showtime",
           public_event_id: public_event_id,
           starts_at: starts_at,
           movie_id: Map.get(poll_option.metadata, "movie_id"),
           venue_id: Map.get(poll_option.metadata, "venue_id")
         }}

      # Venue time slot (synthetic occurrence)
      %{
        "occurrence_type" => "venue_time_slot",
        "venue_id" => venue_id,
        "starts_at" => starts_at,
        "ends_at" => ends_at
      } ->
        {:ok,
         %{
           occurrence_type: "venue_time_slot",
           venue_id: venue_id,
           starts_at: starts_at,
           ends_at: ends_at,
           meal_period: Map.get(poll_option.metadata, "meal_period"),
           date: Map.get(poll_option.metadata, "date")
         }}

      metadata ->
        Logger.warning(
          "Poll option missing occurrence metadata: option_id=#{poll_option.id}, metadata=#{inspect(metadata)}"
        )

        {:error, :missing_metadata}
    end
  end

  defp link_occurrence_planning(occurrence_planning, event_plan_id) do
    OccurrencePlannings.finalize(occurrence_planning, event_plan_id)
  end

  @doc """
  Checks if a poll should be handled by this finalization handler.

  ## Parameters

  - `poll` - Poll struct to check

  ## Returns

  - `true` - If poll is occurrence_selection type and has occurrence_planning
  - `false` - Otherwise
  """
  def handles_poll?(%Poll{poll_type: "occurrence_selection", id: poll_id}) do
    case OccurrencePlannings.get_by_poll(poll_id) do
      %OccurrencePlanning{} -> true
      nil -> false
    end
  end

  def handles_poll?(_poll), do: false

  @doc """
  Helper to check if an occurrence_planning has been finalized.

  ## Parameters

  - `occurrence_planning` - OccurrencePlanning struct

  ## Returns

  - `true` - If linked to an event_plan
  - `false` - If not yet finalized
  """
  def finalized?(%OccurrencePlanning{event_plan_id: nil}), do: false
  def finalized?(%OccurrencePlanning{event_plan_id: _}), do: true
end
