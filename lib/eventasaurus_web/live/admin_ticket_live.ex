defmodule EventasaurusWeb.AdminTicketLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Events, Ticketing}

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
     |> put_flash(:info, "Redirecting to event edit page to add ticket...")
     |> redirect(to: ~p"/events/#{socket.assigns.event.slug}/edit")}
  end

  @impl true
  def handle_event("edit_ticket", %{"id" => _ticket_id_str}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Redirecting to event edit page to edit ticket...")
     |> redirect(to: ~p"/events/#{socket.assigns.event.slug}/edit")}
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
  def handle_event("refresh", _params, socket) do
    tickets = Ticketing.list_tickets_for_event(socket.assigns.event.id)
    {:noreply, assign(socket, :tickets, tickets)}
  end
end
