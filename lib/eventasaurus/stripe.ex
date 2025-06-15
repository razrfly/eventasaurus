defmodule EventasaurusApp.Stripe do
  @moduledoc """
  The Stripe context for handling Stripe Connect accounts.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Stripe.StripeConnectAccount
  alias EventasaurusApp.Accounts.User

  require Logger

  @doc """
  Gets a Stripe Connect account for a user.
  """
  def get_connect_account(user_id) do
    StripeConnectAccount
    |> where([s], s.user_id == ^user_id and is_nil(s.disconnected_at))
    |> Repo.one()
  end

  @doc """
  Creates a Stripe Connect account record after OAuth callback.
  """
  def create_connect_account(%User{} = user, stripe_user_id) do
    %StripeConnectAccount{}
    |> StripeConnectAccount.changeset(%{
      user_id: user.id,
      stripe_user_id: stripe_user_id,
      connected_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Disconnects a Stripe Connect account by setting the disconnected_at timestamp.
  """
  def disconnect_connect_account(%StripeConnectAccount{} = connect_account) do
    connect_account
    |> StripeConnectAccount.changeset(%{disconnected_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Checks if a user has an active Stripe Connect account.
  """
  def user_has_stripe_account?(%{id: user_id}) when is_integer(user_id) do
    case get_connect_account(user_id) do
      nil -> false
      _account -> true
    end
  end
  def user_has_stripe_account?(_), do: false

  @doc """
  Gets the Stripe publishable key for frontend use.
  """
  def get_publishable_key do
    case System.get_env("STRIPE_PUBLISHABLE_KEY") do
      nil -> raise "STRIPE_PUBLISHABLE_KEY environment variable is not set"
      publishable_key -> publishable_key
    end
  end

  @doc """
  Generates the Stripe Connect OAuth URL for the given user.
  """
  def connect_oauth_url(user_id) do
    client_id = get_stripe_client_id()
    redirect_uri = get_redirect_uri()

    query_params = URI.encode_query(%{
      "response_type" => "code",
      "client_id" => client_id,
      "scope" => "read_write",
      "redirect_uri" => redirect_uri,
      "state" => to_string(user_id)
    })

    "https://connect.stripe.com/oauth/authorize?" <> query_params
  end

  @doc """
  Exchanges an OAuth authorization code for Stripe Connect credentials.
  """
  def exchange_oauth_code(code) when is_binary(code) do
    Logger.info("Exchanging OAuth code for Stripe Connect credentials")

    url = "https://connect.stripe.com/oauth/token"
    secret_key = get_stripe_secret_key()

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Bearer #{secret_key}"}
    ]

    body = URI.encode_query(%{
      "grant_type" => "authorization_code",
      "code" => code,
      "client_secret" => secret_key
    })

    case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, response_data} ->
            Logger.info("Successfully exchanged OAuth code", %{
              stripe_user_id: response_data["stripe_user_id"],
              livemode: response_data["livemode"]
            })
            {:ok, response_data}

          {:error, decode_error} ->
            Logger.error("Failed to decode Stripe OAuth response", %{
              error: inspect(decode_error),
              response_body: response_body
            })
            {:error, "Invalid response format from Stripe"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, error_data} ->
            Logger.error("Stripe OAuth error response", %{
              status_code: status_code,
              error: error_data["error"],
              error_description: error_data["error_description"]
            })
            {:error, error_data}

          {:error, _} ->
            Logger.error("Stripe OAuth error with invalid JSON", %{
              status_code: status_code,
              response_body: response_body
            })
            {:error, "Stripe returned an error: HTTP #{status_code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during Stripe OAuth exchange", %{reason: inspect(reason)})
        {:error, "Network error connecting to Stripe: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected error during Stripe OAuth exchange", %{error: inspect(error)})
        {:error, "Unexpected error during OAuth exchange"}
    end
  end

  def exchange_oauth_code(_), do: {:error, "Invalid authorization code"}

  # Private helper functions

  defp get_stripe_client_id do
    case System.get_env("STRIPE_CLIENT_ID") do
      nil -> raise "STRIPE_CLIENT_ID environment variable is not set"
      client_id -> client_id
    end
  end

  defp get_stripe_secret_key do
    case System.get_env("STRIPE_SECRET_KEY") do
      nil -> raise "STRIPE_SECRET_KEY environment variable is not set"
      secret_key -> secret_key
    end
  end

  defp get_redirect_uri do
    base_url = get_base_url()
    "#{base_url}/stripe/callback"
  end

  defp get_base_url do
    # In production, this should be your actual domain
    # In development, use localhost
    case System.get_env("PHX_HOST") do
      nil -> "http://localhost:4000"
      host -> "https://#{host}"
    end
  end
end
