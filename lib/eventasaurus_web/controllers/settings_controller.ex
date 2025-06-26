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
  Display a specific tab in the settings page.
  """
  def show_tab(conn, %{"tab" => tab} = _params) when tab in ["account", "payments"] do
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} ->
        # Get Stripe Connect account for payments tab
        connect_account = if tab == "payments", do: Stripe.get_connect_account(user.id), else: nil

        render(conn, :index,
          user: user,
          active_tab: tab,
          connect_account: connect_account
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
          {:ok, updated_user} ->
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

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
