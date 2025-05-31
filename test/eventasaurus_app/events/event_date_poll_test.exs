defmodule EventasaurusApp.Events.EventDatePollTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.{Event, EventDatePoll}

  describe "event_date_polls" do
    @valid_attrs %{voting_deadline: ~U[2025-12-25 12:00:00Z]}
    @invalid_attrs %{voting_deadline: ~U[2020-01-01 12:00:00Z]} # Past date

    test "create_event_date_poll/3 creates a poll with valid data" do
      event = insert(:event, state: "polling")
      user = insert(:user)

      assert {:ok, %EventDatePoll{} = poll} = Events.create_event_date_poll(event, user, @valid_attrs)
      assert poll.event_id == event.id
      assert poll.created_by_id == user.id
      assert poll.voting_deadline == @valid_attrs.voting_deadline
      assert poll.finalized_date == nil
    end

    test "create_event_date_poll/3 fails with invalid data" do
      event = insert(:event, state: "polling")
      user = insert(:user)

      assert {:error, %Ecto.Changeset{}} = Events.create_event_date_poll(event, user, @invalid_attrs)
    end

    test "create_event_date_poll/3 fails when event already has a poll" do
      event = insert(:event, state: "polling")
      user = insert(:user)

      # Create first poll
      assert {:ok, _poll} = Events.create_event_date_poll(event, user, @valid_attrs)

      # Try to create second poll for same event
      assert {:error, %Ecto.Changeset{} = changeset} = Events.create_event_date_poll(event, user, @valid_attrs)
      assert "an event can only have one poll" in errors_on(changeset).event_id
    end

    test "get_event_date_poll/1 returns poll for event" do
      poll = insert(:event_date_poll)

      retrieved_poll = Events.get_event_date_poll(poll.event)
      assert retrieved_poll.id == poll.id
      assert retrieved_poll.event
      assert retrieved_poll.created_by
    end

    test "get_event_date_poll/1 returns nil when no poll exists" do
      event = insert(:event)

      assert Events.get_event_date_poll(event) == nil
    end

    test "finalize_event_date_poll/2 updates poll and event" do
      poll = insert(:event_date_poll)
      |> Repo.preload(:event)

      selected_date = Date.utc_today() |> Date.add(14)

      assert {:ok, {updated_poll, updated_event}} = Events.finalize_event_date_poll(poll, selected_date)
      assert updated_poll.finalized_date == selected_date
      assert updated_event.state == "confirmed"
      assert Date.from_iso8601!(Date.to_iso8601(selected_date)) ==
             Date.from_iso8601!(Date.to_iso8601(DateTime.to_date(updated_event.start_at)))
    end

    test "has_active_date_poll?/1 returns true for active poll" do
      poll = insert(:event_date_poll, voting_deadline: DateTime.utc_now() |> DateTime.add(7, :day))

      assert Events.has_active_date_poll?(poll.event) == true
    end

    test "has_active_date_poll?/1 returns false for finalized poll" do
      poll = insert(:finalized_event_date_poll)

      assert Events.has_active_date_poll?(poll.event) == false
    end

    test "has_active_date_poll?/1 returns false when no poll exists" do
      event = insert(:event)

      assert Events.has_active_date_poll?(event) == false
    end

    test "delete_event_date_poll/1 removes poll" do
      poll = insert(:event_date_poll)

      assert {:ok, %EventDatePoll{}} = Events.delete_event_date_poll(poll)
      assert Events.get_event_date_poll(poll.event) == nil
    end
  end

  describe "event_date_poll validations" do
    test "changeset with valid attributes" do
      changeset = EventDatePoll.changeset(%EventDatePoll{}, %{
        event_id: 1,
        created_by_id: 1,
        voting_deadline: DateTime.utc_now() |> DateTime.add(7, :day)
      })

      assert changeset.valid?
    end

    test "changeset requires event_id and created_by_id" do
      changeset = EventDatePoll.changeset(%EventDatePoll{}, %{})

      assert "can't be blank" in errors_on(changeset).event_id
      assert "can't be blank" in errors_on(changeset).created_by_id
    end

    test "changeset validates voting_deadline is in future" do
      changeset = EventDatePoll.changeset(%EventDatePoll{}, %{
        event_id: 1,
        created_by_id: 1,
        voting_deadline: DateTime.utc_now() |> DateTime.add(-1, :day)
      })

      refute changeset.valid?
      assert "must be in the future" in errors_on(changeset).voting_deadline
    end

    test "changeset validates finalized_date is not in past" do
      changeset = EventDatePoll.changeset(%EventDatePoll{}, %{
        event_id: 1,
        created_by_id: 1,
        finalized_date: Date.utc_today() |> Date.add(-1)
      })

      refute changeset.valid?
      assert "cannot be in the past" in errors_on(changeset).finalized_date
    end
  end

  describe "event_date_poll state checks" do
    test "active?/1 returns true for poll without deadline" do
      poll = %EventDatePoll{finalized_date: nil, voting_deadline: nil}
      assert EventDatePoll.active?(poll) == true
    end

    test "active?/1 returns true for poll with future deadline" do
      poll = %EventDatePoll{
        finalized_date: nil,
        voting_deadline: DateTime.utc_now() |> DateTime.add(7, :day)
      }
      assert EventDatePoll.active?(poll) == true
    end

    test "active?/1 returns false for poll with past deadline" do
      poll = %EventDatePoll{
        finalized_date: nil,
        voting_deadline: DateTime.utc_now() |> DateTime.add(-1, :day)
      }
      assert EventDatePoll.active?(poll) == false
    end

    test "active?/1 returns false for finalized poll" do
      poll = %EventDatePoll{
        finalized_date: Date.utc_today(),
        voting_deadline: DateTime.utc_now() |> DateTime.add(7, :day)
      }
      assert EventDatePoll.active?(poll) == false
    end

    test "finalized?/1 returns true when finalized_date is set" do
      poll = %EventDatePoll{finalized_date: Date.utc_today()}
      assert EventDatePoll.finalized?(poll) == true
    end

    test "finalized?/1 returns false when finalized_date is nil" do
      poll = %EventDatePoll{finalized_date: nil}
      assert EventDatePoll.finalized?(poll) == false
    end
  end
end
