defmodule EventasaurusApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field(:email, :string)
    field(:name, :string)

    # Profile fields
    field(:username, :string)
    field(:bio, :string)
    field(:website_url, :string)
    field(:profile_public, :boolean, default: true)

    # Social media handles
    field(:instagram_handle, :string)
    field(:x_handle, :string)
    field(:youtube_handle, :string)
    field(:tiktok_handle, :string)
    field(:linkedin_handle, :string)

    # User preferences
    field(:default_currency, :string, default: "USD")
    field(:timezone, :string)

    # Referral tracking
    field(:referral_event_id, :id)

    belongs_to(:referral_event, EventasaurusApp.Events.Event,
      define_field: false,
      foreign_key: :referral_event_id
    )

    many_to_many(:events, EventasaurusApp.Events.Event,
      join_through: EventasaurusApp.Events.EventUser
    )

    many_to_many(:groups, EventasaurusApp.Groups.Group,
      join_through: EventasaurusApp.Groups.GroupUser
    )

    has_many(:poll_votes, EventasaurusApp.Events.PollVote, foreign_key: :voter_id)
    has_many(:orders, EventasaurusApp.Events.Order)

    # Following relationships
    has_many(:user_performer_follows, EventasaurusApp.Follows.UserPerformerFollow)
    has_many(:followed_performers, through: [:user_performer_follows, :performer])

    has_many(:user_venue_follows, EventasaurusApp.Follows.UserVenueFollow)
    has_many(:followed_venues, through: [:user_venue_follows, :venue])

    # User preferences for privacy and social features
    has_one(:preferences, EventasaurusApp.Accounts.UserPreferences)

    timestamps()
  end

  @username_regex ~r/^[a-zA-Z0-9_-]{3,30}$/
  @url_regex ~r/^https?:\/\/.+/

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :username,
      :bio,
      :website_url,
      :profile_public,
      :instagram_handle,
      :x_handle,
      :youtube_handle,
      :tiktok_handle,
      :linkedin_handle,
      :default_currency,
      :timezone,
      :referral_event_id
    ])
    |> validate_required([:email, :name])
    |> normalize_email()
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> validate_username()
    |> validate_bio()
    |> validate_website_url()
    |> validate_social_handles()
    |> validate_currency()
    |> unique_constraint(:email)
    |> unique_constraint(:username, name: :users_username_lower_index)
  end

  @doc """
  Changeset specifically for profile updates (excludes email).
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :name,
      :username,
      :bio,
      :website_url,
      :profile_public,
      :instagram_handle,
      :x_handle,
      :youtube_handle,
      :tiktok_handle,
      :linkedin_handle,
      :default_currency,
      :timezone
    ])
    |> validate_required([:name])
    |> validate_username()
    |> validate_bio()
    |> validate_website_url()
    |> validate_social_handles()
    |> validate_currency()
    |> unique_constraint(:username, name: :users_username_lower_index)
  end

  # Private validation functions

  defp normalize_email(changeset) do
    case get_change(changeset, :email) do
      nil ->
        changeset

      email when is_binary(email) ->
        # Use the existing sanitize_email function which trims and downcases
        case EventasaurusApp.Sanitizer.sanitize_email(email) do
          {:error, reason} ->
            add_error(changeset, :email, "has invalid format: #{to_string(reason)}")

          nil ->
            add_error(changeset, :email, "cannot be blank")

          normalized_email when is_binary(normalized_email) ->
            put_change(changeset, :email, normalized_email)
        end

      _ ->
        add_error(changeset, :email, "must be a string")
    end
  end

  defp validate_username(changeset) do
    changeset
    |> validate_format(:username, @username_regex,
      message:
        "must be 3-30 characters and contain only letters, numbers, underscores, and hyphens"
    )
    |> validate_not_reserved_username()
  end

  defp validate_not_reserved_username(changeset) do
    case get_change(changeset, :username) do
      nil ->
        changeset

      username ->
        if reserved_username?(username) do
          add_error(changeset, :username, "is reserved and cannot be used")
        else
          changeset
        end
    end
  end

  defp validate_bio(changeset) do
    changeset
    |> validate_length(:bio, max: 500, message: "must be 500 characters or less")
  end

  defp validate_website_url(changeset) do
    case get_change(changeset, :website_url) do
      nil ->
        changeset

      "" ->
        changeset

      url ->
        if String.match?(url, @url_regex) do
          changeset
        else
          add_error(
            changeset,
            :website_url,
            "must be a valid URL starting with http:// or https://"
          )
        end
    end
  end

  defp validate_social_handles(changeset) do
    changeset
    |> normalize_social_handle(:instagram_handle)
    |> normalize_social_handle(:x_handle)
    |> normalize_social_handle(:youtube_handle)
    |> normalize_social_handle(:tiktok_handle)
    |> normalize_social_handle(:linkedin_handle)
    |> validate_length(:instagram_handle, max: 30)
    |> validate_length(:x_handle, max: 15)
    |> validate_length(:youtube_handle, max: 100)
    |> validate_length(:tiktok_handle, max: 25)
    |> validate_length(:linkedin_handle, max: 100)
  end

  defp normalize_social_handle(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      "" ->
        changeset

      handle ->
        # Remove @ symbol if present
        normalized = String.replace(handle, ~r/^@/, "")
        put_change(changeset, field, normalized)
    end
  end

  defp validate_currency(changeset) do
    # Get comprehensive list of valid currency codes from CurrencyHelpers
    valid_currencies = EventasaurusWeb.Helpers.CurrencyHelpers.supported_currency_codes()

    # Also include uppercase versions for backwards compatibility
    all_valid_currencies = valid_currencies ++ Enum.map(valid_currencies, &String.upcase/1)

    changeset
    |> validate_inclusion(:default_currency, all_valid_currencies,
      message: "must be a valid currency code"
    )
  end

  # Reserved username checking
  defp reserved_username?(username) when is_binary(username) do
    username_lower = String.downcase(username)
    username_lower in get_reserved_usernames()
  end

  defp get_reserved_usernames do
    reserved_usernames_path = Application.app_dir(:eventasaurus, "priv/reserved_usernames.txt")

    case File.read(reserved_usernames_path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(fn line ->
          line == "" or String.starts_with?(line, "#")
        end)
        |> Enum.map(&String.downcase/1)

      {:error, _} ->
        # Fallback list if file is not found
        [
          "admin",
          "administrator",
          "root",
          "system",
          "support",
          "help",
          "api",
          "www",
          "about",
          "contact",
          "privacy",
          "terms",
          "login",
          "logout",
          "signup",
          "register",
          "dashboard",
          "events",
          "orders",
          "tickets",
          "checkout",
          "profile",
          "settings"
        ]
    end
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

  @doc """
  Get the display name for a user (username if available, otherwise name)
  """
  def display_name(%__MODULE__{username: username, name: _name}) when is_binary(username) do
    username
  end

  def display_name(%__MODULE__{name: name}) do
    name
  end

  @doc """
  Get the canonical profile URL for a user (/users/:username)
  """
  def profile_url(%__MODULE__{username: username}) when is_binary(username) do
    "/users/#{username}"
  end

  def profile_url(%__MODULE__{id: id}) do
    "/users/user-#{id}"
  end

  @doc """
  Get the short profile URL for a user (/u/:username)
  """
  def short_profile_url(%__MODULE__{username: username}) when is_binary(username) do
    "/u/#{username}"
  end

  def short_profile_url(%__MODULE__{id: id}) do
    "/u/#{id}"
  end

  @doc """
  Get the username slug for a user (same as username for SEO-friendly URLs)
  """
  def username_slug(%__MODULE__{username: username}) when is_binary(username) do
    username
  end

  def username_slug(%__MODULE__{id: id}) do
    "user-#{id}"
  end

  @doc """
  Generate a shareable profile link with domain
  """
  def shareable_profile_url(%__MODULE__{} = user, base_url \\ "https://eventasaurus.com") do
    "#{base_url}#{profile_url(user)}"
  end

  @doc """
  Check if user has a custom username (not just an ID-based fallback)
  """
  def has_username?(%__MODULE__{username: username}) when is_binary(username), do: true
  def has_username?(%__MODULE__{}), do: false

  @doc """
  Get profile handle for display (@username)
  """
  def profile_handle(%__MODULE__{username: username}) when is_binary(username) do
    "@#{username}"
  end

  def profile_handle(%__MODULE__{id: id}) do
    "@user-#{id}"
  end

  @doc """
  Check if a user's profile is public
  """
  def profile_public?(%__MODULE__{profile_public: public}) do
    public == true
  end

  @doc """
  Generate profile meta tags for SEO and social sharing
  """
  def profile_meta_tags(%__MODULE__{} = user) do
    %{
      title: "#{display_name(user)} (@#{username_slug(user)}) - Eventasaurus",
      description: user.bio || "#{display_name(user)}'s profile on Eventasaurus",
      canonical_url: profile_url(user),
      og_title: "#{display_name(user)} on Eventasaurus",
      og_description: user.bio || "Check out #{display_name(user)}'s profile on Eventasaurus",
      og_url: shareable_profile_url(user),
      og_image: avatar_url(user, size: 400),
      twitter_card: "summary",
      twitter_title: "#{display_name(user)} (@#{username_slug(user)})",
      twitter_description: user.bio || "#{display_name(user)}'s profile on Eventasaurus",
      twitter_image: avatar_url(user, size: 400)
    }
  end
end
