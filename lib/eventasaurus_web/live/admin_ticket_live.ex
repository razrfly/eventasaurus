defmodule EventasaurusWeb.AdminTicketLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Ticketing}
  alias EventasaurusWeb.Helpers.CurrencyHelpers

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    event = Events.get_event_by_slug(slug)

    if event do
      case socket.assigns[:user] do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "You must be logged in to manage tickets")
           |> redirect(to: "/auth/login")}

        user ->
          if Events.user_can_manage_event?(user, event) do
            tickets = Ticketing.list_tickets_for_event(event.id)

            {:ok,
             socket
             |> assign(:event, event)
             |> assign(:tickets, tickets)
             |> assign(:user, user)
             |> assign(:loading, false)
             |> assign(:show_ticket_modal, false)
             |> assign(:ticket_form_data, %{})
             |> assign(:editing_ticket_id, nil)
             |> assign(:page_title, "Manage Tickets - #{event.title}")}
          else
            {:ok,
             socket
             |> put_flash(:error, "You don't have permission to manage this event's tickets")
             |> redirect(to: "/dashboard")}
          end
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "Event not found")
       |> redirect(to: "/dashboard")}
    end
  end

  @impl true
  def handle_event("add_ticket", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_ticket_modal, true)
     |> assign(:ticket_form_data, %{"currency" => "usd", "pricing_model" => "fixed"})
     |> assign(:editing_ticket_id, nil)}
  end

  @impl true
  def handle_event("edit_ticket", %{"id" => ticket_id_str}, socket) do
    case Integer.parse(ticket_id_str) do
      {ticket_id, ""} ->
        ticket = Enum.find(socket.assigns.tickets, &(&1.id == ticket_id))

        if ticket do
          form_data = %{
            "title" => ticket.title,
            "description" => ticket.description || "",
            "pricing_model" => ticket.pricing_model || "fixed",
            "price" => CurrencyHelpers.format_price_from_cents(ticket.base_price_cents),
            "minimum_price" => CurrencyHelpers.format_price_from_cents(ticket.minimum_price_cents || 0),
            "suggested_price" => CurrencyHelpers.format_price_from_cents(ticket.suggested_price_cents || ticket.base_price_cents),
            "currency" => ticket.currency || "usd",
            "quantity" => Integer.to_string(ticket.quantity),
            "starts_at" => format_datetime_for_input(ticket.starts_at),
            "ends_at" => format_datetime_for_input(ticket.ends_at),
            "tippable" => ticket.tippable || false
          }

          {:noreply,
           socket
           |> assign(:show_ticket_modal, true)
           |> assign(:ticket_form_data, form_data)
           |> assign(:editing_ticket_id, ticket.id)}
        else
          {:noreply, put_flash(socket, :error, "Ticket not found")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid ticket ID")}
    end
  end

  @impl true
  def handle_event("delete_ticket", %{"id" => ticket_id_str}, socket) do
    case Integer.parse(ticket_id_str) do
      {ticket_id, ""} ->
        ticket = Enum.find(socket.assigns.tickets, &(&1.id == ticket_id))

        if ticket do
          case Ticketing.delete_ticket(ticket) do
            {:ok, _} ->
              updated_tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)
              {:noreply,
               socket
               |> assign(:tickets, updated_tickets)
               |> put_flash(:info, "Ticket deleted successfully")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Failed to delete ticket")}
          end
        else
          {:noreply, put_flash(socket, :error, "Ticket not found")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid ticket ID")}
    end
  end

  @impl true
  def handle_event("close_ticket_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_ticket_modal, false)
     |> assign(:ticket_form_data, %{})
     |> assign(:editing_ticket_id, nil)}
  end

  @impl true
  def handle_event("validate_ticket", %{"ticket" => ticket_params}, socket) do
    current_data = socket.assigns.ticket_form_data || %{}
    updated_data = Map.merge(current_data, ticket_params)
    {:noreply, assign(socket, :ticket_form_data, updated_data)}
  end

  @impl true
  def handle_event("save_ticket", %{"ticket" => ticket_params}, socket) do
    case parse_and_validate_ticket_data(ticket_params) do
      {:ok, processed_params} ->
        case socket.assigns.editing_ticket_id do
          nil ->
            # Create new ticket
            case Ticketing.create_ticket(socket.assigns.event, processed_params) do
              {:ok, _ticket} ->
                updated_tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)
                {:noreply,
                 socket
                 |> assign(:tickets, updated_tickets)
                 |> assign(:show_ticket_modal, false)
                 |> assign(:ticket_form_data, %{})
                 |> put_flash(:info, "Ticket created successfully")}

              {:error, changeset} ->
                error_msg = extract_changeset_errors(changeset)
                {:noreply, put_flash(socket, :error, "Failed to create ticket: #{error_msg}")}
            end

          ticket_id ->
            # Update existing ticket
            ticket = Enum.find(socket.assigns.tickets, &(&1.id == ticket_id))
            case Ticketing.update_ticket(ticket, processed_params) do
              {:ok, _ticket} ->
                updated_tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)
                {:noreply,
                 socket
                 |> assign(:tickets, updated_tickets)
                 |> assign(:show_ticket_modal, false)
                 |> assign(:ticket_form_data, %{})
                 |> put_flash(:info, "Ticket updated successfully")}

              {:error, changeset} ->
                error_msg = extract_changeset_errors(changeset)
                {:noreply, put_flash(socket, :error, "Failed to update ticket: #{error_msg}")}
            end
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # Helper functions

  defp format_datetime_for_input(nil), do: ""
  defp format_datetime_for_input(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end

  defp parse_and_validate_ticket_data(params) do
    with {:ok, base_price_cents} <- parse_price_cents(params["price"]),
         {:ok, quantity} <- parse_quantity(params["quantity"]) do
      minimum_price_cents = case parse_price_cents(params["minimum_price"]) do
        {:ok, cents} -> cents
        {:error, _} -> 0
      end

      suggested_price_cents = case parse_price_cents(params["suggested_price"]) do
        {:ok, cents} -> cents
        {:error, _} -> base_price_cents
      end

      processed = %{
        title: String.trim(params["title"] || ""),
        description: params["description"],
        base_price_cents: base_price_cents,
        minimum_price_cents: minimum_price_cents,
        suggested_price_cents: suggested_price_cents,
        pricing_model: params["pricing_model"] || "fixed",
        currency: params["currency"] || "usd",
        quantity: quantity,
        starts_at: parse_datetime(params["starts_at"]),
        ends_at: parse_datetime(params["ends_at"]),
        tippable: params["tippable"] in [true, "true", "on"]
      }
      {:ok, processed}
    else
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_price_cents(nil), do: {:ok, 0}
  defp parse_price_cents(""), do: {:ok, 0}
  defp parse_price_cents(price_str) when is_binary(price_str) do
    case CurrencyHelpers.parse_price_to_cents(price_str) do
      {:ok, cents} -> {:ok, cents}
      :error -> {:error, "Invalid price format"}
    end
  end

  defp parse_quantity(nil), do: {:error, "Quantity is required"}
  defp parse_quantity(""), do: {:error, "Quantity is required"}
  defp parse_quantity(qty_str) when is_binary(qty_str) do
    case Integer.parse(qty_str) do
      {qty, ""} when qty > 0 -> {:ok, qty}
      _ -> {:error, "Quantity must be a positive number"}
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(""), do: nil
  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case NaiveDateTime.from_iso8601(datetime_str) do
      {:ok, naive_dt} -> DateTime.from_naive!(naive_dt, "Etc/UTC")
      {:error, _} -> nil
    end
  end

  defp extract_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end
end
