defmodule EventasaurusApp.Events.SimplePollingTest do
  use EventasaurusApp.DataCase, async: true

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events

  describe "basic polling functions" do
    setup do
      user = user_fixture()
      event = event_fixture()
      %{user: user, event: event}
    end

    test "create and manage binary poll", %{user: user, event: event} do
      # Create binary poll
      attrs = %{
        event_id: event.id,
        created_by_id: user.id,
        title: "Should we have pizza?",
        description: "Vote yes or no",
        voting_system: "binary",
        poll_type: "general"
      }

      {:ok, poll} = Events.create_poll(attrs)
      assert poll.voting_system == "binary"
      assert poll.phase == "list_building"
      assert poll.event_id == event.id

      # Add options
      {:ok, option1} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Yes - Pizza sounds great!",
          suggested_by_id: user.id
        })

      {:ok, option2} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "No - Something else",
          suggested_by_id: user.id
        })

      assert option1.poll_id == poll.id
      assert option2.poll_id == poll.id

      # Transition to voting
      {:ok, _voting_poll} = Events.transition_poll_phase(poll, "voting")
      assert voting_poll.phase == "voting"

      # Cast votes
      {:ok, vote1} = Events.cast_binary_vote(option1, user, "yes")
      assert vote1.vote_value == "yes"
      assert vote1.voter_id == user.id

      user2 = user_fixture()
      {:ok, vote2} = Events.cast_binary_vote(option1, user2, "no")
      assert vote2.vote_value == "no"

      # Verify vote retrieval
      user_vote = Events.get_user_poll_vote(option1, user)
      assert user_vote.vote_value == "yes"

      # Test analytics
      analytics = Events.get_poll_analytics(voting_poll)
      assert analytics.voting_system == "binary"
      assert analytics.total_voters == 2
    end

    test "approval voting workflow", %{user: user, event: event} do
      # Create approval poll
      {:ok, poll} =
        Events.create_poll(%{
          event_id: event.id,
          created_by_id: user.id,
          title: "Pick activities",
          voting_system: "approval",
          poll_type: "time"
        })

      # Add options
      {:ok, hiking} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Hiking",
          suggested_by_id: user.id
        })

      {:ok, bowling} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Bowling",
          suggested_by_id: user.id
        })

      {:ok, _voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Cast approval votes (user can select multiple)
      {:ok, _vote1} = Events.cast_approval_vote(hiking, user, %{selected: true})
      {:ok, _vote2} = Events.cast_approval_vote(bowling, user, %{selected: true})

      # Verify user voted for both options
      hiking_votes = Events.list_poll_votes(hiking)
      bowling_votes = Events.list_poll_votes(bowling)

      assert length(hiking_votes) == 1
      assert length(bowling_votes) == 1
      assert hd(hiking_votes).voter_id == user.id
      assert hd(bowling_votes).voter_id == user.id
    end

    test "ranked choice voting workflow", %{user: user, event: event} do
      {:ok, poll} =
        Events.create_poll(%{
          event_id: event.id,
          created_by_id: user.id,
          title: "Movie ranking",
          voting_system: "ranked",
          poll_type: "movie"
        })

      # Add movie options
      movies =
        for title <- ["Matrix", "Inception", "Interstellar"] do
          {:ok, option} =
            Events.create_poll_option(%{
              poll_id: poll.id,
              title: title,
              suggested_by_id: user.id
            })

          option
        end

      {:ok, _voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Cast ranked votes
      Enum.with_index(movies, 1)
      |> Enum.each(fn {movie, rank} ->
        {:ok, vote} = Events.cast_ranked_vote(movie, user, rank)
        assert vote.vote_rank == rank
      end)

      # Verify rankings
      user_votes = Events.list_user_poll_votes(voting_poll, user)
      assert length(user_votes) == 3

      # Check votes are properly ranked
      ranked_votes = Enum.sort_by(user_votes, & &1.vote_rank)
      assert hd(ranked_votes).vote_rank == 1
      assert List.last(ranked_votes).vote_rank == 3
    end

    test "star rating workflow", %{user: user, event: event} do
      {:ok, poll} =
        Events.create_poll(%{
          event_id: event.id,
          created_by_id: user.id,
          title: "Restaurant ratings",
          voting_system: "star",
          poll_type: "restaurant"
        })

      {:ok, restaurant} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Tony's Italian",
          suggested_by_id: user.id
        })

      {:ok, _voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Cast star rating
      {:ok, vote} = Events.cast_star_vote(restaurant, user, 4)
      assert Decimal.equal?(vote.vote_numeric, Decimal.new(4))

      # Cast another user's rating
      user2 = user_fixture()
      {:ok, vote2} = Events.cast_star_vote(restaurant, user2, 5)
      assert Decimal.equal?(vote2.vote_numeric, Decimal.new(5))

      # Test analytics with average
      analytics = Events.get_poll_analytics(voting_poll)
      restaurant_stats = hd(analytics.vote_counts)
      assert restaurant_stats.total_votes == 2
      # (4 + 5) / 2
      assert restaurant_stats.average_score == 4.5
    end

    test "poll finalization", %{user: user, event: event} do
      {:ok, poll} =
        Events.create_poll(%{
          event_id: event.id,
          created_by_id: user.id,
          title: "Final decision",
          voting_system: "binary"
        })

      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Chosen option",
          suggested_by_id: user.id
        })

      {:ok, _voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Finalize poll with chosen option
      {:ok, final_poll} = Events.finalize_poll(voting_poll, [option.id])

      assert final_poll.phase == "closed"
      assert option.id in final_poll.finalized_option_ids
      assert final_poll.finalized_date != nil
    end

    test "vote management functions", %{user: user, event: event} do
      {:ok, poll} =
        Events.create_poll(%{
          event_id: event.id,
          created_by_id: user.id,
          title: "Test poll",
          voting_system: "approval"
        })

      {:ok, option} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Test option",
          suggested_by_id: user.id
        })

      {:ok, _voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Cast vote
      {:ok, vote} = Events.cast_approval_vote(option, user, %{selected: true})
      assert vote != nil

      # Remove user vote
      {:ok, _} = Events.remove_user_vote(option, user)

      # Verify vote removed
      assert Events.get_user_poll_vote(option, user) == nil
      assert Events.list_poll_votes(option) == []

      # Cast vote again for clearing test
      {:ok, _} = Events.cast_approval_vote(option, user, %{selected: true})

      # Clear all votes for poll
      {:ok, deleted_count} = Events.clear_all_poll_votes(poll.id)
      assert deleted_count == 1
      assert Events.list_poll_votes(option) == []
    end
  end
end
