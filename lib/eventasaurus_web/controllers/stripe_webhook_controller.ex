defmodule EventasaurusWeb.StripeWebhookController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Ticketing

  require Logger

  # Maximum number of retry attempts for webhook processing
  @max_retries 3
  # Delay between retries in milliseconds
  @retry_delay 1000
  # ETS table for idempotency tracking
  @idempotency_table :webhook_idempotency

  @doc """
  Handles Stripe webhook events.

  This endpoint receives webhook events from Stripe and processes them
  after verifying the webhook signature for security.
  """
  def handle_webhook(conn, _params) do
    # Validate request method
    if conn.method != "POST" do
      Logger.warning("Invalid webhook request method", method: conn.method)

      conn
      |> put_status(:method_not_allowed)
      |> json(%{error: "Method not allowed"})
    else
      process_webhook_request(conn)
    end
  end

  # Private helper functions

  defp process_webhook_request(conn) do
    # Get the raw body and signature
    raw_body = conn.assigns[:raw_body] || ""
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    # Validate required headers and body
    case validate_webhook_request(raw_body, signature) do
      :ok ->
        case verify_webhook_signature(raw_body, signature) do
          {:ok, event} ->
            process_webhook_event_with_retry(event, @max_retries)

            conn
            |> put_status(:ok)
            |> json(%{received: true})

          {:error, reason} ->
            Logger.error("Webhook signature verification failed",
              reason: reason,
              signature_present: is_binary(signature)
            )

            conn
            |> put_status(:bad_request)
            |> json(%{error: "Invalid signature"})
        end

      {:error, reason} ->
        Logger.error("Webhook request validation failed", reason: reason)

        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

    defp validate_webhook_request(raw_body, signature) do
    cond do
      is_nil(signature) or signature == "" ->
        {:error, "Missing Stripe signature header"}

      is_nil(raw_body) or raw_body == "" ->
        {:error, "Missing request body"}

      byte_size(raw_body) > 1_000_000 ->
        {:error, "Request body too large"}

      not valid_signature_format?(signature) ->
        {:error, "Invalid signature format"}

      not valid_json_body?(raw_body) ->
        {:error, "Invalid JSON body"}

      true ->
        :ok
    end
  end

  defp valid_signature_format?(signature) do
    # Stripe signature format: "t=timestamp,v1=signature"
    String.match?(signature, ~r/^t=\d+,v1=[a-f0-9]+$/i)
  end

  defp valid_json_body?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

    defp verify_webhook_signature(raw_body, signature) do
    webhook_secret = get_webhook_secret()

    # First validate timestamp to prevent replay attacks
    case validate_webhook_timestamp(signature) do
      :ok ->
        case stripe_impl().verify_webhook_signature(raw_body, signature, webhook_secret) do
          {:ok, event} ->
            # Validate event structure
                    case validate_event_structure(event) do
          :ok ->
            # Check for duplicate events (idempotency)
            case check_idempotency(event["id"]) do
              :ok ->
                Logger.info("Webhook signature verified successfully",
                  event_type: event["type"],
                  event_id: event["id"]
                )
                {:ok, event}

              {:error, :duplicate} ->
                Logger.info("Duplicate webhook event ignored",
                  event_type: event["type"],
                  event_id: event["id"]
                )
                {:ok, :duplicate}
            end

          {:error, reason} ->
            Logger.error("Invalid event structure", reason: reason)
            {:error, reason}
        end

          {:error, reason} ->
            Logger.error("Webhook signature verification failed", reason: reason)
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Webhook timestamp validation failed", reason: reason)
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception during webhook signature verification",
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
      {:error, "Signature verification failed"}
  end

  defp validate_webhook_timestamp(signature) do
    # Extract timestamp from signature header
    case Regex.run(~r/t=(\d+)/, signature) do
      [_, timestamp_str] ->
        case Integer.parse(timestamp_str) do
          {timestamp, ""} ->
            current_time = System.system_time(:second)
            time_diff = abs(current_time - timestamp)

            # Allow 5 minutes tolerance for clock skew
            if time_diff <= 300 do
              :ok
            else
              {:error, "Webhook timestamp too old or too far in future"}
            end

          _ ->
            {:error, "Invalid timestamp format"}
        end

      _ ->
        {:error, "No timestamp found in signature"}
    end
  end

  defp validate_event_structure(event) when is_map(event) do
    required_fields = ["id", "type", "data", "object"]

    missing_fields =
      required_fields
      |> Enum.filter(fn field -> not Map.has_key?(event, field) end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_event_structure(_), do: {:error, "Event must be a map"}

    defp process_webhook_event_with_retry(:duplicate, _retries_left) do
    # Duplicate events are already processed, return success
    :ok
  end

  defp process_webhook_event_with_retry(event, retries_left) when retries_left > 0 do
    case process_webhook_event(event) do
      :ok ->
        # Mark event as processed for idempotency
        mark_event_processed(event["id"])
        :ok

      {:error, reason} when retries_left > 1 ->
        Logger.warning("Webhook processing failed, retrying",
          reason: reason,
          retries_left: retries_left - 1,
          event_type: event["type"],
          event_id: event["id"]
        )

        # Wait before retrying
        Process.sleep(@retry_delay)
        process_webhook_event_with_retry(event, retries_left - 1)

      {:error, reason} ->
        Logger.error("Webhook processing failed after all retries",
          reason: reason,
          event_type: event["type"],
          event_id: event["id"]
        )
        {:error, reason}
    end
  end

  defp process_webhook_event_with_retry(event, 0) do
    Logger.error("No retries left for webhook processing",
      event_type: event["type"],
      event_id: event["id"]
    )
    {:error, "Max retries exceeded"}
  end

  defp process_webhook_event(%{"type" => "payment_intent.succeeded"} = event) do
    payment_intent = event["data"]["object"]
    payment_intent_id = payment_intent["id"]

    Logger.info("Processing payment_intent.succeeded event",
      payment_intent_id: payment_intent_id,
      amount: payment_intent["amount"],
      event_id: event["id"]
    )

    # Validate payment intent structure
    case validate_payment_intent(payment_intent) do
      :ok ->
        process_payment_success(payment_intent_id, payment_intent)

      {:error, reason} ->
        Logger.error("Invalid payment intent structure",
          reason: reason,
          payment_intent_id: payment_intent_id
        )
        {:error, reason}
    end
  end

  defp process_webhook_event(%{"type" => "payment_intent.payment_failed"} = event) do
    payment_intent = event["data"]["object"]
    payment_intent_id = payment_intent["id"]

    Logger.info("Processing payment_intent.payment_failed event",
      payment_intent_id: payment_intent_id,
      event_id: event["id"]
    )

    case validate_payment_intent(payment_intent) do
      :ok ->
        # Mark associated order as failed to prevent inventory blocking
        with {:ok, order} <- find_order_by_payment_intent(payment_intent_id) do
          case Ticketing.mark_order_failed(order) do
            {:ok, updated_order} ->
              Logger.info("Order marked as failed due to payment failure",
                order_id: updated_order.id,
                payment_intent_id: payment_intent_id
              )
              :ok

            {:error, reason} ->
              Logger.error("Failed to mark order as failed",
                order_id: order.id,
                payment_intent_id: payment_intent_id,
                reason: inspect(reason)
              )
              :ok  # Don't fail webhook processing
          end
        else
          {:error, :not_found} ->
            Logger.warning("No order found for failed payment intent",
              payment_intent_id: payment_intent_id
            )
            :ok
        end

      {:error, reason} ->
        Logger.error("Invalid payment intent structure",
          reason: reason,
          payment_intent_id: payment_intent_id
        )
        {:error, reason}
    end
  end

  defp process_webhook_event(%{"type" => "checkout.session.completed"} = event) do
    session = event["data"]["object"]
    session_id = session["id"]

    Logger.info("Processing checkout.session.completed event",
      session_id: session_id,
      amount_total: session["amount_total"],
      payment_status: session["payment_status"],
      event_id: event["id"]
    )

    # Validate checkout session structure
    case validate_checkout_session(session) do
      :ok ->
        process_checkout_session_completed(session_id, session)

      {:error, reason} ->
        Logger.error("Invalid checkout session structure",
          reason: reason,
          session_id: session_id
        )
        {:error, reason}
    end
  end

  defp process_webhook_event(%{"type" => "checkout.session.expired"} = event) do
    session = event["data"]["object"]
    session_id = session["id"]

    Logger.info("Processing checkout.session.expired event",
      session_id: session_id,
      event_id: event["id"]
    )

    case validate_checkout_session(session) do
      :ok ->
        process_checkout_session_expired(session_id, session)

      {:error, reason} ->
        Logger.error("Invalid checkout session structure",
          reason: reason,
          session_id: session_id
        )
        {:error, reason}
    end
  end

  defp process_webhook_event(%{"type" => event_type} = event) do
    Logger.info("Received unhandled webhook event",
      event_type: event_type,
      event_id: event["id"]
    )
    :ok
  end

  defp validate_payment_intent(payment_intent) when is_map(payment_intent) do
    required_fields = ["id", "amount", "currency", "status"]

    missing_fields =
      required_fields
      |> Enum.filter(fn field -> not Map.has_key?(payment_intent, field) end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required payment intent fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_payment_intent(_), do: {:error, "Payment intent must be a map"}

  defp validate_checkout_session(session) when is_map(session) do
    required_fields = ["id", "payment_status"]

    missing_fields =
      required_fields
      |> Enum.filter(fn field -> not Map.has_key?(session, field) end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required checkout session fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_checkout_session(_), do: {:error, "Checkout session must be a map"}

  defp process_payment_success(payment_intent_id, payment_intent) do
    case find_order_by_payment_intent(payment_intent_id) do
      {:ok, order} ->
        # Use sync function to let Stripe be the source of truth
        case Ticketing.sync_order_with_stripe(order) do
          {:ok, updated_order} ->
            Logger.info("Order synced via payment intent webhook",
              order_id: updated_order.id,
              payment_intent_id: payment_intent_id,
              status: updated_order.status,
              amount: payment_intent["amount"]
            )

            # Broadcast order update to LiveViews if status changed
            if updated_order.status != order.status do
              broadcast_order_update(updated_order)
            end
            :ok

          {:error, reason} ->
            Logger.error("Failed to sync order",
              order_id: order.id,
              payment_intent_id: payment_intent_id,
              reason: inspect(reason)
            )
            {:error, "Order sync failed"}
        end

      {:error, :not_found} ->
        Logger.warning("No order found for payment intent",
          payment_intent_id: payment_intent_id
        )
        :ok  # Not an error - might be a different payment

      {:error, reason} ->
        Logger.error("Error finding order for payment intent",
          payment_intent_id: payment_intent_id,
          reason: inspect(reason)
        )
        {:error, "Database error"}
    end
  rescue
    error ->
      Logger.error("Exception during payment success processing",
        payment_intent_id: payment_intent_id,
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
      {:error, "Processing exception"}
  end



  defp process_checkout_session_completed(session_id, session) do
    case find_order_by_session_id(session_id) do
      {:ok, order} ->
        # Use sync function to let Stripe be the source of truth
        case Ticketing.sync_order_with_stripe(order) do
          {:ok, updated_order} ->
            Logger.info("Order synced via checkout session webhook",
              order_id: updated_order.id,
              session_id: session_id,
              status: updated_order.status,
              amount_total: session["amount_total"]
            )

            # Broadcast order update to LiveViews if status changed
            if updated_order.status != order.status do
              broadcast_order_update(updated_order)
            end
            :ok

          {:error, reason} ->
            Logger.error("Failed to sync order via checkout session",
              order_id: order.id,
              session_id: session_id,
              reason: inspect(reason)
            )
            {:error, "Order sync failed"}
        end

      {:error, :not_found} ->
        Logger.warning("No order found for checkout session",
          session_id: session_id
        )
        :ok  # Not an error - might be a different checkout

      {:error, reason} ->
        Logger.error("Error finding order for checkout session",
          session_id: session_id,
          reason: inspect(reason)
        )
        {:error, "Database error"}
    end
  rescue
    error ->
      Logger.error("Exception during checkout session processing",
        session_id: session_id,
        error: inspect(error),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__)
      )
      {:error, "Processing exception"}
  end

  defp process_checkout_session_expired(session_id, _session) do
    Logger.info("Checkout session expired - no action needed, order remains pending",
      session_id: session_id
    )

    # Don't update order state - let it remain pending
    # User can retry checkout if needed
    :ok
  end

  defp find_order_by_session_id(session_id) do
    case Ticketing.get_order_by_session_id(session_id) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  rescue
    error ->
      Logger.error("Database error finding order by session ID",
        session_id: session_id,
        error: inspect(error)
      )
      {:error, error}
  end

  defp find_order_by_payment_intent(payment_intent_id) do
    case Ticketing.get_order_by_payment_intent(payment_intent_id) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  rescue
    error ->
      Logger.error("Database error finding order",
        payment_intent_id: payment_intent_id,
        error: inspect(error)
      )
      {:error, error}
  end

  defp broadcast_order_update(order) do
    Phoenix.PubSub.broadcast(
      EventasaurusApp.PubSub,
      "orders:#{order.user_id}",
      {:order_updated, order}
    )
  rescue
    error ->
      Logger.error("Failed to broadcast order update",
        order_id: order.id,
        error: inspect(error)
      )
  end

    defp check_idempotency(event_id) do
    # Ensure ETS table exists
    unless :ets.whereis(@idempotency_table) != :undefined do
      :ets.new(@idempotency_table, [:set, :public, :named_table])
    end

    case :ets.lookup(@idempotency_table, event_id) do
      [] -> :ok  # Event not seen before
      [_] -> {:error, :duplicate}  # Event already processed
    end
  end

  defp mark_event_processed(event_id) do
    # Store with TTL-like behavior (cleanup old entries periodically)
    current_time = System.system_time(:second)

    # Ensure ETS table exists
    unless :ets.whereis(@idempotency_table) != :undefined do
      :ets.new(@idempotency_table, [:set, :public, :named_table])
    end

    :ets.insert(@idempotency_table, {event_id, current_time})

    # Cleanup old entries (older than 24 hours)
    cleanup_old_idempotency_entries()
  end

  defp cleanup_old_idempotency_entries do
    # Only cleanup occasionally to avoid performance impact
    if :rand.uniform(100) == 1 do
      cutoff_time = System.system_time(:second) - 86_400  # 24 hours ago

      # Delete old entries
      :ets.select_delete(@idempotency_table, [
        {{:"$1", :"$2"}, [{:<, :"$2", cutoff_time}], [true]}
      ])
    end
  end

  defp get_webhook_secret do
    case System.get_env("STRIPE_WEBHOOK_SECRET") do
      nil ->
        Logger.error("STRIPE_WEBHOOK_SECRET environment variable is not set")
        raise "STRIPE_WEBHOOK_SECRET environment variable is not set"
      secret when is_binary(secret) and secret != "" ->
        secret
      _ ->
        Logger.error("STRIPE_WEBHOOK_SECRET environment variable is empty")
        raise "STRIPE_WEBHOOK_SECRET environment variable is empty"
    end
  end

  # Get the configured Stripe implementation (for testing vs production)
  defp stripe_impl do
    Application.get_env(:eventasaurus, :stripe_module, EventasaurusApp.Stripe)
  end
end
