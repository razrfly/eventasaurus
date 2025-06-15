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
  def create_payment_intent(conn, %{"ticket_id" => ticket_id} = params) do
    current_user = conn.assigns[:user]

    if current_user do
      quantity = Map.get(params, "quantity", 1)

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

      @doc """
  Confirms a payment after successful Stripe payment.

  Expects JSON payload with:
  - payment_intent_id: Stripe Payment Intent ID
  """
  def confirm_payment(conn, %{"payment_intent_id" => payment_intent_id}) do
    current_user = conn.assigns[:user]

    if current_user do
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

  # Private helper functions

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
      nil -> {:error, :order_not_found}
      order -> Ticketing.confirm_order(order, payment_intent_id)
    end
  end
end
