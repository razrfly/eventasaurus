defmodule EventasaurusApp.Events.EventDatePoll do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Events.{Event, EventDateOption}
  alias EventasaurusApp.Accounts.User

  schema "event_date_polls" do
    field :voting_deadline, :utc_datetime
    field :finalized_date, :date

    belongs_to :event, Event
    belongs_to :created_by, User, foreign_key: :created_by_id
    has_many :date_options, EventDateOption

    timestamps()
  end

  @doc false
  def changeset(event_date_poll, attrs) do
    event_date_poll
    |> cast(attrs, [:voting_deadline, :finalized_date, :event_id, :created_by_id])
    |> validate_required([:event_id, :created_by_id])
    |> validate_voting_deadline()
    |> validate_finalized_date()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint(:event_id, message: "an event can only have one poll")
  end

  @doc """
  Creates a changeset for creating a new poll.
  """
  def creation_changeset(event_date_poll, attrs) do
    event_date_poll
    |> cast(attrs, [:voting_deadline, :event_id, :created_by_id])
    |> validate_required([:event_id, :created_by_id])
    |> validate_voting_deadline()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint(:event_id, message: "an event can only have one poll")
  end

  @doc """
  Creates a changeset for finalizing a poll with a selected date.
  """
  def finalization_changeset(event_date_poll, finalized_date) do
    event_date_poll
    |> cast(%{finalized_date: finalized_date}, [:finalized_date])
    |> validate_required([:finalized_date])
    |> validate_finalized_date()
  end

  @doc """
  Check if the poll is currently active (not finalized and within deadline).
  """
  def active?(%__MODULE__{finalized_date: nil, voting_deadline: nil}), do: true
  def active?(%__MODULE__{finalized_date: nil, voting_deadline: deadline}) do
    DateTime.compare(DateTime.utc_now(), deadline) == :lt
  end
  def active?(%__MODULE__{finalized_date: _}), do: false

  @doc """
  Check if the poll is finalized.
  """
  def finalized?(%__MODULE__{finalized_date: nil}), do: false
  def finalized?(%__MODULE__{finalized_date: _}), do: true

  defp validate_voting_deadline(changeset) do
    case get_field(changeset, :voting_deadline) do
      nil -> changeset
      deadline ->
        if DateTime.compare(deadline, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, :voting_deadline, "must be in the future")
        end
    end
  end

  defp validate_finalized_date(changeset) do
    finalized_date = get_field(changeset, :finalized_date)

    case finalized_date do
      nil -> changeset
      date ->
        # Validate that finalized date is not in the past
        today = Date.utc_today()
        if Date.compare(date, today) != :lt do
          changeset
        else
          add_error(changeset, :finalized_date, "cannot be in the past")
        end
    end
  end
end
