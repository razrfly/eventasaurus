defmodule EventasaurusApp.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias Nanoid, as: NanoID
  alias EventasaurusApp.EventStateMachine

    # Define state machine using Machinery
  use Machinery,
    field: :status,
    states: [:draft, :polling, :threshold, :confirmed, :canceled],
    transitions: %{
      # From draft state
      draft: [:polling, :confirmed, :canceled],
      # From polling state
      polling: [:threshold, :confirmed, :canceled],
      # From threshold state
      threshold: [:confirmed, :canceled],
      # From confirmed state
      confirmed: [:canceled],
      # Canceled is final
      canceled: []
    }

  # Valid status values for the enum constraint
  @valid_statuses ~w(draft polling threshold confirmed canceled)

  def valid_statuses, do: @valid_statuses

  schema "events" do
    field :title, :string
    field :tagline, :string
    field :description, :string
    field :start_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :timezone, :string
    field :visibility, Ecto.Enum, values: [:public, :private], default: :public
    field :slug, :string
    field :cover_image_url, :string # for user uploads
    field :external_image_data, :map # for Unsplash/TMDB images
    field :status, Ecto.Enum, values: [:draft, :polling, :threshold, :confirmed, :canceled], default: :confirmed
    field :polling_deadline, :utc_datetime
    field :threshold_count, :integer
    field :canceled_at, :utc_datetime

    # Theme fields for the theming system
    field :theme, Ecto.Enum,
      values: [:minimal, :cosmic, :velocity, :retro, :celebration, :nature, :professional],
      default: :minimal
    field :theme_customizations, :map, default: %{}

    # Virtual field for date polling validation
    field :selected_poll_dates, :string, virtual: true

    # Virtual field for computed phase
    field :computed_phase, :string, virtual: true

    # Virtual flags for quick state checks
    field :ended?, :boolean, virtual: true
    field :can_sell_tickets?, :boolean, virtual: true
    field :threshold_met?, :boolean, virtual: true
    field :polling_ended?, :boolean, virtual: true
    field :active_poll?, :boolean, virtual: true

    belongs_to :venue, EventasaurusApp.Venues.Venue

    many_to_many :users, EventasaurusApp.Accounts.User,
      join_through: EventasaurusApp.Events.EventUser

    has_one :date_poll, EventasaurusApp.Events.EventDatePoll

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :tagline, :description, :start_at, :ends_at, :timezone,
                   :visibility, :slug, :cover_image_url, :venue_id, :external_image_data,
                   :theme, :theme_customizations, :status, :polling_deadline, :threshold_count,
                   :canceled_at, :selected_poll_dates])
    |> validate_required([:title, :start_at, :timezone, :visibility])
    |> validate_length(:title, min: 3, max: 100)
    |> validate_length(:tagline, max: 255)
    |> validate_length(:slug, min: 3, max: 100)
    |> validate_status()
    |> validate_slug()
    |> validate_polling_deadline()
    |> validate_threshold_count()
    |> validate_canceled_at()
    |> validate_status_consistency()
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint(:slug)
    |> maybe_generate_slug()
  end

      @doc """
  Check if a status transition is valid.
  """
  def can_transition_to?(current_status, new_status) when is_atom(current_status) and is_atom(new_status) do
    # Access transitions directly from the module configuration
    transitions = %{
      draft: [:polling, :confirmed, :canceled],
      polling: [:threshold, :confirmed, :canceled],
      threshold: [:confirmed, :canceled],
      confirmed: [:canceled],
      canceled: []
    }

    case Map.get(transitions, current_status) do
      nil -> false
      allowed_statuses when is_list(allowed_statuses) -> new_status in allowed_statuses
      allowed_status when is_atom(allowed_status) -> new_status == allowed_status
      _ -> false
    end
  end

  def can_transition_to?(%__MODULE__{status: current_status}, new_status) do
    can_transition_to?(current_status, new_status)
  end

  @doc """
  Get possible transitions from the current status.
  """
  def possible_transitions(current_status) when is_atom(current_status) do
    transitions = %{
      draft: [:polling, :confirmed, :canceled],
      polling: [:threshold, :confirmed, :canceled],
      threshold: [:confirmed, :canceled],
      confirmed: [:canceled],
      canceled: []
    }

    case Map.get(transitions, current_status) do
      nil -> []
      allowed_statuses when is_list(allowed_statuses) -> allowed_statuses
      allowed_status when is_atom(allowed_status) -> [allowed_status]
      _ -> []
    end
  end

  def possible_transitions(%__MODULE__{status: current_status}) do
    possible_transitions(current_status)
  end

    @doc """
  Transition event to a new status.
  """
  def transition_to(%__MODULE__{} = event, new_status) when is_atom(new_status) do
    if can_transition_to?(event.status, new_status) do
      # Handle side effects based on the transition
      updated_event = %{event | status: new_status}
      updated_event = handle_status_change(updated_event, new_status)
      {:ok, updated_event}
    else
      {:error, "invalid transition from '#{event.status}' to '#{new_status}'"}
    end
  end

  # Handle side effects when status changes
  defp handle_status_change(event, :canceled) do
    %{event | canceled_at: DateTime.utc_now()}
  end

  defp handle_status_change(event, _status), do: event

  defp validate_status(changeset) do
    case get_field(changeset, :status) do
      nil -> changeset
      status when status in [:draft, :polling, :threshold, :confirmed, :canceled] -> changeset
      _invalid_status ->
        add_error(changeset, :status, "must be one of: #{Enum.join(@valid_statuses, ", ")}")
    end
  end

  defp validate_polling_deadline(changeset) do
    status = get_field(changeset, :status)
    polling_deadline = get_field(changeset, :polling_deadline)

    case {status, polling_deadline} do
      {:polling, nil} ->
        add_error(changeset, :polling_deadline, "is required when status is polling")
      {:polling, deadline} when not is_nil(deadline) ->
        if DateTime.compare(deadline, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, :polling_deadline, "must be in the future")
        end
      _ -> changeset
    end
  end

  defp validate_threshold_count(changeset) do
    status = get_field(changeset, :status)
    threshold_count = get_field(changeset, :threshold_count)

    case {status, threshold_count} do
      {:threshold, nil} ->
        add_error(changeset, :threshold_count, "is required when status is threshold")
      {:threshold, count} when is_integer(count) and count > 0 ->
        changeset
      {:threshold, _} ->
        add_error(changeset, :threshold_count, "must be a positive integer")
      _ -> changeset
    end
  end

  defp validate_canceled_at(changeset) do
    status = get_field(changeset, :status)
    canceled_at = get_field(changeset, :canceled_at)

    case {status, canceled_at} do
      {:canceled, nil} ->
        # Auto-set canceled_at if not provided
        put_change(changeset, :canceled_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  defp validate_status_consistency(changeset) do
    # Get all relevant fields to check status consistency
    attrs = %{
      status: get_field(changeset, :status),
      canceled_at: get_field(changeset, :canceled_at),
      polling_deadline: get_field(changeset, :polling_deadline),
      threshold_count: get_field(changeset, :threshold_count),

    }

    current_status = attrs.status
    inferred_status = EventStateMachine.infer_status(attrs)

    if current_status == inferred_status do
      changeset
    else
      add_error(changeset, :status,
        "does not match inferred status '#{inferred_status}' based on event attributes. " <>
        "Consider setting status to '#{inferred_status}' or adjusting the related fields.")
    end
  end

  defp validate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil -> changeset
      slug ->
        if Regex.match?(~r/^[a-z0-9\-]+$/, slug) do
          changeset
        else
          add_error(changeset, :slug, "must contain only lowercase letters, numbers, and hyphens")
        end
    end
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        # Generate a random slug - first try to use Nanoid (which should be in deps)
        slug = try do
          # Generate random slug with 10 characters using the specified alphabet
          NanoID.generate(10, "0123456789abcdefghijklmnopqrstuvwxyz")
        rescue
          _ ->
            # Fallback to a custom implementation if Nanoid is unavailable
            alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

            1..10
            |> Enum.map(fn _ ->
              :rand.uniform(String.length(alphabet)) - 1
              |> then(fn idx -> String.at(alphabet, idx) end)
            end)
            |> Enum.join("")
        end

        put_change(changeset, :slug, slug)
      _ ->
        changeset
    end
  end

  @doc """
  Preloads the computed phase for an event.

  Sets the virtual :computed_phase field based on the current state.

  ## Examples

      iex> event = %Event{status: :polling, polling_deadline: ~U[2024-12-01 00:00:00Z]}
      iex> Event.with_computed_phase(event)
      # Returns event with computed_phase field set
  """
  def with_computed_phase(%__MODULE__{} = event) do
    phase = EventStateMachine.computed_phase(event)
    %{event | computed_phase: Atom.to_string(phase)}
  end

  @doc """
  Checks if an event has ended based on its end time.

  ## Examples

      iex> event = %Event{ends_at: ~U[2023-01-01 00:00:00Z]}
      iex> Event.ended?(event)
      true
  """
  def ended?(%__MODULE__{ends_at: nil}), do: false
  def ended?(%__MODULE__{ends_at: ends_at}) do
    DateTime.compare(DateTime.utc_now(), ends_at) == :gt
  end

  @doc """
  Checks if an event can sell tickets (confirmed status and ticketing enabled).

  ## Examples

      iex> event = %Event{status: :confirmed}
      iex> Event.can_sell_tickets?(event)
      false  # Because ticketing is not enabled by default
  """
  def can_sell_tickets?(%__MODULE__{status: :confirmed} = event) do
    EventStateMachine.is_ticketed?(event)
  end
  def can_sell_tickets?(%__MODULE__{}), do: false

  @doc """
  Checks if an event has met its threshold requirements.

  ## Examples

      iex> event = %Event{status: :threshold, threshold_count: 10}
      iex> Event.threshold_met?(event)
      false  # Because default attendee count is 0
  """
  def threshold_met?(%__MODULE__{} = event) do
    EventStateMachine.threshold_met?(event)
  end

  @doc """
  Checks if polling has ended for an event.

  ## Examples

      iex> event = %Event{polling_deadline: ~U[2023-01-01 00:00:00Z]}
      iex> Event.polling_ended?(event)
      true
  """
  def polling_ended?(%__MODULE__{polling_deadline: nil}), do: false
  def polling_ended?(%__MODULE__{polling_deadline: deadline}) do
    DateTime.compare(DateTime.utc_now(), deadline) == :gt
  end

  @doc """
  Checks if an event has an active poll (polling status and deadline not passed).

  ## Examples

      iex> future_deadline = DateTime.utc_now() |> DateTime.add(7, :day)
      iex> event = %Event{status: :polling, polling_deadline: future_deadline}
      iex> Event.active_poll?(event)
      true
  """
  def active_poll?(%__MODULE__{status: :polling, polling_deadline: nil}), do: false
  def active_poll?(%__MODULE__{status: :polling} = event) do
    not polling_ended?(event)
  end
  def active_poll?(%__MODULE__{}), do: false

  @doc """
  Preloads all virtual flags for an event.

  Sets all virtual flag fields based on the current state.

  ## Examples

      iex> event = %Event{status: :confirmed, ends_at: ~U[2025-12-01 00:00:00Z]}
      iex> Event.with_virtual_flags(event)
      # Returns event with all flag fields populated
  """
  def with_virtual_flags(%__MODULE__{} = event) do
    %{event |
      ended?: ended?(event),
      can_sell_tickets?: can_sell_tickets?(event),
      threshold_met?: threshold_met?(event),
      polling_ended?: polling_ended?(event),
      active_poll?: active_poll?(event)
    }
  end

  @doc """
  Preloads both computed phase and all virtual flags for an event.

  Convenience function that sets both the computed_phase and all flag fields.

  ## Examples

      iex> event = %Event{status: :confirmed}
      iex> Event.with_computed_fields(event)
      # Returns event with computed_phase and all flags populated
  """
  def with_computed_fields(%__MODULE__{} = event) do
    event
    |> with_computed_phase()
    |> with_virtual_flags()
  end

  @doc """
  Auto-infers and sets the status field based on event attributes.

  This is useful when creating events where you want the status
  to be automatically determined from meaningful data fields.

  ## Examples

      iex> attrs = %{threshold_count: 10, title: "Event"}
      iex> Event.changeset_with_inferred_status(%Event{}, attrs)
      # Will set status to :threshold
  """
  def changeset_with_inferred_status(event, attrs) do
    # Auto-infer status if not explicitly provided
    attrs_with_status = if Map.has_key?(attrs, :status) or Map.has_key?(attrs, "status") do
      attrs
    else
      inferred_status = EventStateMachine.infer_status(attrs)
      Map.put(attrs, :status, inferred_status)
    end

    changeset(event, attrs_with_status)
  end

  @doc """
  Gets the inferred status for an event without changing the event.

  ## Examples

      iex> event = %Event{threshold_count: 5}
      iex> Event.inferred_status(event)
      :threshold
  """
  def inferred_status(%__MODULE__{} = event) do
    EventStateMachine.infer_status(event)
  end
end
