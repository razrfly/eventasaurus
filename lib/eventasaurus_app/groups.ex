defmodule EventasaurusApp.Groups do
  @moduledoc """
  The Groups context provides comprehensive group management functionality
  for the Eventasaurus application.

  This module handles all operations related to groups and group membership,
  including CRUD operations, membership management, role-based permissions,
  and comprehensive audit logging.

  ## Core Features

  * **Group Management**: Create, read, update, delete groups with soft delete support
  * **Membership Management**: Add/remove members, role assignments, and membership queries
  * **Role-Based Permissions**: Admin and member roles with ownership-based access control
  * **Audit Logging**: Comprehensive logging of all group operations for security and compliance
  * **Venue Integration**: Support for venue assignment to groups with location data

  ## Roles and Permissions

  Groups support two roles:
  * **admin** - Can manage group settings and members
  * **member** - Regular group member

  Group creators are automatically assigned as admins. Group owners (creators)
  have ultimate management permissions regardless of their role status.

  ## Usage Examples

      # Create a group with automatic creator membership
      user = Accounts.get_user!(123)
      {:ok, group} = Groups.create_group_with_creator(%{
        name: "SF Tech Meetup",
        description: "Weekly tech meetups in San Francisco"
      }, user)
      
      # Add a member to the group
      new_member = Accounts.get_user!(456)
      {:ok, _membership} = Groups.add_user_to_group(group, new_member, "member", user)
      
      # Check permissions
      Groups.can_manage?(group, user) # => true (owner)
      Groups.is_admin?(group, new_member) # => false
      
      # List members with roles
      members = Groups.list_group_members_with_roles(group)
      # => [%{user: %User{}, role: "admin", joined_at: ~U[...]}, ...]
      
  ## Audit Logging

  All group operations are automatically logged for security and compliance:
  * Group creation, updates, and deletion
  * Member additions and removals with reasons
  * Role changes with before/after states
  * IP address and metadata tracking for all operations

  Audit logs include actor identification, timestamps, and operation metadata.
  """

  import Ecto.Query, warn: false
  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Groups.{Group, GroupUser, GroupJoinRequest}
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.AuditLogger

  @doc """
  Returns the list of groups.

  ## Examples

      iex> list_groups()
      [%Group{}, ...]

  """
  def list_groups do
    Repo.all(Group)
  end

  @doc """
  Returns groups with preloaded user info and event counts.
  This avoids N+1 queries when displaying group lists.
  Respects privacy settings - only returns discoverable groups.

  ## Parameters
  - user: The current user to check membership
  - search_query: Optional search term for filtering groups
  - only_user_groups: If true, only returns groups the user is a member of

  ## Examples

      iex> list_groups_with_user_info(user, "", false)
      [%{group: %Group{}, event_count: 5, is_member: true, user_role: "admin"}, ...]
  """
  def list_groups_with_user_info(%User{} = user, search_query \\ "", only_user_groups \\ false) do
    # Base query for groups with privacy filtering
    base_query =
      from(g in Group,
        left_join: gu in GroupUser,
        on: gu.group_id == g.id and gu.user_id == ^user.id,
        preload: [:venue, :created_by],
        # Show public groups to everyone
        # Show private groups only to members  
        # Unlisted groups are not discoverable in listings
        where:
          g.visibility == "public" or
            (g.visibility == "private" and not is_nil(gu.id)) or
            false
      )

    # Apply search filter
    query =
      if search_query && String.trim(search_query) != "" do
        search_term = "%#{search_query}%"

        from([g, gu] in base_query,
          where: ilike(g.name, ^search_term) or ilike(g.description, ^search_term)
        )
      else
        base_query
      end

    # Apply user groups filter
    query =
      if only_user_groups do
        from([g, gu] in query,
          where: not is_nil(gu.id)
        )
      else
        query
      end

    # Get groups with user info
    groups_with_membership =
      from([g, gu] in query,
        select: %{
          group: g,
          is_member: not is_nil(gu.id),
          user_role: gu.role
        }
      )

    # Execute query and get groups
    results = Repo.all(groups_with_membership)

    # Get event counts in batch
    group_ids = Enum.map(results, & &1.group.id)

    event_counts =
      from(e in EventasaurusApp.Events.Event,
        where: e.group_id in ^group_ids,
        group_by: e.group_id,
        select: {e.group_id, count(e.id)}
      )

    event_count_map = Repo.all(event_counts) |> Map.new()

    # Get member counts for each group
    member_counts =
      from(gu in GroupUser,
        where: gu.group_id in ^group_ids,
        group_by: gu.group_id,
        select: {gu.group_id, count(gu.id)}
      )

    member_count_map = Repo.all(member_counts) |> Map.new()

    # Combine results and filter based on discoverability
    results
    |> Enum.filter(fn %{group: group, is_member: _is_member} ->
      can_discover_group?(group, user)
    end)
    |> Enum.map(fn %{group: group, is_member: is_member, user_role: user_role} ->
      Map.merge(group, %{
        event_count: Map.get(event_count_map, group.id, 0),
        member_count: Map.get(member_count_map, group.id, 0),
        is_member: is_member,
        user_role: user_role
      })
    end)
  end

  @doc """
  Returns the list of groups for a specific user.

  ## Examples

      iex> list_user_groups(user)
      [%Group{}, ...]

  """
  def list_user_groups(%User{} = user) do
    user
    |> Ecto.assoc(:groups)
    |> Repo.all()
    |> Repo.preload([:venue, :created_by])
  end

  @doc """
  Gets a single group.

  Returns the group or `nil` if the Group does not exist.

  ## Examples

      iex> get_group(123)
      %Group{}

      iex> get_group(456)
      nil

  """
  def get_group(id) do
    case Group
         |> Repo.get(id) do
      nil -> nil
      group -> Repo.preload(group, [:venue, :users, :created_by])
    end
  end

  @doc """
  Gets a single group.

  Raises `Ecto.NoResultsError` if the Group does not exist.

  ## Examples

      iex> get_group!(123)
      %Group{}

      iex> get_group!(456)
      ** (Ecto.NoResultsError)

  """
  def get_group!(id) do
    Group
    |> Repo.get!(id)
    |> Repo.preload([:venue, :users, :created_by])
  end

  @doc """
  Gets a single group by slug.

  Returns nil if the Group does not exist.

  ## Examples

      iex> get_group_by_slug("my-group")
      %Group{}

      iex> get_group_by_slug("nonexistent")
      nil

  """
  def get_group_by_slug(slug) when is_binary(slug) do
    Group
    |> where(slug: ^slug)
    |> preload([:venue, :users, :created_by])
    |> Repo.one()
  end

  @doc """
  Creates a group with audit logging.

  This function creates a new group and automatically logs the creation
  if a creator is specified via the `created_by_id` attribute.

  ## Parameters

  * `attrs` - Map of group attributes (name, description, etc.)
  * `metadata` - Optional audit metadata (IP address, request context, etc.)

  ## Returns

  * `{:ok, %Group{}}` - Successfully created group with preloaded associations
  * `{:error, %Ecto.Changeset{}}` - Validation or database errors

  ## Examples

      # Basic group creation
      iex> create_group(%{name: "Tech Meetup", slug: "tech-meetup"})
      {:ok, %Group{name: "Tech Meetup"}}

      # Group creation with creator and audit metadata
      iex> create_group(%{
      ...>   name: "SF Developers",
      ...>   slug: "sf-developers", 
      ...>   created_by_id: 123
      ...> }, %{ip_address: "192.168.1.1"})
      {:ok, %Group{}}

      # Invalid data
      iex> create_group(%{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_group(attrs \\ %{}, metadata \\ %{}) do
    %Group{}
    |> Group.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, group} ->
        # Log group creation
        if Map.get(attrs, "created_by_id") || Map.get(attrs, :created_by_id) do
          user_id = Map.get(attrs, "created_by_id") || Map.get(attrs, :created_by_id)
          AuditLogger.log_group_created(group.id, user_id, metadata)
        end

        {:ok, Repo.preload(group, [:venue, :users, :created_by])}

      error ->
        error
    end
  end

  @doc """
  Creates a group with the creator automatically added as an admin member.

  This is the recommended way to create groups as it ensures proper
  ownership setup and membership initialization. The operation is
  performed in a database transaction to ensure consistency.

  ## Parameters

  * `group_attrs` - Map of group attributes
  * `user` - User struct of the group creator
  * `metadata` - Optional audit metadata for logging

  ## Returns

  * `{:ok, %Group{}}` - Successfully created group with creator as admin
  * `{:error, %Ecto.Changeset{}}` - Validation or database errors

  ## Examples

      iex> user = %User{id: 123}
      iex> create_group_with_creator(%{
      ...>   name: "Local Hikers",
      ...>   slug: "local-hikers",
      ...>   description: "Weekend hiking group"
      ...> }, user)
      {:ok, %Group{name: "Local Hikers", created_by_id: 123}}

      # With audit metadata
      iex> create_group_with_creator(%{name: "Book Club"}, user, %{
      ...>   ip_address: "10.0.0.1",
      ...>   user_agent: "Mozilla/5.0..."
      ...> })
      {:ok, %Group{}}

      # Invalid group data rolls back the entire transaction
      iex> create_group_with_creator(%{name: ""}, user)
      {:error, %Ecto.Changeset{}}

  """
  def create_group_with_creator(group_attrs, %User{} = user, metadata \\ %{}) do
    group_attrs = Map.put(group_attrs, "created_by_id", user.id)

    Repo.transaction(fn ->
      with {:ok, group} <- create_group(group_attrs, metadata),
           {:ok, _} <- add_user_to_group(group, user, "admin", user, metadata) do
        Repo.preload(group, [:venue, :users, :created_by])
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a group.

  ## Examples

      iex> update_group(group, %{field: new_value})
      {:ok, %Group{}}

      iex> update_group(group, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_group(%Group{} = group, attrs, acting_user_id \\ nil, metadata \\ %{}) do
    changeset = Group.changeset(group, attrs)

    changeset
    |> Repo.update()
    |> case do
      {:ok, updated_group} ->
        # Log group update with changes
        if acting_user_id do
          changes = changeset.changes
          AuditLogger.log_group_updated(updated_group.id, acting_user_id, changes, metadata)
        end

        {:ok, Repo.preload(updated_group, [:venue, :users, :created_by])}

      error ->
        error
    end
  end

  @doc """
  Deletes a group.

  ## Examples

      iex> delete_group(group)
      {:ok, %Group{}}

      iex> delete_group(group)
      {:error, %Ecto.Changeset{}}

  """
  def delete_group(%Group{} = group, acting_user_id \\ nil, metadata \\ %{}) do
    result = Repo.delete(group)

    # Log group deletion
    case result do
      {:ok, deleted_group} ->
        if acting_user_id do
          AuditLogger.log_group_deleted(deleted_group.id, acting_user_id, metadata)
        end

        result

      _ ->
        result
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking group changes.

  ## Examples

      iex> change_group(group)
      %Ecto.Changeset{data: %Group{}}

  """
  def change_group(%Group{} = group, attrs \\ %{}) do
    Group.changeset(group, attrs)
  end

  @doc """
  Adds a user to a group with role assignment and audit logging.

  Prevents duplicate memberships and logs the addition with the acting user
  and optional metadata. All membership additions should specify the role
  and acting user for proper audit trails.

  ## Parameters

  * `group` - Group struct to add member to
  * `user` - User struct of the new member
  * `role` - Role to assign ("admin" or "member", defaults to "member")
  * `acting_user` - User struct performing the action (for audit logging)
  * `metadata` - Optional audit metadata (IP, context, etc.)

  ## Returns

  * `{:ok, %GroupUser{}}` - Successfully added member
  * `{:error, :already_member}` - User is already a group member
  * `{:error, %Ecto.Changeset{}}` - Validation or database errors

  ## Examples

      iex> group = %Group{id: 1}
      iex> new_member = %User{id: 456}
      iex> admin_user = %User{id: 123}
      iex> add_user_to_group(group, new_member, "member", admin_user)
      {:ok, %GroupUser{role: "member"}}

      # Adding an admin with audit metadata
      iex> add_user_to_group(group, new_member, "admin", admin_user, %{
      ...>   ip_address: "192.168.1.100",
      ...>   reason: "promoted for event planning"
      ...> })
      {:ok, %GroupUser{role: "admin"}}

      # Duplicate membership prevention
      iex> add_user_to_group(group, existing_member)
      {:error, :already_member}

  """
  def add_user_to_group(
        %Group{} = group,
        %User{} = user,
        role \\ "member",
        acting_user \\ nil,
        metadata \\ %{}
      ) do
    # Check if user is already a member
    case user_in_group?(group, user) do
      true ->
        {:error, :already_member}

      false ->
        # Special case: group owner can always be added regardless of privacy settings
        if group.created_by_id == user.id do
          perform_add_user_to_group(group, user, role, acting_user, metadata)
        else
          # Check if this is via a join request workflow or direct invitation
          case can_join_group?(group, user) do
            {:ok, :immediate} ->
              # Can join immediately (open group)
              perform_add_user_to_group(group, user, role, acting_user, metadata)

            {:ok, :request_required} ->
              # Need to create join request instead of adding directly
              if acting_user && can_manage?(group, acting_user) do
                # Admin is inviting them directly, bypass request system
                perform_add_user_to_group(group, user, role, acting_user, metadata)
              else
                # User is trying to join request-based group, create join request
                create_join_request(%{
                  group_id: group.id,
                  user_id: user.id,
                  message: Map.get(metadata, :message)
                })
              end

            {:error, :invite_only} ->
              # Only admins can add users to invite-only groups
              if acting_user && can_manage?(group, acting_user) do
                perform_add_user_to_group(group, user, role, acting_user, metadata)
              else
                {:error, :invite_only}
              end

            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  end

  # Private function to actually add user to group
  defp perform_add_user_to_group(group, user, role, acting_user, metadata) do
    attrs = %{
      group_id: group.id,
      user_id: user.id,
      role: role || "member"
    }

    changeset = GroupUser.changeset(%GroupUser{}, attrs)

    result =
      Repo.insert(changeset,
        on_conflict: :nothing,
        conflict_target: [:group_id, :user_id],
        returning: true
      )
      |> case do
        {:ok, %GroupUser{id: nil}} -> {:error, :already_member}
        other -> other
      end

    # Log membership addition
    case result do
      {:ok, _group_user} ->
        if acting_user do
          AuditLogger.log_member_added(group.id, user.id, acting_user.id, role, metadata)
        end

        result

      _ ->
        result
    end
  end

  @doc """
  Removes a user from a group.

  ## Examples

      iex> remove_user_from_group(group, user)
      {:ok, %GroupUser{}}

      iex> remove_user_from_group(group, user)
      {:error, :not_found}

  """
  def remove_user_from_group(
        %Group{} = group,
        %User{} = user,
        acting_user \\ nil,
        reason \\ nil,
        metadata \\ %{}
      ) do
    case Repo.get_by(GroupUser, group_id: group.id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      group_user ->
        # If we have deletion metadata, update the record with audit info
        updated_attrs = %{}

        updated_attrs =
          if reason, do: Map.put(updated_attrs, :deletion_reason, reason), else: updated_attrs

        updated_attrs =
          if acting_user,
            do: Map.put(updated_attrs, :deleted_by_user_id, acting_user.id),
            else: updated_attrs

        # Update with deletion metadata if provided
        group_user =
          if map_size(updated_attrs) > 0 do
            {:ok, updated} =
              group_user
              |> GroupUser.changeset(updated_attrs)
              |> Repo.update()

            updated
          else
            group_user
          end

        result = Repo.delete(group_user)

        # Log membership removal
        case result do
          {:ok, _deleted_group_user} ->
            if acting_user do
              AuditLogger.log_member_removed(group.id, user.id, acting_user.id, reason, metadata)
            end

            result

          _ ->
            result
        end
    end
  end

  @doc """
  Checks if a user is a member of a group.

  This function respects soft delete semantics and only returns true
  for active (non-deleted) memberships.

  ## Parameters

  * `group` - Group struct to check membership in
  * `user` - User struct to check membership for

  ## Returns

  * `true` - User is an active member of the group
  * `false` - User is not a member or membership is soft-deleted

  ## Examples

      iex> group = %Group{id: 1}
      iex> member = %User{id: 123}
      iex> non_member = %User{id: 456}
      iex> user_in_group?(group, member)
      true
      
      iex> user_in_group?(group, non_member)
      false

  """
  def user_in_group?(%Group{} = group, %User{} = user) do
    Repo.exists?(
      from(gu in GroupUser,
        where: gu.group_id == ^group.id and gu.user_id == ^user.id
      )
    )
  end

  @doc """
  Checks if a user is a member of a group using IDs.

  This function provides ID-based membership checking for cases where
  you don't have the full structs available. Supports both string and
  integer IDs for flexibility in different contexts (web forms, APIs, etc.).

  ## Parameters

  * `group_id` - Group ID (integer or string)
  * `user_id` - User ID (integer)

  ## Returns

  * `true` - User is an active member of the group
  * `false` - User is not a member, IDs are invalid, or membership is soft-deleted

  ## Examples

      iex> is_member?(1, 123)
      true
      
      iex> is_member?("1", 123)  # String group_id from web form
      true
      
      iex> is_member?(1, 999)    # Non-existent user
      false
      
      iex> is_member?("invalid", 123)  # Invalid ID format
      false

  """
  def is_member?(group_id, user_id) when is_binary(group_id) do
    case Integer.parse(group_id) do
      {id, _} -> is_member?(id, user_id)
      :error -> false
    end
  end

  def is_member?(group_id, user_id) when is_integer(group_id) and is_integer(user_id) do
    Repo.exists?(
      from(gu in GroupUser,
        where: gu.group_id == ^group_id and gu.user_id == ^user_id
      )
    )
  end

  def is_member?(_, _), do: false

  @doc """
  Checks if a user is an admin of a group.

  ## Examples

      iex> is_admin?(group, user)
      true

      iex> is_admin?(group, user)
      false

  """
  def is_admin?(%Group{} = group, %User{} = user) do
    query =
      from(gu in GroupUser,
        where: gu.group_id == ^group.id and gu.user_id == ^user.id and gu.role == "admin"
      )

    Repo.exists?(query)
  end

  def is_admin?(group_id, user_id) when is_binary(group_id) do
    case Integer.parse(group_id) do
      {id, _} -> is_admin?(id, user_id)
      :error -> false
    end
  end

  def is_admin?(group_id, user_id) when is_integer(group_id) and is_integer(user_id) do
    query =
      from(gu in GroupUser,
        where: gu.group_id == ^group_id and gu.user_id == ^user_id and gu.role == "admin"
      )

    Repo.exists?(query)
  end

  def is_admin?(_, _), do: false

  @doc """
  Checks if a user can manage a group (is admin or owner).

  This function implements the authorization logic for group management
  operations. Users can manage a group if they are either:
  1. The group creator/owner (created_by_id matches user.id)
  2. An admin member of the group

  Group owners always have management rights regardless of their role status.

  ## Parameters

  * `group` - Group struct to check management rights for
  * `user` - User struct to check permissions for

  ## Returns

  * `true` - User can manage the group (owner or admin)
  * `false` - User cannot manage the group

  ## Examples

      iex> owner = %User{id: 123}
      iex> group = %Group{id: 1, created_by_id: 123}
      iex> can_manage?(group, owner)
      true   # Owner can always manage

      iex> admin = %User{id: 456}  # Admin member but not owner
      iex> can_manage?(group, admin)
      true   # If admin role in group_users table

      iex> regular_member = %User{id: 789}  # Regular member
      iex> can_manage?(group, regular_member)
      false  # Cannot manage

      iex> non_member = %User{id: 999}
      iex> can_manage?(group, non_member)
      false  # Not even a member

  """
  def can_manage?(%Group{} = group, %User{} = user) do
    # Owner can always manage
    if group.created_by_id == user.id do
      true
    else
      # Check if user is admin
      is_admin?(group, user)
    end
  end

  @doc """
  Checks if a user can discover a group (see it in listings).

  ## Discovery Rules
  - Public groups: Visible to all users
  - Unlisted groups: Only visible via direct link (not in discovery)
  - Private groups: Only visible to current members

  ## Examples

      iex> public_group = %Group{visibility: "public"}
      iex> can_discover_group?(public_group, user)
      true
      
      iex> private_group = %Group{visibility: "private"}
      iex> can_discover_group?(private_group, non_member)
      false
  """
  def can_discover_group?(%Group{} = group, %User{} = user) do
    case group.visibility do
      "public" -> true
      # Not discoverable in listings
      "unlisted" -> false
      "private" -> user_in_group?(group, user)
      # Guard against unexpected or nil values
      _ -> false
    end
  end

  @doc """
  Checks if a user can view a group's details page.

  ## Access Rules
  - Public groups: Anyone can view
  - Unlisted groups: Anyone with link can view
  - Private groups: Only members can view

  ## Examples

      iex> unlisted_group = %Group{visibility: "unlisted"}
      iex> can_view_group?(unlisted_group, anyone)
      true
      
      iex> private_group = %Group{visibility: "private"}
      iex> can_view_group?(private_group, non_member)
      false
  """
  def can_view_group?(%Group{} = group, %User{} = user) do
    case group.visibility do
      "public" -> true
      "unlisted" -> true
      "private" -> user_in_group?(group, user)
      # Guard against unexpected or nil values
      _ -> false
    end
  end

  @doc """
  Checks if a user can join a group directly.

  ## Join Rules
  - Open: Anyone who can view can join immediately
  - Request: Users can request to join (needs approval)
  - Invite Only: Only admins can invite users

  ## Examples

      iex> open_group = %Group{join_policy: "open", visibility: "public"}
      iex> can_join_group?(open_group, user)
      {:ok, :immediate}
      
      iex> request_group = %Group{join_policy: "request"}
      iex> can_join_group?(request_group, user)
      {:ok, :request_required}
  """
  def can_join_group?(%Group{} = group, %User{} = user) do
    # Can't join if already a member
    if user_in_group?(group, user) do
      {:error, :already_member}
    else
      # Check if user can even see the group
      if can_view_group?(group, user) do
        case group.join_policy do
          "open" -> {:ok, :immediate}
          "request" -> {:ok, :request_required}
          "invite_only" -> {:error, :invite_only}
          # Guard against unexpected or nil values
          _ -> {:error, :invalid_join_policy}
        end
      else
        {:error, :cannot_view}
      end
    end
  end

  @doc """
  Gets a group by slug only if user can access it.

  Returns nil if group doesn't exist or user cannot view it.
  """
  def get_group_by_slug_if_accessible(slug, %User{} = user) when is_binary(slug) do
    case get_group_by_slug(slug) do
      nil ->
        nil

      group ->
        if can_view_group?(group, user) do
          group
        else
          nil
        end
    end
  end

  @doc """
  Updates a user's role in a group.

  ## Examples

      iex> update_member_role(group, user, "admin", acting_user)
      {:ok, %GroupUser{}}

      iex> update_member_role(group, user, "invalid_role", acting_user)
      {:error, :invalid_role}

  """
  def update_member_role(
        %Group{} = group,
        %User{} = user,
        new_role,
        acting_user \\ nil,
        metadata \\ %{}
      ) do
    valid_roles = ["admin", "member"]

    if new_role not in valid_roles do
      {:error, :invalid_role}
    else
      case Repo.get_by(GroupUser, group_id: group.id, user_id: user.id) do
        nil ->
          {:error, :not_member}

        group_user ->
          old_role = group_user.role

          result =
            group_user
            |> GroupUser.changeset(%{role: new_role})
            |> Repo.update()

          # Log role change
          case result do
            {:ok, _updated_group_user} ->
              if acting_user do
                AuditLogger.log_member_role_changed(
                  group.id,
                  user.id,
                  acting_user.id,
                  old_role,
                  new_role,
                  metadata
                )
              end

              result

            _ ->
              result
          end
      end
    end
  end

  @doc """
  Lists all members of a group.

  ## Examples

      iex> list_group_members(group)
      [%User{}, ...]

  """
  def list_group_members(%Group{} = group) do
    query =
      from(u in User,
        join: gu in GroupUser,
        on: gu.user_id == u.id,
        where: gu.group_id == ^group.id,
        select: u
      )

    Repo.all(query)
  end

  @doc """
  Lists all members of a group with their roles.

  ## Examples

      iex> list_group_members_with_roles(group)
      [%{user: %User{}, role: "admin"}, ...]

  """
  def list_group_members_with_roles(%Group{} = group) do
    query =
      from(u in User,
        join: gu in GroupUser,
        on: gu.user_id == u.id,
        where: gu.group_id == ^group.id,
        select: %{user: u, role: gu.role, joined_at: gu.inserted_at}
      )

    Repo.all(query)
  end

  @doc """
  Lists all events for a group.

  ## Examples

      iex> list_group_events(group)
      [%Event{}, ...]

  """
  def list_group_events(%Group{} = group) do
    EventasaurusApp.Events.Event
    |> where(group_id: ^group.id)
    |> Repo.all()
    |> Repo.preload([:venue, :users])
  end

  @doc """
  Counts the number of events in a group.

  ## Examples

      iex> count_group_events(group)
      5

  """
  def count_group_events(%Group{} = group) do
    EventasaurusApp.Events.Event
    |> where(group_id: ^group.id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Syncs event participants to group members.

  This function finds all users who have purchased tickets for events in the group
  and automatically adds them as members if they're not already members.

  ## Parameters

  * `group` - Group struct to sync members for
  * `acting_user` - User performing the sync (for audit logging)
  * `metadata` - Optional metadata for audit logging

  ## Returns

  * `{:ok, %{added: count, already_members: count}}` - Success with counts
  * `{:error, reason}` - If sync fails

  ## Examples

      iex> sync_participants_to_group(group, admin_user)
      {:ok, %{added: 5, already_members: 3}}
      
  """
  def sync_participants_to_group(%Group{} = group, acting_user \\ nil, metadata \\ %{}) do
    Repo.transaction(fn ->
      # Get all events in the group
      event_ids =
        from(e in EventasaurusApp.Events.Event,
          where: e.group_id == ^group.id,
          select: e.id
        )
        |> Repo.all()

      if Enum.empty?(event_ids) do
        %{added: 0, already_members: 0}
      else
        # Get all unique users who are participants in these events
        participant_users =
          from(ep in EventasaurusApp.Events.EventParticipant,
            where: ep.event_id in ^event_ids,
            where: is_nil(ep.deleted_at),
            join: u in User,
            on: ep.user_id == u.id,
            distinct: true,
            select: u
          )
          |> Repo.all()

        # Process each user
        results =
          Enum.reduce(participant_users, %{added: 0, already_members: 0}, fn user, acc ->
            case add_user_to_group(group, user, "member", acting_user, metadata) do
              {:ok, _} ->
                %{acc | added: acc.added + 1}

              {:error, :already_member} ->
                %{acc | already_members: acc.already_members + 1}

              {:error, reason} ->
                Logger.error(
                  "Failed to add user #{user.id} to group #{group.id}: #{inspect(reason)}"
                )

                acc
            end
          end)

        # Log the sync operation
        if acting_user do
          AuditLogger.log_group_sync(group.id, acting_user.id, results, metadata)
        end

        results
      end
    end)
  end

  @doc """
  Syncs participants from a specific event to group members.

  This is useful when a single event is added to a group and you want to
  sync only that event's participants rather than all events.

  ## Parameters

  * `group` - Group struct to sync members to
  * `event` - Event struct whose participants to sync
  * `acting_user` - User performing the sync
  * `metadata` - Optional metadata for audit logging

  ## Examples

      iex> sync_event_participants_to_group(group, event, admin_user)
      {:ok, %{added: 3, already_members: 2}}
      
  """
  def sync_event_participants_to_group(
        %Group{} = group,
        %EventasaurusApp.Events.Event{} = event,
        acting_user \\ nil,
        metadata \\ %{}
      ) do
    if event.group_id != group.id do
      {:error, :event_not_in_group}
    else
      Repo.transaction(fn ->
        # Get all users who are participants of this event
        participant_users =
          from(ep in EventasaurusApp.Events.EventParticipant,
            where: ep.event_id == ^event.id,
            where: is_nil(ep.deleted_at),
            join: u in User,
            on: ep.user_id == u.id,
            distinct: true,
            select: u
          )
          |> Repo.all()

        # Process each user
        results =
          Enum.reduce(participant_users, %{added: 0, already_members: 0}, fn user, acc ->
            case add_user_to_group(group, user, "member", acting_user, metadata) do
              {:ok, _} ->
                %{acc | added: acc.added + 1}

              {:error, :already_member} ->
                %{acc | already_members: acc.already_members + 1}

              {:error, reason} ->
                Logger.error(
                  "Failed to add user #{user.id} to group #{group.id}: #{inspect(reason)}"
                )

                acc
            end
          end)

        # Log the sync operation
        if acting_user do
          event_metadata = Map.merge(metadata, %{event_id: event.id, event_title: event.title})
          AuditLogger.log_event_sync(group.id, event.id, acting_user.id, results, event_metadata)
        end

        results
      end)
    end
  end

  @doc """
  Syncs participants from a specific event to group members by event ID.

  This is a convenience function that fetches the event and group, then
  delegates to the main sync function. Used by async triggers.

  ## Parameters

  * `event_id` - ID of the event whose participants to sync

  ## Returns

  * `{:ok, %{added: count, already_members: count}}` - Success with counts
  * `{:error, reason}` - If sync fails

  """
  def sync_event_participants_to_group(event_id) do
    alias EventasaurusApp.Events

    with event when not is_nil(event) <- Events.get_event(event_id),
         group when not is_nil(group) <- Repo.get(Group, event.group_id) do
      sync_event_participants_to_group(group, event)
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Lists event participants who are not yet group members.

  Returns users who have attended events in the group but are not yet members.
  This is useful for discovering potential members from past event attendees.

  ## Parameters

  * `group` - Group struct
  * `opts` - Options including:
    * `:limit` - Maximum number of results (default: 50)
    * `:order_by` - Order results by :event_count or :recent_event (default: :event_count)

  ## Returns

  List of maps with user info and participation stats:
  * `user` - User struct  
  * `event_count` - Number of events attended in this group
  * `most_recent_event` - Title of their most recent event
  * `most_recent_date` - Date of their most recent event

  ## Examples

      iex> list_event_participants_not_in_group(group, limit: 20)
      [%{user: %User{}, event_count: 5, most_recent_event: "Movie Night", ...}, ...]
      
  """
  def list_event_participants_not_in_group(%Group{} = group, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    order_by = Keyword.get(opts, :order_by, :event_count)

    # Get existing member IDs
    existing_member_ids =
      from(gu in GroupUser,
        where: gu.group_id == ^group.id,
        select: gu.user_id
      )
      |> Repo.all()

    # Query for potential members
    base_query =
      from(ep in EventasaurusApp.Events.EventParticipant,
        join: e in EventasaurusApp.Events.Event,
        on: ep.event_id == e.id,
        join: u in User,
        on: ep.user_id == u.id,
        where: e.group_id == ^group.id and is_nil(ep.deleted_at),
        where: ep.user_id not in ^existing_member_ids,
        group_by: [u.id, u.name, u.email],
        select: %{
          user: u,
          event_count: count(e.id, :distinct),
          most_recent_date: max(ep.inserted_at),
          # We'll need a subquery for the most recent event title
          user_id: u.id
        }
      )

    # Apply ordering
    query =
      case order_by do
        :recent_event -> order_by(base_query, [ep, e, u], desc: max(ep.inserted_at))
        _ -> order_by(base_query, [ep, e, u], desc: count(e.id, :distinct))
      end

    query = limit(query, ^limit)

    potential_members = Repo.all(query)

    # Get most recent event titles for each user
    user_ids = Enum.map(potential_members, & &1.user_id)

    recent_events =
      if Enum.empty?(user_ids) do
        %{}
      else
        from(ep in EventasaurusApp.Events.EventParticipant,
          join: e in EventasaurusApp.Events.Event,
          on: ep.event_id == e.id,
          where: ep.user_id in ^user_ids and e.group_id == ^group.id and is_nil(ep.deleted_at),
          distinct: [ep.user_id],
          order_by: [asc: ep.user_id, desc: ep.inserted_at],
          select: {ep.user_id, e.title}
        )
        |> Repo.all()
        |> Map.new()
      end

    # Combine results
    Enum.map(potential_members, fn member ->
      Map.merge(member, %{
        most_recent_event: Map.get(recent_events, member.user_id, "Unknown")
      })
      |> Map.delete(:user_id)
    end)
  end

  @doc """
  Lists potential group members by searching all users not in the group.

  This is used for the add member modal to search for any user to add to the group.

  ## Parameters

  * `group` - Group struct
  * `opts` - Options including:
    * `:search` - Search term for user name/email
    * `:limit` - Maximum number of results (default: 10)

  ## Returns

  List of User structs that are not currently members

  """
  def list_potential_group_members(%Group{} = group, opts \\ []) do
    search = Keyword.get(opts, :search, "")
    limit = Keyword.get(opts, :limit, 10)

    # Get existing member IDs
    existing_member_ids =
      from(gu in GroupUser,
        where: gu.group_id == ^group.id,
        select: gu.user_id
      )
      |> Repo.all()

    # Query for non-member users
    query =
      from(u in User,
        where: u.id not in ^existing_member_ids
      )

    # Apply search if provided
    query =
      if search && String.trim(search) != "" do
        search_term = "%#{search}%"
        where(query, [u], ilike(u.name, ^search_term) or ilike(u.email, ^search_term))
      else
        query
      end

    query
    |> order_by([u], asc: u.name)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Counts the number of members in a group.

  ## Examples

      iex> count_group_members(group)
      42
      
  """
  def count_group_members(%Group{} = group) do
    from(gu in GroupUser,
      where: gu.group_id == ^group.id,
      select: count(gu.id)
    )
    |> Repo.one()
  end

  @doc """
  Lists group members with pagination and search.

  ## Parameters

  * `group` - Group struct
  * `opts` - Options including:
    * `:page` - Page number (default: 1)
    * `:per_page` - Items per page (default: 20)
    * `:search` - Search term for name/email
    * `:role` - Filter by role ("admin" or "member")
    * `:order_by` - Order by :joined_at or :name (default: :joined_at)

  ## Returns

  Map with:
  * `:entries` - List of member maps with user and membership info
  * `:page` - Current page
  * `:per_page` - Items per page
  * `:total` - Total number of members
  * `:total_pages` - Total number of pages

  """
  def list_group_members_paginated(%Group{} = group, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    search = Keyword.get(opts, :search, "")
    role_filter = Keyword.get(opts, :role)
    order_by = Keyword.get(opts, :order_by, :joined_at)

    offset = (page - 1) * per_page

    # Base query
    base_query =
      from(gu in GroupUser,
        join: u in User,
        on: gu.user_id == u.id,
        where: gu.group_id == ^group.id
      )

    # Apply role filter
    query =
      if role_filter do
        where(base_query, [gu, u], gu.role == ^role_filter)
      else
        base_query
      end

    # Apply search
    query =
      if search && String.trim(search) != "" do
        search_term = "%#{search}%"
        where(query, [gu, u], ilike(u.name, ^search_term) or ilike(u.email, ^search_term))
      else
        query
      end

    # Get total count
    total = Repo.aggregate(query, :count, :id)

    # Apply ordering
    query =
      case order_by do
        :name -> order_by(query, [gu, u], asc: u.name)
        _ -> order_by(query, [gu, u], desc: gu.inserted_at)
      end

    # Apply pagination and select
    members =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> select([gu, u], %{
        user: u,
        role: gu.role,
        joined_at: gu.inserted_at
      })
      |> Repo.all()

    %{
      entries: members,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: ceil(total / per_page)
    }
  end

  ## Group Join Requests

  @doc """
  Creates a new group join request.

  ## Parameters

  * `attrs` - Map with group_id, user_id, and optional message

  ## Returns

  * `{:ok, %GroupJoinRequest{}}` - Successfully created request
  * `{:error, %Ecto.Changeset{}}` - Validation errors

  ## Examples

      iex> create_join_request(%{group_id: 1, user_id: 2, message: "I'd love to join!"})
      {:ok, %GroupJoinRequest{}}
      
      iex> create_join_request(%{group_id: 1, user_id: 2})  # Duplicate request
      {:error, %Ecto.Changeset{}}
  """
  def create_join_request(attrs \\ %{}) do
    group_id = Map.get(attrs, :group_id) || Map.get(attrs, "group_id")
    user_id = Map.get(attrs, :user_id) || Map.get(attrs, "user_id")

    with %Group{} = group <- Repo.get(Group, group_id) || {:error, :group_not_found},
         %User{} = user <- Repo.get(User, user_id) || {:error, :user_not_found},
         false <- user_in_group?(group, user) || {:error, :already_member},
         {:ok, :request_required} <- can_join_group?(group, user) do
      %GroupJoinRequest{}
      |> GroupJoinRequest.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, request} ->
          {:ok, Repo.preload(request, [:group, :user, :reviewed_by])}

        error ->
          error
      end
    else
      {:error, _} = e -> e
      true -> {:error, :already_member}
      {:ok, :immediate} -> {:error, :not_required}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a join request by ID.

  ## Examples

      iex> get_join_request(123)
      %GroupJoinRequest{}
      
      iex> get_join_request(999)
      nil
  """
  def get_join_request(id) do
    GroupJoinRequest
    |> Repo.get(id)
    |> case do
      nil -> nil
      request -> Repo.preload(request, [:group, :user, :reviewed_by])
    end
  end

  @doc """
  Gets a join request by ID with error if not found.

  ## Examples

      iex> get_join_request!(123)
      %GroupJoinRequest{}
      
      iex> get_join_request!(999)
      ** (Ecto.NoResultsError)
  """
  def get_join_request!(id) do
    GroupJoinRequest
    |> Repo.get!(id)
    |> Repo.preload([:group, :user, :reviewed_by])
  end

  @doc """
  Lists pending join requests for a group.

  ## Examples

      iex> list_pending_join_requests(group)
      [%GroupJoinRequest{status: "pending"}, ...]
  """
  def list_pending_join_requests(%Group{} = group) do
    from(r in GroupJoinRequest,
      where: r.group_id == ^group.id and r.status == "pending",
      order_by: [desc: r.inserted_at],
      preload: [:user, :group]
    )
    |> Repo.all()
  end

  @doc """
  Lists all join requests for a group with optional status filter.

  ## Parameters

  * `group` - Group struct
  * `opts` - Options including:
    * `:status` - Filter by status ("pending", "approved", "denied")
    * `:limit` - Maximum results (default: 50)

  ## Examples

      iex> list_join_requests(group)
      [%GroupJoinRequest{}, ...]
      
      iex> list_join_requests(group, status: "approved", limit: 10)
      [%GroupJoinRequest{status: "approved"}, ...]
  """
  def list_join_requests(%Group{} = group, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(r in GroupJoinRequest,
        where: r.group_id == ^group.id,
        order_by: [desc: r.inserted_at],
        preload: [:user, :group, :reviewed_by],
        limit: ^limit
      )

    query =
      if status do
        where(query, [r], r.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Lists join requests for a user with optional status filter.

  ## Examples

      iex> list_user_join_requests(user)
      [%GroupJoinRequest{}, ...]
  """
  def list_user_join_requests(%User{} = user, opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(r in GroupJoinRequest,
        where: r.user_id == ^user.id,
        order_by: [desc: r.inserted_at],
        preload: [:user, :group, :reviewed_by],
        limit: ^limit
      )

    query =
      if status do
        where(query, [r], r.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Approves a join request and adds the user to the group.

  ## Parameters

  * `request` - GroupJoinRequest struct
  * `reviewer` - User who is approving the request
  * `metadata` - Optional audit metadata

  ## Returns

  * `{:ok, %{request: %GroupJoinRequest{}, membership: %GroupUser{}}}` - Success
  * `{:error, %Ecto.Changeset{}}` - Validation errors
  * `{:error, atom}` - Other errors

  ## Examples

      iex> approve_join_request(request, admin_user)
      {:ok, %{request: %GroupJoinRequest{status: "approved"}, membership: %GroupUser{}}}
  """
  def approve_join_request(%GroupJoinRequest{} = request, %User{} = reviewer, metadata \\ %{}) do
    request = Repo.preload(request, [:group, :user])

    cond do
      request.status != "pending" ->
        {:error, :already_processed}

      not can_manage?(request.group, reviewer) ->
        {:error, :forbidden}

      true ->
        Repo.transaction(fn ->
          # Update request status
          update_attrs = %{
            status: "approved",
            reviewed_by_id: reviewer.id,
            reviewed_at: DateTime.utc_now()
          }

          case update_join_request_status(request, update_attrs) do
            {:ok, updated_request} ->
              case perform_add_user_to_group(
                     updated_request.group,
                     updated_request.user,
                     "member",
                     reviewer,
                     metadata
                   ) do
                {:ok, membership} ->
                  # Log the approval
                  AuditLogger.log_join_request_approved(
                    updated_request.group.id,
                    updated_request.user.id,
                    reviewer.id,
                    metadata
                  )

                  %{request: updated_request, membership: membership}

                {:error, :already_member} ->
                  # User is already a member, just update the request status
                  %{request: updated_request, membership: nil}

                {:error, %Ecto.Changeset{} = _cs} ->
                  # Treat unique constraint like already_member
                  %{request: updated_request, membership: nil}

                {:error, reason} ->
                  Repo.rollback(reason)
              end

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)
    end
  end

  @doc """
  Denies a join request.

  ## Parameters

  * `request` - GroupJoinRequest struct
  * `reviewer` - User who is denying the request
  * `metadata` - Optional audit metadata

  ## Examples

      iex> deny_join_request(request, admin_user)
      {:ok, %GroupJoinRequest{status: "denied"}}
  """
  def deny_join_request(%GroupJoinRequest{} = request, %User{} = reviewer, metadata \\ %{}) do
    request = Repo.preload(request, [:group, :user])

    cond do
      request.status != "pending" ->
        {:error, :already_processed}

      not can_manage?(request.group, reviewer) ->
        {:error, :forbidden}

      true ->
        update_attrs = %{
          status: "denied",
          reviewed_by_id: reviewer.id,
          reviewed_at: DateTime.utc_now()
        }

        case update_join_request_status(request, update_attrs) do
          {:ok, updated_request} ->
            # Log the denial
            AuditLogger.log_join_request_denied(
              updated_request.group.id,
              updated_request.user.id,
              reviewer.id,
              metadata
            )

            {:ok, updated_request}

          error ->
            error
        end
    end
  end

  @doc """
  Cancels a pending join request (by the requester).

  ## Examples

      iex> cancel_join_request(request)
      {:ok, %GroupJoinRequest{status: "cancelled"}}
  """
  def cancel_join_request(%GroupJoinRequest{} = request, %User{} = acting_user) do
    request = Repo.preload(request, [:group, :user])

    cond do
      request.status != "pending" ->
        {:error, :already_processed}

      acting_user.id != request.user_id and not can_manage?(request.group, acting_user) ->
        {:error, :forbidden}

      true ->
        update_attrs = %{status: "cancelled"}
        update_join_request_status(request, update_attrs)
    end
  end

  @doc """
  Checks if a user has a pending join request for a group.

  ## Examples

      iex> has_pending_join_request?(group, user)
      true
      
      iex> has_pending_join_request?(group, user)
      false
  """
  def has_pending_join_request?(%Group{} = group, %User{} = user) do
    Repo.exists?(
      from(r in GroupJoinRequest,
        where: r.group_id == ^group.id and r.user_id == ^user.id and r.status == "pending"
      )
    )
  end

  @doc """
  Gets a pending join request for a user and group.

  Returns nil if no pending request exists.

  ## Examples

      iex> get_pending_join_request(group, user)
      %GroupJoinRequest{}
      
      iex> get_pending_join_request(group, user)
      nil
  """
  def get_pending_join_request(%Group{} = group, %User{} = user) do
    from(r in GroupJoinRequest,
      where: r.group_id == ^group.id and r.user_id == ^user.id and r.status == "pending",
      preload: [:group, :user, :reviewed_by]
    )
    |> Repo.one()
  end

  @doc """
  Counts pending join requests for a group.

  ## Examples

      iex> count_pending_join_requests(group)
      5
  """
  def count_pending_join_requests(%Group{} = group) do
    from(r in GroupJoinRequest,
      where: r.group_id == ^group.id and r.status == "pending",
      select: count(r.id)
    )
    |> Repo.one()
  end

  # Private function to update join request status
  defp update_join_request_status(%GroupJoinRequest{} = request, attrs) do
    request
    |> GroupJoinRequest.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_request} ->
        {:ok, Repo.preload(updated_request, [:group, :user, :reviewed_by])}

      error ->
        error
    end
  end
end
