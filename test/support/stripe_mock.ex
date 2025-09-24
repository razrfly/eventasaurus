defmodule EventasaurusApp.StripeMock do
  @moduledoc """
  Mock module for Stripe API calls in tests.

  This module provides mock implementations of Stripe functions
  to enable testing without making actual API calls.
  """

  @behaviour EventasaurusApp.Stripe.Behaviour

  def verify_webhook_signature(_body, _signature, _secret) do
    {:ok, %{}}
  end

  def get_payment_intent(_payment_intent_id, _connect_account) do
    {:ok, %{"status" => "succeeded"}}
  end

  def get_checkout_session(_session_id) do
    {:ok, %{"payment_status" => "paid"}}
  end

  def create_checkout_session(%{} = _params) do
    {:ok,
     %{
       "id" => "cs_test_mock_session",
       "url" => "https://checkout.stripe.com/pay/cs_test_mock_session"
     }}
  end

  def create_payment_intent(
        _amount_cents,
        _currency,
        _connect_account,
        _application_fee_amount,
        _metadata,
        _event \\ nil
      ) do
    {:ok,
     %{
       "id" => "pi_test_mock_intent",
       "client_secret" => "pi_test_mock_intent_secret_test"
     }}
  end
end
