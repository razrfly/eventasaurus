defmodule EventasaurusApp.Events do
  @moduledoc """
  The Events context.
  """

  import Ecto.Query, warn: false
  import Ecto.Changeset, only: [add_error: 3]
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{Event, EventUser, EventParticipant}
  alias EventasaurusApp.EventStateMachine
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Themes
  alias EventasaurusApp.Venues.Venue

  # Generic polling system aliases
  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}

  # Event activity tracking
  alias EventasaurusApp.Events.EventActivity

  alias EventasaurusApp.GuestInvitations
  alias Eventasaurus.Jobs.EmailInvitationJob
  alias Eventasaurus.Jobs.DeadlineReminderNotificationJob
  alias EventasaurusWeb.Utils.TimeUtils
  require Logger

  # Private helper for applying soft delete filtering
  defp apply_soft_delete_filter(query, opts) do
    if Keyword.get(opts, :include_deleted, false) do
      query
    else
      from(e in query, where: is_nil(e.deleted_at))
    end
  end

  @doc """
  Returns the list of events, excluding soft-deleted ones by default.

  ## Options
    - include_deleted: if true, includes soft-deleted events (default: false)

  ## Examples

      iex> list_events()
      [%Event{}, ...]

      iex> list_events(include_deleted: true)
      [%Event{}, ...]

  """
  def list_events(opts \\ []) do
    query =
      from(e in Event,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that are currently active (not ended or canceled).
  Excludes soft-deleted events by default.
  """
  def list_active_events(opts \\ []) do
    query =
      from(e in Event,
        where: e.status != ^:canceled and (is_nil(e.ends_at) or e.ends_at > ^DateTime.utc_now()),
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that have active polls.
  Excludes soft-deleted events by default.
  """
  def list_polling_events(opts \\ []) do
    current_time = DateTime.utc_now()

    query =
      from(e in Event,
        where:
          e.status == :polling and
            not is_nil(e.polling_deadline) and
            e.polling_deadline > ^current_time,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that can sell tickets.
  Excludes soft-deleted events by default.
  """
  def list_ticketed_events(opts \\ []) do
    query =
      from(e in Event,
        where: e.status == :confirmed,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
    |> Enum.filter(& &1.can_sell_tickets?)
  end

  @doc """
  Returns the list of events that have ended.
  Excludes soft-deleted events by default unless include_deleted: true is passed.
  """
  def list_ended_events(opts \\ []) do
    current_time = DateTime.utc_now()

    query =
      from(e in Event,
        where: not is_nil(e.ends_at) and e.ends_at < ^current_time,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that are currently in threshold pre-sale mode.
  Excludes soft-deleted events by default.
  """
  def list_threshold_events(opts \\ []) do
    query =
      from(e in Event,
        where: e.status == :threshold,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events filtered by threshold type.

  ## Parameters
  - threshold_type: "attendee_count", "revenue", or "both"
  """
  def list_events_by_threshold_type(threshold_type, opts \\ [])
      when threshold_type in ["attendee_count", "revenue", "both"] do
    query =
      from(e in Event,
        where: e.threshold_type == ^threshold_type,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that have met their threshold requirements.
  Excludes soft-deleted events by default unless include_deleted: true is passed.
  """
  def list_threshold_met_events(opts \\ []) do
    list_threshold_events(opts)
    |> Enum.filter(&EventasaurusApp.EventStateMachine.threshold_met?/1)
  end

  @doc """
  Returns the list of events that have NOT yet met their threshold requirements.
  Excludes soft-deleted events by default unless include_deleted: true is passed.
  """
  def list_threshold_pending_events(opts \\ []) do
    list_threshold_events(opts)
    |> Enum.reject(&EventasaurusApp.EventStateMachine.threshold_met?/1)
  end

  @doc """
  Returns the list of events filtered by minimum revenue threshold.

  ## Parameters
  - min_revenue_cents: Minimum revenue threshold in cents
  """
  def list_events_by_min_revenue(min_revenue_cents, opts \\ [])
      when is_integer(min_revenue_cents) do
    query =
      from(e in Event,
        where:
          e.threshold_type in ["revenue", "both"] and
            not is_nil(e.threshold_revenue_cents) and
            e.threshold_revenue_cents >= ^min_revenue_cents,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events for a specific venue.

  ## Parameters
  - venue_id: The ID of the venue

  ## Examples

      iex> list_events_by_venue(123)
      [%Event{}, ...]
  """
  def list_events_by_venue(venue_id) when is_integer(venue_id) do
    from(e in Event,
      where: e.venue_id == ^venue_id,
      where: is_nil(e.deleted_at),
      order_by: [asc: e.start_at],
      preload: [:venue]
    )
    |> Repo.all()
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of public events with optional search.

  ## Options
    - search: Search term to filter by title or description
    - include_ended: if true, includes events that have ended (default: false)

  ## Examples

      iex> list_public_events()
      [%Event{}, ...]
      
      iex> list_public_events(search: "movie")
      [%Event{}, ...]
  """
  def list_public_events(opts \\ []) do
    search_term = Keyword.get(opts, :search, "")
    include_ended = Keyword.get(opts, :include_ended, false)
    current_time = DateTime.utc_now()

    query =
      from(e in Event,
        where: e.visibility == :public,
        order_by: [asc: e.start_at],
        preload: [:venue, :users]
      )

    # Apply soft delete filter using the helper
    query = apply_soft_delete_filter(query, opts)

    # Filter out ended and canceled events unless explicitly included
    # An event is considered active/upcoming if:
    # - It's not canceled, AND
    # - It has no end date and hasn't started yet, OR
    # - It has an end date that hasn't passed yet
    query =
      if include_ended do
        # Even when including ended events, exclude canceled ones
        from(e in query,
          where: e.status != ^:canceled
        )
      else
        from(e in query,
          where:
            e.status != ^:canceled and
              ((is_nil(e.ends_at) and e.start_at > ^current_time) or
                 (not is_nil(e.ends_at) and e.ends_at > ^current_time))
        )
      end

    # Apply search filter if provided
    query =
      if search_term != "" do
        search_pattern = "%#{search_term}%"

        from(e in query,
          where: ilike(e.title, ^search_pattern) or ilike(e.description, ^search_pattern)
        )
      else
        query
      end

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events filtered by minimum attendee count threshold.

  ## Parameters
  - min_attendee_count: Minimum attendee count threshold
  """
  def list_events_by_min_attendee_count(min_attendee_count, opts \\ [])
      when is_integer(min_attendee_count) do
    query =
      from(e in Event,
        where:
          e.threshold_type in ["attendee_count", "both"] and
            not is_nil(e.threshold_count) and
            e.threshold_count >= ^min_attendee_count,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events for a specific group with proper ordering.

  This function now uses the unified event fetching logic to ensure consistent
  ordering and filtering across the application.

  ## Parameters
  - group: The group to filter events by
  - user: The user viewing the events (for role/permission context)
  - opts: Options for filtering:
    - :time_filter - :all, :upcoming, :past (default: :all)
    - :limit - maximum number of results (default: 50)
    - :include_deleted - whether to include soft-deleted events (default: false)
  """
  def list_events_for_group(
        %EventasaurusApp.Groups.Group{id: group_id} = _group,
        %User{} = user,
        opts
      )
      when not is_nil(group_id) and is_list(opts) do
    # Use the unified function with group_id filter
    list_unified_events_for_user_optimized(
      user,
      Keyword.merge(opts,
        group_id: group_id,
        # Show all events in the group regardless of user's role
        ownership_filter: :all
      )
    )
  end

  # Header for list_events_for_group/2 with default parameter
  def list_events_for_group(group, opts_or_user \\ [])

  def list_events_for_group(%EventasaurusApp.Groups.Group{id: group_id} = group, %User{} = user)
      when not is_nil(group_id) do
    list_events_for_group(group, user, [])
  end

  @doc """
  Legacy version of list_events_for_group for backward compatibility.

  @deprecated Use list_events_for_group/3 with user parameter instead.
  """
  def list_events_for_group(%EventasaurusApp.Groups.Group{id: group_id} = _group, opts)
      when not is_nil(group_id) do
    query =
      from(e in Event,
        where: e.group_id == ^group_id,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    results =
      Repo.all(query)
      |> Enum.map(&Event.with_computed_fields/1)

    # Get event IDs for participant loading
    event_ids = results |> Enum.map(& &1.id) |> Enum.uniq()

    # Load participants for each event in a single query
    participants_by_event =
      if length(event_ids) > 0 do
        from(ep in EventParticipant,
          where: ep.event_id in ^event_ids and is_nil(ep.deleted_at),
          order_by: [asc: ep.event_id, desc: ep.inserted_at],
          preload: [:user]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.event_id)
      else
        %{}
      end

    # Add participant data to results
    results
    |> Enum.map(fn event ->
      participants = Map.get(participants_by_event, event.id, [])
      participant_count = length(participants)

      Map.merge(event, %{
        participants: participants,
        participant_count: participant_count
      })
    end)
  end

  @doc """
  Gets a single event.

  Raises `Ecto.NoResultsError` if the Event does not exist or is soft-deleted.
  """
  def get_event!(id) do
    query =
      from(e in Event,
        where: e.id == ^id and is_nil(e.deleted_at)
      )

    Repo.one!(query) |> Repo.preload([:venue, :users]) |> Event.with_computed_fields()
  end

  @doc """
  Gets a single event, excluding soft-deleted ones by default.

  ## Options
    - include_deleted: if true, includes soft-deleted events (default: false)

  Returns nil if the Event does not exist or is soft-deleted (unless include_deleted: true).
  """
  def get_event(id, opts \\ []) do
    query = from(e in Event, where: e.id == ^id)

    query = apply_soft_delete_filter(query, opts)

    Repo.one(query) |> maybe_preload()
  end

  defp maybe_preload(nil), do: nil

  defp maybe_preload(event),
    do: Repo.preload(event, [:venue, :users]) |> Event.with_computed_fields()

  @doc """
  Gets a single event by slug, excluding soft-deleted ones by default.

  ## Options
    - include_deleted: if true, includes soft-deleted events (default: false)

  Returns nil if the Event does not exist or is soft-deleted (unless include_deleted: true).
  """
  def get_event_by_slug(slug, opts \\ []) do
    query = from(e in Event, where: e.slug == ^slug)

    query = apply_soft_delete_filter(query, opts)

    Repo.one(query)
    |> maybe_preload()
  end

  @doc """
  Gets a single event by slug.

  Raises `Ecto.NoResultsError` if the Event does not exist.

  ## Examples

      iex> get_event_by_slug!("my-event")
      %Event{}

      iex> get_event_by_slug!("non-existent")
      ** (Ecto.NoResultsError)

  """
  def get_event_by_slug!(slug) do
    query =
      from(e in Event,
        where: e.slug == ^slug and is_nil(e.deleted_at)
      )

    Repo.one!(query)
    |> Repo.preload([:venue, :users])
  end

  @doc """
  Gets a single event by title.

  Returns `nil` if the Event does not exist or is soft-deleted.

  ## Examples

      iex> get_event_by_title("My Event")
      %Event{}

      iex> get_event_by_title("Non-existent")
      nil

  """
  def get_event_by_title(title, opts \\ []) do
    query =
      from(e in Event,
        where: e.title == ^title
      )

    query = apply_soft_delete_filter(query, opts)

    case Repo.one(query) do
      nil -> nil
      event -> Repo.preload(event, [:venue, :users])
    end
  end

  @doc """
  Creates an event with automatic status inference.

  The event status is automatically inferred based on the provided attributes
  using the EventStateMachine. If a status is explicitly provided in attrs,
  it will be validated for consistency with the inferred status.
  """
  def create_event(attrs \\ %{}) do
    # Use changeset with inferred status for automatic state management
    result =
      %Event{}
      |> Event.changeset_with_inferred_status(attrs)
      |> Repo.insert()

    case result do
      {:ok, event} ->
        event =
          event
          |> Repo.preload([:venue, :users])
          |> Event.with_computed_fields()

        # Sync existing participants if event is added to a group
        if event.group_id do
          Task.start(fn ->
            case EventasaurusApp.Groups.get_group(event.group_id) do
              nil ->
                Logger.warning(
                  "Failed to sync participants: Group #{event.group_id} not found for event #{event.id}"
                )

              group ->
                EventasaurusApp.Groups.sync_event_participants_to_group(group, event)
            end
          end)
        end

        # Schedule deadline reminder if event has a polling deadline
        maybe_schedule_deadline_reminder(event)

        {:ok, event}

      error ->
        error
    end
  end

  @doc """
  Updates an event with automatic status inference.

  Similar to create_event/1, the status is automatically inferred based on
  the updated attributes. Virtual computed fields are automatically populated
  in the returned event.
  """
  def update_event(%Event{} = event, attrs) do
    changeset = Event.changeset_with_inferred_status(event, attrs)
    result = Repo.update(changeset)

    case result do
      {:ok, updated_event} ->
        updated_event =
          updated_event
          |> Repo.preload([:venue, :users])
          |> Event.with_computed_fields()

        # Sync participants if event is newly added to a group
        if updated_event.group_id && event.group_id != updated_event.group_id do
          Task.start(fn ->
            case EventasaurusApp.Groups.get_group(updated_event.group_id) do
              nil ->
                Logger.warning(
                  "Failed to sync participants: Group #{updated_event.group_id} not found for event #{updated_event.id}"
                )

              group ->
                EventasaurusApp.Groups.sync_event_participants_to_group(group, updated_event)
            end
          end)
        end

        # Schedule deadline reminder if polling_deadline was added or changed,
        # or if the event newly transitions to :threshold status with a deadline
        if updated_event.polling_deadline != event.polling_deadline or
             (updated_event.status == :threshold and event.status != :threshold) do
          maybe_schedule_deadline_reminder(updated_event)
        end

        {:ok, updated_event}

      error ->
        error
    end
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Hard deletes an event if it meets eligibility criteria.
  Uses the HardDelete module to check eligibility and perform the deletion.
  """
  def hard_delete_event(event_id, user_id, opts \\ []) do
    EventasaurusApp.Events.HardDelete.hard_delete_event(event_id, user_id, opts)
  end

  @doc """
  Checks if an event is eligible for hard deletion.
  """
  def eligible_for_hard_delete?(event_id, user_id, opts \\ []) do
    EventasaurusApp.Events.HardDelete.eligible_for_hard_delete?(event_id, user_id, opts)
  end

  @doc """
  Gets a human-readable reason why an event cannot be hard deleted.
  """
  def get_hard_delete_ineligibility_reason(event_id, user_id, opts \\ []) do
    EventasaurusApp.Events.HardDelete.get_ineligibility_reason(event_id, user_id, opts)
  end

  @doc """
  Soft deletes an event and all its associated records.
  Uses the SoftDelete module to perform cascading soft deletion.
  """
  def soft_delete_event(event_id, reason, user_id) do
    EventasaurusApp.Events.SoftDelete.soft_delete_event(event_id, reason, user_id)
  end

  @doc """
  Checks if an event can be soft deleted.
  """
  def can_soft_delete?(event_id) do
    EventasaurusApp.Events.SoftDelete.can_soft_delete?(event_id)
  end

  @doc """
  Gets statistics about soft deletion for reporting purposes.
  """
  def get_deletion_stats(opts \\ []) do
    EventasaurusApp.Events.SoftDelete.get_deletion_stats(opts)
  end

  @doc """
  Unified deletion function that automatically determines whether to perform
  a hard or soft deletion based on event criteria.

  ## Parameters
    - event_id: ID of the event to delete
    - user_id: ID of the user performing the deletion
    - reason: String explaining why the event is being deleted
    
  ## Returns
    - {:ok, :hard_deleted} - Event was permanently deleted
    - {:ok, :soft_deleted} - Event was soft deleted
    - {:error, reason} - Deletion failed
  """
  def delete_event(event_id, user_id, reason) do
    EventasaurusApp.Events.Delete.delete_event(event_id, user_id, reason)
  end

  @doc """
  Determines the appropriate deletion method for an event.

  Returns :hard if the event is eligible for hard deletion, :soft otherwise.
  """
  def deletion_method(event, user) do
    EventasaurusApp.Events.Delete.deletion_method(event, user)
  end

  @doc """
  Returns a human-readable explanation of why an event would be soft deleted
  instead of hard deleted.
  """
  def soft_delete_reason(event, user) do
    EventasaurusApp.Events.Delete.soft_delete_reason(event, user)
  end

  # Event Restoration Functions

  @doc """
  Restores a soft-deleted event and all its associated records.

  ## Parameters
    - event_id: ID of the soft-deleted event to restore
    - user_id: ID of the user performing the restoration
    
  ## Returns
    - {:ok, event} - Event was successfully restored
    - {:error, reason} - Restoration failed
  """
  def restore_event(event_id, user_id) do
    EventasaurusApp.Events.Restore.restore_event(event_id, user_id)
  end

  @doc """
  Checks if an event is eligible for restoration.

  Returns {:ok, event} if eligible, {:error, reason} if not.
  """
  def eligible_for_restoration?(event_id) do
    EventasaurusApp.Events.Restore.eligible_for_restoration?(event_id)
  end

  @doc """
  Gets restoration statistics for reporting purposes.

  ## Options
    - days_back: Number of days to look back (default: 30)
  """
  def get_restoration_stats(opts \\ []) do
    EventasaurusApp.Events.Restore.get_restoration_stats(opts)
  end

  @doc """
  Counts the number of confirmed orders for an event.
  """
  def count_orders_for_event(event_id) do
    alias EventasaurusApp.Events.Order

    Repo.aggregate(
      from(o in Order,
        where:
          o.event_id == ^event_id and o.status in ["confirmed", "pending"] and
            is_nil(o.deleted_at)
      ),
      :count,
      :id
    )
  end

  @doc """
  Counts the total number of sold tickets for an event across all ticket types.
  """
  def count_sold_tickets_for_event(event_id) do
    alias EventasaurusApp.Events.Ticket
    alias EventasaurusApp.Ticketing

    # Get all ticket IDs for this event (excluding soft-deleted)
    ticket_ids =
      Repo.all(
        from(t in Ticket,
          where: t.event_id == ^event_id and is_nil(t.deleted_at),
          select: t.id
        )
      )

    # Sum up sold tickets across all ticket types
    Enum.reduce(ticket_ids, 0, fn ticket_id, acc ->
      acc + Ticketing.count_sold_tickets(ticket_id)
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.
  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  @doc """
  Manually transition an event to a new status.

  This function bypasses automatic status inference and directly sets
  the event to the specified status. Use with caution - prefer update_event/2
  for normal operations as it includes proper validation.

  ## Examples

      iex> transition_event(event, :canceled)
      {:ok, %Event{status: :canceled}}

      iex> transition_event(event, :invalid_status)
      {:error, "invalid transition from 'draft' to 'invalid_status'"}
  """
  def transition_event(%Event{} = event, new_status) do
    Repo.transaction(fn ->
      # Use Machinery for state transitions instead of manual transition_to function
      case update_event(event, %{status: new_status}) do
        {:ok, updated_event} ->
          Event.with_computed_fields(updated_event)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Get the current inferred status for an event without updating it.

  Useful for checking what status an event should have based on its
  current attributes without performing a database update.
  """
  def get_inferred_status(%Event{} = event) do
    EventStateMachine.infer_status(event)
  end

  @doc """
  Auto-correct an event's status based on its current attributes.

  This function checks if the event's stored status matches what it should be
  based on its attributes, and updates it if necessary.
  """
  def auto_correct_event_status(%Event{} = event) do
    inferred_status = EventStateMachine.infer_status(event)

    if event.status == inferred_status do
      {:ok, Event.with_computed_fields(event)}
    else
      # Use changeset approach to bypass transition rules for auto-correction
      # Auto-correction is for fixing data integrity, not normal business logic
      corrected_attrs = %{status: inferred_status}

      # Add required fields based on inferred status
      corrected_attrs =
        case inferred_status do
          :canceled -> Map.put(corrected_attrs, :canceled_at, DateTime.utc_now())
          # Clear canceled_at when moving away from canceled
          _ -> Map.delete(corrected_attrs, :canceled_at)
        end

      case event
           |> Event.changeset(corrected_attrs)
           |> Repo.update() do
        {:ok, updated_event} ->
          {:ok, Event.with_computed_fields(updated_event)}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Returns the list of events by a specific user.
  """
  @spec list_events_by_user(%User{}, keyword()) :: [%Event{}]
  def list_events_by_user(%User{} = user, opts \\ []) do
    query =
      from(e in Event,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        where: eu.user_id == ^user.id,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    query =
      case opts[:limit] do
        limit when is_integer(limit) and limit > 0 -> from(q in query, limit: ^limit)
        limit when is_integer(limit) -> from(q in query, limit: 0)
        _ -> query
      end

    Repo.all(query)
  end

  @doc """
  Returns the list of soft-deleted events where the user is an organizer.
  Only returns events deleted within the last 90 days that can be restored.
  """
  def list_deleted_events_by_user(%User{} = user) do
    ninety_days_ago = DateTime.utc_now() |> DateTime.add(-90, :day)

    query =
      from(e in Event,
        join: eu in EventasaurusApp.Events.EventUser,
        on: e.id == eu.event_id,
        where:
          eu.user_id == ^user.id and
            not is_nil(e.deleted_at) and
            e.deleted_at > ^ninety_days_ago,
        preload: [:users, :venue, :tickets],
        order_by: [desc: e.deleted_at]
      )

    Repo.all(query)
  end

  @doc """
  Adds a user as an organizer to an event.
  """
  def add_user_to_event(%Event{} = event, %User{} = user, role \\ nil) do
    %EventUser{}
    |> EventUser.changeset(%{
      event_id: event.id,
      user_id: user.id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Removes a user as an organizer from an event.
  """
  def remove_user_from_event(%Event{} = event, %User{} = user) do
    from(eu in EventUser, where: eu.event_id == ^event.id and eu.user_id == ^user.id)
    |> Repo.delete_all()
  end

  @doc """
  Adds multiple users as organizers to an event.
  Returns the count of successfully added organizers.
  """
  def add_organizers_to_event(%Event{} = event, user_ids) when is_list(user_ids) do
    # Get existing organizer user IDs for this event
    existing_organizer_ids =
      from(eu in EventUser,
        where: eu.event_id == ^event.id,
        select: eu.user_id
      )
      |> Repo.all()

    # Filter out user IDs that are already organizers and deduplicate
    new_user_ids =
      user_ids
      |> Enum.uniq()
      |> Kernel.--(existing_organizer_ids)

    # Prepare organizer records for bulk insert
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    organizer_records =
      Enum.map(new_user_ids, fn user_id ->
        %{
          event_id: event.id,
          user_id: user_id,
          role: nil,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end)

    case organizer_records do
      # No new organizers to add
      [] ->
        0

      records ->
        # Use insert_all with conflict handling for better performance and safety
        {count, _} =
          Repo.insert_all(
            EventUser,
            records,
            on_conflict: :nothing,
            conflict_target: [:event_id, :user_id]
          )

        count
    end
  end

  @doc """
  Lists all organizers of an event.
  """
  def list_event_organizers(%Event{} = event) do
    query =
      from(u in User,
        join: eu in EventUser,
        on: u.id == eu.user_id,
        where:
          eu.event_id == ^event.id and
            eu.role == "organizer" and
            is_nil(eu.deleted_at)
      )

    Repo.all(query)
  end

  @doc """
  Checks if a user is an organizer of an event.
  """
  def user_is_organizer?(%Event{} = event, %User{} = user) do
    query =
      from(eu in EventUser,
        where: eu.event_id == ^event.id and eu.user_id == ^user.id,
        select: count(eu.id)
      )

    Repo.one(query) > 0
  end

  @doc """
  Checks if a user can manage an event (i.e., is an organizer).

  This is an alias for user_is_organizer?/2 but provides clearer intent
  for authorization checks in controllers and LiveViews.
  """
  def user_can_manage_event?(%User{} = user, %Event{} = event) do
    user_is_organizer?(event, user)
  end

  @doc """
  Creates an event and associates it with a user in a single transaction.

  The event status is automatically inferred and virtual computed fields
  are populated in the returned event.
  """
  def create_event_with_organizer(event_attrs, %User{} = user) do
    Repo.transaction(fn ->
      with {:ok, event} <- create_event(event_attrs),
           {:ok, _} <- add_user_to_event(event, user, "organizer") do
        event
        |> Repo.preload([:venue, :users])
        |> Event.with_computed_fields()
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Event Participant Functions

  @doc """
  Returns the list of event participants.
  """
  def list_event_participants do
    Repo.all(EventParticipant)
  end

  @doc """
  Gets a single event participant.

  Raises `Ecto.NoResultsError` if the EventParticipant does not exist.
  """
  def get_event_participant!(id), do: Repo.get!(EventParticipant, id)

  @doc """
  Creates an event participant.
  """
  def create_event_participant(attrs \\ %{}) do
    result =
      %EventParticipant{}
      |> EventParticipant.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, participant} ->
        # Sync participant to group if event belongs to a group
        event_id = Map.get(attrs, :event_id) || Map.get(attrs, "event_id")
        user_id = Map.get(attrs, :user_id) || Map.get(attrs, "user_id")

        if event_id && user_id do
          Task.start(fn ->
            case get_event(event_id) do
              nil ->
                Logger.warning("Failed to sync participant to group: Event #{event_id} not found")

              event ->
                if event.group_id do
                  case {EventasaurusApp.Groups.get_group(event.group_id),
                        EventasaurusApp.Accounts.get_user(user_id)} do
                    {nil, _} ->
                      Logger.warning(
                        "Failed to sync participant to group: Group #{event.group_id} not found"
                      )

                    {_, nil} ->
                      Logger.warning(
                        "Failed to sync participant to group: User #{user_id} not found"
                      )

                    {group, user} ->
                      EventasaurusApp.Groups.add_user_to_group(group, user, "member")
                  end
                end
            end
          end)
        end

        {:ok, participant}

      error ->
        error
    end
  end

  @doc """
  Creates or updates an event participant for ticket purchase.

  This function implements the design pattern where:
  1. If participant doesn't exist, create with confirmed_with_order status
  2. If participant exists, upgrade their status to confirmed_with_order
  3. Avoids duplicate participant records
  4. Uses atomic upsert to prevent race conditions
  """
  def create_or_upgrade_participant_for_order(%{event_id: event_id, user_id: user_id} = attrs) do
    # For upsert, we need to handle metadata merging at the database level
    # Since PostgreSQL doesn't have easy metadata merging in upsert, we'll use a transaction
    result =
      Repo.transaction(fn ->
        # Check for active (non-deleted) participant only
        existing_query =
          from(ep in EventParticipant,
            where: ep.event_id == ^event_id and ep.user_id == ^user_id and is_nil(ep.deleted_at),
            limit: 1
          )

        case Repo.one(existing_query) do
          nil ->
            # No existing participant, create new one
            participant_attrs =
              Map.merge(attrs, %{
                status: :confirmed_with_order,
                role: :ticket_holder
              })

            case %EventParticipant{}
                 |> EventParticipant.changeset(participant_attrs)
                 |> Repo.insert() do
              {:ok, participant} -> participant
              {:error, changeset} -> Repo.rollback(changeset)
            end

          existing_participant ->
            # Participant exists, upgrade their status and merge metadata
            new_metadata = Map.get(attrs, :metadata, %{})
            merged_metadata = Map.merge(existing_participant.metadata || %{}, new_metadata)

            upgrade_attrs = %{
              status: :confirmed_with_order,
              role: :ticket_holder,
              metadata: merged_metadata
            }

            case existing_participant
                 |> EventParticipant.changeset(upgrade_attrs)
                 |> Repo.update() do
              {:ok, participant} -> participant
              {:error, changeset} -> Repo.rollback(changeset)
            end
        end
      end)

    # After successful transaction, sync to group if needed
    case result do
      {:ok, _participant} ->
        Task.start(fn ->
          case get_event(event_id) do
            nil ->
              Logger.warning("Failed to sync participant to group: Event #{event_id} not found")

            event ->
              if event.group_id do
                case {EventasaurusApp.Groups.get_group(event.group_id),
                      EventasaurusApp.Accounts.get_user(user_id)} do
                  {nil, _} ->
                    Logger.warning(
                      "Failed to sync participant to group: Group #{event.group_id} not found"
                    )

                  {_, nil} ->
                    Logger.warning(
                      "Failed to sync participant to group: User #{user_id} not found"
                    )

                  {group, user} ->
                    EventasaurusApp.Groups.add_user_to_group(group, user, "member")
                end
              end
          end
        end)

        result

      error ->
        error
    end
  end

  @doc """
  Updates an event participant.
  """
  def update_event_participant(%EventParticipant{} = event_participant, attrs) do
    event_participant
    |> EventParticipant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a participant's status with admin permission checking.
  Only event organizers can change participant status.
  """
  def admin_update_participant_status(
        %EventParticipant{} = participant,
        new_status,
        %User{} = admin_user
      ) do
    # Load the event with preloaded organizers to check permissions
    event = get_event!(participant.event_id)

    # Check if the admin user is an organizer of this event
    if user_is_organizer?(event, admin_user) do
      update_event_participant(participant, %{status: new_status})
    else
      {:error, :permission_denied}
    end
  end

  @doc """
  Deletes an event participant.
  """
  def delete_event_participant(%EventParticipant{} = event_participant) do
    Repo.delete(event_participant)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event participant changes.
  """
  def change_event_participant(%EventParticipant{} = event_participant, attrs \\ %{}) do
    EventParticipant.changeset(event_participant, attrs)
  end

  @doc """
  Lists all participants for an event.
  """
  def list_event_participants_for_event(%Event{} = event) do
    query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id and is_nil(ep.deleted_at),
        preload: [:user, :invited_by_user]
      )

    Repo.all(query)
  end

  @doc """
  Lists all participants for an event (alias for list_event_participants_for_event/1).
  """
  def list_event_participants(%Event{} = event) do
    list_event_participants_for_event(event)
  end

  @doc """
  Lists all events a user is participating in.
  """
  def list_events_with_participation(%User{} = user, opts \\ []) do
    query =
      from(e in Event,
        join: ep in EventParticipant,
        on: e.id == ep.event_id,
        where: ep.user_id == ^user.id,
        preload: [:venue, :users]
      )

    query = apply_soft_delete_filter(query, opts)

    query =
      if opts[:upcoming] do
        now = DateTime.utc_now()

        from(e in query,
          where:
            (not is_nil(e.ends_at) and e.ends_at > ^now) or
              (is_nil(e.ends_at) and (is_nil(e.start_at) or e.start_at > ^now))
        )
      else
        query
      end

    query =
      if opts[:order_by] do
        from(e in query, order_by: ^opts[:order_by])
      else
        query
      end

    query =
      if opts[:limit] do
        from(e in query, limit: ^opts[:limit])
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Returns a unified list of events for a user, combining events they created
  and events they participate in, with role and participation information.
  """
  def list_unified_events_for_user(%User{} = user, opts \\ []) do
    time_filter = Keyword.get(opts, :time_filter, :all)
    ownership_filter = Keyword.get(opts, :ownership_filter, :all)
    limit = Keyword.get(opts, :limit, 50)

    # Base queries for organizer and participant events
    organizer_query =
      from(e in Event,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        where: eu.user_id == ^user.id,
        select: %{
          id: e.id,
          title: e.title,
          slug: e.slug,
          description: e.description,
          start_at: e.start_at,
          ends_at: e.ends_at,
          timezone: e.timezone,
          status: e.status,
          taxation_type: e.taxation_type,
          venue_id: e.venue_id,
          group_id: e.group_id,
          cover_image_url: e.cover_image_url,
          inserted_at: e.inserted_at,
          updated_at: e.updated_at,
          user_role: fragment("'organizer'"),
          user_status: fragment("'confirmed'"),
          can_manage: fragment("true")
        }
      )

    participant_query =
      from(e in Event,
        join: ep in EventParticipant,
        on: e.id == ep.event_id,
        where: ep.user_id == ^user.id,
        select: %{
          id: e.id,
          title: e.title,
          slug: e.slug,
          description: e.description,
          start_at: e.start_at,
          ends_at: e.ends_at,
          timezone: e.timezone,
          status: e.status,
          taxation_type: e.taxation_type,
          venue_id: e.venue_id,
          group_id: e.group_id,
          cover_image_url: e.cover_image_url,
          inserted_at: e.inserted_at,
          updated_at: e.updated_at,
          user_role: fragment("'participant'"),
          user_status: ep.status,
          can_manage: fragment("false")
        }
      )

    # Apply ownership filter
    {organizer_query, participant_query} =
      case ownership_filter do
        :created ->
          # Return empty participant query but with same structure
          empty_participant_query =
            from(e in Event,
              join: ep in EventParticipant,
              on: e.id == ep.event_id,
              where: false,
              select: %{
                id: e.id,
                title: e.title,
                slug: e.slug,
                description: e.description,
                start_at: e.start_at,
                ends_at: e.ends_at,
                timezone: e.timezone,
                status: e.status,
                taxation_type: e.taxation_type,
                venue_id: e.venue_id,
                group_id: e.group_id,
                cover_image_url: e.cover_image_url,
                inserted_at: e.inserted_at,
                updated_at: e.updated_at,
                user_role: fragment("'participant'"),
                user_status: ep.status,
                can_manage: fragment("false")
              }
            )

          {organizer_query, empty_participant_query}

        :participating ->
          # Return empty organizer query but with same structure
          empty_organizer_query =
            from(e in Event,
              join: eu in EventUser,
              on: e.id == eu.event_id,
              where: false,
              select: %{
                id: e.id,
                title: e.title,
                slug: e.slug,
                description: e.description,
                start_at: e.start_at,
                ends_at: e.ends_at,
                timezone: e.timezone,
                status: e.status,
                taxation_type: e.taxation_type,
                venue_id: e.venue_id,
                group_id: e.group_id,
                cover_image_url: e.cover_image_url,
                inserted_at: e.inserted_at,
                updated_at: e.updated_at,
                user_role: fragment("'organizer'"),
                user_status: fragment("'confirmed'"),
                can_manage: fragment("true")
              }
            )

          {empty_organizer_query, participant_query}

        :all ->
          {organizer_query, participant_query}
      end

    # Apply soft delete filter to both queries - exclude deleted events for unified view
    organizer_query = from(e in organizer_query, where: is_nil(e.deleted_at))
    participant_query = from(e in participant_query, where: is_nil(e.deleted_at))

    # Union the queries
    union_query = union_all(organizer_query, ^participant_query)

    # Apply time filter to union query before finalizing
    time_filtered_query =
      case time_filter do
        :upcoming ->
          now = DateTime.utc_now()

          from(e in subquery(union_query),
            where: is_nil(e.start_at) or e.start_at > ^now,
            order_by: [asc: coalesce(e.start_at, e.inserted_at)],
            limit: ^limit
          )

        :past ->
          now = DateTime.utc_now()

          from(e in subquery(union_query),
            where: not is_nil(e.start_at) and e.start_at <= ^now,
            order_by: [desc: coalesce(e.start_at, e.inserted_at)],
            limit: ^limit
          )

        :archived ->
          # Archived events are handled separately in the LiveView
          from(e in subquery(union_query),
            where: false,
            order_by: [desc: coalesce(e.start_at, e.inserted_at)],
            limit: ^limit
          )

        :all ->
          from(e in subquery(union_query),
            order_by: [desc: coalesce(e.start_at, e.inserted_at)],
            limit: ^limit
          )
      end

    # Use with_deleted option to bypass automatic soft delete filtering from Ecto.SoftDelete.Repo
    events = Repo.all(time_filtered_query, with_deleted: true)

    # Preload associations and add computed fields
    event_ids = Enum.map(events, & &1.id)
    venues = get_venues_for_events(event_ids)
    participants = get_participants_for_events(event_ids)

    # Load groups
    group_ids =
      events
      |> Enum.map(& &1.group_id)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    groups =
      if length(group_ids) > 0 do
        from(g in EventasaurusApp.Groups.Group,
          where: g.id in ^group_ids,
          select: %{id: g.id, name: g.name, slug: g.slug}
        )
        |> Repo.all()
      else
        []
      end

    events
    |> Enum.map(fn event ->
      venue = Enum.find(venues, &(&1.id == event.venue_id))
      event_participants = Enum.filter(participants, &(&1.event_id == event.id))
      group = if event.group_id, do: Enum.find(groups, &(&1.id == event.group_id)), else: nil

      event
      |> Map.put(:venue, venue)
      |> Map.put(:participants, event_participants)
      |> Map.put(:participant_count, length(event_participants))
      |> Map.put(:group, group)
    end)
  end

  @doc """
  Optimized version of list_unified_events_for_user that uses a single query with LEFT JOINs
  instead of UNION to improve performance. This reduces database round trips from 3+ to 1.

  Options:
    - :time_filter - :all, :upcoming, :past, :archived (default: :all)
    - :ownership_filter - :all, :created, :participating (default: :all)
    - :limit - maximum number of results (default: 50)
    - :group_id - filter by group_id (optional)
  """
  def list_unified_events_for_user_optimized(%User{} = user, opts \\ []) do
    time_filter = Keyword.get(opts, :time_filter, :all)
    ownership_filter = Keyword.get(opts, :ownership_filter, :all)
    limit = Keyword.get(opts, :limit, 50)
    group_id = Keyword.get(opts, :group_id, nil)
    now = DateTime.utc_now()

    # Build the base query with LEFT JOINs
    base_query =
      from(e in Event,
        left_join: eu in EventUser,
        on: e.id == eu.event_id and eu.user_id == ^user.id,
        left_join: ep in EventParticipant,
        on: e.id == ep.event_id and ep.user_id == ^user.id,
        left_join: v in assoc(e, :venue),
        left_join: c in assoc(v, :city_ref),
        left_join: country in assoc(c, :country),
        where: is_nil(e.deleted_at),
        where: not is_nil(eu.id) or not is_nil(ep.id),
        select: %{
          # Event fields
          id: e.id,
          title: e.title,
          slug: e.slug,
          description: e.description,
          start_at: e.start_at,
          ends_at: e.ends_at,
          timezone: e.timezone,
          status: e.status,
          taxation_type: e.taxation_type,
          is_virtual: e.is_virtual,
          venue_id: e.venue_id,
          group_id: e.group_id,
          cover_image_url: e.cover_image_url,
          inserted_at: e.inserted_at,
          updated_at: e.updated_at,
          deleted_at: e.deleted_at,

          # User relationship fields
          user_role:
            fragment("CASE WHEN ? IS NOT NULL THEN 'organizer' ELSE 'participant' END", eu.id),
          user_status: fragment("COALESCE(?, 'confirmed')", ep.status),
          can_manage: fragment("? IS NOT NULL", eu.id),

          # Participant count calculated in DB
          participant_count:
            fragment(
              "(SELECT COUNT(*) FROM event_participants WHERE event_id = ? AND deleted_at IS NULL)",
              e.id
            ),

          # Poll count calculated in DB
          poll_count:
            fragment(
              "(SELECT COUNT(*) FROM polls WHERE event_id = ? AND deleted_at IS NULL)",
              e.id
            ),

          # Venue fields (flattened)
          venue: %{
            id: v.id,
            name: v.name,
            address: v.address,
            city: c.name,
            state: nil,
            country: country.name,
            latitude: v.latitude,
            longitude: v.longitude,
            venue_type: v.venue_type
          }
        }
      )

    # Apply group filter if provided
    base_with_group =
      if group_id do
        from([e, eu, ep, v, c, country] in base_query,
          where: e.group_id == ^group_id
        )
      else
        base_query
      end

    # Apply ownership filter
    filtered_query =
      case ownership_filter do
        :created ->
          from([e, eu, ep, v, c, country] in base_with_group,
            where: not is_nil(eu.id)
          )

        :participating ->
          from([e, eu, ep, v, c, country] in base_with_group,
            where: not is_nil(ep.id)
          )

        :all ->
          base_with_group
      end

    # Apply time filter
    time_filtered_query =
      case time_filter do
        :upcoming ->
          from([e, eu, ep, v, c, country] in filtered_query,
            where: is_nil(e.start_at) or e.start_at > ^now
          )

        :past ->
          from([e, eu, ep, v, c, country] in filtered_query,
            where: not is_nil(e.start_at) and e.start_at <= ^now
          )

        :archived ->
          # Archived events are handled separately in the LiveView
          from([e, eu, ep, v, c, country] in filtered_query,
            where: false
          )

        :all ->
          filtered_query
      end

    # Apply ordering and limit
    # For upcoming events: ascending (soonest first)
    # For past events: descending (most recent first)
    # For all: descending (most recent first)
    final_query =
      case time_filter do
        :upcoming ->
          from([e, eu, ep, v, c, country] in time_filtered_query,
            order_by: [asc: coalesce(e.start_at, e.inserted_at)],
            limit: ^limit
          )

        _ ->
          from([e, eu, ep, v, c, country] in time_filtered_query,
            order_by: [desc: coalesce(e.start_at, e.inserted_at)],
            limit: ^limit
          )
      end

    # Execute the single query
    results = Repo.all(final_query, with_deleted: true)

    # Get event IDs for participant loading
    event_ids = results |> Enum.map(& &1.id) |> Enum.uniq()

    # Load first 4 participants for each event in a single query
    participants_by_event =
      if length(event_ids) > 0 do
        from(ep in EventParticipant,
          where: ep.event_id in ^event_ids and is_nil(ep.deleted_at),
          order_by: [asc: ep.event_id, desc: ep.inserted_at],
          preload: [:user]
        )
        |> Repo.all()
        |> Enum.group_by(& &1.event_id)
        |> Enum.map(fn {event_id, participants} ->
          # Take only first 4 participants per event for avatar display
          {event_id, Enum.take(participants, 4)}
        end)
        |> Enum.into(%{})
      else
        %{}
      end

    # Load groups for events that have them
    groups_by_id =
      if length(event_ids) > 0 do
        group_ids =
          results
          |> Enum.map(& &1.group_id)
          |> Enum.filter(& &1)
          |> Enum.uniq()

        if length(group_ids) > 0 do
          from(g in EventasaurusApp.Groups.Group,
            where: g.id in ^group_ids,
            select: %{id: g.id, name: g.name, slug: g.slug}
          )
          |> Repo.all()
          |> Enum.map(fn group -> {group.id, group} end)
          |> Enum.into(%{})
        else
          %{}
        end
      else
        %{}
      end

    # Transform results to match expected format
    results
    |> Enum.map(fn result ->
      # Get participants for this event (first 4 only)
      event_participants = Map.get(participants_by_event, result.id, [])

      # Get group if event has one
      group =
        if result.group_id do
          Map.get(groups_by_id, result.group_id)
        else
          nil
        end

      result
      |> Map.put(:participants, event_participants)
      # Keep the participant_count from DB query, don't override it
      |> Map.put(:venue, if(result.venue.id, do: result.venue, else: nil))
      |> Map.put(:group, group)
    end)
  end

  @doc """
  Efficiently calculates all filter counts in a single query to avoid multiple database hits.

  Returns a map with counts for:
  - upcoming: count of upcoming events
  - past: count of past events  
  - archived: count of archived events
  - created: count of events where user is organizer
  - participating: count of events where user is participant

  This replaces 5 separate count queries with 1 optimized query.
  """
  def get_dashboard_filter_counts(%User{} = user) do
    now = DateTime.utc_now()
    # 90 days ago
    archived_cutoff = DateTime.add(now, -90, :day)

    # Single query to get all counts using conditional aggregation
    result =
      Repo.one(
        from(e in Event,
          left_join: eu in EventUser,
          on: e.id == eu.event_id and eu.user_id == ^user.id,
          left_join: ep in EventParticipant,
          on: e.id == ep.event_id and ep.user_id == ^user.id,
          where: is_nil(e.deleted_at) and (not is_nil(eu.id) or not is_nil(ep.id)),
          select: %{
            # Time-based counts for active events
            upcoming:
              fragment(
                "COUNT(CASE WHEN ? IS NULL OR ? > ? THEN 1 END)",
                e.start_at,
                e.start_at,
                ^now
              ),
            past:
              fragment(
                "COUNT(CASE WHEN ? IS NOT NULL AND ? <= ? THEN 1 END)",
                e.start_at,
                e.start_at,
                ^now
              ),

            # Role-based counts (all active events)
            created: fragment("COUNT(CASE WHEN ? IS NOT NULL THEN 1 END)", eu.id),
            participating:
              fragment("COUNT(CASE WHEN ? IS NOT NULL AND ? IS NULL THEN 1 END)", ep.id, eu.id)
          }
        )
      )

    # Get archived count separately since it's from a different table condition
    archived_count =
      Repo.one(
        from(e in Event,
          inner_join: eu in EventUser,
          on: e.id == eu.event_id,
          where:
            eu.user_id == ^user.id and
              not is_nil(e.deleted_at) and
              e.deleted_at > ^archived_cutoff,
          select: count(e.id)
        )
      )

    Map.put(result, :archived, archived_count)
  end

  # Helper functions for preloading
  defp get_venues_for_events([]), do: []

  defp get_venues_for_events(event_ids) do
    from(v in Venue,
      where: v.id in subquery(from(e in Event, where: e.id in ^event_ids, select: e.venue_id))
    )
    |> Repo.all()
  end

  defp get_participants_for_events([]), do: []

  defp get_participants_for_events(event_ids) do
    from(ep in EventParticipant,
      where: ep.event_id in ^event_ids and is_nil(ep.deleted_at),
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Get an event participant by event and user.
  """
  def get_event_participant_by_event_and_user(%Event{} = event, %User{} = user) do
    from(ep in EventParticipant,
      where: ep.event_id == ^event.id and ep.user_id == ^user.id and is_nil(ep.deleted_at),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Checks if a user is a participant in an event.
  """
  def user_is_participant?(%Event{} = event, %User{} = user) do
    case get_event_participant_by_event_and_user(event, user) do
      nil -> false
      _participant -> true
    end
  end

  # Event Registration Functions

  @doc """
  Registers a user for an event with just name and email.

  This function handles the low-friction registration flow:
  1. Checks if user exists in Supabase Auth (by email)
  2. Creates user if they don't exist (with temporary password)
  3. Checks if user is already registered for event
  4. Creates EventParticipant record if not already registered

  Returns:
  - {:ok, :new_registration, participant} - User was created and registered
  - {:ok, :existing_user_registered, participant} - Existing user was registered  
  - {:error, :already_registered} - User already registered for event
  - {:error, reason} - Other errors
  """
  def register_user_for_event(event_id, name, email) do
    alias EventasaurusApp.Services.UserRegistrationService

    # Validate event exists first
    case get_event(event_id) do
      nil ->
        Logger.error("Event not found", %{event_id: event_id})
        {:error, :event_not_found}

      _event ->
        # Delegate to the unified registration service
        case UserRegistrationService.register_user(email, name, :event_registration,
               event_id: event_id
             ) do
          {:ok, %{registration_type: :already_registered, participant: participant}} ->
            # Return the format that callers expect for existing users
            {:ok, :existing_user_registered, participant}

          {:ok, %{registration_type: registration_type, participant: participant}} ->
            # Map to the original return format for backward compatibility
            {:ok, registration_type, participant}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Register a user for voting.

  This function handles user registration when voting on a poll,
  ensuring the user is created and their votes are saved.

  ## Parameters

  - poll_id: ID of the poll being voted on
  - name: User's name
  - email: User's email address
  - votes: Map of votes to save
  - opts: Additional options (event_id, poll_options, etc.)

  ## Returns

  - {:ok, result} - User registered and votes saved
  - {:error, reason} - Registration or vote saving failed
  """
  def register_voter(poll_id, name, email, votes, opts \\ []) do
    alias EventasaurusApp.Services.UserRegistrationService

    # Add poll_id and votes to options
    registration_opts =
      Keyword.merge(opts,
        poll_id: poll_id,
        votes: votes
      )

    # Delegate to the unified registration service
    UserRegistrationService.register_user(email, name, :voting, registration_opts)
  end

  @doc """
  Get registration status for a user and event.
  Returns one of: :not_registered, :registered, :cancelled, :organizer
  """
  def get_user_registration_status(%Event{} = event, user) do
    case user do
      %User{} = user ->
        # First check if user is an organizer/admin
        if user_is_organizer?(event, user) do
          :organizer
        else
          # Check participant status
          case get_event_participant_by_event_and_user(event, user) do
            nil -> :not_registered
            %{status: :cancelled} -> :cancelled
            %{status: _} -> :registered
          end
        end

      _ ->
        :not_registered
    end
  end

  @doc """
  Cancel a user's registration for an event.
  """
  def cancel_user_registration(%Event{} = event, %User{} = user) do
    case get_event_participant_by_event_and_user(event, user) do
      nil ->
        {:error, :not_registered}

      participant ->
        updated_metadata = Map.put(participant.metadata || %{}, :cancelled_at, DateTime.utc_now())
        update_event_participant(participant, %{status: :cancelled, metadata: updated_metadata})
    end
  end

  @doc """
  Re-register a user for an event (for previously cancelled registrations).
  """
  def reregister_user_for_event(%Event{} = event, %User{} = user) do
    case get_event_participant_by_event_and_user(event, user) do
      nil ->
        # Create new registration
        create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          role: :invitee,
          status: :pending,
          source: "re_registration",
          metadata: %{registration_date: DateTime.utc_now()}
        })

      %{status: :cancelled} = participant ->
        # Reactivate cancelled registration
        update_event_participant(participant, %{
          status: :pending,
          metadata: Map.put(participant.metadata || %{}, :reregistered_at, DateTime.utc_now())
        })

      _participant ->
        {:error, :already_registered}
    end
  end

  @doc """
  One-click registration for authenticated users.
  """
  def one_click_register(%Event{} = event, %User{} = user) do
    case get_user_registration_status(event, user) do
      :not_registered ->
        create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          role: :invitee,
          status: :pending,
          source: "one_click_registration",
          metadata: %{registration_date: DateTime.utc_now()}
        })

      :cancelled ->
        reregister_user_for_event(event, user)

      :registered ->
        {:error, :already_registered}

      :organizer ->
        {:error, :organizer_cannot_register}
    end
  end

  # Theme Management Functions

  @doc """
  Updates an event's theme.

  ## Examples

      iex> update_event_theme(event, :cosmic)
      {:ok, %Event{}}

      iex> update_event_theme(event, :invalid)
      {:error, "Invalid theme"}
  """
  def update_event_theme(%Event{} = event, theme) when is_atom(theme) do
    if Themes.valid_theme?(theme) do
      event
      |> Event.changeset(%{theme: theme})
      |> Repo.update()
    else
      {:error, "Invalid theme"}
    end
  end

  @doc """
  Updates an event's theme customizations.
  """
  def update_event_theme_customizations(%Event{} = event, customizations)
      when is_map(customizations) do
    case Themes.validate_customizations(customizations) do
      {:ok, valid_customizations} ->
        merged_customizations = Themes.merge_customizations(event.theme, valid_customizations)

        event
        |> Event.changeset(%{theme_customizations: merged_customizations})
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resets an event's theme customizations to default.

  ## Examples

      iex> reset_event_theme_customizations(event)
      {:ok, %Event{}}
  """
  def reset_event_theme_customizations(%Event{} = event) do
    default_customizations = Themes.get_default_customizations(event.theme)

    event
    |> Event.changeset(%{theme_customizations: default_customizations})
    |> Repo.update()
  end

  @doc """
  Transition an event from one state to another using the state machine.

  Returns {:ok, updated_event} on success, {:error, changeset} on failure.
  """
  def transition_event_state(%Event{} = event, new_state) do
    # Check if the transition is valid using our custom state machine
    # Use Machinery's transition checking instead of manual validation
    case Machinery.transition_to(event, Event, new_state) do
      {:ok, _} ->
        # Persist the state change to the database
        event
        |> Event.changeset(%{status: new_state})
        |> Repo.update()

      {:error, reason} ->
        # Create an error changeset for invalid transitions
        changeset = Event.changeset(event, %{})

        {:error,
         Ecto.Changeset.add_error(
           changeset,
           :status,
           "invalid transition from '#{event.status}' to '#{new_state}': #{reason}"
         )}
    end
  end

  @doc """
  Check if a state transition is valid for an event using Machinery.
  """
  def can_transition_to?(%Event{} = event, new_state) do
    case Machinery.transition_to(event, Event, new_state) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get the list of possible states an event can transition to using Machinery.
  """
  def possible_transitions(%Event{} = event) do
    # Use Machinery's built-in functionality to get possible transitions
    # For now, return a basic list based on current status
    case event.status do
      :draft -> [:polling, :confirmed, :canceled]
      :polling -> [:threshold, :confirmed, :canceled]
      :threshold -> [:confirmed, :canceled]
      :confirmed -> [:canceled]
      :canceled -> []
      _ -> []
    end
  end

  ## Action-Driven Setup Functions

  @doc """
  Sets or updates the start date for an event.
  This action can trigger status transitions based on the event's current state.
  When a specific date is picked, it ends any active polling.
  """
  def pick_date(%Event{} = event, %DateTime{} = start_at, opts \\ []) do
    ends_at = Keyword.get(opts, :ends_at)
    timezone = Keyword.get(opts, :timezone, event.timezone)

    attrs = %{
      start_at: start_at,
      timezone: timezone,
      # Clear polling deadline when a specific date is picked
      polling_deadline: nil
    }

    attrs = if ends_at, do: Map.put(attrs, :ends_at, ends_at), else: attrs

    # Use inferred status changeset to allow automatic status transitions
    changeset = Event.changeset_with_inferred_status(event, attrs)

    case Repo.update(changeset) do
      {:ok, updated_event} -> {:ok, Event.with_computed_fields(updated_event)}
      error -> error
    end
  end

  @doc """
  Enables polling for an event by setting a polling deadline.
  This will transition the event to :polling status.
  """
  def enable_polling(%Event{} = event, %DateTime{} = polling_deadline) do
    attrs = %{
      polling_deadline: polling_deadline
    }

    changeset = Event.changeset_with_inferred_status(event, attrs)

    # Add custom validation for polling deadline
    changeset =
      if DateTime.compare(polling_deadline, DateTime.utc_now()) == :gt do
        changeset
      else
        Ecto.Changeset.add_error(changeset, :polling_deadline, "must be in the future")
      end

    case Repo.update(changeset) do
      {:ok, updated_event} ->
        # Schedule deadline reminder for threshold events
        maybe_schedule_deadline_reminder(updated_event)
        {:ok, Event.with_computed_fields(updated_event)}

      error ->
        error
    end
  end

  @doc """
  Sets a threshold count for an event.
  This will transition the event to :threshold status.
  """
  def set_threshold(%Event{} = event, threshold_count)
      when is_integer(threshold_count) and threshold_count > 0 do
    attrs = %{
      threshold_count: threshold_count,
      status: :threshold
    }

    # Use inferred status changeset to handle status transitions properly
    changeset = Event.changeset_with_inferred_status(event, attrs)

    case Repo.update(changeset) do
      {:ok, updated_event} ->
        # Schedule deadline reminder if event has a polling deadline
        maybe_schedule_deadline_reminder(updated_event)
        {:ok, Event.with_computed_fields(updated_event)}

      error ->
        error
    end
  end

  @doc """
  Enables ticketing for an event.
  This is a placeholder for future ticketing system integration.
  When ticketing is enabled, it clears threshold requirements and confirms the event.
  """
  def enable_ticketing(%Event{} = event, _ticketing_options \\ %{}) do
    # For now, this is a placeholder that just confirms the event
    # In the future, this would set up ticket types, pricing, etc.
    # Clear threshold_count since ticketing means the event is confirmed regardless of threshold
    attrs = %{
      threshold_count: nil,
      is_ticketed: true
    }

    changeset = Event.changeset_with_inferred_status(event, attrs)

    case Repo.update(changeset) do
      {:ok, updated_event} -> {:ok, Event.with_computed_fields(updated_event)}
      error -> error
    end
  end

  @doc """
  Adds or updates details for an event (title, description, tagline, etc.).
  This action doesn't change status but updates event information.
  """
  def add_details(%Event{} = event, details) do
    # Filter to only allowed detail fields
    allowed_fields = [
      :title,
      :description,
      :tagline,
      :cover_image_url,
      :external_image_data,
      :theme,
      :theme_customizations,
      :taxation_type
    ]

    attrs = Map.take(details, allowed_fields)

    # Use regular changeset since we don't want to change status
    changeset = Event.changeset(event, attrs)

    case Repo.update(changeset) do
      {:ok, updated_event} -> {:ok, Event.with_computed_fields(updated_event)}
      error -> error
    end
  end

  @doc """
  Publishes an event by transitioning it to confirmed status.
  This action makes the event publicly available.
  """
  def publish_event(%Event{} = event) do
    attrs = %{
      status: :confirmed,
      visibility: :public
    }

    # Use inferred status changeset to handle status transitions properly
    changeset = Event.changeset_with_inferred_status(event, attrs)

    case Repo.update(changeset) do
      {:ok, updated_event} -> {:ok, Event.with_computed_fields(updated_event)}
      error -> error
    end
  end

  # Guest Invitation System Functions

  @doc """
  Get all events organized by a user for guest invitation suggestions.
  Only returns events that have participants (to avoid empty suggestion lists).
  """
  def list_organizer_events_with_participants(%User{} = user, opts \\ []) do
    query =
      from(e in Event,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        join: ep in EventParticipant,
        on: e.id == ep.event_id,
        where: eu.user_id == ^user.id,
        group_by: [e.id, e.title, e.start_at, e.status, e.deleted_at],
        select: %{
          id: e.id,
          title: e.title,
          start_at: e.start_at,
          status: e.status,
          participant_count: count(ep.id, :distinct)
        },
        order_by: [desc: e.start_at]
      )

    query = apply_soft_delete_filter(query, opts)
    Repo.all(query)
  end

  @doc """
  Get all unique participants from events organized by a user, excluding specified events and users.
  Returns participant data with frequency and recency metrics for scoring.

  OPTIMIZED VERSION: Uses two-phase query approach for better performance.
  Phase 1: Get organizer's event IDs (cached)
  Phase 2: Query participants using those event IDs

  Options:
  - exclude_event_ids: List of event IDs to exclude from results (e.g., current event)
  - exclude_user_ids: List of user IDs to exclude from results (e.g., current participants)
  - limit: Maximum number of participants to return (default: 50)
  """
  def get_historical_participants(%User{} = organizer, opts \\ []) do
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, [])
    exclude_user_ids = Keyword.get(opts, :exclude_user_ids, [])
    limit = Keyword.get(opts, :limit, 50)

    # Phase 1: Get organizer's event IDs (this can be cached)
    organizer_event_ids = get_organizer_event_ids_basic(organizer.id)

    # Apply exclude_event_ids filter
    filtered_event_ids =
      if exclude_event_ids != [] do
        organizer_event_ids -- exclude_event_ids
      else
        organizer_event_ids
      end

    # Early return if no events
    if filtered_event_ids == [] do
      []
    else
      # Phase 2: Query participants using pre-filtered event IDs
      get_participants_for_events(filtered_event_ids, exclude_user_ids, organizer.id, limit)
    end
  end

  # LEGACY VERSION: Kept for compatibility during transition
  def get_historical_participants_legacy(%User{} = organizer, opts \\ []) do
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, [])
    exclude_user_ids = Keyword.get(opts, :exclude_user_ids, [])
    limit = Keyword.get(opts, :limit, 50)

    # Query to get unique participants with their participation history
    query =
      from(p in EventParticipant,
        join: e in Event,
        on: p.event_id == e.id,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        join: u in User,
        on: p.user_id == u.id,
        # Exclude organizer from suggestions
        # Exclude soft-deleted events
        where:
          eu.user_id == ^organizer.id and
            p.user_id != ^organizer.id and
            is_nil(e.deleted_at),
        group_by: [u.id, u.name, u.email, u.username],
        select: %{
          user_id: u.id,
          name: u.name,
          email: u.email,
          username: u.username,
          participation_count: count(p.id),
          last_participation: max(e.start_at),
          event_ids: fragment("array_agg(DISTINCT ?)", e.id)
        },
        order_by: [desc: count(p.id), desc: max(e.start_at)]
      )

    # Apply exclude_event_ids filter if provided
    query =
      if exclude_event_ids != [] do
        from([p, e, eu, u] in query,
          where: e.id not in ^exclude_event_ids
        )
      else
        query
      end

    # Apply exclude_user_ids filter if provided
    query =
      if exclude_user_ids != [] do
        from([p, e, eu, u] in query,
          where: u.id not in ^exclude_user_ids
        )
      else
        query
      end

    query
    |> limit(^limit)
    |> Repo.all()
  end

  # Private helper functions for optimized queries

  @doc false
  defp get_organizer_event_ids_basic(organizer_id) do
    # Basic query for organizer's event IDs, excluding soft-deleted events
    query =
      from(eu in EventUser,
        join: e in Event,
        on: eu.event_id == e.id,
        where: eu.user_id == ^organizer_id and is_nil(e.deleted_at),
        select: eu.event_id
      )

    Repo.all(query)
  end

  @doc false
  defp get_participants_for_events(event_ids, exclude_user_ids, organizer_id, limit) do
    # Build base query for participants in the specified events
    query =
      from(p in EventParticipant,
        join: e in Event,
        on: p.event_id == e.id,
        join: u in User,
        on: p.user_id == u.id,
        # Exclude organizer from suggestions
        # Exclude soft-deleted events
        where:
          p.event_id in ^event_ids and
            p.user_id != ^organizer_id and
            is_nil(e.deleted_at),
        group_by: [u.id, u.name, u.email, u.username],
        select: %{
          user_id: u.id,
          name: u.name,
          email: u.email,
          username: u.username,
          participation_count: count(p.id),
          last_participation: max(e.start_at),
          event_ids: fragment("array_agg(DISTINCT ?)", e.id)
        },
        order_by: [desc: count(p.id), desc: max(e.start_at)]
      )

    # Apply exclude_user_ids filter if provided
    query =
      if exclude_user_ids != [] do
        from([p, e, u] in query,
          where: u.id not in ^exclude_user_ids
        )
      else
        query
      end

    query
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get suggested participants with scoring for a specific event organizer.
  Combines frequency and recency scoring with configurable weights.

  Scoring formula: (Frequency Score × 0.6) + (Recency Score × 0.4)

  Options:
  - exclude_event_ids: List of event IDs to exclude (default: [])
  - exclude_user_ids: List of user IDs to exclude (default: [])
  - limit: Maximum number of suggestions (default: 20)
  - frequency_weight: Weight for frequency score (default: 0.6)
  - recency_weight: Weight for recency score (default: 0.4)
  """
  def get_participant_suggestions(%User{} = organizer, opts \\ []) do
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, [])
    exclude_user_ids = Keyword.get(opts, :exclude_user_ids, [])
    limit = Keyword.get(opts, :limit, 20)
    frequency_weight = Keyword.get(opts, :frequency_weight, 0.6)
    recency_weight = Keyword.get(opts, :recency_weight, 0.4)

    participants =
      get_historical_participants(organizer,
        exclude_event_ids: exclude_event_ids,
        exclude_user_ids: exclude_user_ids,
        # Get more to have better selection after scoring
        limit: limit * 2
      )

    # Use the dedicated scoring module
    config =
      GuestInvitations.create_config(
        frequency_weight: frequency_weight,
        recency_weight: recency_weight
      )

    GuestInvitations.score_participants(participants, config, limit: limit)
  end

  @doc """
  Get paginated participant suggestions for efficient loading.

  Options:
  - exclude_event_ids: List of event IDs to exclude (default: [])
  - page: Page number (1-based, default: 1)
  - per_page: Results per page (default: 20)
  """
  def get_participant_suggestions_paginated(%User{} = organizer, opts \\ []) do
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, [])
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    offset = (page - 1) * per_page

    # Get total count for pagination metadata
    total_count = count_historical_participants(organizer, exclude_event_ids: exclude_event_ids)

    # Get the actual data using the scoring module
    participants =
      get_historical_participants(organizer,
        exclude_event_ids: exclude_event_ids,
        # Get extra for scoring
        limit: per_page * 3
      )
      |> GuestInvitations.score_participants()
      |> Enum.drop(offset)
      |> Enum.take(per_page)

    %{
      participants: participants,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: ceil(total_count / per_page),
      has_next?: page * per_page < total_count,
      has_prev?: page > 1
    }
  end

  @doc """
  Count historical participants for pagination.
  """
  def count_historical_participants(%User{} = organizer, opts \\ []) do
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, [])

    query =
      from(p in EventParticipant,
        join: e in Event,
        on: p.event_id == e.id,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        where:
          eu.user_id == ^organizer.id and
            p.user_id != ^organizer.id,
        select: count(p.user_id, :distinct)
      )

    # Apply exclude_event_ids filter if provided
    query =
      if exclude_event_ids != [] do
        from([p, e, eu] in query,
          where: e.id not in ^exclude_event_ids
        )
      else
        query
      end

    Repo.one(query) || 0
  end

  # Participant Aggregation Functions

  @doc """
  Get participant statistics for a specific event.
  Returns counts by status and role for invitation management.
  """
  def get_event_participant_stats(%Event{} = event) do
    query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id,
        group_by: [ep.status, ep.role],
        select: %{
          status: ep.status,
          role: ep.role,
          count: count(ep.id)
        }
      )

    stats = Repo.all(query)

    # Aggregate into a more usable format
    %{
      total_participants: Enum.sum(Enum.map(stats, & &1.count)),
      by_status: aggregate_by_field(stats, :status),
      by_role: aggregate_by_field(stats, :role),
      breakdown: stats
    }
  end

  @doc """
  Get participant statistics for multiple events organized by a user.
  Returns a map with event_id as keys and participant stats as values.
  """
  def get_organizer_events_participant_stats(%User{} = organizer, event_ids \\ nil) do
    # Get all events organized by user or filter by specific event_ids
    base_query =
      from(e in Event,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        where: eu.user_id == ^organizer.id,
        select: e.id
      )

    event_ids =
      if event_ids do
        from([e, eu] in base_query, where: e.id in ^event_ids)
        |> Repo.all()
      else
        Repo.all(base_query)
      end

    # Get participant stats for each event
    Enum.reduce(event_ids, %{}, fn event_id, acc ->
      event = %Event{id: event_id}
      stats = get_event_participant_stats(event)
      Map.put(acc, event_id, stats)
    end)
  end

  @doc """
  Get detailed participant breakdown for an event with user information.
  Useful for invitation management interfaces.
  """
  def get_event_participant_details(%Event{} = event, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    status_filter = Keyword.get(opts, :status)
    role_filter = Keyword.get(opts, :role)

    query =
      from(ep in EventParticipant,
        join: u in User,
        on: ep.user_id == u.id,
        where: ep.event_id == ^event.id,
        select: %{
          participant_id: ep.id,
          user_id: u.id,
          name: u.name,
          email: u.email,
          username: u.username,
          status: ep.status,
          role: ep.role,
          invited_at: ep.invited_at,
          invitation_message: ep.invitation_message,
          invited_by_user_id: ep.invited_by_user_id,
          metadata: ep.metadata,
          inserted_at: ep.inserted_at
        },
        order_by: [desc: ep.inserted_at]
      )

    # Apply filters if provided
    query =
      if status_filter do
        from(ep in query, where: ep.status == ^status_filter)
      else
        query
      end

    query =
      if role_filter do
        from(ep in query, where: ep.role == ^role_filter)
      else
        query
      end

    query
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get invitation statistics for events organized by a user.
  Shows who invited whom and invitation success rates.
  """
  def get_invitation_stats(%User{} = organizer, opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 90)
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_back * 24 * 60 * 60, :second)

    query =
      from(ep in EventParticipant,
        join: e in Event,
        on: ep.event_id == e.id,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        left_join: inviter in User,
        on: ep.invited_by_user_id == inviter.id,
        # Exclude soft-deleted events
        where:
          eu.user_id == ^organizer.id and
            not is_nil(ep.invited_at) and
            ep.invited_at >= ^cutoff_date and
            is_nil(e.deleted_at),
        group_by: [ep.invited_by_user_id, inviter.name, ep.status],
        select: %{
          invited_by_user_id: ep.invited_by_user_id,
          inviter_name: inviter.name,
          status: ep.status,
          count: count(ep.id)
        }
      )

    stats = Repo.all(query)

    # Aggregate invitation success rates
    invitation_summary =
      stats
      |> Enum.group_by(& &1.invited_by_user_id)
      |> Enum.map(fn {inviter_id, invitations} ->
        total = Enum.sum(Enum.map(invitations, & &1.count))

        accepted =
          invitations
          |> Enum.filter(&(&1.status in [:accepted, :confirmed_with_order]))
          |> Enum.sum_by(& &1.count)

        success_rate = if total > 0, do: accepted / total * 100, else: 0

        %{
          inviter_user_id: inviter_id,
          inviter_name: List.first(invitations).inviter_name,
          total_invitations: total,
          accepted_invitations: accepted,
          success_rate: Float.round(success_rate, 1)
        }
      end)
      |> Enum.sort_by(& &1.total_invitations, :desc)

    %{
      period_days: days_back,
      cutoff_date: cutoff_date,
      invitation_summary: invitation_summary,
      detailed_breakdown: stats
    }
  end

  @doc """
  Check if a user has been invited to an event by a specific organizer.
  Returns invitation details if found.
  """
  def get_user_invitation_status(%Event{} = event, %User{} = user) do
    query =
      from(ep in EventParticipant,
        left_join: inviter in User,
        on: ep.invited_by_user_id == inviter.id,
        where: ep.event_id == ^event.id and ep.user_id == ^user.id,
        select: %{
          participant_id: ep.id,
          status: ep.status,
          role: ep.role,
          invited_at: ep.invited_at,
          invitation_message: ep.invitation_message,
          invited_by_user_id: ep.invited_by_user_id,
          inviter_name: inviter.name,
          metadata: ep.metadata
        }
      )

    case Repo.one(query) do
      nil -> {:not_invited, nil}
      invitation -> {:invited, invitation}
    end
  end

  @doc """
  Get a summary of recent invitation activity for an organizer.
  Useful for dashboard displays.
  """
  def get_recent_invitation_activity(%User{} = organizer, opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 7)
    limit = Keyword.get(opts, :limit, 20)
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_back * 24 * 60 * 60, :second)

    query =
      from(ep in EventParticipant,
        join: e in Event,
        on: ep.event_id == e.id,
        join: eu in EventUser,
        on: e.id == eu.event_id,
        join: u in User,
        on: ep.user_id == u.id,
        left_join: inviter in User,
        on: ep.invited_by_user_id == inviter.id,
        # Exclude soft-deleted events
        where:
          eu.user_id == ^organizer.id and
            not is_nil(ep.invited_at) and
            ep.invited_at >= ^cutoff_date and
            is_nil(e.deleted_at),
        select: %{
          event_id: e.id,
          event_title: e.title,
          participant_name: u.name,
          participant_email: u.email,
          status: ep.status,
          invited_at: ep.invited_at,
          inviter_name: inviter.name,
          invitation_message: ep.invitation_message
        },
        order_by: [desc: ep.invited_at],
        limit: ^limit
      )

    Repo.all(query)
  end

  # Guest Invitation Processing Functions

  @doc """
  Process guest invitations for an event by creating event participants.

  Handles both suggested users (from historical data) and manual email entries.
  Creates users for emails that don't exist, validates duplicates, and tracks
  invitation metadata.

  Options:
  - suggestion_structs: List of suggestion maps with user_id field
  - manual_emails: List of email strings
  - invitation_message: Custom message for the invitation
  - organizer: User struct of the person sending invitations
  - mode: :invitation (default) or :direct_add

  Returns a map with:
  - successful_invitations: Count of successfully processed guests
  - skipped_duplicates: Count of users already participating
  - failed_invitations: Count of failed attempts
  - errors: List of error messages
  """
  def process_guest_invitations(%Event{} = event, %User{} = organizer, opts \\ []) do
    suggestion_structs = Keyword.get(opts, :suggestion_structs, [])
    manual_emails = Keyword.get(opts, :manual_emails, [])
    invitation_message = Keyword.get(opts, :invitation_message, "")
    mode = Keyword.get(opts, :mode, :invitation)

    current_time = DateTime.utc_now()

    # Initialize counters
    result = %{
      successful_invitations: 0,
      skipped_duplicates: 0,
      failed_invitations: 0,
      errors: []
    }

    # Process suggestion invitations
    result_after_suggestions =
      Enum.reduce(suggestion_structs, result, fn suggestion, acc ->
        case process_suggestion_invitation(
               event,
               organizer,
               suggestion,
               invitation_message,
               current_time,
               mode
             ) do
          {:ok, :created} ->
            %{acc | successful_invitations: acc.successful_invitations + 1}

          {:ok, :already_exists} ->
            %{acc | skipped_duplicates: acc.skipped_duplicates + 1}

          {:error, reason} ->
            error_msg =
              "Failed to invite #{get_suggestion_identifier(suggestion)}: #{format_error(reason)}"

            %{
              acc
              | failed_invitations: acc.failed_invitations + 1,
                errors: [error_msg | acc.errors]
            }
        end
      end)

    # Process manual email invitations
    Enum.reduce(manual_emails, result_after_suggestions, fn email, acc ->
      case process_email_invitation(
             event,
             organizer,
             email,
             invitation_message,
             current_time,
             mode
           ) do
        {:ok, :created} ->
          %{acc | successful_invitations: acc.successful_invitations + 1}

        {:ok, :already_exists} ->
          %{acc | skipped_duplicates: acc.skipped_duplicates + 1}

        {:error, reason} ->
          error_msg = "Failed to invite #{email}: #{format_error(reason)}"

          %{
            acc
            | failed_invitations: acc.failed_invitations + 1,
              errors: [error_msg | acc.errors]
          }
      end
    end)
  end

  # Process a single suggestion invitation
  defp process_suggestion_invitation(
         event,
         organizer,
         suggestion,
         invitation_message,
         current_time,
         mode
       ) do
    case EventasaurusApp.Accounts.get_user(suggestion.user_id) do
      %User{} = user ->
        create_invitation_participant(
          event,
          organizer,
          user,
          invitation_message,
          current_time,
          %{
            invitation_method: get_invitation_method(mode, "historical_suggestion"),
            recommendation_level: Map.get(suggestion, :recommendation_level, "unknown"),
            score: Map.get(suggestion, :total_score, 0.0)
          },
          mode
        )

      nil ->
        {:error, :user_not_found}
    end
  end

  # Process a single email invitation
  defp process_email_invitation(event, organizer, email, invitation_message, current_time, mode) do
    case EventasaurusApp.Accounts.find_or_create_guest_user(email) do
      {:ok, user} ->
        create_invitation_participant(
          event,
          organizer,
          user,
          invitation_message,
          current_time,
          %{
            invitation_method: get_invitation_method(mode, "manual_email"),
            email_provided: email
          },
          mode
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Create an event participant with invitation tracking
  defp create_invitation_participant(
         event,
         organizer,
         user,
         invitation_message,
         current_time,
         metadata,
         mode
       ) do
    case get_event_participant_by_event_and_user(event, user) do
      nil ->
        participant_attrs =
          build_participant_attrs(
            event,
            organizer,
            user,
            invitation_message,
            current_time,
            metadata,
            mode
          )

        case create_event_participant(participant_attrs) do
          {:ok, participant} ->
            if mode == :invitation do
              case queue_invitation_email(user, event, invitation_message, organizer) do
                {:ok, _job} ->
                  :ok

                {:error, reason} ->
                  failed =
                    EventParticipant.mark_email_failed(participant, format_email_error(reason))

                  _ = update_event_participant(participant, %{metadata: failed.metadata})
              end
            end

            {:ok, :created}

          {:error, changeset} ->
            {:error, changeset}
        end

      _existing_participant ->
        {:ok, :already_exists}
    end
  end

  # Queue invitation email job to be processed by Oban
  defp queue_invitation_email(user, event, invitation_message, organizer) do
    organizer_id =
      case organizer do
        %User{id: id} -> id
        %{id: id} when is_integer(id) -> id
        id when is_integer(id) -> id
        _ -> nil
      end

    args = %{
      user_id: user.id,
      event_id: event.id,
      invitation_message: invitation_message || "",
      organizer_id: organizer_id
    }

    args
    |> EmailInvitationJob.new(
      unique: [
        keys: [:user_id, :event_id],
        states: [
          :available,
          :scheduled,
          :executing,
          :retryable,
          :completed,
          :cancelled,
          :discarded
        ],
        period: 3600
      ]
    )
    |> Oban.insert()
  end

  # Queue a single participant email using Oban
  def queue_single_participant_email(
        %EventParticipant{} = participant,
        %Event{} = event,
        organizer \\ nil
      ) do
    organizer_id =
      case organizer do
        %User{id: id} ->
          id

        %{id: id} when is_integer(id) ->
          id

        id when is_integer(id) ->
          id

        _ ->
          case get_event_organizer(event) do
            %User{id: id} -> id
            _ -> participant.invited_by_user_id
          end
      end

    %{
      user_id: participant.user_id,
      event_id: event.id,
      invitation_message: participant.invitation_message || "",
      organizer_id: organizer_id
    }
    |> EmailInvitationJob.new(
      unique: [
        keys: [:user_id, :event_id],
        states: [
          :available,
          :scheduled,
          :executing,
          :retryable,
          :completed,
          :cancelled,
          :discarded
        ],
        period: 3600
      ]
    )
    |> Oban.insert()
  end

  # Helper function to format error messages for storage
  def format_email_error(reason) do
    case reason do
      %{message: message} -> message
      %{"message" => message} -> message
      error when is_binary(error) -> error
      error -> inspect(error)
    end
  end

  # Get event with venue preloaded for email templates
  def get_event_with_venue(event_id) do
    case Repo.one(
           from(e in Event,
             where: e.id == ^event_id,
             preload: [:venue]
           )
         ) do
      nil ->
        Logger.error("Event not found for email sending", event_id: event_id)
        nil

      event ->
        event
    end
  end

  # Get user display name for emails
  def get_user_display_name(user) do
    cond do
      user.name && user.name != "" -> user.name
      user.username && user.username != "" -> user.username
      true -> nil
    end
  end

  # Build participant attributes based on mode
  defp build_participant_attrs(
         event,
         organizer,
         user,
         invitation_message,
         current_time,
         metadata,
         mode
       ) do
    base_attrs = %{
      event_id: event.id,
      user_id: user.id,
      role: :invitee,
      status: :pending,
      source: metadata.invitation_method,
      metadata: metadata
    }

    case mode do
      :direct_add ->
        # For direct add, set status to accepted and don't include invitation metadata
        Map.merge(base_attrs, %{
          status: :accepted,
          invited_by_user_id: organizer.id,
          invited_at: current_time
        })

      :invitation ->
        # For invitations, include all invitation metadata
        Map.merge(base_attrs, %{
          invited_by_user_id: organizer.id,
          invited_at: current_time,
          invitation_message: invitation_message
        })

      _ ->
        # Default to invitation mode
        Map.merge(base_attrs, %{
          invited_by_user_id: organizer.id,
          invited_at: current_time,
          invitation_message: invitation_message
        })
    end
  end

  # Get invitation method based on mode
  defp get_invitation_method(:direct_add, "historical_suggestion"), do: "direct_add_suggestion"
  defp get_invitation_method(:direct_add, "manual_email"), do: "direct_add_email"
  defp get_invitation_method(_, original_method), do: original_method

  # Helper functions for error handling
  defp get_suggestion_identifier(suggestion) do
    case suggestion do
      %{email: email} when is_binary(email) -> email
      %{name: name} when is_binary(name) -> name
      %{user_id: user_id} -> "User ID #{user_id}"
      _ -> "Unknown user"
    end
  end

  defp format_error(:user_not_found), do: "User not found"
  defp format_error(:invalid_email), do: "Invalid email address"

  defp format_error(changeset) when is_struct(changeset) do
    case changeset do
      %Ecto.Changeset{errors: [_ | _] = errors} ->
        error_messages =
          Enum.map(errors, fn {field, {message, _opts}} ->
            "#{field}: #{message}"
          end)

        "Validation failed: #{Enum.join(error_messages, ", ")}"

      %Ecto.Changeset{} ->
        "Validation failed: Unknown error"

      _ ->
        "Could not create user account"
    end
  end

  defp format_error(reason), do: inspect(reason)

  # Private helper for aggregating stats by field
  defp aggregate_by_field(stats, field) do
    stats
    |> Enum.group_by(&Map.get(&1, field))
    |> Enum.map(fn {key, group} ->
      {key, Enum.sum(Enum.map(group, & &1.count))}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Gets the count of participants for a specific event.
  """
  def count_event_participants(event) do
    Repo.aggregate(
      from(p in EventParticipant, where: p.event_id == ^event.id and is_nil(p.deleted_at)),
      :count,
      :id
    )
  end

  @doc """
  Gets participants for a specific event with optional pagination support.
  """
  def list_event_participants(event, opts \\ []) do
    limit = Keyword.get(opts, :limit, nil)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(p in EventParticipant,
        where: p.event_id == ^event.id and is_nil(p.deleted_at),
        preload: [:user]
      )

    query =
      if limit do
        query |> limit(^limit) |> offset(^offset)
      else
        query
      end

    Repo.all(query)
  end

  # Email Status Query Helpers

  @doc """
  Lists event participants filtered by email status.
  """
  def list_event_participants_by_email_status(%Event{} = event, status) do
    query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id and is_nil(ep.deleted_at),
        preload: [:user, :invited_by_user]
      )

    query
    |> EventParticipant.by_email_status(status)
    |> Repo.all()
  end

  @doc """
  Lists event participants with failed emails.
  """
  def list_event_participants_with_failed_emails(%Event{} = event) do
    query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id and is_nil(ep.deleted_at),
        preload: [:user, :invited_by_user]
      )

    query
    |> EventParticipant.with_failed_emails()
    |> Repo.all()
  end

  @doc """
  Lists event participants without any email status (never sent).
  """
  def list_event_participants_without_email_status(%Event{} = event) do
    query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id and is_nil(ep.deleted_at),
        preload: [:user, :invited_by_user]
      )

    query
    |> EventParticipant.without_email_status()
    |> Repo.all()
  end

  @doc """
  Gets participants that can be retried for email delivery.
  """
  def list_email_retry_candidates(%Event{} = event, max_attempts \\ 3) do
    EventParticipant.get_retry_candidates(event.id, max_attempts)
    |> Repo.all()
  end

  @doc """
  Gets email delivery statistics for an event.
  """
  def get_email_delivery_stats(%Event{} = event) do
    base_query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id
      )

    stats = %{
      total_participants: Repo.aggregate(base_query, :count, :id),
      not_sent: 0,
      sending: 0,
      sent: 0,
      delivered: 0,
      failed: 0,
      bounced: 0
    }

    # Get counts for each status
    status_counts =
      from(ep in base_query,
        select: {
          fragment("COALESCE(?->>'email_status', 'not_sent')", ep.metadata),
          count(ep.id)
        },
        group_by: fragment("COALESCE(?->>'email_status', 'not_sent')", ep.metadata)
      )
      |> Repo.all()
      |> Map.new()

    # Merge the counts into our stats map
    Map.merge(stats, status_counts)
  end

  @doc """
  Gets participants with detailed email status information for an event.
  """
  def get_event_participant_email_details(%Event{} = event, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    status_filter = Keyword.get(opts, :email_status)

    query =
      from(ep in EventParticipant,
        join: u in User,
        on: ep.user_id == u.id,
        where: ep.event_id == ^event.id,
        select: %{
          participant_id: ep.id,
          user_id: u.id,
          name: u.name,
          email: u.email,
          username: u.username,
          status: ep.status,
          role: ep.role,
          invited_at: ep.invited_at,
          email_status: fragment("COALESCE(?->>'email_status', 'not_sent')", ep.metadata),
          email_last_sent_at: fragment("?->>'email_last_sent_at'", ep.metadata),
          email_attempts: fragment("COALESCE((?->>'email_attempts')::integer, 0)", ep.metadata),
          email_last_error: fragment("?->>'email_last_error'", ep.metadata),
          email_delivery_id: fragment("?->>'email_delivery_id'", ep.metadata),
          metadata: ep.metadata,
          inserted_at: ep.inserted_at
        },
        order_by: [desc: ep.inserted_at]
      )

    # Apply email status filter if provided
    query =
      if status_filter do
        from(ep in query,
          where:
            fragment("COALESCE(?->>'email_status', 'not_sent') = ?", ep.metadata, ^status_filter)
        )
      else
        query
      end

    query
    |> limit(^limit)
    |> Repo.all()
  end

  # Email Retry Logic

  @doc """
  Retries failed emails for a specific event.

  Options:
  - max_attempts: Maximum retry attempts (default: 3)
  - batch_size: Number of emails to retry in one batch (default: 10)
  - delay_seconds: Delay between retries in seconds (default: 300, 5 minutes)
  """
  def retry_failed_emails(%Event{} = event, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    batch_size = Keyword.get(opts, :batch_size, 10)
    delay_seconds = Keyword.get(opts, :delay_seconds, 300)

    # Get candidates for retry
    candidates =
      list_email_retry_candidates(event, max_attempts)
      |> filter_by_retry_delay(delay_seconds)
      |> Enum.take(batch_size)

    results = %{
      attempted: 0,
      successful: 0,
      failed: 0,
      errors: []
    }

    if length(candidates) > 0 do
      Logger.info(
        "Retrying failed emails for event #{event.id}, #{length(candidates)} candidates"
      )

      Enum.reduce(candidates, results, fn participant, acc ->
        case retry_single_email(participant, event) do
          :ok ->
            %{acc | attempted: acc.attempted + 1, successful: acc.successful + 1}

          {:error, reason} ->
            error_msg =
              "Failed to retry email for user #{participant.user_id}: #{format_email_error(reason)}"

            %{
              acc
              | attempted: acc.attempted + 1,
                failed: acc.failed + 1,
                errors: [error_msg | acc.errors]
            }
        end
      end)
    else
      Logger.info("No email retry candidates found for event #{event.id}")
      results
    end
  end

  @doc """
  Retries a single failed email for a participant.
  """
  def retry_single_email(%EventParticipant{} = participant, %Event{} = event) do
    # Check if retry is allowed
    unless EventParticipant.can_retry_email?(participant) do
      {:error, "Maximum retry attempts exceeded"}
    else
      # Get the event organizer
      organizer = get_event_organizer(event)

      # Mark as retrying before queueing the job
      retrying_participant = EventParticipant.update_email_status(participant, "retrying")

      case update_event_participant(participant, %{metadata: retrying_participant.metadata}) do
        {:ok, _} ->
          # Queue the retry using Oban (same as single participant email)
          case queue_single_participant_email(participant, event, organizer) do
            {:ok, _job} ->
              Logger.info("Email retry queued for participant #{participant.id}")
              :ok

            {:error, reason} ->
              # Mark as failed if we couldn't even queue the job
              error_message = format_email_error(reason)
              failed_participant = EventParticipant.mark_email_failed(participant, error_message)
              update_event_participant(participant, %{metadata: failed_participant.metadata})
              {:error, reason}
          end

        {:error, changeset_error} ->
          {:error, changeset_error}
      end
    end
  end

  @doc """
  Schedules email retries for all events with failed emails.
  This function can be called from a background job.
  """
  def schedule_email_retries(opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    batch_size_per_event = Keyword.get(opts, :batch_size_per_event, 5)

    # Find events with failed emails
    events_with_failed_emails = get_events_with_failed_emails(max_attempts)

    Logger.info("Found #{length(events_with_failed_emails)} events with failed emails to retry")

    results =
      Enum.map(events_with_failed_emails, fn event ->
        result =
          retry_failed_emails(event,
            max_attempts: max_attempts,
            batch_size: batch_size_per_event
          )

        {event.id, result}
      end)

    # Log summary
    total_attempted = results |> Enum.map(fn {_, result} -> result.attempted end) |> Enum.sum()
    total_successful = results |> Enum.map(fn {_, result} -> result.successful end) |> Enum.sum()
    total_failed = results |> Enum.map(fn {_, result} -> result.failed end) |> Enum.sum()

    Logger.info(
      "Email retry summary: #{total_attempted} attempted, #{total_successful} successful, #{total_failed} failed"
    )

    %{
      events_processed: length(events_with_failed_emails),
      total_attempted: total_attempted,
      total_successful: total_successful,
      total_failed: total_failed,
      results: Map.new(results)
    }
  end

  # Private helper functions for retry logic

  defp filter_by_retry_delay(participants, delay_seconds) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-delay_seconds, :second)

    Enum.filter(participants, fn participant ->
      email_status = EventParticipant.get_email_status(participant)

      case email_status.last_sent_at do
        nil ->
          true

        timestamp_string ->
          case DateTime.from_iso8601(timestamp_string) do
            {:ok, timestamp, _} -> DateTime.compare(timestamp, cutoff_time) == :lt
            # If we can't parse the timestamp, allow retry
            _ -> true
          end
      end
    end)
  end

  defp get_events_with_failed_emails(max_attempts) do
    # Find events that have participants with failed emails within retry limits
    query =
      from(e in Event,
        join: ep in EventParticipant,
        on: e.id == ep.event_id,
        where: fragment("(?->>'email_status') IN ('failed', 'bounced')", ep.metadata),
        where:
          fragment("COALESCE((?->>'email_attempts')::integer, 0) < ?", ep.metadata, ^max_attempts),
        group_by: e.id,
        select: e
      )

    Repo.all(query)
  end

  defp get_event_organizer(%Event{users: users}) when is_list(users) do
    # Return the first organizer/admin user
    List.first(users)
  end

  defp get_event_organizer(%Event{} = event) do
    # If users aren't preloaded, load the first organizer
    query =
      from(eu in EventUser,
        join: u in User,
        on: eu.user_id == u.id,
        where: eu.event_id == ^event.id,
        limit: 1,
        select: u
      )

    Repo.one(query)
  end

  @doc """
  Get recent physical locations for a specific user based on their event history.

  This function queries the user's past events to find frequently used physical venues.
  Virtual events are excluded since they typically don't reuse meeting URLs and aren't
  useful for recent location suggestions.

  ## Privacy and Security

  Only returns locations from events where the user is an organizer (via EventUser table).
  This ensures users can only see venues from events they organized, not from events
  they merely attended as participants.

  ## Parameters

  - `user_id` - The ID of the user to query
  - `opts` - Optional parameters:
    - `:limit` - Maximum number of locations to return (default: 5)
    - `:exclude_event_ids` - List of event IDs to exclude from the query

  ## Returns

  A list of maps containing physical venue information only, sorted by usage frequency and recency.
  Each map contains:
  - `id` - Venue ID (always present for physical venues)
  - `name` - Venue name (or "Deleted Venue" if venue was deleted)
  - `address` - Full address (or nil if venue was deleted)
  - `city` - City name (or nil if venue was deleted)
  - `state` - State name (or nil if venue was deleted)
  - `country` - Country name (or nil if venue was deleted)
  - `virtual_venue_url` - Always nil (virtual events are excluded)
  - `usage_count` - Number of times this venue has been used
  - `last_used` - DateTime of most recent usage
  - `is_deleted` - Boolean indicating if the venue record was deleted

  ## Examples

      iex> get_recent_locations_for_user(123)
      [
        %{
          id: 456,
          name: "Downtown Conference Center",
          address: "123 Main St, Downtown, CA 90210, USA",
          city: "Downtown",
          state: "CA",
          country: "USA",
          virtual_venue_url: nil,
          usage_count: 5,
          last_used: ~U[2024-01-15 10:30:00Z],
          is_deleted: false
        },
        %{
          id: 789,
          name: "Deleted Venue",
          address: nil,
          city: nil,
          state: nil,
          country: nil,
          virtual_venue_url: nil,
          usage_count: 3,
          last_used: ~U[2024-01-10 14:00:00Z],
          is_deleted: true
        }
      ]

      iex> get_recent_locations_for_user(123, limit: 3, exclude_event_ids: [789])
      # Returns up to 3 physical locations, excluding event ID 789

      iex> get_recent_locations_for_user(999999)
      []  # Returns empty list for non-existent user
  """
  def get_recent_locations_for_user(user_id, opts \\ []) do
    # Validate inputs
    if not is_integer(user_id) or user_id <= 0 do
      raise ArgumentError, "user_id must be a positive integer, got: #{inspect(user_id)}"
    end

    limit = Keyword.get(opts, :limit, 5)
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, [])

    # Validate exclude_event_ids is a list of integers
    if not is_list(exclude_event_ids) do
      raise ArgumentError, "exclude_event_ids must be a list, got: #{inspect(exclude_event_ids)}"
    end

    # Validate all exclude_event_ids are positive integers
    invalid_ids = Enum.reject(exclude_event_ids, &(is_integer(&1) and &1 > 0))

    if not Enum.empty?(invalid_ids) do
      raise ArgumentError,
            "exclude_event_ids must contain only positive integers, invalid: #{inspect(invalid_ids)}"
    end

    # Optimized query: do grouping, counting, and limiting in SQL
    # This avoids fetching all user events and processing in Elixir
    query =
      from(eu in EventUser,
        join: e in Event,
        on: eu.event_id == e.id,
        left_join: v in Venue,
        on: e.venue_id == v.id,
        left_join: c in assoc(v, :city_ref),
        left_join: country in assoc(c, :country),
        where:
          eu.user_id == ^user_id and
            e.id not in ^exclude_event_ids and
            is_nil(e.virtual_venue_url) and
            not is_nil(e.venue_id) and
            is_nil(e.deleted_at),
        group_by: [e.venue_id, v.name, v.address, v.latitude, v.longitude, c.name, country.name],
        select: %{
          venue_id: e.venue_id,
          venue_name: v.name,
          venue_address: v.address,
          venue_latitude: v.latitude,
          venue_longitude: v.longitude,
          venue_city: c.name,
          venue_state: nil,
          venue_country: country.name,
          usage_count: count(e.id),
          last_used: max(e.inserted_at)
        },
        order_by: [desc: count(e.id), desc: max(e.inserted_at)],
        limit: ^limit
      )

    query
    |> Repo.all()
    |> Enum.map(fn row ->
      # Handle deleted venues gracefully
      is_deleted = is_nil(row.venue_name)

      %{
        id: row.venue_id,
        name: if(is_deleted, do: "Deleted Venue", else: row.venue_name),
        address: if(is_deleted, do: nil, else: row.venue_address),
        latitude: if(is_deleted, do: nil, else: row.venue_latitude),
        longitude: if(is_deleted, do: nil, else: row.venue_longitude),
        city: if(is_deleted, do: nil, else: row.venue_city),
        state: if(is_deleted, do: nil, else: row.venue_state),
        country: if(is_deleted, do: nil, else: row.venue_country),
        virtual_venue_url: nil,
        usage_count: row.usage_count,
        last_used: row.last_used,
        is_deleted: is_deleted
      }
    end)
  end

  # Generic Participant Status Management Functions

  @doc """
  Updates a user's participant status for an event.

  Creates or updates an EventParticipant record with the specified status.
  If participant already exists with different status, updates to new status.
  If already has target status, returns existing record.

  Valid statuses: :pending, :accepted, :declined, :cancelled, :confirmed_with_order, :interested

  Returns:
  - {:ok, participant} - User status updated successfully
  - {:error, changeset} - Validation failed
  """
  def update_participant_status(%Event{} = event, %User{} = user, status) when is_atom(status) do
    case get_event_participant_by_event_and_user(event, user) do
      nil ->
        # Create new participant with specified status
        create_event_participant(%{
          event_id: event.id,
          user_id: user.id,
          role: :invitee,
          status: status,
          metadata: %{
            "#{status}_at" => DateTime.utc_now(),
            source: "api"
          }
        })

      existing_participant ->
        # Update existing participant to new status
        update_event_participant(existing_participant, %{
          status: status,
          metadata:
            Map.merge(existing_participant.metadata || %{}, %{
              "#{status}_at" => DateTime.utc_now(),
              previous_status: existing_participant.status
            })
        })
    end
  end

  @doc """
  Removes a user's participation status from an event.

  If status_filter is provided, only removes if user has that specific status.
  If status_filter is nil, removes any participation record.

  Returns:
  - {:ok, :removed} - Participation successfully removed
  - {:ok, :not_participant} - User was not a participant (or didn't have specified status)
  - {:error, reason} - Delete operation failed
  """
  def remove_participant_status(%Event{} = event, %User{} = user, status_filter \\ nil) do
    case get_event_participant_by_event_and_user(event, user) do
      %EventParticipant{status: current_status} = participant ->
        should_remove =
          case status_filter do
            # Remove any participation
            nil -> true
            # Status matches filter
            ^current_status -> true
            # Status doesn't match filter
            _ -> false
          end

        if should_remove do
          case delete_event_participant(participant) do
            {:ok, _} -> {:ok, :removed}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, :not_participant}
        end

      nil ->
        # User not a participant
        {:ok, :not_participant}
    end
  end

  @doc """
  Checks if a user has a specific status for an event.

  Returns true if user has EventParticipant record with the specified status.
  """
  def user_has_status?(%Event{} = event, %User{} = user, status) when is_atom(status) do
    case get_event_participant_by_event_and_user(event, user) do
      %EventParticipant{status: ^status} -> true
      _ -> false
    end
  end

  @doc """
  Lists all users with a specific status for an event.

  Returns list of EventParticipant structs with preloaded users.
  Only accessible to event organizers.
  """
  def list_participants_by_status(%Event{} = event, status) when is_atom(status) do
    query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id and ep.status == ^status and is_nil(ep.deleted_at),
        preload: [:user],
        order_by: [desc: ep.inserted_at]
      )

    Repo.all(query)
  end

  @doc """
  Lists participants with a specific status for an event with pagination.

  Returns list of EventParticipant structs with preloaded users.
  Only accessible to event organizers.
  """
  def list_participants_by_status(%Event{} = event, status, page, per_page)
      when is_atom(status) and is_integer(page) and is_integer(per_page) do
    offset = (page - 1) * per_page

    query =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id and ep.status == ^status and is_nil(ep.deleted_at),
        preload: [:user],
        order_by: [desc: ep.inserted_at],
        limit: ^per_page,
        offset: ^offset
      )

    Repo.all(query)
  end

  @doc """
  Counts users with a specific status for an event.

  Returns integer count of participants with the specified status.
  """
  def count_participants_by_status(%Event{} = event, status) when is_atom(status) do
    from(ep in EventParticipant,
      where: ep.event_id == ^event.id and ep.status == ^status and is_nil(ep.deleted_at),
      select: count(ep.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets comprehensive participant analytics for an event.

  Returns map with counts for all participant statuses and overall statistics.
  Only accessible to event organizers.
  """
  def get_participant_analytics(%Event{} = event) do
    # Get counts for all possible statuses
    status_counts =
      from(ep in EventParticipant,
        where: ep.event_id == ^event.id,
        group_by: ep.status,
        select: {ep.status, count(ep.id)}
      )
      |> Repo.all()
      |> Enum.into(%{})

    # Calculate totals
    total_participants = Enum.sum(Map.values(status_counts))

    # Build comprehensive analytics
    %{
      status_counts: %{
        pending: Map.get(status_counts, :pending, 0),
        accepted: Map.get(status_counts, :accepted, 0),
        declined: Map.get(status_counts, :declined, 0),
        cancelled: Map.get(status_counts, :cancelled, 0),
        confirmed_with_order: Map.get(status_counts, :confirmed_with_order, 0),
        interested: Map.get(status_counts, :interested, 0)
      },
      total_participants: total_participants,
      engagement_metrics: %{
        response_rate: calculate_response_rate(status_counts),
        conversion_rate: calculate_conversion_rate(status_counts),
        interest_ratio: calculate_interest_ratio(status_counts, total_participants)
      }
    }
  end

  # Helper functions for analytics calculations
  defp calculate_response_rate(status_counts) do
    responded = (status_counts[:accepted] || 0) + (status_counts[:declined] || 0)
    total = Enum.sum(Map.values(status_counts))
    if total > 0, do: responded / total, else: 0
  end

  defp calculate_conversion_rate(status_counts) do
    converted = (status_counts[:accepted] || 0) + (status_counts[:confirmed_with_order] || 0)
    total = Enum.sum(Map.values(status_counts))
    if total > 0, do: converted / total, else: 0
  end

  defp calculate_interest_ratio(status_counts, total_participants) do
    interested = status_counts[:interested] || 0
    if total_participants > 0, do: interested / total_participants, else: 0
  end

  # LiveView Support Functions

  @doc """
  Gets a user's current participant status for an event.

  Returns the status atom or nil if not a participant.
  """
  def get_user_participant_status(%Event{} = event, %User{} = user) do
    case get_event_participant_by_event_and_user(event, user) do
      nil -> nil
      participant -> participant.status
    end
  end

  @doc """
  Updates a user's participant status for an event.

  If the user is not already a participant, creates a new participant record.
  If the user is already a participant, updates their status.
  """
  def update_user_participant_status(%Event{} = event, %User{} = user, status) do
    update_participant_status(event, user, status)
  end

  @doc """
  Removes a user's participant status for an event.

  Deletes the participant record entirely.
  """
  def remove_user_participant_status(%Event{} = event, %User{} = user) do
    case remove_participant_status(event, user) do
      {:ok, :removed} -> {:ok, :removed}
      {:ok, :not_participant} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Legacy wrapper functions for backward compatibility
  @doc """
  Legacy wrapper for mark_user_interested/2.
  Use update_participant_status/3 instead.
  """
  def mark_user_interested(%Event{} = event, %User{} = user) do
    update_participant_status(event, user, :interested)
  end

  @doc """
  Legacy wrapper for remove_user_interest/2.
  Use remove_participant_status/3 instead.
  """
  def remove_user_interest(%Event{} = event, %User{} = user) do
    remove_participant_status(event, user, :interested)
  end

  @doc """
  Legacy wrapper for user_is_interested?/2.
  Use user_has_status/3 instead.
  """
  def user_is_interested?(%Event{} = event, %User{} = user) do
    user_has_status?(event, user, :interested)
  end

  @doc """
  Legacy wrapper for get_user_interest_status/2.
  Returns participant status or :not_participant.
  """
  def get_user_interest_status(%Event{} = event, %User{} = user) do
    case get_event_participant_by_event_and_user(event, user) do
      %EventParticipant{status: status} -> status
      nil -> :not_participant
    end
  end

  @doc """
  Legacy wrapper for list_interested_users/1.
  Use list_participants_by_status/2 instead.
  """
  def list_interested_users(%Event{} = event) do
    list_participants_by_status(event, :interested)
    |> Enum.map(& &1.user)
  end

  @doc """
  Legacy wrapper for count_interested_users/1.
  Use count_participants_by_status/2 instead.
  """
  def count_interested_users(%Event{} = event) do
    count_participants_by_status(event, :interested)
  end

  @doc """
  Legacy wrapper for get_event_interest_stats/1.
  Use get_participant_analytics/1 instead.
  """
  def get_event_interest_stats(%Event{} = event) do
    analytics = get_participant_analytics(event)

    %{
      interested_count: analytics.status_counts.interested,
      total_participants: analytics.total_participants,
      interest_ratio: analytics.engagement_metrics.interest_ratio,
      conversion_potential: analytics.status_counts.interested
    }
  end

  # =================
  # Generic Polling System
  # =================

  @doc """
  Returns the list of polls for an event.
  """
  def list_polls(%Event{} = event) do
    ordered_options =
      from(po in PollOption,
        where: po.status == "active" and is_nil(po.deleted_at),
        order_by: [asc: po.order_index, asc: po.inserted_at],
        preload: [:suggested_by, :votes]
      )

    query =
      from(p in Poll,
        where: p.event_id == ^event.id and is_nil(p.deleted_at),
        order_by: [asc: p.order_index, asc: p.inserted_at],
        preload: [:created_by, poll_options: ^ordered_options]
      )

    Repo.all(query)
  end

  @doc """
  Counts the number of polls for a given event.

  This is more efficient than loading all polls just to count them.

  ## Examples

      iex> count_polls_for_event(event)
      5
  """
  def count_polls_for_event(%Event{} = event) do
    from(p in Poll, where: p.event_id == ^event.id and is_nil(p.deleted_at))
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns the list of active polls (not closed) for an event.
  """
  def list_active_polls(%Event{} = event) do
    query =
      from(p in Poll,
        where: p.event_id == ^event.id and p.phase != "closed",
        order_by: [asc: p.order_index, asc: p.inserted_at],
        preload: [:created_by]
      )

    polls = Repo.all(query)

    # Load poll options with proper ordering for each poll
    Enum.map(polls, fn poll ->
      poll_options_query =
        if poll.poll_type == "date_selection" do
          from(po in PollOption,
            where: po.poll_id == ^poll.id,
            order_by: [asc: fragment("
            CASE 
              WHEN ?->'date' IS NOT NULL THEN 
                CASE 
                  WHEN ?->>'date' ~ '^\\d{4}-\\d{2}-\\d{2}$' THEN (?->>'date')::date
                  ELSE '9999-12-31'::date
                END
              ELSE '9999-12-31'::date
            END
          ", po.metadata, po.metadata, po.metadata)],
            preload: [:suggested_by, :votes]
          )
        else
          from(po in PollOption,
            where: po.poll_id == ^poll.id,
            order_by: [asc: po.order_index],
            preload: [:suggested_by, :votes]
          )
        end

      poll_options = Repo.all(poll_options_query)
      Map.put(poll, :poll_options, poll_options)
    end)
  end

  @doc """
  Gets a single poll.

  Returns nil if poll not found.
  """
  def get_poll(id) do
    Repo.get(Poll, id)
  end

  @doc """
  Gets a single poll with poll_options preloaded for social card generation.

  Returns nil if poll not found.
  Preloads poll_options ordered by vote count (for social card display).
  """
  def get_poll_with_options(id) do
    poll = Repo.get(Poll, id)

    if poll do
      # Preload poll_options ordered by vote count (most popular first)
      # This ensures the social card shows the most relevant options
      poll_options_query =
        from(po in PollOption,
          where: po.poll_id == ^poll.id and po.status == "active",
          where: is_nil(po.deleted_at),
          left_join: v in assoc(po, :votes),
          group_by: po.id,
          order_by: [desc: count(v.id), asc: po.order_index],
          limit: 10
        )

      Repo.preload(poll, poll_options: poll_options_query)
    else
      nil
    end
  end

  @doc """
  Gets a single poll.

  Raises if poll not found.
  """
  def get_poll!(id) do
    poll = Repo.get!(Poll, id)

    # For date_selection polls, we need to order the options chronologically
    poll_options_query =
      if poll.poll_type == "date_selection" do
        from(po in PollOption,
          where: po.poll_id == ^poll.id,
          order_by: [asc: fragment("
          CASE 
            WHEN ?->'date' IS NOT NULL THEN 
              CASE 
                WHEN ?->>'date' ~ '^\\d{4}-\\d{2}-\\d{2}$' THEN (?->>'date')::date
                ELSE '9999-12-31'::date
              END
            ELSE '9999-12-31'::date
          END
        ", po.metadata, po.metadata, po.metadata)],
          preload: [:suggested_by, :votes]
        )
      else
        # For other poll types, use the regular order_index
        from(po in PollOption,
          where: po.poll_id == ^poll.id,
          order_by: [asc: po.order_index],
          preload: [:suggested_by, :votes]
        )
      end

    poll_options = Repo.all(poll_options_query)

    poll
    |> Repo.preload([:event, :created_by])
    |> Map.put(:poll_options, poll_options)
  end

  @doc """
  Gets a poll by its sequential number within an event.

  ## Examples

      iex> get_poll_by_number!(5, event_id)
      %Poll{number: 5}

      iex> get_poll_by_number!(999, event_id)
      ** (Ecto.NoResultsError)

  """
  def get_poll_by_number!(number, event_id) when is_integer(number) do
    poll =
      from(p in Poll,
        where: p.event_id == ^event_id and p.number == ^number,
        where: is_nil(p.deleted_at)
      )
      |> Repo.one!()

    # For date_selection polls, we need to order the options chronologically
    poll_options_query =
      if poll.poll_type == "date_selection" do
        from(po in PollOption,
          where: po.poll_id == ^poll.id,
          order_by: [
            asc:
              fragment(
                "
          CASE
            WHEN ?->'date' IS NOT NULL THEN
              CASE
                WHEN ?->>'date' ~ '^\\d{4}-\\d{2}-\\d{2}$' THEN (?->>'date')::date
                ELSE '9999-12-31'::date
              END
            ELSE '9999-12-31'::date
          END
        ",
                po.metadata,
                po.metadata,
                po.metadata
              )
          ],
          preload: [:suggested_by, :votes]
        )
      else
        # For other poll types, use the regular order_index
        from(po in PollOption,
          where: po.poll_id == ^poll.id,
          order_by: [asc: po.order_index],
          preload: [:suggested_by, :votes]
        )
      end

    poll_options = Repo.all(poll_options_query)

    poll
    |> Repo.preload([:event, :created_by])
    |> Map.put(:poll_options, poll_options)
  end

  @doc """
  Gets a poll by number for a specific event with options optimized for social card display.

  Returns nil if poll not found.
  Preloads poll_options ordered by vote count (for social card display).
  Matches semantics of get_poll_with_options/1.
  """
  def get_poll_with_options_by_number(number, event_id) when is_integer(number) do
    poll =
      from(p in Poll,
        where: p.event_id == ^event_id and p.number == ^number,
        where: is_nil(p.deleted_at)
      )
      |> Repo.one()

    if poll do
      # Preload poll_options ordered by vote count (most popular first)
      # This ensures the social card shows the most relevant options
      # Matches semantics of get_poll_with_options/1
      poll_options_query =
        from(po in PollOption,
          where: po.poll_id == ^poll.id and po.status == "active",
          where: is_nil(po.deleted_at),
          left_join: v in assoc(po, :votes),
          group_by: po.id,
          order_by: [desc: count(v.id), asc: po.order_index],
          limit: 10
        )

      Repo.preload(poll, poll_options: poll_options_query)
    else
      nil
    end
  end

  @doc """
  Gets a poll for a specific event and poll type.
  """
  def get_event_poll(%Event{} = event, poll_type, opts \\ []) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    query =
      from(p in Poll,
        join: e in Event,
        on: p.event_id == e.id,
        where: p.event_id == ^event.id and p.poll_type == ^poll_type
      )

    query =
      if include_deleted do
        query
      else
        from([p, e] in query,
          where: is_nil(e.deleted_at) and is_nil(p.deleted_at)
        )
      end

    ordered_options =
      from(po in PollOption,
        where: po.status == "active" and is_nil(po.deleted_at),
        order_by: [asc: po.order_index, asc: po.inserted_at],
        preload: [:suggested_by, :votes]
      )

    query =
      from([p, e] in query,
        preload: [:created_by, poll_options: ^ordered_options]
      )

    Repo.one(query)
  end

  @doc """
  Creates a poll.
  """
  def create_poll(attrs \\ %{}) do
    result =
      %Poll{}
      |> Poll.creation_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, poll} ->
        # Track poll creation analytics
        # The created_by_id is already set in the poll from the changeset
        if poll.created_by_id do
          metadata = %{
            event_id: poll.event_id,
            poll_type: poll.voting_system,
            # New polls don't have options yet
            options_count: 0,
            # All users must be authenticated - no anonymous functionality
            is_anonymous: false
          }

          Eventasaurus.Services.PollAnalyticsService.track_poll_created(
            to_string(poll.created_by_id),
            to_string(poll.id),
            metadata
          )
        end

        {:ok, poll}

      error ->
        error
    end
  end

  @doc """
  Updates a poll.
  """
  def update_poll(%Poll{} = poll, attrs) do
    poll
    |> Poll.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the privacy settings for a poll.
  """
  def update_poll_privacy(%Poll{} = poll, privacy_settings) do
    poll
    |> Poll.privacy_changeset(privacy_settings)
    |> Repo.update()
  end

  @doc """
  Reorders polls within an event.

  ## Examples
      
      iex> reorder_polls(event_id, [%{poll_id: 1, order_index: 0}, %{poll_id: 2, order_index: 1}])
      {:ok, [%Poll{}, %Poll{}]}
  """
  def reorder_polls(event_id, poll_orders) when is_list(poll_orders) do
    result =
      Repo.transaction(fn ->
        # Get all polls for the event to verify they belong to it
        polls_query =
          from(p in Poll,
            where: p.event_id == ^event_id,
            select: %{id: p.id}
          )

        valid_poll_ids =
          polls_query
          |> lock("FOR UPDATE")
          |> Repo.all()
          |> Enum.map(& &1.id)
          |> MapSet.new()

        # Validate all poll_ids in the request belong to this event
        requested_poll_ids = Enum.map(poll_orders, & &1.poll_id)

        # Check for duplicates first
        if length(Enum.uniq(requested_poll_ids)) != length(requested_poll_ids) do
          Repo.rollback(:duplicate_poll_ids)
        else
          # Validate all poll_ids belong to this event
          if Enum.all?(requested_poll_ids, fn id -> MapSet.member?(valid_poll_ids, id) end) do
            # Bulk-load all polls to avoid N+1 queries
            polls_by_id =
              from(p in Poll, where: p.event_id == ^event_id and p.id in ^requested_poll_ids)
              |> lock("FOR UPDATE")
              |> Repo.all()
              |> Map.new(&{&1.id, &1})

            # Update each poll's order_index and stop on first error
            case Enum.reduce_while(poll_orders, {:ok, []}, fn %{
                                                                poll_id: poll_id,
                                                                order_index: new_index
                                                              },
                                                              {:ok, acc} ->
                   case Map.fetch(polls_by_id, poll_id) do
                     :error ->
                       {:halt, Repo.rollback(:invalid_poll_ids)}

                     {:ok, poll} ->
                       case poll |> Poll.order_changeset(new_index) |> Repo.update() do
                         {:ok, updated} ->
                           {:cont, {:ok, [updated | acc]}}

                         {:error, changeset} ->
                           {:halt, Repo.rollback({:update_failed, changeset})}
                       end
                   end
                 end) do
              {:ok, updated} -> Enum.reverse(updated)
              other -> other
            end
          else
            Repo.rollback(:invalid_poll_ids)
          end
        end
      end)

    # Broadcast the reordering if successful
    case result do
      {:ok, updated_polls} ->
        EventasaurusWeb.Services.PollPubSubService.broadcast_polls_reordered(
          event_id,
          updated_polls
        )

        {:ok, updated_polls}

      error ->
        error
    end
  end

  @doc """
  Transitions a poll to a new phase.
  """
  def transition_poll_phase(%Poll{} = poll, new_phase) do
    poll
    |> Poll.phase_transition_changeset(new_phase)
    |> Repo.update()
  end

  @doc """
  Finalizes a poll with selected options.
  """
  def finalize_poll(%Poll{} = poll, option_ids, finalized_date \\ nil) do
    with {:ok, updated_poll} <-
           poll
           |> Poll.finalization_changeset(option_ids, finalized_date)
           |> Repo.update() do
      # Create activity if this is a supported poll type and has winning options
      if option_ids != [] and
           updated_poll.poll_type in ["movie", "game", "places", "venue_selection"] do
        # Get the first winning option (for now, support single winner)
        winning_option_id = List.first(option_ids)

        if winning_option_id do
          # Use the poll's event creator as the activity creator
          updated_poll = Repo.preload(updated_poll, [:event, :created_by])

          case create_activity_from_poll(
                 updated_poll,
                 winning_option_id,
                 updated_poll.created_by_id
               ) do
            {:ok, _activity} ->
              :ok

            {:error, reason} ->
              require Logger

              Logger.warning("Failed to create activity from poll finalization",
                poll_id: updated_poll.id,
                option_id: winning_option_id,
                reason: inspect(reason)
              )
          end
        end
      end

      {:ok, updated_poll}
    end
  end

  @doc """
  Deletes a poll.
  """
  def delete_poll(%Poll{} = poll) do
    Repo.delete(poll)
  end

  # =================
  # Poll Options
  # =================

  @doc """
  Returns the list of options for a poll.
  """
  def list_poll_options(%Poll{} = poll) do
    query =
      from(po in PollOption,
        where: po.poll_id == ^poll.id and po.status == "active",
        order_by: [asc: po.order_index, asc: po.inserted_at],
        preload: [:suggested_by, :votes]
      )

    Repo.all(query)
  end

  @doc """
  Returns all options for a poll (including hidden/removed).
  """
  def list_all_poll_options(%Poll{} = poll) do
    query =
      from(po in PollOption,
        where: po.poll_id == ^poll.id,
        order_by: [asc: po.order_index, asc: po.inserted_at],
        preload: [:suggested_by, :votes]
      )

    Repo.all(query)
  end

  @doc """
  Returns poll options by their IDs with specified preloads.
  Only returns active options and filters out any missing records safely.
  """
  def list_poll_options_by_ids(option_ids, preloads \\ []) when is_list(option_ids) do
    query =
      from(po in PollOption,
        where: po.id in ^option_ids and po.status == "active",
        order_by: [asc: po.order_index, asc: po.inserted_at],
        preload: ^preloads
      )

    Repo.all(query)
  end

  @doc """
  Gets a single poll option.
  """
  def get_poll_option!(id) do
    Repo.get!(PollOption, id)
    |> Repo.preload([:poll, :suggested_by, :votes])
  end

  @doc """
  Gets a single poll option, returns nil if not found.
  """
  def get_poll_option(id) do
    case Repo.get(PollOption, id) do
      nil -> nil
      option -> Repo.preload(option, [:poll, :suggested_by, :votes])
    end
  end

  @doc """
  Creates a poll option.
  """
  def create_poll_option(attrs \\ %{}, opts \\ []) do
    # Normalize attrs to handle both string and atom keys
    poll_id = attrs["poll_id"] || attrs[:poll_id]
    raw_title = attrs["title"] || attrs[:title]
    suggested_by_id = attrs["suggested_by_id"] || attrs[:suggested_by_id]

    # Extract title string - handle case where attrs might be improperly nested
    title =
      cond do
        is_binary(raw_title) ->
          raw_title

        is_map(raw_title) and (raw_title["title"] || raw_title[:title]) ->
          raw_title["title"] || raw_title[:title]

        true ->
          nil
      end

    # Extract place_id from external_data if it's a place
    place_id =
      case attrs["external_data"] || attrs[:external_data] do
        data when is_map(data) -> data["place_id"] || data[:place_id]
        _ -> nil
      end

    # Auto-assign order_index if not provided (new items go to top)
    attrs_with_order =
      if is_nil(attrs["order_index"]) && is_nil(attrs[:order_index]) && poll_id do
        max_order_index =
          from(po in PollOption,
            where: po.poll_id == ^poll_id,
            select: max(po.order_index)
          )
          |> Repo.one()

        # If there are no existing options, start at 0, otherwise use max + 1
        new_order_index = if max_order_index, do: max_order_index + 1, else: 0

        # Normalize the attrs map format and add order_index
        if is_map(attrs) && Map.has_key?(attrs, "poll_id") do
          Map.put(attrs, "order_index", new_order_index)
        else
          Map.put(attrs, :order_index, new_order_index)
        end
      else
        attrs
      end

    # Check for duplicates using place_id (for places) or title (for non-places)
    if poll_id && title && suggested_by_id do
      case check_duplicate_option(poll_id, title, place_id, suggested_by_id) do
        {:ok, :unique} ->
          result =
            %PollOption{}
            |> PollOption.creation_changeset(attrs_with_order, opts)
            |> Repo.insert()

          case result do
            {:ok, option} ->
              # Track poll suggestion analytics if it's a user suggestion
              if suggested_by_id do
                poll = get_poll!(poll_id)

                metadata = %{
                  event_id: poll.event_id,
                  poll_type: poll.voting_system,
                  option_title: option.title,
                  # New suggestions are not approved yet
                  is_approved: false
                }

                Eventasaurus.Services.PollAnalyticsService.track_poll_suggestion_created(
                  to_string(suggested_by_id),
                  to_string(poll_id),
                  to_string(option.id),
                  metadata
                )
              end

              {:ok, option}

            error ->
              error
          end

        {:error, :duplicate_by_same_user} ->
          changeset =
            %PollOption{}
            |> PollOption.creation_changeset(attrs_with_order, opts)
            |> add_error(:title, "You have already suggested this option")

          {:error, changeset}

        {:error, :duplicate_by_other_user} ->
          changeset =
            %PollOption{}
            |> PollOption.creation_changeset(attrs_with_order, opts)
            |> add_error(:title, "This option has already been suggested by another user")

          {:error, changeset}

        {:error, error_message} when is_binary(error_message) ->
          changeset =
            %PollOption{}
            |> PollOption.creation_changeset(attrs_with_order, opts)
            |> add_error(:base, error_message)

          {:error, changeset}
      end
    else
      %PollOption{}
      |> PollOption.creation_changeset(attrs, opts)
      |> Repo.insert()
    end
  end

  # Helper function to check for duplicate options by place_id (for places) or title (for non-places)
  defp check_duplicate_option(poll_id, title, place_id, current_user_id) do
    # Safely convert poll_id and current_user_id to integers
    with {:ok, poll_id_int} <- safe_to_integer(poll_id, :poll_id),
         {:ok, user_id_int} <- safe_to_integer(current_user_id, :user_id) do
      # Build the query based on whether we have a non-empty (trimmed) place_id
      trimmed_place_id =
        case place_id do
          id when is_binary(id) -> String.trim(id)
          _ -> nil
        end

      place_id_valid = is_binary(trimmed_place_id) and byte_size(trimmed_place_id) > 0

      query =
        if place_id_valid do
          # For places, check only by place_id (title-agnostic)
          from(po in PollOption,
            where:
              po.poll_id == ^poll_id_int and
                po.status == "active" and
                is_nil(po.deleted_at) and
                fragment("?->>'place_id' = ?", po.external_data, ^trimmed_place_id)
          )
        else
          # For non-places, check by case-insensitive title per user
          downcased = String.downcase(String.trim(to_string(title || "")))

          from(po in PollOption,
            where:
              po.poll_id == ^poll_id_int and
                po.suggested_by_id == ^user_id_int and
                fragment("lower(?) = ?", po.title, ^downcased) and
                po.status == "active" and
                is_nil(po.deleted_at)
          )
        end

      case Repo.one(query) do
        nil ->
          {:ok, :unique}

        %PollOption{suggested_by_id: ^user_id_int} ->
          {:error, :duplicate_by_same_user}

        %PollOption{suggested_by_id: _other_user_id} ->
          {:error, :duplicate_by_other_user}
      end
    else
      {:error, :invalid_poll_id} ->
        {:error, "Invalid poll ID provided"}

      {:error, :invalid_user_id} ->
        {:error, "Invalid user ID provided"}
    end
  end

  # Helper function for safe integer conversion
  defp safe_to_integer(value, field_type) do
    case value do
      nil ->
        {:error, :"invalid_#{field_type}"}

      id when is_integer(id) ->
        {:ok, id}

      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed_int, ""} -> {:ok, parsed_int}
          _ -> {:error, :"invalid_#{field_type}"}
        end

      _ ->
        {:error, :"invalid_#{field_type}"}
    end
  end

  @doc """
  Count active poll options for a specific user in a poll.
  This queries the database directly to ensure accurate counts.
  """
  @spec count_user_poll_suggestions(integer() | String.t(), integer() | String.t()) ::
          non_neg_integer()
  def count_user_poll_suggestions(poll_id, user_id) do
    {poll_id_int, user_id_int} =
      case {safe_to_integer(poll_id, :poll_id), safe_to_integer(user_id, :user_id)} do
        {{:ok, p}, {:ok, u}} -> {p, u}
        {{:error, _}, _} -> raise ArgumentError, "invalid poll_id"
        {_, {:error, _}} -> raise ArgumentError, "invalid user_id"
      end

    from(po in PollOption,
      where:
        po.poll_id == ^poll_id_int and
          po.suggested_by_id == ^user_id_int and
          po.status == "active" and
          is_nil(po.deleted_at)
    )
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Updates a poll option.
  """
  def update_poll_option(%PollOption{} = poll_option, attrs, opts \\ []) do
    # Check if this is a suggestion approval (status changing to active)
    was_active = poll_option.status == "active"

    result =
      poll_option
      |> PollOption.changeset(attrs, opts)
      |> Repo.update()

    case result do
      {:ok, updated_option} ->
        # Track suggestion approval if status changed to active
        is_now_active = updated_option.status == "active"

        if !was_active && is_now_active && updated_option.suggested_by_id do
          # Use get_poll instead of get_poll! to avoid crashes
          case get_poll(updated_option.poll_id) do
            nil ->
              # Poll was deleted, skip analytics
              :ok

            poll ->
              approver_id = Map.get(opts, :approver_id) || Map.get(opts, :current_user_id)

              if approver_id do
                metadata = %{
                  event_id: poll.event_id,
                  poll_type: poll.voting_system,
                  option_title: updated_option.title,
                  suggested_by_id: updated_option.suggested_by_id
                }

                Eventasaurus.Services.PollAnalyticsService.track_poll_suggestion_approved(
                  to_string(approver_id),
                  to_string(updated_option.poll_id),
                  to_string(updated_option.id),
                  metadata
                )
              end
          end
        end

        {:ok, updated_option}

      error ->
        error
    end
  end

  @doc """
  Updates a poll option status (for moderation).
  """
  def update_poll_option_status(%PollOption{} = poll_option, status) do
    poll_option
    |> PollOption.status_changeset(status)
    |> Repo.update()
  end

  @doc """
  Enriches a poll option with external API data.
  """
  def enrich_poll_option(%PollOption{} = poll_option, external_data) do
    poll_option
    |> PollOption.enrichment_changeset(external_data)
    |> Repo.update()
  end

  @doc """
  Reorders poll options by moving a dragged option relative to a target option.

  ## Parameters
  - dragged_option_id: ID of the option being moved
  - target_option_id: ID of the option to position relative to
  - direction: "before" or "after" - where to position the dragged option

  ## Returns
  - {:ok, updated_poll} on success
  - {:error, reason} on failure
  """
  def reorder_poll_option(dragged_option_id, target_option_id, direction)
      when direction in ["before", "after"] do
    Repo.transaction(fn ->
      # Get both options and validate they exist and belong to the same poll
      dragged_option = Repo.get!(PollOption, dragged_option_id)
      target_option = Repo.get!(PollOption, target_option_id)

      if dragged_option.poll_id != target_option.poll_id do
        Repo.rollback("Options belong to different polls")
      end

      # Get all poll options ordered by current order_index
      all_options =
        from(po in PollOption,
          where: po.poll_id == ^dragged_option.poll_id,
          order_by: [asc: po.order_index, asc: po.id]
        )
        |> Repo.all()

      # Calculate new order indices
      {new_orders, updated_count} =
        calculate_new_order_indices(all_options, dragged_option, target_option, direction)

      # Update the order indices in the database
      if updated_count > 0 do
        Enum.each(new_orders, fn {option_id, new_index} ->
          from(po in PollOption, where: po.id == ^option_id)
          |> Repo.update_all(set: [order_index: new_index])
        end)
      end

      # Return the updated poll with preloaded options
      updated_poll = get_poll!(dragged_option.poll_id)
      updated_poll
    end)
  rescue
    Ecto.NoResultsError ->
      {:error, "Option not found"}
  end

  # Helper function to calculate new order indices
  defp calculate_new_order_indices(all_options, dragged_option, target_option, direction) do
    # Remove dragged option from the list
    other_options = Enum.reject(all_options, &(&1.id == dragged_option.id))

    # Find target position in the filtered list
    target_index = Enum.find_index(other_options, &(&1.id == target_option.id))

    if target_index == nil do
      {[], 0}
    else
      insert_index = if direction == "after", do: target_index + 1, else: target_index

      # Insert dragged option at new position
      new_ordered_options = List.insert_at(other_options, insert_index, dragged_option)
      max_index = length(new_ordered_options) - 1

      # For desc display, highest index should render first
      new_orders =
        new_ordered_options
        |> Enum.with_index()
        |> Enum.filter(fn {option, new_index} ->
          option.order_index != max_index - new_index
        end)
        |> Enum.map(fn {option, new_index} ->
          {option.id, max_index - new_index}
        end)

      {new_orders, length(new_orders)}
    end
  end

  @doc """
  Deletes a poll option.
  """
  def delete_poll_option(%PollOption{} = poll_option) do
    Repo.delete(poll_option)
  end

  @doc """
  Checks if a user can delete their own poll suggestion within the 5-minute window.

  Returns true if:
  - The user is the one who suggested the option
  - The option was created less than 5 minutes ago
  """
  def can_delete_own_suggestion?(%PollOption{} = poll_option, %User{} = user) do
    poll_option.suggested_by_id == user.id &&
      NaiveDateTime.diff(NaiveDateTime.utc_now(), poll_option.inserted_at, :second) < 300
  end

  def can_delete_own_suggestion?(_, _), do: false

  @doc """
  Checks if a user can delete their own poll option based on the poll's configured removal settings.

  Returns true if:
  - The user is the one who suggested the option
  - The poll's removal strategy allows deletion (not "disabled")
  - For "time_based" strategy: option was created within the configured time limit
  - For "vote_based" strategy: no votes have been cast on this option
  """
  def can_delete_option_based_on_poll_settings?(%PollOption{} = poll_option, %User{} = user) do
    with %Poll{} = poll <- get_poll(poll_option.poll_id) do
      # User must be the one who suggested the option
      if poll_option.suggested_by_id == user.id do
        check_removal_strategy_allows_deletion?(poll, poll_option)
      else
        false
      end
    else
      _ -> false
    end
  end

  def can_delete_option_based_on_poll_settings?(_, _), do: false

  # Private helper to check if poll strategy allows deletion
  defp check_removal_strategy_allows_deletion?(%Poll{} = poll, %PollOption{} = poll_option) do
    case Poll.get_option_removal_strategy(poll) do
      "disabled" ->
        false

      "time_based" ->
        time_limit_minutes = Poll.get_option_removal_time_limit(poll)

        time_limit_seconds =
          if is_integer(time_limit_minutes) and time_limit_minutes > 0,
            do: time_limit_minutes * 60,
            else: 0

        NaiveDateTime.diff(NaiveDateTime.utc_now(), poll_option.inserted_at, :second) <
          time_limit_seconds

      "vote_based" ->
        # Check if any votes exist on this option
        vote_count =
          from(v in PollVote, where: v.poll_option_id == ^poll_option.id)
          |> Repo.aggregate(:count, :id)

        vote_count == 0

      _ ->
        false
    end
  end

  # =================
  # Date Selection Poll Options
  # =================

  @doc """
  Creates a date-based poll option for date_selection polls.

  ## Parameters
  - poll: The poll to add the date option to (must be poll_type: "date_selection")
  - user: The user suggesting the date
  - date: Date as string (ISO 8601), Date struct, or DateTime struct
  - opts: Optional parameters with keys:
    - :title - Custom title for the date option (defaults to formatted date)
    - :description - Optional description for the date option

  ## Returns
  - {:ok, poll_option} on success
  - {:error, changeset} on failure

  ## Examples
      iex> create_date_poll_option(poll, user, "2024-12-25")
      {:ok, %PollOption{}}

      iex> create_date_poll_option(poll, user, ~D[2024-12-25], title: "Christmas Day")
      {:ok, %PollOption{}}
  """
  def create_date_poll_option(
        %Poll{poll_type: "date_selection"} = poll,
        %User{} = user,
        date,
        opts \\ []
      ) do
    alias EventasaurusApp.Events.DateMetadata

    # Use the new DateMetadata.build_date_metadata function for proper structure
    try do
      metadata = DateMetadata.build_date_metadata(date, opts)

      # Use custom title or generate from date
      parsed_date =
        case date do
          %Date{} = d -> d
          date_string -> Date.from_iso8601!(date_string)
        end

      title = Keyword.get(opts, :title, format_date_for_display(parsed_date))
      description = Keyword.get(opts, :description)

      attrs = %{
        "poll_id" => poll.id,
        "suggested_by_id" => user.id,
        "title" => title,
        "description" => description,
        "metadata" => metadata,
        "status" => "active"
      }

      # The PollOption changeset will now validate the metadata structure
      create_poll_option(attrs, poll_type: "date_selection")
    rescue
      e in ArgumentError ->
        changeset =
          PollOption.changeset(%PollOption{}, %{}, poll_type: "date_selection")
          |> Ecto.Changeset.add_error(:metadata, "Invalid date: #{e.message}")

        {:error, changeset}
    end
  end

  @doc """
  Creates multiple date-based poll options from a date range.

  ## Parameters
  - poll: The poll to add date options to (must be poll_type: "date_selection")
  - user: The user suggesting the dates
  - start_date: Start date (string, Date, or DateTime)
  - end_date: End date (string, Date, or DateTime)
  - opts: Optional parameters (same as create_date_poll_option/4)

  ## Returns
  - {:ok, [poll_options]} on success for all dates
  - {:error, reason} on failure
  """
  def create_date_range_poll_options(
        %Poll{poll_type: "date_selection"} = poll,
        %User{} = user,
        start_date,
        end_date,
        opts \\ []
      ) do
    with {:ok, parsed_start} <- parse_date_input(start_date),
         {:ok, parsed_end} <- parse_date_input(end_date),
         :ok <- validate_date_range(parsed_start, parsed_end) do
      date_range = Date.range(parsed_start, parsed_end)

      Repo.transaction(fn ->
        Enum.map(date_range, fn date ->
          case create_date_poll_option(poll, user, date, opts) do
            {:ok, option} -> option
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
      end)
    end
  end

  @doc """
  Creates multiple date-based poll options from a list of dates.

  ## Parameters
  - poll: The poll to add date options to (must be poll_type: "date_selection")
  - user: The user suggesting the dates
  - dates: List of dates (strings, Date structs, or DateTime structs)
  - opts: Optional parameters (same as create_date_poll_option/4)

  ## Returns
  - {:ok, [poll_options]} on success for all dates
  - {:error, reason} on failure
  """
  def create_date_list_poll_options(
        %Poll{poll_type: "date_selection"} = poll,
        %User{} = user,
        dates,
        opts \\ []
      )
      when is_list(dates) do
    Repo.transaction(fn ->
      Enum.map(dates, fn date ->
        case create_date_poll_option(poll, user, date, opts) do
          {:ok, option} -> option
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Gets all date options for a date_selection poll, sorted by date.

  ## Returns
  List of poll options with parsed dates in chronological order.
  """
  def list_date_poll_options(%Poll{poll_type: "date_selection"} = poll) do
    poll
    |> list_poll_options()
    |> Enum.filter(&has_date_metadata?/1)
    |> sort_date_options_by_date()
  end

  @doc """
  Updates a date poll option with a new date.

  ## Parameters
  - poll_option: The poll option to update
  - new_date: New date (string, Date, or DateTime)
  - opts: Optional parameters for title/description updates
  """
  def update_date_poll_option(%PollOption{} = poll_option, new_date, opts \\ []) do
    alias EventasaurusApp.Events.DateMetadata

    try do
      # Build new metadata using the validated structure
      new_metadata =
        DateMetadata.build_date_metadata(
          new_date,
          [
            created_at:
              get_in(poll_option.metadata, ["created_at"]) ||
                DateTime.utc_now() |> DateTime.to_iso8601()
          ] ++ opts
        )

      # Extract parsed date from metadata instead of redundantly parsing
      parsed_date =
        case new_metadata do
          %{"date" => date_string} when is_binary(date_string) ->
            Date.from_iso8601!(date_string)

          _ ->
            # Fallback: parse the original input if metadata doesn't contain expected format
            case new_date do
              %Date{} = d -> d
              date_string -> Date.from_iso8601!(date_string)
            end
        end

      # Update title if provided, otherwise use new date display
      attrs = %{
        "metadata" => new_metadata,
        "title" => Keyword.get(opts, :title, format_date_for_display(parsed_date))
      }

      # Add description if provided
      attrs =
        if description = Keyword.get(opts, :description) do
          Map.put(attrs, "description", description)
        else
          attrs
        end

      # The PollOption changeset will validate the new metadata structure
      update_poll_option(poll_option, attrs, poll_type: "date_selection")
    rescue
      e in ArgumentError ->
        changeset =
          PollOption.changeset(poll_option, %{}, poll_type: "date_selection")
          |> Ecto.Changeset.add_error(:metadata, "Invalid date: #{e.message}")

        {:error, changeset}
    end
  end

  @doc """
  Extracts the date from a date poll option's metadata.

  ## Returns
  - {:ok, %Date{}} on success
  - {:error, reason} if no valid date found
  """
  def get_date_from_poll_option(%PollOption{metadata: nil}), do: {:error, "No metadata found"}

  def get_date_from_poll_option(%PollOption{metadata: metadata}) do
    case Map.get(metadata, "date") do
      nil ->
        {:error, "No date found in metadata"}

      date_string when is_binary(date_string) ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> {:ok, date}
          {:error, _} -> {:error, "Invalid date format in metadata"}
        end

      _ ->
        {:error, "Date metadata is not a string"}
    end
  end

  # Private helper functions for date poll options

  defp parse_date_input(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} -> {:ok, parsed_date}
      {:error, _} -> {:error, "Invalid date format. Use YYYY-MM-DD format."}
    end
  end

  defp parse_date_input(%Date{} = date), do: {:ok, date}

  defp parse_date_input(%DateTime{} = datetime) do
    {:ok, DateTime.to_date(datetime)}
  end

  defp parse_date_input(%NaiveDateTime{} = naive_datetime) do
    {:ok, NaiveDateTime.to_date(naive_datetime)}
  end

  defp parse_date_input(_), do: {:error, "Invalid date input type"}

  defp format_date_for_display(%Date{} = date) do
    # Format as "December 25, 2024" (without day name to match existing dates)
    Calendar.strftime(date, "%B %-d, %Y")
  end

  defp validate_date_range(%Date{} = start_date, %Date{} = end_date) do
    case Date.compare(start_date, end_date) do
      :gt -> {:error, "Start date must be before or equal to end date"}
      _ -> :ok
    end
  end

  defp has_date_metadata?(%PollOption{metadata: nil}), do: false

  defp has_date_metadata?(%PollOption{metadata: metadata}) do
    Map.has_key?(metadata, "date") && is_binary(Map.get(metadata, "date"))
  end

  defp sort_date_options_by_date(options) do
    options
    |> Enum.sort_by(
      fn option ->
        case get_date_from_poll_option(option) do
          {:ok, date} -> date
          # Put invalid dates at the end
          {:error, _} -> ~D[9999-12-31]
        end
      end,
      Date
    )
  end

  @doc """
  Validates existing date poll options for metadata compliance.

  This function can be used during migration to identify and fix
  any existing poll options that don't meet the new validation standards.
  """
  def validate_existing_date_poll_options(poll_id) do
    query =
      from(po in PollOption,
        join: p in Poll,
        on: po.poll_id == p.id,
        where: p.id == ^poll_id and p.poll_type == "date_selection",
        preload: [:poll]
      )

    options = Repo.all(query)

    results =
      Enum.map(options, fn option ->
        case EventasaurusWeb.Adapters.DatePollAdapter.validate_date_metadata(option) do
          {:ok, _} -> {:valid, option, nil}
          {:error, reason} -> {:invalid, option, reason}
        end
      end)

    valid_count = Enum.count(results, fn {status, _, _} -> status == :valid end)
    invalid_results = Enum.filter(results, fn {status, _, _} -> status == :invalid end)

    %{
      total: length(results),
      valid: valid_count,
      invalid: length(invalid_results),
      invalid_options: invalid_results
    }
  end

  @doc """
  Attempts to fix invalid date metadata for existing poll options.

  This function tries to reconstruct valid metadata from existing data
  for options that don't meet the new validation standards.
  """
  def fix_invalid_date_metadata(%PollOption{} = option) do
    alias EventasaurusApp.Events.DateMetadata

    # Try to extract date from existing metadata or title
    date_result =
      case option.metadata do
        %{"date" => date_string} when is_binary(date_string) ->
          Date.from_iso8601(date_string)

        _ ->
          # Try to parse from title (legacy format)
          if option.title && Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, option.title) do
            Date.from_iso8601(option.title)
          else
            {:error, "No valid date found"}
          end
      end

    case date_result do
      {:ok, date} ->
        # Build properly structured metadata
        valid_metadata =
          DateMetadata.build_date_metadata(date,
            created_at:
              get_in(option.metadata, ["created_at"]) ||
                option.inserted_at |> DateTime.to_iso8601(),
            updated_at:
              get_in(option.metadata, ["updated_at"]) ||
                option.updated_at |> DateTime.to_iso8601()
          )

        update_poll_option(option, %{"metadata" => valid_metadata}, poll_type: "date_selection")

      {:error, reason} ->
        {:error, "Cannot fix metadata: #{reason}"}
    end
  end

  @doc """
  Batch validates and fixes all date poll options in the system.

  This is a migration helper function to ensure all existing data
  meets the new validation requirements.
  """
  def migrate_all_date_poll_metadata do
    # Find all date_selection polls
    date_polls = from(p in Poll, where: p.poll_type == "date_selection") |> Repo.all()

    results =
      Enum.map(date_polls, fn poll ->
        validation_result = validate_existing_date_poll_options(poll.id)

        fixed_count =
          if validation_result.invalid > 0 do
            # Attempt to fix invalid options
            fixed =
              validation_result.invalid_options
              |> Enum.map(fn {:invalid, option, _reason} ->
                case fix_invalid_date_metadata(option) do
                  {:ok, _} -> :fixed
                  {:error, _} -> :failed
                end
              end)
              |> Enum.count(&(&1 == :fixed))

            fixed
          else
            0
          end

        %{
          poll_id: poll.id,
          validation_result: validation_result,
          fixed_count: fixed_count
        }
      end)

    %{
      polls_processed: length(results),
      results: results
    }
  end

  # =================
  # Poll Votes
  # =================

  @doc """
  Returns the list of votes for a poll option.
  """
  def list_poll_votes(%PollOption{} = poll_option) do
    query =
      from(pv in PollVote,
        where: pv.poll_option_id == ^poll_option.id,
        order_by: [desc: pv.voted_at],
        preload: [:voter]
      )

    Repo.all(query)
  end

  @doc """
  Returns the votes for a poll option by a specific user.
  """
  def get_user_poll_vote(%PollOption{} = poll_option, %User{} = user) do
    query =
      from(pv in PollVote,
        where: pv.poll_option_id == ^poll_option.id and pv.voter_id == ^user.id,
        preload: [:voter]
      )

    Repo.one(query)
  end

  @doc """
  Returns all votes by a user for a poll.
  Returns an empty list if user is nil or not a valid User struct.
  """
  def list_user_poll_votes(%Poll{} = poll, %User{} = user) do
    query =
      from(pv in PollVote,
        join: po in PollOption,
        on: pv.poll_option_id == po.id,
        where: po.poll_id == ^poll.id and pv.voter_id == ^user.id,
        preload: [:poll_option, :voter]
      )

    Repo.all(query)
  end

  # Catch-all clause for nil or invalid user - return empty list
  def list_user_poll_votes(%Poll{}, _user), do: []

  @doc """
  Creates a vote based on voting system.
  """
  def create_poll_vote(poll_option, user, vote_data, voting_system) do
    # Get the poll_id from the poll_option
    poll_option_with_poll = Repo.preload(poll_option, :poll)

    # Handle the case where the poll association is nil
    case poll_option_with_poll.poll do
      nil ->
        # Return a proper changeset error instead of string
        changeset =
          PollVote.changeset(%PollVote{}, %{})
          |> Ecto.Changeset.add_error(:poll_id, "Poll not found for this option")

        {:error, changeset}

      poll ->
        attrs =
          Map.merge(vote_data, %{
            poll_option_id: poll_option.id,
            voter_id: user.id,
            poll_id: poll.id
          })

        changeset =
          case voting_system do
            "binary" -> PollVote.binary_vote_changeset(%PollVote{}, attrs)
            "approval" -> PollVote.approval_vote_changeset(%PollVote{}, attrs)
            "ranked" -> PollVote.ranked_vote_changeset(%PollVote{}, attrs)
            "star" -> PollVote.star_vote_changeset(%PollVote{}, attrs)
            _ -> PollVote.changeset(%PollVote{}, attrs)
          end

        case Repo.insert(changeset) do
          {:ok, vote} ->
            # Invalidate cache for performance
            EventasaurusApp.Events.PollStatsCache.invalidate(poll.id)

            # Track poll vote analytics
            metadata = %{
              event_id: poll.event_id,
              poll_type: voting_system,
              vote_value: Map.get(vote_data, :vote_value) || Map.get(vote_data, "vote_value"),
              rank: Map.get(vote_data, :vote_rank) || Map.get(vote_data, "vote_rank"),
              rating:
                if(
                  vote_numeric =
                    Map.get(vote_data, :vote_numeric) || Map.get(vote_data, "vote_numeric"),
                  do: Decimal.to_float(vote_numeric),
                  else: nil
                )
            }

            Eventasaurus.Services.PollAnalyticsService.track_poll_vote(
              to_string(user.id),
              to_string(poll.id),
              to_string(poll_option.id),
              voting_system,
              metadata
            )

            {:ok, vote}

          error ->
            error
        end
    end
  end

  @doc """
  Updates a poll vote.
  """
  def update_poll_vote(%PollVote{} = poll_vote, attrs) do
    poll_vote
    |> PollVote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a poll vote.
  """
  def delete_poll_vote(%PollVote{} = poll_vote) do
    # Load the poll to enable broadcasting
    poll_vote = Repo.preload(poll_vote, poll_option: :poll)
    poll = poll_vote.poll_option.poll

    case Repo.delete(poll_vote) do
      {:ok, deleted_vote} ->
        # Invalidate cache for performance
        EventasaurusApp.Events.PollStatsCache.invalidate(poll.id)
        # Broadcast updates after successful deletion
        broadcast_poll_update(poll, :votes_updated)
        broadcast_poll_stats_update(poll)
        {:ok, deleted_vote}

      error ->
        error
    end
  end

  # =================
  # Poll Analytics
  # =================

  @doc """
  Gets vote counts and statistics for a poll.
  """
  def get_poll_analytics(%Poll{} = poll) do
    poll_with_options = Repo.preload(poll, poll_options: :votes)

    vote_counts =
      poll_with_options.poll_options
      |> Enum.map(fn option ->
        votes = option.votes
        total_votes = length(votes)

        vote_breakdown =
          case poll.voting_system do
            "binary" -> count_binary_votes(votes)
            "approval" -> %{selected: total_votes}
            "ranked" -> count_ranked_votes(votes)
            "star" -> count_star_votes(votes)
          end

        %{
          option_id: option.id,
          option_title: option.title,
          total_votes: total_votes,
          vote_breakdown: vote_breakdown,
          average_score: calculate_average_score(votes)
        }
      end)

    %{
      poll_id: poll.id,
      poll_title: poll.title,
      voting_system: poll.voting_system,
      phase: poll.phase,
      total_options: length(poll_with_options.poll_options),
      vote_counts: vote_counts,
      total_voters: count_unique_voters(poll_with_options)
    }
  end

  # Helper functions for vote counting
  defp count_binary_votes(votes) do
    Enum.reduce(votes, %{yes: 0, maybe: 0, no: 0}, fn vote, acc ->
      case vote.vote_value do
        "yes" -> %{acc | yes: acc.yes + 1}
        "maybe" -> %{acc | maybe: acc.maybe + 1}
        "no" -> %{acc | no: acc.no + 1}
        _ -> acc
      end
    end)
  end

  defp count_ranked_votes(votes) do
    votes
    |> Enum.group_by(& &1.vote_rank)
    |> Enum.map(fn {rank, votes} -> {rank, length(votes)} end)
    |> Enum.into(%{})
  end

  defp count_star_votes(votes) do
    votes
    |> Enum.group_by(fn vote ->
      vote.vote_numeric |> Decimal.to_float() |> trunc()
    end)
    |> Enum.map(fn {rating, votes} -> {rating, length(votes)} end)
    |> Enum.into(%{})
  end

  defp calculate_average_score(votes) do
    if length(votes) == 0 do
      0.0
    else
      total_score =
        votes
        |> Enum.map(&PollVote.vote_score/1)
        |> Enum.sum()

      total_score / length(votes)
    end
  end

  defp count_unique_voters(poll_with_options) do
    poll_with_options.poll_options
    |> Enum.flat_map(& &1.votes)
    |> Enum.map(& &1.voter_id)
    |> Enum.uniq()
    |> length()
  end

  # =================
  # Poll Authorization & Lifecycle
  # =================

  @doc """
  Checks if a user can create polls for an event.
  """
  def can_create_poll?(%User{} = user, %Event{} = event) do
    # Event organizers can create polls
    # Event participants with appropriate permissions can create polls
    user_is_organizer?(event, user) ||
      case get_event_participant_by_event_and_user(event, user) do
        nil -> false
        participant -> participant.role in [:organizer, :co_organizer]
      end
  end

  @doc """
  Transitions a poll from list_building to voting phase (with suggestions allowed by default).
  """
  def transition_poll_to_voting(%Poll{} = poll) do
    if poll.phase == "list_building" do
      poll
      |> Poll.phase_transition_changeset("voting_with_suggestions")
      |> Repo.update()
    else
      {:error, "Poll is not in list_building phase"}
    end
  end

  @doc """
  Transitions a poll from list_building to voting only (suggestions disabled).
  """
  def transition_poll_to_voting_only(%Poll{} = poll) do
    if poll.phase == "list_building" do
      poll
      |> Poll.phase_transition_changeset("voting_only")
      |> Repo.update()
    else
      {:error, "Poll is not in list_building phase"}
    end
  end

  @doc """
  Disables suggestions during voting by transitioning from voting_with_suggestions to voting_only.
  """
  def disable_poll_suggestions(%Poll{phase: "voting_with_suggestions"} = poll) do
    poll
    |> Poll.phase_transition_changeset("voting_only")
    |> Repo.update()
  end

  # Legacy support
  def disable_poll_suggestions(%Poll{phase: "voting"} = poll) do
    poll
    |> Poll.phase_transition_changeset("voting_only")
    |> Repo.update()
  end

  def disable_poll_suggestions(%Poll{}),
    do: {:error, "Poll is not in a phase that allows disabling suggestions"}

  @doc """
  Finalizes a poll (single-argument version for LiveView component).
  """
  def finalize_poll(%Poll{} = poll) do
    # Determine winner(s) from votes via a single grouped query
    votes_by_option =
      from(v in PollVote,
        join: po in PollOption,
        on: v.poll_option_id == po.id,
        where: po.poll_id == ^poll.id,
        group_by: v.poll_option_id,
        select: {v.poll_option_id, count(v.id)}
      )
      |> Repo.all()

    case votes_by_option do
      [] ->
        # No votes cast
        finalize_poll(poll, [])

      counts ->
        # Find highest vote count
        {_, max_votes} = Enum.max_by(counts, &elem(&1, 1))

        # Collect all options tied for highest; pick first to preserve single-winner behavior
        [winner_id | _] =
          counts
          |> Enum.filter(fn {_id, count} -> count == max_votes end)
          |> Enum.map(&elem(&1, 0))

        finalize_poll(poll, [winner_id])
    end
  end

  # =================
  # High-Level Voting Functions with Business Logic
  # =================

  @doc """
  Casts a binary vote (yes/no/maybe) with validation and real-time updates.
  """
  def cast_binary_vote(%Poll{} = poll, %PollOption{} = poll_option, %User{} = user, vote_value)
      when vote_value in ["yes", "maybe", "no"] do
    if poll.voting_system != "binary" do
      {:error, "Poll does not support binary voting"}
    else
      cast_vote_with_transaction(poll, poll_option, user, %{vote_value: vote_value}, "binary")
    end
  end

  @doc """
  Casts an approval vote (selecting/deselecting an option) with validation.
  """
  def cast_approval_vote(
        %Poll{} = poll,
        %PollOption{} = poll_option,
        %User{} = user,
        selected \\ true
      ) do
    if poll.voting_system != "approval" do
      {:error, "Poll does not support approval voting"}
    else
      vote_value = if selected, do: "selected", else: nil

      if selected do
        cast_vote_with_transaction(poll, poll_option, user, %{vote_value: vote_value}, "approval")
      else
        # For approval voting, "deselecting" means removing the vote
        case get_user_poll_vote(poll_option, user) do
          nil -> {:ok, nil}
          existing_vote -> delete_poll_vote(existing_vote)
        end
      end
    end
  end

  @doc """
  Casts multiple approval votes at once for efficiency.
  """
  def cast_approval_votes(%Poll{} = poll, option_ids, %User{} = user) when is_list(option_ids) do
    if poll.voting_system != "approval" do
      {:error, "Poll does not support approval voting"}
    else
      Repo.transaction(fn ->
        # First, remove all existing approval votes for this user in this poll
        clear_user_poll_votes(poll, user)

        # Then add votes for selected options
        poll_options =
          from(po in PollOption,
            where: po.poll_id == ^poll.id and po.id in ^option_ids,
            preload: [:poll]
          )
          |> Repo.all()

        results =
          for option <- poll_options do
            case create_poll_vote(option, user, %{vote_value: "selected"}, "approval") do
              {:ok, vote} -> vote
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end

        # Broadcast updates
        broadcast_poll_update(poll, :votes_updated)
        broadcast_poll_stats_update(poll)
        results
      end)
    end
  end

  @doc """
  Casts a ranked vote with rank validation.
  """
  def cast_ranked_vote(%Poll{} = poll, %PollOption{} = poll_option, %User{} = user, rank)
      when is_integer(rank) and rank > 0 do
    if poll.voting_system != "ranked" do
      {:error, "Poll does not support ranked voting"}
    else
      Repo.transaction(fn ->
        # Check if user already has a vote with this rank for this poll
        existing_vote_with_rank =
          from(pv in PollVote,
            join: po in PollOption,
            on: pv.poll_option_id == po.id,
            where:
              po.poll_id == ^poll.id and
                pv.voter_id == ^user.id and
                pv.vote_rank == ^rank
          )
          |> Repo.one()

        # If there's an existing vote with this rank, remove it first
        if existing_vote_with_rank do
          Repo.delete!(existing_vote_with_rank)
        end

        # Create or update the vote for this option
        case create_poll_vote(poll_option, user, %{vote_rank: rank}, "ranked") do
          {:ok, vote} ->
            broadcast_poll_update(poll, :votes_updated)
            broadcast_poll_stats_update(poll)
            vote

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Casts multiple ranked votes at once (full ballot).
  """
  def cast_ranked_votes(%Poll{} = poll, ranked_options, %User{} = user)
      when is_list(ranked_options) do
    if poll.voting_system != "ranked" do
      {:error, "Poll does not support ranked voting"}
    else
      Repo.transaction(fn ->
        # Clear all existing ranked votes for this user in this poll
        clear_user_poll_votes(poll, user)

        # Validate that ranks are unique and sequential
        ranks = Enum.map(ranked_options, fn {_option_id, rank} -> rank end)

        if length(ranks) != length(Enum.uniq(ranks)) do
          Repo.rollback("Duplicate ranks not allowed")
        end

        # Cast votes for each ranked option
        results =
          for {option_id, rank} <- ranked_options do
            case Repo.get(PollOption, option_id) do
              nil ->
                Repo.rollback("Option with ID #{option_id} not found")

              option ->
                case create_poll_vote(option, user, %{vote_rank: rank}, "ranked") do
                  {:ok, vote} -> vote
                  {:error, changeset} -> Repo.rollback(changeset)
                end
            end
          end

        # Invalidate IRV cache since votes changed
        EventasaurusApp.Events.RankedChoiceVoting.invalidate_cache(poll.id)

        broadcast_poll_update(poll, :votes_updated)
        broadcast_poll_stats_update(poll)
        results
      end)
    end
  end

  @doc """
  Casts a star rating vote with validation.
  """
  def cast_star_vote(%Poll{} = poll, %PollOption{} = poll_option, %User{} = user, rating)
      when is_number(rating) and rating >= 1 and rating <= 5 do
    if poll.voting_system != "star" do
      {:error, "Poll does not support star rating"}
    else
      vote_numeric =
        if is_integer(rating), do: Decimal.new(rating), else: Decimal.from_float(rating)

      cast_vote_with_transaction(poll, poll_option, user, %{vote_numeric: vote_numeric}, "star")
    end
  end

  @doc """
  Clears all votes by a user for a specific poll.
  """
  def clear_user_poll_votes(%Poll{} = poll, %User{} = user) do
    query =
      from(pv in PollVote,
        join: po in PollOption,
        on: pv.poll_option_id == po.id,
        where: po.poll_id == ^poll.id and pv.voter_id == ^user.id
      )

    {count, _} = Repo.delete_all(query)

    # Invalidate IRV cache since votes changed
    if poll.voting_system == "ranked" do
      EventasaurusApp.Events.RankedChoiceVoting.invalidate_cache(poll.id)
    end

    broadcast_poll_update(poll, :votes_updated)
    broadcast_poll_stats_update(poll)
    {:ok, count}
  end

  @doc """
  Checks if a user can vote on a poll based on current phase and permissions.
  """
  def can_user_vote?(%Poll{} = poll, %User{} = user) do
    # Must be in any voting phase (including new phases)
    # Must be within voting deadline (if set)
    # User must be a participant in the event
    Poll.voting?(poll) and
      (is_nil(poll.voting_deadline) or
         DateTime.compare(DateTime.utc_now(), poll.voting_deadline) == :lt) and
      user_can_participate?(poll, user)
  end

  @doc """
  Gets comprehensive voting summary for a user on a poll.
  """
  def get_user_voting_summary(%Poll{} = poll, %User{} = user) do
    user_votes = list_user_poll_votes(poll, user)

    case poll.voting_system do
      "binary" ->
        votes_by_option = Enum.group_by(user_votes, & &1.poll_option_id)

        %{
          voting_system: "binary",
          votes_cast: length(user_votes),
          votes_by_option: votes_by_option
        }

      "approval" ->
        selected_options = Enum.map(user_votes, & &1.poll_option_id)

        %{
          voting_system: "approval",
          votes_cast: length(user_votes),
          selected_options: selected_options
        }

      "ranked" ->
        ranked_votes =
          user_votes
          |> Enum.sort_by(& &1.vote_rank)
          |> Enum.map(fn vote -> {vote.poll_option_id, vote.vote_rank} end)

        %{
          voting_system: "ranked",
          votes_cast: length(user_votes),
          ranked_options: ranked_votes
        }

      "star" ->
        ratings_by_option =
          user_votes
          |> Enum.map(fn vote ->
            {vote.poll_option_id, Decimal.to_float(vote.vote_numeric)}
          end)
          |> Enum.into(%{})

        %{
          voting_system: "star",
          votes_cast: length(user_votes),
          ratings_by_option: ratings_by_option
        }
    end
  end

  # =================
  # Private Helper Functions for Voting
  # =================

  defp cast_vote_with_transaction(poll, poll_option, user, vote_data, voting_system) do
    Repo.transaction(fn ->
      # For binary and star voting, remove existing vote first (replace behavior)
      if voting_system in ["binary", "star"] do
        case get_user_poll_vote(poll_option, user) do
          nil ->
            :ok

          existing_vote ->
            case delete_poll_vote(existing_vote) do
              {:ok, _} -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end
        end
      end

      case create_poll_vote(poll_option, user, vote_data, voting_system) do
        {:ok, vote} ->
          broadcast_poll_update(poll, :votes_updated)
          # Broadcast enhanced statistics update
          broadcast_poll_stats_update(poll)
          vote

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp user_can_participate?(poll, user) do
    # Get the event for this poll
    event = Repo.get!(Event, poll.event_id)

    # Check if user is event organizer or participant
    user_is_organizer?(event, user) or
      get_event_participant_by_event_and_user(event, user) != nil
  end

  defp broadcast_poll_update(poll, event_type) do
    # Use BroadcastThrottler for efficient real-time updates
    EventasaurusWeb.Services.BroadcastThrottler.throttle_poll_update_broadcast(
      poll.id,
      event_type,
      poll.event_id
    )
  end

  # =================
  # Poll Analytics
  # =================

  # =================
  # Missing Poll Functions (Used by LiveView Components)
  # =================

  @doc """
  Updates the status of a poll (e.g., "list_building", "voting", "finalized").
  """
  def update_poll_status(%Poll{} = poll, new_status) do
    poll
    |> Poll.status_changeset(%{status: new_status})
    |> Repo.update()
    |> case do
      {:ok, updated_poll} ->
        broadcast_poll_update(updated_poll, :status_updated)
        {:ok, updated_poll}

      error ->
        error
    end
  end

  @doc """
  Clears all votes for a poll (used by moderation).
  """
  def clear_all_poll_votes(poll_id) do
    from(v in PollVote,
      where:
        v.poll_option_id in subquery(
          from(o in PollOption, where: o.poll_id == ^poll_id, select: o.id)
        )
    )
    |> Repo.delete_all()
    |> case do
      {deleted_count, _} ->
        poll = get_poll!(poll_id)
        broadcast_poll_update(poll, :votes_cleared)
        {:ok, deleted_count}
    end
  end

  # =================
  # Event-Poll Integration & Lifecycle Hooks
  # =================

  @doc """
  Creates a poll for an event with event-based notifications.

  This is the recommended way to create polls as it includes:
  - Event association validation
  - Event-based PubSub broadcasting
  - Lifecycle integration with event workflows
  """
  def create_event_poll(%Event{} = event, %User{} = creator, attrs \\ %{}) do
    if not can_create_poll?(creator, event) do
      {:error, "User does not have permission to create polls for this event"}
    else
      poll_attrs =
        Map.merge(attrs, %{
          event_id: event.id,
          created_by_id: creator.id
        })

      Repo.transaction(fn ->
        case create_poll(poll_attrs) do
          {:ok, poll} ->
            # Trigger event-poll lifecycle integration
            handle_poll_creation(event, poll, creator)

            # Broadcast to event followers
            broadcast_event_poll_activity(event, :poll_created, poll, creator)

            poll

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Updates a poll with event lifecycle integration.
  """
  def update_event_poll(%Poll{} = poll, attrs, %User{} = updater) do
    event = Repo.get!(Event, poll.event_id)

    if not user_can_manage_event?(updater, event) do
      {:error, "User does not have permission to update this poll"}
    else
      case update_poll(poll, attrs) do
        {:ok, updated_poll} ->
          # Handle phase transitions
          if Map.get(attrs, :phase) && attrs.phase != poll.phase do
            handle_poll_phase_transition(event, updated_poll, poll.phase, attrs.phase, updater)
          end

          broadcast_event_poll_activity(event, :poll_updated, updated_poll, updater)
          {:ok, updated_poll}

        error ->
          error
      end
    end
  end

  @doc """
  Finalizes a poll with event workflow integration.
  """
  def finalize_event_poll(%Poll{} = poll, option_ids, %User{} = finalizer) do
    event = Repo.get!(Event, poll.event_id) |> Repo.preload([:polls])

    if not user_can_manage_event?(finalizer, event) do
      {:error, "User does not have permission to finalize this poll"}
    else
      Repo.transaction(fn ->
        case finalize_poll(poll, option_ids) do
          {:ok, finalized_poll} ->
            # Handle event workflow integration based on poll type
            handle_poll_finalization(event, finalized_poll, finalizer)

            broadcast_event_poll_activity(event, :poll_finalized, finalized_poll, finalizer)

            finalized_poll

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Deletes a poll with event cleanup.
  """
  def delete_event_poll(%Poll{} = poll, %User{} = deleter) do
    event = Repo.get!(Event, poll.event_id)

    if not user_can_manage_event?(deleter, event) do
      {:error, "User does not have permission to delete this poll"}
    else
      case delete_poll(poll) do
        {:ok, deleted_poll} ->
          broadcast_event_poll_activity(event, :poll_deleted, deleted_poll, deleter)
          {:ok, deleted_poll}

        error ->
          error
      end
    end
  end

  @doc """
  Gets all active polls for an event with event context.
  """
  def list_event_active_polls(%Event{} = event) do
    # list_active_polls already handles the proper ordering for date_selection polls
    list_active_polls(event)
  end

  @doc """
  Gets poll statistics for an event dashboard.
  """
  def get_event_poll_stats(%Event{} = event) do
    polls = list_polls(event)

    %{
      total_polls: length(polls),
      active_polls: length(Enum.filter(polls, &(&1.phase != "closed"))),
      polls_by_type:
        Enum.group_by(polls, & &1.poll_type)
        |> Enum.map(fn {type, polls} -> {type, length(polls)} end)
        |> Enum.into(%{}),
      polls_by_phase:
        Enum.group_by(polls, & &1.phase)
        |> Enum.map(fn {phase, polls} -> {phase, length(polls)} end)
        |> Enum.into(%{}),
      total_participants: count_unique_poll_participants(polls)
    }
  end

  # =================
  # Private Event-Poll Integration Helpers
  # =================

  defp handle_poll_creation(%Event{} = event, %Poll{} = poll, %User{} = creator) do
    # Log poll creation activity
    Logger.info("Poll created for event", %{
      event_id: event.id,
      poll_id: poll.id,
      poll_type: poll.poll_type,
      creator_id: creator.id
    })

    # Handle specific poll type workflows
    case poll.poll_type do
      "date_selection" ->
        # If this is a date selection poll, check if event should transition to polling status
        if event.status == :draft do
          transition_event(event, :polling)
        end

      "venue_selection" ->
        # Similar logic for venue selection polls
        if event.status == :draft do
          transition_event(event, :polling)
        end

      _ ->
        # General poll creation - no specific event status changes needed
        :ok
    end
  end

  defp handle_poll_phase_transition(
         %Event{} = event,
         %Poll{} = poll,
         old_phase,
         new_phase,
         %User{} = user
       ) do
    Logger.info("Poll phase transition", %{
      event_id: event.id,
      poll_id: poll.id,
      from_phase: old_phase,
      to_phase: new_phase,
      user_id: user.id
    })

    case {old_phase, new_phase} do
      {"list_building", "voting_with_suggestions"} ->
        # Poll is now ready for voting with suggestions allowed - notify event participants
        broadcast_event_poll_activity(event, :poll_voting_started, poll, user)

      {"list_building", "voting_only"} ->
        # Poll is now ready for voting only (no suggestions) - notify event participants
        broadcast_event_poll_activity(event, :poll_voting_started, poll, user)

      {"list_building", "voting"} ->
        # Legacy transition - treat as voting_with_suggestions
        broadcast_event_poll_activity(event, :poll_voting_started, poll, user)

      {"voting_with_suggestions", "voting_only"} ->
        # Organizer disabled suggestions during voting - notify participants
        broadcast_event_poll_activity(event, :poll_suggestions_disabled, poll, user)

      {"voting_with_suggestions", "closed"} ->
        # Poll voting has ended - may trigger event workflow changes
        handle_poll_voting_ended(event, poll, user)

      {"voting_only", "closed"} ->
        # Poll voting has ended - may trigger event workflow changes
        handle_poll_voting_ended(event, poll, user)

      {"voting", "closed"} ->
        # Legacy transition - poll voting has ended
        handle_poll_voting_ended(event, poll, user)

      _ ->
        :ok
    end
  end

  defp handle_poll_finalization(%Event{} = event, %Poll{} = poll, %User{} = finalizer) do
    Logger.info("Poll finalized", %{
      event_id: event.id,
      poll_id: poll.id,
      poll_type: poll.poll_type,
      finalizer_id: finalizer.id
    })

    # Handle event workflow based on poll type and results
    case poll.poll_type do
      "date_selection" ->
        handle_date_poll_finalization(event, poll, finalizer)

      "venue_selection" ->
        handle_venue_poll_finalization(event, poll, finalizer)

      "threshold_interest" ->
        handle_threshold_poll_finalization(event, poll, finalizer)

      _ ->
        # General poll finalization
        Logger.info("General poll finalized - no specific event workflow changes")
    end
  end

  defp handle_poll_voting_ended(%Event{} = event, %Poll{} = poll, %User{} = user) do
    # When poll voting ends, it might affect event status
    case poll.poll_type do
      "date_selection" ->
        # If date selection voting ended but not finalized, event may need organizer action
        if event.status == :polling do
          broadcast_event_poll_activity(event, :organizer_action_needed, poll, user)
        end

      "threshold_interest" ->
        # Check if threshold was met to auto-transition event
        analytics = get_poll_analytics(poll)

        if threshold_met_from_poll?(poll, analytics) do
          transition_event(event, :confirmed)
        end

      _ ->
        :ok
    end
  end

  @doc """
  Finalizes a date_selection poll with winning date determination and event integration.

  ## Parameters
  - poll: The date_selection poll to finalize
  - finalizer: The user performing the finalization
  - opts: Optional parameters:
    - :finalization_strategy - :highest_votes (default), :most_yes_votes, :manual
    - :selected_option_ids - For manual selection, specific option IDs to finalize
    - :preserve_time - Whether to preserve existing event time (default: true)

  ## Returns
  - {:ok, {updated_poll, updated_event}} on success
  - {:error, reason} on failure
  """
  def finalize_date_selection_poll(
        %Poll{poll_type: "date_selection"} = poll,
        %User{} = finalizer,
        opts \\ []
      ) do
    strategy = Keyword.get(opts, :finalization_strategy, :highest_votes)
    preserve_time = Keyword.get(opts, :preserve_time, true)

    Repo.transaction(fn ->
      # Determine winning date(s) based on strategy
      case determine_winning_date_options(poll, strategy, opts) do
        {:ok, [_ | _] = winning_option_ids} ->
          # Finalize the poll with winning options
          case finalize_poll(poll, winning_option_ids) do
            {:ok, finalized_poll} ->
              # Update the associated event if single date selected
              event = Repo.get!(Event, poll.event_id)

              case update_event_from_date_poll(event, winning_option_ids, preserve_time) do
                {:ok, updated_event} ->
                  # Trigger event-poll lifecycle integration
                  handle_date_poll_finalization(updated_event, finalized_poll, finalizer)

                  Logger.info("Date selection poll finalized successfully", %{
                    poll_id: finalized_poll.id,
                    event_id: updated_event.id,
                    winning_options: winning_option_ids,
                    finalizer_id: finalizer.id
                  })

                  {finalized_poll, updated_event}

                {:error, reason} ->
                  Logger.warning("Failed to update event from date poll", %{
                    poll_id: poll.id,
                    event_id: event.id,
                    reason: reason
                  })

                  Repo.rollback(reason)
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        {:ok, []} ->
          Repo.rollback("No winning date options found")

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Determines winning date options based on voting results and strategy.
  """
  def determine_winning_date_options(
        %Poll{poll_type: "date_selection"} = poll,
        strategy,
        opts \\ []
      ) do
    case strategy do
      :manual ->
        # Manual selection - use provided option IDs
        selected_ids = Keyword.get(opts, :selected_option_ids, [])

        if length(selected_ids) > 0 do
          {:ok, selected_ids}
        else
          {:error, "No option IDs provided for manual selection"}
        end

      :highest_votes ->
        determine_highest_voted_date_options(poll)

      :most_yes_votes ->
        determine_most_yes_voted_date_options(poll)

      _ ->
        {:error, "Unknown finalization strategy: #{strategy}"}
    end
  end

  @doc """
  Updates an event's date based on finalized date poll results.
  """
  def update_event_from_date_poll(%Event{} = event, winning_option_ids, preserve_time \\ true) do
    if length(winning_option_ids) == 1 do
      # Single date selected - update event date
      option_id = List.first(winning_option_ids)
      option = Repo.get!(PollOption, option_id)

      case extract_date_from_option(option) do
        {:ok, selected_date} ->
          # Convert date to datetime, preserving existing time if requested
          new_datetime =
            if preserve_time && event.start_at do
              DateTime.new!(
                selected_date,
                DateTime.to_time(event.start_at),
                event.timezone || "UTC"
              )
            else
              # Default to 6 PM if no existing time
              DateTime.new!(selected_date, ~T[18:00:00], event.timezone || "UTC")
            end

          # Update event with new date and confirmed status
          attrs = %{
            start_at: new_datetime,
            status: :confirmed,
            # Clear polling deadline
            polling_deadline: nil
          }

          # Preserve existing end time if it exists
          attrs =
            if event.ends_at do
              # Calculate duration and apply to new date
              duration = DateTime.diff(event.ends_at, event.start_at, :second)
              new_ends_at = DateTime.add(new_datetime, duration, :second)
              Map.put(attrs, :ends_at, new_ends_at)
            else
              attrs
            end

          changeset = Event.changeset_with_inferred_status(event, attrs)
          Repo.update(changeset)

        {:error, reason} ->
          {:error, "Could not extract date from winning option: #{reason}"}
      end
    else
      # Multiple dates selected - cannot update event date automatically
      Logger.info("Multiple dates selected, event date not updated automatically", %{
        event_id: event.id,
        selected_options: winning_option_ids
      })

      {:ok, event}
    end
  end

  defp handle_date_poll_finalization(%Event{} = event, %Poll{} = poll, %User{} = _finalizer) do
    # Get selected options from finalized poll
    selected_options = poll.finalized_option_ids || []

    case length(selected_options) do
      1 ->
        # Single date selected - event should already be updated by update_event_from_date_poll
        option_id = List.first(selected_options)
        option = Repo.get!(PollOption, option_id)

        case extract_date_from_option(option) do
          {:ok, date} ->
            Logger.info("Event date updated from poll finalization", %{
              event_id: event.id,
              selected_date: Date.to_string(date),
              poll_id: poll.id
            })

            # Transition event to confirmed if not already
            if event.status != :confirmed do
              transition_event(event, :confirmed)
            end

          {:error, reason} ->
            Logger.warning("Could not extract date from finalized poll option", %{
              poll_id: poll.id,
              option_id: option_id,
              reason: reason
            })
        end

      count when count > 1 ->
        Logger.info("Multiple dates selected in poll finalization", %{
          event_id: event.id,
          poll_id: poll.id,
          selected_count: count,
          message: "Event organizer needs to manually select final date"
        })

      0 ->
        Logger.warning("No dates selected in poll finalization", %{
          event_id: event.id,
          poll_id: poll.id
        })
    end
  end

  defp determine_highest_voted_date_options(%Poll{} = poll) do
    # Get all poll options with their vote counts
    options_with_votes =
      poll
      |> list_poll_options()
      |> Enum.map(fn option ->
        vote_count = length(option.votes || [])
        {option.id, vote_count}
      end)
      |> Enum.sort_by(fn {_id, count} -> count end, :desc)

    case options_with_votes do
      [] ->
        {:error, "No options found for poll"}

      [{top_option_id, top_count} | rest] ->
        if top_count > 0 do
          # Find all options with the highest vote count (handles ties)
          winning_options =
            Enum.take_while([{top_option_id, top_count} | rest], fn {_id, count} ->
              count == top_count
            end)

          winning_ids = Enum.map(winning_options, fn {id, _count} -> id end)
          {:ok, winning_ids}
        else
          {:error, "No votes cast for any option"}
        end
    end
  end

  defp determine_most_yes_voted_date_options(%Poll{voting_system: "binary"} = poll) do
    # For binary voting system, count "yes" votes specifically
    options_with_yes_votes =
      poll
      |> list_poll_options()
      |> Enum.map(fn option ->
        yes_count =
          option.votes
          |> Enum.count(fn vote -> vote.vote_value == "yes" end)

        {option.id, yes_count}
      end)
      |> Enum.sort_by(fn {_id, count} -> count end, :desc)

    case options_with_yes_votes do
      [] ->
        {:error, "No options found for poll"}

      [{top_option_id, top_count} | rest] ->
        if top_count > 0 do
          # Find all options with the highest "yes" vote count
          winning_options =
            Enum.take_while([{top_option_id, top_count} | rest], fn {_id, count} ->
              count == top_count
            end)

          winning_ids = Enum.map(winning_options, fn {id, _count} -> id end)
          {:ok, winning_ids}
        else
          {:error, "No 'yes' votes cast for any option"}
        end
    end
  end

  defp determine_most_yes_voted_date_options(%Poll{} = poll) do
    # For non-binary voting systems, fall back to highest votes
    determine_highest_voted_date_options(poll)
  end

  defp handle_venue_poll_finalization(%Event{} = event, %Poll{} = poll, %User{} = _finalizer) do
    # Similar logic for venue selection
    selected_options = poll.finalized_option_ids || []

    if length(selected_options) == 1 do
      option_id = List.first(selected_options)
      option = Repo.get!(PollOption, option_id)

      case extract_venue_from_option(option) do
        {:ok, venue_id} ->
          update_event(event, %{venue_id: venue_id})

          Logger.info("Event venue updated from poll finalization", %{
            event_id: event.id,
            venue_id: venue_id
          })

        {:error, reason} ->
          Logger.warning("Could not extract venue from poll option", %{
            poll_id: poll.id,
            option_id: option_id,
            reason: reason
          })
      end
    end
  end

  defp handle_threshold_poll_finalization(%Event{} = event, %Poll{} = poll, %User{} = _finalizer) do
    # Check if poll results indicate enough interest to confirm event
    analytics = get_poll_analytics(poll)

    if threshold_met_from_poll?(poll, analytics) do
      transition_event(event, :confirmed)

      Logger.info("Event confirmed from threshold poll results", %{
        event_id: event.id,
        poll_id: poll.id
      })
    else
      Logger.info("Event threshold not met from poll results", %{
        event_id: event.id,
        poll_id: poll.id
      })
    end
  end

  defp broadcast_event_poll_activity(
         %Event{} = event,
         activity_type,
         %Poll{} = poll,
         %User{} = user
       ) do
    # Broadcast to event-specific channel for event page updates
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "events:#{event.id}",
      {:poll_activity, activity_type, poll, user}
    )

    # Broadcast to general event participants channel
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "event_participants:#{event.id}",
      {:poll_activity, activity_type, poll, user}
    )

    # Broadcast to organizers channel for management updates
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "event_organizers:#{event.id}",
      {:poll_activity, activity_type, poll, user}
    )
  end

  defp count_unique_poll_participants(polls) do
    polls
    |> Enum.flat_map(fn poll -> poll.poll_options || [] end)
    |> Enum.flat_map(fn option -> option.votes || [] end)
    |> Enum.map(& &1.voter_id)
    |> Enum.uniq()
    |> length()
  end

  defp threshold_met_from_poll?(%Poll{} = poll, analytics) do
    # Simple heuristic: if total unique voters > 5 and approval rate > 70%
    total_voters = Map.get(analytics, :unique_voters, 0)

    case poll.voting_system do
      "binary" ->
        yes_percentage = Map.get(analytics, :approval_percentage, 0)
        total_voters >= 5 and yes_percentage >= 70

      "approval" ->
        selected_percentage = Map.get(analytics, :selection_percentage, 0)
        total_voters >= 5 and selected_percentage >= 70

      _ ->
        # For other voting systems, just check participant count
        total_voters >= 10
    end
  end

  defp extract_date_from_option(%PollOption{} = option) do
    cond do
      # First, try our new metadata structure (date_selection polls)
      option.metadata && Map.has_key?(option.metadata, "date") ->
        case Date.from_iso8601(option.metadata["date"]) do
          {:ok, date} -> {:ok, date}
          {:error, reason} -> {:error, "Invalid date in metadata: #{reason}"}
        end

      # Legacy support: external_data with date (old system)
      option.external_data && Map.has_key?(option.external_data, "date") ->
        case DateTime.from_iso8601(option.external_data["date"]) do
          {:ok, datetime, _} -> {:ok, DateTime.to_date(datetime)}
          {:error, reason} -> {:error, "Invalid datetime in external_data: #{reason}"}
        end

      # Legacy support: try to parse date from title (format: "2024-12-15")
      option.title && Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, option.title) ->
        case Date.from_iso8601(option.title) do
          {:ok, date} -> {:ok, date}
          {:error, reason} -> {:error, "Invalid date format in title: #{reason}"}
        end

      true ->
        {:error, "No valid date information found in option"}
    end
  end

  defp extract_venue_from_option(%PollOption{} = option) do
    cond do
      option.external_data && Map.has_key?(option.external_data, "venue_id") ->
        {:ok, option.external_data["venue_id"]}

      # Try to find venue by name in title
      option.title ->
        case Repo.get_by(EventasaurusApp.Venues.Venue, name: option.title) do
          nil -> {:error, "Venue not found"}
          venue -> {:ok, venue.id}
        end

      true ->
        {:error, "No venue information found in option"}
    end
  end

  # =================
  # Time Extraction and Formatting Functions (NEW)
  # =================

  @doc """
  Extracts time slots from a poll option's metadata.

  Returns a list of time slot maps with start_time, end_time, timezone, and display fields.

  ## Returns
  - {:ok, [time_slots]} if time slots exist
  - {:ok, []} if poll option is all-day or has no time slots
  - {:error, reason} if metadata is invalid

  ## Examples
      iex> extract_time_slots_from_option(option)
      {:ok, [%{"start_time" => "09:00", "end_time" => "12:00", "timezone" => "UTC", "display" => "9:00 AM - 12:00 PM"}]}

      iex> extract_time_slots_from_option(all_day_option)
      {:ok, []}
  """
  def extract_time_slots_from_option(%PollOption{metadata: nil}),
    do: {:error, "No metadata found"}

  def extract_time_slots_from_option(%PollOption{metadata: metadata}) do
    case {Map.get(metadata, "time_enabled"), Map.get(metadata, "time_slots")} do
      {true, time_slots} when is_list(time_slots) and length(time_slots) > 0 ->
        {:ok, time_slots}

      {true, _} ->
        {:error, "Time enabled but no valid time slots found"}

      {false, _} ->
        # All-day event
        {:ok, []}

      {nil, _} ->
        # Legacy date-only format (backward compatibility)
        {:ok, []}

      _ ->
        {:error, "Invalid time metadata structure"}
    end
  end

  @doc """
  Formats datetime information for display, handling both date-only and date+time options.

  ## Returns
  A formatted string suitable for user display

  ## Examples
      iex> format_datetime_for_display(date_only_option)
      "Monday, December 25, 2024 (All day)"

      iex> format_datetime_for_display(date_time_option)
      "Monday, December 25, 2024 - 9:00 AM - 12:00 PM, 2:00 PM - 5:00 PM"
  """
  def format_datetime_for_display(%PollOption{metadata: metadata}) do
    date_display = Map.get(metadata, "display_date", "Unknown Date")

    case extract_time_slots_from_option(%PollOption{metadata: metadata}) do
      {:ok, []} ->
        "#{date_display} (All day)"

      {:ok, time_slots} ->
        time_displays = Enum.map(time_slots, &Map.get(&1, "display", "Unknown Time"))
        "#{date_display} - #{Enum.join(time_displays, ", ")}"

      {:error, _} ->
        "#{date_display} (Time information unavailable)"
    end
  end

  @doc """
  Validates time slots for internal consistency and format correctness.

  ## Parameters
  - time_slots: List of time slot maps

  ## Returns
  - :ok if all time slots are valid
  - {:error, reasons} if validation fails

  ## Examples
      iex> validate_time_slots([%{"start_time" => "09:00", "end_time" => "12:00"}])
      :ok

      iex> validate_time_slots([%{"start_time" => "14:00", "end_time" => "12:00"}])
      {:error, ["slot 1 end_time must be after start_time"]}
  """
  def validate_time_slots(time_slots) when is_list(time_slots) do
    alias EventasaurusApp.Events.DateMetadata

    case DateMetadata.validate_time_slots(time_slots) do
      %Ecto.Changeset{valid?: true} ->
        :ok

      %Ecto.Changeset{errors: errors} ->
        error_messages = Enum.map(errors, fn {_field, {message, _opts}} -> message end)
        {:error, error_messages}
    end
  end

  def validate_time_slots(_), do: {:error, ["time_slots must be a list"]}

  @doc """
  Converts time in HH:MM format to total minutes since midnight.

  ## Examples
      iex> time_to_minutes("09:30")
      {:ok, 570}

      iex> time_to_minutes("25:00")
      {:error, "Invalid time format"}
  """
  def time_to_minutes(time_string) when is_binary(time_string) do
    case Regex.run(~r/^(\d{1,2}):(\d{2})$/, time_string) do
      [_, hour_str, minute_str] ->
        hour = String.to_integer(hour_str)
        minute = String.to_integer(minute_str)

        if hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
          {:ok, hour * 60 + minute}
        else
          {:error, "Invalid time format"}
        end

      _ ->
        {:error, "Invalid time format"}
    end
  end

  def time_to_minutes(_), do: {:error, "Time must be a string"}

  @doc """
  Converts minutes since midnight to HH:MM format.

  ## Examples
      iex> minutes_to_time(570)
      {:ok, "09:30"}

      iex> minutes_to_time(1500)
      {:error, "Invalid minutes value"}
  """
  def minutes_to_time(minutes) when is_integer(minutes) and minutes >= 0 and minutes < 1440 do
    hour = div(minutes, 60)
    minute = rem(minutes, 60)
    {:ok, "#{String.pad_leading("#{hour}", 2, "0")}:#{String.pad_leading("#{minute}", 2, "0")}"}
  end

  def minutes_to_time(_), do: {:error, "Invalid minutes value"}

  @doc """
  Formats time string for display in 24-hour format.

  Legacy function name retained for backward compatibility.
  Despite the name, now returns 24-hour format as the European standard.

  Delegates to `EventasaurusWeb.Utils.TimeUtils.format_time_12hour/1`.

  ## Examples
      iex> format_time_12hour("14:30")
      "14:30"

      iex> format_time_12hour("09:00")
      "09:00"
  """
  def format_time_12hour(time_string) when is_binary(time_string) do
    TimeUtils.format_time_12hour(time_string)
  end

  def format_time_12hour(_), do: "Invalid Time"

  @doc """
  Generates a display string for a time range.

  ## Examples
      iex> generate_time_range_display("09:00", "17:00")
      "09:00 - 17:00"

      iex> generate_time_range_display("14:30", "16:45")
      "14:30 - 16:45"
  """
  def generate_time_range_display(start_time, end_time) do
    "#{format_time_12hour(start_time)} - #{format_time_12hour(end_time)}"
  end

  @doc """
  Checks if two time slots overlap.

  ## Examples
      iex> time_slots_overlap?("09:00", "12:00", "11:00", "14:00")
      true

      iex> time_slots_overlap?("09:00", "12:00", "13:00", "15:00")
      false
  """
  def time_slots_overlap?(start1, end1, start2, end2) do
    with {:ok, start1_min} <- time_to_minutes(start1),
         {:ok, end1_min} <- time_to_minutes(end1),
         {:ok, start2_min} <- time_to_minutes(start2),
         {:ok, end2_min} <- time_to_minutes(end2) do
      # Two time slots overlap if one starts before the other ends
      start1_min < end2_min and start2_min < end1_min
    else
      # If any time parsing fails, assume no overlap
      _ -> false
    end
  end

  @doc """
  Merges overlapping time slots in a list, returning a list of non-overlapping slots.

  ## Examples
      iex> merge_overlapping_time_slots([
      ...>   %{"start_time" => "09:00", "end_time" => "12:00"},
      ...>   %{"start_time" => "11:00", "end_time" => "14:00"}
      ...> ])
      [%{"start_time" => "09:00", "end_time" => "14:00", "display" => "9:00 AM - 2:00 PM"}]
  """
  def merge_overlapping_time_slots(time_slots) when is_list(time_slots) do
    # Sort by start time
    sorted_slots =
      Enum.sort_by(time_slots, fn slot ->
        case time_to_minutes(slot["start_time"]) do
          {:ok, minutes} -> minutes
          # Put invalid times at the end
          _ -> 9999
        end
      end)

    # Merge overlapping slots
    merged =
      Enum.reduce(sorted_slots, [], fn slot, acc ->
        case acc do
          [] ->
            [slot]

          [last_slot | rest] ->
            if time_slots_overlap?(
                 last_slot["start_time"],
                 last_slot["end_time"],
                 slot["start_time"],
                 slot["end_time"]
               ) do
              # Merge the slots
              merged_slot = %{
                "start_time" => last_slot["start_time"],
                "end_time" => latest_end_time(last_slot["end_time"], slot["end_time"]),
                "timezone" => last_slot["timezone"] || slot["timezone"] || "UTC"
              }

              merged_slot =
                Map.put(
                  merged_slot,
                  "display",
                  generate_time_range_display(merged_slot["start_time"], merged_slot["end_time"])
                )

              [merged_slot | rest]
            else
              [slot | acc]
            end
        end
      end)

    Enum.reverse(merged)
  end

  def merge_overlapping_time_slots(_), do: []

  @doc """
  Creates date+time poll option with time slot support.

  ## Parameters
  - poll: The poll to add the option to (must be poll_type: "date_selection")
  - user: The user suggesting the option
  - date: Date as string, Date struct, or DateTime struct
  - opts: Options including:
    - :time_enabled - boolean to enable time slots (default: false)
    - :time_slots - list of time slot maps
    - :all_day - boolean for all-day events (default: true unless time_enabled)
    - :timezone - timezone for time slots (default: "UTC")
    - :title - custom title
    - :description - description

  ## Examples
      iex> create_date_time_poll_option(poll, user, "2024-12-25",
      ...>   time_enabled: true,
      ...>   time_slots: [%{"start_time" => "09:00", "end_time" => "12:00"}]
      ...> )
      {:ok, %PollOption{}}
  """
  def create_date_time_poll_option(
        %Poll{poll_type: "date_selection"} = poll,
        %User{} = user,
        date,
        opts \\ []
      ) do
    alias EventasaurusApp.Events.DateMetadata

    # Extract time options
    time_enabled = Keyword.get(opts, :time_enabled, false)
    time_slots = Keyword.get(opts, :time_slots, [])
    all_day = Keyword.get(opts, :all_day, not time_enabled)
    timezone = Keyword.get(opts, :timezone, "UTC")

    # Validate time slots if time is enabled - return early on error
    with :ok <- validate_time_slots_if_enabled(time_enabled, time_slots) do
      # Build enhanced metadata with time support
      enhanced_opts =
        opts
        |> Keyword.put(:time_enabled, time_enabled)
        |> Keyword.put(:time_slots, time_slots)
        |> Keyword.put(:all_day, all_day)

      # Ensure time slots have proper timezone and display
      enhanced_time_slots =
        if time_enabled and length(time_slots) > 0 do
          Enum.map(time_slots, fn slot ->
            slot
            |> Map.put_new("timezone", timezone)
            |> Map.put_new(
              "display",
              generate_time_range_display(slot["start_time"], slot["end_time"])
            )
          end)
        else
          []
        end

      final_opts = Keyword.put(enhanced_opts, :time_slots, enhanced_time_slots)

      try do
        metadata = DateMetadata.build_date_metadata(date, final_opts)

        # Parse date for title generation
        parsed_date =
          case date do
            %Date{} = d -> d
            date_string -> Date.from_iso8601!(date_string)
          end

        # Generate enhanced title including time information
        title =
          if time_enabled and length(enhanced_time_slots) > 0 do
            time_display =
              enhanced_time_slots
              |> Enum.map(&Map.get(&1, "display", "Unknown Time"))
              |> Enum.join(", ")

            base_title = Keyword.get(opts, :title, format_date_for_display(parsed_date))
            "#{base_title} - #{time_display}"
          else
            Keyword.get(opts, :title, format_date_for_display(parsed_date))
          end

        description = Keyword.get(opts, :description)

        attrs = %{
          "poll_id" => poll.id,
          "suggested_by_id" => user.id,
          "title" => title,
          "description" => description,
          "metadata" => metadata,
          "status" => "active"
        }

        create_poll_option(attrs, poll_type: "date_selection")
      rescue
        e in ArgumentError ->
          changeset =
            PollOption.changeset(%PollOption{}, %{}, poll_type: "date_selection")
            |> Ecto.Changeset.add_error(:metadata, "Invalid date or time: #{e.message}")

          {:error, changeset}
      end
    else
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Helper function for conditional time slot validation
  defp validate_time_slots_if_enabled(false, _), do: :ok
  defp validate_time_slots_if_enabled(true, []), do: :ok

  defp validate_time_slots_if_enabled(true, time_slots) do
    case validate_time_slots(time_slots) do
      :ok ->
        :ok

      {:error, reasons} ->
        changeset =
          PollOption.changeset(%PollOption{}, %{}, poll_type: "date_selection")
          |> Ecto.Changeset.add_error(
            :metadata,
            "Invalid time slots: #{Enum.join(reasons, ", ")}"
          )

        {:error, changeset}
    end
  end

  @doc """
  Updates a date poll option with new time information.

  ## Parameters
  - poll_option: The poll option to update
  - opts: Update options including time_enabled, time_slots, etc.

  ## Examples
      iex> update_date_time_poll_option(option, time_enabled: true, time_slots: [...])
      {:ok, %PollOption{}}
  """
  def update_date_time_poll_option(%PollOption{} = poll_option, opts \\ []) do
    alias EventasaurusApp.Events.DateMetadata

    # Get current metadata
    current_metadata = poll_option.metadata || %{}
    current_date = Map.get(current_metadata, "date")

    if current_date do
      # Parse current date
      {:ok, parsed_date} = Date.from_iso8601(current_date)

      # Merge current metadata with new options
      preserved_opts = [
        created_at: Map.get(current_metadata, "created_at"),
        updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      ]

      final_opts = Keyword.merge(preserved_opts, opts)

      try do
        new_metadata = DateMetadata.build_date_metadata(parsed_date, final_opts)

        # Update title if time information changed
        time_enabled =
          Keyword.get(opts, :time_enabled, Map.get(current_metadata, "time_enabled", false))

        time_slots = Keyword.get(opts, :time_slots, Map.get(current_metadata, "time_slots", []))

        new_title =
          if time_enabled and length(time_slots) > 0 do
            time_display =
              time_slots
              |> Enum.map(&Map.get(&1, "display", "Unknown Time"))
              |> Enum.join(", ")

            base_title = Keyword.get(opts, :title, format_date_for_display(parsed_date))
            "#{base_title} - #{time_display}"
          else
            Keyword.get(opts, :title, poll_option.title)
          end

        attrs = %{
          "metadata" => new_metadata,
          "title" => new_title
        }

        # Add description if provided
        attrs =
          if description = Keyword.get(opts, :description) do
            Map.put(attrs, "description", description)
          else
            attrs
          end

        update_poll_option(poll_option, attrs, poll_type: "date_selection")
      rescue
        e in ArgumentError ->
          changeset =
            PollOption.changeset(poll_option, %{}, poll_type: "date_selection")
            |> Ecto.Changeset.add_error(:metadata, "Invalid time information: #{e.message}")

          {:error, changeset}
      end
    else
      {:error, "Cannot update time information: no date found in metadata"}
    end
  end

  # Private helper functions for time operations

  defp latest_end_time(end_time1, end_time2) do
    case {time_to_minutes(end_time1), time_to_minutes(end_time2)} do
      {{:ok, minutes1}, {:ok, minutes2}} ->
        if minutes1 > minutes2, do: end_time1, else: end_time2

      _ ->
        # Fallback to first time if parsing fails
        end_time1
    end
  end

  # =================
  # Enhanced Poll Analytics (All Poll Types)
  # =================

  @doc """
  Gets enhanced vote statistics for a poll option similar to legacy get_date_option_vote_tally().
  Returns detailed breakdown with percentages and scores appropriate for the poll's voting system.
  """
  def get_poll_option_vote_tally(%PollOption{} = poll_option) do
    poll = Repo.preload(poll_option, :poll).poll
    votes = list_poll_votes(poll_option)

    case poll.voting_system do
      "binary" -> get_binary_option_tally(votes)
      "approval" -> get_approval_option_tally(votes)
      "star" -> get_star_option_tally(votes)
      "ranked" -> get_ranked_option_tally(votes)
      _ -> get_generic_option_tally(votes)
    end
  end

  @doc """
  Gets enhanced vote tallies for all options in a poll.
  Similar to legacy get_poll_vote_tallies() but with rich statistics for all poll types.
  """
  def get_enhanced_poll_vote_tallies(%Poll{} = poll) do
    poll_with_options = Repo.preload(poll, poll_options: :votes)

    options_with_tallies =
      poll_with_options.poll_options
      |> Enum.map(fn option ->
        %{
          option: option,
          tally: get_poll_option_vote_tally(option)
        }
      end)

    # Sort by score (highest first) for all poll types
    sorted_options =
      case poll.voting_system do
        "ranked" ->
          # For ranked voting, sort by average rank (lower is better)
          Enum.sort_by(options_with_tallies, & &1.tally.average_rank, :asc)

        _ ->
          # For other types, sort by score (higher is better)
          Enum.sort_by(options_with_tallies, & &1.tally.score, :desc)
      end

    %{
      poll_id: poll.id,
      poll_title: poll.title,
      voting_system: poll.voting_system,
      total_unique_voters: count_unique_voters(poll_with_options),
      options_with_tallies: sorted_options
    }
  end

  # Helper functions for different voting system tallies

  defp get_binary_option_tally(votes) do
    tally =
      Enum.reduce(votes, %{yes: 0, maybe: 0, no: 0, total: 0}, fn vote, acc ->
        vote_type =
          case vote.vote_value do
            "yes" -> :yes
            "maybe" -> :maybe
            "no" -> :no
            _ -> :unknown
          end

        if vote_type != :unknown do
          acc
          |> Map.update!(vote_type, &(&1 + 1))
          |> Map.update!(:total, &(&1 + 1))
        else
          acc
        end
      end)

    # Calculate weighted score (yes: 1.0, maybe: 0.5, no: 0.0) - same as legacy
    score = tally.yes * 1.0 + tally.maybe * 0.5
    max_possible_score = if tally.total > 0, do: tally.total * 1.0, else: 1.0
    percentage = if tally.total > 0, do: score / max_possible_score * 100, else: 0.0

    # Calculate individual percentages
    yes_percentage = if tally.total > 0, do: tally.yes / tally.total * 100, else: 0.0
    maybe_percentage = if tally.total > 0, do: tally.maybe / tally.total * 100, else: 0.0
    no_percentage = if tally.total > 0, do: tally.no / tally.total * 100, else: 0.0

    Map.merge(tally, %{
      score: score,
      percentage: Float.round(percentage, 1),
      yes_percentage: Float.round(yes_percentage, 1),
      maybe_percentage: Float.round(maybe_percentage, 1),
      no_percentage: Float.round(no_percentage, 1),
      vote_distribution: [
        %{type: "yes", count: tally.yes, percentage: yes_percentage},
        %{type: "maybe", count: tally.maybe, percentage: maybe_percentage},
        %{type: "no", count: tally.no, percentage: no_percentage}
      ]
    })
  end

  defp get_approval_option_tally(votes) do
    total = length(votes)
    # In approval voting, all votes are "selected"
    selected = total

    # Score is simply the number of selections
    score = selected

    # Percentage is how many people selected this option (calculated later relative to total poll voters)

    %{
      selected: selected,
      total: total,
      score: score,
      # Will be recalculated relative to total poll voters
      percentage: 100.0,
      vote_distribution: [
        %{type: "selected", count: selected, percentage: 100.0}
      ]
    }
  end

  defp get_star_option_tally(votes) do
    total = length(votes)

    if total == 0 do
      %{
        total: 0,
        score: 0.0,
        percentage: 0.0,
        average_rating: 0.0,
        rating_distribution: [],
        vote_distribution: []
      }
    else
      # Group votes by rating
      rating_counts =
        Enum.reduce(votes, %{}, fn vote, acc ->
          rating = vote.vote_numeric |> Decimal.to_float() |> round()
          Map.update(acc, rating, 1, &(&1 + 1))
        end)

      # Calculate average rating
      total_rating_sum =
        Enum.reduce(votes, 0, fn vote, sum ->
          rating = vote.vote_numeric |> Decimal.to_float()
          sum + rating
        end)

      average_rating = total_rating_sum / total

      # Calculate score (0-100 based on average rating out of 5)
      score = average_rating / 5.0 * 100
      percentage = score

      # Build rating distribution
      rating_distribution =
        for rating <- 1..5 do
          count = Map.get(rating_counts, rating, 0)
          rating_percentage = if total > 0, do: count / total * 100, else: 0.0
          %{rating: rating, count: count, percentage: Float.round(rating_percentage, 1)}
        end

      vote_distribution =
        Enum.map(rating_distribution, fn %{rating: rating, count: count, percentage: perc} ->
          %{type: "#{rating}_star", count: count, percentage: perc}
        end)

      %{
        total: total,
        score: Float.round(score, 1),
        percentage: Float.round(percentage, 1),
        average_rating: Float.round(average_rating, 2),
        rating_distribution: rating_distribution,
        vote_distribution: vote_distribution
      }
    end
  end

  defp get_ranked_option_tally(votes) do
    total = length(votes)

    if total == 0 do
      %{
        total: 0,
        score: 0.0,
        percentage: 0.0,
        # High number for unranked
        average_rank: 999.0,
        rank_distribution: [],
        vote_distribution: []
      }
    else
      # Group votes by rank
      rank_counts =
        Enum.reduce(votes, %{}, fn vote, acc ->
          rank = vote.vote_rank
          Map.update(acc, rank, 1, &(&1 + 1))
        end)

      # Calculate average rank (lower is better)
      total_rank_sum =
        Enum.reduce(votes, 0, fn vote, sum ->
          sum + vote.vote_rank
        end)

      average_rank = total_rank_sum / total

      # Calculate score (inverse of average rank - higher rank = lower score)
      # Score is 100 / average_rank, so rank 1 = 100 points, rank 2 = 50 points, etc.
      score = if average_rank > 0, do: 100.0 / average_rank, else: 0.0
      # Cap at 100%
      percentage = min(score, 100.0)

      # Build rank distribution
      max_rank = Map.keys(rank_counts) |> Enum.max()

      rank_distribution =
        for rank <- 1..max_rank do
          count = Map.get(rank_counts, rank, 0)
          rank_percentage = if total > 0, do: count / total * 100, else: 0.0
          %{rank: rank, count: count, percentage: Float.round(rank_percentage, 1)}
        end

      vote_distribution =
        Enum.map(rank_distribution, fn %{rank: rank, count: count, percentage: perc} ->
          %{type: "rank_#{rank}", count: count, percentage: perc}
        end)

      %{
        total: total,
        score: Float.round(score, 1),
        percentage: Float.round(percentage, 1),
        average_rank: Float.round(average_rank, 2),
        rank_distribution: rank_distribution,
        vote_distribution: vote_distribution
      }
    end
  end

  defp get_generic_option_tally(votes) do
    total = length(votes)

    %{
      total: total,
      score: total,
      percentage: if(total > 0, do: 100.0, else: 0.0),
      vote_distribution: [
        %{type: "vote", count: total, percentage: if(total > 0, do: 100.0, else: 0.0)}
      ]
    }
  end

  @doc """
  Gets real-time voting statistics for display on public pages.
  Similar to legacy system but works for all poll types.
  """
  def get_poll_voting_stats(%Poll{} = poll) do
    enhanced_tallies = get_enhanced_poll_vote_tallies(poll)
    total_voters = enhanced_tallies.total_unique_voters

    # Calculate relative percentages for approval voting
    options_with_stats =
      Enum.map(enhanced_tallies.options_with_tallies, fn %{option: option, tally: tally} ->
        relative_tally =
          case poll.voting_system do
            "approval" ->
              # For approval voting, calculate percentage relative to total poll voters
              selection_percentage =
                if total_voters > 0, do: tally.selected / total_voters * 100, else: 0.0

              Map.merge(tally, %{
                percentage: Float.round(selection_percentage, 1),
                vote_distribution: [
                  %{
                    type: "selected",
                    count: tally.selected,
                    percentage: Float.round(selection_percentage, 1)
                  }
                ]
              })

            _ ->
              tally
          end

        %{
          option_id: option.id,
          option_title: option.title,
          option_description: option.description,
          tally: relative_tally
        }
      end)

    # Add IRV results for ranked choice polls
    irv_results =
      if poll.voting_system == "ranked" do
        alias EventasaurusApp.Events.RankedChoiceVoting
        RankedChoiceVoting.calculate_irv_winner(poll)
      else
        nil
      end

    base_stats = %{
      poll_id: poll.id,
      poll_title: poll.title,
      voting_system: poll.voting_system,
      phase: poll.phase,
      total_unique_voters: total_voters,
      options: options_with_stats
    }

    # Add IRV results if applicable
    if irv_results do
      Map.put(base_stats, :irv_results, irv_results)
    else
      base_stats
    end
  end

  @doc """
  Broadcasts poll statistics update to all connected clients.
  Used for real-time updates when votes are cast.
  """
  def broadcast_poll_stats_update(%Poll{} = poll) do
    stats = get_poll_voting_stats(poll)

    # Use BroadcastThrottler for efficient real-time updates
    EventasaurusWeb.Services.BroadcastThrottler.throttle_poll_stats_broadcast(
      poll.id,
      stats,
      poll.event_id
    )

    stats
  end

  # Event Activity Tracking Functions

  @doc """
  Lists activities for an event.
  """
  def list_event_activities(%Event{} = event, opts \\ []) do
    query =
      from(a in EventActivity,
        where: a.event_id == ^event.id,
        order_by: [desc: a.occurred_at, desc: a.inserted_at],
        preload: [:created_by]
      )

    query = if limit = opts[:limit], do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  @doc """
  Lists activities for a group.
  """
  def list_group_activities(group_id, opts \\ []) do
    query =
      from(a in EventActivity,
        where: a.group_id == ^group_id,
        order_by: [desc: a.occurred_at, desc: a.inserted_at],
        preload: [:created_by, :event]
      )

    query =
      if activity_type = opts[:activity_type] do
        where(query, [a], a.activity_type == ^activity_type)
      else
        query
      end

    query = if limit = opts[:limit], do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  @doc """
  Gets a single event activity.
  """
  def get_event_activity!(id),
    do: Repo.get!(EventActivity, id) |> Repo.preload([:event, :created_by])

  @doc """
  Creates an event activity.
  """
  def create_event_activity(attrs \\ %{}) do
    # If event_id is provided but group_id is not, try to get group_id from event
    event_id = Map.get(attrs, :event_id) || Map.get(attrs, "event_id")
    group_id = Map.get(attrs, :group_id) || Map.get(attrs, "group_id")

    attrs =
      case {event_id, group_id} do
        {event_id, nil} when not is_nil(event_id) ->
          case get_event(event_id) do
            %Event{group_id: group_id} when not is_nil(group_id) ->
              Map.put(attrs, :group_id, group_id)

            _ ->
              attrs
          end

        _ ->
          attrs
      end

    %EventActivity{}
    |> EventActivity.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an event activity.
  If group_id is not set on the activity, tries to inherit it from the event.
  """
  def update_event_activity(%EventActivity{} = activity, attrs) do
    # If the activity has no group_id, try to get it from the event
    attrs =
      if is_nil(activity.group_id) do
        case get_event(activity.event_id) do
          %Event{group_id: event_group_id} when not is_nil(event_group_id) ->
            Map.put(attrs, :group_id, event_group_id)

          _ ->
            attrs
        end
      else
        attrs
      end

    activity
    |> EventActivity.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an event activity.
  """
  def delete_event_activity(%EventActivity{} = activity) do
    Repo.delete(activity)
  end

  @doc """
  Backfills group_id for activities that are missing it.
  This is useful for fixing historical data where group_id wasn't properly set.
  Returns the count of updated activities.
  """
  def backfill_activity_group_ids do
    # Find all activities with nil group_id where the event has a group_id
    from(a in EventActivity,
      join: e in Event,
      on: a.event_id == e.id,
      where: is_nil(a.group_id) and not is_nil(e.group_id),
      select: {a.id, e.group_id}
    )
    |> Repo.all()
    |> Enum.reduce(0, fn {activity_id, group_id}, count ->
      from(a in EventActivity, where: a.id == ^activity_id)
      |> Repo.update_all(set: [group_id: group_id])

      count + 1
    end)
  end

  @doc """
  Creates an activity from a poll winner.
  Automatically called when a poll is finalized.
  """
  def create_activity_from_poll(%Poll{} = poll, winning_option_id, user_id) do
    with %PollOption{} = option <- Repo.get(PollOption, winning_option_id) do
      metadata = build_activity_metadata_from_poll_option(poll.poll_type, option)

      create_event_activity(%{
        event_id: poll.event_id,
        activity_type: poll_type_to_activity_type(poll.poll_type),
        metadata: metadata,
        occurred_at: DateTime.utc_now(),
        created_by_id: user_id,
        source: "poll_winner"
      })
    end
  end

  defp poll_type_to_activity_type("movie"), do: "movie_watched"
  defp poll_type_to_activity_type("game"), do: "game_played"
  defp poll_type_to_activity_type("places"), do: "place_visited"
  defp poll_type_to_activity_type("venue_selection"), do: "place_visited"
  defp poll_type_to_activity_type(_), do: "activity_completed"

  defp build_activity_metadata_from_poll_option("movie", %PollOption{} = option) do
    # Extract movie data from external_data
    case option.external_data do
      %{"tmdb_id" => tmdb_id} = data ->
        %{
          "tmdb_id" => tmdb_id,
          "title" => data["title"] || option.title,
          "year" => data["year"],
          "poster_url" => data["poster_url"],
          "rating" => data["rating"]
        }

      _ ->
        %{"title" => option.title, "description" => option.description}
    end
  end

  defp build_activity_metadata_from_poll_option(_, %PollOption{} = option) do
    # Generic metadata for other poll types
    metadata = %{
      "title" => option.title,
      "description" => option.description
    }

    # Include external_data if present
    if option.external_data && map_size(option.external_data) > 0 do
      Map.merge(metadata, option.external_data)
    else
      metadata
    end
  end

  @doc """
  Counts activities by type for a group.
  """
  def count_group_activities_by_type(group_id) do
    from(a in EventActivity,
      where: a.group_id == ^group_id,
      group_by: a.activity_type,
      select: {a.activity_type, count(a.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Checks if an activity already exists (to avoid duplicates).
  """
  def activity_exists?(event_id, activity_type, metadata_match) when is_map(metadata_match) do
    from(a in EventActivity,
      where: a.event_id == ^event_id and a.activity_type == ^activity_type,
      where: fragment("? @> ?", a.metadata, ^metadata_match)
    )
    |> Repo.exists?()
  end

  # Private helper to schedule deadline reminder notifications for threshold events
  defp maybe_schedule_deadline_reminder(
         %Event{status: :threshold, polling_deadline: deadline} = event
       )
       when not is_nil(deadline) do
    case DeadlineReminderNotificationJob.schedule_for_deadline(event) do
      {:ok, _job} ->
        Logger.info("Scheduled deadline reminder for event #{event.id} at #{deadline}")

      {:error, reason} ->
        Logger.warning(
          "Failed to schedule deadline reminder for event #{event.id}: #{inspect(reason)}"
        )
    end
  end

  defp maybe_schedule_deadline_reminder(_event), do: :ok
end
