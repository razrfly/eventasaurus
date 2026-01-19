defmodule EventasaurusApp.Events.RankedChoiceVotingTest do
  use EventasaurusApp.DataCase
  alias EventasaurusApp.Events.RankedChoiceVoting
  alias EventasaurusApp.Events
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  describe "calculate_irv_winner/1" do
    setup do
      user = user_fixture()
      event = event_fixture(%{creator_id: user.id})

      poll =
        poll_fixture(%{
          event: event,
          user: user,
          title: "Test Ranked Choice Poll",
          voting_system: "ranked",
          poll_type: "generic"
        })

      # Create poll options
      option_a = poll_option_fixture(%{poll: poll, user: user, title: "Option A"})
      option_b = poll_option_fixture(%{poll: poll, user: user, title: "Option B"})
      option_c = poll_option_fixture(%{poll: poll, user: user, title: "Option C"})
      option_d = poll_option_fixture(%{poll: poll, user: user, title: "Option D"})

      %{
        poll: poll,
        options: %{
          a: option_a,
          b: option_b,
          c: option_c,
          d: option_d
        },
        user: user
      }
    end

    test "returns empty results when no votes cast", %{poll: poll} do
      result = RankedChoiceVoting.calculate_irv_winner(poll)

      assert result.winner == nil
      assert result.rounds == []
      assert result.final_percentages == %{}
      assert result.total_voters == 0
      assert result.majority_threshold == 0
    end

    test "determines winner with majority in first round", %{poll: poll, options: options} do
      # Create 5 voters
      voters = for _ <- 1..5, do: user_fixture()

      # 3 voters rank A first (majority)
      for voter <- Enum.take(voters, 3) do
        Events.cast_ranked_vote(poll, voter, options.a.id, 1)
        Events.cast_ranked_vote(poll, voter, options.b.id, 2)
      end

      # 2 voters rank B first
      for voter <- Enum.drop(voters, 3) do
        Events.cast_ranked_vote(poll, voter, options.b.id, 1)
        Events.cast_ranked_vote(poll, voter, options.a.id, 2)
      end

      result = RankedChoiceVoting.calculate_irv_winner(poll)

      assert result.winner.id == options.a.id
      assert result.total_voters == 5
      assert result.majority_threshold == 3
      assert length(result.rounds) == 1

      first_round = hd(result.rounds)
      assert first_round.vote_counts[options.a.id] == 3
      assert first_round.vote_counts[options.b.id] == 2
    end

    test "eliminates lowest candidate and redistributes votes", %{poll: poll, options: options} do
      # Create 7 voters with specific preferences
      voters = for _ <- 1..7, do: user_fixture()

      # 3 voters: A > B > C
      for voter <- Enum.take(voters, 3) do
        Events.cast_ranked_vote(poll, voter, options.a.id, 1)
        Events.cast_ranked_vote(poll, voter, options.b.id, 2)
        Events.cast_ranked_vote(poll, voter, options.c.id, 3)
      end

      # 2 voters: B > C > A
      for voter <- voters |> Enum.drop(3) |> Enum.take(2) do
        Events.cast_ranked_vote(poll, voter, options.b.id, 1)
        Events.cast_ranked_vote(poll, voter, options.c.id, 2)
        Events.cast_ranked_vote(poll, voter, options.a.id, 3)
      end

      # 1 voter: C > A > B
      voter_6 = Enum.at(voters, 5)
      Events.cast_ranked_vote(poll, voter_6, options.c.id, 1)
      Events.cast_ranked_vote(poll, voter_6, options.a.id, 2)
      Events.cast_ranked_vote(poll, voter_6, options.b.id, 3)

      # 1 voter: D > C > B
      voter_7 = Enum.at(voters, 6)
      Events.cast_ranked_vote(poll, voter_7, options.d.id, 1)
      Events.cast_ranked_vote(poll, voter_7, options.c.id, 2)
      Events.cast_ranked_vote(poll, voter_7, options.b.id, 3)

      result = RankedChoiceVoting.calculate_irv_winner(poll)

      # First round: A=3, B=2, C=1, D=1 (no majority, D eliminated)
      # Second round: D's vote goes to C, so A=3, B=2, C=2 (no majority, tie broken by ID)
      # Third round: After elimination, A should win

      assert result.winner.id == options.a.id
      assert result.total_voters == 7
      assert result.majority_threshold == 4
      assert length(result.rounds) >= 2

      # Check that D was eliminated in first round
      first_round = hd(result.rounds)
      assert first_round.eliminated == options.d.id
    end

    test "handles tie-breaking deterministically", %{poll: poll, options: options} do
      # Create 4 voters with tied first preferences
      voters = for _ <- 1..4, do: user_fixture()

      # 2 voters for A
      for voter <- Enum.take(voters, 2) do
        Events.cast_ranked_vote(poll, voter, options.a.id, 1)
        Events.cast_ranked_vote(poll, voter, options.b.id, 2)
      end

      # 2 voters for B
      for voter <- Enum.drop(voters, 2) do
        Events.cast_ranked_vote(poll, voter, options.b.id, 1)
        Events.cast_ranked_vote(poll, voter, options.a.id, 2)
      end

      result = RankedChoiceVoting.calculate_irv_winner(poll)

      # With a tie, the winner should be deterministic (lowest ID wins the tie)
      assert result.winner != nil
      assert result.total_voters == 4
    end

    test "handles exhausted ballots correctly", %{poll: poll, options: options} do
      # Create voters with incomplete rankings
      voters = for _ <- 1..5, do: user_fixture()

      # 2 voters only rank C (will be exhausted after C is eliminated)
      for voter <- Enum.take(voters, 2) do
        Events.cast_ranked_vote(poll, voter, options.c.id, 1)
      end

      # 2 voters rank A > B
      for voter <- voters |> Enum.drop(2) |> Enum.take(2) do
        Events.cast_ranked_vote(poll, voter, options.a.id, 1)
        Events.cast_ranked_vote(poll, voter, options.b.id, 2)
      end

      # 1 voter ranks B > A
      voter_5 = Enum.at(voters, 4)
      Events.cast_ranked_vote(poll, voter_5, options.b.id, 1)
      Events.cast_ranked_vote(poll, voter_5, options.a.id, 2)

      result = RankedChoiceVoting.calculate_irv_winner(poll)

      # After C is eliminated, those 2 ballots are exhausted
      # A should win with 2 votes vs B with 1 vote
      assert result.winner.id == options.a.id
      assert result.total_voters == 5
    end
  end

  describe "get_leaderboard/1" do
    setup do
      user = user_fixture()
      event = event_fixture(%{creator_id: user.id})

      poll =
        poll_fixture(%{
          event: event,
          user: user,
          title: "Test Leaderboard Poll",
          voting_system: "ranked",
          poll_type: "generic"
        })

      option_a = poll_option_fixture(%{poll: poll, user: user, title: "Leader"})
      option_b = poll_option_fixture(%{poll: poll, user: user, title: "Runner Up"})
      option_c = poll_option_fixture(%{poll: poll, user: user, title: "Eliminated"})

      %{poll: poll, options: %{a: option_a, b: option_b, c: option_c}, user: user}
    end

    test "returns empty leaderboard when no votes", %{poll: poll} do
      leaderboard = RankedChoiceVoting.get_leaderboard(poll)
      assert leaderboard == []
    end

    test "returns properly formatted leaderboard entries", %{poll: poll, options: options} do
      # Create voters and votes
      voters = for _ <- 1..5, do: user_fixture()

      # 3 voters for A
      for voter <- Enum.take(voters, 3) do
        Events.cast_ranked_vote(poll, voter, options.a.id, 1)
        Events.cast_ranked_vote(poll, voter, options.b.id, 2)
        Events.cast_ranked_vote(poll, voter, options.c.id, 3)
      end

      # 2 voters for B
      for voter <- Enum.drop(voters, 3) do
        Events.cast_ranked_vote(poll, voter, options.b.id, 1)
        Events.cast_ranked_vote(poll, voter, options.c.id, 2)
      end

      leaderboard = RankedChoiceVoting.get_leaderboard(poll)

      assert length(leaderboard) >= 2

      # Check first entry (winner)
      first_entry = hd(leaderboard)
      assert first_entry.position == 1
      assert first_entry.option.id == options.a.id
      assert first_entry.votes == 3
      assert first_entry.status == :winner
      assert first_entry.eliminated_round == nil

      # Check that all entries have required fields
      for entry <- leaderboard do
        assert Map.has_key?(entry, :position)
        assert Map.has_key?(entry, :option)
        assert Map.has_key?(entry, :votes)
        assert Map.has_key?(entry, :percentage)
        assert Map.has_key?(entry, :status)
        assert Map.has_key?(entry, :eliminated_round)
      end
    end

    test "properly indicates elimination rounds", %{poll: poll, options: options} do
      # Create scenario where C gets eliminated
      voters = for _ <- 1..7, do: user_fixture()

      # 3 for A, 3 for B, 1 for C (C will be eliminated)
      for voter <- Enum.take(voters, 3) do
        Events.cast_ranked_vote(poll, voter, options.a.id, 1)
      end

      for voter <- voters |> Enum.drop(3) |> Enum.take(3) do
        Events.cast_ranked_vote(poll, voter, options.b.id, 1)
      end

      last_voter = List.last(voters)
      Events.cast_ranked_vote(poll, last_voter, options.c.id, 1)
      Events.cast_ranked_vote(poll, last_voter, options.a.id, 2)

      leaderboard = RankedChoiceVoting.get_leaderboard(poll)

      # Find C in the leaderboard
      c_entry = Enum.find(leaderboard, &(&1.option.id == options.c.id))

      assert c_entry.status == :eliminated
      assert c_entry.eliminated_round == 1
      assert c_entry.votes == 1
    end
  end
end
