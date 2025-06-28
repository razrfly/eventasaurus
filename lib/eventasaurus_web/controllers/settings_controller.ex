defmodule EventasaurusWeb.SettingsController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User
  alias EventasaurusApp.Stripe
  alias EventasaurusApp.Auth

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
  Display a specific tab in the settings page.
  """
  def show_tab(conn, %{"tab" => tab} = _params) when tab in ["account", "payments"] do
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} ->
        # Get Stripe Connect account for payments tab
        connect_account = if tab == "payments", do: Stripe.get_connect_account(user.id), else: nil

        # Get Facebook identity for account tab
        facebook_identity = if tab == "account" do
          identities = get_user_identities(conn)
          # Get the first Facebook identity (should only be one)
          List.first(identities)
        else
          nil
        end

        render(conn, :index,
          user: user,
          active_tab: tab,
          connect_account: connect_account,
          facebook_identity: facebook_identity
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
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} ->
        case Accounts.update_user(user, user_params) do
          {:ok, _updated_user} ->
            conn
            |> put_flash(:info, "Account updated successfully.")
            |> redirect(to: ~p"/settings/account")

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_flash(:error, "Failed to update account. Please check the errors below.")
            |> render(:index,
              user: user,
              active_tab: "account",
              connect_account: nil,
              changeset: changeset
            )
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in to update your account.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Update user password.
  """
  def update_password(conn, %{"password" => password_params} = _params) do
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} ->
        current_password = password_params["current_password"]
        new_password = password_params["new_password"]
        confirm_password = password_params["confirm_password"]

        cond do
          is_nil(current_password) or String.trim(current_password) == "" ->
            conn
            |> put_flash(:error, "Current password is required.")
            |> redirect(to: ~p"/settings/account")

          is_nil(new_password) or String.length(new_password) < 6 ->
            conn
            |> put_flash(:error, "New password must be at least 6 characters long.")
            |> redirect(to: ~p"/settings/account")

          new_password != confirm_password ->
            conn
            |> put_flash(:error, "New password and confirmation do not match.")
            |> redirect(to: ~p"/settings/account")

          true ->
            # First verify current password by attempting to authenticate
            case EventasaurusApp.Auth.authenticate(user.email, current_password) do
              {:ok, _auth_data} ->
                # Current password is correct, update to new password
                case EventasaurusApp.Auth.update_current_user_password(conn, new_password) do
                  {:ok, _result} ->
                    conn
                    |> put_flash(:info, "Password updated successfully.")
                    |> redirect(to: ~p"/settings/account")

                  {:error, reason} ->
                    error_message = case reason do
                      :no_authentication_token -> "Authentication session expired. Please log in again."
                      _ -> "Failed to update password. Please try again."
                    end

                    conn
                    |> put_flash(:error, error_message)
                    |> redirect(to: ~p"/settings/account")
                end

              {:error, _reason} ->
                conn
                |> put_flash(:error, "Current password is incorrect.")
                |> redirect(to: ~p"/settings/account")
            end
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in to update your password.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Link Facebook account to the current user.
  """
  def link_facebook(conn, _params) do
    # Store marker that this is for linking (let Supabase handle CSRF state)
    conn = put_session(conn, :oauth_action, "link")

    # Get Facebook OAuth URL and redirect (without custom state)
    facebook_url = EventasaurusApp.Auth.get_facebook_oauth_url()
    redirect(conn, external: facebook_url)
  end

  @doc """
  Unlink Facebook account from the current user.
  """
  def unlink_facebook(conn, %{"identity_id" => identity_id}) do
    # Facebook unlinking must be done from frontend using supabase.auth.unlinkIdentity()
    conn
    |> put_flash(:error, "Account unlinking must be done using the client-side method. Please use the JavaScript implementation.")
    |> redirect(to: ~p"/settings/account")
  end

  @doc """
  Get user's linked identities (for displaying connected accounts).
  """
  def get_user_identities(conn) do
    case Auth.get_user_identities(conn) do
      {:ok, response} ->
        # Extract identities array from response
        identities = Map.get(response, "identities", [])

        # Transform into our format and find Facebook identity
        Enum.map(identities, fn identity ->
          provider = Map.get(identity, "provider")

          %{
            provider: provider,
            connected: true,
            display_name: String.capitalize(provider)
          }
        end)

      {:error, reason} ->
        Logger.error("Failed to retrieve user identities for settings page: #{inspect(reason)}")
        # Return empty list so page doesn't crash
        []
    end
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
