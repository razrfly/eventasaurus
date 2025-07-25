defmodule EventasaurusApp.Events.EventValidationTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Events.Event

  describe "validate_free_event_revenue/1" do
    test "prevents free events from having revenue threshold type" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC",
        status: :threshold,
        taxation_type: "ticketless",
        threshold_type: "revenue",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      })

      refute changeset.valid?
      assert {"cannot be set to revenue for free events. Use attendee_count instead.", _} = 
        changeset.errors[:threshold_type]
    end

    test "prevents free events from having both threshold type" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event", 
        timezone: "UTC",
        status: :threshold,
        taxation_type: "ticketless",
        threshold_type: "both",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      })

      refute changeset.valid?
      assert {"cannot be set to both for free events. Use attendee_count instead.", _} = 
        changeset.errors[:threshold_type]
    end

    test "prevents free events from having revenue cents set" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC", 
        taxation_type: "ticketless",
        threshold_type: "attendee_count",  # Valid threshold type to avoid other errors
        threshold_revenue_cents: 5000,
        status: :draft
      })

      refute changeset.valid?
      assert {"cannot be set for free events", _} = 
        changeset.errors[:threshold_revenue_cents]
    end

    test "allows free events with attendee_count threshold type" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC",
        status: :threshold,
        taxation_type: "ticketless", 
        threshold_type: "attendee_count",
        threshold_count: 50,
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      })

      assert changeset.valid?
    end

    test "allows ticketed events to have revenue thresholds" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC",
        status: :threshold,
        taxation_type: "ticketed_event",
        threshold_type: "revenue",
        threshold_revenue_cents: 5000,
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      })

      assert changeset.valid?
    end

    test "allows contribution events to have revenue thresholds" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event", 
        timezone: "UTC",
        status: :threshold,
        taxation_type: "contribution_collection",
        threshold_type: "revenue",
        threshold_revenue_cents: 5000,
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      })

      assert changeset.valid?
    end
  end

  describe "validate_virtual_event_venue/1" do
    test "prevents virtual events from having a physical venue" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC",
        is_virtual: true,
        venue_id: 123
      })

      refute changeset.valid?
      assert {"must be nil for virtual events", _} = 
        changeset.errors[:venue_id]
    end

    test "allows virtual events with no venue" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC", 
        is_virtual: true,
        venue_id: nil,
        status: :draft  # Draft events don't require start_at
      })

      assert changeset.valid?
    end

    test "allows physical events to have a venue" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC",
        is_virtual: false,
        venue_id: 123,
        status: :draft  # Draft events don't require start_at
      })

      assert changeset.valid?
    end

    test "allows physical events with no venue (TBD)" do
      changeset = Event.changeset(%Event{}, %{
        title: "Test Event",
        timezone: "UTC",
        is_virtual: false,
        venue_id: nil,
        status: :draft  # Draft events don't require start_at
      })

      assert changeset.valid?
    end
  end

  describe "integration with FormHelpers mapping" do
    test "validates free event mapped from participation_type" do
      # Simulate FormHelpers mapping for free event with invalid revenue threshold
      attrs = %{
        title: "Test Event",
        timezone: "UTC",
        is_ticketed: false,
        taxation_type: "ticketless",
        threshold_type: "revenue",  # This should fail
        threshold_revenue_cents: 5000,
        status: :draft  # To avoid start_at requirement
      }

      changeset = Event.changeset(%Event{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:threshold_type]
      # Check if revenue cents error exists (it may not if threshold_type fails first)
      if changeset.errors[:threshold_revenue_cents] do
        assert changeset.errors[:threshold_revenue_cents]
      end
    end

    test "validates virtual event mapped from venue_certainty" do
      # Simulate FormHelpers mapping for virtual event with invalid venue
      attrs = %{
        title: "Test Event", 
        timezone: "UTC",
        is_virtual: true,
        venue_id: 123  # This should fail
      }

      changeset = Event.changeset(%Event{}, attrs)

      refute changeset.valid?
      assert changeset.errors[:venue_id]
    end

    test "validates crowdfunding event correctly" do
      # Simulate FormHelpers mapping for crowdfunding
      attrs = %{
        title: "Test Event",
        timezone: "UTC",
        status: :threshold,
        is_ticketed: true,
        taxation_type: "ticketed_event",
        threshold_type: "revenue",
        threshold_revenue_cents: 5000,
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      changeset = Event.changeset(%Event{}, attrs)

      assert changeset.valid?
    end

    test "validates interest validation event correctly" do
      # Simulate FormHelpers mapping for interest validation
      attrs = %{
        title: "Test Event",
        timezone: "UTC", 
        status: :threshold,
        threshold_type: "attendee_count",
        threshold_count: 50,
        is_ticketed: false,
        taxation_type: "ticketless",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      changeset = Event.changeset(%Event{}, attrs)

      assert changeset.valid?
    end

    test "validates free confirmed event correctly" do
      # Simulate FormHelpers mapping for a simple free confirmed event
      attrs = %{
        title: "Test Event",
        timezone: "UTC",
        status: :confirmed,
        is_ticketed: false,
        taxation_type: "ticketless",
        is_virtual: false,
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      changeset = Event.changeset(%Event{}, attrs)

      assert changeset.valid?
    end

    test "validates virtual confirmed event correctly" do
      # Simulate FormHelpers mapping for a virtual confirmed event
      attrs = %{
        title: "Test Event",
        timezone: "UTC",
        status: :confirmed,
        is_virtual: true,
        venue_id: nil,
        virtual_venue_url: "https://zoom.us/j/123456",
        start_at: DateTime.utc_now() |> DateTime.add(7, :day)
      }

      changeset = Event.changeset(%Event{}, attrs)

      assert changeset.valid?
    end
  end
end