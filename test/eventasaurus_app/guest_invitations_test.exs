defmodule EventasaurusApp.GuestInvitationsTest do
  use ExUnit.Case, async: true
  alias EventasaurusApp.GuestInvitations

  describe "default_config/0" do
    test "returns valid default configuration" do
      config = GuestInvitations.default_config()

      assert config.frequency_weight == 0.6
      assert config.recency_weight == 0.4
      assert config.affinity_weight == 0.0
      assert config.social_weight == 0.0
      assert is_map(config.frequency_thresholds)
      assert is_map(config.recency_thresholds)
    end
  end

  describe "calculate_frequency_score/2" do
    test "scores based on participation count thresholds" do
      config = GuestInvitations.default_config()

      # Test various participation counts
      assert GuestInvitations.calculate_frequency_score(0, config) == 0.0
      assert GuestInvitations.calculate_frequency_score(1, config) == 0.2
      assert GuestInvitations.calculate_frequency_score(2, config) == 0.4
      assert GuestInvitations.calculate_frequency_score(3, config) == 0.6
      assert GuestInvitations.calculate_frequency_score(5, config) == 0.8
      assert GuestInvitations.calculate_frequency_score(10, config) == 1.0
      assert GuestInvitations.calculate_frequency_score(15, config) == 1.0
    end
  end

  describe "calculate_recency_score/2" do
    test "returns 0.0 for nil date" do
      assert GuestInvitations.calculate_recency_score(nil) == 0.0
    end

    test "scores based on days since last participation" do
      now = DateTime.utc_now()
      config = GuestInvitations.default_config()

      # Very recent (within 30 days)
      recent_date = DateTime.add(now, -15 * 24 * 60 * 60, :second)
      assert GuestInvitations.calculate_recency_score(recent_date, config) == 1.0

      # Recent (within 90 days)
      moderate_date = DateTime.add(now, -60 * 24 * 60 * 60, :second)
      assert GuestInvitations.calculate_recency_score(moderate_date, config) == 0.8

      # Old (within 180 days)
      old_date = DateTime.add(now, -120 * 24 * 60 * 60, :second)
      assert GuestInvitations.calculate_recency_score(old_date, config) == 0.6

      # Some (within 365 days)
      some_date = DateTime.add(now, -300 * 24 * 60 * 60, :second)
      assert GuestInvitations.calculate_recency_score(some_date, config) == 0.4

      # Old (within 730 days)
      very_old_date = DateTime.add(now, -600 * 24 * 60 * 60, :second)
      assert GuestInvitations.calculate_recency_score(very_old_date, config) == 0.2

      # Ancient (older than 730 days)
      ancient_date = DateTime.add(now, -1000 * 24 * 60 * 60, :second)
      assert GuestInvitations.calculate_recency_score(ancient_date, config) == 0.1
    end
  end

  describe "score_participant/2" do
    test "calculates total score with default weights" do
      participant = %{
        user_id: 1,
        name: "Test User",
        participation_count: 5,
        last_participation: DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60, :second)
      }

      scored = GuestInvitations.score_participant(participant)

      # Good tier
      assert scored.frequency_score == 0.8
      # Very recent tier (30 days = boundary)
      assert scored.recency_score == 1.0
      # 0.48 + 0.4 = 0.88
      assert scored.total_score == 0.8 * 0.6 + 1.0 * 0.4
      assert Map.has_key?(scored, :scoring_config)
    end
  end

  describe "score_participants/3" do
    test "scores and sorts multiple participants" do
      participants = [
        %{user_id: 1, participation_count: 1, last_participation: nil},
        %{
          user_id: 2,
          participation_count: 10,
          last_participation: DateTime.add(DateTime.utc_now(), -15 * 24 * 60 * 60, :second)
        },
        %{
          user_id: 3,
          participation_count: 3,
          last_participation: DateTime.add(DateTime.utc_now(), -200 * 24 * 60 * 60, :second)
        }
      ]

      scored = GuestInvitations.score_participants(participants)

      # Should be sorted by total_score in descending order
      assert length(scored) == 3
      # Highest score (frequent + recent)
      assert Enum.at(scored, 0).user_id == 2
      # Medium score
      assert Enum.at(scored, 1).user_id == 3
      # Lowest score
      assert Enum.at(scored, 2).user_id == 1
    end

    test "respects limit option" do
      participants = [
        %{user_id: 1, participation_count: 1, last_participation: nil},
        %{user_id: 2, participation_count: 10, last_participation: DateTime.utc_now()},
        %{user_id: 3, participation_count: 5, last_participation: DateTime.utc_now()}
      ]

      scored = GuestInvitations.score_participants(participants, nil, limit: 2)

      assert length(scored) == 2
    end
  end

  describe "explain_score/1" do
    test "provides detailed scoring explanation" do
      participant = %{
        user_id: 1,
        participation_count: 5,
        last_participation: DateTime.add(DateTime.utc_now(), -45 * 24 * 60 * 60, :second)
      }

      scored = GuestInvitations.score_participant(participant)
      explanation = GuestInvitations.explain_score(scored)

      assert explanation.total_score == scored.total_score
      assert explanation.breakdown.frequency.tier == "good"
      assert explanation.breakdown.recency.tier == "recent"
      # participation_count: 5 → frequency 0.8, 45-day recency → 0.8, total = 0.80 → :highly_recommended
      assert explanation.recommendation == :highly_recommended
    end
  end
end
