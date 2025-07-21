defmodule EventasaurusApp.Events.Poll do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  import Ecto.SoftDelete.Schema
  alias EventasaurusApp.Events.{Event, PollOption, PollVote}
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Repo

  schema "polls" do
    field :title, :string
    field :description, :string
    field :poll_type, :string
    field :voting_system, :string
    field :phase, :string, default: "list_building"
    field :status, :string, virtual: true  # Virtual field for backward compatibility
    field :list_building_deadline, :utc_datetime
    field :voting_deadline, :utc_datetime
    field :finalized_date, :date
    field :finalized_option_ids, {:array, :integer}
    field :max_options_per_user, :integer
    field :auto_finalize, :boolean, default: false

    # Virtual fields for attaching stats in queries
    field :stats, {:array, :map}, virtual: true
    field :unique_voters, :integer, virtual: true

    belongs_to :event, Event
    belongs_to :created_by, User, foreign_key: :created_by_id
    has_many :poll_options, PollOption

    # Deletion metadata fields
    field :deletion_reason, :string
    belongs_to :deleted_by_user, EventasaurusApp.Accounts.User, foreign_key: :deleted_by_user_id

    timestamps()
    soft_delete_schema()
  end

  @doc """
  Callback to populate virtual fields after loading from database.
  """
  def __after_load__(poll) do
    %{poll | status: status(poll)}
  end

  @doc """
  Returns the status representation of the poll for backward compatibility.
  Maps the new phase system back to the legacy status values.
  """
  def status(%__MODULE__{phase: phase}) do
    case phase do
      "list_building" -> "list_building"
      "voting_with_suggestions" -> "voting"
      "voting_only" -> "voting"
      "voting" -> "voting"  # Legacy support
      "closed" -> "finalized"
      phase -> phase
    end
  end

  # Private helper for status-to-phase mapping
  defp map_status_to_phase(attrs) do
    case Map.get(attrs, :status) || Map.get(attrs, "status") do
      nil -> attrs
      "list_building" -> Map.put(attrs, :phase, "list_building")
      "voting" -> Map.put(attrs, :phase, "voting_with_suggestions")  # Default to suggestions allowed
      "finalized" -> Map.put(attrs, :phase, "closed")
      status -> Map.put(attrs, :phase, status)
    end
  end

  @doc false
  def changeset(poll, attrs) do
    # Map status to phase for backward compatibility
    attrs = map_status_to_phase(attrs)

    poll
    |> cast(attrs, [
      :title, :description, :poll_type, :voting_system, :phase,
      :list_building_deadline, :voting_deadline, :finalized_date,
      :finalized_option_ids, :max_options_per_user, :auto_finalize,
      :event_id, :created_by_id
    ])
    |> validate_required([:title, :poll_type, :voting_system, :event_id, :created_by_id])
    |> validate_inclusion(:phase, phases())
    |> validate_inclusion(:voting_system, ~w(binary approval ranked star))
    |> validate_poll_type()
    |> validate_deadlines()
    |> validate_finalized_date()
    |> check_constraint(:phase, name: :valid_phase, message: "Invalid phase value")
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint([:event_id, :poll_type],
         name: :polls_event_poll_type_unique,
         message: "A poll of this type already exists for this event")
  end

  @doc """
  Creates a changeset for creating a new poll.
  """
  def creation_changeset(poll, attrs) do
    # Map status to phase for backward compatibility
    attrs = map_status_to_phase(attrs)

    poll
    |> cast(attrs, [
      :title, :description, :poll_type, :voting_system,
      :list_building_deadline, :voting_deadline, :max_options_per_user,
      :auto_finalize, :event_id, :created_by_id
    ])
    |> validate_required([:title, :poll_type, :voting_system, :event_id, :created_by_id])
    |> validate_inclusion(:voting_system, ~w(binary approval ranked star))
    |> validate_poll_type()
    |> validate_deadlines()
    |> put_change(:phase, "list_building")
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint([:event_id, :poll_type],
         name: :polls_event_poll_type_unique,
         message: "A poll of this type already exists for this event")
  end

  @doc """
  Creates a changeset for transitioning poll phase.
  """
  def phase_transition_changeset(poll, new_phase) when new_phase in ["list_building", "voting_with_suggestions", "voting_only", "closed"] do
    poll
    |> cast(%{phase: new_phase}, [:phase])
    |> validate_required([:phase])
    |> validate_inclusion(:phase, phases())
    |> validate_phase_transition(poll.phase, new_phase)
    |> check_constraint(:phase, name: :valid_phase, message: "Invalid phase value")
  end

  # Legacy support for old "voting" phase
  def phase_transition_changeset(poll, "voting") do
    phase_transition_changeset(poll, "voting_with_suggestions")
  end

  @doc """
  Creates a changeset for finalizing a poll with selected options.
  """
  def finalization_changeset(poll, option_ids, finalized_date \\ nil) do
    finalized_date = finalized_date || Date.utc_today()

    poll
    |> cast(%{
      finalized_option_ids: option_ids,
      finalized_date: finalized_date,
      phase: "closed"
    }, [:finalized_option_ids, :finalized_date, :phase])
    |> validate_required([:finalized_option_ids, :finalized_date])
    |> validate_finalized_date()
    |> validate_finalized_options()
    |> check_constraint(:phase, name: :valid_phase, message: "Invalid phase value")
  end

  @doc """
  Creates a changeset for updating poll status/phase.
  """
  def status_changeset(poll, attrs) do
    # Map status to phase for backward compatibility
    attrs = map_status_to_phase(attrs)

    changeset = poll
    |> cast(attrs, [:phase])
    |> validate_required([:phase])
    |> validate_inclusion(:phase, phases())
    |> check_constraint(:phase, name: :valid_phase, message: "Invalid phase value")

    new_phase = get_field(changeset, :phase)
    validate_phase_transition(changeset, poll.phase, new_phase)
  end

  @doc """
  Check if the poll is in list building phase.
  """
  def list_building?(%__MODULE__{phase: "list_building"}), do: true
  def list_building?(%__MODULE__{}), do: false

  @doc """
  Check if the poll is in any voting phase.
  """
  def voting?(%__MODULE__{phase: "voting_with_suggestions"}), do: true
  def voting?(%__MODULE__{phase: "voting_only"}), do: true
  def voting?(%__MODULE__{phase: "voting"}), do: true  # Legacy support
  def voting?(%__MODULE__{}), do: false

  @doc """
  Check if the poll is in voting phase with suggestions allowed.
  """
  def voting_with_suggestions?(%__MODULE__{phase: "voting_with_suggestions"}), do: true
  def voting_with_suggestions?(%__MODULE__{phase: "voting"}), do: true  # Legacy support - assume suggestions allowed
  def voting_with_suggestions?(%__MODULE__{}), do: false

  @doc """
  Check if the poll is in voting-only phase (no suggestions).
  """
  def voting_only?(%__MODULE__{phase: "voting_only"}), do: true
  def voting_only?(%__MODULE__{}), do: false

  @doc """
  Check if suggestions are allowed in the current phase.
  """
  def suggestions_allowed?(%__MODULE__{phase: "list_building"}), do: true
  def suggestions_allowed?(%__MODULE__{phase: "voting_with_suggestions"}), do: true
  def suggestions_allowed?(%__MODULE__{phase: "voting"}), do: true  # Legacy support
  def suggestions_allowed?(%__MODULE__{}), do: false

  @doc """
  Check if the poll is closed/finalized.
  """
  def closed?(%__MODULE__{phase: "closed"}), do: true
  def closed?(%__MODULE__{}), do: false

  @doc """
  Check if the poll is finalized (has results).
  """
  def finalized?(%__MODULE__{finalized_date: nil}), do: false
  def finalized?(%__MODULE__{finalized_date: _}), do: true

  @doc """
  Check if the poll is currently active for the given phase.
  """
  def active_for_phase?(%__MODULE__{phase: "list_building"} = poll) do
    case poll.list_building_deadline do
      nil -> true
      deadline -> DateTime.compare(DateTime.utc_now(), deadline) == :lt
    end
  end

  def active_for_phase?(%__MODULE__{phase: "voting_with_suggestions"} = poll) do
    case poll.voting_deadline do
      nil -> true
      deadline -> DateTime.compare(DateTime.utc_now(), deadline) == :lt
    end
  end

  def active_for_phase?(%__MODULE__{phase: "voting_only"} = poll) do
    case poll.voting_deadline do
      nil -> true
      deadline -> DateTime.compare(DateTime.utc_now(), deadline) == :lt
    end
  end

  def active_for_phase?(%__MODULE__{phase: "voting"} = poll) do  # Legacy support
    case poll.voting_deadline do
      nil -> true
      deadline -> DateTime.compare(DateTime.utc_now(), deadline) == :lt
    end
  end

  def active_for_phase?(%__MODULE__{phase: "closed"}), do: false

  @doc """
  Get all supported poll types.
  """
  def poll_types, do: ~w(movie places custom time general venue date_selection)

  @doc """
  Get all supported voting systems.
  """
  def voting_systems, do: ~w(binary approval ranked star)

  @doc """
  Get all valid phases.
  """
  def phases, do: ~w(list_building voting_with_suggestions voting_only closed)

  @doc """
  Get display name for poll type.
  """
  def poll_type_display("movie"), do: "Movies"
  def poll_type_display("places"), do: "Places"
  def poll_type_display("custom"), do: "Custom"
  def poll_type_display("time"), do: "Time/Schedule"
  def poll_type_display("general"), do: "General"  # Test type
  def poll_type_display("venue"), do: "Venue"  # Test type
  def poll_type_display("date_selection"), do: "Date Selection"
  def poll_type_display(type), do: String.capitalize(type)

  @doc """
  Get display name for voting system.
  """
  def voting_system_display("binary"), do: "Yes/No Voting"
  def voting_system_display("approval"), do: "Approval Voting (Select Multiple)"
  def voting_system_display("ranked"), do: "Ranked Choice Voting"
  def voting_system_display("star"), do: "Star Rating (1-5)"

  @doc """
  Get display name for poll phase.
  """
  def phase_display("list_building"), do: "Building Phase - Suggest and vote on options"
  def phase_display("voting_with_suggestions"), do: "Voting Phase - Vote and suggest more options"
  def phase_display("voting_only"), do: "Voting Phase - Vote on existing options"
  def phase_display("closed"), do: "Results - Poll closed"
  def phase_display("voting"), do: "Voting Phase"  # Legacy support

  defp validate_poll_type(changeset) do
    poll_type = get_field(changeset, :poll_type)

    if poll_type && poll_type not in poll_types() do
      add_error(changeset, :poll_type, "is not a supported poll type")
    else
      changeset
    end
  end

  defp validate_deadlines(changeset) do
    list_deadline = get_field(changeset, :list_building_deadline)
    voting_deadline = get_field(changeset, :voting_deadline)

    changeset
    |> validate_deadline(:list_building_deadline, list_deadline)
    |> validate_deadline(:voting_deadline, voting_deadline)
    |> validate_deadline_order(list_deadline, voting_deadline)
  end

  defp validate_deadline(changeset, _field, nil), do: changeset
  defp validate_deadline(changeset, field, deadline) do
    if DateTime.compare(deadline, DateTime.utc_now()) == :gt do
      changeset
    else
      add_error(changeset, field, "must be in the future")
    end
  end

  defp validate_deadline_order(changeset, nil, _), do: changeset
  defp validate_deadline_order(changeset, _, nil), do: changeset
  defp validate_deadline_order(changeset, list_deadline, voting_deadline) do
    if DateTime.compare(list_deadline, voting_deadline) == :lt do
      changeset
    else
      add_error(changeset, :voting_deadline, "must be after list building deadline")
    end
  end

  defp validate_finalized_date(changeset) do
    finalized_date = get_field(changeset, :finalized_date)

    case finalized_date do
      nil -> changeset
      date ->
        today = Date.utc_today()
        if Date.compare(date, today) != :lt do
          changeset
        else
          add_error(changeset, :finalized_date, "cannot be in the past")
        end
    end
  end

  defp validate_finalized_options(changeset) do
    options = get_field(changeset, :finalized_option_ids)

    case options do
      nil -> add_error(changeset, :finalized_option_ids, "must select at least one option")
      [] -> add_error(changeset, :finalized_option_ids, "must select at least one option")
      _ -> changeset
    end
  end

  defp validate_phase_transition(changeset, current_phase, new_phase) do
    case {current_phase, new_phase} do
      # Same phase (no change)
      {same, same} -> changeset

      # From list_building phase
      {"list_building", "voting_with_suggestions"} -> changeset
      {"list_building", "voting_only"} -> changeset
      {"list_building", "closed"} -> changeset
      {"list_building", "voting"} -> changeset  # Legacy support

      # From voting_with_suggestions phase
      {"voting_with_suggestions", "voting_only"} -> changeset
      {"voting_with_suggestions", "closed"} -> changeset
      {"voting_with_suggestions", "list_building"} -> validate_no_votes_for_building_transition(changeset)

      # From voting_only phase
      {"voting_only", "voting_with_suggestions"} -> changeset  # NEW: Allow bidirectional voting transitions
      {"voting_only", "closed"} -> changeset
      {"voting_only", "list_building"} -> validate_no_votes_for_building_transition(changeset)

      # Legacy voting phase transitions
      {"voting", "closed"} -> changeset
      {"voting", "list_building"} -> validate_no_votes_for_building_transition(changeset)
      {"voting", "voting_with_suggestions"} -> changeset
      {"voting", "voting_only"} -> changeset

      # From closed phase - no transitions allowed (final state)
      {"closed", _} -> add_error(changeset, :phase, "cannot transition from closed phase")

      # Invalid transitions
      _ -> add_error(changeset, :phase, "invalid phase transition from #{current_phase} to #{new_phase}")
    end
  end

  defp validate_no_votes_for_building_transition(changeset) do
    poll = changeset.data

    vote_count = from(v in PollVote,
                     join: o in assoc(v, :poll_option),
                     where: o.poll_id == ^poll.id)
                 |> Repo.aggregate(:count, :id)

    if vote_count > 0 do
      add_error(changeset, :phase, "cannot return to building phase when votes exist")
    else
      changeset
    end
  end
end
