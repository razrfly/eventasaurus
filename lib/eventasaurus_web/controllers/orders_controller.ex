defmodule EventasaurusWeb.OrdersController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Ticketing

  require Logger

  @doc """
  Gets order details by order ID.

  Expects order_id as URL parameter.
  """
  def show(conn, %{"id" => order_id}) do
    current_user = conn.assigns[:user]

    if current_user do
      case get_user_order(current_user.id, order_id) do
        {:ok, order} ->
          conn
          |> json(%{
            success: true,
            order: format_order_response(order)
          })

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{
            success: false,
            error: "order_not_found",
            message: "Order not found"
          })

        {:error, reason} ->
          Logger.error("Failed to get order",
            order_id: order_id,
            user_id: current_user.id,
            reason: inspect(reason)
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "order_retrieval_failed",
            message: "Unable to retrieve order"
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to view orders"
      })
    end
  end

  @doc """
  Lists all orders for the current user.

  Optional query parameters:
  - status: Filter by order status
  - limit: Number of orders to return (default: 20)
  - offset: Number of orders to skip (default: 0)
  """
  def index(conn, params) do
    current_user = conn.assigns[:user]

    if current_user do
      status_filter = Map.get(params, "status")
      limit = safe_parse_integer(Map.get(params, "limit", "20"), 20)
      offset = safe_parse_integer(Map.get(params, "offset", "0"), 0)

      case get_user_orders(current_user.id, status_filter, limit, offset) do
        {:ok, orders} ->
          conn
          |> json(%{
            success: true,
            orders: Enum.map(orders, &format_order_response/1),
            pagination: %{
              limit: limit,
              offset: offset,
              has_more: length(orders) == limit
            }
          })

        {:error, reason} ->
          Logger.error("Failed to list orders",
            user_id: current_user.id,
            reason: inspect(reason)
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "order_listing_failed",
            message: "Unable to retrieve orders"
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to view orders"
      })
    end
  end

  @doc """
  Cancels an order if it's in a cancellable state.

  Expects order_id as URL parameter.
  """
  def cancel(conn, %{"id" => order_id}) do
    current_user = conn.assigns[:user]

    if current_user do
      case cancel_user_order(current_user.id, order_id) do
        {:ok, order} ->
          Logger.info("Order cancelled successfully",
            order_id: order.id,
            user_id: current_user.id
          )

          conn
          |> json(%{
            success: true,
            order: format_order_response(order),
            message: "Order cancelled successfully"
          })

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{
            success: false,
            error: "order_not_found",
            message: "Order not found"
          })

        {:error, :cannot_cancel} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "cannot_cancel",
            message: "This order cannot be cancelled"
          })

        {:error, reason} ->
          Logger.error("Order cancellation failed",
            order_id: order_id,
            user_id: current_user.id,
            reason: inspect(reason)
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "cancellation_failed",
            message: "Unable to cancel order"
          })
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to cancel orders"
      })
    end
  end

  # Private helper functions

  defp safe_parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> default
    end
  end

  defp safe_parse_integer(value, _default) when is_integer(value), do: value
  defp safe_parse_integer(_, default), do: default

  defp get_user_order(user_id, order_id) do
    case Ticketing.get_user_order(user_id, order_id) do
      nil -> {:error, :not_found}
      order -> {:ok, order}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    error -> {:error, error}
  end

  defp get_user_orders(user_id, status_filter, limit, offset) do
    try do
      orders = Ticketing.list_user_orders(user_id, status_filter, limit, offset)
      {:ok, orders}
    rescue
      error -> {:error, error}
    end
  end

  defp cancel_user_order(user_id, order_id) do
    case get_user_order(user_id, order_id) do
      {:ok, order} ->
        if order.status in ["pending", "payment_pending"] do
          Ticketing.cancel_order(order)
        else
          {:error, :cannot_cancel}
        end

      error ->
        error
    end
  end

  defp format_order_response(order) do
    %{
      id: order.id,
      status: order.status,
      total_cents: order.total_cents,
      application_fee_amount: order.application_fee_amount,
      stripe_session_id: order.stripe_session_id,
      ticket: %{
        id: order.ticket.id,
        title: order.ticket.title,
        price_cents: order.ticket.base_price_cents
      },
      event: %{
        id: order.event.id,
        title: order.event.title,
        slug: order.event.slug,
        start_date: order.event.start_date
      },
      inserted_at: order.inserted_at,
      updated_at: order.updated_at
    }
  end
end
