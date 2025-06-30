defmodule EventasaurusApp.Stripe do
  @moduledoc """
  The Stripe context for handling Stripe Connect accounts.
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Stripe.StripeConnectAccount
  alias EventasaurusApp.Accounts.User

  require Logger
  import Bitwise

  defmodule Behaviour do
    @moduledoc """
    Behaviour for Stripe API operations to enable mocking in tests.
    """

    @callback verify_webhook_signature(binary(), binary(), binary()) :: {:ok, map()} | {:error, term()}
    @callback get_payment_intent(binary(), binary() | nil) :: {:ok, map()} | {:error, term()}
    @callback get_checkout_session(binary()) :: {:ok, map()} | {:error, term()}
    @callback create_checkout_session(map()) :: {:ok, map()} | {:error, term()}
    @callback create_payment_intent(map(), binary() | nil) :: {:ok, map()} | {:error, term()}
  end

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
      {"Content-Type", "application/x-www-form-urlencoded"}
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
            Logger.info("Successfully exchanged OAuth code",
              stripe_user_id: response_data["stripe_user_id"],
              livemode: response_data["livemode"]
            )
            {:ok, response_data}

          {:error, decode_error} ->
            Logger.error("Failed to decode Stripe OAuth response",
              error: inspect(decode_error),
              response_body: redact_secrets(response_body)
            )
            {:error, "Invalid response format from Stripe"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, error_data} ->
            Logger.error("Stripe OAuth error response",
              status_code: status_code,
              error: error_data["error"],
              error_description: error_data["error_description"]
            )
            {:error, error_data}

          {:error, _} ->
            Logger.error("Stripe OAuth error with invalid JSON",
              status_code: status_code,
              response_body: redact_secrets(response_body)
            )
            {:error, "Stripe returned an error: HTTP #{status_code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during Stripe OAuth exchange", reason: inspect(reason))
        {:error, "Network error connecting to Stripe: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected error during Stripe OAuth exchange", error: inspect(error))
        {:error, "Unexpected error during OAuth exchange"}
    end
  end

  def exchange_oauth_code(_), do: {:error, "Invalid authorization code"}

  @doc """
  Creates a Payment Intent for a Stripe Connect account with application fees.
  """
  def create_payment_intent(amount_cents, currency, connect_account, application_fee_amount, metadata \\ %{}) do
    Logger.info("Creating Payment Intent for Stripe Connect account",
      amount_cents: amount_cents,
      currency: currency,
      stripe_user_id: connect_account.stripe_user_id,
      application_fee_amount: application_fee_amount
    )

    url = "https://api.stripe.com/v1/payment_intents"
    secret_key = get_stripe_secret_key()

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Bearer #{secret_key}"}
    ]

    # Build metadata with order information
    full_metadata = Map.merge(%{
      "platform" => "eventasaurus",
      "connect_account_id" => to_string(connect_account.id)
    }, metadata)

    body_params = %{
      "amount" => amount_cents,
      "currency" => currency,
      "application_fee_amount" => application_fee_amount,
      "transfer_data[destination]" => connect_account.stripe_user_id,
      "automatic_payment_methods[enabled]" => "true"
    }

    # Add metadata to body params
    body_params_with_metadata =
      full_metadata
      |> Enum.reduce(body_params, fn {key, value}, acc ->
        Map.put(acc, "metadata[#{key}]", to_string(value))
      end)

    body = URI.encode_query(body_params_with_metadata)

    case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, payment_intent} ->
            Logger.info("Successfully created Payment Intent",
              payment_intent_id: payment_intent["id"],
              amount: payment_intent["amount"],
              application_fee_amount: payment_intent["application_fee_amount"]
            )
            {:ok, payment_intent}

          {:error, decode_error} ->
            Logger.error("Failed to decode Payment Intent response",
              error: inspect(decode_error),
              response_body: redact_secrets(response_body)
            )
            {:error, "Invalid response format from Stripe"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, error_data} ->
            Logger.error("Stripe Payment Intent error",
              status_code: status_code,
              error_type: error_data["error"]["type"],
              error_message: error_data["error"]["message"]
            )
            {:error, error_data["error"]["message"] || "Payment Intent creation failed"}

          {:error, _} ->
            Logger.error("Stripe Payment Intent error with invalid JSON",
              status_code: status_code,
              response_body: redact_secrets(response_body)
            )
            {:error, "Stripe returned an error: HTTP #{status_code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during Payment Intent creation", reason: inspect(reason))
        {:error, "Network error connecting to Stripe: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected error during Payment Intent creation", error: inspect(error))
        {:error, "Unexpected error during Payment Intent creation"}
    end
  end

  @doc """
  Creates a Stripe Checkout Session for dynamic pricing with Stripe Connect support.

  Supports:
  - Fixed pricing (traditional pricing)
  - Flexible pricing (pay-what-you-want above minimum)
  - Custom pricing with tips
  - Idempotency via idempotency_key
  """
  def create_checkout_session(%{
    amount_cents: amount_cents,
    currency: currency,
    connect_account: connect_account,
    application_fee_amount: application_fee_amount,
    success_url: success_url,
    cancel_url: cancel_url,
    metadata: metadata,
    idempotency_key: idempotency_key,
    pricing_model: pricing_model,
    allow_promotion_codes: allow_promotion_codes
  } = params) do

    # Extract customer information for pre-filling
    customer_email = Map.get(params, :customer_email)

    Logger.info("Creating Stripe Checkout Session",
      amount_cents: amount_cents,
      currency: currency,
      pricing_model: pricing_model,
      stripe_user_id: connect_account.stripe_user_id,
      application_fee_amount: application_fee_amount
    )

    url = "https://api.stripe.com/v1/checkout/sessions"
    secret_key = get_stripe_secret_key()

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Bearer #{secret_key}"},
      {"Idempotency-Key", idempotency_key}
    ]

    # Build metadata with order and pricing information
    full_metadata = Map.merge(%{
      "platform" => "eventasaurus",
      "connect_account_id" => to_string(connect_account.id),
      "pricing_model" => pricing_model
    }, metadata)

    # Base line item configuration - let Stripe handle tax calculation
    line_item = %{
      "price_data[currency]" => currency,
      "price_data[product_data][name]" => Map.get(params, :ticket_name, "Event Ticket"),
      "price_data[product_data][description]" => Map.get(params, :ticket_description, ""),
      "quantity" => Map.get(params, :quantity, 1)
    }

    # Configure pricing based on model - use base amount without tax
    line_item = case pricing_model do
      "flexible" ->
        # For flexible pricing, set minimum and allow adjustment
        line_item
        |> Map.put("price_data[unit_amount]", amount_cents)
        |> Map.put("adjustable_quantity[enabled]", "false")

      "fixed" ->
        # Traditional fixed pricing
        line_item
        |> Map.put("price_data[unit_amount]", amount_cents)
        |> Map.put("adjustable_quantity[enabled]", "false")

      _ ->
        # Default to fixed pricing
        line_item
        |> Map.put("price_data[unit_amount]", amount_cents)
        |> Map.put("adjustable_quantity[enabled]", "false")
    end

    # Calculate expiry time (30 minutes from now = 1800 seconds)
    expires_at = DateTime.utc_now() |> DateTime.add(30 * 60, :second) |> DateTime.to_unix()

    # Build body parameters - try automatic tax first, fallback to manual if not configured
    body_params = %{
      "mode" => "payment",
      "success_url" => success_url,
      "cancel_url" => cancel_url,
      "expires_at" => expires_at,
      # Use Stripe Connect's application fee handling
      "payment_intent_data[application_fee_amount]" => application_fee_amount,
      "payment_intent_data[transfer_data][destination]" => connect_account.stripe_user_id,
      "allow_promotion_codes" => allow_promotion_codes || false,

      # Line items
      "line_items[0][price_data][currency]" => line_item["price_data[currency]"],
      "line_items[0][price_data][product_data][name]" => line_item["price_data[product_data][name]"],
      "line_items[0][price_data][unit_amount]" => line_item["price_data[unit_amount]"],
      "line_items[0][quantity]" => line_item["quantity"]
    }

    # Try to enable automatic tax - only if tax settings are configured in Stripe
    # If this fails, Stripe will return an error and we'll fall back to manual calculation
    body_params = try_enable_automatic_tax(body_params)

    # Add tax behavior only if automatic tax is enabled
    body_params = if Map.get(body_params, "automatic_tax[enabled]") == "true" do
      Map.put(body_params, "line_items[0][price_data][tax_behavior]", "exclusive")
    else
      body_params
    end

    # Add customer information for pre-filling if available
    body_params = if customer_email do
      Map.put(body_params, "customer_email", customer_email)
    else
      body_params
    end

    # Add metadata to body params
    body_params_with_metadata =
      full_metadata
      |> Enum.reduce(body_params, fn {key, value}, acc ->
        Map.put(acc, "metadata[#{key}]", to_string(value))
      end)

    body = URI.encode_query(body_params_with_metadata)

    case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, checkout_session} ->
            Logger.info("Successfully created Checkout Session",
              session_id: checkout_session["id"],
              url: checkout_session["url"],
              expires_at: checkout_session["expires_at"]
            )
            {:ok, checkout_session}

          {:error, decode_error} ->
            Logger.error("Failed to decode Checkout Session response",
              error: inspect(decode_error),
              response_body: redact_secrets(response_body)
            )
            {:error, "Invalid response format from Stripe"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, error_data} ->
            Logger.error("Stripe Checkout Session error",
              status_code: status_code,
              error_type: error_data["error"]["type"],
              error_message: error_data["error"]["message"]
            )
            {:error, error_data["error"]["message"] || "Checkout Session creation failed"}

          {:error, _} ->
            Logger.error("Stripe Checkout Session error with invalid JSON",
              status_code: status_code,
              response_body: redact_secrets(response_body)
            )
            {:error, "Stripe returned an error: HTTP #{status_code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during Checkout Session creation", reason: inspect(reason))
        {:error, "Network error connecting to Stripe: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected error during Checkout Session creation", error: inspect(error))
        {:error, "Unexpected error during Checkout Session creation"}
    end
  end

  @doc """
  Creates a Stripe Checkout Session with multiple line items for multi-ticket purchases.

  ## Examples

      iex> line_items = [%{price_data: %{...}, quantity: 2}, %{price_data: %{...}, quantity: 1}]
      iex> create_multi_line_checkout_session(%{line_items: line_items, connect_account: account, ...})
      {:ok, %{"id" => "cs_...", "url" => "https://checkout.stripe.com/..."}}

  """
  def create_multi_line_checkout_session(%{
    line_items: line_items,
    connect_account: connect_account,
    application_fee_amount: application_fee_amount,
    success_url: success_url,
    cancel_url: cancel_url,
    metadata: metadata,
    idempotency_key: idempotency_key
  } = params) do

    # Extract customer information for pre-filling
    customer_email = Map.get(params, :customer_email)

    Logger.info("Creating Multi-Line Stripe Checkout Session",
      line_items_count: length(line_items),
      stripe_user_id: connect_account.stripe_user_id,
      application_fee_amount: application_fee_amount
    )

    url = "https://api.stripe.com/v1/checkout/sessions"
    secret_key = get_stripe_secret_key()

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Bearer #{secret_key}"},
      {"Idempotency-Key", idempotency_key}
    ]

    # Build metadata with order and pricing information
    full_metadata = Map.merge(%{
      "platform" => "eventasaurus",
      "connect_account_id" => to_string(connect_account.id)
    }, metadata)

    # Calculate expiry time (30 minutes from now = 1800 seconds)
    expires_at = DateTime.utc_now() |> DateTime.add(30 * 60, :second) |> DateTime.to_unix()

    # Build body parameters - try automatic tax first, fallback to manual if not configured
    body_params = %{
      "mode" => "payment",
      "success_url" => success_url,
      "cancel_url" => cancel_url,
      "expires_at" => expires_at,
      # Use Stripe Connect's application fee handling
      "payment_intent_data[application_fee_amount]" => application_fee_amount,
      "payment_intent_data[transfer_data][destination]" => connect_account.stripe_user_id,
      "allow_promotion_codes" => false
    }

    # Try to enable automatic tax - only if tax settings are configured in Stripe
    body_params = try_enable_automatic_tax(body_params)

    # Add customer information for pre-filling if available
    body_params = if customer_email do
      Map.put(body_params, "customer_email", customer_email)
    else
      body_params
    end

    # Add line items to body params
    body_params_with_line_items =
      line_items
      |> Enum.with_index()
      |> Enum.reduce(body_params, fn {line_item, index}, acc ->
        # Add tax behavior only if automatic tax is enabled
        acc_with_basic_fields = acc
        |> Map.put("line_items[#{index}][price_data][currency]", line_item.price_data.currency)
        |> Map.put("line_items[#{index}][price_data][product_data][name]", line_item.price_data.product_data.name)
        |> Map.put("line_items[#{index}][price_data][product_data][description]", line_item.price_data.product_data.description)
        |> Map.put("line_items[#{index}][price_data][unit_amount]", line_item.price_data.unit_amount)
        |> Map.put("line_items[#{index}][quantity]", line_item.quantity)

        # Add tax behavior if automatic tax is enabled
        if Map.get(acc, "automatic_tax[enabled]") == "true" do
          Map.put(acc_with_basic_fields, "line_items[#{index}][price_data][tax_behavior]", "exclusive")
        else
          acc_with_basic_fields
        end
      end)

    # Add metadata to body params
    body_params_with_metadata =
      full_metadata
      |> Enum.reduce(body_params_with_line_items, fn {key, value}, acc ->
        Map.put(acc, "metadata[#{key}]", to_string(value))
      end)

    body = URI.encode_query(body_params_with_metadata)

    case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, checkout_session} ->
            Logger.info("Successfully created Multi-Line Checkout Session",
              session_id: checkout_session["id"],
              url: checkout_session["url"],
              expires_at: checkout_session["expires_at"]
            )
            {:ok, checkout_session}

          {:error, decode_error} ->
            Logger.error("Failed to decode Multi-Line Checkout Session response",
              error: inspect(decode_error),
              response_body: redact_secrets(response_body)
            )
            {:error, "Invalid response format from Stripe"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, error_data} ->
            Logger.error("Stripe Multi-Line Checkout Session error",
              status_code: status_code,
              error_type: error_data["error"]["type"],
              error_message: error_data["error"]["message"]
            )
            {:error, error_data["error"]["message"] || "Multi-Line Checkout Session creation failed"}

          {:error, _} ->
            Logger.error("Stripe Multi-Line Checkout Session error with invalid JSON",
              status_code: status_code,
              response_body: redact_secrets(response_body)
            )
            {:error, "Stripe returned an error: HTTP #{status_code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during Multi-Line Checkout Session creation", reason: inspect(reason))
        {:error, "Network error connecting to Stripe: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected error during Multi-Line Checkout Session creation", error: inspect(error))
        {:error, "Unexpected error during Multi-Line Checkout Session creation"}
    end
  end

  @doc """
  Retrieves a Checkout Session by ID.
  """
  def get_checkout_session(session_id) do
    url = "https://api.stripe.com/v1/checkout/sessions/#{session_id}"
    secret_key = get_stripe_secret_key()

    headers = [
      {"Authorization", "Bearer #{secret_key}"}
    ]

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, checkout_session} -> {:ok, checkout_session}
          {:error, decode_error} ->
            Logger.error("Failed to decode Checkout Session response",
              error: inspect(decode_error),
              response_body: redact_secrets(response_body)
            )
            {:error, "Invalid response format from Stripe"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, error_data} ->
            Logger.error("Stripe Checkout Session retrieval error",
              status_code: status_code,
              error_type: error_data["error"]["type"],
              error_message: error_data["error"]["message"]
            )
            {:error, error_data["error"]["message"] || "Checkout Session retrieval failed"}

          {:error, _} ->
            {:error, "Stripe returned an error: HTTP #{status_code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during Checkout Session retrieval", reason: inspect(reason))
        {:error, "Network error connecting to Stripe: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected error during Checkout Session retrieval", error: inspect(error))
        {:error, "Unexpected error during Checkout Session retrieval"}
    end
  end

  @doc """
  Retrieves a Payment Intent by ID.
  """
  def get_payment_intent(payment_intent_id, connect_account \\ nil) do
    url = "https://api.stripe.com/v1/payment_intents/#{payment_intent_id}"
    secret_key = get_stripe_secret_key()

    headers = [
      {"Authorization", "Bearer #{secret_key}"}
    ]

    # Add Stripe-Account header if this is for a connected account
    headers = if connect_account do
      [{"Stripe-Account", connect_account.stripe_user_id} | headers]
    else
      headers
    end

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, payment_intent} ->
            {:ok, payment_intent}

          {:error, decode_error} ->
            Logger.error("Failed to decode Payment Intent response",
              error: inspect(decode_error),
              response_body: redact_secrets(response_body)
            )
            {:error, "Invalid response format from Stripe"}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, error_data} ->
            Logger.error("Stripe Payment Intent retrieval error",
              status_code: status_code,
              error_type: error_data["error"]["type"],
              error_message: error_data["error"]["message"]
            )
            {:error, error_data["error"]["message"] || "Payment Intent retrieval failed"}

          {:error, _} ->
            {:error, "Stripe returned an error: HTTP #{status_code}"}
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during Payment Intent retrieval", reason: inspect(reason))
        {:error, "Network error connecting to Stripe: #{inspect(reason)}"}

      {:error, error} ->
        Logger.error("Unexpected error during Payment Intent retrieval", error: inspect(error))
        {:error, "Unexpected error during Payment Intent retrieval"}
    end
  end

  @doc """
  Verifies a Stripe webhook signature to ensure the webhook is authentic.
  """
  def verify_webhook_signature(raw_body, signature_header, webhook_secret) do
    # Parse the signature header
    case parse_signature_header(signature_header) do
      {:ok, timestamp, signature} ->
        # Create the signed payload
        signed_payload = "#{timestamp}.#{raw_body}"

        # Compute the expected signature
        expected_signature = :crypto.mac(:hmac, :sha256, webhook_secret, signed_payload)
        |> Base.encode16(case: :lower)

        # Compare signatures
        if secure_compare(signature, expected_signature) do
          # Parse the event from the raw body
          case Jason.decode(raw_body) do
            {:ok, event} -> {:ok, event}
            {:error, _} -> {:error, "Invalid JSON in webhook body"}
          end
        else
          {:error, "Signature verification failed"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp parse_signature_header(signature_header) do
    # Stripe signature header format: "t=timestamp,v1=signature"
    parts = String.split(signature_header, ",")

    timestamp =
      parts
      |> Enum.find(&String.starts_with?(&1, "t="))
      |> case do
        "t=" <> timestamp -> timestamp
        _ -> nil
      end

    signature =
      parts
      |> Enum.find(&String.starts_with?(&1, "v1="))
      |> case do
        "v1=" <> signature -> signature
        _ -> nil
      end

    if timestamp && signature do
      {:ok, timestamp, signature}
    else
      {:error, "Invalid signature header format"}
    end
  end

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    secure_compare(a, b, 0) == 0
  end
  defp secure_compare(_, _), do: false

  defp secure_compare(<<a, rest_a::binary>>, <<b, rest_b::binary>>, acc) do
    secure_compare(rest_a, rest_b, bor(acc, bxor(a, b)))
  end
  defp secure_compare(<<>>, <<>>, acc), do: acc

  defp redact_secrets(raw_response) when is_binary(raw_response) do
    raw_response
    |> String.replace(~r/"(access_token|refresh_token)"\s*:\s*"[^"]+"/, "\"\\1\":\"<redacted>\"")
    |> String.replace(~r/"(client_secret)"\s*:\s*"[^"]+"/, "\"\\1\":\"<redacted>\"")
  end

  defp redact_secrets(other), do: other

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

  # Helper function to try enabling automatic tax calculation
  # Falls back gracefully if tax settings are not configured in Stripe
  defp try_enable_automatic_tax(body_params) do
    # Check if automatic tax should be enabled based on environment configuration
    enable_auto_tax = Application.get_env(:eventasaurus_app, :stripe_auto_tax_enabled, false)

    if enable_auto_tax do
      Logger.info("Attempting to enable Stripe automatic tax calculation")
      body_params
      |> Map.put("automatic_tax[enabled]", "true")
    else
      Logger.info("Using manual tax calculation (automatic tax disabled)")
      body_params
    end
  end

end
