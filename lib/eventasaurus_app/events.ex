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
          # Persist the change to the database using the updated fields
          attrs = %{
            status: updated_event.status,
            canceled_at: updated_event.canceled_at
          }

          changeset = Event.changeset(event, attrs)
          case Repo.update(changeset) do
            {:ok, persisted_event} -> Event.with_computed_fields(persisted_event)
            {:error, changeset} -> Repo.rollback(changeset)
          end
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
            preload: [:user]

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
                # Create user with temporary supabase_id - will be updated when they confirm email
                temp_supabase_id = "temp_#{Ecto.UUID.generate()}"
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

  defp create_or_find_supabase_user(email, name) do
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
    case Machinery.transition_to(event, EventStateMachine, new_state) do
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
    case Machinery.transition_to(event, EventStateMachine, new_state) do
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
    Repo.delete(option)
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
    new_dates =
      new_dates
      |> Enum.map(&ensure_date_struct/1)
      |> Enum.uniq()

    existing_options = list_event_date_options(poll)
    existing_dates = Enum.map(existing_options, & &1.date)

    # Find dates to add and remove
    dates_to_add = new_dates -- existing_dates
    dates_to_remove = existing_dates -- new_dates

    # Early exit if no changes needed
    if dates_to_add == [] and dates_to_remove == [] do
      {:ok, existing_options}
    else
      Repo.transaction(fn ->
        # Remove date options that are no longer selected
        if length(dates_to_remove) > 0 do
          options_to_remove = Enum.filter(existing_options, fn option ->
            option.date in dates_to_remove
          end)

          Enum.each(options_to_remove, fn option ->
            case delete_event_date_option(option) do
              {:ok, _} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)
        end

        # Add new date options
        if length(dates_to_add) > 0 do
          Enum.each(dates_to_add, fn date ->
            case create_event_date_option(poll, date) do
              {:ok, _option} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)
        end

        # Return the updated list of options
        list_event_date_options(poll)
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
end
