defmodule EventasaurusApp.Events.EventTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events.Event

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public
      }

      changeset = Event.changeset(%Event{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :status) == :confirmed  # Default status
    end

        test "requires title, start_at, timezone, and visibility" do
      changeset = Event.changeset(%Event{}, %{})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert %{title: ["can't be blank"]} = errors
      assert %{start_at: ["can't be blank"]} = errors
      assert %{timezone: ["can't be blank"]} = errors
      # Note: visibility has a default, so it doesn't show as blank
    end

    test "validates status enum values" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :invalid_status
      }

      changeset = Event.changeset(%Event{}, attrs)
      refute changeset.valid?
    end

    test "requires polling_deadline when status is polling" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :polling
      }

      changeset = Event.changeset(%Event{}, attrs)
      refute changeset.valid?
      assert %{polling_deadline: ["is required when status is polling"]} = errors_on(changeset)
    end

    test "requires threshold_count when status is threshold" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :threshold
      }

      changeset = Event.changeset(%Event{}, attrs)
      refute changeset.valid?
      assert %{threshold_count: ["is required when status is threshold"]} = errors_on(changeset)
    end

    test "auto-sets canceled_at when status is canceled" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :canceled
      }

      changeset = Event.changeset(%Event{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :canceled_at) != nil
    end
  end

  describe "state transitions" do
    test "can_transition_to?/2 validates allowed transitions" do
      # From draft
      assert Event.can_transition_to?(:draft, :polling)
      assert Event.can_transition_to?(:draft, :confirmed)
      assert Event.can_transition_to?(:draft, :canceled)
      refute Event.can_transition_to?(:draft, :threshold)

      # From polling
      assert Event.can_transition_to?(:polling, :threshold)
      assert Event.can_transition_to?(:polling, :confirmed)
      assert Event.can_transition_to?(:polling, :canceled)
      refute Event.can_transition_to?(:polling, :draft)

      # From threshold
      assert Event.can_transition_to?(:threshold, :confirmed)
      assert Event.can_transition_to?(:threshold, :canceled)
      refute Event.can_transition_to?(:threshold, :draft)
      refute Event.can_transition_to?(:threshold, :polling)

      # From confirmed
      assert Event.can_transition_to?(:confirmed, :canceled)
      refute Event.can_transition_to?(:confirmed, :draft)
      refute Event.can_transition_to?(:confirmed, :polling)
      refute Event.can_transition_to?(:confirmed, :threshold)

      # From canceled (final state)
      refute Event.can_transition_to?(:canceled, :draft)
      refute Event.can_transition_to?(:canceled, :polling)
      refute Event.can_transition_to?(:canceled, :threshold)
      refute Event.can_transition_to?(:canceled, :confirmed)
    end

    test "possible_transitions/1 returns allowed transitions" do
      assert Enum.sort(Event.possible_transitions(:draft)) == [:canceled, :confirmed, :polling]
      assert Enum.sort(Event.possible_transitions(:polling)) == [:canceled, :confirmed, :threshold]
      assert Enum.sort(Event.possible_transitions(:threshold)) == [:canceled, :confirmed]
      assert Event.possible_transitions(:confirmed) == [:canceled]
      assert Event.possible_transitions(:canceled) == []
    end

    test "transition_to/2 handles status changes with side effects" do
      event = %Event{status: :confirmed, canceled_at: nil}

      {:ok, updated_event} = Event.transition_to(event, :canceled)
      assert updated_event.status == :canceled
      assert updated_event.canceled_at != nil
    end
  end

  describe "status consistency validation" do
    test "allows consistent status and attributes" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :polling,
        polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      changeset = Event.changeset(%Event{}, attrs)
      assert changeset.valid?
    end

    test "rejects inconsistent status and attributes" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        threshold_count: 10  # This should make status :threshold
      }

      changeset = Event.changeset(%Event{}, attrs)
      refute changeset.valid?
      assert %{status: [error_msg]} = errors_on(changeset)
      assert error_msg =~ "does not match inferred status 'threshold'"
    end

    test "allows confirmed status with no special fields" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed
      }

      changeset = Event.changeset(%Event{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset_with_inferred_status/2" do
    test "auto-infers status when not provided" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        threshold_count: 5
      }

      changeset = Event.changeset_with_inferred_status(%Event{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :status) == :threshold
    end

    test "respects explicitly provided status" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed,
        threshold_count: 5
      }

      changeset = Event.changeset_with_inferred_status(%Event{}, attrs)
      # This will be invalid due to inconsistency, but status should remain :confirmed
      assert get_field(changeset, :status) == :confirmed
      refute changeset.valid?
    end

    test "infers canceled status" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        canceled_at: DateTime.utc_now()
      }

      changeset = Event.changeset_with_inferred_status(%Event{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :status) == :canceled
    end

    test "infers polling status" do
      attrs = %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      changeset = Event.changeset_with_inferred_status(%Event{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :status) == :polling
    end
  end

  describe "inferred_status/1" do
    test "returns inferred status for event struct" do
      event = %Event{threshold_count: 10}
      assert Event.inferred_status(event) == :threshold
    end

    test "returns canceled for canceled event" do
      event = %Event{canceled_at: DateTime.utc_now()}
      assert Event.inferred_status(event) == :canceled
    end

    test "returns confirmed for regular event" do
      event = %Event{title: "Regular Event"}
      assert Event.inferred_status(event) == :confirmed
    end
  end

  describe "with_computed_phase/1" do
    test "sets computed_phase virtual field based on event state" do
      # Test planning phase (draft status)
      event = %Event{status: :draft}
      result = Event.with_computed_phase(event)
      assert result.computed_phase == "planning"

      # Test polling phase
      future_deadline = DateTime.utc_now() |> DateTime.add(7, :day)
      event = %Event{status: :polling, polling_deadline: future_deadline}
      result = Event.with_computed_phase(event)
      assert result.computed_phase == "polling"

      # Test confirmed phase
      event = %Event{status: :confirmed}
      result = Event.with_computed_phase(event)
      assert result.computed_phase == "open"

      # Test canceled phase
      event = %Event{status: :canceled, canceled_at: DateTime.utc_now()}
      result = Event.with_computed_phase(event)
      assert result.computed_phase == "canceled"
    end

    test "preserves all other event fields" do
      original_event = %Event{
        id: 123,
        title: "Test Event",
        status: :confirmed,
        start_at: DateTime.utc_now(),
        timezone: "UTC"
      }

      result = Event.with_computed_phase(original_event)

      # Should preserve all original fields
      assert result.id == original_event.id
      assert result.title == original_event.title
      assert result.status == original_event.status
      assert result.start_at == original_event.start_at
      assert result.timezone == original_event.timezone

      # Should add the computed phase
      assert result.computed_phase == "open"
    end
  end

  describe "computed_phase virtual field" do
        test "virtual field is properly defined" do
      # Verify the virtual field exists in the schema
            changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        start_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        timezone: "UTC",
        visibility: :public,
        status: :confirmed  # Use confirmed since that's the inferred status for basic events
      })

      assert changeset.valid?

      # Virtual field should be accessible but not persisted
      event = %Event{status: :confirmed}
      assert Map.has_key?(event, :computed_phase)
      assert event.computed_phase == nil # Not set by default
    end
  end

  describe "ended?/1" do
    test "returns false when ends_at is nil" do
      event = %Event{ends_at: nil}
      assert Event.ended?(event) == false
    end

    test "returns true when event has ended" do
      past_time = ~U[2023-01-01 00:00:00Z]
      event = %Event{ends_at: past_time}
      assert Event.ended?(event) == true
    end

    test "returns false when event has not ended yet" do
      future_time = DateTime.utc_now() |> DateTime.add(24, :hour)
      event = %Event{ends_at: future_time}
      assert Event.ended?(event) == false
    end
  end

  describe "can_sell_tickets?/1" do
    test "returns false for non-confirmed events" do
      event = %Event{status: :draft}
      assert Event.can_sell_tickets?(event) == false

      event = %Event{status: :polling}
      assert Event.can_sell_tickets?(event) == false

      event = %Event{status: :canceled}
      assert Event.can_sell_tickets?(event) == false
    end

    test "returns false for confirmed events without ticketing" do
      # Since EventStateMachine.is_ticketed?/1 returns false by default
      event = %Event{status: :confirmed}
      assert Event.can_sell_tickets?(event) == false
    end
  end

  describe "threshold_met?/1" do
    test "delegates to EventStateMachine.threshold_met?/1" do
      event = %Event{threshold_count: 10}
      # Should return false since default attendee count is 0
      assert Event.threshold_met?(event) == false

      event = %Event{threshold_count: nil}
      assert Event.threshold_met?(event) == false
    end
  end

  describe "polling_ended?/1" do
    test "returns false when polling_deadline is nil" do
      event = %Event{polling_deadline: nil}
      assert Event.polling_ended?(event) == false
    end

    test "returns true when polling deadline has passed" do
      past_deadline = ~U[2023-01-01 00:00:00Z]
      event = %Event{polling_deadline: past_deadline}
      assert Event.polling_ended?(event) == true
    end

    test "returns false when polling deadline is in the future" do
      future_deadline = DateTime.utc_now() |> DateTime.add(7, :day)
      event = %Event{polling_deadline: future_deadline}
      assert Event.polling_ended?(event) == false
    end

    test "handles edge cases around deadline time" do
      # Test with a deadline 1 second in the past
      past_by_one_second = DateTime.utc_now() |> DateTime.add(-1, :second)
      event = %Event{polling_deadline: past_by_one_second}
      assert Event.polling_ended?(event) == true

      # Test with a deadline 1 second in the future
      future_by_one_second = DateTime.utc_now() |> DateTime.add(1, :second)
      event = %Event{polling_deadline: future_by_one_second}
      assert Event.polling_ended?(event) == false
    end
  end

  describe "active_poll?/1" do
    test "returns false for non-polling events" do
      event = %Event{status: :draft}
      assert Event.active_poll?(event) == false

      event = %Event{status: :confirmed}
      assert Event.active_poll?(event) == false

      event = %Event{status: :canceled}
      assert Event.active_poll?(event) == false
    end

    test "returns true for polling events with future deadline" do
      future_deadline = DateTime.utc_now() |> DateTime.add(7, :day)
      event = %Event{status: :polling, polling_deadline: future_deadline}
      assert Event.active_poll?(event) == true
    end

    test "returns false for polling events with past deadline" do
      past_deadline = ~U[2023-01-01 00:00:00Z]
      event = %Event{status: :polling, polling_deadline: past_deadline}
      assert Event.active_poll?(event) == false
    end

    test "returns false for polling events with no deadline" do
      event = %Event{status: :polling, polling_deadline: nil}
      assert Event.active_poll?(event) == false
    end
  end

  describe "with_virtual_flags/1" do
    test "populates all virtual flag fields" do
      event = %Event{
        status: :confirmed,
        ends_at: DateTime.utc_now() |> DateTime.add(24, :hour),
        polling_deadline: nil,
        threshold_count: 10
      }

      result = Event.with_virtual_flags(event)

      # Check that all flags are populated
      assert is_boolean(result.ended?)
      assert is_boolean(result.can_sell_tickets?)
      assert is_boolean(result.threshold_met?)
      assert is_boolean(result.polling_ended?)
      assert is_boolean(result.active_poll?)

      # Check specific values
      assert result.ended? == false  # Future end time
      assert result.can_sell_tickets? == false  # No ticketing enabled
      assert result.threshold_met? == false  # No attendees
      assert result.polling_ended? == false  # No polling deadline
      assert result.active_poll? == false  # Not polling status
    end

    test "preserves all other event fields" do
      original_event = %Event{
        id: 123,
        title: "Test Event",
        status: :confirmed,
        start_at: DateTime.utc_now(),
        timezone: "UTC"
      }

      result = Event.with_virtual_flags(original_event)

      # Should preserve all original fields
      assert result.id == original_event.id
      assert result.title == original_event.title
      assert result.status == original_event.status
      assert result.start_at == original_event.start_at
      assert result.timezone == original_event.timezone
    end
  end

  describe "with_computed_fields/1" do
    test "populates both computed_phase and all virtual flags" do
      event = %Event{
        status: :polling,
        polling_deadline: DateTime.utc_now() |> DateTime.add(7, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(24, :hour)
      }

      result = Event.with_computed_fields(event)

      # Should have computed phase
      assert result.computed_phase == "polling"

      # Should have all virtual flags
      assert is_boolean(result.ended?)
      assert is_boolean(result.can_sell_tickets?)
      assert is_boolean(result.threshold_met?)
      assert is_boolean(result.polling_ended?)
      assert is_boolean(result.active_poll?)

      # Check specific values for polling event
      assert result.ended? == false
      assert result.can_sell_tickets? == false
      assert result.threshold_met? == false
      assert result.polling_ended? == false
      assert result.active_poll? == true  # Active polling
    end
  end

  describe "virtual fields schema" do
    test "virtual flag fields are properly defined" do
      event = %Event{status: :confirmed}

      # Virtual fields should be accessible but not set by default
      assert Map.has_key?(event, :ended?)
      assert Map.has_key?(event, :can_sell_tickets?)
      assert Map.has_key?(event, :threshold_met?)
      assert Map.has_key?(event, :polling_ended?)
      assert Map.has_key?(event, :active_poll?)

      # Should be nil by default
      assert event.ended? == nil
      assert event.can_sell_tickets? == nil
      assert event.threshold_met? == nil
      assert event.polling_ended? == nil
      assert event.active_poll? == nil
    end
  end
end
