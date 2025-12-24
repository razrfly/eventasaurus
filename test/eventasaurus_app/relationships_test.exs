defmodule EventasaurusApp.RelationshipsTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Relationships

  import EventasaurusApp.Factory

  describe "get_relationship/1" do
    test "returns relationship when it exists" do
      relationship = insert(:user_relationship)
      found = Relationships.get_relationship(relationship.id)

      assert found.id == relationship.id
      assert found.status == :active
    end

    test "returns nil when relationship does not exist" do
      assert Relationships.get_relationship(999_999) == nil
    end
  end

  describe "get_relationship_between/2" do
    test "returns relationship between two users" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2)

      relationship = Relationships.get_relationship_between(user1, user2)

      assert relationship.user_id == user1.id
      assert relationship.related_user_id == user2.id
    end

    test "returns nil when no relationship exists" do
      user1 = insert(:user)
      user2 = insert(:user)

      assert Relationships.get_relationship_between(user1, user2) == nil
    end
  end

  describe "list_relationships/2" do
    test "returns all active relationships for a user" do
      user = insert(:user)
      other1 = insert(:user)
      other2 = insert(:user)
      insert(:user_relationship, user: user, related_user: other1)
      insert(:user_relationship, user: user, related_user: other2)

      relationships = Relationships.list_relationships(user)

      assert length(relationships) == 2
      assert Enum.all?(relationships, &(&1.status == :active))
    end

    test "does not return blocked relationships" do
      user = insert(:user)
      blocked = insert(:user)
      insert(:user_relationship, user: user, related_user: blocked, status: :blocked)

      relationships = Relationships.list_relationships(user)

      assert relationships == []
    end

    test "respects limit option" do
      user = insert(:user)
      for _ <- 1..5, do: insert(:user_relationship, user: user, related_user: insert(:user))

      relationships = Relationships.list_relationships(user, limit: 3)

      assert length(relationships) == 3
    end

    test "preloads related_user" do
      user = insert(:user)
      other = insert(:user)
      insert(:user_relationship, user: user, related_user: other)

      [relationship] = Relationships.list_relationships(user)

      assert relationship.related_user.id == other.id
      assert relationship.related_user.email == other.email
    end
  end

  describe "connected?/2" do
    test "returns true when active relationship exists" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2)

      assert Relationships.connected?(user1, user2)
    end

    test "returns false when no relationship exists" do
      user1 = insert(:user)
      user2 = insert(:user)

      refute Relationships.connected?(user1, user2)
    end

    test "returns false when relationship is blocked" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2, status: :blocked)

      refute Relationships.connected?(user1, user2)
    end
  end

  describe "mutually_connected?/2" do
    test "returns true when both directions exist" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2)
      insert(:user_relationship, user: user2, related_user: user1)

      assert Relationships.mutually_connected?(user1, user2)
    end

    test "returns false when only one direction exists" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2)

      refute Relationships.mutually_connected?(user1, user2)
    end
  end

  describe "create_from_shared_event/4" do
    test "creates bidirectional relationships" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event)

      {:ok, {rel1, rel2}} =
        Relationships.create_from_shared_event(user1, user2, event, "Met at Jazz Night")

      assert rel1.user_id == user1.id
      assert rel1.related_user_id == user2.id
      assert rel1.origin == :shared_event
      assert rel1.context == "Met at Jazz Night"
      assert rel1.originated_from_event_id == event.id

      assert rel2.user_id == user2.id
      assert rel2.related_user_id == user1.id
      assert rel2.origin == :shared_event
    end

    test "increments shared_event_count for existing relationships" do
      user1 = insert(:user)
      user2 = insert(:user)
      event1 = insert(:event)
      event2 = insert(:event)

      {:ok, {rel1, _}} =
        Relationships.create_from_shared_event(user1, user2, event1, "First event")

      assert rel1.shared_event_count == 1

      {:ok, {updated_rel1, _}} =
        Relationships.create_from_shared_event(user1, user2, event2, "Second event")

      assert updated_rel1.shared_event_count == 2
      assert updated_rel1.context == "Second event"
    end
  end

  describe "create_from_introduction/4" do
    test "creates bidirectional relationships" do
      user1 = insert(:user)
      user2 = insert(:user)
      introducer = insert(:user)

      {:ok, {rel1, rel2}} =
        Relationships.create_from_introduction(user1, user2, introducer, "Introduced by Sarah")

      assert rel1.origin == :introduction
      assert rel1.context == "Introduced by Sarah"
      assert rel2.origin == :introduction
    end
  end

  describe "create_manual/3" do
    test "creates bidirectional relationships" do
      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, {rel1, rel2}} =
        Relationships.create_manual(user1, user2, "Friends from work")

      assert rel1.origin == :manual
      assert rel1.context == "Friends from work"
      assert rel2.origin == :manual
    end
  end

  describe "relationship_strength/2" do
    test "returns nil when no relationship exists" do
      user1 = insert(:user)
      user2 = insert(:user)

      assert Relationships.relationship_strength(user1, user2) == nil
    end

    test "calculates strength based on shared events and recency" do
      user1 = insert(:user)
      user2 = insert(:user)

      insert(:user_relationship,
        user: user1,
        related_user: user2,
        shared_event_count: 5,
        last_shared_event_at: DateTime.utc_now()
      )

      strength = Relationships.relationship_strength(user1, user2)

      # 5/10 * 0.6 = 0.3 (event score) + ~0.4 (recency score) = ~0.7
      assert strength >= 0.6
      assert strength <= 0.8
    end

    test "returns lower strength for old relationships" do
      user1 = insert(:user)
      user2 = insert(:user)
      old_date = DateTime.add(DateTime.utc_now(), -120, :day)

      insert(:user_relationship,
        user: user1,
        related_user: user2,
        shared_event_count: 1,
        last_shared_event_at: old_date
      )

      strength = Relationships.relationship_strength(user1, user2)

      # 1/10 * 0.6 = 0.06 (event score) + 0 (recency score, beyond 90 days) = ~0.06
      assert strength < 0.1
    end
  end

  describe "list_by_strength/2" do
    test "returns relationships ordered by strength" do
      user = insert(:user)
      strong_friend = insert(:user)
      weak_friend = insert(:user)

      insert(:user_relationship,
        user: user,
        related_user: strong_friend,
        shared_event_count: 10,
        last_shared_event_at: DateTime.utc_now()
      )

      insert(:user_relationship,
        user: user,
        related_user: weak_friend,
        shared_event_count: 1,
        last_shared_event_at: DateTime.add(DateTime.utc_now(), -60, :day)
      )

      [first, second] = Relationships.list_by_strength(user)

      assert first.related_user_id == strong_friend.id
      assert second.related_user_id == weak_friend.id
    end
  end

  describe "mutual_connections/2" do
    test "finds users connected to both" do
      user1 = insert(:user)
      user2 = insert(:user)
      mutual = insert(:user)

      # Both user1 and user2 are connected to mutual
      insert(:user_relationship, user: user1, related_user: mutual)
      insert(:user_relationship, user: user2, related_user: mutual)

      mutuals = Relationships.mutual_connections(user1, user2)

      assert length(mutuals) == 1
      assert hd(mutuals).id == mutual.id
    end

    test "returns empty list when no mutual connections" do
      user1 = insert(:user)
      user2 = insert(:user)

      assert Relationships.mutual_connections(user1, user2) == []
    end
  end

  describe "suggested_connections/2" do
    test "suggests friends of friends" do
      user = insert(:user)
      friend = insert(:user)
      friend_of_friend = insert(:user)

      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: friend, related_user: friend_of_friend)

      suggestions = Relationships.suggested_connections(user)

      assert length(suggestions) == 1
      assert hd(suggestions).user.id == friend_of_friend.id
      assert hd(suggestions).mutual_count == 1
    end

    test "does not suggest already connected users" do
      user = insert(:user)
      friend = insert(:user)
      already_connected = insert(:user)

      insert(:user_relationship, user: user, related_user: friend)
      insert(:user_relationship, user: user, related_user: already_connected)
      insert(:user_relationship, user: friend, related_user: already_connected)

      suggestions = Relationships.suggested_connections(user)

      refute Enum.any?(suggestions, &(&1.user.id == already_connected.id))
    end
  end

  describe "block_user/2" do
    test "blocks an existing relationship" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2)

      {:ok, relationship} = Relationships.block_user(user1, user2)

      assert relationship.status == :blocked
      assert relationship.context == nil
    end

    test "creates a blocked relationship when none exists" do
      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, relationship} = Relationships.block_user(user1, user2)

      assert relationship.status == :blocked
      assert relationship.origin == :manual
    end

    test "blocking is asymmetric" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2)
      insert(:user_relationship, user: user2, related_user: user1)

      {:ok, _} = Relationships.block_user(user1, user2)

      assert Relationships.blocked?(user1, user2)
      refute Relationships.blocked?(user2, user1)
    end
  end

  describe "unblock_user/2" do
    test "removes blocked relationship" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2, status: :blocked)

      {:ok, _} = Relationships.unblock_user(user1, user2)

      refute Relationships.blocked?(user1, user2)
      assert Relationships.get_relationship_between(user1, user2) == nil
    end

    test "returns error when no blocked relationship exists" do
      user1 = insert(:user)
      user2 = insert(:user)

      assert {:error, :not_found} = Relationships.unblock_user(user1, user2)
    end
  end

  describe "blocked?/2" do
    test "returns true when user is blocked" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2, status: :blocked)

      assert Relationships.blocked?(user1, user2)
    end

    test "returns false when not blocked" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2, status: :active)

      refute Relationships.blocked?(user1, user2)
    end
  end

  describe "list_blocked/1" do
    test "returns all blocked users" do
      user = insert(:user)
      blocked1 = insert(:user)
      blocked2 = insert(:user)

      insert(:user_relationship, user: user, related_user: blocked1, status: :blocked)
      insert(:user_relationship, user: user, related_user: blocked2, status: :blocked)

      blocked = Relationships.list_blocked(user)

      assert length(blocked) == 2
      blocked_ids = Enum.map(blocked, & &1.id)
      assert blocked1.id in blocked_ids
      assert blocked2.id in blocked_ids
    end
  end

  describe "record_shared_event/3" do
    test "increments count for existing relationships" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event)

      insert(:user_relationship, user: user1, related_user: user2, shared_event_count: 3)
      insert(:user_relationship, user: user2, related_user: user1, shared_event_count: 3)

      {:ok, {rel1, rel2}} = Relationships.record_shared_event(user1, user2, event)

      assert rel1.shared_event_count == 4
      assert rel2.shared_event_count == 4
    end

    test "returns nil when no relationship exists" do
      user1 = insert(:user)
      user2 = insert(:user)
      event = insert(:event)

      assert {:ok, nil} = Relationships.record_shared_event(user1, user2, event)
    end
  end

  describe "relationships_from_event/1" do
    test "returns all relationships formed at an event" do
      event = insert(:event)
      user1 = insert(:user)
      user2 = insert(:user)

      insert(:user_relationship,
        user: user1,
        related_user: user2,
        originated_from_event: event,
        origin: :shared_event
      )

      relationships = Relationships.relationships_from_event(event)

      assert length(relationships) == 1
      assert hd(relationships).originated_from_event_id == event.id
    end
  end

  describe "remove_relationship/2" do
    test "removes relationships in both directions" do
      user1 = insert(:user)
      user2 = insert(:user)
      insert(:user_relationship, user: user1, related_user: user2)
      insert(:user_relationship, user: user2, related_user: user1)

      {:ok, count} = Relationships.remove_relationship(user1, user2)

      assert count == 2
      refute Relationships.connected?(user1, user2)
      refute Relationships.connected?(user2, user1)
    end
  end
end
