defmodule EventasaurusWeb.Helpers.TicketCrypto do
  @moduledoc """
  Shared cryptographic functions for ticket operations.

  This module centralizes ticket-related cryptographic operations to ensure
  consistency across the application and eliminate code duplication.
  """

  @doc """
  Generate a deterministic secret key for ticket signing operations.

  Uses the Phoenix secret key base as entropy source, with a fallback
  to a deterministic key if the secret key base is unavailable.

  Returns a 32-byte binary suitable for HMAC operations.
  """
  def get_ticket_secret_key do
    # Use Phoenix secret key base as entropy source for ticket signatures
    # Use get_in/2 to safely handle nil endpoint config
    secret_base =
      get_in(Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint, []), [:secret_key_base])

    # Add nil check with fallback
    if secret_base do
      :crypto.hash(:sha256, secret_base <> "ticket_signing")
    else
      # Fallback: generate deterministic key from app name
      :crypto.hash(:sha256, "eventasaurus_ticket_signing_fallback_key")
    end
  end
end
