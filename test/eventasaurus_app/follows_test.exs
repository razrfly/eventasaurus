defmodule EventasaurusApp.FollowsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Follows
  import EventasaurusApp.Factory

  describe "performer following" do
    test "follow_performer/2 creates a follow relationship" do
      user = insert(:user)
      performer = insert(:performer)

      assert {:ok, follow} = Follows.follow_performer(user, performer)
      assert follow.user_id == user.id
      assert follow.performer_id == performer.id
    end

    test "follow_performer/2 returns error when already following" do
      user = insert(:user)
      performer = insert(:performer)

      assert {:ok, _follow} = Follows.follow_performer(user, performer)
      assert {:error, changeset} = Follows.follow_performer(user, performer)
      assert changeset.errors[:user_id] || changeset.errors[:performer_id]
    end

    test "unfollow_performer/2 removes the follow relationship" do
      user = insert(:user)
      performer = insert(:performer)

      {:ok, _follow} = Follows.follow_performer(user, performer)
      assert {:ok, _deleted} = Follows.unfollow_performer(user, performer)
      refute Follows.following_performer?(user, performer)
    end

    test "unfollow_performer/2 returns error when not following" do
      user = insert(:user)
      performer = insert(:performer)

      assert {:error, :not_found} = Follows.unfollow_performer(user, performer)
    end

    test "following_performer?/2 returns true when following" do
      user = insert(:user)
      performer = insert(:performer)

      refute Follows.following_performer?(user, performer)
      {:ok, _follow} = Follows.follow_performer(user, performer)
      assert Follows.following_performer?(user, performer)
    end

    test "following_performer?/2 returns false for nil user" do
      performer = insert(:performer)
      refute Follows.following_performer?(nil, performer)
    end

    test "list_followed_performers/1 returns followed performers" do
      user = insert(:user)
      performer1 = insert(:performer)
      performer2 = insert(:performer)
      performer3 = insert(:performer)

      {:ok, _} = Follows.follow_performer(user, performer1)
      {:ok, _} = Follows.follow_performer(user, performer2)

      followed = Follows.list_followed_performers(user)
      followed_ids = Enum.map(followed, & &1.id)

      assert performer1.id in followed_ids
      assert performer2.id in followed_ids
      refute performer3.id in followed_ids
    end

    test "list_followed_performers/1 respects limit and offset" do
      user = insert(:user)
      performers = for _ <- 1..5, do: insert(:performer)
      for p <- performers, do: Follows.follow_performer(user, p)

      limited = Follows.list_followed_performers(user, limit: 2)
      assert length(limited) == 2

      offset = Follows.list_followed_performers(user, limit: 2, offset: 2)
      assert length(offset) == 2
    end

    test "count_performer_followers/1 returns follower count" do
      performer = insert(:performer)
      users = for _ <- 1..3, do: insert(:user)

      assert Follows.count_performer_followers(performer) == 0

      for u <- users, do: Follows.follow_performer(u, performer)
      assert Follows.count_performer_followers(performer) == 3
    end
  end

  describe "venue following" do
    test "follow_venue/2 creates a follow relationship" do
      user = insert(:user)
      venue = insert(:venue)

      assert {:ok, follow} = Follows.follow_venue(user, venue)
      assert follow.user_id == user.id
      assert follow.venue_id == venue.id
    end

    test "follow_venue/2 returns error when already following" do
      user = insert(:user)
      venue = insert(:venue)

      assert {:ok, _follow} = Follows.follow_venue(user, venue)
      assert {:error, changeset} = Follows.follow_venue(user, venue)
      assert changeset.errors[:user_id] || changeset.errors[:venue_id]
    end

    test "unfollow_venue/2 removes the follow relationship" do
      user = insert(:user)
      venue = insert(:venue)

      {:ok, _follow} = Follows.follow_venue(user, venue)
      assert {:ok, _deleted} = Follows.unfollow_venue(user, venue)
      refute Follows.following_venue?(user, venue)
    end

    test "unfollow_venue/2 returns error when not following" do
      user = insert(:user)
      venue = insert(:venue)

      assert {:error, :not_found} = Follows.unfollow_venue(user, venue)
    end

    test "following_venue?/2 returns true when following" do
      user = insert(:user)
      venue = insert(:venue)

      refute Follows.following_venue?(user, venue)
      {:ok, _follow} = Follows.follow_venue(user, venue)
      assert Follows.following_venue?(user, venue)
    end

    test "following_venue?/2 returns false for nil user" do
      venue = insert(:venue)
      refute Follows.following_venue?(nil, venue)
    end

    test "list_followed_venues/1 returns followed venues" do
      user = insert(:user)
      venue1 = insert(:venue)
      venue2 = insert(:venue)
      venue3 = insert(:venue)

      {:ok, _} = Follows.follow_venue(user, venue1)
      {:ok, _} = Follows.follow_venue(user, venue2)

      followed = Follows.list_followed_venues(user)
      followed_ids = Enum.map(followed, & &1.id)

      assert venue1.id in followed_ids
      assert venue2.id in followed_ids
      refute venue3.id in followed_ids
    end

    test "list_followed_venues/1 respects limit and offset" do
      user = insert(:user)
      venues = for _ <- 1..5, do: insert(:venue)
      for v <- venues, do: Follows.follow_venue(user, v)

      limited = Follows.list_followed_venues(user, limit: 2)
      assert length(limited) == 2

      offset = Follows.list_followed_venues(user, limit: 2, offset: 2)
      assert length(offset) == 2
    end

    test "count_venue_followers/1 returns follower count" do
      venue = insert(:venue)
      users = for _ <- 1..3, do: insert(:user)

      assert Follows.count_venue_followers(venue) == 0

      for u <- users, do: Follows.follow_venue(u, venue)
      assert Follows.count_venue_followers(venue) == 3
    end
  end
end
