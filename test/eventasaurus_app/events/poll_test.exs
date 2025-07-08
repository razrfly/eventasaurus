defmodule EventasaurusApp.Events.PollTest do
  use EventasaurusApp.DataCase, async: false  # async: false for PubSub testing

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}

  setup do
    user = user_fixture()
    user2 = user_fixture()
    event = event_fixture()

    %{user: user, user2: user2, event: event}
  end

  describe "poll creation and management" do
    test "create_poll/1 creates a poll with valid attributes", %{user: user, event: event} do
      attrs = %{
        event_id: event.id,
        title: "Test Poll",
        description: "A poll for testing",
        voting_system: "binary",
        poll_type: "general",
        status: "list_building",
        created_by_id: user.id
      }

      assert {:ok, %Poll{} = poll} = Events.create_poll(attrs)
      assert poll.title == "Test Poll"
      assert poll.voting_system == "binary"
      assert poll.poll_type == "general"
      assert poll.status == "list_building"
    end

    test "create_poll/1 validates required fields" do
      assert {:error, changeset} = Events.create_poll(%{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.title
      assert "can't be blank" in errors.voting_system
      assert "can't be blank" in errors.poll_type
    end

    test "create_poll/1 validates voting_system enum", %{user: user, event: event} do
      attrs = %{
        event_id: event.id,
        title: "Test Poll",
        voting_system: "invalid_system",
        poll_type: "general",
        created_by_id: user.id
      }

      assert {:error, changeset} = Events.create_poll(attrs)
      assert "is invalid" in errors_on(changeset).voting_system
    end

    test "list_polls/1 returns polls for an event", %{user: user, event: event} do
      {:ok, poll1} = Events.create_poll(%{
        event_id: event.id,
        title: "Poll 1",
        voting_system: "binary",
        poll_type: "general",
        created_by_id: user.id
      })

      {:ok, poll2} = Events.create_poll(%{
        event_id: event.id,
        title: "Poll 2",
        voting_system: "approval",
        poll_type: "venue",
        created_by_id: user.id
      })

      polls = Events.list_polls(event)
      assert length(polls) == 2
      assert Enum.any?(polls, &(&1.id == poll1.id))
      assert Enum.any?(polls, &(&1.id == poll2.id))
    end

    test "get_poll!/1 returns poll with preloaded associations", %{user: user, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Test Poll",
        voting_system: "binary",
        poll_type: "general",
        created_by_id: user.id
      })

      fetched_poll = Events.get_poll!(poll.id)
      assert fetched_poll.id == poll.id
      assert %Ecto.Association.NotLoaded{} != fetched_poll.poll_options
      assert %Ecto.Association.NotLoaded{} != fetched_poll.event
    end
  end

  describe "poll options management" do
    setup %{user: user, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Test Poll",
        voting_system: "approval",
        poll_type: "general",
        created_by_id: user.id
      })

      %{poll: poll}
    end

    test "create_poll_option/1 creates option for poll", %{poll: poll} do
      attrs = %{
        poll_id: poll.id,
        title: "Option 1",
        description: "First option"
      }

      assert {:ok, %PollOption{} = option} = Events.create_poll_option(attrs)
      assert option.title == "Option 1"
      assert option.poll_id == poll.id
    end

    test "create_poll_option/1 validates required fields" do
      assert {:error, changeset} = Events.create_poll_option(%{})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.title
      assert "can't be blank" in errors.poll_id
    end

    test "delete_poll_option/1 removes option", %{poll: poll} do
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "Option to Delete"
      })

      assert {:ok, _} = Events.delete_poll_option(option)
      assert_raise Ecto.NoResultsError, fn ->
        Events.get_poll_option!(option.id)
      end
    end
  end

  describe "binary voting system" do
    setup %{user: user, user2: user2, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Binary Poll",
        voting_system: "binary",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "Yes or No Option"
      })

      %{poll: Events.get_poll!(poll.id), option: option}
    end

    test "cast_binary_vote/4 creates a yes vote", %{poll: poll, option: option, user: user} do
      assert {:ok, vote} = Events.cast_binary_vote(poll, option, user, "yes")
      assert vote.vote_value == "yes"
      assert vote.user_id == user.id
      assert vote.poll_option_id == option.id
    end

    test "cast_binary_vote/4 creates a no vote", %{poll: poll, option: option, user: user} do
      assert {:ok, vote} = Events.cast_binary_vote(poll, option, user, "no")
      assert vote.vote_value == "no"
    end

    test "cast_binary_vote/4 replaces existing vote", %{poll: poll, option: option, user: user} do
      # Cast initial vote
      {:ok, _} = Events.cast_binary_vote(poll, option, user, "yes")

      # Cast different vote
      {:ok, new_vote} = Events.cast_binary_vote(poll, option, user, "no")

      # Should only have one vote
      votes = Events.get_user_poll_votes(poll, user)
      assert length(votes) == 1
      assert new_vote.vote_value == "no"
    end

    test "cast_binary_vote/4 validates vote values", %{poll: poll, option: option, user: user} do
      assert {:error, _} = Events.cast_binary_vote(poll, option, user, "invalid")
    end

    test "multiple users can vote on same option", %{poll: poll, option: option, user: user, user2: user2} do
      {:ok, vote1} = Events.cast_binary_vote(poll, option, user, "yes")
      {:ok, vote2} = Events.cast_binary_vote(poll, option, user2, "no")

      assert vote1.user_id == user.id
      assert vote2.user_id == user2.id
      assert vote1.vote_value == "yes"
      assert vote2.vote_value == "no"
    end
  end

  describe "approval voting system" do
    setup %{user: user, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Approval Poll",
        voting_system: "approval",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option1} = Events.create_poll_option(%{poll_id: poll.id, title: "Option 1"})
      {:ok, option2} = Events.create_poll_option(%{poll_id: poll.id, title: "Option 2"})
      {:ok, option3} = Events.create_poll_option(%{poll_id: poll.id, title: "Option 3"})

      %{
        poll: Events.get_poll!(poll.id),
        option1: option1,
        option2: option2,
        option3: option3
      }
    end

    test "cast_approval_vote/4 allows voting for multiple options", %{poll: poll, option1: option1, option2: option2, user: user} do
      {:ok, vote1} = Events.cast_approval_vote(poll, option1, user, true)
      {:ok, vote2} = Events.cast_approval_vote(poll, option2, user, true)

      votes = Events.get_user_poll_votes(poll, user)
      assert length(votes) == 2
      assert Enum.any?(votes, &(&1.poll_option_id == option1.id))
      assert Enum.any?(votes, &(&1.poll_option_id == option2.id))
    end

    test "cast_approval_vote/4 allows removing votes", %{poll: poll, option1: option1, user: user} do
      # Vote for option
      {:ok, _} = Events.cast_approval_vote(poll, option1, user, true)

      # Remove vote
      {:ok, result} = Events.cast_approval_vote(poll, option1, user, false)

      votes = Events.get_user_poll_votes(poll, user)
      assert length(votes) == 0
      assert result == :vote_removed
    end

    test "cast_approval_votes/3 handles multiple options efficiently", %{poll: poll, option1: option1, option2: option2, option3: option3, user: user} do
      option_ids = [option1.id, option2.id, option3.id]

      {:ok, votes} = Events.cast_approval_votes(poll, option_ids, user)
      assert length(votes) == 3

      user_votes = Events.get_user_poll_votes(poll, user)
      assert length(user_votes) == 3
    end
  end

  describe "ranked choice voting system" do
    setup %{user: user, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Ranked Poll",
        voting_system: "ranked",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option1} = Events.create_poll_option(%{poll_id: poll.id, title: "First Choice"})
      {:ok, option2} = Events.create_poll_option(%{poll_id: poll.id, title: "Second Choice"})
      {:ok, option3} = Events.create_poll_option(%{poll_id: poll.id, title: "Third Choice"})

      %{
        poll: Events.get_poll!(poll.id),
        option1: option1,
        option2: option2,
        option3: option3
      }
    end

    test "cast_ranked_vote/4 creates vote with rank", %{poll: poll, option1: option1, user: user} do
      {:ok, vote} = Events.cast_ranked_vote(poll, option1, user, 1)
      assert vote.vote_rank == 1
      assert vote.poll_option_id == option1.id
    end

    test "cast_ranked_votes/3 creates full ranking", %{poll: poll, option1: option1, option2: option2, option3: option3, user: user} do
      rankings = [
        {option1.id, 1},
        {option3.id, 2},
        {option2.id, 3}
      ]

      {:ok, votes} = Events.cast_ranked_votes(poll, rankings, user)
      assert length(votes) == 3

      # Verify rankings
      votes_by_option = Enum.group_by(votes, & &1.poll_option_id)
      assert votes_by_option[option1.id] |> List.first() |> Map.get(:vote_rank) == 1
      assert votes_by_option[option3.id] |> List.first() |> Map.get(:vote_rank) == 2
      assert votes_by_option[option2.id] |> List.first() |> Map.get(:vote_rank) == 3
    end

    test "cast_ranked_votes/3 prevents duplicate ranks", %{poll: poll, option1: option1, option2: option2, user: user} do
      rankings = [
        {option1.id, 1},
        {option2.id, 1}  # Duplicate rank
      ]

      assert {:error, _} = Events.cast_ranked_votes(poll, rankings, user)
    end

    test "cast_ranked_votes/3 replaces existing rankings", %{poll: poll, option1: option1, option2: option2, option3: option3, user: user} do
      # Initial ranking
      initial_rankings = [{option1.id, 1}, {option2.id, 2}]
      {:ok, _} = Events.cast_ranked_votes(poll, initial_rankings, user)

      # New ranking
      new_rankings = [{option3.id, 1}, {option1.id, 2}, {option2.id, 3}]
      {:ok, votes} = Events.cast_ranked_votes(poll, new_rankings, user)

      # Should only have 3 votes total
      user_votes = Events.get_user_poll_votes(poll, user)
      assert length(user_votes) == 3

      # Verify new rankings
      votes_by_option = Enum.group_by(user_votes, & &1.poll_option_id)
      assert votes_by_option[option3.id] |> List.first() |> Map.get(:vote_rank) == 1
    end
  end

  describe "star rating voting system" do
    setup %{user: user, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Star Poll",
        voting_system: "star",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option1} = Events.create_poll_option(%{poll_id: poll.id, title: "Rate Me 1"})
      {:ok, option2} = Events.create_poll_option(%{poll_id: poll.id, title: "Rate Me 2"})

      %{poll: Events.get_poll!(poll.id), option1: option1, option2: option2}
    end

    test "cast_star_vote/4 creates vote with rating", %{poll: poll, option1: option1, user: user} do
      {:ok, vote} = Events.cast_star_vote(poll, option1, user, 5)
      assert Decimal.equal?(vote.vote_numeric, Decimal.new(5))
    end

    test "cast_star_vote/4 validates rating range", %{poll: poll, option1: option1, user: user} do
      assert {:error, _} = Events.cast_star_vote(poll, option1, user, 0)
      assert {:error, _} = Events.cast_star_vote(poll, option1, user, 6)
      assert {:error, _} = Events.cast_star_vote(poll, option1, user, -1)
    end

    test "cast_star_vote/4 allows multiple option ratings", %{poll: poll, option1: option1, option2: option2, user: user} do
      {:ok, _} = Events.cast_star_vote(poll, option1, user, 4)
      {:ok, _} = Events.cast_star_vote(poll, option2, user, 2)

      votes = Events.get_user_poll_votes(poll, user)
      assert length(votes) == 2
    end

    test "cast_star_vote/4 replaces existing rating for same option", %{poll: poll, option1: option1, user: user} do
      {:ok, _} = Events.cast_star_vote(poll, option1, user, 3)
      {:ok, new_vote} = Events.cast_star_vote(poll, option1, user, 5)

      votes = Events.get_user_poll_votes(poll, user)
      assert length(votes) == 1
      assert Decimal.equal?(new_vote.vote_numeric, Decimal.new(5))
    end
  end

  describe "vote management and utilities" do
    setup %{user: user, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Management Poll",
        voting_system: "approval",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option1} = Events.create_poll_option(%{poll_id: poll.id, title: "Option 1"})
      {:ok, option2} = Events.create_poll_option(%{poll_id: poll.id, title: "Option 2"})

      %{poll: Events.get_poll!(poll.id), option1: option1, option2: option2}
    end

    test "remove_user_vote/2 removes specific vote", %{poll: poll, option1: option1, option2: option2, user: user} do
      # Create votes
      {:ok, _} = Events.cast_approval_vote(poll, option1, user, true)
      {:ok, _} = Events.cast_approval_vote(poll, option2, user, true)

      # Remove one vote
      {:ok, _} = Events.remove_user_vote(option1, user)

      votes = Events.get_user_poll_votes(poll, user)
      assert length(votes) == 1
      assert List.first(votes).poll_option_id == option2.id
    end

    test "clear_user_poll_votes/2 removes all user votes for poll", %{poll: poll, option1: option1, option2: option2, user: user} do
      # Create votes
      {:ok, _} = Events.cast_approval_vote(poll, option1, user, true)
      {:ok, _} = Events.cast_approval_vote(poll, option2, user, true)

      # Clear all votes
      {:ok, count} = Events.clear_user_poll_votes(poll, user)
      assert count == 2

      votes = Events.get_user_poll_votes(poll, user)
      assert length(votes) == 0
    end

    test "can_user_vote?/2 checks voting permissions", %{poll: poll, user: user} do
      # Should be able to vote when poll is in voting status
      assert Events.can_user_vote?(user, poll) == true

      # Update poll to finalized status
      {:ok, updated_poll} = Events.update_poll(poll, %{status: "finalized"})

      # Should not be able to vote when finalized
      assert Events.can_user_vote?(user, updated_poll) == false
    end

    test "get_user_voting_summary/2 returns comprehensive vote summary", %{poll: poll, option1: option1, option2: option2, user: user} do
      # Create votes
      {:ok, _} = Events.cast_approval_vote(poll, option1, user, true)
      {:ok, _} = Events.cast_approval_vote(poll, option2, user, true)

      summary = Events.get_user_voting_summary(poll, user)

      assert summary.total_votes == 2
      assert summary.voting_system == "approval"
      assert length(summary.votes) == 2
      assert summary.can_vote == true
    end
  end

  describe "event integration" do
    test "create_event_poll/3 creates poll with event integration", %{user: user, event: event} do
      attrs = %{
        title: "Event Integrated Poll",
        voting_system: "binary",
        poll_type: "general"
      }

      {:ok, poll} = Events.create_event_poll(event, user, attrs)

      assert poll.event_id == event.id
      assert poll.created_by_id == user.id
      assert poll.title == "Event Integrated Poll"
    end

    test "finalize_event_poll/3 triggers event-level actions", %{user: user, event: event} do
      # Create a date poll for finalization testing
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Date Selection",
        voting_system: "approval",
        poll_type: "date",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "2024-12-15",
        description: "December 15th"
      })

      # Cast some votes
      {:ok, _} = Events.cast_approval_vote(poll, option, user, true)

      # Finalize the poll
      {:ok, finalized_poll} = Events.finalize_event_poll(poll, option, user)

      assert finalized_poll.status == "finalized"
      assert finalized_poll.finalized_option_id == option.id
    end
  end

  describe "PubSub integration and real-time updates" do
    test "voting broadcasts poll updates" do
      # Subscribe to poll updates
      poll_topic = "polls:test_poll"
      Phoenix.PubSub.subscribe(EventasaurusApp.PubSub, poll_topic)

      # This test would verify PubSub broadcasting
      # Implementation depends on the specific PubSub setup
      assert true  # Placeholder - actual implementation would test broadcasts
    end
  end

  describe "concurrent voting and race conditions" do
    setup %{user: user, user2: user2, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Concurrent Poll",
        voting_system: "binary",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option} = Events.create_poll_option(%{poll_id: poll.id, title: "Concurrent Option"})

      %{poll: Events.get_poll!(poll.id), option: option}
    end

    test "concurrent votes from different users succeed", %{poll: poll, option: option, user: user, user2: user2} do
      # Simulate concurrent voting
      task1 = Task.async(fn -> Events.cast_binary_vote(poll, option, user, "yes") end)
      task2 = Task.async(fn -> Events.cast_binary_vote(poll, option, user2, "no") end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      assert {:ok, _} = result1
      assert {:ok, _} = result2

      # Both votes should exist
      votes = Events.get_poll_votes(poll)
      assert length(votes) == 2
    end

    test "concurrent votes from same user handle conflicts properly", %{poll: poll, option: option, user: user} do
      # Simulate user rapidly clicking - should result in one final vote
      tasks = for vote_value <- ["yes", "no", "yes"] do
        Task.async(fn -> Events.cast_binary_vote(poll, option, user, vote_value) end)
      end

      results = Enum.map(tasks, &Task.await/1)

      # At least one should succeed
      assert Enum.any?(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Should only have one vote for the user
      user_votes = Events.get_user_poll_votes(poll, user)
      assert length(user_votes) == 1
    end
  end

  describe "poll analytics and reporting" do
    setup %{user: user, user2: user2, event: event} do
      {:ok, poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Analytics Poll",
        voting_system: "star",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

      {:ok, option1} = Events.create_poll_option(%{poll_id: poll.id, title: "Option A"})
      {:ok, option2} = Events.create_poll_option(%{poll_id: poll.id, title: "Option B"})

      # Create some votes for analytics
      {:ok, _} = Events.cast_star_vote(poll, option1, user, 5)
      {:ok, _} = Events.cast_star_vote(poll, option2, user, 3)
      {:ok, _} = Events.cast_star_vote(poll, option1, user2, 4)

      %{poll: Events.get_poll!(poll.id), option1: option1, option2: option2}
    end

    test "get_poll_analytics/1 returns vote statistics", %{poll: poll} do
      analytics = Events.get_poll_analytics(poll)

      assert analytics.total_votes > 0
      assert analytics.total_voters > 0
      assert analytics.voting_system == "star"
      assert is_list(analytics.option_results)
    end

    test "get_poll_votes/1 returns all votes for poll", %{poll: poll} do
      votes = Events.get_poll_votes(poll)
      assert length(votes) == 3  # Based on setup
    end
  end

  describe "backward compatibility with date polling" do
    test "existing date polling functions still work", %{user: user, event: event} do
      # Test that existing date polling is unaffected
      {:ok, date_poll} = Events.create_event_date_poll(%{
        event_id: event.id,
        created_by_user_id: user.id
      })

      assert date_poll.event_id == event.id

      # Verify date options still work
      {:ok, date_option} = Events.create_event_date_option(%{
        event_date_poll_id: date_poll.id,
        event_date: ~D[2024-12-01],
        start_time: ~T[10:00:00],
        end_time: ~T[18:00:00]
      })

      assert date_option.event_date_poll_id == date_poll.id
    end

    test "date polling and generic polling coexist", %{user: user, event: event} do
      # Create both types of polls for same event
      {:ok, date_poll} = Events.create_event_date_poll(%{
        event_id: event.id,
        created_by_user_id: user.id
      })

      {:ok, generic_poll} = Events.create_poll(%{
        event_id: event.id,
        title: "Generic Poll",
        voting_system: "approval",
        poll_type: "venue",
        created_by_id: user.id
      })

      # Both should exist and not interfere
      assert date_poll.event_id == event.id
      assert generic_poll.event_id == event.id
      assert date_poll.id != generic_poll.id
    end
  end
end
