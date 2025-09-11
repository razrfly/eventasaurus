defmodule EventasaurusApp.Events.EventParticipant do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto.SoftDelete.Schema

  schema "event_participants" do
    field :role, Ecto.Enum, values: [:invitee, :poll_voter, :ticket_holder]
    field :status, Ecto.Enum, values: [:pending, :accepted, :declined, :cancelled, :confirmed_with_order, :interested]
    field :source, :string
    field :metadata, :map

    # Guest invitation fields
    field :invited_at, :utc_datetime
    field :invitation_message, :string

    belongs_to :event, EventasaurusApp.Events.Event
    belongs_to :user, EventasaurusApp.Accounts.User
    belongs_to :invited_by_user, EventasaurusApp.Accounts.User

    # Deletion metadata fields
    field :deletion_reason, :string
    belongs_to :deleted_by_user, EventasaurusApp.Accounts.User, foreign_key: :deleted_by_user_id

    timestamps()
    soft_delete_schema()
  end

  @doc false
  def changeset(event_participant, attrs) do
    event_participant
    |> cast(attrs, [:role, :status, :source, :metadata, :event_id, :user_id,
                    :invited_by_user_id, :invited_at, :invitation_message])
    |> validate_required([:role, :status, :event_id, :user_id])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:invited_by_user_id)
    |> unique_constraint([:event_id, :user_id])
    |> validate_not_event_user()
    |> validate_invitation_fields()
  end

  # Email status tracking functions

  @doc """
  Gets the email status for a participant.
  Returns email status information from the metadata field.
  """
  def get_email_status(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    %{
      status: Map.get(metadata, "email_status", "not_sent"),
      last_sent_at: Map.get(metadata, "email_last_sent_at"),
      attempts: Map.get(metadata, "email_attempts", 0),
      last_error: Map.get(metadata, "email_last_error"),
      delivery_id: Map.get(metadata, "email_delivery_id")
    }
  end
  def get_email_status(_), do: %{status: "not_sent", attempts: 0}

  @doc """
  Updates the email status in the participant's metadata.
  """
  def update_email_status(%__MODULE__{} = participant, status, attrs \\ %{}) do
    current_metadata = participant.metadata || %{}
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    email_metadata = %{
      "email_status" => status,
      "email_last_updated_at" => timestamp,
      "email_attempts" => Map.get(current_metadata, "email_attempts", 0) + 1
    }

    # Add optional attributes like error message, delivery ID
    email_metadata = Map.merge(email_metadata, attrs)

    # If status is "sent", update the sent timestamp
    email_metadata = if status == "sent" do
      Map.put(email_metadata, "email_last_sent_at", timestamp)
    else
      email_metadata
    end

    updated_metadata = Map.merge(current_metadata, email_metadata)

    %{participant | metadata: updated_metadata}
  end

  @doc """
  Marks an email as sent with optional delivery ID.
  """
  def mark_email_sent(%__MODULE__{} = participant, delivery_id \\ nil) do
    attrs = if delivery_id, do: %{"email_delivery_id" => delivery_id}, else: %{}
    update_email_status(participant, "sent", attrs)
  end

  @doc """
  Marks an email as failed with error message.
  """
  def mark_email_failed(%__MODULE__{} = participant, error_message) do
    attrs = %{"email_last_error" => error_message}
    update_email_status(participant, "failed", attrs)
  end

  @doc """
  Marks an email as delivered (for webhook updates).
  """
  def mark_email_delivered(%__MODULE__{} = participant) do
    update_email_status(participant, "delivered")
  end

  @doc """
  Marks an email as bounced (for webhook updates).
  """
  def mark_email_bounced(%__MODULE__{} = participant, bounce_reason \\ nil) do
    attrs = if bounce_reason, do: %{"email_bounce_reason" => bounce_reason}, else: %{}
    update_email_status(participant, "bounced", attrs)
  end

  @doc """
  Checks if an email can be retried based on attempt count and last failure.
  """
  def can_retry_email?(%__MODULE__{} = participant, max_attempts \\ 3) do
    email_status = get_email_status(participant)

    email_status.status in ["failed", "bounced"] and
    email_status.attempts < max_attempts
  end

  @doc """
  Gets participants that need email retry.
  """
  def get_retry_candidates(event_id, max_attempts \\ 3) do
    from(ep in __MODULE__,
      where: ep.event_id == ^event_id,
      where: fragment("(?->>'email_status') IN ('failed', 'bounced')", ep.metadata),
      where: fragment("COALESCE((?->>'email_attempts')::integer, 0) < ?", ep.metadata, ^max_attempts),
      preload: [:user, :invited_by_user]
    )
  end

  @doc """
  Gets participants by email status.
  """
  def by_email_status(query \\ __MODULE__, status) do
    from(ep in query,
      where: fragment("(?->>'email_status') = ?", ep.metadata, ^status)
    )
  end

  @doc """
  Gets participants without email status (never sent).
  """
  def without_email_status(query \\ __MODULE__) do
    from(ep in query,
      where: fragment("(?->>'email_status') IS NULL", ep.metadata)
    )
  end

  @doc """
  Gets participants with failed email delivery.
  """
  def with_failed_emails(query \\ __MODULE__) do
    from(ep in query,
      where: fragment("(?->>'email_status') IN ('failed', 'bounced')", ep.metadata)
    )
  end

  defp validate_not_event_user(changeset) do
    event_id = get_field(changeset, :event_id)
    user_id = get_field(changeset, :user_id)

    if event_id && user_id do
      # Check if user is already an event_user (organizer/admin) for this event
      query = from eu in EventasaurusApp.Events.EventUser,
              where: eu.event_id == ^event_id and eu.user_id == ^user_id

      case EventasaurusApp.Repo.one(query) do
        nil ->
          # User is not an event_user, validation passes
          changeset
        _event_user ->
          # User is already an event_user, add error
          add_error(changeset, :user_id, "cannot be a participant because they are already an organizer/admin for this event")
      end
    else
      changeset
    end
  end

  # New validation function for invitation fields
  defp validate_invitation_fields(changeset) do
    changeset
    |> validate_length(:invitation_message, max: 1000, message: "must be 1000 characters or less")
    |> validate_invited_by_not_self()
  end

  defp validate_invited_by_not_self(changeset) do
    user_id = get_field(changeset, :user_id)
    invited_by_user_id = get_field(changeset, :invited_by_user_id)

    if user_id && invited_by_user_id && user_id == invited_by_user_id do
      add_error(changeset, :invited_by_user_id, "cannot invite yourself")
    else
      changeset
    end
  end

  # Status validation functions - single source of truth from schema

  @doc """
  Gets valid status atoms directly from the schema definition.
  This ensures the schema remains the single source of truth.
  """
  def valid_statuses do
    __MODULE__.__schema__(:type, :status) 
    |> elem(1) 
    |> Keyword.get(:values)
  end

  @doc """
  Gets valid status strings for API/form validation.
  """
  def valid_status_strings do
    valid_statuses() |> Enum.map(&Atom.to_string/1)
  end

  @doc """
  Safely parses a status string to atom, validating against schema.
  Returns {:ok, atom} for valid statuses, {:error, :invalid_status} otherwise.
  """
  def parse_status(status_str) when is_binary(status_str) do
    if status_str in valid_status_strings() do
      {:ok, String.to_existing_atom(status_str)}
    else
      {:error, :invalid_status}
    end
  end
end
