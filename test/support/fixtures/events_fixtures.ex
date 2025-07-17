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
    # Convert keyword list to map if necessary
    attrs =
      case attrs do
        list when is_list(list) -> Enum.into(list, %{})
        map when is_map(map) -> map
      end

    # Extract organizers if provided (handle both atom and string keys)
    organizers = Map.get(attrs, :organizers, Map.get(attrs, "organizers", []))

    # Create a user for the event if no organizers provided (handle both atom and string keys)
    user =
      case organizers do
        [] ->
          Map.get_lazy(attrs, :user, fn ->
            Map.get_lazy(attrs, "user", fn ->
              EventasaurusApp.AccountsFixtures.user_fixture()
            end)
          end)

        [first_organizer | _] ->
          first_organizer
      end

    # Convert all keys to strings for consistency
    string_attrs =
      attrs
      # Remove user and organizers from attrs since they're not part of event schema
      |> Map.drop([:user, "user", :organizers, "organizers"])
      |> Enum.reduce(%{}, fn {k, v}, acc ->
        Map.put(acc, to_string(k), v)
      end)

    # Merge with default string-key attributes
    final_attrs =
      Map.merge(
        %{
          "title" => "Test Event #{System.unique_integer([:positive])}",
          "description" => "A test event description",
          "start_at" => ~U[2024-12-01 10:00:00Z],
          "timezone" => "UTC",
          "slug" => "test-event-#{System.unique_integer([:positive])}",
          "status" => :confirmed,
          "taxation_type" => "ticketless"
        },
        string_attrs
      )

    {:ok, event} = Events.create_event(final_attrs)

    # Add the organizers to the event
    organizers_to_add =
      case organizers do
        [] -> [user]
        list -> list
      end

    for organizer <- organizers_to_add do
      {:ok, _} = Events.add_user_to_event(event, organizer)
    end

    # Use the same approach as get_event! to ensure consistency with the API
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
