defmodule EventasaurusApp.Accounts.UserPreferences do
  @moduledoc """
  User preferences for privacy and social features.

  This schema stores user-controlled settings for how others can interact
  with them on the platform. It follows privacy-first design principles:

  - Users control their own boundaries
  - No request fatigue (silent permission checks, not accept/reject flows)
  - Extensible for future preference types

  ## Connection Permissions

  Controls who can add the user to their "people" network:

  - `:closed` - Only the user can initiate connections
  - `:event_attendees` - Only people from shared events can connect (default)
  - `:extended_network` - People connected to existing relationships (friends of friends)
  - `:open` - Anyone on the platform can connect

  ## Future Preferences (reserved)

  - `show_on_attendee_lists` - Whether to appear on event attendee lists
  - `discoverable_in_suggestions` - Whether to appear in "suggested connections"
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type connection_permission :: :closed | :event_attendees | :extended_network | :open

  @type t :: %__MODULE__{
          id: integer(),
          user_id: integer(),
          connection_permission: connection_permission(),
          show_on_attendee_lists: boolean(),
          discoverable_in_suggestions: boolean(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "user_preferences" do
    belongs_to(:user, EventasaurusApp.Accounts.User)

    field(:connection_permission, Ecto.Enum,
      values: [:closed, :event_attendees, :extended_network, :open],
      default: :event_attendees
    )

    # Future preferences (reserved for later phases)
    field(:show_on_attendee_lists, :boolean, default: true)
    field(:discoverable_in_suggestions, :boolean, default: true)

    timestamps()
  end

  @doc """
  Creates a changeset for user preferences.

  ## Examples

      iex> changeset(%UserPreferences{}, %{connection_permission: :closed})
      #Ecto.Changeset<...>
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [
      :user_id,
      :connection_permission,
      :show_on_attendee_lists,
      :discoverable_in_suggestions
    ])
    |> validate_required([:user_id])
    |> validate_inclusion(:connection_permission, [:closed, :event_attendees, :extended_network, :open])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for updating preferences (excludes user_id).

  ## Examples

      iex> update_changeset(%UserPreferences{}, %{connection_permission: :open})
      #Ecto.Changeset<...>
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [
      :connection_permission,
      :show_on_attendee_lists,
      :discoverable_in_suggestions
    ])
    |> validate_inclusion(:connection_permission, [:closed, :event_attendees, :extended_network, :open])
  end

  @doc """
  Returns the default preferences for a new user.

  ## Examples

      iex> defaults()
      %{connection_permission: :event_attendees, show_on_attendee_lists: true, discoverable_in_suggestions: true}
  """
  @spec defaults() :: map()
  def defaults do
    %{
      connection_permission: :event_attendees,
      show_on_attendee_lists: true,
      discoverable_in_suggestions: true
    }
  end

  @doc """
  Returns human-readable label for a connection permission level.

  ## Examples

      iex> permission_label(:closed)
      "Let me reach out first"

      iex> permission_label(:event_attendees)
      "People I've been to events with"
  """
  @spec permission_label(connection_permission()) :: String.t()
  def permission_label(:closed), do: "Let me reach out first"
  def permission_label(:event_attendees), do: "People I've been to events with"
  def permission_label(:extended_network), do: "People in my extended network"
  def permission_label(:open), do: "Open to everyone"

  @doc """
  Returns description for a connection permission level.

  ## Examples

      iex> permission_description(:closed)
      "Only you can initiate connections"
  """
  @spec permission_description(connection_permission()) :: String.t()
  def permission_description(:closed), do: "Only you can initiate connections"

  def permission_description(:event_attendees),
    do: "People who attended the same events as you"

  def permission_description(:extended_network),
    do: "People connected to your existing connections"

  def permission_description(:open), do: "Anyone on Eventasaurus can reach out"
end
