defmodule EventasaurusApp.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias Nanoid, as: NanoID

  # Valid states for the event state machine
  @valid_states ["confirmed", "polling"]

  # Valid transitions map
  @valid_transitions %{
    "confirmed" => ["polling"],
    "polling" => ["confirmed"]
  }

  def valid_states, do: @valid_states
  def valid_transitions, do: @valid_transitions

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
    field :state, :string, default: "confirmed" # State machine field

    # Theme fields for the theming system
    field :theme, Ecto.Enum,
      values: [:minimal, :cosmic, :velocity, :retro, :celebration, :nature, :professional],
      default: :minimal
    field :theme_customizations, :map, default: %{}

    # Virtual field for date polling validation
    field :selected_poll_dates, :string, virtual: true

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
                   :theme, :theme_customizations, :state, :selected_poll_dates])
    |> validate_required([:title, :start_at, :timezone, :visibility])
    |> validate_length(:title, min: 3, max: 100)
    |> validate_length(:tagline, max: 255)
    |> validate_length(:slug, min: 3, max: 100)
    |> validate_state()
    |> validate_slug()
    |> foreign_key_constraint(:venue_id)
    |> unique_constraint(:slug)
    |> maybe_generate_slug()
  end

  @doc """
  Check if a state transition is valid.
  """
  def can_transition_to?(current_state, new_state) when is_binary(current_state) and is_binary(new_state) do
    case Map.get(@valid_transitions, current_state) do
      nil -> false
      allowed_states -> new_state in allowed_states
    end
  end

  def can_transition_to?(%__MODULE__{state: current_state}, new_state) do
    can_transition_to?(current_state, new_state)
  end

  @doc """
  Get possible transitions from the current state.
  """
  def possible_transitions(current_state) when is_binary(current_state) do
    Map.get(@valid_transitions, current_state, [])
  end

  def possible_transitions(%__MODULE__{state: current_state}) do
    possible_transitions(current_state)
  end

  defp validate_state(changeset) do
    case get_field(changeset, :state) do
      nil -> changeset
      state when state in @valid_states -> changeset
      _invalid_state ->
        add_error(changeset, :state, "must be one of: #{Enum.join(@valid_states, ", ")}")
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
end
