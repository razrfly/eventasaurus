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
      draft: [:polling, :threshold, :confirmed, :canceled],
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
  @valid_statuses [:draft, :polling, :threshold, :confirmed, :canceled]
  @valid_threshold_types ["attendee_count", "revenue", "both"]
  @valid_taxation_types ["ticketed_event", "contribution_collection", "ticketless"]

  def valid_statuses, do: @valid_statuses
  def valid_threshold_types, do: @valid_threshold_types
  def valid_taxation_types, do: @valid_taxation_types

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
    field :rich_external_data, :map, default: %{} # for comprehensive external API data
    field :status, Ecto.Enum, values: [:draft, :polling, :threshold, :confirmed, :canceled], default: :confirmed
    field :polling_deadline, :utc_datetime
    field :threshold_count, :integer
    field :threshold_type, :string, default: "attendee_count"
    field :threshold_revenue_cents, :integer
    field :canceled_at, :utc_datetime
    field :is_ticketed, :boolean, default: false
    field :taxation_type, :string, default: "ticketless"
    field :virtual_venue_url, :string # for virtual meeting URLs

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
    has_many :tickets, EventasaurusApp.Events.Ticket, on_delete: :delete_all
    has_many :orders, EventasaurusApp.Events.Order, on_delete: :delete_all
    has_many :polls, EventasaurusApp.Events.Poll, on_delete: :delete_all

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    # Convert empty strings to nil for threshold_revenue_cents
    attrs = normalize_threshold_revenue_cents(attrs)

    event
    |> cast(attrs, [:title, :tagline, :description, :start_at, :ends_at, :timezone,
                   :visibility, :slug, :cover_image_url, :venue_id, :external_image_data,
                   :rich_external_data, :theme, :theme_customizations, :status, :polling_deadline, :threshold_count,
                   :threshold_type, :threshold_revenue_cents, :canceled_at, :selected_poll_dates,
                   :virtual_venue_url, :is_ticketed, :taxation_type])
    |> validate_required([:title, :timezone, :visibility])
    |> validate_virtual_venue_url()
    |> maybe_validate_start_at()
    |> validate_length(:title, min: 3, max: 100)
    |> validate_length(:tagline, max: 255)
    |> validate_length(:slug, min: 3, max: 100)
    |> validate_status()
    |> validate_slug()
    |> validate_polling_deadline()
    |> validate_threshold_count()
    |> validate_threshold_type()
    |> validate_threshold_revenue_cents()
    |> validate_threshold_consistency()
    |> validate_taxation_type()
    |> validate_taxation_consistency()
    |> validate_canceled_at()
    |> validate_status_consistency()
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint(:slug)
    |> check_constraint(:taxation_type, name: :valid_taxation_type)
    |> maybe_generate_slug()
  end

  # Helper function to normalize threshold_revenue_cents field
  defp normalize_threshold_revenue_cents(attrs) when is_map(attrs) do
    case Map.get(attrs, "threshold_revenue_cents") do
      nil -> attrs
      "" -> Map.put(attrs, "threshold_revenue_cents", nil)
      value when is_binary(value) ->
        if String.trim(value) == "" do
          Map.put(attrs, "threshold_revenue_cents", nil)
        else
          attrs
        end
      _ -> attrs
    end
  end
  defp normalize_threshold_revenue_cents(attrs), do: attrs

  # Note: Transition logic is handled by Machinery state machine
  # See lib/eventasaurus_app/event_state_machine.ex for transition rules

  defp validate_status(changeset) do
    case get_field(changeset, :status) do
      nil -> changeset
      status when status in [:draft, :polling, :threshold, :confirmed, :canceled] -> changeset
      _invalid_status ->
        valid_statuses_str = @valid_statuses |> Enum.map(&to_string/1) |> Enum.join(", ")
        add_error(changeset, :status, "must be one of: #{valid_statuses_str}")
    end
  end

  defp validate_threshold_type(changeset) do
    case get_field(changeset, :threshold_type) do
      nil ->
        put_change(changeset, :threshold_type, "attendee_count")
      threshold_type when threshold_type in @valid_threshold_types ->
        changeset
      _invalid_type ->
        valid_types_str = @valid_threshold_types |> Enum.join(", ")
        add_error(changeset, :threshold_type, "must be one of: #{valid_types_str}")
    end
  end

  defp validate_taxation_type(changeset) do
    case get_field(changeset, :taxation_type) do
      nil ->
        put_change(changeset, :taxation_type, "ticketless")
      taxation_type when taxation_type in @valid_taxation_types ->
        changeset
      _invalid_type ->
        valid_types_str = @valid_taxation_types |> Enum.join(", ")
        add_error(changeset, :taxation_type, "must be one of: #{valid_types_str}")
    end
  end

  defp validate_taxation_consistency(changeset) do
    taxation_type = get_field(changeset, :taxation_type)
    is_ticketed = get_field(changeset, :is_ticketed)

    case {taxation_type, is_ticketed} do
      # Ticketless events cannot have ticketing enabled
      {"ticketless", true} ->
        add_error(changeset, :is_ticketed, "must be false for ticketless events")
      # Contribution collections cannot have ticketing enabled
      {"contribution_collection", true} ->
        add_error(changeset, :is_ticketed, "must be false for contribution collection events")
      # All other combinations are valid
      _ ->
        changeset
    end
  end

  @doc """
  Validates that events with existing tickets cannot be set to ticketless.
  This should be called when updating an event that might have tickets.
  """
  def validate_tickets_taxation_consistency(%Ecto.Changeset{} = changeset, tickets_count \\ 0) do
    taxation_type = get_field(changeset, :taxation_type)

    case {taxation_type, tickets_count} do
      # Cannot set to ticketless if tickets exist
      {"ticketless", count} when count > 0 ->
        add_error(changeset, :taxation_type, "cannot be set to ticketless when tickets exist. Please delete all tickets first or choose a different taxation type.")

      # All other combinations are valid
      _ ->
        changeset
    end
  end

  defp validate_threshold_revenue_cents(changeset) do
    case get_field(changeset, :threshold_revenue_cents) do
      nil -> changeset
      revenue when is_integer(revenue) and revenue >= 0 -> changeset
      _invalid_revenue ->
        add_error(changeset, :threshold_revenue_cents, "must be a non-negative integer")
    end
  end

  defp validate_threshold_consistency(changeset) do
    threshold_type = get_field(changeset, :threshold_type)
    threshold_count = get_field(changeset, :threshold_count)
    threshold_revenue_cents = get_field(changeset, :threshold_revenue_cents)
    status = get_field(changeset, :status)

    case {status, threshold_type, threshold_count, threshold_revenue_cents} do
      # If status is threshold, we need appropriate threshold values
      {:threshold, "attendee_count", nil, _} ->
        add_error(changeset, :threshold_count, "is required when threshold type is attendee_count")

      {:threshold, "revenue", _, nil} ->
        add_error(changeset, :threshold_revenue_cents, "is required when threshold type is revenue")

      {:threshold, "both", nil, _} ->
        add_error(changeset, :threshold_count, "is required when threshold type is both")

      {:threshold, "both", _, nil} ->
        add_error(changeset, :threshold_revenue_cents, "is required when threshold type is both")

      _ ->
        changeset
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
    threshold_type = get_field(changeset, :threshold_type)
    threshold_count = get_field(changeset, :threshold_count)

    case {status, threshold_type, threshold_count} do
      # For threshold events with revenue-only type, threshold_count is not required
      {:threshold, "revenue", _} ->
        changeset
      # For attendee_count and both types, threshold_count is required
      {:threshold, type, nil} when type in ["attendee_count", "both"] ->
        add_error(changeset, :threshold_count, "is required when threshold type is #{type}")
      {:threshold, _type, count} when is_integer(count) and count > 0 ->
        changeset
      {:threshold, _type, _} ->
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
    # Simplified validation - just ensure status is valid
    # Status inference and auto-correction happens at the context level
    changeset
  end

  defp maybe_validate_start_at(changeset) do
    case get_field(changeset, :status) do
      status when status in [:confirmed, :threshold] ->
        validate_required(changeset, [:start_at])
      _ ->
        changeset
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

  defp validate_virtual_venue_url(changeset) do
    case get_change(changeset, :virtual_venue_url) do
      nil -> changeset
      "" -> changeset
      url ->
        if valid_url?(url) do
          changeset
        else
          add_error(changeset, :virtual_venue_url, "must be a valid URL")
        end
    end
  end

  defp valid_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] && uri.host != nil
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
      # Use atom keys for direct API calls, string keys for form data
      if is_atom(Map.keys(attrs) |> List.first()) do
        Map.put(attrs, :status, inferred_status)
      else
        Map.put(attrs, "status", to_string(inferred_status))
      end
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

  # ============================================================================
  # Rich External Data Helper Functions
  # ============================================================================

  @doc """
  Gets TMDB data from rich_external_data field.

  ## Examples

      iex> event = %Event{rich_external_data: %{"tmdb" => %{"id" => 123, "title" => "Movie"}}}
      iex> Event.get_tmdb_data(event)
      %{"id" => 123, "title" => "Movie"}

      iex> event = %Event{rich_external_data: %{}}
      iex> Event.get_tmdb_data(event)
      nil
  """
  def get_tmdb_data(%__MODULE__{rich_external_data: nil}), do: nil
  def get_tmdb_data(%__MODULE__{rich_external_data: data}) when is_map(data) do
    Map.get(data, "tmdb")
  end
  def get_tmdb_data(%__MODULE__{}), do: nil

  @doc """
  Sets TMDB data in rich_external_data field.

  ## Examples

      iex> event = %Event{rich_external_data: %{}}
      iex> tmdb_data = %{"id" => 123, "title" => "Movie"}
      iex> Event.put_tmdb_data(event, tmdb_data)
      %Event{rich_external_data: %{"tmdb" => %{"id" => 123, "title" => "Movie"}}}
  """
  def put_tmdb_data(%__MODULE__{} = event, tmdb_data) when is_map(tmdb_data) do
    rich_data = event.rich_external_data || %{}
    updated_data = Map.put(rich_data, "tmdb", tmdb_data)
    %{event | rich_external_data: updated_data}
  end

  @doc """
  Checks if event has TMDB data.

  ## Examples

      iex> event = %Event{rich_external_data: %{"tmdb" => %{"id" => 123}}}
      iex> Event.has_tmdb_data?(event)
      true

      iex> event = %Event{rich_external_data: %{}}
      iex> Event.has_tmdb_data?(event)
      false
  """
  def has_tmdb_data?(%__MODULE__{} = event) do
    case get_tmdb_data(event) do
      nil -> false
      data when is_map(data) -> map_size(data) > 0
      _ -> false
    end
  end

  @doc """
  Gets provider data from rich_external_data field.

  ## Examples

      iex> event = %Event{rich_external_data: %{"spotify" => %{"id" => "abc123"}}}
      iex> Event.get_provider_data(event, "spotify")
      %{"id" => "abc123"}
  """
  def get_provider_data(%__MODULE__{rich_external_data: nil}, _provider), do: nil
  def get_provider_data(%__MODULE__{rich_external_data: data}, provider) when is_map(data) and is_binary(provider) do
    Map.get(data, provider)
  end
  def get_provider_data(%__MODULE__{}, _provider), do: nil

  @doc """
  Sets provider data in rich_external_data field.

  ## Examples

      iex> event = %Event{rich_external_data: %{}}
      iex> Event.put_provider_data(event, "spotify", %{"id" => "abc123"})
      %Event{rich_external_data: %{"spotify" => %{"id" => "abc123"}}}
  """
  def put_provider_data(%__MODULE__{} = event, provider, data) when is_binary(provider) and is_map(data) do
    rich_data = event.rich_external_data || %{}
    updated_data = Map.put(rich_data, provider, data)
    %{event | rich_external_data: updated_data}
  end

  @doc """
  Removes provider data from rich_external_data field.

  ## Examples

      iex> event = %Event{rich_external_data: %{"tmdb" => %{"id" => 123}, "spotify" => %{"id" => "abc"}}}
      iex> Event.remove_provider_data(event, "spotify")
      %Event{rich_external_data: %{"tmdb" => %{"id" => 123}}}
  """
  def remove_provider_data(%__MODULE__{} = event, provider) when is_binary(provider) do
    rich_data = event.rich_external_data || %{}
    updated_data = Map.delete(rich_data, provider)
    %{event | rich_external_data: updated_data}
  end

  @doc """
  Checks if event has any external provider data.

  ## Examples

      iex> event = %Event{rich_external_data: %{"tmdb" => %{"id" => 123}}}
      iex> Event.has_external_data?(event)
      true

      iex> event = %Event{rich_external_data: %{}}
      iex> Event.has_external_data?(event)
      false
  """
  def has_external_data?(%__MODULE__{rich_external_data: nil}), do: false
  def has_external_data?(%__MODULE__{rich_external_data: data}) when is_map(data) do
    map_size(data) > 0
  end
  def has_external_data?(%__MODULE__{}), do: false

  @doc """
  Lists all providers that have data for this event.

  ## Examples

      iex> event = %Event{rich_external_data: %{"tmdb" => %{"id" => 123}, "spotify" => %{"id" => "abc"}}}
      iex> Event.list_providers(event)
      ["tmdb", "spotify"]
  """
  def list_providers(%__MODULE__{rich_external_data: nil}), do: []
  def list_providers(%__MODULE__{rich_external_data: data}) when is_map(data) do
    Map.keys(data)
  end
  def list_providers(%__MODULE__{}), do: []
end
