defmodule EventasaurusApp.Relationships do
  @moduledoc """
  The Relationships context manages connections between users.

  Relationships are formed organically through shared events, introductions, or manual
  connections. This module provides functions for creating, querying, and managing
  these connections with a focus on meaningful, event-driven social interactions.

  ## Core Concepts

  - **Origin**: How a relationship was formed (`:shared_event`, `:introduction`, `:manual`)
  - **Context**: Human-readable description of the connection (required for active relationships)
  - **Strength**: Measured by `shared_event_count` and `last_shared_event_at`
  - **Status**: Either `:active` or `:blocked`

  ## Relationship Symmetry

  Most operations create bidirectional relationships (A->B and B->A). Blocking is
  asymmetric - only the blocking user's relationship changes to `:blocked`.

  ## Example

      # Create a relationship from a shared event
      {:ok, relationships} = Relationships.create_from_shared_event(
        user1,
        user2,
        event,
        "Met at Jazz Night - January 2025"
      )

      # Check if users are connected
      Relationships.connected?(user1, user2)
      #=> true

      # Get all relationships for a user
      Relationships.list_relationships(user)

      # Block a user
      Relationships.block_user(user1, user2)
  """

  import Ecto.Query, warn: false

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Relationships.UserRelationship

  # =============================================================================
  # Core CRUD Operations
  # =============================================================================

  @doc """
  Gets a single relationship by ID.

  Returns `nil` if the relationship does not exist.

  ## Examples

      iex> get_relationship(123)
      %UserRelationship{}

      iex> get_relationship(999)
      nil
  """
  @spec get_relationship(integer()) :: UserRelationship.t() | nil
  def get_relationship(id), do: Repo.get(UserRelationship, id)

  @doc """
  Gets a relationship between two specific users.

  Returns the relationship from `user` to `other_user`, or `nil` if none exists.

  ## Examples

      iex> get_relationship_between(user1, user2)
      %UserRelationship{user_id: user1.id, related_user_id: user2.id}

      iex> get_relationship_between(stranger1, stranger2)
      nil
  """
  @spec get_relationship_between(User.t(), User.t()) :: UserRelationship.t() | nil
  def get_relationship_between(%User{id: user_id}, %User{id: related_user_id}) do
    Repo.get_by(UserRelationship, user_id: user_id, related_user_id: related_user_id)
  end

  @doc """
  Lists all active relationships for a user.

  Returns relationships where the user is the owner and status is `:active`.
  Preloads the related user for convenience.

  ## Options

  - `:limit` - Maximum number of relationships to return
  - `:order_by` - Field to order by (default: `:inserted_at`)

  ## Examples

      iex> list_relationships(user)
      [%UserRelationship{status: :active, related_user: %User{}}]
  """
  @spec list_relationships(User.t(), keyword()) :: [UserRelationship.t()]
  def list_relationships(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    order_by = Keyword.get(opts, :order_by, :inserted_at)

    query =
      from(r in UserRelationship,
        where: r.user_id == ^user_id and r.status == :active,
        order_by: [desc: field(r, ^order_by)],
        preload: [:related_user]
      )

    query =
      if limit do
        from(r in query, limit: ^limit)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Checks if two users are connected (have an active relationship).

  Returns `true` if there's an active relationship from `user` to `other_user`.

  ## Examples

      iex> connected?(user1, user2)
      true

      iex> connected?(stranger1, stranger2)
      false
  """
  @spec connected?(User.t(), User.t()) :: boolean()
  def connected?(%User{id: user_id}, %User{id: related_user_id}) do
    query =
      from(r in UserRelationship,
        where:
          r.user_id == ^user_id and
            r.related_user_id == ^related_user_id and
            r.status == :active
      )

    Repo.exists?(query)
  end

  @doc """
  Checks if two users are mutually connected (both have active relationships with each other).

  ## Examples

      iex> mutually_connected?(user1, user2)
      true
  """
  @spec mutually_connected?(User.t(), User.t()) :: boolean()
  def mutually_connected?(user1, user2) do
    connected?(user1, user2) && connected?(user2, user1)
  end

  # =============================================================================
  # Relationship Creation
  # =============================================================================

  @doc """
  Creates a bidirectional relationship from a shared event.

  This is the primary way relationships are formed in Eventasaurus. When two users
  attend the same event and one initiates a connection, both directions are created.

  ## Parameters

  - `user` - The user initiating the connection
  - `other_user` - The other user to connect with
  - `event` - The event where they met
  - `context` - Human-readable context (e.g., "Met at Jazz Night - January 2025")

  ## Returns

  - `{:ok, {relationship1, relationship2}}` - Both relationship records
  - `{:error, changeset}` - If validation fails

  ## Examples

      iex> create_from_shared_event(user1, user2, event, "Met at Jazz Night")
      {:ok, {%UserRelationship{}, %UserRelationship{}}}
  """
  @spec create_from_shared_event(User.t(), User.t(), Event.t(), String.t()) ::
          {:ok, {UserRelationship.t(), UserRelationship.t()}} | {:error, Ecto.Changeset.t()}
  def create_from_shared_event(%User{id: user_id}, %User{id: other_user_id}, %Event{id: event_id}, context)
      when user_id != other_user_id do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      # Create or update relationship in both directions
      rel1 =
        create_or_update_relationship(%{
          user_id: user_id,
          related_user_id: other_user_id,
          origin: :shared_event,
          context: context,
          originated_from_event_id: event_id,
          last_shared_event_at: now
        })

      rel2 =
        create_or_update_relationship(%{
          user_id: other_user_id,
          related_user_id: user_id,
          origin: :shared_event,
          context: context,
          originated_from_event_id: event_id,
          last_shared_event_at: now
        })

      case {rel1, rel2} do
        {{:ok, r1}, {:ok, r2}} -> {r1, r2}
        {{:error, changeset}, _} -> Repo.rollback(changeset)
        {_, {:error, changeset}} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Creates a bidirectional relationship from an introduction.

  Used when a mutual connection introduces two users to each other.

  ## Parameters

  - `user` - The user being introduced
  - `other_user` - The other user being introduced
  - `introducer` - The mutual connection making the introduction
  - `context` - Human-readable context (e.g., "Introduced by Sarah")

  ## Returns

  - `{:ok, {relationship1, relationship2}}` - Both relationship records
  - `{:error, changeset}` - If validation fails
  """
  @spec create_from_introduction(User.t(), User.t(), User.t(), String.t()) ::
          {:ok, {UserRelationship.t(), UserRelationship.t()}} | {:error, Ecto.Changeset.t()}
  def create_from_introduction(
        %User{id: user_id},
        %User{id: other_user_id},
        %User{id: _introducer_id},
        context
      )
      when user_id != other_user_id do
    Repo.transaction(fn ->
      rel1 =
        create_or_update_relationship(%{
          user_id: user_id,
          related_user_id: other_user_id,
          origin: :introduction,
          context: context
        })

      rel2 =
        create_or_update_relationship(%{
          user_id: other_user_id,
          related_user_id: user_id,
          origin: :introduction,
          context: context
        })

      case {rel1, rel2} do
        {{:ok, r1}, {:ok, r2}} -> {r1, r2}
        {{:error, changeset}, _} -> Repo.rollback(changeset)
        {_, {:error, changeset}} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Creates a manual relationship (user-initiated without event context).

  ## Parameters

  - `user` - The user creating the relationship
  - `other_user` - The user to connect with
  - `context` - Human-readable context (required)

  ## Returns

  - `{:ok, {relationship1, relationship2}}` - Both relationship records
  - `{:error, changeset}` - If validation fails
  """
  @spec create_manual(User.t(), User.t(), String.t()) ::
          {:ok, {UserRelationship.t(), UserRelationship.t()}} | {:error, Ecto.Changeset.t()}
  def create_manual(%User{id: user_id}, %User{id: other_user_id}, context)
      when user_id != other_user_id do
    Repo.transaction(fn ->
      rel1 =
        create_or_update_relationship(%{
          user_id: user_id,
          related_user_id: other_user_id,
          origin: :manual,
          context: context
        })

      rel2 =
        create_or_update_relationship(%{
          user_id: other_user_id,
          related_user_id: user_id,
          origin: :manual,
          context: context
        })

      case {rel1, rel2} do
        {{:ok, r1}, {:ok, r2}} -> {r1, r2}
        {{:error, changeset}, _} -> Repo.rollback(changeset)
        {_, {:error, changeset}} -> Repo.rollback(changeset)
      end
    end)
  end

  # Helper to create or update a relationship
  defp create_or_update_relationship(attrs) do
    case Repo.get_by(UserRelationship, user_id: attrs.user_id, related_user_id: attrs.related_user_id) do
      nil ->
        %UserRelationship{}
        |> UserRelationship.changeset(attrs)
        |> Repo.insert()

      existing ->
        # Update shared event count if this is a new shared event
        new_count = existing.shared_event_count + 1

        existing
        |> UserRelationship.metrics_changeset(%{
          shared_event_count: new_count,
          last_shared_event_at: attrs[:last_shared_event_at],
          context: attrs[:context]
        })
        |> Repo.update()
    end
  end

  # =============================================================================
  # Relationship Strength & Discovery
  # =============================================================================

  @doc """
  Gets the relationship strength between two users.

  Strength is calculated based on:
  - Number of shared events
  - Recency of last shared event

  Returns a float between 0.0 and 1.0, or `nil` if no relationship exists.

  ## Examples

      iex> relationship_strength(user1, user2)
      0.85

      iex> relationship_strength(stranger1, stranger2)
      nil
  """
  @spec relationship_strength(User.t(), User.t()) :: float() | nil
  def relationship_strength(%User{id: user_id}, %User{id: related_user_id}) do
    case Repo.get_by(UserRelationship, user_id: user_id, related_user_id: related_user_id, status: :active) do
      nil ->
        nil

      relationship ->
        calculate_strength(relationship)
    end
  end

  defp calculate_strength(%UserRelationship{} = rel) do
    # Base score from shared events (max out at 10 events)
    event_score = min(rel.shared_event_count / 10, 1.0) * 0.6

    # Recency score (decays over 90 days)
    recency_score =
      case rel.last_shared_event_at do
        nil ->
          0.2

        last_shared ->
          days_ago = DateTime.diff(DateTime.utc_now(), last_shared, :day)
          max(1.0 - days_ago / 90, 0.0) * 0.4
      end

    Float.round(event_score + recency_score, 2)
  end

  @doc """
  Lists relationships ordered by strength (strongest first).

  Useful for showing "closest" connections or suggesting introductions.

  ## Options

  - `:limit` - Maximum number to return (default: 10)
  - `:min_strength` - Minimum strength threshold (default: 0.0)

  ## Examples

      iex> list_by_strength(user, limit: 5)
      [%UserRelationship{shared_event_count: 8}, %UserRelationship{shared_event_count: 5}]
  """
  @spec list_by_strength(User.t(), keyword()) :: [UserRelationship.t()]
  def list_by_strength(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    query =
      from(r in UserRelationship,
        where: r.user_id == ^user_id and r.status == :active,
        order_by: [desc: r.shared_event_count, desc: r.last_shared_event_at],
        limit: ^limit,
        preload: [:related_user]
      )

    Repo.all(query)
  end

  @doc """
  Finds mutual connections between two users.

  Returns users who are connected to both the given users.
  Useful for suggesting introductions or showing "friends in common".

  ## Examples

      iex> mutual_connections(user1, user2)
      [%User{name: "Mutual Friend"}]
  """
  @spec mutual_connections(User.t(), User.t()) :: [User.t()]
  def mutual_connections(%User{id: user1_id}, %User{id: user2_id}) do
    query =
      from(r1 in UserRelationship,
        join: r2 in UserRelationship,
        on: r1.related_user_id == r2.related_user_id,
        join: u in User,
        on: u.id == r1.related_user_id,
        where:
          r1.user_id == ^user1_id and
            r2.user_id == ^user2_id and
            r1.status == :active and
            r2.status == :active,
        select: u
      )

    Repo.all(query)
  end

  @doc """
  Finds users who might know each other through mutual connections.

  Returns users who are:
  1. Not already connected to the given user
  2. Have at least one mutual connection

  Useful for "People You May Know" features.

  ## Options

  - `:limit` - Maximum number to return (default: 10)
  - `:min_mutual` - Minimum mutual connections required (default: 1)

  ## Examples

      iex> suggested_connections(user, limit: 5)
      [%{user: %User{}, mutual_count: 3}]
  """
  @spec suggested_connections(User.t(), keyword()) :: [%{user: User.t(), mutual_count: integer()}]
  def suggested_connections(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    min_mutual = Keyword.get(opts, :min_mutual, 1)

    # Get all user's current connections
    connected_ids =
      from(r in UserRelationship,
        where: r.user_id == ^user_id and r.status == :active,
        select: r.related_user_id
      )
      |> Repo.all()

    # Find friends of friends, excluding already-connected users
    query =
      from(r1 in UserRelationship,
        join: r2 in UserRelationship,
        on: r1.related_user_id == r2.user_id,
        join: u in User,
        on: u.id == r2.related_user_id,
        where:
          r1.user_id == ^user_id and
            r1.status == :active and
            r2.status == :active and
            r2.related_user_id != ^user_id and
            r2.related_user_id not in ^connected_ids,
        group_by: u.id,
        having: count(r2.id) >= ^min_mutual,
        order_by: [desc: count(r2.id)],
        limit: ^limit,
        select: %{user: u, mutual_count: count(r2.id)}
      )

    Repo.all(query)
  end

  # =============================================================================
  # Blocking Functions
  # =============================================================================

  @doc """
  Blocks a user.

  This updates the relationship status to `:blocked`. The blocked user will not
  be able to see or interact with the blocking user. Blocking is asymmetric -
  only the blocking user's relationship is updated.

  ## Parameters

  - `blocker` - The user doing the blocking
  - `blocked_user` - The user being blocked

  ## Returns

  - `{:ok, relationship}` - The updated relationship
  - `{:error, :no_relationship}` - If no relationship exists (creates a blocked one)
  """
  @spec block_user(User.t(), User.t()) :: {:ok, UserRelationship.t()} | {:error, Ecto.Changeset.t()}
  def block_user(%User{id: blocker_id}, %User{id: blocked_id}) when blocker_id != blocked_id do
    case Repo.get_by(UserRelationship, user_id: blocker_id, related_user_id: blocked_id) do
      nil ->
        # Create a new blocked relationship
        %UserRelationship{}
        |> UserRelationship.changeset(%{
          user_id: blocker_id,
          related_user_id: blocked_id,
          status: :blocked,
          origin: :manual,
          context: nil
        })
        |> Repo.insert()

      relationship ->
        relationship
        |> UserRelationship.status_changeset(%{status: :blocked, context: nil})
        |> Repo.update()
    end
  end

  @doc """
  Unblocks a user.

  This removes the relationship entirely (rather than restoring to active,
  since the context may no longer be valid).

  ## Parameters

  - `unblocker` - The user doing the unblocking
  - `unblocked_user` - The user being unblocked

  ## Returns

  - `{:ok, relationship}` - The deleted relationship
  - `{:error, :not_found}` - If no blocked relationship exists
  """
  @spec unblock_user(User.t(), User.t()) :: {:ok, UserRelationship.t()} | {:error, :not_found}
  def unblock_user(%User{id: unblocker_id}, %User{id: unblocked_id}) do
    case Repo.get_by(UserRelationship, user_id: unblocker_id, related_user_id: unblocked_id, status: :blocked) do
      nil ->
        {:error, :not_found}

      relationship ->
        Repo.delete(relationship)
    end
  end

  @doc """
  Checks if a user has blocked another user.

  ## Examples

      iex> blocked?(user1, user2)
      true
  """
  @spec blocked?(User.t(), User.t()) :: boolean()
  def blocked?(%User{id: blocker_id}, %User{id: blocked_id}) do
    query =
      from(r in UserRelationship,
        where:
          r.user_id == ^blocker_id and
            r.related_user_id == ^blocked_id and
            r.status == :blocked
      )

    Repo.exists?(query)
  end

  @doc """
  Lists all users blocked by the given user.

  ## Examples

      iex> list_blocked(user)
      [%User{}]
  """
  @spec list_blocked(User.t()) :: [User.t()]
  def list_blocked(%User{id: user_id}) do
    query =
      from(r in UserRelationship,
        join: u in User,
        on: u.id == r.related_user_id,
        where: r.user_id == ^user_id and r.status == :blocked,
        select: u
      )

    Repo.all(query)
  end

  # =============================================================================
  # Event-Related Functions
  # =============================================================================

  @doc """
  Records that two users attended the same event.

  If they already have a relationship, increments the shared event count.
  If not, does nothing (relationships must be explicitly created).

  ## Parameters

  - `user1` - First user
  - `user2` - Second user
  - `event` - The shared event

  ## Returns

  - `{:ok, relationships}` - Updated relationships (if any existed)
  - `{:ok, nil}` - If no relationship existed
  """
  @spec record_shared_event(User.t(), User.t(), Event.t()) ::
          {:ok, {UserRelationship.t(), UserRelationship.t()} | nil}
  def record_shared_event(%User{id: user1_id}, %User{id: user2_id}, %Event{} = _event)
      when user1_id != user2_id do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Only update if relationships already exist
    rel1 = Repo.get_by(UserRelationship, user_id: user1_id, related_user_id: user2_id, status: :active)
    rel2 = Repo.get_by(UserRelationship, user_id: user2_id, related_user_id: user1_id, status: :active)

    case {rel1, rel2} do
      {nil, nil} ->
        {:ok, nil}

      {r1, r2} ->
        Repo.transaction(fn ->
          updated_r1 =
            if r1 do
              {:ok, updated} =
                r1
                |> UserRelationship.metrics_changeset(%{
                  shared_event_count: r1.shared_event_count + 1,
                  last_shared_event_at: now
                })
                |> Repo.update()

              updated
            end

          updated_r2 =
            if r2 do
              {:ok, updated} =
                r2
                |> UserRelationship.metrics_changeset(%{
                  shared_event_count: r2.shared_event_count + 1,
                  last_shared_event_at: now
                })
                |> Repo.update()

              updated
            end

          {updated_r1, updated_r2}
        end)
    end
  end

  @doc """
  Gets all relationships formed at a specific event.

  Useful for showing "connections made at this event".

  ## Examples

      iex> relationships_from_event(event)
      [%UserRelationship{origin: :shared_event}]
  """
  @spec relationships_from_event(Event.t()) :: [UserRelationship.t()]
  def relationships_from_event(%Event{id: event_id}) do
    query =
      from(r in UserRelationship,
        where: r.originated_from_event_id == ^event_id and r.status == :active,
        preload: [:user, :related_user]
      )

    Repo.all(query)
  end

  # =============================================================================
  # Deletion
  # =============================================================================

  @doc """
  Removes a relationship in both directions.

  This is a "soft" removal - the records are deleted entirely.

  ## Parameters

  - `user` - One user in the relationship
  - `other_user` - The other user

  ## Returns

  - `{:ok, count}` - Number of relationships deleted (0, 1, or 2)
  """
  @spec remove_relationship(User.t(), User.t()) :: {:ok, integer()}
  def remove_relationship(%User{id: user_id}, %User{id: other_user_id}) do
    query =
      from(r in UserRelationship,
        where:
          (r.user_id == ^user_id and r.related_user_id == ^other_user_id) or
            (r.user_id == ^other_user_id and r.related_user_id == ^user_id)
      )

    {count, _} = Repo.delete_all(query)
    {:ok, count}
  end
end
