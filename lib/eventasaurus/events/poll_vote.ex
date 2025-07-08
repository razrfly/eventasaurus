defmodule EventasaurusApp.Events.PollVote do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Events.PollOption
  alias EventasaurusApp.Accounts.User

  schema "poll_votes" do
    field :vote_value, :string
    field :vote_numeric, :decimal
    field :vote_rank, :integer
    field :voted_at, :utc_datetime

    belongs_to :poll_option, PollOption
    belongs_to :voter, User, foreign_key: :voter_id

    timestamps()
  end

  @doc false
  def changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [:vote_value, :vote_numeric, :vote_rank, :voted_at, :poll_option_id, :voter_id])
    |> validate_required([:poll_option_id, :voter_id])
    |> validate_vote_fields()
    |> put_voted_at()
    |> foreign_key_constraint(:poll_option_id)
    |> foreign_key_constraint(:voter_id)
    |> unique_constraint([:poll_option_id, :voter_id],
         message: "You have already voted for this option")
  end

  @doc """
  Creates a changeset for creating a binary vote (yes/no).
  """
  def binary_vote_changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [:vote_value, :poll_option_id, :voter_id])
    |> validate_required([:vote_value, :poll_option_id, :voter_id])
    |> validate_inclusion(:vote_value, ~w(yes no))
    |> put_voted_at()
    |> foreign_key_constraint(:poll_option_id)
    |> foreign_key_constraint(:voter_id)
    |> unique_constraint([:poll_option_id, :voter_id],
         message: "You have already voted for this option")
  end

  @doc """
  Creates a changeset for creating an approval vote (selected/not selected).
  """
  def approval_vote_changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [:vote_value, :poll_option_id, :voter_id])
    |> validate_required([:vote_value, :poll_option_id, :voter_id])
    |> validate_inclusion(:vote_value, ~w(selected))
    |> put_voted_at()
    |> foreign_key_constraint(:poll_option_id)
    |> foreign_key_constraint(:voter_id)
    |> unique_constraint([:poll_option_id, :voter_id],
         message: "You have already voted for this option")
  end

  @doc """
  Creates a changeset for creating a ranked vote (1st, 2nd, 3rd, etc).
  """
  def ranked_vote_changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [:vote_rank, :poll_option_id, :voter_id])
    |> validate_required([:vote_rank, :poll_option_id, :voter_id])
    |> validate_number(:vote_rank, greater_than: 0, less_than_or_equal_to: 10)
    |> put_change(:vote_value, "ranked")
    |> put_voted_at()
    |> foreign_key_constraint(:poll_option_id)
    |> foreign_key_constraint(:voter_id)
    |> unique_constraint([:poll_option_id, :voter_id],
         message: "You have already voted for this option")
  end

  @doc """
  Creates a changeset for creating a star rating vote (1-5 stars).
  """
  def star_vote_changeset(poll_vote, attrs) do
    poll_vote
    |> cast(attrs, [:vote_numeric, :poll_option_id, :voter_id])
    |> validate_required([:vote_numeric, :poll_option_id, :voter_id])
    |> validate_number(:vote_numeric, greater_than: 0, less_than_or_equal_to: 5)
    |> put_change(:vote_value, "star")
    |> put_voted_at()
    |> foreign_key_constraint(:poll_option_id)
    |> foreign_key_constraint(:voter_id)
    |> unique_constraint([:poll_option_id, :voter_id],
         message: "You have already voted for this option")
  end

  @doc """
  Check if the vote is positive (yes, selected, or high rating).
  """
  def positive?(%__MODULE__{vote_value: "yes"}), do: true
  def positive?(%__MODULE__{vote_value: "selected"}), do: true
  def positive?(%__MODULE__{vote_value: "star", vote_numeric: rating}) when rating >= 3, do: true
  def positive?(%__MODULE__{vote_value: "ranked"}), do: true  # All ranked votes are considered positive
  def positive?(%__MODULE__{}), do: false

  @doc """
  Check if the vote is negative.
  """
  def negative?(%__MODULE__{vote_value: "no"}), do: true
  def negative?(%__MODULE__{vote_value: "star", vote_numeric: rating}) when rating < 3, do: true
  def negative?(%__MODULE__{}), do: false

  @doc """
  Check if the vote is neutral.
  """
  def neutral?(%__MODULE__{vote_value: "star", vote_numeric: rating}) when rating == 3, do: true
  def neutral?(%__MODULE__{}), do: false

  @doc """
  Get a numeric score for the vote (useful for tallying and sorting).
  """
  def vote_score(%__MODULE__{vote_value: "yes"}), do: 1.0
  def vote_score(%__MODULE__{vote_value: "no"}), do: 0.0
  def vote_score(%__MODULE__{vote_value: "selected"}), do: 1.0
  def vote_score(%__MODULE__{vote_value: "star", vote_numeric: rating}), do: Decimal.to_float(rating)
  def vote_score(%__MODULE__{vote_value: "ranked", vote_rank: rank}) do
    # Higher ranks get lower scores (1st place = 10 points, 2nd = 9, etc.)
    max(11 - rank, 1) / 10.0
  end
  def vote_score(%__MODULE__{}), do: 0.0

  @doc """
  Get a human-readable string for the vote.
  """
  def vote_display(%__MODULE__{vote_value: "yes"}), do: "Yes"
  def vote_display(%__MODULE__{vote_value: "no"}), do: "No"
  def vote_display(%__MODULE__{vote_value: "selected"}), do: "Selected"
  def vote_display(%__MODULE__{vote_value: "star", vote_numeric: rating}) do
    rating_str = rating |> Decimal.to_float() |> :erlang.float_to_binary(decimals: 1)
    "#{rating_str} ★"
  end
  def vote_display(%__MODULE__{vote_value: "ranked", vote_rank: rank}) do
    case rank do
      1 -> "1st Choice"
      2 -> "2nd Choice"
      3 -> "3rd Choice"
      n when n > 3 -> "#{n}th Choice"
    end
  end
  def vote_display(%__MODULE__{}), do: "Unknown"

  @doc """
  Get all valid vote values for binary voting.
  """
  def binary_vote_values, do: ~w(yes no)

  @doc """
  Get all valid vote values for approval voting.
  """
  def approval_vote_values, do: ~w(selected)

  @doc """
  Get vote value options for binary voting forms/dropdowns.
  """
  def binary_vote_options do
    [
      {"Yes", "yes"},
      {"No", "no"}
    ]
  end

  @doc """
  Get star rating options for forms/dropdowns.
  """
  def star_rating_options do
    [
      {"1 ★", 1},
      {"2 ★", 2},
      {"3 ★", 3},
      {"4 ★", 4},
      {"5 ★", 5}
    ]
  end

  @doc """
  Get rank options for ranked voting forms/dropdowns.
  """
  def rank_options(max_rank \\ 10) do
    1..max_rank
    |> Enum.map(fn rank ->
      label = case rank do
        1 -> "1st Choice"
        2 -> "2nd Choice"
        3 -> "3rd Choice"
        n -> "#{n}th Choice"
      end
      {label, rank}
    end)
  end

  @doc """
  Compare two votes for sorting by value/rank/rating.
  """
  def compare(%__MODULE__{vote_rank: rank1}, %__MODULE__{vote_rank: rank2})
      when not is_nil(rank1) and not is_nil(rank2) do
    cond do
      rank1 < rank2 -> :lt
      rank1 > rank2 -> :gt
      true -> :eq
    end
  end

  def compare(%__MODULE__{vote_numeric: rating1}, %__MODULE__{vote_numeric: rating2})
      when not is_nil(rating1) and not is_nil(rating2) do
    Decimal.compare(rating1, rating2)
  end

  def compare(%__MODULE__{vote_value: val1}, %__MODULE__{vote_value: val2}) do
    cond do
      val1 == val2 -> :eq
      val1 == "yes" and val2 == "no" -> :gt
      val1 == "no" and val2 == "yes" -> :lt
      val1 == "selected" -> :gt
      true -> :eq
    end
  end

  defp validate_vote_fields(changeset) do
    vote_value = get_field(changeset, :vote_value)
    vote_numeric = get_field(changeset, :vote_numeric)
    vote_rank = get_field(changeset, :vote_rank)

    case {vote_value, vote_numeric, vote_rank} do
      {nil, nil, nil} ->
        add_error(changeset, :vote_value, "must provide at least one vote field")

      {"star", nil, _} ->
        add_error(changeset, :vote_numeric, "is required for star voting")

      {"ranked", _, nil} ->
        add_error(changeset, :vote_rank, "is required for ranked voting")

      {value, nil, nil} when value in ~w(yes no selected) ->
        changeset

      {"star", numeric, nil} when not is_nil(numeric) ->
        validate_number(changeset, :vote_numeric, greater_than: 0, less_than_or_equal_to: 5)

      {"ranked", _, rank} when not is_nil(rank) ->
        validate_number(changeset, :vote_rank, greater_than: 0, less_than_or_equal_to: 10)

      _ ->
        add_error(changeset, :vote_value, "invalid combination of vote fields")
    end
  end

  defp put_voted_at(changeset) do
    case get_field(changeset, :voted_at) do
      nil -> put_change(changeset, :voted_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
