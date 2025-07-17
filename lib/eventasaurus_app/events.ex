defmodule EventasaurusApp.Events do
  @moduledoc """
  The Events context.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{Event, EventUser, EventParticipant}
  alias EventasaurusApp.EventStateMachine
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Themes
  alias EventasaurusApp.Events.EventDateVote
  alias EventasaurusApp.Venues.Venue

  # Generic polling system aliases
  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}

  alias EventasaurusApp.GuestInvitations
  require Logger

  @doc """
  Returns the list of events.

  ## Examples

      iex> list_events()
      [%Event{}, ...]

  """
  def list_events do
    Repo.all(Event)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that are currently active (not ended or canceled).
  """
  def list_active_events do
    query = from e in Event,
            where: e.status != ^:canceled and (is_nil(e.ends_at) or e.ends_at > ^DateTime.utc_now()),
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that have active polls.
  """
  def list_polling_events do
    current_time = DateTime.utc_now()

    query = from e in Event,
            where: e.status == :polling and
                   not is_nil(e.polling_deadline) and
                   e.polling_deadline > ^current_time,
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that can sell tickets.
  """
  def list_ticketed_events do
    query = from e in Event,
            where: e.status == :confirmed,
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
    |> Enum.filter(& &1.can_sell_tickets?)
  end

  @doc """
  Returns the list of events that have ended.
  """
  def list_ended_events do
    current_time = DateTime.utc_now()

    query = from e in Event,
            where: not is_nil(e.ends_at) and e.ends_at < ^current_time,
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that are currently in threshold pre-sale mode.
  """
  def list_threshold_events do
    query = from e in Event,
            where: e.status == :threshold,
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events filtered by threshold type.

  ## Parameters
  - threshold_type: "attendee_count", "revenue", or "both"
  """
  def list_events_by_threshold_type(threshold_type) when threshold_type in ["attendee_count", "revenue", "both"] do
    query = from e in Event,
            where: e.threshold_type == ^threshold_type,
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events that have met their threshold requirements.
  """
  def list_threshold_met_events do
    list_threshold_events()
    |> Enum.filter(&EventasaurusApp.EventStateMachine.threshold_met?/1)
  end

  @doc """
  Returns the list of events that have NOT yet met their threshold requirements.
  """
  def list_threshold_pending_events do
    list_threshold_events()
    |> Enum.reject(&EventasaurusApp.EventStateMachine.threshold_met?/1)
  end

  @doc """
  Returns the list of events filtered by minimum revenue threshold.

  ## Parameters
  - min_revenue_cents: Minimum revenue threshold in cents
  """
  def list_events_by_min_revenue(min_revenue_cents) when is_integer(min_revenue_cents) do
    query = from e in Event,
            where: e.threshold_type in ["revenue", "both"] and
                   not is_nil(e.threshold_revenue_cents) and
                   e.threshold_revenue_cents >= ^min_revenue_cents,
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Returns the list of events filtered by minimum attendee count threshold.

  ## Parameters
  - min_attendee_count: Minimum attendee count threshold
  """
  def list_events_by_min_attendee_count(min_attendee_count) when is_integer(min_attendee_count) do
    query = from e in Event,
            where: e.threshold_type in ["attendee_count", "both"] and
                   not is_nil(e.threshold_count) and
                   e.threshold_count >= ^min_attendee_count,
            preload: [:venue, :users]

    Repo.all(query)
    |> Enum.map(&Event.with_computed_fields/1)
  end

  @doc """
  Gets a single event.

  Raises `Ecto.NoResultsError` if the Event does not exist.
  """
  def get_event!(id), do: Repo.get!(Event, id) |> Repo.preload([:venue, :users]) |> Event.with_computed_fields()

  @doc """
  Gets a single event.

  Returns nil if the Event does not exist.
  """
  def get_event(id), do: Repo.get(Event, id) |> maybe_preload()

  defp maybe_preload(nil), do: nil
  defp maybe_preload(event), do: Repo.preload(event, [:venue, :users]) |> Event.with_computed_fields()

  @doc """
  Gets a single event by slug.

  Returns nil if the Event does not exist.
  """
  def get_event_by_slug(slug) do
    Repo.get_by(Event, slug: slug)
    |> Repo.preload([:venue, :users])
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
    Repo.get_by!(Event, slug: slug)
    |> Repo.preload([:venue, :users])
  end

  @doc """
  Gets a single event by title.

  Returns `nil` if the Event does not exist.

  ## Examples

      iex> get_event_by_title("My Event")
      %Event{}

      iex> get_event_by_title("Non-existent")
      nil

  """
  def get_event_by_title(title) do
    case Repo.get_by(Event, title: title) do
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
    result = %Event{}
    |> Event.changeset_with_inferred_status(attrs)
    |> Repo.insert()

    case result do
      {:ok, event} ->
        event
        |> Repo.preload([:venue, :users])
        |> Event.with_computed_fields()
        |> then(&{:ok, &1})
      error -> error
    end
  end

  @doc """
  Updates an event with automatic status inference.

  Similar to create_event/1, the status is automatically inferred based on
  the updated attributes. Virtual computed fields are automatically populated
  in the returned event.
  """
  def update_event(%Event{} = event, attrs) do
    result = event
    |> Event.changeset_with_inferred_status(attrs)
    |> Repo.update()

    case result do
      {:ok, updated_event} ->
        updated_event
        |> Repo.preload([:venue, :users])
        |> Event.with_computed_fields()
        |> then(&{:ok, &1})
      error -> error
    end
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
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
        {:error, reason} -> Repo.rollback(reason)
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
      corrected_attrs = case inferred_status do
        :canceled -> Map.put(corrected_attrs, :canceled_at, DateTime.utc_now())
        _ -> Map.delete(corrected_attrs, :canceled_at)  # Clear canceled_at when moving away from canceled
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
  def list_events_by_user(%User{} = user) do
    query = from e in Event,
            join: eu in EventUser, on: e.id == eu.event_id,
            where: eu.user_id == ^user.id,
            preload: [:venue, :users]

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
    existing_organizer_ids = from(eu in EventUser,
                                  where: eu.event_id == ^event.id,
                                  select: eu.user_id)
                            |> Repo.all()

    # Filter out user IDs that are already organizers and deduplicate
    new_user_ids =
      user_ids
      |> Enum.uniq()
      |> Kernel.--(existing_organizer_ids)

    # Prepare organizer records for bulk insert
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    organizer_records = Enum.map(new_user_ids, fn user_id ->
      %{
        event_id: event.id,
        user_id: user_id,
        role: nil,
        inserted_at: timestamp,
        updated_at: timestamp
      }
    end)

    case organizer_records do
      [] -> 0  # No new organizers to add
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
    query = from u in User,
            join: eu in EventUser, on: u.id == eu.user_id,
            where: eu.event_id == ^event.id

    Repo.all(query)
  end

  @doc """
  Checks if a user is an organizer of an event.
  """
  def user_is_organizer?(%Event{} = event, %User{} = user) do
    query = from eu in EventUser,
            where: eu.event_id == ^event.id and eu.user_id == ^user.id,
            select: count(eu.id)

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
           {:ok, _} <- add_user_to_event(event, user) do
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
    %EventParticipant{}
    |> EventParticipant.changeset(attrs)
    |> Repo.insert()
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
    Repo.transaction(fn ->
      case Repo.get_by(EventParticipant, event_id: event_id, user_id: user_id) do
        nil ->
          # No existing participant, create new one
          participant_attrs = Map.merge(attrs, %{
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
    query = from ep in EventParticipant,
            where: ep.event_id == ^event.id,
            preload: [:user, :invited_by_user]

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
  def list_events_with_participation(%User{} = user) do
    query = from e in Event,
            join: ep in EventParticipant, on: e.id == ep.event_id,
            where: ep.user_id == ^user.id,
            preload: [:venue, :users]

    Repo.all(query)
  end

  @doc """
  Get an event participant by event and user.
  """
  def get_event_participant_by_event_and_user(%Event{} = event, %User{} = user) do
    Repo.get_by(EventParticipant, event_id: event.id, user_id: user.id)
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
    alias EventasaurusApp.Auth.Client
    alias EventasaurusApp.Auth.SupabaseSync
    alias EventasaurusApp.Accounts

    Logger.debug("Starting user registration process", %{
      event_id: event_id,
      name: name,
      email_domain: email |> String.split("@") |> List.last()
    })

    Repo.transaction(fn ->
      # Get the event (handle exception)
      event = try do
        get_event!(event_id)
      rescue
        Ecto.NoResultsError ->
          Logger.error("Event not found", %{event_id: event_id})
          Repo.rollback(:event_not_found)
      end
      Logger.debug("Event found for registration", %{event_title: event.title, event_id: event.id})

      # Get the user from the database to update socket assigns
      user = case Accounts.get_user_by_email(email) do
        nil -> nil
        user -> user
      end

      if user do
        Logger.debug("Existing user found in local database", %{user_id: user.id})
      else
        Logger.debug("No existing user found in local database")
      end

      user = case user do
        nil ->
          # User doesn't exist locally, check Supabase and create if needed
          Logger.info("User not found locally, attempting Supabase user creation/lookup")
          case create_or_find_supabase_user(email, name) do
            {:ok, supabase_user} ->
              Logger.info("Successfully created/found user in Supabase")
              # Sync with local database
              case SupabaseSync.sync_user(supabase_user) do
                {:ok, user} ->
                  Logger.info("Successfully synced user to local database", %{user_id: user.id})
                  user
                {:error, reason} ->
                  Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
                  Repo.rollback(reason)
              end
                          {:error, :user_confirmation_required} ->
                # User was created via OTP but email confirmation is required
                Logger.info("User created via OTP but email confirmation required, creating temporary local user record")
                # Create user with pending confirmation ID - TODO: implement cleanup for unconfirmed users
                temp_supabase_id = "pending_confirmation_#{Ecto.UUID.generate()}"
                case Accounts.create_user(%{
                  email: email,
                  name: name,
                  supabase_id: temp_supabase_id  # Temporary ID - will be updated when user confirms email
                }) do
                  {:ok, user} ->
                    Logger.info("Successfully created temporary local user", %{user_id: user.id, temp_supabase_id: temp_supabase_id})
                    user
                  {:error, reason} ->
                    Logger.error("Failed to create temporary local user", %{reason: inspect(reason)})
                    Repo.rollback(reason)
                end
              {:error, :invalid_user_data} ->
                Logger.error("Invalid user data from Supabase after OTP creation")
                Repo.rollback(:invalid_user_data)
            {:error, reason} ->
              Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
              Repo.rollback(reason)
          end

        user ->
          # User exists locally
          Logger.debug("Using existing local user", %{user_id: user.id})
          user
      end

      # Check if user is already registered for this event
      case get_event_participant_by_event_and_user(event, user) do
        nil ->
          Logger.debug("User not yet registered for event, creating participant record", %{
            user_id: user.id,
            event_id: event.id
          })
          # User not registered, create participant record
          participant_attrs = %{
            event_id: event.id,
            user_id: user.id,
            role: :invitee,
            status: :pending,
            source: "public_registration",
            metadata: %{
              registration_date: DateTime.utc_now(),
              registered_name: name
            }
          }

          case create_event_participant(participant_attrs) do
            {:ok, participant} ->
              Logger.info("Successfully created event participant", %{
                participant_id: participant.id,
                user_id: user.id,
                event_id: event.id
              })
              if user do
                {:existing_user_registered, participant}
              else
                {:new_registration, participant}
              end
            {:error, reason} ->
              Logger.error("Failed to create event participant", %{reason: inspect(reason)})
              Repo.rollback(reason)
          end

        _participant ->
          Logger.info("User already registered for event", %{user_id: user.id, event_id: event.id})
          Repo.rollback(:already_registered)
      end
    end)
    |> case do
      {:ok, result} ->
        Logger.info("Registration transaction completed successfully", %{
          result_type: elem(result, 0),
          participant_id: elem(result, 1).id
        })
        {:ok, elem(result, 0), elem(result, 1)}
      {:error, reason} ->
        Logger.warning("Registration transaction failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Get registration status for a user and event.
  Returns one of: :not_registered, :registered, :cancelled, :organizer
  """
  def get_user_registration_status(%Event{} = event, user) do
    # Handle both User structs and Supabase user data
    local_user = case user do
      %User{} = u -> u
      %{"id" => _supabase_id} = supabase_user ->
        # Use shared function to find or create user
        case Accounts.find_or_create_from_supabase(supabase_user) do
          {:ok, user} -> user
          {:error, reason} ->
            require Logger
            Logger.error("Failed to create user for registration status check", %{
              reason: inspect(reason),
              supabase_id: supabase_user["id"]
            })
            :error
        end
      _ -> nil
    end

    case local_user do
      nil -> :not_registered
      :error -> :error
      user ->
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
    end
  end

  @doc """
  Cancel a user's registration for an event.
  """
  def cancel_user_registration(%Event{} = event, %User{} = user) do
    case get_event_participant_by_event_and_user(event, user) do
      nil -> {:error, :not_registered}
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

  @doc """
  Creates or finds a Supabase user by email and name.

  This function is used by both event registration and ticket purchase flows
  to ensure consistent user creation patterns.

  Returns:
  - {:ok, supabase_user} - User found or created successfully
  - {:error, :user_confirmation_required} - User created but email confirmation required
  - {:error, :invalid_user_data} - Invalid user data returned from Supabase
  - {:error, reason} - Other errors
  """
  def create_or_find_supabase_user(email, name) do
    alias EventasaurusApp.Auth.Client
    require Logger

    Logger.debug("Starting passwordless Supabase user creation for event", %{
      email_domain: email |> String.split("@") |> List.last(),
      name: name
    })

    # First check if user exists in Supabase
    case Client.admin_get_user_by_email(email) do
      {:ok, nil} ->
        # User doesn't exist, create them via passwordless OTP
        Logger.info("User not found in Supabase, creating with passwordless OTP")
        user_metadata = %{name: name}

        case Client.sign_in_with_otp(email, user_metadata) do
          {:ok, _response} ->
            Logger.info("Successfully initiated passwordless signup", %{
              email_domain: email |> String.split("@") |> List.last()
            })

            # After OTP creation, the user should exist in Supabase
            # Try to fetch the user data again (no sleep - if timing is an issue, we'll handle it differently)
            case Client.admin_get_user_by_email(email) do
              {:ok, supabase_user} when not is_nil(supabase_user) ->
                Logger.info("Successfully retrieved user data after OTP creation", %{
                  user_id: supabase_user["id"],
                  email: supabase_user["email"],
                  has_metadata: !is_nil(supabase_user["user_metadata"]),
                  confirmed_at: supabase_user["confirmed_at"],
                  email_confirmed_at: supabase_user["email_confirmed_at"]
                })

                # Additional validation - ensure we have the required fields
                if is_nil(supabase_user["id"]) or is_nil(supabase_user["email"]) do
                  Logger.error("Supabase user data missing required fields", %{
                    has_id: !is_nil(supabase_user["id"]),
                    has_email: !is_nil(supabase_user["email"]),
                    user_keys: Map.keys(supabase_user)
                  })
                  {:error, :invalid_user_data}
                else
                  {:ok, supabase_user}
                end

              {:ok, nil} ->
                # User still doesn't exist - this might happen due to timing or confirmation requirements
                Logger.warning("User not found after OTP creation - email confirmation may be required")
                {:error, :user_confirmation_required}
              {:error, reason} ->
                Logger.error("Failed to retrieve user after OTP creation", %{reason: inspect(reason)})
                {:error, reason}
            end
          {:error, reason} ->
            Logger.error("Failed to create passwordless user", %{reason: inspect(reason)})
            {:error, reason}
        end

      {:ok, supabase_user} ->
        # User exists in Supabase
        Logger.debug("User already exists in Supabase", %{
          supabase_user_id: supabase_user["id"],
          email_domain: email |> String.split("@") |> List.last()
        })
        {:ok, supabase_user}

      {:error, reason} ->
        Logger.error("Error checking for user in Supabase", %{reason: inspect(reason)})
        {:error, reason}
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
  def update_event_theme_customizations(%Event{} = event, customizations) when is_map(customizations) do
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
        {:error, Ecto.Changeset.add_error(changeset, :status, "invalid transition from '#{event.status}' to '#{new_state}': #{reason}")}
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

  # EventDatePoll Functions

  alias EventasaurusApp.Events.EventDatePoll

  @doc """
  Creates a date poll for an event.
  """
  def create_event_date_poll(%Event{} = event, %User{} = creator, attrs \\ %{}) do
    poll_attrs = Map.merge(attrs, %{
      event_id: event.id,
      created_by_id: creator.id
    })

    %EventDatePoll{}
    |> EventDatePoll.creation_changeset(poll_attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the date poll for an event.
  """
  def get_event_date_poll(%Event{} = event) do
    Repo.get_by(EventDatePoll, event_id: event.id)
    |> Repo.preload([:event, :created_by, :date_options])
  end

  @doc """
  Gets a date poll by ID.
  """
  def get_event_date_poll!(id) do
    Repo.get!(EventDatePoll, id)
    |> Repo.preload([:event, :created_by, :date_options])
  end

  @doc """
  Updates a date poll.
  """
  def update_event_date_poll(%EventDatePoll{} = poll, attrs) do
    poll
    |> EventDatePoll.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Finalizes a date poll with the selected date.
  """
  def finalize_event_date_poll(%EventDatePoll{} = poll, selected_date) do
    Repo.transaction(fn ->
      # Update the poll with the finalized date
      with {:ok, updated_poll} <- poll
                                   |> EventDatePoll.finalization_changeset(selected_date)
                                   |> Repo.update(),
           # Update the event's start_at and state - preserve original time
           {:ok, updated_event} <- poll.event
                                   |> Event.changeset(%{
                                     start_at: DateTime.new!(selected_date, DateTime.to_time(poll.event.start_at), poll.event.start_at.time_zone),
                                     status: :confirmed
                                   })
                                   |> Repo.update() do
        {updated_poll, updated_event}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Deletes a date poll.
  """
  def delete_event_date_poll(%EventDatePoll{} = poll) do
    Repo.delete(poll)
  end

  @doc """
  Checks if an event has an active date poll.
  """
  def has_active_date_poll?(%Event{} = event) do
    case get_event_date_poll(event) do
      nil -> false
      poll -> EventDatePoll.active?(poll)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking date poll changes.
  """
  def change_event_date_poll(%EventDatePoll{} = poll, attrs \\ %{}) do
    EventDatePoll.changeset(poll, attrs)
  end

  # EventDateOption Functions

  alias EventasaurusApp.Events.EventDateOption

  @doc """
  Creates a date option for a poll.
  """
  def create_event_date_option(%EventDatePoll{} = poll, date) when is_binary(date) or is_struct(date, Date) do
    date_value = case date do
      %Date{} = d -> d
      date_string when is_binary(date_string) -> Date.from_iso8601!(date_string)
    end

    %EventDateOption{}
    |> EventDateOption.creation_changeset(%{
      event_date_poll_id: poll.id,
      date: date_value
    })
    |> Repo.insert()
  end

  @doc """
  Creates multiple date options for a poll from a date range.
  """
  def create_date_options_from_range(%EventDatePoll{} = poll, start_date, end_date) do
    start_date = ensure_date_struct(start_date)
    end_date = ensure_date_struct(end_date)

    date_range = Date.range(start_date, end_date)

    Repo.transaction(fn ->
      Enum.map(date_range, fn date ->
        case create_event_date_option(poll, date) do
          {:ok, option} -> option
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Creates multiple date options from a list of dates.
  """
  def create_date_options_from_list(%EventDatePoll{} = poll, dates) when is_list(dates) do
    Repo.transaction(fn ->
      Enum.map(dates, fn date ->
        case create_event_date_option(poll, date) do
          {:ok, option} -> option
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Gets a date option by ID.
  """
  def get_event_date_option!(id) do
    Repo.get!(EventDateOption, id)
    |> Repo.preload(:event_date_poll)
  end

  @doc """
  Gets all date options for a poll, sorted by date.
  """
  def list_event_date_options(%EventDatePoll{} = poll) do
    from(edo in EventDateOption,
      where: edo.event_date_poll_id == ^poll.id,
      order_by: [asc: edo.date]
    )
    |> Repo.all()
  end

  @doc """
  Updates a date option.
  """
  def update_event_date_option(%EventDateOption{} = option, attrs) do
    option
    |> EventDateOption.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a date option.
  """
  def delete_event_date_option(%EventDateOption{} = option) do
    require Logger
    Logger.info("=== DELETE EVENT DATE OPTION START ===")
    Logger.info("Option ID: #{option.id}, Date: #{option.date}")

    # Check if there are any votes for this option
    votes_count = from(v in EventasaurusApp.Events.EventDateVote, where: v.event_date_option_id == ^option.id)
                  |> Repo.aggregate(:count, :id)

    Logger.info("Votes count for option #{option.id}: #{votes_count}")

    result = Repo.delete(option)

    case result do
      {:ok, deleted_option} ->
        Logger.info("Successfully deleted option ID: #{deleted_option.id}")
      {:error, changeset} ->
        Logger.error("Failed to delete option ID: #{option.id}, changeset: #{inspect(changeset)}")
    end

    result
  end

  @doc """
  Deletes all date options for a poll.
  """
  def delete_all_date_options(%EventDatePoll{} = poll) do
    from(edo in EventDateOption, where: edo.event_date_poll_id == ^poll.id)
    |> Repo.delete_all()
  end

  @doc """
  Intelligently updates date options for a poll, preserving existing votes.
  This function only adds new date options and removes date options that are no longer selected,
  keeping existing date options (and their votes) that remain in the selection.
  """
  def update_event_date_options(%EventDatePoll{} = poll, new_dates) do
    require Logger
    Logger.info("=== UPDATE EVENT DATE OPTIONS START ===")
    Logger.info("Poll ID: #{poll.id}")
    Logger.info("New dates input: #{inspect(new_dates)}")

    new_dates =
      new_dates
      |> Enum.map(&ensure_date_struct/1)
      |> Enum.uniq()

    Logger.info("Processed new dates: #{inspect(new_dates)}")

    existing_options = list_event_date_options(poll)
    existing_dates = Enum.map(existing_options, & &1.date)

    Logger.info("Existing options count: #{length(existing_options)}")
    Logger.info("Existing dates: #{inspect(existing_dates)}")

    # Find dates to add and remove
    dates_to_add = new_dates -- existing_dates
    dates_to_remove = existing_dates -- new_dates

    Logger.info("Dates to add: #{inspect(dates_to_add)}")
    Logger.info("Dates to remove: #{inspect(dates_to_remove)}")

    # Early exit if no changes needed
    if dates_to_add == [] and dates_to_remove == [] do
      Logger.info("No changes needed, returning existing options")
      {:ok, existing_options}
    else
      Logger.info("Starting transaction to update date options")
      Repo.transaction(fn ->
        # Remove date options that are no longer selected
        if length(dates_to_remove) > 0 do
          Logger.info("Removing #{length(dates_to_remove)} date options")
          options_to_remove = Enum.filter(existing_options, fn option ->
            option.date in dates_to_remove
          end)

          Logger.info("Options to remove: #{inspect(Enum.map(options_to_remove, &{&1.id, &1.date}))}")

          Enum.each(options_to_remove, fn option ->
            Logger.info("Attempting to delete option ID: #{option.id}, date: #{option.date}")
            case delete_event_date_option(option) do
              {:ok, deleted_option} ->
                Logger.info("Successfully deleted option ID: #{deleted_option.id}")
                :ok
              {:error, changeset} ->
                Logger.error("Failed to delete option ID: #{option.id}, changeset: #{inspect(changeset)}")
                Repo.rollback(changeset)
            end
          end)
        end

        # Add new date options
        if length(dates_to_add) > 0 do
          Logger.info("Adding #{length(dates_to_add)} new date options")
          Enum.each(dates_to_add, fn date ->
            Logger.info("Attempting to create option for date: #{date}")
            case create_event_date_option(poll, date) do
              {:ok, option} ->
                Logger.info("Successfully created option ID: #{option.id} for date: #{date}")
                :ok
              {:error, changeset} ->
                Logger.error("Failed to create option for date: #{date}, changeset: #{inspect(changeset)}")
                Repo.rollback(changeset)
            end
          end)
        end

        # Return the updated list of options
        updated_options = list_event_date_options(poll)
        Logger.info("Transaction completed, returning #{length(updated_options)} options")
        updated_options
      end)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking date option changes.
  """
  def change_event_date_option(%EventDateOption{} = option, attrs \\ %{}) do
    EventDateOption.changeset(option, attrs)
  end

  @doc """
  Check if a date already exists as an option in a poll.
  """
  def date_option_exists?(%EventDatePoll{} = poll, date) do
    date_value = ensure_date_struct(date)

    from(edo in EventDateOption,
      where: edo.event_date_poll_id == ^poll.id and edo.date == ^date_value
    )
    |> Repo.exists?()
  end

  defp ensure_date_struct(%Date{} = date), do: date
  defp ensure_date_struct(date_string) when is_binary(date_string), do: Date.from_iso8601!(date_string)

  # EventDateVote Functions

  alias EventasaurusApp.Events.EventDateVote

  @doc """
  Creates a vote for a date option.
  """
  def create_event_date_vote(%EventDateOption{} = option, %User{} = user, vote_type) do
    %EventDateVote{}
    |> EventDateVote.creation_changeset(%{
      event_date_option_id: option.id,
      user_id: user.id,
      vote_type: vote_type
    })
    |> Repo.insert()
  end

  @doc """
  Gets a vote by ID.
  """
  def get_event_date_vote!(id) do
    Repo.get!(EventDateVote, id)
    |> Repo.preload([:event_date_option, :user])
  end

  @doc """
  Gets a user's vote for a specific date option.
  """
  def get_user_vote_for_option(%EventDateOption{} = option, %User{} = user) do
    Repo.get_by(EventDateVote, event_date_option_id: option.id, user_id: user.id)
    |> Repo.preload([:event_date_option, :user])
  end

  @doc """
  Gets all votes for a specific date option.
  """
  def list_votes_for_date_option(%EventDateOption{} = option) do
    from(v in EventDateVote,
      where: v.event_date_option_id == ^option.id,
      preload: [:user],
      order_by: [asc: v.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets all votes for a poll (across all date options).
  """
  def list_votes_for_poll(%EventDatePoll{} = poll) do
    from(v in EventDateVote,
      join: o in EventDateOption, on: v.event_date_option_id == o.id,
      where: o.event_date_poll_id == ^poll.id,
      preload: [:user, :event_date_option],
      order_by: [asc: o.date, asc: v.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets all votes by a user for a specific poll.
  """
  def list_user_votes_for_poll(%EventDatePoll{} = poll, %User{} = user) do
    from(v in EventDateVote,
      join: o in EventDateOption, on: v.event_date_option_id == o.id,
      where: o.event_date_poll_id == ^poll.id and v.user_id == ^user.id,
      preload: [:event_date_option],
      order_by: [asc: o.date]
    )
    |> Repo.all()
  end

  @doc """
  Updates a user's vote for a date option (upsert operation).
  """
  def cast_vote(%EventDateOption{} = option, %User{} = user, vote_type) do
    case get_user_vote_for_option(option, user) do
      nil ->
        # Create new vote
        create_event_date_vote(option, user, vote_type)

      existing_vote ->
        # Update existing vote
        update_event_date_vote(existing_vote, %{vote_type: vote_type})
    end
  end

  @doc """
  Updates a vote.
  """
  def update_event_date_vote(%EventDateVote{} = vote, attrs) do
    vote
    |> EventDateVote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a vote.
  """
  def delete_event_date_vote(%EventDateVote{} = vote) do
    Repo.delete(vote)
  end

  @doc """
  Removes a user's vote for a specific date option.
  """
  def remove_user_vote(%EventDateOption{} = option, %User{} = user) do
    case get_user_vote_for_option(option, user) do
      nil -> {:ok, :no_vote_found}
      vote -> delete_event_date_vote(vote)
    end
  end

  def remove_user_vote(%PollOption{} = poll_option, %User{} = user) do
    case get_user_poll_vote(poll_option, user) do
      nil ->
        {:ok, :no_vote_found}
      vote ->
        case Repo.delete(vote) do
          {:ok, deleted_vote} ->
            # Broadcast poll updates
            poll = Repo.get(Poll, poll_option.poll_id)
            if poll do
              broadcast_poll_update(poll, :votes_updated)
              broadcast_poll_stats_update(poll)
            end
            {:ok, deleted_vote}
          error ->
            error
        end
    end
  end



  @doc """
  Gets vote tally for a specific date option.
  """
  def get_date_option_vote_tally(%EventDateOption{} = option) do
    votes = list_votes_for_date_option(option)

    tally = Enum.reduce(votes, %{yes: 0, if_need_be: 0, no: 0, total: 0}, fn vote, acc ->
      acc
      |> Map.update!(vote.vote_type, &(&1 + 1))
      |> Map.update!(:total, &(&1 + 1))
    end)

    # Calculate weighted score (yes: 1.0, if_need_be: 0.5, no: 0.0)
    score = tally.yes * 1.0 + tally.if_need_be * 0.5
    max_possible_score = if tally.total > 0, do: tally.total * 1.0, else: 1.0
    percentage = if tally.total > 0, do: (score / max_possible_score) * 100, else: 0.0

    Map.put(tally, :score, score)
    |> Map.put(:percentage, Float.round(percentage, 1))
  end

  @doc """
  Gets vote tallies for all options in a poll.
  """
  def get_poll_vote_tallies(%EventDatePoll{} = poll) do
    options = list_event_date_options(poll) |> Repo.preload(:votes)

    Enum.map(options, fn option ->
      %{
        option: option,
        tally: get_date_option_vote_tally(option)
      }
    end)
    |> Enum.sort_by(& &1.tally.score, :desc)
  end

  @doc """
  Check if a user has voted for a specific date option.
  """
  def user_has_voted?(%EventDateOption{} = option, %User{} = user) do
    case get_user_vote_for_option(option, user) do
      nil -> false
      _vote -> true
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking vote changes.
  """
  def change_event_date_vote(%EventDateVote{} = vote, attrs \\ %{}) do
    EventDateVote.changeset(vote, attrs)
  end

  @doc """
  Registers a voter and casts their vote for an event date option.

  This function mirrors register_user_for_event but also casts the vote:
  1. Checks if user exists in Supabase Auth (by email)
  2. Creates user if they don't exist (with temporary password)
  3. Checks if user is already registered for event (if not, registers them)
  4. Casts the vote for the specified date option

  Returns:
  - {:ok, :new_voter, participant, vote} - User was created, registered, and vote cast
  - {:ok, :existing_user_voted, participant, vote} - Existing user voted (may or may not have been registered)
  - {:error, reason} - Other errors
  """
  def register_voter_and_cast_vote(event_id, name, email, option, vote_type) do
    alias EventasaurusApp.Auth.SupabaseSync
    alias EventasaurusApp.Accounts
    require Logger
    Logger.info("Starting voter registration and vote casting", %{
      event_id: event_id,
      email: email,
      name: name,
      option_id: option.id,
      vote_type: vote_type
    })

    Repo.transaction(fn ->
      # Get the event (handle exception)
      event = try do
        get_event!(event_id)
      rescue
        Ecto.NoResultsError ->
          Logger.error("Event not found", %{event_id: event_id})
          Repo.rollback(:event_not_found)
      end

      # Check if user exists in our local database first
      existing_user = Accounts.get_user_by_email(email)

      if existing_user do
        Logger.debug("Existing user found in local database", %{user_id: existing_user.id})
      else
        Logger.debug("No existing user found in local database")
      end

      user = case existing_user do
        nil ->
          # User doesn't exist locally, check Supabase and create if needed
          Logger.info("User not found locally, attempting Supabase user creation/lookup")
                        case create_or_find_supabase_user(email, name) do
                {:ok, supabase_user} ->
                  Logger.info("Successfully created/found user in Supabase")
                  # Sync with local database
                  case SupabaseSync.sync_user(supabase_user) do
                    {:ok, user} ->
                      Logger.info("Successfully synced user to local database", %{user_id: user.id})
                      user
                    {:error, reason} ->
                      Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
                      Repo.rollback(reason)
                  end
                {:error, :user_confirmation_required} ->
                  Logger.info("User created via OTP but email confirmation required for voting")
                  Repo.rollback(:email_confirmation_required)
                {:error, reason} ->
                  Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
                  Repo.rollback(reason)
              end

        user ->
          # User exists locally
          Logger.debug("Using existing local user", %{user_id: user.id})
          user
      end

      # Check if user is registered for the event, register if not
      participant = case get_event_participant_by_event_and_user(event, user) do
        nil ->
          Logger.debug("User not registered for event, creating participant record", %{
            user_id: user.id,
            event_id: event.id
          })
          # User not registered, create participant record
          participant_attrs = %{
            event_id: event.id,
            user_id: user.id,
            role: :invitee,
            status: :pending,
            source: "voting_registration",
            metadata: %{
              registration_date: DateTime.utc_now(),
              registered_name: name,
              registered_via_voting: true
            }
          }

          case create_event_participant(participant_attrs) do
            {:ok, participant} ->
              Logger.info("Successfully created event participant for voter", %{
                participant_id: participant.id,
                user_id: user.id,
                event_id: event.id
              })
              participant
            {:error, reason} ->
              Logger.error("Failed to create event participant for voter", %{reason: inspect(reason)})
              Repo.rollback(reason)
          end

        participant ->
          Logger.debug("User already registered for event", %{user_id: user.id, event_id: event.id})
          participant
      end

      # Cast the vote
      case cast_vote(option, user, vote_type) do
        {:ok, vote} ->
          Logger.info("Successfully cast vote", %{
            vote_id: vote.id,
            user_id: user.id,
            option_id: option.id,
            vote_type: vote_type
          })
          if existing_user do
            {:existing_user_voted, participant, vote}
          else
            {:new_voter, participant, vote}
          end
        {:error, reason} ->
          Logger.error("Failed to cast vote", %{reason: inspect(reason)})
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} ->
        Logger.info("Voter registration and vote transaction completed successfully", %{
          result_type: elem(result, 0),
          participant_id: elem(result, 1).id,
          vote_id: elem(result, 2).id
        })
        {:ok, elem(result, 0), elem(result, 1), elem(result, 2)}
      {:error, reason} ->
        Logger.warning("Voter registration and vote transaction failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Casts multiple votes for a user using a single database transaction.

  This function uses Ecto.Multi to perform bulk vote operations efficiently:
  - Handles conflict resolution for existing votes (upsert)
  - Uses Repo.insert_all for new votes
  - Updates existing votes in bulk
  - All operations happen in a single transaction

  votes_data should be a list of maps: [%{option_id: 1, vote_type: :yes}, ...]

  Returns:
  - {:ok, %{inserted: count, updated: count}} on success
  - {:error, reason} on failure
  """
  def bulk_cast_votes(%User{} = user, votes_data) when is_list(votes_data) do
    require Logger
    Logger.info("Starting bulk vote casting", %{
      user_id: user.id,
      vote_count: length(votes_data)
    })

    # Validate vote types before starting
    valid_vote_types = [:yes, :if_need_be, :no]
    invalid_votes = Enum.filter(votes_data, fn %{vote_type: vote_type} ->
      vote_type not in valid_vote_types
    end)

    if length(invalid_votes) > 0 do
      Logger.error("Invalid vote types found in bulk operation", %{invalid_votes: invalid_votes})
      {:error, :invalid_type}
    else
      # Prepare votes data for processing
      option_ids = Enum.map(votes_data, & &1.option_id)

      # Get existing votes for this user and these options
      existing_votes_query = from(v in EventDateVote,
        where: v.user_id == ^user.id and v.event_date_option_id in ^option_ids,
        select: {v.event_date_option_id, v}
      )

      existing_votes_map = existing_votes_query
      |> Repo.all()
      |> Map.new()

      # Separate into updates and inserts
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      {votes_to_update, votes_to_insert} = Enum.reduce(votes_data, {[], []}, fn vote_data, {updates, inserts} ->
        case Map.get(existing_votes_map, vote_data.option_id) do
          nil ->
            # New vote - prepare for insert
            insert_data = %{
              event_date_option_id: vote_data.option_id,
              user_id: user.id,
              vote_type: vote_data.vote_type,
              inserted_at: now,
              updated_at: now
            }
            {updates, [insert_data | inserts]}

          existing_vote ->
            # Existing vote - prepare for update (only if different)
            if existing_vote.vote_type != vote_data.vote_type do
              update_data = {existing_vote.id, %{vote_type: vote_data.vote_type, updated_at: now}}
              {[update_data | updates], inserts}
            else
              # Vote type is the same, no update needed
              {updates, inserts}
            end
        end
      end)

      # Execute the bulk operations using Ecto.Multi
      multi = Ecto.Multi.new()

      # Add insert operations if there are new votes
      multi = if length(votes_to_insert) > 0 do
        Ecto.Multi.insert_all(multi, :insert_votes, EventDateVote, votes_to_insert)
      else
        multi
      end

      # Add update operations if there are votes to update
      multi = if length(votes_to_update) > 0 do
        Enum.reduce(votes_to_update, multi, fn {vote_id, update_attrs}, acc ->
          vote = Repo.get!(EventDateVote, vote_id)
          changeset = EventDateVote.changeset(vote, update_attrs)
          Ecto.Multi.update(acc, {:update_vote, vote_id}, changeset)
        end)
      else
        multi
      end

      # Execute the transaction
      case Repo.transaction(multi) do
        {:ok, results} ->
          inserted_count = case Map.get(results, :insert_votes) do
            {count, _} -> count
            nil -> 0
          end

          updated_count = Enum.count(results, fn {key, _} ->
            case key do
              {:update_vote, _} -> true
              _ -> false
            end
          end)

          Logger.info("Bulk vote casting completed successfully", %{
            user_id: user.id,
            inserted: inserted_count,
            updated: updated_count
          })

          {:ok, %{inserted: inserted_count, updated: updated_count}}

        {:error, operation, reason, _changes} ->
          Logger.error("Bulk vote casting failed", %{
            user_id: user.id,
            operation: operation,
            reason: inspect(reason)
          })
          {:error, reason}
      end
    end
  end

  @doc """
  Registers a voter and casts multiple votes using bulk operations.

  This is an optimized version of register_voter_and_cast_vote that handles
  multiple votes in a single transaction for better performance.

  votes_data should be a list of maps: [%{option: option_struct, vote_type: :yes}, ...]

  Returns:
  - {:ok, result_type, participant, vote_results} on success
  - {:error, reason} on failure
  """
  def register_voter_and_bulk_cast_votes(event_id, name, email, votes_data) when is_list(votes_data) do
    alias EventasaurusApp.Auth.SupabaseSync
    alias EventasaurusApp.Accounts
    require Logger

    Logger.info("Starting voter registration and bulk vote casting", %{
      event_id: event_id,
      email: email,
      name: name,
      vote_count: length(votes_data)
    })

    # Validate vote types before starting transaction
    valid_vote_types = [:yes, :if_need_be, :no]
    invalid_votes = Enum.filter(votes_data, fn %{vote_type: vote_type} ->
      vote_type not in valid_vote_types
    end)

    if length(invalid_votes) > 0 do
      Logger.error("Invalid vote types found", %{invalid_votes: invalid_votes})
      {:error, :invalid_vote_types}
    else
      Repo.transaction(fn ->
        # Get the event (handle exception)
        event = try do
          get_event!(event_id)
        rescue
          Ecto.NoResultsError ->
            Logger.error("Event not found", %{event_id: event_id})
            Repo.rollback(:event_not_found)
        end

        # Check if user exists in our local database first
        existing_user = Accounts.get_user_by_email(email)

        user = case existing_user do
          nil ->
            # User doesn't exist locally, check Supabase and create if needed
            Logger.info("User not found locally, attempting Supabase user creation/lookup")
            case create_or_find_supabase_user(email, name) do
              {:ok, supabase_user} ->
                Logger.info("Successfully created/found user in Supabase")
                # Sync with local database
                case SupabaseSync.sync_user(supabase_user) do
                  {:ok, user} ->
                    Logger.info("Successfully synced user to local database", %{user_id: user.id})
                    user
                  {:error, reason} ->
                    Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
                    Repo.rollback(reason)
                end
              {:error, :user_confirmation_required} ->
                Logger.info("User created via OTP but email confirmation required for voting")
                Repo.rollback(:email_confirmation_required)
              {:error, reason} ->
                Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
                Repo.rollback(reason)
            end

          user ->
            # User exists locally
            Logger.debug("Using existing local user", %{user_id: user.id})
            user
        end

        # Check if user is registered for the event, register if not
        participant = case get_event_participant_by_event_and_user(event, user) do
          nil ->
            Logger.debug("User not registered for event, creating participant record", %{
              user_id: user.id,
              event_id: event.id
            })

            participant_attrs = %{
              event_id: event.id,
              user_id: user.id,
              role: :invitee,
              status: :pending,
              source: "bulk_voting_registration",
              metadata: %{
                registration_date: DateTime.utc_now(),
                registered_name: name,
                registered_via_bulk_voting: true
              }
            }

            case create_event_participant(participant_attrs) do
              {:ok, participant} ->
                Logger.info("Successfully created event participant for bulk voter", %{
                  participant_id: participant.id,
                  user_id: user.id,
                  event_id: event.id
                })
                participant
              {:error, reason} ->
                Logger.error("Failed to create event participant for bulk voter", %{reason: inspect(reason)})
                Repo.rollback(reason)
            end

          participant ->
            Logger.debug("User already registered for event", %{user_id: user.id, event_id: event.id})
            participant
        end

        # Convert votes_data to the format expected by bulk_cast_votes
        bulk_votes_data = Enum.map(votes_data, fn %{option: option, vote_type: vote_type} ->
          %{option_id: option.id, vote_type: vote_type}
        end)

        # Cast all votes using bulk operation
        case bulk_cast_votes(user, bulk_votes_data) do
          {:ok, vote_results} ->
            Logger.info("Successfully cast bulk votes", %{
              user_id: user.id,
              vote_results: vote_results
            })

            result_type = if existing_user, do: :existing_user_voted, else: :new_voter
            {result_type, participant, vote_results}

          {:error, reason} ->
            Logger.error("Failed to cast bulk votes", %{reason: inspect(reason)})
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {result_type, participant, vote_results}} ->
          Logger.info("Bulk voter registration and vote transaction completed successfully", %{
            result_type: result_type,
            participant_id: participant.id,
            vote_results: vote_results
          })
          {:ok, result_type, participant, vote_results}

        {:error, reason} ->
          Logger.warning("Bulk voter registration and vote transaction failed", %{reason: inspect(reason)})
          {:error, reason}
      end
    end
  end

  @doc """
  Registers a voter and casts a single poll vote for anonymous users.

  This function handles single poll votes for anonymous users, creating a user account
  if needed and casting the vote. This is used for simple single-option voting scenarios.

  ## Parameters
  - poll_id: The ID of the poll
  - name: The user's name
  - email: The user's email address
  - poll_option: The poll option being voted on
  - vote_value: The vote value (varies by voting system)

  ## Returns
  - {:ok, :new_voter, participant, vote} - If a new user was created
  - {:ok, :existing_user_voted, participant, vote} - If an existing user voted
  - {:error, reason} - If the operation failed
  """
  def register_voter_and_cast_poll_vote(poll_id, name, email, poll_option, vote_value) do
    alias EventasaurusApp.Auth.SupabaseSync
    alias EventasaurusApp.Accounts
    require Logger

    Logger.info("Starting voter registration and single poll vote casting", %{
      poll_id: poll_id,
      email: email,
      name: name,
      option_id: poll_option.id,
      vote_value: vote_value
    })

    Repo.transaction(fn ->
      # Get the poll and related event
      poll = Repo.get!(Poll, poll_id)
      event = Repo.get!(Event, poll.event_id)

      # Check if user exists in our local database first
      existing_user = Accounts.get_user_by_email(email)

      user = case existing_user do
        nil ->
          # User doesn't exist locally, check Supabase and create if needed
          Logger.info("User not found locally, attempting Supabase user creation/lookup")
          case create_or_find_supabase_user(email, name) do
            {:ok, supabase_user} ->
              Logger.info("Successfully created/found user in Supabase")
              # Sync with local database
              case SupabaseSync.sync_user(supabase_user) do
                {:ok, user} ->
                  Logger.info("Successfully synced user to local database", %{user_id: user.id})
                  user
                {:error, reason} ->
                  Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
                  Repo.rollback(reason)
              end
            {:error, :user_confirmation_required} ->
              Logger.info("User created via OTP but email confirmation required for voting")
              Repo.rollback(:email_confirmation_required)
            {:error, reason} ->
              Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
              Repo.rollback(reason)
          end

        user ->
          # User exists locally
          Logger.debug("Using existing local user", %{user_id: user.id})
          user
      end

      # Check if user is registered for the event, register if not
      participant = case get_event_participant_by_event_and_user(event, user) do
        nil ->
          Logger.debug("User not registered for event, creating participant record", %{
            user_id: user.id,
            event_id: event.id
          })

          participant_attrs = %{
            event_id: event.id,
            user_id: user.id,
            role: :invitee,
            status: :pending,
            source: "poll_voting_registration",
            metadata: %{
              registration_date: DateTime.utc_now(),
              registered_name: name,
              registered_via_poll_voting: true
            }
          }

          case create_event_participant(participant_attrs) do
            {:ok, participant} ->
              Logger.info("Successfully created event participant for poll voter", %{
                participant_id: participant.id,
                user_id: user.id,
                event_id: event.id
              })
              participant
            {:error, reason} ->
              Logger.error("Failed to create event participant for poll voter", %{reason: inspect(reason)})
              Repo.rollback(reason)
          end

        participant ->
          Logger.debug("User already registered for event", %{user_id: user.id, event_id: event.id})
          participant
      end

      # Cast the vote based on the poll's voting system
      vote_data = case poll.voting_system do
        "binary" when vote_value in ["yes", "maybe", "no"] ->
          %{vote_value: vote_value}
        "approval" when vote_value == "selected" ->
          %{vote_value: vote_value}
        "star" when is_number(vote_value) and vote_value >= 1 and vote_value <= 5 ->
          %{vote_numeric: vote_value}
        "ranked" when is_number(vote_value) and vote_value >= 1 ->
          %{vote_rank: vote_value}
        _ ->
          Logger.error("Invalid vote value for voting system", %{
            voting_system: poll.voting_system,
            vote_value: vote_value
          })
          Repo.rollback(:invalid_vote_value)
      end

      case create_poll_vote(poll_option, user, vote_data, poll.voting_system) do
        {:ok, vote} ->
          Logger.info("Successfully cast poll vote", %{
            user_id: user.id,
            poll_id: poll.id,
            option_id: poll_option.id,
            vote_value: vote_value
          })

          result_type = if existing_user, do: :existing_user_voted, else: :new_voter
          {result_type, participant, vote}

        {:error, reason} ->
          Logger.error("Failed to cast poll vote", %{reason: inspect(reason)})
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {result_type, participant, vote}} ->
        Logger.info("Poll voter registration and vote transaction completed successfully", %{
          result_type: result_type,
          participant_id: participant.id,
          vote_id: vote.id
        })
        {:ok, result_type, participant, vote}

      {:error, reason} ->
        Logger.warning("Poll voter registration and vote transaction failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  @doc """
  Registers a voter and casts multiple poll votes for anonymous users.

  This function handles bulk poll votes for anonymous users, creating a user account
  if needed and casting multiple votes in a single transaction. This is used when
  anonymous users have multiple temporary votes stored.

  ## Parameters
  - poll_id: The ID of the poll
  - name: The user's name
  - email: The user's email address
  - temp_votes: The temporary votes in the format from the frontend

  ## Returns
  - {:ok, :new_voter, participant, votes} - If a new user was created
  - {:ok, :existing_user_voted, participant, votes} - If an existing user voted
  - {:error, reason} - If the operation failed
  """
  def register_voter_and_cast_poll_votes(poll_id, name, email, temp_votes) do
    alias EventasaurusApp.Auth.SupabaseSync
    alias EventasaurusApp.Accounts
    require Logger

    Logger.info("Starting voter registration and bulk poll vote casting", %{
      poll_id: poll_id,
      email: email,
      name: name,
      temp_votes: temp_votes
    })

    Repo.transaction(fn ->
      # Get the poll and related event
      poll = Repo.get!(Poll, poll_id)
      event = Repo.get!(Event, poll.event_id)

      # Check if user exists in our local database first
      existing_user = Accounts.get_user_by_email(email)

      user = case existing_user do
        nil ->
          # User doesn't exist locally, check Supabase and create if needed
          Logger.info("User not found locally, attempting Supabase user creation/lookup")
          case create_or_find_supabase_user(email, name) do
            {:ok, supabase_user} ->
              Logger.info("Successfully created/found user in Supabase")
              # Sync with local database
              case SupabaseSync.sync_user(supabase_user) do
                {:ok, user} ->
                  Logger.info("Successfully synced user to local database", %{user_id: user.id})
                  user
                {:error, reason} ->
                  Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
                  Repo.rollback(reason)
              end
            {:error, :user_confirmation_required} ->
              Logger.info("User created via OTP but email confirmation required for voting")
              Repo.rollback(:email_confirmation_required)
            {:error, reason} ->
              Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
              Repo.rollback(reason)
          end

        user ->
          # User exists locally
          Logger.debug("Using existing local user", %{user_id: user.id})
          user
      end

      # Check if user is registered for the event, register if not
      participant = case get_event_participant_by_event_and_user(event, user) do
        nil ->
          Logger.debug("User not registered for event, creating participant record", %{
            user_id: user.id,
            event_id: event.id
          })

          participant_attrs = %{
            event_id: event.id,
            user_id: user.id,
            role: :invitee,
            status: :pending,
            source: "poll_voting_registration",
            metadata: %{
              registration_date: DateTime.utc_now(),
              registered_name: name,
              registered_via_poll_voting: true
            }
          }

          case create_event_participant(participant_attrs) do
            {:ok, participant} ->
              Logger.info("Successfully created event participant for poll voter", %{
                participant_id: participant.id,
                user_id: user.id,
                event_id: event.id
              })
              participant
            {:error, reason} ->
              Logger.error("Failed to create event participant for poll voter", %{reason: inspect(reason)})
              Repo.rollback(reason)
          end

        participant ->
          Logger.debug("User already registered for event", %{user_id: user.id, event_id: event.id})
          participant
      end

      # Convert temp_votes to database format and cast votes
      votes = case cast_temp_votes_for_poll(poll, user, temp_votes) do
        {:ok, votes} ->
          Logger.info("Successfully cast bulk poll votes", %{
            user_id: user.id,
            poll_id: poll.id,
            vote_count: length(votes)
          })
          votes

        {:error, reason} ->
          Logger.error("Failed to cast bulk poll votes", %{reason: inspect(reason)})
          Repo.rollback(reason)
      end

      result_type = if existing_user, do: :existing_user_voted, else: :new_voter
      {result_type, participant, votes}
    end)
    |> case do
      {:ok, {result_type, participant, votes}} ->
        Logger.info("Poll voter registration and bulk vote transaction completed successfully", %{
          result_type: result_type,
          participant_id: participant.id,
          vote_count: length(votes)
        })
        {:ok, result_type, participant, votes}

      {:error, reason} ->
        Logger.warning("Poll voter registration and bulk vote transaction failed", %{reason: inspect(reason)})
        {:error, reason}
    end
  end

  # Helper function to cast temp votes for a poll
  defp cast_temp_votes_for_poll(poll, user, temp_votes) do
    # Handle different temp vote formats based on voting system
    case poll.voting_system do
      "binary" ->
        cast_binary_temp_votes(poll, user, temp_votes)
      "approval" ->
        cast_approval_temp_votes(poll, user, temp_votes)
      "ranked" ->
        cast_ranked_temp_votes(poll, user, temp_votes)
      "star" ->
        cast_star_temp_votes(poll, user, temp_votes)
      _ ->
        {:error, :unsupported_voting_system}
    end
  end

  defp cast_binary_temp_votes(poll, user, temp_votes) do
    # temp_votes format: %{option_id => vote_value}
    # where vote_value is "yes", "maybe", or "no"
    poll_options = Repo.all(from po in PollOption, where: po.poll_id == ^poll.id)

    results = for {option_id, vote_value} <- temp_votes do
      case Enum.find(poll_options, &(&1.id == option_id)) do
        nil ->
          {:error, :option_not_found}
        poll_option ->
          create_poll_vote(poll_option, user, %{vote_value: vote_value}, "binary")
      end
    end

    case Enum.find(results, &(match?({:error, _}, &1))) do
      nil ->
        {:ok, Enum.map(results, fn {:ok, vote} -> vote end)}
      error ->
        error
    end
  end

  defp cast_approval_temp_votes(poll, user, temp_votes) do
    # temp_votes format: %{option_id => "selected"}
    # Only selected options are in the map
    poll_options = Repo.all(from po in PollOption, where: po.poll_id == ^poll.id)

    results = for {option_id, _} <- temp_votes do
      case Enum.find(poll_options, &(&1.id == option_id)) do
        nil ->
          {:error, :option_not_found}
        poll_option ->
          create_poll_vote(poll_option, user, %{vote_value: "selected"}, "approval")
      end
    end

    case Enum.find(results, &(match?({:error, _}, &1))) do
      nil ->
        {:ok, Enum.map(results, fn {:ok, vote} -> vote end)}
      error ->
        error
    end
  end

  defp cast_ranked_temp_votes(poll, user, temp_votes) do
    # temp_votes format: %{poll_type: :ranked, votes: [%{option_id: id, rank: rank}, ...]}
    # or %{poll_type: :ranked, votes: %{option_id => rank}}
    poll_options = Repo.all(from po in PollOption, where: po.poll_id == ^poll.id)

    votes_data = case temp_votes do
      %{poll_type: :ranked, votes: votes} when is_list(votes) ->
        votes
      %{poll_type: :ranked, votes: votes} when is_map(votes) ->
        for {option_id, rank} <- votes, do: %{option_id: option_id, rank: rank}
      _ ->
        []
    end

    results = for %{option_id: option_id, rank: rank} <- votes_data do
      case Enum.find(poll_options, &(&1.id == option_id)) do
        nil ->
          {:error, :option_not_found}
        poll_option ->
          create_poll_vote(poll_option, user, %{vote_rank: rank}, "ranked")
      end
    end

    case Enum.find(results, &(match?({:error, _}, &1))) do
      nil ->
        {:ok, Enum.map(results, fn {:ok, vote} -> vote end)}
      error ->
        error
    end
  end

  defp cast_star_temp_votes(poll, user, temp_votes) do
    # temp_votes format: %{option_id => rating}
    # where rating is 1-5
    poll_options = Repo.all(from po in PollOption, where: po.poll_id == ^poll.id)

    results = for {option_id, rating} <- temp_votes do
      case Enum.find(poll_options, &(&1.id == option_id)) do
        nil ->
          {:error, :option_not_found}
        poll_option ->
          create_poll_vote(poll_option, user, %{vote_numeric: rating}, "star")
      end
    end

    case Enum.find(results, &(match?({:error, _}, &1))) do
      nil ->
        {:ok, Enum.map(results, fn {:ok, vote} -> vote end)}
      error ->
        error
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
    changeset = if DateTime.compare(polling_deadline, DateTime.utc_now()) == :gt do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :polling_deadline, "must be in the future")
    end

    case Repo.update(changeset) do
      {:ok, updated_event} -> {:ok, Event.with_computed_fields(updated_event)}
      error -> error
    end
  end

    @doc """
  Sets a threshold count for an event.
  This will transition the event to :threshold status.
  """
  def set_threshold(%Event{} = event, threshold_count) when is_integer(threshold_count) and threshold_count > 0 do
    attrs = %{
      threshold_count: threshold_count,
      status: :threshold
    }

    # Use inferred status changeset to handle status transitions properly
    changeset = Event.changeset_with_inferred_status(event, attrs)

    case Repo.update(changeset) do
      {:ok, updated_event} -> {:ok, Event.with_computed_fields(updated_event)}
      error -> error
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
    allowed_fields = [:title, :description, :tagline, :cover_image_url, :external_image_data, :theme, :theme_customizations, :taxation_type]
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
  def list_organizer_events_with_participants(%User{} = user) do
    query = from e in Event,
            join: eu in EventUser, on: e.id == eu.event_id,
            join: ep in EventParticipant, on: e.id == ep.event_id,
            where: eu.user_id == ^user.id,
            group_by: [e.id, e.title, e.start_at, e.status],
            select: %{
              id: e.id,
              title: e.title,
              start_at: e.start_at,
              status: e.status,
              participant_count: count(ep.id, :distinct)
            },
            order_by: [desc: e.start_at]

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
    filtered_event_ids = if exclude_event_ids != [] do
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
    query = from p in EventParticipant,
            join: e in Event, on: p.event_id == e.id,
            join: eu in EventUser, on: e.id == eu.event_id,
            join: u in User, on: p.user_id == u.id,
            where: eu.user_id == ^organizer.id and
                   p.user_id != ^organizer.id,  # Exclude organizer from suggestions
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

    # Apply exclude_event_ids filter if provided
    query = if exclude_event_ids != [] do
      from [p, e, eu, u] in query,
           where: e.id not in ^exclude_event_ids
    else
      query
    end

    # Apply exclude_user_ids filter if provided
    query = if exclude_user_ids != [] do
      from [p, e, eu, u] in query,
           where: u.id not in ^exclude_user_ids
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
    # Basic query for organizer's event IDs
    query = from eu in EventUser,
            where: eu.user_id == ^organizer_id,
            select: eu.event_id

    Repo.all(query)
  end

  @doc false
  defp get_participants_for_events(event_ids, exclude_user_ids, organizer_id, limit) do
    # Build base query for participants in the specified events
    query = from p in EventParticipant,
            join: e in Event, on: p.event_id == e.id,
            join: u in User, on: p.user_id == u.id,
            where: p.event_id in ^event_ids and
                   p.user_id != ^organizer_id,  # Exclude organizer from suggestions
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

    # Apply exclude_user_ids filter if provided
    query = if exclude_user_ids != [] do
      from [p, e, u] in query,
           where: u.id not in ^exclude_user_ids
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

    participants = get_historical_participants(organizer,
      exclude_event_ids: exclude_event_ids,
      exclude_user_ids: exclude_user_ids,
      limit: limit * 2  # Get more to have better selection after scoring
    )

         # Use the dedicated scoring module
     config = GuestInvitations.create_config(
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
     participants = get_historical_participants(organizer,
       exclude_event_ids: exclude_event_ids,
       limit: per_page * 3  # Get extra for scoring
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

    query = from p in EventParticipant,
            join: e in Event, on: p.event_id == e.id,
            join: eu in EventUser, on: e.id == eu.event_id,
            where: eu.user_id == ^organizer.id and
                   p.user_id != ^organizer.id,
            select: count(p.user_id, :distinct)

    # Apply exclude_event_ids filter if provided
    query = if exclude_event_ids != [] do
      from [p, e, eu] in query,
           where: e.id not in ^exclude_event_ids
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
    query = from ep in EventParticipant,
            where: ep.event_id == ^event.id,
            group_by: [ep.status, ep.role],
            select: %{
              status: ep.status,
              role: ep.role,
              count: count(ep.id)
            }

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
    base_query = from e in Event,
                 join: eu in EventUser, on: e.id == eu.event_id,
                 where: eu.user_id == ^organizer.id,
                 select: e.id

    event_ids = if event_ids do
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

    query = from ep in EventParticipant,
            join: u in User, on: ep.user_id == u.id,
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

    # Apply filters if provided
    query = if status_filter do
      from ep in query, where: ep.status == ^status_filter
    else
      query
    end

    query = if role_filter do
      from ep in query, where: ep.role == ^role_filter
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

    query = from ep in EventParticipant,
            join: e in Event, on: ep.event_id == e.id,
            join: eu in EventUser, on: e.id == eu.event_id,
            left_join: inviter in User, on: ep.invited_by_user_id == inviter.id,
            where: eu.user_id == ^organizer.id and
                   not is_nil(ep.invited_at) and
                   ep.invited_at >= ^cutoff_date,
            group_by: [ep.invited_by_user_id, inviter.name, ep.status],
            select: %{
              invited_by_user_id: ep.invited_by_user_id,
              inviter_name: inviter.name,
              status: ep.status,
              count: count(ep.id)
            }

    stats = Repo.all(query)

    # Aggregate invitation success rates
    invitation_summary = stats
    |> Enum.group_by(& &1.invited_by_user_id)
    |> Enum.map(fn {inviter_id, invitations} ->
      total = Enum.sum(Enum.map(invitations, & &1.count))
      accepted = invitations
                 |> Enum.filter(& &1.status in [:accepted, :confirmed_with_order])
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
    query = from ep in EventParticipant,
            left_join: inviter in User, on: ep.invited_by_user_id == inviter.id,
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

    query = from ep in EventParticipant,
            join: e in Event, on: ep.event_id == e.id,
            join: eu in EventUser, on: e.id == eu.event_id,
            join: u in User, on: ep.user_id == u.id,
            left_join: inviter in User, on: ep.invited_by_user_id == inviter.id,
            where: eu.user_id == ^organizer.id and
                   not is_nil(ep.invited_at) and
                   ep.invited_at >= ^cutoff_date,
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
    result_after_suggestions = Enum.reduce(suggestion_structs, result, fn suggestion, acc ->
      case process_suggestion_invitation(event, organizer, suggestion, invitation_message, current_time, mode) do
        {:ok, :created} ->
          %{acc | successful_invitations: acc.successful_invitations + 1}
        {:ok, :already_exists} ->
          %{acc | skipped_duplicates: acc.skipped_duplicates + 1}
        {:error, reason} ->
          error_msg = "Failed to invite #{get_suggestion_identifier(suggestion)}: #{format_error(reason)}"
          %{acc | failed_invitations: acc.failed_invitations + 1, errors: [error_msg | acc.errors]}
      end
    end)

    # Process manual email invitations
    Enum.reduce(manual_emails, result_after_suggestions, fn email, acc ->
      case process_email_invitation(event, organizer, email, invitation_message, current_time, mode) do
        {:ok, :created} ->
          %{acc | successful_invitations: acc.successful_invitations + 1}
        {:ok, :already_exists} ->
          %{acc | skipped_duplicates: acc.skipped_duplicates + 1}
        {:error, reason} ->
          error_msg = "Failed to invite #{email}: #{format_error(reason)}"
          %{acc | failed_invitations: acc.failed_invitations + 1, errors: [error_msg | acc.errors]}
      end
    end)
  end

  # Process a single suggestion invitation
  defp process_suggestion_invitation(event, organizer, suggestion, invitation_message, current_time, mode) do
    case EventasaurusApp.Accounts.get_user(suggestion.user_id) do
      %User{} = user ->
        create_invitation_participant(event, organizer, user, invitation_message, current_time, %{
          invitation_method: get_invitation_method(mode, "historical_suggestion"),
          recommendation_level: Map.get(suggestion, :recommendation_level, "unknown"),
          score: Map.get(suggestion, :total_score, 0.0)
        }, mode)
      nil ->
        {:error, :user_not_found}
    end
  end

  # Process a single email invitation
  defp process_email_invitation(event, organizer, email, invitation_message, current_time, mode) do
    case EventasaurusApp.Accounts.find_or_create_guest_user(email) do
      {:ok, user} ->
        create_invitation_participant(event, organizer, user, invitation_message, current_time, %{
          invitation_method: get_invitation_method(mode, "manual_email"),
          email_provided: email
        }, mode)
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Create an event participant with invitation tracking
  defp create_invitation_participant(event, organizer, user, invitation_message, current_time, metadata, mode) do
    case get_event_participant_by_event_and_user(event, user) do
      nil ->
        participant_attrs = build_participant_attrs(event, organizer, user, invitation_message, current_time, metadata, mode)

        case create_event_participant(participant_attrs) do
          {:ok, _participant} ->
            # Send email for invitation mode only
            if mode == :invitation do
              send_invitation_email(user, event, invitation_message, organizer)
            end
            {:ok, :created}
          {:error, changeset} -> {:error, changeset}
        end
      _existing_participant ->
        {:ok, :already_exists}
    end
  end

  # Send invitation email to the invited user
  defp send_invitation_email(user, event, invitation_message, organizer) do
    # Send email asynchronously to avoid blocking the user flow
    Task.start(fn ->
      # Load event with venue for email context
      case get_event_with_venue(event.id) do
        nil ->
          require Logger
          Logger.error("Cannot send invitation email - event not found",
            user_id: user.id,
            event_id: event.id,
            organizer_id: organizer.id
          )

        event_with_venue ->
          guest_name = get_user_display_name(user)

          # Get the participant record to update email status
          participant = get_event_participant_by_event_and_user(event_with_venue, user)

          if participant do
            # Mark email as being sent
            updated_participant = EventParticipant.update_email_status(participant, "sending")

            case update_event_participant(participant, %{metadata: updated_participant.metadata}) do
              {:ok, _} ->
                # Attempt to send the email
                case Eventasaurus.Emails.send_guest_invitation(
                  user.email,
                  guest_name,
                  event_with_venue,
                  invitation_message,
                  organizer
                ) do
                  {:ok, response} ->
                    require Logger
                    Logger.info("Guest invitation email sent successfully",
                      user_id: user.id,
                      event_id: event.id,
                      organizer_id: organizer.id
                    )

                    # Mark email as sent successfully
                    delivery_id = extract_delivery_id(response)
                    sent_participant = EventParticipant.mark_email_sent(participant, delivery_id)
                    update_event_participant(participant, %{metadata: sent_participant.metadata})

                  {:error, reason} ->
                    require Logger
                    Logger.error("Failed to send guest invitation email",
                      user_id: user.id,
                      event_id: event.id,
                      organizer_id: organizer.id,
                      reason: inspect(reason)
                    )

                    # Mark email as failed
                    error_message = format_email_error(reason)
                    failed_participant = EventParticipant.mark_email_failed(participant, error_message)
                    update_event_participant(participant, %{metadata: failed_participant.metadata})
                end

              {:error, changeset_error} ->
                require Logger
                Logger.error("Failed to update participant email status",
                  user_id: user.id,
                  event_id: event.id,
                  reason: inspect(changeset_error)
                )
            end
          else
            require Logger
            Logger.error("Cannot find participant record for email tracking",
              user_id: user.id,
              event_id: event.id
            )
          end
      end
    end)
  end

  # Helper function to extract delivery ID from email service response
  defp extract_delivery_id(response) do
    case response do
      %{id: id} -> id
      %{"id" => id} -> id
      _ -> nil
    end
  end

  # Helper function to format error messages for storage
  defp format_email_error(reason) do
    case reason do
      %{message: message} -> message
      %{"message" => message} -> message
      error when is_binary(error) -> error
      error -> inspect(error)
    end
  end

  # Get event with venue preloaded for email templates
  defp get_event_with_venue(event_id) do
    case Repo.one(
      from e in Event,
      where: e.id == ^event_id,
      preload: [:venue]
    ) do
      nil ->
        Logger.error("Event not found for email sending", event_id: event_id)
        nil
      event -> event
    end
  end

  # Get user display name for emails
  defp get_user_display_name(user) do
    cond do
      user.name && user.name != "" -> user.name
      user.username && user.username != "" -> user.username
      true -> nil
    end
  end

    # Build participant attributes based on mode
  defp build_participant_attrs(event, organizer, user, invitation_message, current_time, metadata, mode) do
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
        error_messages = Enum.map(errors, fn {field, {message, _opts}} ->
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
      from(p in EventParticipant, where: p.event_id == ^event.id),
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

    query = from p in EventParticipant,
            where: p.event_id == ^event.id,
            preload: [:user]

    query = if limit do
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
    query = from ep in EventParticipant,
            where: ep.event_id == ^event.id,
            preload: [:user, :invited_by_user]

    query
    |> EventParticipant.by_email_status(status)
    |> Repo.all()
  end

  @doc """
  Lists event participants with failed emails.
  """
  def list_event_participants_with_failed_emails(%Event{} = event) do
    query = from ep in EventParticipant,
            where: ep.event_id == ^event.id,
            preload: [:user, :invited_by_user]

    query
    |> EventParticipant.with_failed_emails()
    |> Repo.all()
  end

  @doc """
  Lists event participants without any email status (never sent).
  """
  def list_event_participants_without_email_status(%Event{} = event) do
    query = from ep in EventParticipant,
            where: ep.event_id == ^event.id,
            preload: [:user, :invited_by_user]

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
    base_query = from ep in EventParticipant,
                 where: ep.event_id == ^event.id

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
    status_counts = from(ep in base_query,
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

    query = from ep in EventParticipant,
            join: u in User, on: ep.user_id == u.id,
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

    # Apply email status filter if provided
    query = if status_filter do
      from ep in query,
           where: fragment("COALESCE(?->>'email_status', 'not_sent') = ?", ep.metadata, ^status_filter)
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
    candidates = list_email_retry_candidates(event, max_attempts)
                |> filter_by_retry_delay(delay_seconds)
                |> Enum.take(batch_size)

    results = %{
      attempted: 0,
      successful: 0,
      failed: 0,
      errors: []
    }

    if length(candidates) > 0 do
      Logger.info("Retrying failed emails for event #{event.id}, #{length(candidates)} candidates")

      Enum.reduce(candidates, results, fn participant, acc ->
        case retry_single_email(participant, event) do
          :ok ->
            %{acc | attempted: acc.attempted + 1, successful: acc.successful + 1}
          {:error, reason} ->
            error_msg = "Failed to retry email for user #{participant.user_id}: #{format_email_error(reason)}"
            %{acc |
              attempted: acc.attempted + 1,
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

    # Load event with venue and get organizer info
    case get_event_with_venue(event.id) do
      nil ->
        {:error, "Event not found"}

      event_with_venue ->
        organizer = get_event_organizer(event_with_venue)
        guest_name = get_user_display_name(participant.user)
        invitation_message = participant.invitation_message || ""

        # Mark as retrying
        retrying_participant = EventParticipant.update_email_status(participant, "retrying")

        case update_event_participant(participant, %{metadata: retrying_participant.metadata}) do
          {:ok, _} ->
            # Attempt to send the email
            case Eventasaurus.Emails.send_guest_invitation(
              participant.user.email,
              guest_name,
              event_with_venue,
              invitation_message,
              organizer
            ) do
              {:ok, response} ->
                Logger.info("Email retry successful for participant #{participant.id}")

                # Mark as sent
                delivery_id = extract_delivery_id(response)
                sent_participant = EventParticipant.mark_email_sent(participant, delivery_id)
                update_event_participant(participant, %{metadata: sent_participant.metadata})
                :ok

              {:error, reason} ->
                Logger.error("Email retry failed for participant #{participant.id}: #{inspect(reason)}")

                # Mark as failed again
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

    results = Enum.map(events_with_failed_emails, fn event ->
      result = retry_failed_emails(event,
        max_attempts: max_attempts,
        batch_size: batch_size_per_event
      )

      {event.id, result}
    end)

    # Log summary
    total_attempted = results |> Enum.map(fn {_, result} -> result.attempted end) |> Enum.sum()
    total_successful = results |> Enum.map(fn {_, result} -> result.successful end) |> Enum.sum()
    total_failed = results |> Enum.map(fn {_, result} -> result.failed end) |> Enum.sum()

    Logger.info("Email retry summary: #{total_attempted} attempted, #{total_successful} successful, #{total_failed} failed")

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
        nil -> true
        timestamp_string ->
          case DateTime.from_iso8601(timestamp_string) do
            {:ok, timestamp, _} -> DateTime.compare(timestamp, cutoff_time) == :lt
            _ -> true  # If we can't parse the timestamp, allow retry
          end
      end
    end)
  end

  defp get_events_with_failed_emails(max_attempts) do
    # Find events that have participants with failed emails within retry limits
    query = from e in Event,
            join: ep in EventParticipant, on: e.id == ep.event_id,
            where: fragment("(?->>'email_status') IN ('failed', 'bounced')", ep.metadata),
            where: fragment("COALESCE((?->>'email_attempts')::integer, 0) < ?", ep.metadata, ^max_attempts),
            group_by: e.id,
            select: e

    Repo.all(query)
  end

  defp get_event_organizer(%Event{users: users}) when is_list(users) do
    # Return the first organizer/admin user
    List.first(users)
  end
  defp get_event_organizer(%Event{} = event) do
    # If users aren't preloaded, load the first organizer
    query = from eu in EventUser,
            join: u in User, on: eu.user_id == u.id,
            where: eu.event_id == ^event.id,
            limit: 1,
            select: u

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
      raise ArgumentError, "exclude_event_ids must contain only positive integers, invalid: #{inspect(invalid_ids)}"
    end

    # Check if user exists (graceful handling for non-existent users)
    case Repo.get(EventasaurusApp.Accounts.User, user_id) do
      nil ->
        # Return empty list for non-existent users rather than raising error
        # This provides better UX when user accounts are deleted
        []
      _user ->
        # Optimized query with proper indexing and selective fields
        query = from(eu in EventUser,
          join: e in Event, on: eu.event_id == e.id,
          left_join: v in Venue, on: e.venue_id == v.id,
          where: eu.user_id == ^user_id and
                 e.id not in ^exclude_event_ids and
                 is_nil(e.virtual_venue_url) and
                 not is_nil(e.venue_id),
          select: %{
            venue_id: e.venue_id,
            venue_name: v.name,
            venue_address: v.address,
            venue_city: v.city,
            venue_state: v.state,
            venue_country: v.country,
            virtual_venue_url: e.virtual_venue_url,
            event_created_at: e.inserted_at
          },
          order_by: [desc: e.inserted_at]
        )

        query
        |> Repo.all()
        |> Enum.group_by(fn row ->
          # Group by venue_id for physical venues only
          row.venue_id
        end)
        |> Enum.map(fn {venue_id, rows} ->
          # Calculate usage statistics
          usage_count = length(rows)
          last_used = rows |> Enum.map(& &1.event_created_at) |> Enum.max()

          # Build location info for physical venue
          first_row = List.first(rows)

          # Handle deleted venues gracefully
          is_deleted = is_nil(first_row.venue_name)

          %{
            id: venue_id,
            name: if(is_deleted, do: "Deleted Venue", else: first_row.venue_name),
            address: if(is_deleted, do: nil, else: first_row.venue_address),
            city: if(is_deleted, do: nil, else: first_row.venue_city),
            state: if(is_deleted, do: nil, else: first_row.venue_state),
            country: if(is_deleted, do: nil, else: first_row.venue_country),
            virtual_venue_url: first_row.virtual_venue_url,
            usage_count: usage_count,
            last_used: last_used,
            is_deleted: is_deleted
          }
        end)
        |> Enum.filter(fn location -> not is_nil(location.id) end)
        |> Enum.sort(fn location1, location2 ->
          # Sort by usage count (descending), then by recency (descending)
          case {location1.usage_count, location2.usage_count} do
            {c1, c2} when c1 > c2 -> true
            {c1, c2} when c1 < c2 -> false
            _ -> NaiveDateTime.compare(location1.last_used, location2.last_used) == :gt
          end
        end)
        |> Enum.take(limit)
    end
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
          metadata: Map.merge(existing_participant.metadata || %{}, %{
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
        should_remove = case status_filter do
          nil -> true  # Remove any participation
          ^current_status -> true  # Status matches filter
          _ -> false  # Status doesn't match filter
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
    query = from ep in EventParticipant,
            where: ep.event_id == ^event.id and ep.status == ^status,
            preload: [:user],
            order_by: [desc: ep.inserted_at]

    Repo.all(query)
  end

  @doc """
  Lists participants with a specific status for an event with pagination.

  Returns list of EventParticipant structs with preloaded users.
  Only accessible to event organizers.
  """
  def list_participants_by_status(%Event{} = event, status, page, per_page) when is_atom(status) and is_integer(page) and is_integer(per_page) do
    offset = (page - 1) * per_page

    query = from ep in EventParticipant,
            where: ep.event_id == ^event.id and ep.status == ^status,
            preload: [:user],
            order_by: [desc: ep.inserted_at],
            limit: ^per_page,
            offset: ^offset

    Repo.all(query)
  end

  @doc """
  Counts users with a specific status for an event.

  Returns integer count of participants with the specified status.
  """
  def count_participants_by_status(%Event{} = event, status) when is_atom(status) do
    from(ep in EventParticipant,
      where: ep.event_id == ^event.id and ep.status == ^status,
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
    status_counts = from(ep in EventParticipant,
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
    query = from p in Poll,
            where: p.event_id == ^event.id,
            order_by: [asc: p.inserted_at],
            preload: [:created_by, poll_options: [:suggested_by, :votes]]

    Repo.all(query)
  end

  @doc """
  Returns the list of active polls (not closed) for an event.
  """
  def list_active_polls(%Event{} = event) do
    query = from p in Poll,
            where: p.event_id == ^event.id and p.phase != "closed",
            order_by: [asc: p.inserted_at],
            preload: [:created_by, poll_options: [:suggested_by, :votes]]

    Repo.all(query)
  end

  @doc """
  Gets a single poll.
  """
  def get_poll!(id) do
    Repo.get!(Poll, id)
    |> Repo.preload([:event, :created_by, poll_options: [:suggested_by, :votes]])
  end

  @doc """
  Gets a poll for a specific event and poll type.
  """
  def get_event_poll(%Event{} = event, poll_type) do
    query = from p in Poll,
            where: p.event_id == ^event.id and p.poll_type == ^poll_type,
            preload: [:created_by, poll_options: [:suggested_by, :votes]]

    Repo.one(query)
  end

  @doc """
  Creates a poll.
  """
  def create_poll(attrs \\ %{}) do
    %Poll{}
    |> Poll.creation_changeset(attrs)
    |> Repo.insert()
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
    poll
    |> Poll.finalization_changeset(option_ids, finalized_date)
    |> Repo.update()
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
    query = from po in PollOption,
            where: po.poll_id == ^poll.id and po.status == "active",
            order_by: [asc: po.order_index, asc: po.inserted_at],
            preload: [:suggested_by, :votes]

    Repo.all(query)
  end

  @doc """
  Returns all options for a poll (including hidden/removed).
  """
  def list_all_poll_options(%Poll{} = poll) do
    query = from po in PollOption,
            where: po.poll_id == ^poll.id,
            order_by: [asc: po.order_index, asc: po.inserted_at],
            preload: [:suggested_by, :votes]

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
    %PollOption{}
    |> PollOption.creation_changeset(attrs, opts)
    |> Repo.insert()
  end

  @doc """
  Updates a poll option.
  """
  def update_poll_option(%PollOption{} = poll_option, attrs, opts \\ []) do
    poll_option
    |> PollOption.changeset(attrs, opts)
    |> Repo.update()
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
  def reorder_poll_option(dragged_option_id, target_option_id, direction) when direction in ["before", "after"] do
    Repo.transaction(fn ->
      # Get both options and validate they exist and belong to the same poll
      dragged_option = Repo.get!(PollOption, dragged_option_id)
      target_option = Repo.get!(PollOption, target_option_id)

      if dragged_option.poll_id != target_option.poll_id do
        Repo.rollback("Options belong to different polls")
      end

      # Get all poll options ordered by current order_index
      all_options = from(po in PollOption,
                         where: po.poll_id == ^dragged_option.poll_id,
                         order_by: [asc: po.order_index, asc: po.id])
                    |> Repo.all()

      # Calculate new order indices
      {new_orders, updated_count} = calculate_new_order_indices(all_options, dragged_option, target_option, direction)

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

      # Calculate which options need their order_index updated
      new_orders = new_ordered_options
                  |> Enum.with_index()
                  |> Enum.filter(fn {option, new_index} ->
                       option.order_index != new_index
                     end)
                  |> Enum.map(fn {option, new_index} ->
                       {option.id, new_index}
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
  def create_date_poll_option(%Poll{poll_type: "date_selection"} = poll, %User{} = user, date, opts \\ []) do
    alias EventasaurusApp.Events.DateMetadata

    # Use the new DateMetadata.build_date_metadata function for proper structure
    try do
      metadata = DateMetadata.build_date_metadata(date, opts)

      # Use custom title or generate from date
      parsed_date = case date do
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
        changeset = PollOption.changeset(%PollOption{}, %{}, poll_type: "date_selection")
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
  def create_date_range_poll_options(%Poll{poll_type: "date_selection"} = poll, %User{} = user, start_date, end_date, opts \\ []) do
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
  def create_date_list_poll_options(%Poll{poll_type: "date_selection"} = poll, %User{} = user, dates, opts \\ []) when is_list(dates) do
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
      new_metadata = DateMetadata.build_date_metadata(new_date, [
        created_at: get_in(poll_option.metadata, ["created_at"]) || DateTime.utc_now() |> DateTime.to_iso8601()
      ] ++ opts)

      # Extract parsed date from metadata instead of redundantly parsing
      parsed_date = case new_metadata do
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
      attrs = if description = Keyword.get(opts, :description) do
        Map.put(attrs, "description", description)
      else
        attrs
      end

      # The PollOption changeset will validate the new metadata structure
      update_poll_option(poll_option, attrs, poll_type: "date_selection")
    rescue
      e in ArgumentError ->
        changeset = PollOption.changeset(poll_option, %{}, poll_type: "date_selection")
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
      nil -> {:error, "No date found in metadata"}
      date_string when is_binary(date_string) ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> {:ok, date}
          {:error, _} -> {:error, "Invalid date format in metadata"}
        end
      _ -> {:error, "Date metadata is not a string"}
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
    # Format as "Monday, December 25, 2024"
    Calendar.strftime(date, "%A, %B %d, %Y")
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
    |> Enum.sort_by(fn option ->
      case get_date_from_poll_option(option) do
        {:ok, date} -> date
        {:error, _} -> ~D[9999-12-31]  # Put invalid dates at the end
      end
    end, Date)
  end

  @doc """
  Validates existing date poll options for metadata compliance.

  This function can be used during migration to identify and fix
  any existing poll options that don't meet the new validation standards.
  """
  def validate_existing_date_poll_options(poll_id) do
    query = from po in PollOption,
            join: p in Poll, on: po.poll_id == p.id,
            where: p.id == ^poll_id and p.poll_type == "date_selection",
            preload: [:poll]

    options = Repo.all(query)

    results = Enum.map(options, fn option ->
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
    date_result = case option.metadata do
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
        valid_metadata = DateMetadata.build_date_metadata(date, [
          created_at: get_in(option.metadata, ["created_at"]) || option.inserted_at |> DateTime.to_iso8601(),
          updated_at: get_in(option.metadata, ["updated_at"]) || option.updated_at |> DateTime.to_iso8601()
        ])

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

    results = Enum.map(date_polls, fn poll ->
      validation_result = validate_existing_date_poll_options(poll.id)

      fixed_count = if validation_result.invalid > 0 do
        # Attempt to fix invalid options
        fixed = validation_result.invalid_options
        |> Enum.map(fn {:invalid, option, _reason} ->
          case fix_invalid_date_metadata(option) do
            {:ok, _} -> :fixed
            {:error, _} -> :failed
          end
        end)
        |> Enum.count(& &1 == :fixed)

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
    query = from pv in PollVote,
            where: pv.poll_option_id == ^poll_option.id,
            order_by: [desc: pv.voted_at],
            preload: [:voter]

    Repo.all(query)
  end

  @doc """
  Returns the votes for a poll option by a specific user.
  """
  def get_user_poll_vote(%PollOption{} = poll_option, %User{} = user) do
    query = from pv in PollVote,
            where: pv.poll_option_id == ^poll_option.id and pv.voter_id == ^user.id,
            preload: [:voter]

    Repo.one(query)
  end

  @doc """
  Returns all votes by a user for a poll.
  """
  def list_user_poll_votes(%Poll{} = poll, %User{} = user) do
    query = from pv in PollVote,
            join: po in PollOption, on: pv.poll_option_id == po.id,
            where: po.poll_id == ^poll.id and pv.voter_id == ^user.id,
            preload: [:poll_option, :voter]

    Repo.all(query)
  end

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
        changeset = PollVote.changeset(%PollVote{}, %{})
        |> Ecto.Changeset.add_error(:poll_id, "Poll not found for this option")
        {:error, changeset}

      poll ->
        attrs = Map.merge(vote_data, %{
          poll_option_id: poll_option.id,
          voter_id: user.id,
          poll_id: poll.id
        })

        changeset = case voting_system do
          "binary" -> PollVote.binary_vote_changeset(%PollVote{}, attrs)
          "approval" -> PollVote.approval_vote_changeset(%PollVote{}, attrs)
          "ranked" -> PollVote.ranked_vote_changeset(%PollVote{}, attrs)
          "star" -> PollVote.star_vote_changeset(%PollVote{}, attrs)
          _ -> PollVote.changeset(%PollVote{}, attrs)
        end

        Repo.insert(changeset)
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
    Repo.delete(poll_vote)
  end

  # =================
  # Poll Analytics
  # =================

  @doc """
  Gets vote counts and statistics for a poll.
  """
  def get_poll_analytics(%Poll{} = poll) do
    poll_with_options = Repo.preload(poll, [poll_options: :votes])

    vote_counts = poll_with_options.poll_options
    |> Enum.map(fn option ->
      votes = option.votes
      total_votes = length(votes)

      vote_breakdown = case poll.voting_system do
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
      total_score = votes
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
    user_is_organizer?(event, user) ||

    # Event participants with appropriate permissions can create polls
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

  def disable_poll_suggestions(%Poll{phase: "voting"} = poll) do  # Legacy support
    poll
    |> Poll.phase_transition_changeset("voting_only")
    |> Repo.update()
  end

  def disable_poll_suggestions(%Poll{}), do:
    {:error, "Poll is not in a phase that allows disabling suggestions"}

  @doc """
  Finalizes a poll (single-argument version for LiveView component).
  """
  def finalize_poll(%Poll{} = poll) do
    finalize_poll(poll, %{})
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
  def cast_approval_vote(%Poll{} = poll, %PollOption{} = poll_option, %User{} = user, selected \\ true) do
    if poll.voting_system != "approval" do
      {:error, "Poll does not support approval voting"}
    else
      vote_value = if selected, do: "selected", else: nil

      if selected do
        cast_vote_with_transaction(poll, poll_option, user, %{vote_value: vote_value}, "approval")
      else
        # For approval voting, "deselecting" means removing the vote
        remove_user_vote(poll_option, user)
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
        poll_options = from(po in PollOption,
                           where: po.poll_id == ^poll.id and po.id in ^option_ids,
                           preload: [:poll])
                      |> Repo.all()

        results = for option <- poll_options do
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
        existing_vote_with_rank = from(pv in PollVote,
                                      join: po in PollOption, on: pv.poll_option_id == po.id,
                                      where: po.poll_id == ^poll.id and
                                             pv.voter_id == ^user.id and
                                             pv.vote_rank == ^rank)
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
    def cast_ranked_votes(%Poll{} = poll, ranked_options, %User{} = user) when is_list(ranked_options) do
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
        results = for {option_id, rank} <- ranked_options do
          case Repo.get(PollOption, option_id) do
            nil -> Repo.rollback("Option with ID #{option_id} not found")
            option ->
              case create_poll_vote(option, user, %{vote_rank: rank}, "ranked") do
                {:ok, vote} -> vote
                {:error, changeset} -> Repo.rollback(changeset)
              end
          end
        end

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
      vote_numeric = if is_integer(rating), do: Decimal.new(rating), else: Decimal.from_float(rating)
      cast_vote_with_transaction(poll, poll_option, user, %{vote_numeric: vote_numeric}, "star")
    end
  end



  @doc """
  Clears all votes by a user for a specific poll.
  """
  def clear_user_poll_votes(%Poll{} = poll, %User{} = user) do
    query = from(pv in PollVote,
                join: po in PollOption, on: pv.poll_option_id == po.id,
                where: po.poll_id == ^poll.id and pv.voter_id == ^user.id)

    {count, _} = Repo.delete_all(query)
    broadcast_poll_update(poll, :votes_updated)
    broadcast_poll_stats_update(poll)
    {:ok, count}
  end



  @doc """
  Checks if a user can vote on a poll based on current phase and permissions.
  """
  def can_user_vote?(%Poll{} = poll, %User{} = user) do
    # Must be in any voting phase (including new phases)
    Poll.voting?(poll) and
    # Must be within voting deadline (if set)
    (is_nil(poll.voting_deadline) or DateTime.compare(DateTime.utc_now(), poll.voting_deadline) == :lt) and
    # User must be a participant in the event
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
        ranked_votes = user_votes
                      |> Enum.sort_by(& &1.vote_rank)
                      |> Enum.map(fn vote -> {vote.poll_option_id, vote.vote_rank} end)
        %{
          voting_system: "ranked",
          votes_cast: length(user_votes),
          ranked_options: ranked_votes
        }

      "star" ->
        ratings_by_option = user_votes
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
          nil -> :ok
          existing_vote -> Repo.delete!(existing_vote)
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
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "polls:#{poll.id}",
      {event_type, poll}
    )

    # Also broadcast to event channel for real-time event updates
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "events:#{poll.event_id}",
      {:poll_updated, poll}
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
      error -> error
    end
  end

  @doc """
  Clears all votes for a poll (used by moderation).
  """
  def clear_all_poll_votes(poll_id) do
    from(v in PollVote, where: v.poll_option_id in subquery(
      from(o in PollOption, where: o.poll_id == ^poll_id, select: o.id)
    ))
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
      poll_attrs = Map.merge(attrs, %{
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

        error -> error
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

        error -> error
      end
    end
  end

  @doc """
  Gets all active polls for an event with event context.
  """
  def list_event_active_polls(%Event{} = event) do
    list_active_polls(event)
    |> Repo.preload([:created_by, poll_options: [:suggested_by, :votes]])
  end

  @doc """
  Gets poll statistics for an event dashboard.
  """
  def get_event_poll_stats(%Event{} = event) do
    polls = list_polls(event)

    %{
      total_polls: length(polls),
      active_polls: length(Enum.filter(polls, & &1.phase != "closed")),
      polls_by_type: Enum.group_by(polls, & &1.poll_type) |> Enum.map(fn {type, polls} -> {type, length(polls)} end) |> Enum.into(%{}),
      polls_by_phase: Enum.group_by(polls, & &1.phase) |> Enum.map(fn {phase, polls} -> {phase, length(polls)} end) |> Enum.into(%{}),
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

  defp handle_poll_phase_transition(%Event{} = event, %Poll{} = poll, old_phase, new_phase, %User{} = user) do
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
  def finalize_date_selection_poll(%Poll{poll_type: "date_selection"} = poll, %User{} = finalizer, opts \\ []) do
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
  def determine_winning_date_options(%Poll{poll_type: "date_selection"} = poll, strategy, opts \\ []) do
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
          new_datetime = if preserve_time && event.start_at do
            DateTime.new!(selected_date, DateTime.to_time(event.start_at), event.timezone || "UTC")
          else
            # Default to 6 PM if no existing time
            DateTime.new!(selected_date, ~T[18:00:00], event.timezone || "UTC")
          end

          # Update event with new date and confirmed status
          attrs = %{
            start_at: new_datetime,
            status: :confirmed,
            polling_deadline: nil  # Clear polling deadline
          }

          # Preserve existing end time if it exists
          attrs = if event.ends_at do
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
    options_with_votes = poll
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
          winning_options = Enum.take_while([{top_option_id, top_count} | rest], fn {_id, count} ->
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
    options_with_yes_votes = poll
    |> list_poll_options()
    |> Enum.map(fn option ->
      yes_count = option.votes
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
          winning_options = Enum.take_while([{top_option_id, top_count} | rest], fn {_id, count} ->
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

  defp broadcast_event_poll_activity(%Event{} = event, activity_type, %Poll{} = poll, %User{} = user) do
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
  def extract_time_slots_from_option(%PollOption{metadata: nil}), do: {:error, "No metadata found"}
  def extract_time_slots_from_option(%PollOption{metadata: metadata}) do
    case {Map.get(metadata, "time_enabled"), Map.get(metadata, "time_slots")} do
      {true, time_slots} when is_list(time_slots) and length(time_slots) > 0 ->
        {:ok, time_slots}
      {true, _} ->
        {:error, "Time enabled but no valid time slots found"}
      {false, _} ->
        {:ok, []}  # All-day event
      {nil, _} ->
        {:ok, []}  # Legacy date-only format (backward compatibility)
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
      %Ecto.Changeset{valid?: true} -> :ok
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
  Formats time in 24-hour format to 12-hour format with AM/PM.

  ## Examples
      iex> format_time_12hour("14:30")
      "2:30 PM"

      iex> format_time_12hour("09:00")
      "9:00 AM"
  """
  def format_time_12hour(time_string) when is_binary(time_string) do
    case time_to_minutes(time_string) do
      {:ok, minutes} ->
        hour = div(minutes, 60)
        minute = rem(minutes, 60)

        {display_hour, period} = if hour == 0 do
          {12, "AM"}
        else
          if hour < 12 do
            {hour, "AM"}
          else
            display_hour = if hour == 12, do: 12, else: hour - 12
            {display_hour, "PM"}
          end
        end

        minute_str = if minute == 0, do: ":00", else: ":#{String.pad_leading("#{minute}", 2, "0")}"
        "#{display_hour}#{minute_str} #{period}"
      {:error, _} ->
        time_string  # Return original if parsing fails
    end
  end

  def format_time_12hour(_), do: "Invalid Time"

  @doc """
  Generates a display string for a time range.

  ## Examples
      iex> generate_time_range_display("09:00", "17:00")
      "9:00 AM - 5:00 PM"

      iex> generate_time_range_display("14:30", "16:45")
      "2:30 PM - 4:45 PM"
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
      _ -> false  # If any time parsing fails, assume no overlap
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
    sorted_slots = Enum.sort_by(time_slots, fn slot ->
      case time_to_minutes(slot["start_time"]) do
        {:ok, minutes} -> minutes
        _ -> 9999  # Put invalid times at the end
      end
    end)

    # Merge overlapping slots
    merged = Enum.reduce(sorted_slots, [], fn slot, acc ->
      case acc do
        [] ->
          [slot]
        [last_slot | rest] ->
          if time_slots_overlap?(last_slot["start_time"], last_slot["end_time"],
                                 slot["start_time"], slot["end_time"]) do
            # Merge the slots
            merged_slot = %{
              "start_time" => last_slot["start_time"],
              "end_time" => latest_end_time(last_slot["end_time"], slot["end_time"]),
              "timezone" => last_slot["timezone"] || slot["timezone"] || "UTC"
            }
            merged_slot = Map.put(merged_slot, "display",
              generate_time_range_display(merged_slot["start_time"], merged_slot["end_time"]))

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
  def create_date_time_poll_option(%Poll{poll_type: "date_selection"} = poll, %User{} = user, date, opts \\ []) do
    alias EventasaurusApp.Events.DateMetadata

    # Extract time options
    time_enabled = Keyword.get(opts, :time_enabled, false)
    time_slots = Keyword.get(opts, :time_slots, [])
    all_day = Keyword.get(opts, :all_day, not time_enabled)
    timezone = Keyword.get(opts, :timezone, "UTC")

    # Validate time slots if time is enabled - return early on error
    with :ok <- validate_time_slots_if_enabled(time_enabled, time_slots) do
      # Build enhanced metadata with time support
      enhanced_opts = opts
      |> Keyword.put(:time_enabled, time_enabled)
      |> Keyword.put(:time_slots, time_slots)
      |> Keyword.put(:all_day, all_day)

      # Ensure time slots have proper timezone and display
      enhanced_time_slots = if time_enabled and length(time_slots) > 0 do
        Enum.map(time_slots, fn slot ->
          slot
          |> Map.put_new("timezone", timezone)
          |> Map.put_new("display", generate_time_range_display(slot["start_time"], slot["end_time"]))
        end)
      else
        []
      end

      final_opts = Keyword.put(enhanced_opts, :time_slots, enhanced_time_slots)

      try do
        metadata = DateMetadata.build_date_metadata(date, final_opts)

        # Parse date for title generation
        parsed_date = case date do
          %Date{} = d -> d
          date_string -> Date.from_iso8601!(date_string)
        end

        # Generate enhanced title including time information
        title = if time_enabled and length(enhanced_time_slots) > 0 do
          time_display = enhanced_time_slots
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
          changeset = PollOption.changeset(%PollOption{}, %{}, poll_type: "date_selection")
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
      :ok -> :ok
      {:error, reasons} ->
        changeset = PollOption.changeset(%PollOption{}, %{}, poll_type: "date_selection")
        |> Ecto.Changeset.add_error(:metadata, "Invalid time slots: #{Enum.join(reasons, ", ")}")
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
        time_enabled = Keyword.get(opts, :time_enabled, Map.get(current_metadata, "time_enabled", false))
        time_slots = Keyword.get(opts, :time_slots, Map.get(current_metadata, "time_slots", []))

        new_title = if time_enabled and length(time_slots) > 0 do
          time_display = time_slots
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
        attrs = if description = Keyword.get(opts, :description) do
          Map.put(attrs, "description", description)
        else
          attrs
        end

        update_poll_option(poll_option, attrs, poll_type: "date_selection")
      rescue
        e in ArgumentError ->
          changeset = PollOption.changeset(poll_option, %{}, poll_type: "date_selection")
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
        end_time1  # Fallback to first time if parsing fails
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
    poll_with_options = Repo.preload(poll, [poll_options: :votes])

    options_with_tallies = poll_with_options.poll_options
    |> Enum.map(fn option ->
      %{
        option: option,
        tally: get_poll_option_vote_tally(option)
      }
    end)

    # Sort by score (highest first) for all poll types
    sorted_options = case poll.voting_system do
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
    tally = Enum.reduce(votes, %{yes: 0, maybe: 0, no: 0, total: 0}, fn vote, acc ->
      vote_type = case vote.vote_value do
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
    percentage = if tally.total > 0, do: (score / max_possible_score) * 100, else: 0.0

    # Calculate individual percentages
    yes_percentage = if tally.total > 0, do: (tally.yes / tally.total) * 100, else: 0.0
    maybe_percentage = if tally.total > 0, do: (tally.maybe / tally.total) * 100, else: 0.0
    no_percentage = if tally.total > 0, do: (tally.no / tally.total) * 100, else: 0.0

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
    selected = total  # In approval voting, all votes are "selected"

    # Score is simply the number of selections
    score = selected
    # Percentage is how many people selected this option (calculated later relative to total poll voters)

    %{
      selected: selected,
      total: total,
      score: score,
      percentage: 100.0,  # Will be recalculated relative to total poll voters
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
      rating_counts = Enum.reduce(votes, %{}, fn vote, acc ->
        rating = vote.vote_numeric |> Decimal.to_float() |> round()
        Map.update(acc, rating, 1, &(&1 + 1))
      end)

      # Calculate average rating
      total_rating_sum = Enum.reduce(votes, 0, fn vote, sum ->
        rating = vote.vote_numeric |> Decimal.to_float()
        sum + rating
      end)
      average_rating = total_rating_sum / total

      # Calculate score (0-100 based on average rating out of 5)
      score = (average_rating / 5.0) * 100
      percentage = score

      # Build rating distribution
      rating_distribution = for rating <- 1..5 do
        count = Map.get(rating_counts, rating, 0)
        rating_percentage = if total > 0, do: (count / total) * 100, else: 0.0
        %{rating: rating, count: count, percentage: Float.round(rating_percentage, 1)}
      end

      vote_distribution = Enum.map(rating_distribution, fn %{rating: rating, count: count, percentage: perc} ->
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
        average_rank: 999.0,  # High number for unranked
        rank_distribution: [],
        vote_distribution: []
      }
    else
      # Group votes by rank
      rank_counts = Enum.reduce(votes, %{}, fn vote, acc ->
        rank = vote.vote_rank
        Map.update(acc, rank, 1, &(&1 + 1))
      end)

      # Calculate average rank (lower is better)
      total_rank_sum = Enum.reduce(votes, 0, fn vote, sum ->
        sum + vote.vote_rank
      end)
      average_rank = total_rank_sum / total

      # Calculate score (inverse of average rank - higher rank = lower score)
      # Score is 100 / average_rank, so rank 1 = 100 points, rank 2 = 50 points, etc.
      score = if average_rank > 0, do: (100.0 / average_rank), else: 0.0
      percentage = min(score, 100.0)  # Cap at 100%

      # Build rank distribution
      max_rank = Map.keys(rank_counts) |> Enum.max()
      rank_distribution = for rank <- 1..max_rank do
        count = Map.get(rank_counts, rank, 0)
        rank_percentage = if total > 0, do: (count / total) * 100, else: 0.0
        %{rank: rank, count: count, percentage: Float.round(rank_percentage, 1)}
      end

      vote_distribution = Enum.map(rank_distribution, fn %{rank: rank, count: count, percentage: perc} ->
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
    options_with_stats = Enum.map(enhanced_tallies.options_with_tallies, fn %{option: option, tally: tally} ->
      relative_tally = case poll.voting_system do
        "approval" ->
          # For approval voting, calculate percentage relative to total poll voters
          selection_percentage = if total_voters > 0, do: (tally.selected / total_voters) * 100, else: 0.0
          Map.merge(tally, %{
            percentage: Float.round(selection_percentage, 1),
            vote_distribution: [
              %{type: "selected", count: tally.selected, percentage: Float.round(selection_percentage, 1)}
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

    %{
      poll_id: poll.id,
      poll_title: poll.title,
      voting_system: poll.voting_system,
      phase: poll.phase,
      total_unique_voters: total_voters,
      options: options_with_stats
    }
  end

  @doc """
  Broadcasts poll statistics update to all connected clients.
  Used for real-time updates when votes are cast.
  """
  def broadcast_poll_stats_update(%Poll{} = poll) do
    stats = get_poll_voting_stats(poll)

    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "polls:#{poll.id}:stats",
      {:poll_stats_updated, stats}
    )

    # Also broadcast to event channel
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      "events:#{poll.event_id}:polls",
      {:poll_stats_updated, poll.id, stats}
    )

    stats
  end
end
