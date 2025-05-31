defmodule EventasaurusApp.Events.EventDateOption do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusApp.Events.{EventDatePoll, EventDateVote}

  schema "event_date_options" do
    field :date, :date

    belongs_to :event_date_poll, EventDatePoll
    has_many :votes, EventDateVote

    timestamps()
  end

  @doc false
  def changeset(event_date_option, attrs) do
    event_date_option
    |> cast(attrs, [:date, :event_date_poll_id])
    |> validate_required([:date, :event_date_poll_id])
    |> validate_date_not_in_past()
    |> foreign_key_constraint(:event_date_poll_id)
    |> unique_constraint([:event_date_poll_id, :date], message: "date already exists for this poll")
  end

  @doc """
  Creates a changeset for creating multiple date options at once.
  """
  def creation_changeset(event_date_option, attrs) do
    changeset(event_date_option, attrs)
  end

  @doc """
  Check if the date option is in the past.
  """
  def past?(%__MODULE__{date: date}) do
    Date.compare(date, Date.utc_today()) == :lt
  end

  @doc """
  Check if the date option is today.
  """
  def today?(%__MODULE__{date: date}) do
    Date.compare(date, Date.utc_today()) == :eq
  end

  @doc """
  Check if the date option is in the future.
  """
  def future?(%__MODULE__{date: date}) do
    Date.compare(date, Date.utc_today()) == :gt
  end

  @doc """
  Get a human-readable string for the date option.
  """
  def to_display_string(%__MODULE__{date: date}) do
    date
    |> Date.to_string()
  end

  @doc """
  Compare two date options for sorting.
  """
  def compare(%__MODULE__{date: date1}, %__MODULE__{date: date2}) do
    Date.compare(date1, date2)
  end

  defp validate_date_not_in_past(changeset) do
    case get_field(changeset, :date) do
      nil -> changeset
      date ->
        if Date.compare(date, Date.utc_today()) != :lt do
          changeset
        else
          add_error(changeset, :date, "cannot be in the past")
        end
    end
  end
end
