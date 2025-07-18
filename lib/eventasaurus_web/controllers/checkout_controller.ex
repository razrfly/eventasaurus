defmodule EventasaurusWeb.CheckoutController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Ticketing
  alias EventasaurusApp.Accounts.User

  require Logger

  @doc """
  Creates a Stripe Checkout Session for ticket purchase with dynamic pricing support.

  Supports:
  - Fixed pricing (traditional pricing)
  - Flexible pricing (pay-what-you-want above minimum)
  - Custom pricing with tips

  POST /api/checkout/sessions

  Body params:
  - ticket_id (required): ID of the ticket to purchase
  - quantity (optional): Number of tickets, default 1
  - custom_price_cents (optional): Custom price for flexible pricing
  - tip_cents (optional): Tip amount per ticket
  """
  def create_session(conn, params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, ticket} <- get_ticket(params["ticket_id"]),
         {:ok, session_params} <- validate_session_params(params),
         {:ok, result} <- Ticketing.create_checkout_session(user, ticket, session_params) do

      Logger.info("Checkout session created successfully",
        order_id: result.order.id,
        session_id: result.session_id,
        user_id: user.id
      )

      json(conn, %{
        success: true,
        checkout_url: result.checkout_url,
        session_id: result.session_id,
        order_id: result.order.id
      })
    else
      {:error, :no_user} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})

      {:error, :ticket_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Ticket not found"})

      {:error, :ticket_unavailable} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Ticket is no longer available"})

      {:error, :price_below_minimum} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Price is below minimum required amount"})

      {:error, :custom_price_required} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Custom price is required for flexible pricing"})

      {:error, :no_stripe_account} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Event organizer has not connected their Stripe account"})

      {:error, reason} when is_binary(reason) ->
        Logger.error("Checkout session creation failed", reason: reason)
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: reason})

      {:error, reason} ->
        Logger.error("Unexpected checkout session creation error", error: inspect(reason))
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Unable to create checkout session"})
    end
  end

  @doc """
  Handles successful checkout session completion.

  GET /orders/:order_id/success?session_id=<session_id>
  """
    def success(conn, %{"order_id" => order_id, "session_id" => session_id}) do
    try do
      order = Ticketing.get_order!(order_id) |> EventasaurusApp.Repo.preload([:event, :ticket])

      # Verify the session matches our order
      if order.stripe_session_id == session_id do
        # Check if order needs to be confirmed
        case order.status do
          "pending" ->
            # Order will be confirmed via webhook, but we can show success page
            render(conn, "success.html", order: order, session_id: session_id)

          "confirmed" ->
            # Order is already confirmed
            render(conn, "success.html", order: order, session_id: session_id)

          _ ->
            # Something went wrong
            conn
            |> put_flash(:error, "There was an issue with your payment. Please contact support.")
            |> redirect(to: "/")
        end
      else
        # Session ID mismatch - possible security issue
        Logger.warning("Session ID mismatch for order",
          order_id: order_id,
          expected_session: order.stripe_session_id,
          received_session: session_id
        )

        conn
        |> put_flash(:error, "Invalid payment session.")
        |> redirect(to: "/")
      end
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_flash(:error, "Order not found.")
        |> redirect(to: "/")
    end
  end

  @doc """
  Handles checkout session cancellation.

  Users are redirected here when they cancel the checkout process.
  """
  def cancel(conn, %{"session_id" => _session_id}) do
    conn
    |> put_flash(:info, "Payment was cancelled. You can try again anytime.")
    |> redirect(to: "/")
  end

  # Private helper functions

  defp get_current_user(conn) do
    case conn.assigns[:user] do
      %User{} = user -> {:ok, user}
      _ -> {:error, :no_user}
    end
  end

  defp get_ticket(ticket_id) when is_binary(ticket_id) do
    try do
      ticket = Ticketing.get_ticket!(ticket_id)
      {:ok, ticket}
    rescue
      Ecto.NoResultsError -> {:error, :ticket_not_found}
    end
  end

  defp get_ticket(ticket_id) when is_integer(ticket_id) do
    try do
      ticket = Ticketing.get_ticket!(ticket_id)
      {:ok, ticket}
    rescue
      Ecto.NoResultsError -> {:error, :ticket_not_found}
    end
  end

  defp get_ticket(_), do: {:error, :ticket_not_found}

  defp validate_session_params(params) do
    # Convert string parameters to appropriate types
    session_params = %{}

    # Quantity validation
    session_params = case params["quantity"] do
      nil -> Map.put(session_params, :quantity, 1)
      quantity when is_integer(quantity) and quantity > 0 ->
        Map.put(session_params, :quantity, quantity)
      quantity when is_binary(quantity) ->
        case Integer.parse(quantity) do
          {q, ""} when q > 0 -> Map.put(session_params, :quantity, q)
          _ -> Map.put(session_params, :quantity, 1)
        end
      _ -> Map.put(session_params, :quantity, 1)
    end

    # Custom price validation
    session_params = case params["custom_price_cents"] do
      nil -> session_params
      price when is_integer(price) and price > 0 ->
        Map.put(session_params, :custom_price_cents, price)
      price when is_binary(price) ->
        case Integer.parse(price) do
          {p, ""} when p > 0 -> Map.put(session_params, :custom_price_cents, p)
          _ -> session_params
        end
      _ -> session_params
    end

    # Tip validation
    session_params = case params["tip_cents"] do
      nil -> Map.put(session_params, :tip_cents, 0)
      tip when is_integer(tip) and tip >= 0 ->
        Map.put(session_params, :tip_cents, tip)
      tip when is_binary(tip) ->
        case Integer.parse(tip) do
          {t, ""} when t >= 0 -> Map.put(session_params, :tip_cents, t)
          _ -> Map.put(session_params, :tip_cents, 0)
        end
      _ -> Map.put(session_params, :tip_cents, 0)
    end

    {:ok, session_params}
  end

  @doc """
  Sync endpoint for post-checkout success - following t3dotgg pattern.
  Called from frontend after successful checkout to ensure order is confirmed.
  """
  def sync_after_success(conn, %{"order_id" => order_id}) do
    current_user = conn.assigns[:user]

    try do
      order = Ticketing.get_order!(order_id)

      # Verify order belongs to current user
      if order.user_id != current_user.id do
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})
      else
        # Sync with Stripe to get latest status
        case Ticketing.sync_order_with_stripe(order) do
          {:ok, updated_order} ->
            json(conn, %{
              order_id: updated_order.id,
              status: updated_order.status,
              confirmed: updated_order.status == "confirmed"
            })

          {:error, reason} ->
            Logger.error("Failed to sync order after success",
              order_id: order.id,
              user_id: current_user.id,
              reason: inspect(reason)
            )

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to sync order status"})
        end
      end
    rescue
      Ecto.NoResultsError ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Order not found"})
    end
  end
end
