defmodule EventasaurusWeb.TicketController do
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Ticketing
  alias EventasaurusWeb.Helpers.TicketCrypto

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
        |> put_flash(:error, "Order not found.")
        |> render(:verify_error, error: "Order not found")

      {:error, :not_confirmed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, "Order is not confirmed.")
        |> render(:verify_error, error: "Order not confirmed")

      {:error, :invalid_ticket} ->
        conn
        |> put_status(:bad_request)
        |> put_flash(:error, "Invalid ticket format.")
        |> render(:verify_error, error: "Invalid ticket format")

      {:error, :invalid_hash} ->
        conn
        |> put_status(:unauthorized)
        |> put_flash(:error, "Ticket authentication failed.")
        |> render(:verify_error, error: "Invalid ticket signature")

      {:error, :invalid_format} ->
        conn
        |> put_status(:bad_request)
        |> put_flash(:error, "Invalid ticket format.")
        |> render(:verify_error, error: "Malformed ticket ID")
    end
  end

  defp verify_ticket(ticket_id, order_id) when is_binary(ticket_id) and is_binary(order_id) do
    # Parse order_id to integer for database lookup
    case Integer.parse(order_id) do
      {parsed_order_id, ""} ->
        # Extract components from ticket ID
        case extract_ticket_components(ticket_id) do
          {:error, reason} -> {:error, reason}
          {:ok, extracted_order_id, provided_hash} ->
            # Verify order IDs match
            if extracted_order_id != parsed_order_id do
              {:error, :invalid_ticket}
            else
              # Get and validate order
              case get_order_with_validation(parsed_order_id) do
                {:error, reason} -> {:error, reason}
                {:ok, order} ->
                  # Validate cryptographic hash
                  if validate_ticket_hash(order, provided_hash) do
                    {:ok, order}
                  else
                    {:error, :invalid_hash}
                  end
              end
            end
        end
      _ -> {:error, :invalid_format}
    end
  end

  defp verify_ticket(_, _), do: {:error, :invalid_format}

  defp extract_ticket_components("EVT-" <> rest) do
    case String.split(rest, "-", parts: 2) do
      [order_id_str, hash] when byte_size(hash) == 16 ->  # Updated to 16 chars for HMAC
        case Integer.parse(order_id_str) do
          {order_id, ""} -> {:ok, order_id, hash}
          _ -> {:error, :invalid_format}
        end
      _ -> {:error, :invalid_format}
    end
  end

  defp extract_ticket_components(_), do: {:error, :invalid_format}

  defp get_order_with_validation(order_id) do
    case Ticketing.get_order(order_id) do
      nil -> {:error, :not_found}
      order ->
        if order.status == "confirmed" do
          {:ok, order}
        else
          {:error, :not_confirmed}
        end
    end
  end

  defp validate_ticket_hash(order, provided_hash) do
    # Generate expected hash using the same method as dashboard_live.ex
    expected_hash = generate_secure_hash_for_order(order)
    # Use constant-time comparison to prevent timing attacks
    secure_compare(provided_hash, expected_hash)
  end

  defp generate_secure_hash_for_order(order) do
    # Use HMAC with server secret for cryptographically secure hash generation
    secret_key = TicketCrypto.get_ticket_secret_key()
    data = "#{order.id}#{order.inserted_at}#{order.user_id}#{order.status}"
    :crypto.mac(:hmac, :sha256, secret_key, data)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 16)  # Increased entropy to 16 chars
  end

  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false
  defp secure_compare(a, b) do
    :crypto.hash_equals(a, b)
  end
end
