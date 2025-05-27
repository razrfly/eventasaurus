defmodule EventasaurusApp.EventsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `EventasaurusApp.Events` context.
  """

  alias EventasaurusApp.Events

  @doc """
  Generate an event.
  """
  def event_fixture(attrs \\ %{}) do
    # Create a user for the event if not provided
    user = Map.get_lazy(attrs, :user, fn ->
      EventasaurusApp.AccountsFixtures.user_fixture()
    end)

    {:ok, event} =
      attrs
      |> Map.delete(:user)  # Remove user from attrs since it's not part of event schema
      |> Enum.into(%{
        title: "Test Event #{System.unique_integer([:positive])}",
        description: "A test event description",
        start_at: ~U[2024-12-01 10:00:00Z],
        timezone: "UTC",
        slug: "test-event-#{System.unique_integer([:positive])}"
      })
      |> Events.create_event()

    # Add the user to the event
    {:ok, _} = Events.add_user_to_event(event, user)

    # Reload the event with users preloaded
    Events.get_event!(event.id)
  end

  @doc """
  Generate an event participant.
  """
  def event_participant_fixture(attrs \\ %{}) do
    event = Map.get_lazy(attrs, :event, fn -> event_fixture() end)
    user = Map.get_lazy(attrs, :user, fn -> EventasaurusApp.AccountsFixtures.user_fixture() end)

    {:ok, participant} =
      attrs
      |> Enum.into(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "test_fixture"
      })
      |> Events.create_event_participant()

    participant
  end
end
