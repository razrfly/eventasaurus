defmodule EventasaurusWeb.StripePaymentController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Ticketing

  require Logger

  @doc """
  Creates a payment intent for a ticket purchase using Stripe Connect.

  Expects JSON payload with:
  - ticket_id: ID of the ticket to purchase
  - quantity: Number of tickets (optional, defaults to 1)
  """
  def create_payment_intent(conn, params) do
    current_user = conn.assigns[:user]

    if current_user do
      case validate_payment_intent_params(params) do
        {:ok, %{ticket_id: ticket_id, quantity: quantity}} ->
          process_payment_intent_creation(conn, current_user, ticket_id, quantity)

        {:error, errors} ->
          Logger.warning("Invalid payment intent parameters",
            errors: errors,
            user_id: current_user.id,
            params: sanitize_params(params)
          )

          conn
          |> put_status(:bad_request)
          |> json(%{
            success: false,
            error: "validation_failed",
            message: "Invalid parameters",
            details: errors
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to purchase tickets"
      })
    end
  end



  defp process_payment_intent_creation(conn, current_user, ticket_id, quantity) do
    case create_order_with_payment_intent(current_user, ticket_id, quantity) do
        {:ok, %{order: order, payment_intent: payment_intent}} ->
          Logger.info("Payment intent created successfully",
            order_id: order.id,
            payment_intent_id: payment_intent["id"],
            user_id: current_user.id
          )

          conn
          |> put_status(:created)
          |> json(%{
            success: true,
            order_id: order.id,
            payment_intent: %{
              id: payment_intent["id"],
              client_secret: payment_intent["client_secret"],
              amount: payment_intent["amount"],
              currency: payment_intent["currency"]
            }
          })

        {:error, :ticket_unavailable} ->
          Logger.warning("Ticket unavailable for purchase",
            ticket_id: ticket_id,
            quantity: quantity,
            user_id: current_user.id
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "ticket_unavailable",
            message: "The requested tickets are no longer available"
          })

        {:error, :no_stripe_account} ->
          Logger.warning("Event organizer has no Stripe Connect account",
            ticket_id: ticket_id,
            user_id: current_user.id
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "no_stripe_account",
            message: "The event organizer has not set up payment processing"
          })

        {:error, :no_organizer} ->
          Logger.error("Event has no organizer",
            ticket_id: ticket_id,
            user_id: current_user.id
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "no_organizer",
            message: "Event configuration error"
          })

        {:error, :ticket_not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{
            success: false,
            error: "ticket_not_found",
            message: "Ticket not found"
          })

        {:error, reason} when is_binary(reason) ->
          Logger.error("Stripe payment intent creation failed",
            ticket_id: ticket_id,
            user_id: current_user.id,
            reason: reason
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "payment_intent_failed",
            message: reason
          })

        {:error, reason} ->
          Logger.error("Order creation failed",
            ticket_id: ticket_id,
            user_id: current_user.id,
            reason: inspect(reason)
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "order_creation_failed",
            message: "Unable to create order"
          })
      end
  end

      @doc """
  Confirms a payment after successful Stripe payment.

  Expects JSON payload with:
  - payment_intent_id: Stripe Payment Intent ID
  """
  def confirm_payment(conn, params) do
    current_user = conn.assigns[:user]

    if current_user do
      case validate_confirm_payment_params(params) do
        {:ok, payment_intent_id} ->
          process_payment_confirmation(conn, current_user, payment_intent_id)

        {:error, errors} ->
          Logger.warning("Invalid payment confirmation parameters",
            errors: errors,
            user_id: current_user.id,
            params: sanitize_params(params)
          )

          conn
          |> put_status(:bad_request)
          |> json(%{
            success: false,
            error: "validation_failed",
            message: "Invalid parameters",
            details: errors
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to confirm payments"
      })
    end
  end



  defp process_payment_confirmation(conn, current_user, payment_intent_id) do
    case find_and_confirm_order(payment_intent_id, current_user.id) do
      {:ok, order} ->
        Logger.info("Payment confirmed successfully",
          order_id: order.id,
          payment_intent_id: payment_intent_id,
          user_id: current_user.id
        )

        conn
        |> json(%{
          success: true,
          order_id: order.id,
          status: order.status
        })

      {:error, :order_not_found} ->
        Logger.warning("Order not found for payment confirmation",
          payment_intent_id: payment_intent_id,
          user_id: current_user.id
        )

        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "order_not_found",
          message: "Order not found"
        })

      {:error, :already_confirmed} ->
        Logger.info("Attempted to confirm already confirmed order",
          payment_intent_id: payment_intent_id,
          user_id: current_user.id
        )

        conn
        |> put_status(:conflict)
        |> json(%{
          success: false,
          error: "already_confirmed",
          message: "Order is already confirmed"
        })

      {:error, reason} ->
        Logger.error("Payment confirmation failed",
          payment_intent_id: payment_intent_id,
          user_id: current_user.id,
          reason: inspect(reason)
        )

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "confirmation_failed",
          message: "Unable to confirm payment"
        })
    end
  end

  # Private helper functions

  defp validate_payment_intent_params(params) do
    errors = []

    # Validate ticket_id
    {ticket_id, errors} = case Map.get(params, "ticket_id") do
      nil -> {nil, ["ticket_id is required" | errors]}
      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed_id, ""} when parsed_id > 0 -> {parsed_id, errors}
          _ -> {nil, ["ticket_id must be a positive integer" | errors]}
        end
      id when is_integer(id) and id > 0 -> {id, errors}
      _ -> {nil, ["ticket_id must be a positive integer" | errors]}
    end

    # Validate quantity
    {quantity, errors} = case Map.get(params, "quantity", 1) do
      q when is_binary(q) ->
        case Integer.parse(q) do
          {parsed_q, ""} when parsed_q > 0 and parsed_q <= 100 -> {parsed_q, errors}
          {parsed_q, ""} when parsed_q <= 0 -> {nil, ["quantity must be positive" | errors]}
          {parsed_q, ""} when parsed_q > 100 -> {nil, ["quantity cannot exceed 100" | errors]}
          _ -> {nil, ["quantity must be a valid integer" | errors]}
        end
      q when is_integer(q) and q > 0 and q <= 100 -> {q, errors}
      q when is_integer(q) and q <= 0 -> {nil, ["quantity must be positive" | errors]}
      q when is_integer(q) and q > 100 -> {nil, ["quantity cannot exceed 100" | errors]}
      nil -> {1, errors}  # Default value
      _ -> {nil, ["quantity must be a valid integer" | errors]}
    end

    if Enum.empty?(errors) do
      {:ok, %{ticket_id: ticket_id, quantity: quantity}}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp validate_confirm_payment_params(params) do
    case Map.get(params, "payment_intent_id") do
      nil ->
        {:error, ["payment_intent_id is required"]}
      id when is_binary(id) and byte_size(id) > 0 ->
        # Validate Stripe Payment Intent ID format (starts with "pi_")
        if String.starts_with?(id, "pi_") and byte_size(id) > 3 do
          {:ok, id}
        else
          {:error, ["payment_intent_id must be a valid Stripe Payment Intent ID"]}
        end
      _ ->
        {:error, ["payment_intent_id must be a non-empty string"]}
    end
  end

  defp sanitize_params(params) do
    # Remove sensitive data from params for logging
    params
    |> Map.drop(["password", "token", "secret"])
    |> Enum.into(%{})
  end

  defp create_order_with_payment_intent(user, ticket_id, quantity) do
    with {:ok, ticket} <- get_ticket(ticket_id),
         {:ok, result} <- Ticketing.create_order_with_stripe_connect(user, ticket, %{quantity: quantity}) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_ticket(ticket_id) do
    try do
      ticket = Ticketing.get_ticket_with_event!(ticket_id)
      {:ok, ticket}
    rescue
      Ecto.NoResultsError -> {:error, :ticket_not_found}
    end
  end

  defp find_and_confirm_order(payment_intent_id, user_id) do
    # Find order by payment intent ID and user
    case Ticketing.get_user_order_by_payment_intent(user_id, payment_intent_id) do
      nil ->
        {:error, :order_not_found}
      %{status: "pending"} = order ->
        Ticketing.confirm_order(order, payment_intent_id)
      %{status: "payment_pending"} = order ->
        Ticketing.confirm_order(order, payment_intent_id)
      %{} ->
        {:error, :already_confirmed}
    end
  end
end
