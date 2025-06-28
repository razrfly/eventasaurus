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

        # Get Facebook identity from the user's session token
        facebook_identity = get_facebook_identity_from_session(conn)

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
  def unlink_facebook(conn, %{"identity_id" => _identity_id}) do
    # Facebook unlinking must be done from frontend using supabase.auth.unlinkIdentity()
    conn
    |> put_flash(:error, "Account unlinking must be done using the client-side method. Please use the JavaScript implementation.")
    |> redirect(to: ~p"/settings/account")
  end

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}

  defp get_facebook_identity_from_session(conn) do
    try do
      # Get the access token from the session
      access_token = get_session(conn, :access_token)

      if access_token do
        # Decode the JWT to get user metadata (basic decode without verification for metadata only)
        case decode_jwt_payload(access_token) do
          {:ok, payload} ->
            # Check app_metadata.providers for facebook
            providers = get_in(payload, ["app_metadata", "providers"]) || []

            if "facebook" in providers do
              # Return a basic facebook identity structure
              %{
                "id" => "facebook-identity",
                "provider" => "facebook",
                "created_at" => get_in(payload, ["user_metadata", "iss"]) || "Unknown",
                "identity_id" => get_in(payload, ["user_metadata", "provider_id"]) || "facebook"
              }
            else
              nil
            end

          {:error, _reason} ->
            nil
        end
      else
        nil
      end
    rescue
      _ -> nil
    end
  end

  defp decode_jwt_payload(token) do
    try do
      # Split JWT into parts
      case String.split(token, ".") do
        [_header, payload, _signature] ->
          # Decode base64 payload (add padding if needed)
          padded_payload = payload <> String.duplicate("=", rem(4 - rem(String.length(payload), 4), 4))

                    case Base.url_decode64(padded_payload) do
            {:ok, json_string} ->
              case Jason.decode(json_string) do
                {:ok, data} -> {:ok, data}
                {:error, _} -> {:error, :invalid_json}
              end

            :error -> {:error, :invalid_base64}
          end

        _ -> {:error, :invalid_jwt_format}
      end
    rescue
      _ -> {:error, :decode_error}
    end
  end
end
