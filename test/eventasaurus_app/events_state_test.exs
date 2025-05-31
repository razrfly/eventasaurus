defmodule EventasaurusApp.EventsStateTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.Event

  describe "event state transitions" do
    test "event is created with confirmed state by default" do
      {:ok, event} = Events.create_event(%{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day),
        timezone: "UTC"
      })

      assert event.state == "confirmed"
    end

    test "can transition from confirmed to polling" do
      {:ok, event} = Events.create_event(%{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day),
        timezone: "UTC",
        state: "confirmed"
      })

      {:ok, updated_event} = Events.transition_event_state(event, "polling")
      assert updated_event.state == "polling"
    end

    test "can transition from polling to confirmed" do
      {:ok, event} = Events.create_event(%{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day),
        timezone: "UTC",
        state: "polling"
      })

      {:ok, updated_event} = Events.transition_event_state(event, "confirmed")
      assert updated_event.state == "confirmed"
    end

    test "validates state field only accepts valid states" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day),
        timezone: "UTC",
        state: "invalid_state"
      })

      refute changeset.valid?
      assert "must be one of: confirmed, polling" in errors_on(changeset).state
    end

    test "can_transition_to? returns correct boolean" do
      {:ok, confirmed_event} = Events.create_event(%{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day),
        timezone: "UTC",
        state: "confirmed"
      })

      {:ok, polling_event} = Events.create_event(%{
        title: "Test Event 2",
        start_at: DateTime.utc_now() |> DateTime.add(8, :day),
        timezone: "UTC",
        state: "polling"
      })

      assert Events.can_transition_to?(confirmed_event, "polling")
      assert Events.can_transition_to?(polling_event, "confirmed")
    end

    test "possible_transitions returns correct list" do
      {:ok, confirmed_event} = Events.create_event(%{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day),
        timezone: "UTC",
        state: "confirmed"
      })

      {:ok, polling_event} = Events.create_event(%{
        title: "Test Event 2",
        start_at: DateTime.utc_now() |> DateTime.add(8, :day),
        timezone: "UTC",
        state: "polling"
      })

      assert Events.possible_transitions(confirmed_event) == ["polling"]
      assert Events.possible_transitions(polling_event) == ["confirmed"]
    end
  end
end
