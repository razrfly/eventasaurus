defmodule EventasaurusApp.Follows do
  @moduledoc """
  Context for managing user follows of performers and venues.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Follows.{UserPerformerFollow, UserVenueFollow}
  alias EventasaurusApp.Accounts.User
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusApp.Venues.Venue

  # =============================================================================
  # Performer Following
  # =============================================================================

  @doc """
  Follow a performer.

  Returns `{:ok, follow}` on success, or `{:error, changeset}` on failure.
  """
  def follow_performer(%User{id: user_id}, %Performer{id: performer_id}) do
    %UserPerformerFollow{}
    |> UserPerformerFollow.changeset(%{user_id: user_id, performer_id: performer_id})
    |> Repo.insert()
  end

  @doc """
  Unfollow a performer.

  Returns `{:ok, follow}` on success, or `{:error, :not_found}` if not following.
  """
  def unfollow_performer(%User{id: user_id}, %Performer{id: performer_id}) do
    case Repo.get_by(UserPerformerFollow, user_id: user_id, performer_id: performer_id) do
      nil -> {:error, :not_found}
      follow -> Repo.delete(follow)
    end
  end

  @doc """
  Check if a user is following a performer.
  """
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

  Options:
  - `:limit` - Maximum number of results (default: 50)
  - `:offset` - Number of results to skip (default: 0)
  """
  def list_followed_performers(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
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
  """
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

  Returns `{:ok, follow}` on success, or `{:error, changeset}` on failure.
  """
  def follow_venue(%User{id: user_id}, %Venue{id: venue_id}) do
    %UserVenueFollow{}
    |> UserVenueFollow.changeset(%{user_id: user_id, venue_id: venue_id})
    |> Repo.insert()
  end

  @doc """
  Unfollow a venue.

  Returns `{:ok, follow}` on success, or `{:error, :not_found}` if not following.
  """
  def unfollow_venue(%User{id: user_id}, %Venue{id: venue_id}) do
    case Repo.get_by(UserVenueFollow, user_id: user_id, venue_id: venue_id) do
      nil -> {:error, :not_found}
      follow -> Repo.delete(follow)
    end
  end

  @doc """
  Check if a user is following a venue.
  """
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

  Options:
  - `:limit` - Maximum number of results (default: 50)
  - `:offset` - Number of results to skip (default: 0)
  """
  def list_followed_venues(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
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
  """
  def count_venue_followers(%Venue{id: venue_id}) do
    Repo.aggregate(
      from(f in UserVenueFollow, where: f.venue_id == ^venue_id),
      :count
    )
  end
end
