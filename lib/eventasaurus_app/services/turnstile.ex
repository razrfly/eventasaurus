defmodule EventasaurusApp.Services.Turnstile do
  @moduledoc """
  Module for verifying Cloudflare Turnstile tokens to prevent bot signups.
  """

  require Logger

  @verify_endpoint "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc """
  Verifies a Turnstile token with Cloudflare's API.
  
  Returns {:ok, true} if the token is valid, {:ok, false} if invalid,
  or {:error, reason} if the verification fails.
  """
  def verify_token(token) when is_binary(token) do
    config = Application.get_env(:eventasaurus, :turnstile, [])
    
    case config[:secret_key] do
      nil ->
        Logger.warning("Turnstile secret key not configured")
        {:error, :not_configured}
        
      secret_key ->
        perform_verification(token, secret_key)
    end
  end
  
  def verify_token(_), do: {:error, :invalid_token}

  defp perform_verification(token, secret_key) do
    body = URI.encode_query(%{
      "secret" => secret_key,
      "response" => token
    })
    
    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "application/json"}
    ]
    
    case HTTPoison.post(@verify_endpoint, body, headers, timeout: 5000, recv_timeout: 5000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        parse_verification_response(response_body)
        
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        Logger.error("Turnstile API returned status #{status_code}")
        {:error, :api_error}
        
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Turnstile verification failed: #{inspect(reason)}")
        {:error, :network_error}
    end
  end
  
  defp parse_verification_response(body) do
    case Jason.decode(body) do
      {:ok, %{"success" => true}} ->
        Logger.debug("Turnstile verification successful")
        {:ok, true}
        
      {:ok, %{"success" => false, "error-codes" => errors}} ->
        Logger.warning("Turnstile verification failed: #{inspect(errors)}")
        {:ok, false}
        
      {:ok, %{"success" => false}} ->
        Logger.warning("Turnstile verification failed (no error codes)")
        {:ok, false}
        
      {:error, _} ->
        Logger.error("Failed to parse Turnstile response")
        {:error, :invalid_response}
    end
  end

  @doc """
  Checks if Turnstile is configured with both keys.
  """
  def enabled? do
    config = Application.get_env(:eventasaurus, :turnstile, [])
    config[:site_key] != nil && config[:secret_key] != nil
  end
end