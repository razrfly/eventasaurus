defmodule EventasaurusApp.Follows do
  @moduledoc """
  Context for managing user follows of performers and venues.

  This module provides a complete API for the social following feature,
  allowing users to follow and unfollow performers and venues to personalize
  their experience and stay updated on content.

  ## Features

  - Follow/unfollow performers and venues
  - Check following status
  - List followed entities with pagination
  - Count followers for performers and venues
  - Rate limiting to prevent spam (max 60 follow actions per minute)
  - Telemetry events for analytics

  ## Examples

      # Follow a performer
      {:ok, follow} = Follows.follow_performer(user, performer)

      # Check if following
      true = Follows.following_performer?(user, performer)

      # Get follower count
      42 = Follows.count_performer_followers(performer)

      # List followed performers with pagination
      performers = Follows.list_followed_performers(user, limit: 10, offset: 0)

  ## Telemetry Events

  The following telemetry events are emitted:

  - `[:eventasaurus, :follows, :follow]` - When a user follows an entity
  - `[:eventasaurus, :follows, :unfollow]` - When a user unfollows an entity

  Each event includes metadata with `:entity_type` (`:performer` or `:venue`),
  `:user_id`, and `:entity_id`.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Follows.{UserPerformerFollow, UserVenueFollow}
  alias EventasaurusApp.Accounts.User
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusApp.Venues.Venue

  # Rate limiting: max 60 follow/unfollow actions per minute per user
  @rate_limit_window_ms 60_000
  @rate_limit_max_actions 60

  # =============================================================================
  # Performer Following
  # =============================================================================

  @doc """
  Follow a performer.

  Creates a follow relationship between the user and performer. If the user
  is already following the performer, returns an error changeset with a
  unique constraint violation.

  Rate limiting is applied to prevent spam - users are limited to
  #{@rate_limit_max_actions} follow/unfollow actions per minute.

  ## Parameters

  - `user` - The `%User{}` struct of the user who wants to follow
  - `performer` - The `%Performer{}` struct to follow

  ## Returns

  - `{:ok, %UserPerformerFollow{}}` - Successfully followed
  - `{:error, :rate_limited}` - Too many follow actions, try again later
  - `{:error, %Ecto.Changeset{}}` - Validation error (e.g., already following)

  ## Examples

      iex> Follows.follow_performer(user, performer)
      {:ok, %UserPerformerFollow{}}

      iex> Follows.follow_performer(user, already_followed_performer)
      {:error, %Ecto.Changeset{errors: [user_id: {"has already been taken", _}]}}
  """
  @spec follow_performer(User.t(), Performer.t()) ::
          {:ok, UserPerformerFollow.t()} | {:error, Ecto.Changeset.t()} | {:error, :rate_limited}
  def follow_performer(%User{id: user_id} = user, %Performer{id: performer_id} = performer) do
    with :ok <- check_rate_limit(user_id) do
      result =
        %UserPerformerFollow{}
        |> UserPerformerFollow.changeset(%{user_id: user_id, performer_id: performer_id})
        |> Repo.insert()

      case result do
        {:ok, follow} ->
          emit_telemetry(:follow, :performer, user, performer)
          {:ok, follow}

        error ->
          error
      end
    end
  end

  @doc """
  Unfollow a performer.

  Removes the follow relationship between the user and performer.

  Rate limiting is applied to prevent spam - users are limited to
  #{@rate_limit_max_actions} follow/unfollow actions per minute.

  ## Parameters

  - `user` - The `%User{}` struct of the user who wants to unfollow
  - `performer` - The `%Performer{}` struct to unfollow

  ## Returns

  - `{:ok, %UserPerformerFollow{}}` - Successfully unfollowed
  - `{:error, :not_found}` - User was not following this performer
  - `{:error, :rate_limited}` - Too many follow actions, try again later

  ## Examples

      iex> Follows.unfollow_performer(user, followed_performer)
      {:ok, %UserPerformerFollow{}}

      iex> Follows.unfollow_performer(user, not_followed_performer)
      {:error, :not_found}
  """
  @spec unfollow_performer(User.t(), Performer.t()) ::
          {:ok, UserPerformerFollow.t()} | {:error, :not_found} | {:error, :rate_limited}
  def unfollow_performer(%User{id: user_id} = user, %Performer{id: performer_id} = performer) do
    with :ok <- check_rate_limit(user_id) do
      case Repo.get_by(UserPerformerFollow, user_id: user_id, performer_id: performer_id) do
        nil ->
          {:error, :not_found}

        follow ->
          result = Repo.delete(follow)

          case result do
            {:ok, deleted_follow} ->
              emit_telemetry(:unfollow, :performer, user, performer)
              {:ok, deleted_follow}

            error ->
              error
          end
      end
    end
  end

  @doc """
  Check if a user is following a performer.

  This is a fast check that only queries for existence, not the full record.
  Returns `false` if `user` is `nil` (unauthenticated users).

  ## Parameters

  - `user` - The `%User{}` struct (or `nil` for unauthenticated)
  - `performer` - The `%Performer{}` struct to check

  ## Returns

  - `true` - User is following the performer
  - `false` - User is not following (or user is nil)

  ## Examples

      iex> Follows.following_performer?(user, followed_performer)
      true

      iex> Follows.following_performer?(nil, performer)
      false
  """
  @spec following_performer?(User.t() | nil, Performer.t()) :: boolean()
  def following_performer?(%User{id: user_id}, %Performer{id: performer_id}) do
    Repo.exists?(
      from(f in UserPerformerFollow,
        where: f.user_id == ^user_id and f.performer_id == ^performer_id
      )
    )
  end

  def following_performer?(nil, _performer), do: false

  @doc """
  List all performers a user is following.

  Returns performers ordered by follow date (most recent first) with
  pagination support.

  ## Parameters

  - `user` - The `%User{}` struct
  - `opts` - Keyword list of options:
    - `:limit` - Maximum number of results (default: 50, max: 100)
    - `:offset` - Number of results to skip (default: 0)

  ## Returns

  A list of `%Performer{}` structs.

  ## Examples

      iex> Follows.list_followed_performers(user)
      [%Performer{}, %Performer{}, ...]

      iex> Follows.list_followed_performers(user, limit: 10, offset: 20)
      [%Performer{}, ...]
  """
  @spec list_followed_performers(User.t(), keyword()) :: [Performer.t()]
  def list_followed_performers(%User{id: user_id}, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> min(100)
    offset = Keyword.get(opts, :offset, 0)

    from(f in UserPerformerFollow,
      where: f.user_id == ^user_id,
      join: p in assoc(f, :performer),
      order_by: [desc: f.inserted_at],
      limit: ^limit,
      offset: ^offset,
      select: p
    )
    |> Repo.all()
  end

  @doc """
  Count how many users are following a performer.

  This is an efficient count query that doesn't load follower records.

  ## Parameters

  - `performer` - The `%Performer{}` struct

  ## Returns

  A non-negative integer representing the follower count.

  ## Examples

      iex> Follows.count_performer_followers(popular_performer)
      1234

      iex> Follows.count_performer_followers(new_performer)
      0
  """
  @spec count_performer_followers(Performer.t()) :: non_neg_integer()
  def count_performer_followers(%Performer{id: performer_id}) do
    Repo.aggregate(
      from(f in UserPerformerFollow, where: f.performer_id == ^performer_id),
      :count
    )
  end

  # =============================================================================
  # Venue Following
  # =============================================================================

  @doc """
  Follow a venue.

  Creates a follow relationship between the user and venue. If the user
  is already following the venue, returns an error changeset with a
  unique constraint violation.

  Rate limiting is applied to prevent spam - users are limited to
  #{@rate_limit_max_actions} follow/unfollow actions per minute.

  ## Parameters

  - `user` - The `%User{}` struct of the user who wants to follow
  - `venue` - The `%Venue{}` struct to follow

  ## Returns

  - `{:ok, %UserVenueFollow{}}` - Successfully followed
  - `{:error, :rate_limited}` - Too many follow actions, try again later
  - `{:error, %Ecto.Changeset{}}` - Validation error (e.g., already following)

  ## Examples

      iex> Follows.follow_venue(user, venue)
      {:ok, %UserVenueFollow{}}

      iex> Follows.follow_venue(user, already_followed_venue)
      {:error, %Ecto.Changeset{errors: [user_id: {"has already been taken", _}]}}
  """
  @spec follow_venue(User.t(), Venue.t()) ::
          {:ok, UserVenueFollow.t()} | {:error, Ecto.Changeset.t()} | {:error, :rate_limited}
  def follow_venue(%User{id: user_id} = user, %Venue{id: venue_id} = venue) do
    with :ok <- check_rate_limit(user_id) do
      result =
        %UserVenueFollow{}
        |> UserVenueFollow.changeset(%{user_id: user_id, venue_id: venue_id})
        |> Repo.insert()

      case result do
        {:ok, follow} ->
          emit_telemetry(:follow, :venue, user, venue)
          {:ok, follow}

        error ->
          error
      end
    end
  end

  @doc """
  Unfollow a venue.

  Removes the follow relationship between the user and venue.

  Rate limiting is applied to prevent spam - users are limited to
  #{@rate_limit_max_actions} follow/unfollow actions per minute.

  ## Parameters

  - `user` - The `%User{}` struct of the user who wants to unfollow
  - `venue` - The `%Venue{}` struct to unfollow

  ## Returns

  - `{:ok, %UserVenueFollow{}}` - Successfully unfollowed
  - `{:error, :not_found}` - User was not following this venue
  - `{:error, :rate_limited}` - Too many follow actions, try again later

  ## Examples

      iex> Follows.unfollow_venue(user, followed_venue)
      {:ok, %UserVenueFollow{}}

      iex> Follows.unfollow_venue(user, not_followed_venue)
      {:error, :not_found}
  """
  @spec unfollow_venue(User.t(), Venue.t()) ::
          {:ok, UserVenueFollow.t()} | {:error, :not_found} | {:error, :rate_limited}
  def unfollow_venue(%User{id: user_id} = user, %Venue{id: venue_id} = venue) do
    with :ok <- check_rate_limit(user_id) do
      case Repo.get_by(UserVenueFollow, user_id: user_id, venue_id: venue_id) do
        nil ->
          {:error, :not_found}

        follow ->
          result = Repo.delete(follow)

          case result do
            {:ok, deleted_follow} ->
              emit_telemetry(:unfollow, :venue, user, venue)
              {:ok, deleted_follow}

            error ->
              error
          end
      end
    end
  end

  @doc """
  Check if a user is following a venue.

  This is a fast check that only queries for existence, not the full record.
  Returns `false` if `user` is `nil` (unauthenticated users).

  ## Parameters

  - `user` - The `%User{}` struct (or `nil` for unauthenticated)
  - `venue` - The `%Venue{}` struct to check

  ## Returns

  - `true` - User is following the venue
  - `false` - User is not following (or user is nil)

  ## Examples

      iex> Follows.following_venue?(user, followed_venue)
      true

      iex> Follows.following_venue?(nil, venue)
      false
  """
  @spec following_venue?(User.t() | nil, Venue.t()) :: boolean()
  def following_venue?(%User{id: user_id}, %Venue{id: venue_id}) do
    Repo.exists?(
      from(f in UserVenueFollow,
        where: f.user_id == ^user_id and f.venue_id == ^venue_id
      )
    )
  end

  def following_venue?(nil, _venue), do: false

  @doc """
  List all venues a user is following.

  Returns venues ordered by follow date (most recent first) with
  pagination support.

  ## Parameters

  - `user` - The `%User{}` struct
  - `opts` - Keyword list of options:
    - `:limit` - Maximum number of results (default: 50, max: 100)
    - `:offset` - Number of results to skip (default: 0)

  ## Returns

  A list of `%Venue{}` structs.

  ## Examples

      iex> Follows.list_followed_venues(user)
      [%Venue{}, %Venue{}, ...]

      iex> Follows.list_followed_venues(user, limit: 10, offset: 20)
      [%Venue{}, ...]
  """
  @spec list_followed_venues(User.t(), keyword()) :: [Venue.t()]
  def list_followed_venues(%User{id: user_id}, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> min(100)
    offset = Keyword.get(opts, :offset, 0)

    from(f in UserVenueFollow,
      where: f.user_id == ^user_id,
      join: v in assoc(f, :venue),
      order_by: [desc: f.inserted_at],
      limit: ^limit,
      offset: ^offset,
      select: v
    )
    |> Repo.all()
  end

  @doc """
  Count how many users are following a venue.

  This is an efficient count query that doesn't load follower records.

  ## Parameters

  - `venue` - The `%Venue{}` struct

  ## Returns

  A non-negative integer representing the follower count.

  ## Examples

      iex> Follows.count_venue_followers(popular_venue)
      567

      iex> Follows.count_venue_followers(new_venue)
      0
  """
  @spec count_venue_followers(Venue.t()) :: non_neg_integer()
  def count_venue_followers(%Venue{id: venue_id}) do
    Repo.aggregate(
      from(f in UserVenueFollow, where: f.venue_id == ^venue_id),
      :count
    )
  end

  # =============================================================================
  # Rate Limiting
  # =============================================================================

  # ETS table for rate limiting - created on first use
  # Using ETS instead of :persistent_term because:
  # - :persistent_term copies all data on every write (expensive for frequent updates)
  # - :persistent_term never cleans up entries (memory leak)
  # - ETS is designed for concurrent read/write access
  @rate_limit_table :follow_rate_limits

  @doc false
  @spec check_rate_limit(integer()) :: :ok | {:error, :rate_limited}
  defp check_rate_limit(user_id) do
    ensure_rate_limit_table_exists()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@rate_limit_table, user_id) do
      [] ->
        # First action, initialize counter
        :ets.insert(@rate_limit_table, {user_id, now, 1})
        :ok

      [{^user_id, window_start, _count}] when now - window_start > @rate_limit_window_ms ->
        # Window expired, reset counter
        :ets.insert(@rate_limit_table, {user_id, now, 1})
        :ok

      [{^user_id, _window_start, count}] when count >= @rate_limit_max_actions ->
        # Rate limit exceeded
        {:error, :rate_limited}

      [{^user_id, window_start, count}] ->
        # Increment counter
        :ets.insert(@rate_limit_table, {user_id, window_start, count + 1})
        :ok
    end
  end

  # Lazily create the ETS table if it doesn't exist
  # Using :public so any process can read/write (needed for concurrent requests)
  @spec ensure_rate_limit_table_exists() :: :ok
  defp ensure_rate_limit_table_exists do
    case :ets.whereis(@rate_limit_table) do
      :undefined ->
        # Table doesn't exist, create it
        # Using try/catch to handle race condition where another process creates it first
        try do
          :ets.new(@rate_limit_table, [:set, :public, :named_table, {:read_concurrency, true}])
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end

    :ok
  end

  # =============================================================================
  # Telemetry
  # =============================================================================

  @doc false
  @spec emit_telemetry(
          :follow | :unfollow,
          :performer | :venue,
          User.t(),
          Performer.t() | Venue.t()
        ) :: :ok
  defp emit_telemetry(action, entity_type, %User{id: user_id}, entity) do
    entity_id =
      case entity do
        %Performer{id: id} -> id
        %Venue{id: id} -> id
      end

    :telemetry.execute(
      [:eventasaurus, :follows, action],
      %{count: 1},
      %{
        entity_type: entity_type,
        user_id: user_id,
        entity_id: entity_id
      }
    )

    :ok
  end
end
