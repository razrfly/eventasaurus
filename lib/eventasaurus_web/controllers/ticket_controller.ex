defmodule EventasaurusWeb.TicketController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Ticketing

  def verify(conn, %{"ticket_id" => ticket_id} = params) do
    order_id = params["order"]

    case verify_ticket(ticket_id, order_id) do
      {:ok, order} ->
        conn
        |> put_flash(:info, "Ticket verified successfully!")
        |> render(:verify, order: order, ticket_id: ticket_id)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_flash(:error, "Ticket not found or invalid.")
        |> render(:verify_error, error: "Ticket not found")

      {:error, :invalid_ticket} ->
        conn
        |> put_status(:bad_request)
        |> put_flash(:error, "Invalid ticket format.")
        |> render(:verify_error, error: "Invalid ticket")
    end
  end

  defp verify_ticket(ticket_id, order_id) when is_binary(ticket_id) and is_binary(order_id) do
    # Extract order ID from ticket format: EVT-{order_id}-{hash}
    case extract_order_id_from_ticket(ticket_id) do
      ^order_id ->
        case Ticketing.get_order(order_id) do
          nil -> {:error, :not_found}
          order ->
            if order.status == "confirmed" do
              {:ok, order}
            else
              {:error, :not_found}
            end
        end
      _ -> {:error, :invalid_ticket}
    end
  end

  defp verify_ticket(_, _), do: {:error, :invalid_ticket}

  defp extract_order_id_from_ticket("EVT-" <> rest) do
    case String.split(rest, "-", parts: 2) do
      [order_id, _hash] -> order_id
      _ -> nil
    end
  end

  defp extract_order_id_from_ticket(_), do: nil
end
