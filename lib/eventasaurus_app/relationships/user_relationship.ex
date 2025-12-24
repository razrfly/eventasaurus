defmodule EventasaurusApp.Relationships.UserRelationship do
  @moduledoc """
  Schema representing a relationship between two users.

  Relationships are formed through shared events, introductions, or manual connections.
  This schema tracks the origin and context of how users became connected, as well as
  the strength of their relationship through shared event metrics.

  ## Fields

  - `user_id` - The ID of the user who initiated or owns this relationship record
  - `related_user_id` - The ID of the other user in the relationship
  - `status` - The current status: `:active` or `:blocked`
  - `origin` - How the relationship was formed: `:shared_event`, `:introduction`, or `:manual`
  - `context` - Human-readable context (e.g., "Met at Jazz Night - Jan 2025")
  - `originated_from_event_id` - The event where the relationship was formed (if applicable)
  - `shared_event_count` - Number of events both users have attended together
  - `last_shared_event_at` - When the users last attended an event together

  ## Relationship Symmetry

  Relationships are stored as directed edges (user_id -> related_user_id). For mutual
  relationships, two records exist (A->B and B->A). This allows for asymmetric states
  like blocking (A blocks B, but B doesn't block A).

  ## Constraints

  - Unique constraint on `[user_id, related_user_id]` prevents duplicate relationships
  - Check constraint prevents self-relationships
  - Check constraint requires context when status is `:active`
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type status :: :active | :blocked
  @type origin :: :shared_event | :introduction | :manual

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          related_user_id: integer() | nil,
          status: status(),
          origin: origin(),
          context: String.t() | nil,
          originated_from_event_id: integer() | nil,
          shared_event_count: integer(),
          last_shared_event_at: DateTime.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "user_relationships" do
    belongs_to(:user, EventasaurusApp.Accounts.User)
    belongs_to(:related_user, EventasaurusApp.Accounts.User)
    belongs_to(:originated_from_event, EventasaurusApp.Events.Event)

    field(:status, Ecto.Enum, values: [:active, :blocked], default: :active)
    field(:origin, Ecto.Enum, values: [:shared_event, :introduction, :manual])
    field(:context, :string)
    field(:shared_event_count, :integer, default: 1)
    field(:last_shared_event_at, :utc_datetime)

    timestamps()
  end

  @doc """
  Builds a changeset for creating a new relationship.

  ## Parameters

  - `relationship` - The `%UserRelationship{}` struct
  - `attrs` - Map of attributes

  ## Required Fields

  - `user_id` - The initiating user
  - `related_user_id` - The other user
  - `origin` - How the relationship was formed
  - `context` - Required for active relationships

  ## Validations

  - Both user IDs are required
  - Origin is required
  - Context is required when status is `:active`
  - Foreign key constraints on all IDs
  - Unique constraint on user pair
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :user_id,
      :related_user_id,
      :status,
      :origin,
      :context,
      :originated_from_event_id,
      :shared_event_count,
      :last_shared_event_at
    ])
    |> validate_required([:user_id, :related_user_id, :origin])
    |> validate_context_when_active()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:related_user_id)
    |> foreign_key_constraint(:originated_from_event_id)
    |> unique_constraint([:user_id, :related_user_id])
    |> check_constraint(:user_id, name: :no_self_relationship, message: "cannot create relationship with yourself")
  end

  @doc """
  Builds a changeset for updating relationship status (e.g., blocking).

  ## Parameters

  - `relationship` - The existing `%UserRelationship{}` struct
  - `attrs` - Map with `:status` and optionally updated `:context`
  """
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:status, :context])
    |> validate_context_when_active()
  end

  @doc """
  Builds a changeset for updating shared event metrics.

  ## Parameters

  - `relationship` - The existing `%UserRelationship{}` struct
  - `attrs` - Map with `:shared_event_count` and/or `:last_shared_event_at`
  """
  @spec metrics_changeset(t(), map()) :: Ecto.Changeset.t()
  def metrics_changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:shared_event_count, :last_shared_event_at, :context])
  end

  # Private validation that ensures context is present when status is active
  defp validate_context_when_active(changeset) do
    status = get_field(changeset, :status)
    context = get_field(changeset, :context)

    if status == :active && (is_nil(context) || context == "") do
      add_error(changeset, :context, "is required for active relationships")
    else
      changeset
    end
  end
end
