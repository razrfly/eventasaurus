defmodule EventasaurusApp.EventsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Accounts

  describe "smart registration functions" do
    test "get_user_registration_status/2 returns :not_registered for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert Events.get_user_registration_status(event, user) == :not_registered
    end

    test "get_user_registration_status/2 returns :registered for registered user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert Events.get_user_registration_status(event, user) == :registered
    end

    test "get_user_registration_status/2 returns :cancelled for cancelled user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      assert Events.get_user_registration_status(event, user) == :cancelled
    end

    test "one_click_register/2 creates registration for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert {:ok, participant} = Events.one_click_register(event, user)
      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.status == :pending
      assert participant.source == "one_click_registration"
    end

    test "one_click_register/2 returns error for already registered user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert {:error, :already_registered} = Events.one_click_register(event, user)
    end

    test "one_click_register/2 reactivates cancelled registration" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      assert {:ok, participant} = Events.one_click_register(event, user)
      assert participant.status == :pending
      assert participant.metadata[:reregistered_at]
    end

    test "cancel_user_registration/2 cancels existing registration" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert {:ok, updated_participant} = Events.cancel_user_registration(event, user)
      assert updated_participant.status == :cancelled
    end

    test "cancel_user_registration/2 returns error for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert {:error, :not_registered} = Events.cancel_user_registration(event, user)
    end

    test "reregister_user_for_event/2 reactivates cancelled registration" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :cancelled
      })

      assert {:ok, updated_participant} = Events.reregister_user_for_event(event, user)
      assert updated_participant.status == :pending
      assert updated_participant.metadata[:reregistered_at]
    end

    test "reregister_user_for_event/2 creates new registration for unregistered user" do
      event = event_fixture()
      user = user_fixture()

      assert {:ok, participant} = Events.reregister_user_for_event(event, user)
      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.status == :pending
      assert participant.source == "re_registration"
    end

    test "reregister_user_for_event/2 returns error for already registered user" do
      event = event_fixture()
      user = user_fixture()

      {:ok, _participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending
      })

      assert {:error, :already_registered} = Events.reregister_user_for_event(event, user)
    end
  end

  # Helper functions for creating test data
  defp event_fixture(attrs \\ %{}) do
    {:ok, event} =
      attrs
      |> Enum.into(%{
        title: "Test Event",
        description: "A test event",
        start_at: ~U[2024-01-01 10:00:00Z],
        timezone: "UTC",
        slug: "test-event-#{System.unique_integer([:positive])}"
      })
      |> Events.create_event()

    event
  end

  defp user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "test#{System.unique_integer([:positive])}@example.com",
        name: "Test User",
        supabase_id: "test-supabase-id-#{System.unique_integer([:positive])}"
      })
      |> Accounts.create_user()

    user
  end
end
