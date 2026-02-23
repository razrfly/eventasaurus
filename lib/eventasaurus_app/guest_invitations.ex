defmodule EventasaurusApp.GuestInvitations do
  @moduledoc """
  Guest invitation system with configurable scoring algorithms for participant suggestions.

  This module provides scoring algorithms to prioritize participant suggestions based on:
  - Participation frequency (how often they've attended events)
  - Participation recency (how recently they attended)
  - Event affinity (preference for certain types of events)
  - Social connections (mutual participants in past events)
  """

  @doc """
  Default scoring configuration.
  """
  def default_config do
    %{
      frequency_weight: 0.6,
      recency_weight: 0.4,
      # Future feature
      affinity_weight: 0.0,
      # Future feature
      social_weight: 0.0,
      frequency_thresholds: %{
        # 1.0 score
        excellent: 10,
        # 0.8 score
        good: 5,
        # 0.6 score
        moderate: 3,
        # 0.4 score
        some: 2,
        # 0.2 score
        minimal: 1
      },
      recency_thresholds: %{
        # 1.0 score (within 30 days)
        very_recent: 30,
        # 0.8 score (within 3 months)
        recent: 90,
        # 0.6 score (within 6 months)
        moderate: 180,
        # 0.4 score (within 1 year)
        some: 365,
        # 0.2 score (within 2 years)
        old: 730
        # older than 2 years gets 0.1 score
      }
    }
  end

  @doc """
  Score a single participant based on their participation history.

  ## Parameters
  - participant: Map with participation data (%{participation_count: int, last_participation: DateTime})
  - config: Scoring configuration (defaults to default_config/0)

  ## Returns
  Map with original participant data plus scoring details:
  - frequency_score: 0.0-1.0
  - recency_score: 0.0-1.0
  - total_score: weighted combination of component scores
  """
  def score_participant(participant, config \\ nil) do
    config = config || default_config()

    frequency_score = calculate_frequency_score(participant.participation_count, config)
    recency_score = calculate_recency_score(participant.last_participation, config)

    # For future extensibility
    affinity_score = 0.0
    social_score = 0.0

    total_score =
      frequency_score * config.frequency_weight +
        recency_score * config.recency_weight +
        affinity_score * config.affinity_weight +
        social_score * config.social_weight

    participant
    |> Map.merge(%{
      frequency_score: frequency_score,
      recency_score: recency_score,
      affinity_score: affinity_score,
      social_score: social_score,
      total_score: total_score,
      recommendation_level: get_recommendation(total_score),
      scoring_config: config
    })
  end

  @doc """
  Score multiple participants and sort by total score.

  ## Parameters
  - participants: List of participant maps
  - config: Scoring configuration (optional)
  - opts: Options for sorting and limiting
    - sort_order: :desc (default) or :asc
    - limit: Maximum number of results to return

  ## Returns
  List of scored participants sorted by total_score
  """
  def score_participants(participants, config \\ nil, opts \\ []) do
    config = config || default_config()
    sort_order = Keyword.get(opts, :sort_order, :desc)
    limit = Keyword.get(opts, :limit, nil)

    scored = Enum.map(participants, &score_participant(&1, config))

    sorted =
      case sort_order do
        :desc -> Enum.sort_by(scored, & &1.total_score, :desc)
        :asc -> Enum.sort_by(scored, & &1.total_score, :asc)
      end

    if limit do
      Enum.take(sorted, limit)
    else
      sorted
    end
  end

  @doc """
  Calculate frequency score based on participation count.

  Uses configurable thresholds to determine score tiers.
  Score ranges from 0.0 (no participation) to 1.0 (excellent participation).
  """
  def calculate_frequency_score(participation_count, config \\ nil) do
    config = config || default_config()
    thresholds = config.frequency_thresholds

    cond do
      participation_count >= thresholds.excellent -> 1.0
      participation_count >= thresholds.good -> 0.8
      participation_count >= thresholds.moderate -> 0.6
      participation_count >= thresholds.some -> 0.4
      participation_count >= thresholds.minimal -> 0.2
      true -> 0.0
    end
  end

  @doc """
  Calculate recency score based on last participation date.

  Uses configurable thresholds to determine score tiers.
  Score ranges from 0.0 (never participated) to 1.0 (very recent participation).
  """
  def calculate_recency_score(last_participation, config \\ nil) do
    case last_participation do
      nil ->
        0.0

      date ->
        config = config || default_config()
        thresholds = config.recency_thresholds
        days_ago = DateTime.diff(DateTime.utc_now(), date, :day)

        cond do
          days_ago <= thresholds.very_recent -> 1.0
          days_ago <= thresholds.recent -> 0.8
          days_ago <= thresholds.moderate -> 0.6
          days_ago <= thresholds.some -> 0.4
          days_ago <= thresholds.old -> 0.2
          # Older than 2 years but still some value
          true -> 0.1
        end
    end
  end

  @doc """
  Create a custom scoring configuration.

  ## Parameters
  - opts: Keyword list of configuration overrides
    - frequency_weight: Weight for frequency score (0.0-1.0)
    - recency_weight: Weight for recency score (0.0-1.0)
    - frequency_thresholds: Map of participation count thresholds
    - recency_thresholds: Map of day thresholds

  ## Examples
      # Prioritize recent participation over frequency
      config = create_config(frequency_weight: 0.3, recency_weight: 0.7)

      # Make frequency scoring more generous
      config = create_config(
        frequency_thresholds: %{excellent: 5, good: 3, moderate: 2, some: 1, minimal: 1}
      )
  """
  def create_config(opts \\ []) do
    base_config = default_config()
    opts_map = Enum.into(opts, %{})

    # Simple merge - for nested maps, opts take precedence completely
    updated_config = Map.merge(base_config, opts_map)

    validate_config(updated_config)
  end

  @doc """
  Validate that scoring configuration is valid.

  Ensures weights sum to reasonable values and thresholds are properly ordered.
  """
  def validate_config(config) do
    # Validate weights
    total_weight =
      config.frequency_weight + config.recency_weight +
        config.affinity_weight + config.social_weight

    if total_weight > 1.1 do
      raise ArgumentError, "Total scoring weights exceed 1.0: #{total_weight}"
    end

    # Validate frequency thresholds are in descending order
    freq = config.frequency_thresholds

    unless freq.excellent >= freq.good and
             freq.good >= freq.moderate and
             freq.moderate >= freq.some and
             freq.some >= freq.minimal do
      raise ArgumentError, "Frequency thresholds must be in descending order"
    end

    # Validate recency thresholds are in ascending order (days)
    rec = config.recency_thresholds

    unless rec.very_recent <= rec.recent and
             rec.recent <= rec.moderate and
             rec.moderate <= rec.some and
             rec.some <= rec.old do
      raise ArgumentError,
            "Recency thresholds must be in ascending order (days). Got: #{inspect(rec)}"
    end

    config
  end

  @doc """
  Get scoring explanation for a participant.

  Returns human-readable explanation of how the score was calculated.
  Useful for debugging and UI display.
  """
  def explain_score(scored_participant) do
    p = scored_participant
    config = p.scoring_config || default_config()

    frequency_tier = get_frequency_tier(p.participation_count, config)
    recency_tier = get_recency_tier(p.last_participation, config)

    %{
      total_score: p.total_score,
      breakdown: %{
        frequency: %{
          score: p.frequency_score,
          weight: config.frequency_weight,
          weighted_score: p.frequency_score * config.frequency_weight,
          tier: frequency_tier,
          count: p.participation_count
        },
        recency: %{
          score: p.recency_score,
          weight: config.recency_weight,
          weighted_score: p.recency_score * config.recency_weight,
          tier: recency_tier,
          last_participation: p.last_participation
        }
      },
      recommendation: get_recommendation(p.total_score)
    }
  end

  # Private helper functions

  defp get_frequency_tier(count, config) do
    thresholds = config.frequency_thresholds

    cond do
      count >= thresholds.excellent -> "excellent"
      count >= thresholds.good -> "good"
      count >= thresholds.moderate -> "moderate"
      count >= thresholds.some -> "some"
      count >= thresholds.minimal -> "minimal"
      true -> "none"
    end
  end

  defp get_recency_tier(last_participation, config) do
    case last_participation do
      nil ->
        "never"

      date ->
        thresholds = config.recency_thresholds
        days_ago = DateTime.diff(DateTime.utc_now(), date, :day)

        cond do
          days_ago <= thresholds.very_recent -> "very_recent"
          days_ago <= thresholds.recent -> "recent"
          days_ago <= thresholds.moderate -> "moderate"
          days_ago <= thresholds.some -> "some"
          days_ago <= thresholds.old -> "old"
          true -> "very_old"
        end
    end
  end

  defp get_recommendation(total_score) do
    cond do
      total_score >= 0.7 -> :highly_recommended
      total_score >= 0.4 -> :recommended
      true -> :suggested
    end
  end
end
