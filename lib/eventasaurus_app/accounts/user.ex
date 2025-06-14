defmodule EventasaurusApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :supabase_id, :string

    many_to_many :events, EventasaurusApp.Events.Event,
      join_through: EventasaurusApp.Events.EventUser

    has_many :event_date_votes, EventasaurusApp.Events.EventDateVote
    has_many :orders, EventasaurusApp.Events.Order

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :supabase_id])
    |> validate_required([:email, :name, :supabase_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> unique_constraint(:supabase_id)
  end

  @doc """
  Generate an avatar URL for this user using DiceBear.

  Accepts options as either a keyword list or map.

  ## Examples

      iex> user = %User{email: "test@example.com"}
      iex> User.avatar_url(user)
      "https://api.dicebear.com/9.x/dylan/svg?seed=test%40example.com"

      iex> User.avatar_url(user, size: 100)
      "https://api.dicebear.com/9.x/dylan/svg?seed=test%40example.com&size=100"

      iex> User.avatar_url(user, %{size: 100, backgroundColor: "blue"})
      "https://api.dicebear.com/9.x/dylan/svg?seed=test%40example.com&size=100&backgroundColor=blue"
  """
  def avatar_url(%__MODULE__{} = user, options \\ []) do
    # Normalize keywords to map to avoid crashing later
    opts_map =
      case options do
        kw when is_list(kw) -> Enum.into(kw, %{})
        m when is_map(m) -> m
        _ -> %{}
      end

    EventasaurusApp.Avatars.generate_user_avatar(user, opts_map)
  end
end
