defmodule EventasaurusWeb.SettingsController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Stripe

  require Logger

  @doc """
  Display the settings page with account tab active by default.
  """
  def index(conn, _params) do
    # Redirect to account settings by default
    redirect(conn, to: ~p"/settings/account")
  end

  @doc """
  Display the account settings tab.
  """
  def account(conn, _params) do
    show_tab(conn, %{"tab" => "account"})
  end

  @doc """
  Display the payments settings tab.
  """
  def payments(conn, _params) do
    show_tab(conn, %{"tab" => "payments"})
  end

  @doc """
  Display the privacy settings tab.
  """
  def privacy(conn, _params) do
    show_tab(conn, %{"tab" => "privacy"})
  end

  @doc """
  Display a specific tab in the settings page.
  """
  def show_tab(conn, %{"tab" => tab} = _params) when tab in ["account", "payments", "privacy"] do
    # Use conn.assigns[:user] which is set by assign_user_struct plug (not auth_user)
    case ensure_user_struct(conn.assigns[:user]) do
      {:ok, user} ->
        # Get Stripe Connect account for payments tab
        connect_account = if tab == "payments", do: Stripe.get_connect_account(user.id), else: nil

        # Get user preferences for privacy tab
        preferences =
          if tab == "privacy" do
            case Accounts.get_or_create_preferences(user) do
              {:ok, prefs} -> prefs
              _ -> nil
            end
          else
            nil
          end

        render(conn, :index,
          user: user,
          active_tab: tab,
          connect_account: connect_account,
          preferences: preferences,
          # Facebook identity is no longer supported with Clerk auth
          facebook_identity: nil
        )

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in to access settings.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  def show_tab(conn, _params) do
    # Default to account tab if invalid tab specified
    show_tab(conn, %{"tab" => "account"})
  end

  @doc """
  Update user account information.
  """
  def update_account(conn, %{"user" => user_params} = _params) do
    # Use conn.assigns[:user] which is set by assign_user_struct plug (not auth_user)
    case ensure_user_struct(conn.assigns[:user]) do
      {:ok, user} ->
        case update_user_profile(user, user_params) do
          {:ok, _updated_user} ->
            conn
            |> put_flash(:info, "Profile updated successfully.")
            |> redirect(to: ~p"/settings/account")

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_flash(:error, "Failed to update profile. Please check the errors below.")
            |> render(:index,
              user: user,
              active_tab: "account",
              connect_account: nil,
              changeset: changeset,
              facebook_identity: nil
            )
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in to update your account.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  # Helper function to update user profile using the profile_changeset
  defp update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> EventasaurusApp.Repo.update()
  end

  @doc """
  Update user privacy preferences.
  """
  def update_privacy(conn, %{"preferences" => preferences_params} = _params) do
    case ensure_user_struct(conn.assigns[:user]) do
      {:ok, user} ->
        with {:ok, preferences} <- Accounts.get_or_create_preferences(user),
             {:ok, _updated} <- Accounts.update_preferences(preferences, preferences_params) do
          conn
          |> put_flash(:info, "Privacy settings updated successfully.")
          |> redirect(to: ~p"/settings/privacy")
        else
          {:error, %Ecto.Changeset{} = _changeset} ->
            conn
            |> put_flash(:error, "Failed to update privacy settings. Please try again.")
            |> redirect(to: ~p"/settings/privacy")

          _ ->
            conn
            |> put_flash(:error, "Failed to update privacy settings. Please try again.")
            |> redirect(to: ~p"/settings/privacy")
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in to update privacy settings.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Update user password.

  Note: With Clerk authentication, password changes are managed through
  Clerk's user management interface. This endpoint is deprecated.
  """
  def update_password(conn, _params) do
    conn
    |> put_flash(
      :info,
      "Password management is handled through your account settings. Please use the account menu to manage your password."
    )
    |> redirect(to: ~p"/settings/account")
  end

  @doc """
  Link Facebook account to the current user.

  Note: With Clerk authentication, social account linking is managed through
  Clerk's user management interface. This endpoint is deprecated.
  """
  def link_facebook(conn, _params) do
    conn
    |> put_flash(:info, "Social account linking is managed through your account settings.")
    |> redirect(to: ~p"/settings/account")
  end

  @doc """
  Unlink Facebook account from the current user.

  Note: With Clerk authentication, social account unlinking is managed through
  Clerk's user management interface. This endpoint is deprecated.
  """
  def unlink_facebook(conn, _params) do
    conn
    |> put_flash(:info, "Social account management is handled through your account settings.")
    |> redirect(to: ~p"/settings/account")
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%User{} = user), do: {:ok, user}

  # Handle Clerk JWT claims (has "sub" key for Clerk user ID)
  defp ensure_user_struct(%{"sub" => _clerk_id} = clerk_claims) do
    alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync
    ClerkSync.sync_user(clerk_claims)
  end

  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
