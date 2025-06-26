defmodule EventasaurusWeb.StripeConnectController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Stripe
  alias EventasaurusApp.Accounts
  alias EventasaurusApp.Accounts.User

  require Logger

  @doc """
  Initiates the Stripe Connect OAuth flow by redirecting to Stripe.
  """
  def connect(conn, _params) do
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, %User{id: user_id}} ->
        # Check if user already has a connected account
        case Stripe.get_connect_account(user_id) do
          nil ->
            # Generate OAuth URL and redirect
            oauth_url = Stripe.connect_oauth_url(user_id)
            Logger.info("Initiating Stripe Connect OAuth for user", user_id: user_id)
            redirect(conn, external: oauth_url)

          _existing_account ->
            conn
            |> put_flash(:info, "You already have a connected Stripe account.")
            |> redirect(to: ~p"/settings/payments")
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in to connect a Stripe account.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Handles the OAuth callback from Stripe Connect.
  """
  def callback(conn, %{"code" => code, "state" => user_id_string} = _params) do
    Logger.info("Processing Stripe Connect OAuth callback",
      user_id_string: user_id_string,
      has_code: !is_nil(code)
    )

    with {user_id, ""} <- Integer.parse(user_id_string),
         %User{} = user <- Accounts.get_user(user_id),
         {:ok, oauth_response} <- Stripe.exchange_oauth_code(code),
         stripe_user_id <- oauth_response["stripe_user_id"],
         true <- is_binary(stripe_user_id) and String.length(stripe_user_id) > 0,
         {:ok, connect_account} <- Stripe.create_connect_account(user, stripe_user_id) do

      Logger.info("Successfully connected Stripe account",
        user_id: user_id,
        stripe_user_id: stripe_user_id,
        connect_account_id: connect_account.id
      )

      conn
      |> put_flash(:info, "Successfully connected your Stripe account! You can now receive payments.")
      |> redirect(to: ~p"/settings/payments")

    else
      :error ->
        Logger.error("Invalid user ID in state parameter", user_id_string: user_id_string)
        conn
        |> put_flash(:error, "Invalid callback parameters.")
        |> redirect(to: ~p"/settings/payments")

      nil ->
        Logger.error("User not found for Stripe Connect callback", user_id_string: user_id_string)
        conn
        |> put_flash(:error, "User not found. Please try connecting again.")
        |> redirect(to: ~p"/settings/payments")

      {:error, %{"error" => error_type, "error_description" => description}} ->
        Logger.error("Stripe OAuth error", error_type: error_type, description: description)
        conn
        |> put_flash(:error, "Stripe connection failed: #{description}")
        |> redirect(to: ~p"/settings/payments")

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
        Logger.error("Database error creating Stripe Connect account", errors: errors)
        conn
        |> put_flash(:error, "Failed to save your Stripe connection. Please try again.")
        |> redirect(to: ~p"/settings/payments")

      {:error, reason} when is_binary(reason) ->
        Logger.error("Stripe Connect callback error", reason: reason)
        conn
        |> put_flash(:error, "Connection failed: #{reason}")
        |> redirect(to: ~p"/settings/payments")

      false ->
        Logger.error("Invalid stripe_user_id received from Stripe OAuth response")
        conn
        |> put_flash(:error, "Invalid response from Stripe. Please try again.")
        |> redirect(to: ~p"/settings/payments")

      error ->
        Logger.error("Unexpected error in Stripe Connect callback", error: inspect(error))
        conn
        |> put_flash(:error, "Something went wrong connecting your Stripe account.")
        |> redirect(to: ~p"/settings/payments")
    end
  end

  def callback(conn, %{"error" => error_type} = params) do
    error_description = params["error_description"] || "Unknown error"

    Logger.warning("Stripe Connect OAuth error",
      error_type: error_type,
      error_description: error_description
    )

    conn
    |> put_flash(:error, "Stripe connection was cancelled or failed: #{error_description}")
    |> redirect(to: ~p"/settings/payments")
  end

  def callback(conn, params) do
    Logger.error("Invalid Stripe Connect callback parameters", params: inspect(params))

    conn
    |> put_flash(:error, "Invalid callback parameters.")
    |> redirect(to: ~p"/settings/payments")
  end

  @doc """
  Disconnects the user's Stripe Connect account.
  """
  def disconnect(conn, _params) do
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, %User{id: user_id}} ->
        case Stripe.get_connect_account(user_id) do
          nil ->
            conn
            |> put_flash(:info, "No Stripe account to disconnect.")
            |> redirect(to: ~p"/settings/payments")

          connect_account ->
            case Stripe.disconnect_connect_account(connect_account) do
              {:ok, _disconnected_account} ->
                Logger.info("Successfully disconnected Stripe account",
                  user_id: user_id,
                  stripe_user_id: connect_account.stripe_user_id
                )

                conn
                |> put_flash(:info, "Successfully disconnected your Stripe account.")
                |> redirect(to: ~p"/settings/payments")

              {:error, changeset} ->
                Logger.error("Failed to disconnect Stripe account",
                  user_id: user_id,
                  errors: inspect(changeset.errors)
                )

                conn
                |> put_flash(:error, "Failed to disconnect your Stripe account.")
                |> redirect(to: ~p"/settings/payments")
            end
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Shows the Stripe Connect status page.
  """
  def status(conn, _params) do
    case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, %User{id: user_id} = user} ->
        connect_account = Stripe.get_connect_account(user_id)
        render(conn, :status, connect_account: connect_account, user: user)

      {:error, _} ->
        conn
        |> put_flash(:error, "You must be logged in.")
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
