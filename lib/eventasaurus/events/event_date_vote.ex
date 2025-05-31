defmodule EventasaurusApp.Events.EventDateVote do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Events.EventDateOption
  alias EventasaurusApp.Accounts.User

  schema "event_date_votes" do
    field :vote_type, Ecto.Enum, values: [:yes, :if_need_be, :no]

    belongs_to :event_date_option, EventDateOption
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(event_date_vote, attrs) do
    event_date_vote
    |> cast(attrs, [:vote_type, :event_date_option_id, :user_id])
    |> validate_required([:vote_type, :event_date_option_id, :user_id])
    |> validate_inclusion(:vote_type, [:yes, :if_need_be, :no])
    |> foreign_key_constraint(:event_date_option_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:event_date_option_id, :user_id], message: "user has already voted for this date option")
  end

  @doc """
  Creates a changeset for creating a new vote.
  """
  def creation_changeset(event_date_vote, attrs) do
    event_date_vote
    |> cast(attrs, [:vote_type, :event_date_option_id, :user_id])
    |> validate_required([:vote_type, :event_date_option_id, :user_id])
    |> validate_inclusion(:vote_type, [:yes, :if_need_be, :no])
    |> foreign_key_constraint(:event_date_option_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:event_date_option_id, :user_id], message: "user has already voted for this date option")
  end

  @doc """
  Check if the vote is positive (yes or if_need_be).
  """
  def positive?(%__MODULE__{vote_type: :yes}), do: true
  def positive?(%__MODULE__{vote_type: :if_need_be}), do: true
  def positive?(%__MODULE__{vote_type: :no}), do: false

  @doc """
  Check if the vote is negative.
  """
  def negative?(%__MODULE__{vote_type: :no}), do: true
  def negative?(%__MODULE__{vote_type: _}), do: false

  @doc """
  Get a human-readable string for the vote type.
  """
  def vote_type_display(%__MODULE__{vote_type: :yes}), do: "Yes"
  def vote_type_display(%__MODULE__{vote_type: :if_need_be}), do: "If needed"
  def vote_type_display(%__MODULE__{vote_type: :no}), do: "No"

  @doc """
  Get a numeric score for the vote (useful for tallying).
  """
  def vote_score(%__MODULE__{vote_type: :yes}), do: 1.0
  def vote_score(%__MODULE__{vote_type: :if_need_be}), do: 0.5
  def vote_score(%__MODULE__{vote_type: :no}), do: 0.0

  @doc """
  Get all possible vote types.
  """
  def vote_types, do: [:yes, :if_need_be, :no]

  @doc """
  Get vote type options for forms/dropdowns.
  """
  def vote_type_options do
    [
      {"Yes", :yes},
      {"If needed", :if_need_be},
      {"No", :no}
    ]
  end
end
