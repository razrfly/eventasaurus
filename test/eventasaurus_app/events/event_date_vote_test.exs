defmodule EventasaurusApp.Events.EventDateVoteTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.EventDateVote

  describe "event_date_votes" do
    setup do
      user = insert(:user)
      option = insert(:event_date_option)
      %{user: user, option: option}
    end

    test "create_event_date_vote/3 creates a vote with valid data", %{option: option, user: user} do
      assert {:ok, %EventDateVote{} = vote} = Events.create_event_date_vote(option, user, :yes)
      assert vote.event_date_option_id == option.id
      assert vote.user_id == user.id
      assert vote.vote_type == :yes
    end

    test "create_event_date_vote/3 works with all vote types", %{option: option, user: _user} do
      # Test with different users to avoid unique constraint
      user1 = insert(:user)
      user2 = insert(:user)
      user3 = insert(:user)

      assert {:ok, vote1} = Events.create_event_date_vote(option, user1, :yes)
      assert vote1.vote_type == :yes

      assert {:ok, vote2} = Events.create_event_date_vote(option, user2, :if_need_be)
      assert vote2.vote_type == :if_need_be

      assert {:ok, vote3} = Events.create_event_date_vote(option, user3, :no)
      assert vote3.vote_type == :no
    end

    test "create_event_date_vote/3 prevents duplicate votes from same user", %{option: option, user: user} do
      # Create first vote
      assert {:ok, _vote} = Events.create_event_date_vote(option, user, :yes)

      # Try to create duplicate
      assert {:error, %Ecto.Changeset{} = changeset} = Events.create_event_date_vote(option, user, :no)
      assert "user has already voted for this date option" in errors_on(changeset).event_date_option_id
    end

    test "get_event_date_vote!/1 returns vote with preloaded associations", %{option: option, user: user} do
      {:ok, vote} = Events.create_event_date_vote(option, user, :yes)

      retrieved_vote = Events.get_event_date_vote!(vote.id)
      assert retrieved_vote.id == vote.id
      assert retrieved_vote.event_date_option.id == option.id
      assert retrieved_vote.user.id == user.id
    end

    test "get_user_vote_for_option/2 finds user's vote for option", %{option: option, user: user} do
      {:ok, vote} = Events.create_event_date_vote(option, user, :yes)

      found_vote = Events.get_user_vote_for_option(option, user)
      assert found_vote.id == vote.id
      assert found_vote.vote_type == :yes
    end

    test "get_user_vote_for_option/2 returns nil when no vote exists", %{option: option, user: user} do
      assert Events.get_user_vote_for_option(option, user) == nil
    end

    test "list_votes_for_date_option/1 returns all votes for option", %{option: option} do
      user1 = insert(:user)
      user2 = insert(:user)
      user3 = insert(:user)

      {:ok, _vote1} = Events.create_event_date_vote(option, user1, :yes)
      {:ok, _vote2} = Events.create_event_date_vote(option, user2, :if_need_be)
      {:ok, _vote3} = Events.create_event_date_vote(option, user3, :no)

      votes = Events.list_votes_for_date_option(option)
      assert length(votes) == 3
      assert Enum.all?(votes, fn vote -> vote.event_date_option_id == option.id end)
    end

    test "cast_vote/3 creates new vote when none exists", %{option: option, user: user} do
      assert {:ok, %EventDateVote{} = vote} = Events.cast_vote(option, user, :yes)
      assert vote.vote_type == :yes
    end

    test "cast_vote/3 updates existing vote", %{option: option, user: user} do
      # Create initial vote
      {:ok, original_vote} = Events.create_event_date_vote(option, user, :yes)

      # Update vote
      assert {:ok, %EventDateVote{} = updated_vote} = Events.cast_vote(option, user, :no)
      assert updated_vote.id == original_vote.id
      assert updated_vote.vote_type == :no
    end

    test "update_event_date_vote/2 updates vote", %{option: option, user: user} do
      {:ok, vote} = Events.create_event_date_vote(option, user, :yes)

      assert {:ok, updated_vote} = Events.update_event_date_vote(vote, %{vote_type: :if_need_be})
      assert updated_vote.vote_type == :if_need_be
    end

    test "delete_event_date_vote/1 removes vote", %{option: option, user: user} do
      {:ok, vote} = Events.create_event_date_vote(option, user, :yes)

      assert {:ok, %EventDateVote{}} = Events.delete_event_date_vote(vote)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event_date_vote!(vote.id) end
    end

    test "remove_user_vote/2 removes user's vote for option", %{option: option, user: user} do
      {:ok, _vote} = Events.create_event_date_vote(option, user, :yes)

      assert {:ok, %EventDateVote{}} = Events.remove_user_vote(option, user)
      assert Events.get_user_vote_for_option(option, user) == nil
    end

    test "remove_user_vote/2 returns ok when no vote exists", %{option: option, user: user} do
      assert {:ok, :no_vote_found} = Events.remove_user_vote(option, user)
    end

    test "user_has_voted?/2 correctly identifies if user has voted", %{option: option, user: user} do
      assert Events.user_has_voted?(option, user) == false

      {:ok, _vote} = Events.create_event_date_vote(option, user, :yes)
      assert Events.user_has_voted?(option, user) == true
    end
  end

  describe "vote tallies and analytics" do
    setup do
      poll = insert(:event_date_poll)
      option = insert(:event_date_option, %{event_date_poll: poll})
      %{poll: poll, option: option}
    end

    test "get_date_option_vote_tally/1 calculates correct tally", %{option: option} do
      # Create votes with different types
      user1 = insert(:user)
      user2 = insert(:user)
      user3 = insert(:user)
      user4 = insert(:user)

      {:ok, _vote1} = Events.create_event_date_vote(option, user1, :yes)
      {:ok, _vote2} = Events.create_event_date_vote(option, user2, :yes)
      {:ok, _vote3} = Events.create_event_date_vote(option, user3, :if_need_be)
      {:ok, _vote4} = Events.create_event_date_vote(option, user4, :no)

      tally = Events.get_date_option_vote_tally(option)

      assert tally.yes == 2
      assert tally.if_need_be == 1
      assert tally.no == 1
      assert tally.total == 4
      assert tally.score == 2.5  # (2 * 1.0) + (1 * 0.5) + (1 * 0.0)
      assert tally.percentage == 62.5  # (2.5 / 4.0) * 100
    end

    test "get_date_option_vote_tally/1 handles no votes", %{option: option} do
      tally = Events.get_date_option_vote_tally(option)

      assert tally.yes == 0
      assert tally.if_need_be == 0
      assert tally.no == 0
      assert tally.total == 0
      assert tally.score == 0.0
      assert tally.percentage == 0.0
    end

    test "list_votes_for_poll/1 returns votes across all options", %{poll: poll} do
      option1 = insert(:event_date_option, %{event_date_poll: poll})
      option2 = insert(:event_date_option, %{event_date_poll: poll})

      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, _vote1} = Events.create_event_date_vote(option1, user1, :yes)
      {:ok, _vote2} = Events.create_event_date_vote(option2, user2, :no)

      votes = Events.list_votes_for_poll(poll)
      assert length(votes) == 2
    end

    test "list_user_votes_for_poll/2 returns user's votes for poll", %{poll: poll} do
      option1 = insert(:event_date_option, %{event_date_poll: poll})
      option2 = insert(:event_date_option, %{event_date_poll: poll})

      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, _vote1} = Events.create_event_date_vote(option1, user1, :yes)
      {:ok, _vote2} = Events.create_event_date_vote(option2, user1, :no)
      {:ok, _vote3} = Events.create_event_date_vote(option1, user2, :if_need_be)

      user1_votes = Events.list_user_votes_for_poll(poll, user1)
      assert length(user1_votes) == 2
      assert Enum.all?(user1_votes, fn vote -> vote.user_id == user1.id end)

      user2_votes = Events.list_user_votes_for_poll(poll, user2)
      assert length(user2_votes) == 1
      assert hd(user2_votes).user_id == user2.id
    end

    test "get_poll_vote_tallies/1 returns tallies sorted by score", %{poll: _poll} do
      # Create a fresh poll for this test to avoid interference
      fresh_poll = insert(:event_date_poll)
      option1 = insert(:event_date_option, %{event_date_poll: fresh_poll})
      option2 = insert(:event_date_option, %{event_date_poll: fresh_poll})

      user1 = insert(:user)
      user2 = insert(:user)
      user3 = insert(:user)

      # option1: 2 yes votes (score: 2.0)
      {:ok, _vote1} = Events.create_event_date_vote(option1, user1, :yes)
      {:ok, _vote2} = Events.create_event_date_vote(option1, user2, :yes)

      # option2: 1 if_need_be vote (score: 0.5)
      {:ok, _vote3} = Events.create_event_date_vote(option2, user3, :if_need_be)

      tallies = Events.get_poll_vote_tallies(fresh_poll)
      assert length(tallies) == 2

      # Should be sorted by score descending
      [first, second] = tallies
      assert first.option.id == option1.id
      assert first.tally.score == 2.0
      assert second.option.id == option2.id
      assert second.tally.score == 0.5
    end
  end

  describe "event_date_vote validations" do
    test "changeset with valid attributes" do
      changeset = EventDateVote.changeset(%EventDateVote{}, %{
        event_date_option_id: 1,
        user_id: 1,
        vote_type: :yes
      })

      assert changeset.valid?
    end

    test "changeset requires all fields" do
      changeset = EventDateVote.changeset(%EventDateVote{}, %{})

      assert "can't be blank" in errors_on(changeset).event_date_option_id
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).vote_type
    end

    test "changeset validates vote_type inclusion" do
      changeset = EventDateVote.changeset(%EventDateVote{}, %{
        event_date_option_id: 1,
        user_id: 1,
        vote_type: :invalid
      })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).vote_type
    end

    test "changeset accepts all valid vote types" do
      for vote_type <- [:yes, :if_need_be, :no] do
        changeset = EventDateVote.changeset(%EventDateVote{}, %{
          event_date_option_id: 1,
          user_id: 1,
          vote_type: vote_type
        })

        assert changeset.valid?
      end
    end
  end

  describe "event_date_vote helper functions" do
    test "positive?/1 correctly identifies positive votes" do
      yes_vote = %EventDateVote{vote_type: :yes}
      if_need_be_vote = %EventDateVote{vote_type: :if_need_be}
      no_vote = %EventDateVote{vote_type: :no}

      assert EventDateVote.positive?(yes_vote) == true
      assert EventDateVote.positive?(if_need_be_vote) == true
      assert EventDateVote.positive?(no_vote) == false
    end

    test "negative?/1 correctly identifies negative votes" do
      yes_vote = %EventDateVote{vote_type: :yes}
      if_need_be_vote = %EventDateVote{vote_type: :if_need_be}
      no_vote = %EventDateVote{vote_type: :no}

      assert EventDateVote.negative?(yes_vote) == false
      assert EventDateVote.negative?(if_need_be_vote) == false
      assert EventDateVote.negative?(no_vote) == true
    end

    test "vote_type_display/1 returns human readable strings" do
      yes_vote = %EventDateVote{vote_type: :yes}
      if_need_be_vote = %EventDateVote{vote_type: :if_need_be}
      no_vote = %EventDateVote{vote_type: :no}

      assert EventDateVote.vote_type_display(yes_vote) == "Yes"
      assert EventDateVote.vote_type_display(if_need_be_vote) == "If needed"
      assert EventDateVote.vote_type_display(no_vote) == "No"
    end

    test "vote_score/1 returns correct numeric scores" do
      yes_vote = %EventDateVote{vote_type: :yes}
      if_need_be_vote = %EventDateVote{vote_type: :if_need_be}
      no_vote = %EventDateVote{vote_type: :no}

      assert EventDateVote.vote_score(yes_vote) == 1.0
      assert EventDateVote.vote_score(if_need_be_vote) == 0.5
      assert EventDateVote.vote_score(no_vote) == 0.0
    end

    test "vote_types/0 returns all possible vote types" do
      assert EventDateVote.vote_types() == [:yes, :if_need_be, :no]
    end

    test "vote_type_options/0 returns form options" do
      options = EventDateVote.vote_type_options()
      assert options == [{"Yes", :yes}, {"If needed", :if_need_be}, {"No", :no}]
    end
  end
end
