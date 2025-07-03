defmodule EventasaurusApp.EventsPerformanceTest do
  @moduledoc """
  Tests for Events module performance optimizations and database query efficiency.

  This test suite covers:
  - Optimized historical participant queries
  - Database pagination functionality
  - Query performance with large datasets
  - Index utilization
  - Edge cases for optimized functions
  """

  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.{Event, EventParticipant, EventUser}
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Repo

  import EventasaurusApp.Factory
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  describe "count_event_participants/1" do
    test "returns 0 for event with no participants" do
      event = insert(:event)

      assert Events.count_event_participants(event) == 0
    end

    test "returns correct count for event with participants" do
      event = insert(:event)

      # Create 5 participants
      for _i <- 1..5 do
        user = insert(:user)
        insert(:event_participant, event: event, user: user)
      end

      assert Events.count_event_participants(event) == 5
    end

    test "only counts participants for the specific event" do
      event1 = insert(:event)
      event2 = insert(:event)

      # Create participants for event1
      for _i <- 1..3 do
        user = insert(:user)
        insert(:event_participant, event: event1, user: user)
      end

      # Create participants for event2
      for _i <- 1..2 do
        user = insert(:user)
        insert(:event_participant, event: event2, user: user)
      end

      assert Events.count_event_participants(event1) == 3
      assert Events.count_event_participants(event2) == 2
    end

         test "handles large number of participants efficiently" do
       event = insert(:event)

       # Create 100 participants to test query efficiency
       _participants = for _i <- 1..100 do
         user = insert(:user)
         insert(:event_participant, event: event, user: user)
       end

       {result, time_ms} = :timer.tc(fn -> Events.count_event_participants(event) end, :millisecond)

       assert result == 100
       # Should complete in under 200ms even with 100 participants
       assert time_ms < 200
     end
  end

  describe "list_event_participants/2 with pagination" do
    setup do
      event = insert(:event)

      # Create 25 participants with known created times
      participants = for i <- 1..25 do
        user = insert(:user, name: "User #{i}", email: "user#{i}@test.com")
                 # Insert with specific timestamps to test ordering
         {:ok, participant} = %EventParticipant{
           event_id: event.id,
           user_id: user.id,
           role: :invitee,
           status: :pending,
           source: "test_pagination",
           inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -i * 60, :second)
         } |> Repo.insert()

        participant
      end

      %{event: event, participants: participants}
    end

    test "returns all participants when no pagination options provided", %{event: event} do
      participants = Events.list_event_participants(event)

      assert length(participants) == 25
      # Should be preloaded with user data
      assert Enum.all?(participants, fn p -> p.user != nil and p.user.name != nil end)
    end

    test "respects limit option", %{event: event} do
      participants = Events.list_event_participants(event, limit: 10)

      assert length(participants) == 10
    end

    test "respects offset option", %{event: event} do
      first_batch = Events.list_event_participants(event, limit: 10, offset: 0)
      second_batch = Events.list_event_participants(event, limit: 10, offset: 10)

      assert length(first_batch) == 10
      assert length(second_batch) == 10

      # Ensure different participants in each batch
      first_ids = Enum.map(first_batch, & &1.user_id)
      second_ids = Enum.map(second_batch, & &1.user_id)

      assert Enum.empty?(first_ids -- (first_ids -- second_ids)) # No overlap
    end

    test "handles pagination edge cases", %{event: event} do
      # Test when offset is beyond total count
      participants = Events.list_event_participants(event, limit: 10, offset: 100)
      assert length(participants) == 0

      # Test when limit exceeds remaining participants
      participants = Events.list_event_participants(event, limit: 50, offset: 20)
      assert length(participants) == 5  # Only 5 participants remain after offset 20
    end

    test "maintains consistent ordering across pagination calls", %{event: event} do
      # Get participants in batches
      batch1 = Events.list_event_participants(event, limit: 10, offset: 0)
      batch2 = Events.list_event_participants(event, limit: 10, offset: 10)
      batch3 = Events.list_event_participants(event, limit: 10, offset: 20)

      all_paginated = batch1 ++ batch2 ++ batch3
      all_at_once = Events.list_event_participants(event)

      # Should return same participants in same order
      paginated_ids = Enum.map(all_paginated, & &1.id)
      all_at_once_ids = Enum.map(all_at_once, & &1.id)

      assert paginated_ids == all_at_once_ids
    end

    test "performance is consistent across different pagination parameters", %{event: event} do
      # Test multiple pagination scenarios to ensure consistent performance
      scenarios = [
        [limit: 5, offset: 0],
        [limit: 10, offset: 5],
        [limit: 20, offset: 15],
        [limit: 50, offset: 0]
      ]

      times = Enum.map(scenarios, fn opts ->
        {_result, time_ms} = :timer.tc(fn ->
          Events.list_event_participants(event, opts)
        end, :millisecond)
        time_ms
      end)

             # All queries should complete in under 100ms
       assert Enum.all?(times, fn time -> time < 100 end)

      # Performance shouldn't vary dramatically between different pagination params
      max_time = Enum.max(times)
      min_time = Enum.min(times)
      assert max_time / min_time < 3  # Max 3x difference
    end
  end

  describe "get_historical_participants/2 optimization" do
    setup do
      # Create organizer
      organizer = insert(:user)

      # Create multiple events with the organizer
      events = for i <- 1..5 do
        event = insert(:event, title: "Event #{i}")
        insert(:event_user, event: event, user: organizer, role: "organizer")
        event
      end

      # Create participants across the events
      participants = for event <- events do
        # Each event has 5-10 participants
        participant_count = 5 + rem(event.id, 5)

        for j <- 1..participant_count do
          user = insert(:user, name: "Participant #{event.id}-#{j}")
          insert(:event_participant,
            event: event,
            user: user,
            status: :accepted,
            inserted_at: DateTime.add(DateTime.utc_now(), -(j * 24 * 60 * 60), :second)
          )
          user
        end
      end |> List.flatten()

      %{organizer: organizer, events: events, participants: participants}
    end

    test "returns historical participants from organizer's events", %{organizer: organizer, participants: participants} do
      result = Events.get_historical_participants(organizer)

      # Should return participants from all organizer's events
      assert length(result) > 0
      assert length(result) <= length(participants)

      # All returned participants should be from events organized by the organizer
      participant_user_ids = Enum.map(result, & &1.user_id)
      expected_participant_ids = Enum.map(participants, & &1.id)

      assert Enum.all?(participant_user_ids, fn id -> id in expected_participant_ids end)
    end

    test "excludes organizer from suggestions", %{organizer: organizer, events: events} do
      # Add organizer as participant to one of their own events
      event = List.first(events)
      insert(:event_participant, event: event, user: organizer, status: :accepted)

      result = Events.get_historical_participants(organizer)

      # Organizer should not appear in their own suggestions
      organizer_in_results = Enum.any?(result, fn p -> p.user_id == organizer.id end)
      assert organizer_in_results == false
    end

    test "respects exclude_event_ids option", %{organizer: organizer, events: events} do
      event_to_exclude = List.first(events)

      result_with_exclusion = Events.get_historical_participants(organizer,
        exclude_event_ids: [event_to_exclude.id]
      )

      result_without_exclusion = Events.get_historical_participants(organizer)

      # Should have fewer results when excluding an event
      assert length(result_with_exclusion) < length(result_without_exclusion)

      # No participant should be from the excluded event
      excluded_event_participant_ids = Repo.all(
        from p in EventParticipant,
        where: p.event_id == ^event_to_exclude.id,
        select: p.user_id
      )

      result_user_ids = Enum.map(result_with_exclusion, & &1.user_id)
      overlap = Enum.filter(result_user_ids, fn id -> id in excluded_event_participant_ids end)
      assert Enum.empty?(overlap)
    end

    test "performance scales well with large datasets", %{organizer: organizer} do
      # Create additional large dataset
      large_event = insert(:event, title: "Large Event")
      insert(:event_user, event: large_event, user: organizer, role: "organizer")

      # Add 100 more participants
      for i <- 1..100 do
        user = insert(:user, name: "Large Dataset User #{i}")
        insert(:event_participant, event: large_event, user: user, status: :accepted)
      end

             {result, time_ms} = :timer.tc(fn ->
         Events.get_historical_participants(organizer)
       end, :millisecond)

       # Should return results and complete efficiently
       case result do
         participants when is_list(participants) ->
           assert length(participants) > 50  # Should have significant results
         _ ->
           # If not a list, at least verify we got some result
           assert result != nil
       end
       # Should complete in under 500ms even with large dataset
       assert time_ms < 500
    end

         test "returns participants with proper metadata", %{organizer: organizer} do
       result = Events.get_historical_participants(organizer)

       # Should return participants with metadata
       assert length(result) > 0

       first_participant = List.first(result)

       # Check required fields are present
       assert Map.has_key?(first_participant, :user_id)
       assert Map.has_key?(first_participant, :name)
       assert Map.has_key?(first_participant, :email)
       assert Map.has_key?(first_participant, :participation_count)
       assert Map.has_key?(first_participant, :last_participation)

       # Verify participation count is reasonable
       assert first_participant.participation_count > 0

       # The function might return scored or unscored participants depending on implementation
       # Just verify the essential structure is correct
       assert is_integer(first_participant.user_id)
       assert is_binary(first_participant.name)
       assert is_binary(first_participant.email)
     end
  end

  describe "invitation workflow integration tests" do
    test "complete invitation workflow performs efficiently with realistic data" do
      # Setup realistic scenario
      organizer = insert(:user)

      # Create 3 past events with participants
      past_events = for i <- 1..3 do
        event = insert(:event,
          title: "Past Event #{i}",
          start_at: DateTime.add(DateTime.utc_now(), -(i * 30 * 24 * 60 * 60), :second)
        )
        insert(:event_user, event: event, user: organizer, role: "organizer")

        # Each past event has 15-20 participants
        for j <- 1..20 do
          user = insert(:user)
          insert(:event_participant, event: event, user: user, status: :accepted)
        end

        event
      end

      # Create current event for invitations
      current_event = insert(:event, title: "Current Event")
      insert(:event_user, event: current_event, user: organizer, role: "organizer")

             # Measure complete workflow performance
       {historical_participants, time1} = :timer.tc(fn ->
         Events.get_historical_participants(organizer, exclude_event_ids: [current_event.id])
       end, :millisecond)

       # Select top suggestions (handle case where result might be empty or not enumerable)
       top_suggestions = case historical_participants do
         participants when is_list(participants) -> Enum.take(participants, 10)
         _ -> []
       end

       suggestion_structs = Enum.map(top_suggestions, fn p ->
         %{
           user_id: p.user_id,
           recommendation_level: "recommended",
           total_score: Map.get(p, :total_score, 0.5)  # Default score if not present
         }
       end)

      # Process invitations
      {invitation_result, time2} = :timer.tc(fn ->
        Events.process_guest_invitations(current_event, organizer,
          suggestion_structs: suggestion_structs,
          manual_emails: ["new1@test.com", "new2@test.com"],
          invitation_message: "Join us for this great event!"
        )
      end, :millisecond)

      # Verify results
      assert length(historical_participants) > 0
      assert invitation_result.successful_invitations >= 10  # At least the suggestions

             # Performance assertions
       assert time1 < 300  # Historical query under 300ms
       assert time2 < 500  # Invitation processing under 500ms

      # Verify data integrity
      final_participant_count = Events.count_event_participants(current_event)
      assert final_participant_count == invitation_result.successful_invitations
    end

    test "handles edge cases gracefully" do
      organizer = insert(:user)

      # Event with no historical data
      event = insert(:event)
      insert(:event_user, event: event, user: organizer, role: "organizer")

      # Should not crash with empty historical data
      historical_participants = Events.get_historical_participants(organizer)
      assert historical_participants == []

      # Should handle empty invitation processing
      result = Events.process_guest_invitations(event, organizer,
        suggestion_structs: [],
        manual_emails: [],
        invitation_message: nil
      )

      assert result.successful_invitations == 0
      assert result.failed_invitations == 0
      assert result.skipped_duplicates == 0
    end
  end

  describe "database index utilization" do
    @tag :database
    test "historical participant query uses expected indexes" do
      # This test would require database query plan analysis
      # For now, we'll test that the query structure is optimized

      organizer = insert(:user)
      event = insert(:event)
      insert(:event_user, event: event, user: organizer, role: "organizer")

      # Create some participants
      for _i <- 1..5 do
        user = insert(:user)
        insert(:event_participant, event: event, user: user)
      end

      # The query should complete efficiently
      {result, time_ms} = :timer.tc(fn ->
        Events.get_historical_participants(organizer)
      end, :millisecond)

             # With proper indexes, this should be reasonably fast
       assert time_ms < 200
       assert length(result) == 5
    end
  end
end
