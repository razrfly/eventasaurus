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
  def unlink_facebook(conn, %{"identity_id" => identity_id}) do
    try do
      case EventasaurusApp.Auth.unlink_facebook_account(conn, identity_id) do
        {:ok, _result} ->
          conn
          |> put_flash(:info, "Facebook account disconnected successfully!")
          |> redirect(to: ~p"/settings/account")

        {:error, %{status: 404, message: message}} ->
          if String.contains?(message, "manual_linking_disabled") do
            conn
            |> put_flash(:error, "Account unlinking is currently disabled. Please contact support or enable manual linking in your project settings.")
            |> redirect(to: ~p"/settings/account")
          else
            conn
            |> put_flash(:error, "Failed to disconnect Facebook account. Please try again or contact support.")
            |> redirect(to: ~p"/settings/account")
          end

        {:error, %{message: message}} ->
          if String.contains?(message, "minimum_identity_count") do
            conn
            |> put_flash(:error, "Cannot disconnect Facebook account. You must have at least one other login method before disconnecting Facebook.")
            |> redirect(to: ~p"/settings/account")
          else
            conn
            |> put_flash(:error, "Failed to disconnect Facebook account. Please try again or contact support.")
            |> redirect(to: ~p"/settings/account")
          end

        {:error, reason} ->
          Logger.error("Failed to unlink Facebook account: #{inspect(reason)}")
          conn
          |> put_flash(:error, "Failed to disconnect Facebook account. Please try again or contact support.")
          |> redirect(to: ~p"/settings/account")
      end
    rescue
      error ->
        Logger.error("Exception during Facebook unlinking: #{inspect(error)}")
        conn
        |> put_flash(:error, "An unexpected error occurred. Please try again or contact support.")
        |> redirect(to: ~p"/settings/account")
    end
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

      Logger.error("DEBUG: Access token present: #{!is_nil(access_token)}")

      if access_token do
        # First check if user has Facebook provider in JWT
        case decode_jwt_payload(access_token) do
          {:ok, payload} ->
            providers = get_in(payload, ["app_metadata", "providers"]) || []
            Logger.error("DEBUG: Providers from JWT: #{inspect(providers)}")

            if "facebook" in providers do
              Logger.error("DEBUG: Facebook found in providers, creating identity")
              # User has Facebook connected - we know this from the providers list
              # Try to get actual identity details, but fall back gracefully if API fails
              facebook_identity = case EventasaurusApp.Auth.Client.get_real_user_identities(access_token) do
                {:ok, %{"identities" => identities}} when is_list(identities) ->
                  Logger.error("DEBUG: Successfully fetched #{length(identities)} identities")
                  # Find the Facebook identity with the real identity_id
                  Enum.find(identities, fn identity ->
                    identity["provider"] == "facebook"
                  end)

                {:error, reason} ->
                  Logger.error("DEBUG: Failed to fetch identities: #{inspect(reason)}")
                  nil
              end

              # Return Facebook identity (real or fallback)
              if facebook_identity do
                Logger.error("DEBUG: Using real Facebook identity")
                %{
                  "id" => facebook_identity["id"],
                  "provider" => "facebook",
                  "created_at" => facebook_identity["created_at"],
                  "identity_id" => facebook_identity["identity_id"] || facebook_identity["id"]
                }
              else
                Logger.error("DEBUG: Using fallback Facebook identity")
                # Fallback - we know Facebook is connected from providers list
                %{
                  "id" => "facebook-identity",
                  "provider" => "facebook",
                  "created_at" => get_in(payload, ["created_at"]) || "Unknown",
                  "identity_id" => get_in(payload, ["user_metadata", "provider_id"]) || "facebook"
                }
              end
            else
              Logger.error("DEBUG: Facebook NOT found in providers")
              nil
            end

          {:error, reason} ->
            Logger.error("DEBUG: JWT decode failed: #{inspect(reason)}")
            nil
        end
      else
        Logger.error("DEBUG: No access token in session")
        nil
      end
    rescue
      error -> 
        Logger.error("DEBUG: Exception in get_facebook_identity_from_session: #{inspect(error)}")
        nil
    end
  end



  # SECURITY NOTE: This function decodes JWT payloads without signature verification.
  # This is acceptable in our context because:
  # 1. The tokens are stored in server-side sessions after successful Supabase authentication
  # 2. We only extract metadata (providers list) for UI display purposes
  # 3. The tokens originated from our trusted Supabase authentication service
  # 4. This is not used for authorization decisions - only for UI state
  #
  # TODO: Consider using a proper JWT library (JOSE, Joken) for signature verification
  # in future security improvements for defense-in-depth.
  defp decode_jwt_payload(token) do
    try do
      Logger.error("DEBUG: Decoding JWT token of length: #{String.length(token)}")
      # Split JWT into parts
      case String.split(token, ".") do
        [_header, payload, _signature] ->
          Logger.error("DEBUG: JWT payload part: #{String.slice(payload, 0, 50)}...")
          # Decode base64 payload (add padding if needed)
          padded_payload = payload <> String.duplicate("=", rem(4 - rem(String.length(payload), 4), 4))

          case Base.url_decode64(padded_payload) do
            {:ok, json_string} ->
              Logger.error("DEBUG: Decoded JSON string: #{String.slice(json_string, 0, 200)}...")
              case Jason.decode(json_string) do
                {:ok, data} -> 
                  Logger.error("DEBUG: Successfully parsed JWT payload")
                  {:ok, data}
                {:error, reason} -> 
                  Logger.error("DEBUG: JSON decode failed: #{inspect(reason)}")
                  {:error, :invalid_json}
              end

            :error -> 
              Logger.error("DEBUG: Base64 decode failed")
              {:error, :invalid_base64}
          end

        parts -> 
          Logger.error("DEBUG: Invalid JWT format, got #{length(parts)} parts")
          {:error, :invalid_jwt_format}
      end
    rescue
      error -> 
        Logger.error("DEBUG: JWT decode exception: #{inspect(error)}")
        {:error, :decode_error}
    end
  end
end
