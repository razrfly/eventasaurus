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
      threshold_count: nil
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
    allowed_fields = [:title, :description, :tagline, :cover_image_url, :external_image_data, :theme, :theme_customizations]
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
  Get recent locations for a specific user based on their event history.

  This function queries the user's past events to find frequently used locations,
  supporting both physical venues and virtual meeting URLs.

  ## Parameters

  - `user_id` - The ID of the user to query
  - `opts` - Optional parameters:
    - `:limit` - Maximum number of locations to return (default: 5)
    - `:exclude_event_ids` - List of event IDs to exclude from the query

  ## Returns

  A list of maps containing location information, sorted by usage frequency and recency.
  Each map contains:
  - `id` - Venue ID (nil for virtual events)
  - `name` - Location name ("Virtual Event" for virtual meetings)
  - `address` - Full address (nil for virtual events)
  - `city` - City name (nil for virtual events)
  - `state` - State name (nil for virtual events)
  - `country` - Country name (nil for virtual events)
  - `virtual_venue_url` - Meeting URL (nil for physical venues)
  - `usage_count` - Number of times this location has been used
  - `last_used` - DateTime of most recent usage

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
          last_used: ~U[2024-01-15 10:30:00Z]
        },
        %{
          id: nil,
          name: "Virtual Event",
          address: nil,
          city: nil,
          state: nil,
          country: nil,
          virtual_venue_url: "https://zoom.us/j/1234567890",
          usage_count: 3,
          last_used: ~U[2024-01-10 14:00:00Z]
        }
      ]

      iex> get_recent_locations_for_user(123, limit: 3, exclude_event_ids: [789])
      # Returns up to 3 locations, excluding event ID 789
  """
  def get_recent_locations_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    exclude_event_ids = Keyword.get(opts, :exclude_event_ids, [])

    query = from(eu in EventUser,
      join: e in Event, on: eu.event_id == e.id,
      left_join: v in Venue, on: e.venue_id == v.id,
      where: eu.user_id == ^user_id and e.id not in ^exclude_event_ids,
      select: %{
        venue_id: e.venue_id,
        venue_name: v.name,
        venue_address: v.address,
        venue_city: v.city,
        venue_state: v.state,
        venue_country: v.country,
        virtual_venue_url: e.virtual_venue_url,
        event_created_at: e.inserted_at
      }
    )

    query
    |> Repo.all()
    |> Enum.group_by(fn row ->
      # Group by venue_id for physical venues, or by virtual_venue_url for virtual events
      case {row.venue_id, row.virtual_venue_url} do
        {nil, nil} -> {:virtual, "Virtual Event"}
        {nil, url} when not is_nil(url) -> {:virtual, url}
        {venue_id, _} -> {:venue, venue_id}
      end
    end)
    |> Enum.map(fn {key, rows} ->
      # Calculate usage statistics
      usage_count = length(rows)
      last_used = rows |> Enum.map(& &1.event_created_at) |> Enum.max()

      # Build location info based on type
      case key do
        {:venue, venue_id} ->
          # Physical venue
          first_row = List.first(rows)
          %{
            id: venue_id,
            name: first_row.venue_name,
            address: first_row.venue_address,
            city: first_row.venue_city,
            state: first_row.venue_state,
            country: first_row.venue_country,
            virtual_venue_url: nil,
            usage_count: usage_count,
            last_used: last_used
          }

        {:virtual, url} ->
          # Virtual event
          %{
            id: nil,
            name: if(url == "Virtual Event", do: "Virtual Event", else: "Virtual Meeting"),
            address: nil,
            city: nil,
            state: nil,
            country: nil,
            virtual_venue_url: if(url == "Virtual Event", do: nil, else: url),
            usage_count: usage_count,
            last_used: last_used
          }
      end
    end)
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
