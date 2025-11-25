defmodule EventasaurusApp.Planning.OccurrencePlanningsTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Planning.{OccurrencePlanning, OccurrencePlannings}
  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts

  setup do
    # Create test user
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        password: "SecurePassword123!",
        username: "testuser"
      })

    # Create test event
    {:ok, event} =
      Events.create_event(%{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(1, :day),
        timezone: "UTC",
        visibility: :private,
        status: :draft
      })

    # Create test poll
    {:ok, poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Test Poll",
        poll_type: "occurrence_selection",
        voting_system: "binary",
        created_by_id: user.id
      })

    %{user: user, event: event, poll: poll}
  end

  describe "create/1" do
    test "creates occurrence planning with valid attributes", %{event: event, poll: poll} do
      attrs = %{
        event_id: event.id,
        poll_id: poll.id,
        series_type: "movie",
        series_id: 123
      }

      assert {:ok, %OccurrencePlanning{} = planning} = OccurrencePlannings.create(attrs)
      assert planning.event_id == event.id
      assert planning.poll_id == poll.id
      assert planning.series_type == "movie"
      assert planning.series_id == 123
    end

    test "creates occurrence planning for discovery mode", %{event: event, poll: poll} do
      attrs = %{
        event_id: event.id,
        poll_id: poll.id
      }

      assert {:ok, %OccurrencePlanning{} = planning} = OccurrencePlannings.create(attrs)
      assert planning.series_type == nil
      assert planning.series_id == nil
    end

    test "fails with invalid attributes" do
      attrs = %{event_id: nil}

      assert {:error, changeset} = OccurrencePlannings.create(attrs)
      refute changeset.valid?
    end
  end

  describe "get!/1 and get/1" do
    test "get!/1 returns the occurrence planning", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      retrieved = OccurrencePlannings.get!(planning.id)

      assert retrieved.id == planning.id
      assert retrieved.event_id == event.id
    end

    test "get/1 returns the occurrence planning", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      retrieved = OccurrencePlannings.get(planning.id)

      assert retrieved.id == planning.id
    end

    test "get/1 returns nil when not found" do
      assert OccurrencePlannings.get(999_999) == nil
    end
  end

  describe "get_by_event/1 and get_by_event!/1" do
    test "returns occurrence planning by event_id", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      retrieved = OccurrencePlannings.get_by_event(event.id)

      assert retrieved.id == planning.id
      assert retrieved.event_id == event.id
    end

    test "get_by_event/1 returns nil when not found" do
      assert OccurrencePlannings.get_by_event(999_999) == nil
    end
  end

  describe "get_by_poll/1 and get_by_poll!/1" do
    test "returns occurrence planning by poll_id", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      retrieved = OccurrencePlannings.get_by_poll(poll.id)

      assert retrieved.id == planning.id
      assert retrieved.poll_id == poll.id
    end

    test "get_by_poll/1 returns nil when not found" do
      assert OccurrencePlannings.get_by_poll(999_999) == nil
    end
  end

  describe "list_for_series/2" do
    test "lists occurrence plannings for a series", %{event: event, poll: poll} do
      {:ok, _planning1} =
        OccurrencePlannings.create(%{
          event_id: event.id,
          poll_id: poll.id,
          series_type: "movie",
          series_id: 123
        })

      # Create another event and poll for second planning
      {:ok, event2} =
        Events.create_event(%{
          title: "Test Event 2",
          start_at: DateTime.utc_now() |> DateTime.add(2, :day),
          timezone: "UTC",
          visibility: :private,
          status: :draft
        })

      user = Repo.get_by(EventasaurusApp.Accounts.User, email: "test@example.com")

      {:ok, poll2} =
        Events.create_poll(%{
          event_id: event2.id,
          title: "Test Poll 2",
          poll_type: "occurrence_selection",
          voting_system: "binary",
          created_by_id: user.id
        })

      {:ok, _planning2} =
        OccurrencePlannings.create(%{
          event_id: event2.id,
          poll_id: poll2.id,
          series_type: "movie",
          series_id: 123
        })

      plannings = OccurrencePlannings.list_for_series("movie", 123)

      assert length(plannings) == 2
    end

    test "returns empty list for non-existent series" do
      plannings = OccurrencePlannings.list_for_series("movie", 999_999)

      assert plannings == []
    end
  end

  describe "list_pending/0 and list_finalized/0" do
    test "list_pending/0 returns only pending plannings", %{event: event, poll: poll} do
      {:ok, pending_planning} =
        OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      # Create finalized planning
      {:ok, event2} =
        Events.create_event(%{
          title: "Test Event 2",
          start_at: DateTime.utc_now() |> DateTime.add(2, :day),
          timezone: "UTC",
          visibility: :private,
          status: :draft
        })

      user = Repo.get_by(EventasaurusApp.Accounts.User, email: "test@example.com")

      {:ok, poll2} =
        Events.create_poll(%{
          event_id: event2.id,
          title: "Test Poll 2",
          poll_type: "occurrence_selection",
          voting_system: "binary",
          created_by_id: user.id
        })

      {:ok, finalized_planning} =
        OccurrencePlannings.create(%{event_id: event2.id, poll_id: poll2.id})

      {:ok, _} = OccurrencePlannings.finalize(finalized_planning, 999)

      pending = OccurrencePlannings.list_pending()

      assert length(pending) >= 1
      assert Enum.any?(pending, fn p -> p.id == pending_planning.id end)
      refute Enum.any?(pending, fn p -> p.id == finalized_planning.id end)
    end

    test "list_finalized/0 returns only finalized plannings", %{event: event, poll: poll} do
      {:ok, pending_planning} =
        OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      # Create finalized planning
      {:ok, event2} =
        Events.create_event(%{
          title: "Test Event 2",
          start_at: DateTime.utc_now() |> DateTime.add(2, :day),
          timezone: "UTC",
          visibility: :private,
          status: :draft
        })

      user = Repo.get_by(EventasaurusApp.Accounts.User, email: "test@example.com")

      {:ok, poll2} =
        Events.create_poll(%{
          event_id: event2.id,
          title: "Test Poll 2",
          poll_type: "occurrence_selection",
          voting_system: "binary",
          created_by_id: user.id
        })

      {:ok, finalized_planning} =
        OccurrencePlannings.create(%{event_id: event2.id, poll_id: poll2.id})

      {:ok, _} = OccurrencePlannings.finalize(finalized_planning, 999)

      finalized = OccurrencePlannings.list_finalized()

      assert length(finalized) >= 1
      refute Enum.any?(finalized, fn p -> p.id == pending_planning.id end)
      assert Enum.any?(finalized, fn p -> p.id == finalized_planning.id end)
    end
  end

  describe "update/2" do
    test "updates occurrence planning", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      assert {:ok, updated} =
               OccurrencePlannings.update(planning, %{
                 series_type: "movie",
                 series_id: 456
               })

      assert updated.series_type == "movie"
      assert updated.series_id == 456
    end
  end

  describe "finalize/2 and finalized?/1" do
    test "finalizes occurrence planning", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      refute OccurrencePlannings.finalized?(planning)

      assert {:ok, finalized} = OccurrencePlannings.finalize(planning, 999)
      assert finalized.event_plan_id == 999
      assert OccurrencePlannings.finalized?(finalized)
    end

    test "finalized?/1 returns true when event_plan_id is set", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})
      {:ok, finalized} = OccurrencePlannings.finalize(planning, 123)

      assert OccurrencePlannings.finalized?(finalized)
    end

    test "finalized?/1 returns false when event_plan_id is nil", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      refute OccurrencePlannings.finalized?(planning)
    end
  end

  describe "has_occurrence_planning?/1" do
    test "returns true when event has occurrence planning", %{event: event, poll: poll} do
      {:ok, _planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      assert OccurrencePlannings.has_occurrence_planning?(event.id)
    end

    test "returns false when event has no occurrence planning" do
      refute OccurrencePlannings.has_occurrence_planning?(999_999)
    end
  end

  describe "delete/1" do
    test "deletes occurrence planning", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      assert {:ok, deleted} = OccurrencePlannings.delete(planning)
      assert deleted.id == planning.id
      assert OccurrencePlannings.get(planning.id) == nil
    end
  end

  describe "preload/2" do
    test "preloads associations", %{event: event, poll: poll} do
      {:ok, planning} = OccurrencePlannings.create(%{event_id: event.id, poll_id: poll.id})

      preloaded = OccurrencePlannings.preload(planning, [:event, :poll])

      assert preloaded.event.id == event.id
      assert preloaded.poll.id == poll.id
    end
  end
end
