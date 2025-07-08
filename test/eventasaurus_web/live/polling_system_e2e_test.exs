defmodule EventasaurusWeb.PollingSystemE2ETest do
  use EventasaurusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.{Poll, PollOption}

  @binary_poll_attrs %{
    title: "Should we have pizza?",
    description: "Vote yes or no for pizza",
    voting_system: "binary",
    poll_type: "general"
  }

  @approval_poll_attrs %{
    title: "Pick your favorite activities",
    description: "Select all activities you'd enjoy",
    voting_system: "approval",
    poll_type: "activity"
  }

  @ranked_poll_attrs %{
    title: "Rank the movie options",
    description: "Order these movies by preference",
    voting_system: "ranked",
    poll_type: "movie"
  }

  @star_poll_attrs %{
    title: "Rate these restaurants",
    description: "Give each restaurant 1-5 stars",
    voting_system: "star",
    poll_type: "restaurant"
  }

  describe "Complete Polling System Workflow" do
    setup do
      user = user_fixture()
      event = event_fixture()

      %{user: user, event: event}
    end

    test "binary poll complete workflow", %{user: user, event: event} do
      # 1. Create binary poll
      poll_attrs = Map.merge(@binary_poll_attrs, %{
        event_id: event.id,
        created_by_id: user.id
      })

      {:ok, poll} = Events.create_poll(poll_attrs)
      assert poll.voting_system == "binary"
      assert poll.phase == "list_building"

      # 2. Add poll options
      {:ok, option1} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "Yes - Pizza sounds great!",
        suggested_by_id: user.id
      })

      {:ok, option2} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "No - Let's try something else",
        suggested_by_id: user.id
      })

      # 3. Transition to voting phase
      {:ok, voting_poll} = Events.transition_poll_phase(poll, "voting")
      assert voting_poll.phase == "voting"

      # 4. Cast binary votes
      {:ok, _vote1} = Events.cast_binary_vote(option1, user, "yes")

      # Create another user for diverse voting
      user2 = user_fixture()
      {:ok, _vote2} = Events.cast_binary_vote(option1, user2, "no")
      {:ok, _vote3} = Events.cast_binary_vote(option2, user2, "yes")

      # 5. Verify vote counts
      analytics = Events.get_poll_analytics(voting_poll)
      assert analytics.total_voters >= 2
      assert length(analytics.vote_counts) == 2

      # 6. Finalize poll
      {:ok, final_poll} = Events.finalize_poll(voting_poll, [option1.id])
      assert final_poll.phase == "closed"
      assert option1.id in final_poll.finalized_option_ids
    end

    test "approval voting complete workflow", %{user: user, event: event} do
      # Create approval poll
      poll_attrs = Map.merge(@approval_poll_attrs, %{
        event_id: event.id,
        created_by_id: user.id
      })

      {:ok, poll} = Events.create_poll(poll_attrs)

      # Add multiple options
      options = for title <- ["Hiking", "Mini Golf", "Bowling", "Escape Room"] do
        {:ok, option} = Events.create_poll_option(%{
          poll_id: poll.id,
          title: title,
          suggested_by_id: user.id
        })
        option
      end

      # Transition to voting
      {:ok, voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Cast approval votes (multiple selections)
      user2 = user_fixture()

      # User 1 votes for hiking and bowling
      Events.cast_approval_vote(Enum.at(options, 0), user, %{selected: true})
      Events.cast_approval_vote(Enum.at(options, 2), user, %{selected: true})

      # User 2 votes for mini golf and escape room
      Events.cast_approval_vote(Enum.at(options, 1), user2, %{selected: true})
      Events.cast_approval_vote(Enum.at(options, 3), user2, %{selected: true})

      # Verify analytics
      analytics = Events.get_poll_analytics(voting_poll)
      assert analytics.voting_system == "approval"
      assert analytics.total_voters == 2

      # Each user voted for 2 options, so total votes should be 4
      total_votes = analytics.vote_counts |> Enum.map(& &1.total_votes) |> Enum.sum()
      assert total_votes == 4
    end

    test "ranked choice voting complete workflow", %{user: user, event: event} do
      # Create ranked poll
      poll_attrs = Map.merge(@ranked_poll_attrs, %{
        event_id: event.id,
        created_by_id: user.id
      })

      {:ok, poll} = Events.create_poll(poll_attrs)

      # Add movie options
      movie_titles = ["The Matrix", "Inception", "Interstellar", "Blade Runner"]
      options = for title <- movie_titles do
        {:ok, option} = Events.create_poll_option(%{
          poll_id: poll.id,
          title: title,
          suggested_by_id: user.id
        })
        option
      end

      {:ok, voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Cast ranked votes
      user2 = user_fixture()

      # User 1 ranking: Matrix(1), Inception(2), Interstellar(3), Blade Runner(4)
      Enum.with_index(options, 1)
      |> Enum.each(fn {option, rank} ->
        Events.cast_ranked_vote(option, user, rank)
      end)

      # User 2 ranking: Inception(1), Matrix(2), Blade Runner(3), Interstellar(4)
      rankings = [2, 1, 4, 3]  # Different preference order
      Enum.zip(options, rankings)
      |> Enum.each(fn {option, rank} ->
        Events.cast_ranked_vote(option, user2, rank)
      end)

      # Verify analytics show ranking distribution
      analytics = Events.get_poll_analytics(voting_poll)
      assert analytics.voting_system == "ranked"
      assert analytics.total_voters == 2

      # Each option should have exactly 2 votes (one from each voter)
      Enum.each(analytics.vote_counts, fn vote_count ->
        assert vote_count.total_votes == 2
      end)
    end

    test "star rating complete workflow", %{user: user, event: event} do
      # Create star rating poll
      poll_attrs = Map.merge(@star_poll_attrs, %{
        event_id: event.id,
        created_by_id: user.id
      })

      {:ok, poll} = Events.create_poll(poll_attrs)

      # Add restaurant options
      restaurants = ["Tony's Italian", "Sushi Palace", "BBQ Junction", "Vegan Delights"]
      options = for name <- restaurants do
        {:ok, option} = Events.create_poll_option(%{
          poll_id: poll.id,
          title: name,
          suggested_by_id: user.id
        })
        option
      end

      {:ok, voting_poll} = Events.transition_poll_phase(poll, "voting")

      # Cast star ratings
      user2 = user_fixture()

      # User 1 ratings: 5, 4, 3, 2
      ratings1 = [5, 4, 3, 2]
      Enum.zip(options, ratings1)
      |> Enum.each(fn {option, rating} ->
        Events.cast_star_vote(option, user, rating)
      end)

      # User 2 ratings: 4, 5, 4, 3
      ratings2 = [4, 5, 4, 3]
      Enum.zip(options, ratings2)
      |> Enum.each(fn {option, rating} ->
        Events.cast_star_vote(option, user2, rating)
      end)

      # Verify analytics include star ratings
      analytics = Events.get_poll_analytics(voting_poll)
      assert analytics.voting_system == "star"
      assert analytics.total_voters == 2

      # Verify average scores are calculated
      Enum.each(analytics.vote_counts, fn vote_count ->
        assert vote_count.total_votes == 2
        assert is_number(vote_count.average_score)
        assert vote_count.average_score >= 1.0
        assert vote_count.average_score <= 5.0
      end)
    end

    test "poll moderation features", %{user: user, event: event} do
      # Create poll with multiple options
      {:ok, poll} = Events.create_poll(Map.merge(@approval_poll_attrs, %{
        event_id: event.id,
        created_by_id: user.id
      }))

      {:ok, option1} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "Good option",
        suggested_by_id: user.id
      })

      {:ok, option2} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "Inappropriate option",
        suggested_by_id: user.id
      })

      # Test vote clearing
      user2 = user_fixture()
      Events.cast_approval_vote(option1, user, %{selected: true})
      Events.cast_approval_vote(option2, user2, %{selected: true})

      # Clear all votes for the poll
      {:ok, deleted_count} = Events.clear_all_poll_votes(poll.id)
      assert deleted_count == 2

      # Verify votes are cleared
      assert Events.list_poll_votes(option1) == []
      assert Events.list_poll_votes(option2) == []

      # Test removing individual votes
      Events.cast_approval_vote(option1, user, %{selected: true})
      {:ok, _} = Events.remove_user_vote(option1, user)
      assert Events.list_poll_votes(option1) == []
    end

    test "event-poll integration workflow", %{user: user, event: event} do
      # Test event-poll integration functions
      {:ok, poll} = Events.create_event_poll(event, user, @binary_poll_attrs)

      assert poll.event_id == event.id
      assert poll.created_by_id == user.id

      # Add options and finalize through event workflow
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "Event Pizza Option",
        suggested_by_id: user.id
      })

      {:ok, final_poll} = Events.finalize_event_poll(poll, [option.id], user)
      assert final_poll.phase == "closed"
    end

    test "poll analytics and statistics", %{user: user, event: event} do
      # Create multiple polls for comprehensive stats
      {:ok, binary_poll} = Events.create_poll(Map.merge(@binary_poll_attrs, %{
        event_id: event.id,
        created_by_id: user.id
      }))

      {:ok, approval_poll} = Events.create_poll(Map.merge(@approval_poll_attrs, %{
        event_id: event.id,
        created_by_id: user.id
      }))

      # Test event poll statistics
      stats = Events.get_event_poll_stats(event)

      assert stats.total_polls == 2
      assert stats.active_polls == 2  # Both in list_building phase
      assert stats.polls_by_type["general"] == 1
      assert stats.polls_by_type["activity"] == 1
      assert stats.polls_by_phase["list_building"] == 2
    end

    test "real-time updates and PubSub broadcasting", %{user: user, event: event} do
      # Test that poll operations broadcast properly
      topic = "polls:#{event.id}"
      EventasaurusWeb.Endpoint.subscribe(topic)

      {:ok, poll} = Events.create_event_poll(event, user, @binary_poll_attrs)

      # Should receive poll creation broadcast
      assert_receive %Phoenix.Socket.Broadcast{
        topic: ^topic,
        event: "poll_created",
        payload: %{poll: ^poll}
      }

      # Test vote broadcasting
      {:ok, option} = Events.create_poll_option(%{
        poll_id: poll.id,
        title: "Test option",
        suggested_by_id: user.id
      })

      {:ok, _voting_poll} = Events.transition_poll_phase(poll, "voting")
      {:ok, _vote} = Events.cast_binary_vote(option, user, "yes")

      # Should receive vote update broadcast
      assert_receive %Phoenix.Socket.Broadcast{
        topic: ^topic,
        event: "vote_cast"
      }
    end
  end
end
