defmodule EventasaurusApp.DiscoveryTest do
  @moduledoc """
  Tests for the Discovery context module.

  These tests verify privacy-respecting discovery functionality including:
  - Privacy filtering (discoverable_in_suggestions, show_on_attendee_lists)
  - Friends-of-friends discovery
  - Shared event discovery
  - Event co-attendee discovery
  - Upcoming event attendee discovery
  - Combined discovery
  """

  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Discovery
  alias EventasaurusApp.Repo

  import EventasaurusApp.Factory

  # =============================================================================
  # Privacy Helper Tests
  # =============================================================================

  describe "discoverable_user_ids/0" do
    test "returns users with no preferences (defaults to discoverable)" do
      user = insert(:user)

      discoverable_ids = Discovery.discoverable_user_ids() |> Repo.all()

      assert user.id in discoverable_ids
    end

    test "returns users with discoverable_in_suggestions: true" do
      user = insert(:user)
      insert(:user_preferences, user: user, discoverable_in_suggestions: true)

      discoverable_ids = Discovery.discoverable_user_ids() |> Repo.all()

      assert user.id in discoverable_ids
    end

    test "excludes users with discoverable_in_suggestions: false" do
      user = insert(:user)
      insert(:user_preferences, user: user, discoverable_in_suggestions: false)

      discoverable_ids = Discovery.discoverable_user_ids() |> Repo.all()

      refute user.id in discoverable_ids
    end
  end

  describe "attendee_visible_user_ids/0" do
    test "returns users with no preferences (defaults to visible)" do
      user = insert(:user)

      visible_ids = Discovery.attendee_visible_user_ids() |> Repo.all()

      assert user.id in visible_ids
    end

    test "returns users with show_on_attendee_lists: true" do
      user = insert(:user)
      insert(:user_preferences, user: user, show_on_attendee_lists: true)

      visible_ids = Discovery.attendee_visible_user_ids() |> Repo.all()

      assert user.id in visible_ids
    end

    test "excludes users with show_on_attendee_lists: false" do
      user = insert(:user)
      insert(:user_preferences, user: user, show_on_attendee_lists: false)

      visible_ids = Discovery.attendee_visible_user_ids() |> Repo.all()

      refute user.id in visible_ids
    end
  end

  describe "discoverable?/1" do
    test "returns true for user with no preferences" do
      user = insert(:user)

      assert Discovery.discoverable?(user)
    end

    test "returns true for user with discoverable_in_suggestions: true" do
      user = insert(:user)
      insert(:user_preferences, user: user, discoverable_in_suggestions: true)

      assert Discovery.discoverable?(user)
    end

    test "returns false for user with discoverable_in_suggestions: false" do
      user = insert(:user)
      insert(:user_preferences, user: user, discoverable_in_suggestions: false)

      refute Discovery.discoverable?(user)
    end
  end

  describe "visible_on_attendee_lists?/1" do
    test "returns true for user with no preferences" do
      user = insert(:user)

      assert Discovery.visible_on_attendee_lists?(user)
    end

    test "returns true for user with show_on_attendee_lists: true" do
      user = insert(:user)
      insert(:user_preferences, user: user, show_on_attendee_lists: true)

      assert Discovery.visible_on_attendee_lists?(user)
    end

    test "returns false for user with show_on_attendee_lists: false" do
      user = insert(:user)
      insert(:user_preferences, user: user, show_on_attendee_lists: false)

      refute Discovery.visible_on_attendee_lists?(user)
    end
  end

  # =============================================================================
  # Friends of Friends Tests
  # =============================================================================

  describe "friends_of_friends/2" do
    test "returns empty list when user has no connections" do
      user = insert(:user)

      results = Discovery.friends_of_friends(user)

      assert results == []
    end

    test "returns friends of friends" do
      # User -> Friend -> FoF
      user = insert(:user)
      friend = insert(:user)
      friend_of_friend = insert(:user)

      # User is connected to friend
      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)

      # Friend is connected to FoF
      insert(:user_relationship, user: friend, related_user: friend_of_friend)
      insert(:user_relationship, user: friend_of_friend, related_user: friend)

      results = Discovery.friends_of_friends(user)

      assert length(results) == 1
      [result] = results
      assert result.user.id == friend_of_friend.id
      assert result.mutual_count == 1
    end

    test "respects limit option" do
      user = insert(:user)
      friend = insert(:user)

      # Connect user to friend
      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)

      # Create multiple FoFs
      for _ <- 1..5 do
        fof = insert(:user)
        insert(:user_relationship, user: friend, related_user: fof)
        insert(:user_relationship, user: fof, related_user: friend)
      end

      results = Discovery.friends_of_friends(user, limit: 2)

      assert length(results) <= 2
    end

    test "filters out non-discoverable users by default" do
      user = insert(:user)
      friend = insert(:user)
      private_fof = insert(:user)

      # User is connected to friend
      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)

      # Friend is connected to private FoF
      insert(:user_relationship, user: friend, related_user: private_fof)
      insert(:user_relationship, user: private_fof, related_user: friend)

      # Make FoF private
      insert(:user_preferences, user: private_fof, discoverable_in_suggestions: false)

      results = Discovery.friends_of_friends(user)

      assert results == []
    end

    test "includes non-discoverable users with skip_privacy_filter: true" do
      user = insert(:user)
      friend = insert(:user)
      private_fof = insert(:user)

      # User is connected to friend
      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)

      # Friend is connected to private FoF
      insert(:user_relationship, user: friend, related_user: private_fof)
      insert(:user_relationship, user: private_fof, related_user: friend)

      # Make FoF private
      insert(:user_preferences, user: private_fof, discoverable_in_suggestions: false)

      results = Discovery.friends_of_friends(user, skip_privacy_filter: true)

      assert length(results) == 1
      [result] = results
      assert result.user.id == private_fof.id
    end

    test "includes mutual users when include_mutual_users: true" do
      user = insert(:user)
      friend = insert(:user)
      fof = insert(:user)

      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)
      insert(:user_relationship, user: friend, related_user: fof)
      insert(:user_relationship, user: fof, related_user: friend)

      results = Discovery.friends_of_friends(user, include_mutual_users: true)

      assert length(results) == 1
      [result] = results
      assert Map.has_key?(result, :mutual_users)
      assert is_list(result.mutual_users)
    end
  end

  # =============================================================================
  # Shared Events Tests
  # =============================================================================

  describe "shared_events/3" do
    test "returns empty list when no shared events" do
      user1 = insert(:user)
      user2 = insert(:user)

      events = Discovery.shared_events(user1, user2)

      assert events == []
    end

    test "returns events both users attended as participants" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user1, event: event, status: :accepted)
      insert(:event_participant, user: user2, event: event, status: :accepted)

      events = Discovery.shared_events(user1, user2)

      assert length(events) == 1
      assert hd(events).id == event.id
    end

    test "returns events where one user was organizer and other was participant" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_user, user: user1, event: event, role: "organizer")
      insert(:event_participant, user: user2, event: event, status: :accepted)

      events = Discovery.shared_events(user1, user2)

      assert length(events) == 1
      assert hd(events).id == event.id
    end

    test "respects limit option" do
      user1 = insert(:user)
      user2 = insert(:user)

      # Create multiple shared events
      for i <- 1..5 do
        event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -i, :day))
        insert(:event_participant, user: user1, event: event, status: :accepted)
        insert(:event_participant, user: user2, event: event, status: :accepted)
      end

      events = Discovery.shared_events(user1, user2, limit: 2)

      assert length(events) == 2
    end

    test "orders by most recent by default" do
      user1 = insert(:user)
      user2 = insert(:user)

      old_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -30, :day))
      recent_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -1, :day))

      insert(:event_participant, user: user1, event: old_event, status: :accepted)
      insert(:event_participant, user: user2, event: old_event, status: :accepted)
      insert(:event_participant, user: user1, event: recent_event, status: :accepted)
      insert(:event_participant, user: user2, event: recent_event, status: :accepted)

      events = Discovery.shared_events(user1, user2)

      assert hd(events).id == recent_event.id
    end

    test "orders by oldest when order: :oldest" do
      user1 = insert(:user)
      user2 = insert(:user)

      old_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -30, :day))
      recent_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -1, :day))

      insert(:event_participant, user: user1, event: old_event, status: :accepted)
      insert(:event_participant, user: user2, event: old_event, status: :accepted)
      insert(:event_participant, user: user1, event: recent_event, status: :accepted)
      insert(:event_participant, user: user2, event: recent_event, status: :accepted)

      events = Discovery.shared_events(user1, user2, order: :oldest)

      assert hd(events).id == old_event.id
    end

    test "excludes future events by default" do
      user1 = insert(:user)
      user2 = insert(:user)

      future_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), 7, :day))

      insert(:event_participant, user: user1, event: future_event, status: :accepted)
      insert(:event_participant, user: user2, event: future_event, status: :accepted)

      events = Discovery.shared_events(user1, user2)

      assert events == []
    end

    test "includes future events when include_upcoming: true" do
      user1 = insert(:user)
      user2 = insert(:user)

      future_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), 7, :day))

      insert(:event_participant, user: user1, event: future_event, status: :accepted)
      insert(:event_participant, user: user2, event: future_event, status: :accepted)

      events = Discovery.shared_events(user1, user2, include_upcoming: true)

      assert length(events) == 1
      assert hd(events).id == future_event.id
    end

    test "excludes soft-deleted participants" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user1, event: event, status: :accepted)

      insert(:event_participant,
        user: user2,
        event: event,
        status: :accepted,
        deleted_at: DateTime.utc_now()
      )

      events = Discovery.shared_events(user1, user2)

      assert events == []
    end

    test "excludes cancelled participant statuses" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user1, event: event, status: :accepted)
      insert(:event_participant, user: user2, event: event, status: :cancelled)

      events = Discovery.shared_events(user1, user2)

      assert events == []
    end

    test "includes pending participant statuses" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user1, event: event, status: :accepted)
      insert(:event_participant, user: user2, event: event, status: :pending)

      events = Discovery.shared_events(user1, user2)

      assert length(events) == 1
      assert hd(events).id == event.id
    end
  end

  describe "shared_event_count/2" do
    test "returns count of shared events" do
      user1 = insert(:user)
      user2 = insert(:user)

      for i <- 1..3 do
        event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -i, :day))
        insert(:event_participant, user: user1, event: event, status: :accepted)
        insert(:event_participant, user: user2, event: event, status: :accepted)
      end

      count = Discovery.shared_event_count(user1, user2)

      assert count == 3
    end

    test "returns 0 when no shared events" do
      user1 = insert(:user)
      user2 = insert(:user)

      count = Discovery.shared_event_count(user1, user2)

      assert count == 0
    end
  end

  # =============================================================================
  # Event Co-Attendees Tests
  # =============================================================================

  describe "event_co_attendees/2" do
    test "returns empty list when user has no event attendance" do
      user = insert(:user)

      results = Discovery.event_co_attendees(user)

      assert results == []
    end

    test "returns co-attendees from past events" do
      user = insert(:user)
      other_user = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: other_user, event: event, status: :accepted)

      results = Discovery.event_co_attendees(user)

      assert length(results) == 1
      [result] = results
      assert result.user.id == other_user.id
      assert result.shared_event_count >= 1
    end

    test "excludes already connected users by default" do
      user = insert(:user)
      connected_user = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: connected_user, event: event, status: :accepted)

      # Create connection
      insert(:user_relationship, user: user, related_user: connected_user, status: :active)

      results = Discovery.event_co_attendees(user)

      assert results == []
    end

    test "includes connected users with exclude_connected: false" do
      user = insert(:user)
      connected_user = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: connected_user, event: event, status: :accepted)

      # Create connection
      insert(:user_relationship, user: user, related_user: connected_user, status: :active)

      results = Discovery.event_co_attendees(user, exclude_connected: false)

      assert length(results) == 1
    end

    test "respects limit option" do
      user = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))
      insert(:event_participant, user: user, event: event, status: :accepted)

      # Create multiple co-attendees
      for _ <- 1..5 do
        other = insert(:user)
        insert(:event_participant, user: other, event: event, status: :accepted)
      end

      results = Discovery.event_co_attendees(user, limit: 2)

      assert length(results) <= 2
    end

    test "filters out non-visible users by default" do
      user = insert(:user)
      private_user = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: private_user, event: event, status: :accepted)

      # Make user not visible on attendee lists
      insert(:user_preferences, user: private_user, show_on_attendee_lists: false)

      results = Discovery.event_co_attendees(user)

      assert results == []
    end

    test "includes non-visible users with skip_privacy_filter: true" do
      user = insert(:user)
      private_user = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: private_user, event: event, status: :accepted)

      # Make user not visible on attendee lists
      insert(:user_preferences, user: private_user, show_on_attendee_lists: false)

      results = Discovery.event_co_attendees(user, skip_privacy_filter: true)

      assert length(results) == 1
    end

    test "filters by specific event with event_id option" do
      user = insert(:user)
      other_user1 = insert(:user)
      other_user2 = insert(:user)

      event1 = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))
      event2 = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -3, :day))

      # User attended both events
      insert(:event_participant, user: user, event: event1, status: :accepted)
      insert(:event_participant, user: user, event: event2, status: :accepted)

      # Other users at different events
      insert(:event_participant, user: other_user1, event: event1, status: :accepted)
      insert(:event_participant, user: other_user2, event: event2, status: :accepted)

      results = Discovery.event_co_attendees(user, event_id: event1.id)

      assert length(results) == 1
      [result] = results
      assert result.user.id == other_user1.id
    end

    test "respects timeframe: :upcoming option" do
      user = insert(:user)
      past_attendee = insert(:user)
      future_attendee = insert(:user)

      past_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))
      future_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), 7, :day))

      insert(:event_participant, user: user, event: past_event, status: :accepted)
      insert(:event_participant, user: past_attendee, event: past_event, status: :accepted)

      insert(:event_participant, user: user, event: future_event, status: :accepted)
      insert(:event_participant, user: future_attendee, event: future_event, status: :accepted)

      results = Discovery.event_co_attendees(user, timeframe: :upcoming)

      assert length(results) == 1
      [result] = results
      assert result.user.id == future_attendee.id
    end

    test "respects timeframe: :all option" do
      user = insert(:user)
      past_attendee = insert(:user)
      future_attendee = insert(:user)

      past_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))
      future_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), 7, :day))

      insert(:event_participant, user: user, event: past_event, status: :accepted)
      insert(:event_participant, user: past_attendee, event: past_event, status: :accepted)

      insert(:event_participant, user: user, event: future_event, status: :accepted)
      insert(:event_participant, user: future_attendee, event: future_event, status: :accepted)

      results = Discovery.event_co_attendees(user, timeframe: :all)

      assert length(results) == 2
    end

    test "respects min_shared_events option" do
      user = insert(:user)
      casual_attendee = insert(:user)
      frequent_attendee = insert(:user)

      # Create 3 events user attended
      events =
        for i <- 1..3 do
          insert(:event, start_at: DateTime.add(DateTime.utc_now(), -i, :day))
        end

      for event <- events do
        insert(:event_participant, user: user, event: event, status: :accepted)
      end

      # Casual attendee at 1 event
      insert(:event_participant, user: casual_attendee, event: hd(events), status: :accepted)

      # Frequent attendee at all events
      for event <- events do
        insert(:event_participant, user: frequent_attendee, event: event, status: :accepted)
      end

      results = Discovery.event_co_attendees(user, min_shared_events: 2)

      assert length(results) == 1
      [result] = results
      assert result.user.id == frequent_attendee.id
    end

    test "includes pending participant statuses in event_co_attendees" do
      user = insert(:user)
      pending_attendee = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      # User has accepted status
      insert(:event_participant, user: user, event: event, status: :accepted)
      # Other attendee has pending status - should still appear
      insert(:event_participant, user: pending_attendee, event: event, status: :pending)

      results = Discovery.event_co_attendees(user)

      assert length(results) == 1
      [result] = results
      assert result.user.id == pending_attendee.id
    end
  end

  # =============================================================================
  # Upcoming Event Attendees Tests
  # =============================================================================

  describe "upcoming_event_attendees/2" do
    test "returns empty list when no upcoming events" do
      user = insert(:user)

      results = Discovery.upcoming_event_attendees(user)

      assert results == []
    end

    test "returns attendees of upcoming events" do
      user = insert(:user)
      other_user = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), 7, :day))

      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: other_user, event: event, status: :accepted)

      results = Discovery.upcoming_event_attendees(user)

      assert length(results) == 1
      [result] = results
      assert result.user.id == other_user.id
      assert Map.has_key?(result, :upcoming_events)
      assert Map.has_key?(result, :upcoming_event_count)
    end

    test "respects days_ahead option" do
      user = insert(:user)
      near_attendee = insert(:user)
      far_attendee = insert(:user)

      near_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), 3, :day))
      far_event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), 60, :day))

      insert(:event_participant, user: user, event: near_event, status: :accepted)
      insert(:event_participant, user: near_attendee, event: near_event, status: :accepted)

      insert(:event_participant, user: user, event: far_event, status: :accepted)
      insert(:event_participant, user: far_attendee, event: far_event, status: :accepted)

      results = Discovery.upcoming_event_attendees(user, days_ahead: 7)

      assert length(results) == 1
      [result] = results
      assert result.user.id == near_attendee.id
    end

    test "excludes past events" do
      user = insert(:user)
      past_attendee = insert(:user)
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))

      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: past_attendee, event: event, status: :accepted)

      results = Discovery.upcoming_event_attendees(user)

      assert results == []
    end
  end

  # =============================================================================
  # Combined Discovery Tests
  # =============================================================================

  describe "discover/2" do
    test "returns empty list for user with no connections or events" do
      user = insert(:user)

      results = Discovery.discover(user)

      assert results == []
    end

    test "combines results from multiple sources" do
      user = insert(:user)
      friend = insert(:user)
      fof = insert(:user)
      co_attendee = insert(:user)

      # Create FoF connection
      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)
      insert(:user_relationship, user: friend, related_user: fof)
      insert(:user_relationship, user: fof, related_user: friend)

      # Create co-attendee relationship
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))
      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: co_attendee, event: event, status: :accepted)

      results = Discovery.discover(user)

      # Should have at least results from both sources
      assert length(results) >= 1

      user_ids = Enum.map(results, fn r -> r.user.id end)
      # Either fof or co_attendee should be present
      assert fof.id in user_ids or co_attendee.id in user_ids
    end

    test "deduplicates users appearing in multiple sources" do
      user = insert(:user)
      friend = insert(:user)
      multi_source_user = insert(:user)

      # Multi source user is FoF
      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)
      insert(:user_relationship, user: friend, related_user: multi_source_user)
      insert(:user_relationship, user: multi_source_user, related_user: friend)

      # Multi source user is also co-attendee
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))
      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: multi_source_user, event: event, status: :accepted)

      results = Discovery.discover(user)

      # User should only appear once
      user_ids = Enum.map(results, fn r -> r.user.id end)
      assert Enum.count(user_ids, fn id -> id == multi_source_user.id end) <= 1
    end

    test "includes source field in results" do
      user = insert(:user)
      friend = insert(:user)
      fof = insert(:user)

      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)
      insert(:user_relationship, user: friend, related_user: fof)
      insert(:user_relationship, user: fof, related_user: friend)

      results = Discovery.discover(user)

      assert length(results) >= 1
      [result | _] = results
      assert Map.has_key?(result, :source)
      assert result.source in [:friends_of_friends, :event_co_attendees, :upcoming_events]
    end

    test "includes context field in results" do
      user = insert(:user)
      friend = insert(:user)
      fof = insert(:user)

      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)
      insert(:user_relationship, user: friend, related_user: fof)
      insert(:user_relationship, user: fof, related_user: friend)

      results = Discovery.discover(user)

      assert length(results) >= 1
      [result | _] = results
      assert Map.has_key?(result, :context)
      assert is_binary(result.context)
    end

    test "respects sources option to limit which sources are queried" do
      user = insert(:user)
      friend = insert(:user)
      fof = insert(:user)

      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: user)
      insert(:user_relationship, user: friend, related_user: fof)
      insert(:user_relationship, user: fof, related_user: friend)

      # Also add event attendance
      event = insert(:event, start_at: DateTime.add(DateTime.utc_now(), -7, :day))
      co_attendee = insert(:user)
      insert(:event_participant, user: user, event: event, status: :accepted)
      insert(:event_participant, user: co_attendee, event: event, status: :accepted)

      # Only query friends_of_friends
      results = Discovery.discover(user, sources: [:friends_of_friends])

      # All results should be from friends_of_friends source
      sources = Enum.map(results, fn r -> r.source end) |> Enum.uniq()
      assert sources == [:friends_of_friends] or sources == []
    end
  end
end
