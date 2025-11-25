defmodule EventasaurusApp.Planning.OccurrencePlanning do
  @moduledoc """
  Schema for tracking poll-based occurrence selection planning.

  This schema tracks the state of flexible "Plan with friends" workflows where
  users poll friends to decide on a specific occurrence (movie showtime, restaurant
  time slot, etc.) before creating the final event_plan.

  ## Workflow
  1. User initiates flexible planning for a series (movie, restaurant, quiz, etc.)
  2. System finds matching occurrences based on filter_criteria
  3. Creates poll with occurrence options
  4. Creates occurrence_planning record to track the process
  5. Friends vote on poll
  6. Poll finalizes → creates event_plan (linked via event_plan_id)

  ## Polymorphic Series Reference
  The series_type + series_id fields create a polymorphic reference to the "thing"
  being planned:
  - series_type: "movie", series_id: 123 → Planning showtimes for movie #123
  - series_type: "venue", series_id: 456 → Planning time slots for venue #456
  - series_type: "activity_series", series_id: 789 → Planning dates for activity #789
  - series_type: nil, series_id: nil → Discovery mode (e.g., "which restaurant?")
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "occurrence_planning" do
    # The private event being planned
    belongs_to(:event, EventasaurusApp.Events.Event)

    # The poll used to decide on the occurrence
    belongs_to(:poll, EventasaurusApp.Events.Poll)

    # Polymorphic reference to the series entity (movie, venue, activity, etc.)
    field(:series_type, :string)
    field(:series_id, :integer)

    # The result - NULL until poll finalizes, then links to created event_plan
    belongs_to(:event_plan, EventasaurusApp.Events.EventPlan,
      foreign_key: :event_plan_id,
      define_field: false
    )

    field(:event_plan_id, :id)

    # Optional: filters used to generate poll options
    # Stores date ranges, time preferences, venue filters, etc.
    field(:filter_criteria, :map, default: %{})

    timestamps()
  end

  @doc """
  Changeset for creating a new occurrence planning record.
  """
  def changeset(occurrence_planning, attrs) do
    occurrence_planning
    |> cast(attrs, [
      :event_id,
      :poll_id,
      :series_type,
      :series_id,
      :event_plan_id,
      :filter_criteria
    ])
    |> validate_required([:event_id, :poll_id])
    |> validate_series_reference()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:poll_id)
    |> foreign_key_constraint(:event_plan_id)
    |> unique_constraint([:event_id, :poll_id],
      name: :occurrence_planning_event_id_poll_id_index,
      message: "event already has an occurrence planning poll"
    )
  end

  @doc """
  Changeset for finalizing the occurrence planning by linking to event_plan.
  """
  def finalization_changeset(occurrence_planning, event_plan_id) do
    occurrence_planning
    |> cast(%{event_plan_id: event_plan_id}, [:event_plan_id])
    |> validate_required([:event_plan_id])
    |> foreign_key_constraint(:event_plan_id)
  end

  @doc """
  Get all supported series types.
  """
  def series_types do
    ~w(movie venue activity_series quiz_series)
  end

  @doc """
  Get display name for series type.
  """
  def series_type_display(nil), do: "Discovery"
  def series_type_display("movie"), do: "Movie"
  def series_type_display("venue"), do: "Venue"
  def series_type_display("activity_series"), do: "Activity"
  def series_type_display("quiz_series"), do: "Quiz"

  def series_type_display(type) when is_binary(type),
    do: type |> String.replace("_", " ") |> String.capitalize()

  # Private validation helpers

  defp validate_series_reference(changeset) do
    series_type = get_field(changeset, :series_type)
    series_id = get_field(changeset, :series_id)

    case {series_type, series_id} do
      # Discovery mode - both nil is valid
      {nil, nil} ->
        changeset

      # Both set - validate type is supported
      {type, id} when is_binary(type) and is_integer(id) ->
        if type in series_types() do
          changeset
        else
          add_error(
            changeset,
            :series_type,
            "must be one of: #{Enum.join(series_types(), ", ")}"
          )
        end

      # Only one set - invalid
      {nil, _id} ->
        add_error(changeset, :series_type, "must be set when series_id is present")

      {_type, nil} ->
        add_error(changeset, :series_id, "must be set when series_type is present")

      _ ->
        changeset
    end
  end
end
