defmodule EventasaurusWeb.CheckoutLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Ticketing, Events}
  alias EventasaurusWeb.Helpers.CurrencyHelpers

  require Logger

  @impl true
  def mount(%{"slug" => event_slug} = params, _session, socket) do
    case get_event_by_slug(event_slug) do
      {:ok, event} ->
        # Get selected tickets from URL parameters
        selected_tickets = parse_tickets_from_params(params)

        if map_size(selected_tickets) == 0 do
          # No tickets selected, redirect back to event
          {:ok,
           socket
           |> put_flash(:error, "Please select tickets before proceeding to checkout.")
           |> redirect(to: "/events/#{event.slug}")}
        else
          # Load tickets and calculate order details
          tickets = Ticketing.list_tickets_for_event(event.id)

          # Validate that selected tickets exist and are available
          case validate_selected_tickets(tickets, selected_tickets) do
            {:ok, validated_selection} ->
              order_items = build_order_items(tickets, validated_selection)
              total_amount = calculate_total_amount(order_items)

                                          # Get user from socket assigns (set by auth hook)
              user = socket.assigns[:user]
              is_guest = is_nil(user)

              {:ok,
               socket
               |> assign(:event, event)
               |> assign(:tickets, tickets)
               |> assign(:selected_tickets, validated_selection)
               |> assign(:order_items, order_items)
               |> assign(:total_amount, total_amount)
               |> assign(:processing, false)
               |> assign(:errors, [])
               |> assign(:user, user)
               |> assign(:is_guest, is_guest)
               |> assign(:guest_form, %{"name" => "", "email" => ""})
               |> assign(:show_guest_form, is_guest)}

            {:error, message} ->
              {:ok,
               socket
               |> put_flash(:error, message)
               |> redirect(to: "/events/#{event.slug}")}
          end
        end

      {:error, :event_not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Event not found.")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_event("proceed_with_checkout", _params, socket) do
    %{
      user: user,
      event: _event,
      order_items: order_items,
      total_amount: total_amount,
      is_guest: is_guest,
      guest_form: guest_form
    } = socket.assigns

    # Validate guest information if user is not authenticated
    if is_guest do
      case validate_guest_form(guest_form) do
        {:ok, guest_info} ->
          proceed_with_guest_checkout(socket, guest_info, order_items, total_amount)
        {:error, errors} ->
          {:noreply,
           socket
           |> assign(:errors, errors)
           |> put_flash(:error, "Please complete all required fields.")}
      end
    else
      # Authenticated user flow
      Logger.info("Proceed with checkout clicked",
        user_id: user.id,
        total_amount: total_amount,
        order_items_count: length(order_items)
      )

      socket = assign(socket, :processing, true)

      case total_amount do
        0 ->
          # Free tickets - create orders directly
          Logger.info("Processing free ticket checkout")
          handle_free_ticket_checkout(socket, user, order_items)

        _ ->
          # Paid tickets - create Stripe checkout session
          Logger.info("Processing paid ticket checkout")
          handle_paid_ticket_checkout(socket, user, order_items)
      end
    end
  end

  @impl true
  def handle_event("update_quantity", %{"ticket_id" => ticket_id, "quantity" => quantity_str}, socket) do
    ticket_id = String.to_integer(ticket_id)
    quantity = String.to_integer(quantity_str)

    # Validate quantity
    ticket = Enum.find(socket.assigns.tickets, &(&1.id == ticket_id))
    available = if ticket, do: Ticketing.available_quantity(ticket), else: 0

    cond do
      quantity < 0 ->
        {:noreply, socket}

      quantity == 0 ->
        # Remove ticket from selection
        updated_selection = Map.delete(socket.assigns.selected_tickets, ticket_id)
        update_checkout_totals(socket, updated_selection)

      quantity > available ->
        {:noreply,
         socket
         |> put_flash(:error, "Only #{available} tickets available for #{ticket.title}")
        }

      quantity > 10 ->
        {:noreply,
         socket
         |> put_flash(:error, "Maximum 10 tickets per order")
        }

      true ->
        # Update quantity
        updated_selection = Map.put(socket.assigns.selected_tickets, ticket_id, quantity)
        update_checkout_totals(socket, updated_selection)
    end
  end

  @impl true
  def handle_event("remove_ticket", %{"ticket_id" => ticket_id}, socket) do
    ticket_id = String.to_integer(ticket_id)
    updated_selection = Map.delete(socket.assigns.selected_tickets, ticket_id)

    if map_size(updated_selection) == 0 do
      # No tickets left, redirect back to event
      {:noreply,
       socket
       |> put_flash(:info, "All tickets removed from cart.")
       |> redirect(to: "/events/#{socket.assigns.event.slug}")}
    else
      update_checkout_totals(socket, updated_selection)
    end
  end

  @impl true
  def handle_event("show_guest_form", _params, socket) do
    {:noreply, assign(socket, :show_guest_form, true)}
  end

  @impl true
  def handle_event("update_guest_form", %{"value" => value} = params, socket) do
    field = case params do
      %{"field" => field} -> field
      _ -> nil
    end

    if field do
      updated_form = Map.put(socket.assigns.guest_form, field, value)
      # Clear validation errors when user starts typing
      {:noreply,
       socket
       |> assign(:guest_form, updated_form)
       |> assign(:errors, [])
       |> clear_flash()}
    else
      {:noreply, socket}
    end
  end

  # Private helper functions

  defp get_event_by_slug(slug) do
    case Events.get_event_by_slug(slug) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  defp parse_tickets_from_params(params) do
    # Parse tickets from new URI-encoded format where ticket IDs are parameter keys
    # Remove known non-ticket parameters like "slug"
    known_params = ["slug"]

    params
    |> Enum.reject(fn {key, _value} -> key in known_params end)
    |> Enum.reduce(%{}, fn {ticket_id_str, quantity_value}, acc ->
      case {Integer.parse(ticket_id_str), parse_quantity(quantity_value)} do
        {{ticket_id, ""}, quantity} when is_integer(quantity) and quantity > 0 ->
          Map.put(acc, ticket_id, quantity)
        _ ->
          acc
      end
    end)
  end

  defp parse_quantity(value) when is_integer(value) and value > 0, do: value
  defp parse_quantity(value) when is_binary(value) do
    case Integer.parse(value) do
      {quantity, ""} when quantity > 0 -> quantity
      _ -> nil
    end
  end
  defp parse_quantity(_), do: nil

  defp validate_selected_tickets(tickets, selected_tickets) do
    # Create a map of ticket_id -> ticket for quick lookup
    ticket_map = Enum.into(tickets, %{}, fn ticket -> {ticket.id, ticket} end)

    # Validate each selected ticket
    validated_tickets =
      selected_tickets
      |> Enum.reduce_while(%{}, fn {ticket_id, quantity}, acc ->
        case Map.get(ticket_map, ticket_id) do
          nil ->
            # Ticket doesn't exist
            {:halt, {:error, "Selected ticket no longer exists"}}

          ticket ->
            available = Ticketing.available_quantity(ticket)

            cond do
              quantity <= 0 ->
                # Skip invalid quantities
                {:cont, acc}

              quantity > available ->
                {:halt, {:error, "Only #{available} tickets available for #{ticket.title}"}}

              quantity > 10 ->
                {:halt, {:error, "cannot exceed 10 tickets per order"}}

              true ->
                {:cont, Map.put(acc, ticket_id, quantity)}
            end
        end
      end)

    case validated_tickets do
      {:error, message} -> {:error, message}
      validated_map when map_size(validated_map) == 0 -> {:error, "No valid tickets selected"}
      validated_map ->
        # Check total quantity across all tickets
        total_quantity = validated_map |> Map.values() |> Enum.sum()
        if total_quantity > 10 do
          {:error, "cannot exceed 10 tickets per order"}
        else
          {:ok, validated_map}
        end
    end
  end

  defp build_order_items(tickets, selected_tickets) do
    tickets
    |> Enum.filter(fn ticket ->
      Map.has_key?(selected_tickets, ticket.id) && Map.get(selected_tickets, ticket.id, 0) > 0
    end)
    |> Enum.map(fn ticket ->
      quantity = Map.get(selected_tickets, ticket.id, 0)
      %{
        ticket: ticket,
        quantity: quantity,
        unit_price: ticket.base_price_cents || 0,
        total_price: (ticket.base_price_cents || 0) * quantity
      }
    end)
  end

  defp calculate_total_amount(order_items) do
    Enum.reduce(order_items, 0, fn item, acc -> acc + item.total_price end)
  end

  defp update_checkout_totals(socket, updated_selection) do
    order_items = build_order_items(socket.assigns.tickets, updated_selection)
    total_amount = calculate_total_amount(order_items)

    {:noreply,
     socket
     |> assign(:selected_tickets, updated_selection)
     |> assign(:order_items, order_items)
     |> assign(:total_amount, total_amount)
     |> preserve_auth_state()
     |> clear_flash()}
  end

  defp handle_free_ticket_checkout(socket, user, order_items) do
    try do
      # Create orders for each ticket type
      results = Enum.map(order_items, fn item ->
        Logger.info("Creating order for free ticket",
          user_id: user.id,
          ticket_id: item.ticket.id,
          quantity: item.quantity
        )
        result = Ticketing.create_order(user, item.ticket, %{quantity: item.quantity})
        Logger.info("Order creation result", result: inspect(result))
        result
      end)

      # Check if all orders were created successfully
      case Enum.find(results, fn result -> match?({:error, _}, result) end) do
        nil ->
          # All orders created successfully - confirm them
          orders = Enum.map(results, fn {:ok, order} -> order end)

          # Confirm all orders (free tickets)
          confirmation_results = Enum.map(orders, fn order ->
            case Ticketing.confirm_order(order, "free_ticket") do
              {:ok, confirmed_order} -> {:ok, confirmed_order}
              {:error, reason} -> {:error, {order.id, reason}}
            end
          end)

          # Check if all confirmations were successful
          case Enum.find(confirmation_results, fn result -> match?({:error, _}, result) end) do
            nil ->
              # All confirmations successful
              confirmed_orders = Enum.map(confirmation_results, fn {:ok, order} -> order end)

              Logger.info("Free ticket orders created and confirmed",
                user_id: user.id,
                event_id: socket.assigns.event.id,
                order_count: length(confirmed_orders)
              )

              {:noreply,
               socket
               |> put_flash(:success, "Your free tickets have been reserved successfully!")
               |> redirect(to: "/events/#{socket.assigns.event.slug}")}

            {:error, {order_id, reason}} ->
              Logger.error("Failed to confirm free ticket order",
                user_id: user.id,
                order_id: order_id,
                reason: inspect(reason)
              )

              {:noreply,
               socket
               |> assign(:processing, false)
               |> put_flash(:error, "Failed to confirm ticket reservation. Please try again.")}
          end

        {:error, reason} ->
          Logger.error("Failed to create free ticket orders",
            user_id: user.id,
            event_id: socket.assigns.event.id,
            reason: inspect(reason)
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Failed to reserve tickets. Please try again.")}
      end
    rescue
      error ->
        Logger.error("Exception during free ticket checkout",
          user_id: user.id,
          event_id: socket.assigns.event.id,
          error: inspect(error)
        )

        {:noreply,
         socket
         |> assign(:processing, false)
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  defp handle_paid_ticket_checkout(socket, user, order_items) do
    # For paid tickets with multiple ticket types, we need to create separate orders
    # Each order will have its own Stripe payment intent

    # For simplicity, we'll handle multiple ticket orders by redirecting to the first ticket's checkout
    # In a production system, you might combine into a single order or handle each separately

    case order_items do
      [single_item] ->
        # Single ticket type - create payment intent directly
        create_stripe_checkout_session(socket, user, single_item)

      multiple_items ->
        # Multiple ticket types - for now, combine into a single checkout
        # This is a simplified approach; production might handle differently
        _total_amount = calculate_total_amount(multiple_items)

        # Create a combined order description
        _description = multiple_items
        |> Enum.map(fn item -> "#{item.quantity}x #{item.ticket.title}" end)
        |> Enum.join(", ")

        # Use the first ticket's event for organization context
        _first_ticket = hd(multiple_items).ticket

        # For multiple items, we'll need to create orders separately but redirect to a combined payment
        create_combined_stripe_checkout(socket, user, multiple_items)
    end
  end

  defp create_stripe_checkout_session(socket, user, order_item) do
    try do
      case Ticketing.create_checkout_session(user, order_item.ticket, %{quantity: order_item.quantity}) do
        {:ok, %{checkout_url: checkout_url, session_id: session_id}} ->
          Logger.info("Stripe hosted checkout session created",
            user_id: user.id,
            session_id: session_id
          )

          # Redirect to Stripe hosted checkout
          {:noreply,
           socket
           |> assign(:processing, false)
           |> redirect(external: checkout_url)}

        {:error, :no_stripe_account} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> preserve_auth_state()
           |> put_flash(:error, "The event organizer has not set up payment processing. Please contact them directly.")}

        {:error, :ticket_unavailable} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> preserve_auth_state()
           |> put_flash(:error, "Sorry, these tickets are no longer available.")}

        {:error, reason} when is_binary(reason) ->
          Logger.error("Stripe checkout creation failed",
            user_id: user.id,
            ticket_id: order_item.ticket.id,
            reason: reason
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> preserve_auth_state()
           |> put_flash(:error, "Payment processing is temporarily unavailable. Please try again.")}

        {:error, reason} ->
          Logger.error("Order creation failed",
            user_id: user.id,
            ticket_id: order_item.ticket.id,
            reason: inspect(reason)
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> preserve_auth_state()
           |> put_flash(:error, "Unable to process payment. Please try again.")}
      end
    rescue
      error ->
        Logger.error("Exception during Stripe checkout creation",
          user_id: user.id,
          ticket_id: order_item.ticket.id,
          error: inspect(error)
        )

        {:noreply,
         socket
         |> assign(:processing, false)
         |> preserve_auth_state()
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  defp create_combined_stripe_checkout(socket, user, order_items) do
    # For multiple ticket types, we need to create a combined Stripe checkout session
    # with multiple line items for all selected tickets

    try do
      Logger.info("Creating hosted checkout session for multiple ticket types",
        user_id: user.id,
        ticket_count: length(order_items)
      )

      case Ticketing.create_multi_ticket_checkout_session(user, order_items) do
        {:ok, %{checkout_url: checkout_url, session_id: session_id}} ->
          Logger.info("Successfully created multi-ticket hosted checkout",
            user_id: user.id,
            session_id: session_id
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> redirect(external: checkout_url)}

        {:error, :no_stripe_account} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> preserve_auth_state()
           |> put_flash(:error, "The event organizer has not set up payment processing. Please contact them directly.")}

        {:error, :ticket_unavailable} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> preserve_auth_state()
           |> put_flash(:error, "Sorry, some of these tickets are no longer available.")}

        {:error, reason} ->
          Logger.error("Failed to create hosted checkout for multiple tickets",
            user_id: user.id,
            reason: inspect(reason)
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> preserve_auth_state()
           |> put_flash(:error, "Unable to process your order. Please try again.")}
      end
    rescue
      error ->
        Logger.error("Exception during multiple order creation",
          user_id: user.id,
          error: inspect(error)
        )

        {:noreply,
         socket
         |> assign(:processing, false)
         |> preserve_auth_state()
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end



  def validate_guest_form(guest_form) do
    name = String.trim(guest_form["name"] || "")
    email = String.trim(guest_form["email"] || "")

    errors = []

    errors = if name == "", do: ["Name is required" | errors], else: errors
    errors = if email == "", do: ["Email is required" | errors], else: errors
    # Email format validation handled by HTML5 type="email" + Supabase Auth API

    case errors do
      [] -> {:ok, %{name: name, email: email}}
      _ -> {:error, errors}
    end
  end

  # Basic server-side email validation with HTML5 + Supabase Auth API as additional layers
  def valid_email?(email) when is_binary(email) do
    String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
  end
  def valid_email?(_), do: false

  defp proceed_with_guest_checkout(socket, guest_info, order_items, total_amount) do
    Logger.info("Proceed with guest checkout",
      name: guest_info.name,
      email: guest_info.email,
      total_amount: total_amount,
      order_items_count: length(order_items)
    )

    socket = assign(socket, :processing, true)

    case total_amount do
      0 ->
        # Free tickets - handle guest free ticket checkout
        Logger.info("Processing guest free ticket checkout")
        handle_guest_free_ticket_checkout(socket, guest_info, order_items)

      _ ->
        # Paid tickets - create guest Stripe checkout session
        Logger.info("Processing guest paid ticket checkout")
        handle_guest_paid_ticket_checkout(socket, guest_info, order_items)
    end
  end

  defp handle_guest_free_ticket_checkout(socket, guest_info, order_items) do
    try do
      # For free tickets, we'll use the first ticket to create the user
      # then create orders for all ticket types
      case order_items do
        [] ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "No tickets selected.")}

        [_first_item | _rest] ->
          # Create/find user first using Events.register_user_for_event pattern
          case Events.register_user_for_event(socket.assigns.event.id, guest_info.name, guest_info.email) do
            {:ok, :new_registration, _participant} ->
              # User was created and registered, now process tickets
              process_guest_free_tickets(socket, guest_info.email, order_items)

            {:ok, :existing_user_registered, _participant} ->
              # User existed and was registered, now process tickets
              process_guest_free_tickets(socket, guest_info.email, order_items)

            {:error, :already_registered} ->
              # User is already registered, just process tickets
              process_guest_free_tickets(socket, guest_info.email, order_items)

            {:error, reason} ->
              Logger.error("Failed to register guest user for event",
                email: guest_info.email,
                event_id: socket.assigns.event.id,
                reason: inspect(reason)
              )

              {:noreply,
               socket
               |> assign(:processing, false)
               |> put_flash(:error, "Failed to process registration. Please try again.")}
          end
      end
    rescue
      error ->
        Logger.error("Exception during guest free ticket checkout",
          email: guest_info.email,
          event_id: socket.assigns.event.id,
          error: inspect(error)
        )

        {:noreply,
         socket
         |> assign(:processing, false)
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  defp process_guest_free_tickets(socket, email, order_items) do
    # Get the user from database
    case EventasaurusApp.Accounts.get_user_by_email(email) do
      nil ->
        {:noreply,
         socket
         |> assign(:processing, false)
         |> put_flash(:error, "User account not found. Please try again.")}

      user ->
        handle_free_ticket_checkout(socket, user, order_items)
    end
  end

  defp handle_guest_paid_ticket_checkout(socket, guest_info, order_items) do
    try do
      # For paid tickets, create separate checkout sessions for each ticket type
      # For simplicity, we'll handle the first ticket type first
      case order_items do
        [] ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "No tickets selected.")}

        [single_item] ->
          # Single ticket type - create guest checkout session
          create_guest_stripe_checkout_session(socket, guest_info, single_item)

        multiple_items ->
          # Multiple ticket types - create multi-ticket guest checkout session
          Logger.info("Multiple ticket types selected for guest checkout")
          create_guest_multi_ticket_checkout_session(socket, guest_info, multiple_items)
      end
    rescue
      error ->
        Logger.error("Exception during guest paid ticket checkout",
          email: guest_info.email,
          error: inspect(error)
        )

        {:noreply,
         socket
         |> assign(:processing, false)
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  defp create_guest_stripe_checkout_session(socket, guest_info, order_item) do
    try do
      case Ticketing.create_guest_checkout_session(
        order_item.ticket,
        guest_info.name,
        guest_info.email,
        %{quantity: order_item.quantity}
      ) do
        {:ok, %{order: order, checkout_url: checkout_url, session_id: session_id, user: _user}} ->
          Logger.info("Guest Stripe checkout session created",
            order_id: order.id,
            session_id: session_id,
            email: guest_info.email
          )

          # Redirect to Stripe Checkout
          {:noreply,
           socket
           |> assign(:processing, false)
           |> redirect(external: checkout_url)}

        {:error, :no_stripe_account} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "The event organizer has not set up payment processing. Please contact them directly.")}

        {:error, :ticket_unavailable} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Sorry, these tickets are no longer available.")}

        {:error, reason} when is_binary(reason) ->
          Logger.error("Guest Stripe checkout creation failed",
            email: guest_info.email,
            ticket_id: order_item.ticket.id,
            reason: reason
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Payment processing is temporarily unavailable. Please try again.")}

        {:error, reason} ->
          Logger.error("Guest order creation failed",
            email: guest_info.email,
            ticket_id: order_item.ticket.id,
            reason: inspect(reason)
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Unable to process payment. Please try again.")}
      end
    rescue
      error ->
        Logger.error("Exception during guest Stripe checkout creation",
          email: guest_info.email,
          ticket_id: order_item.ticket.id,
          error: inspect(error)
        )

        {:noreply,
         socket
         |> assign(:processing, false)
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  defp create_guest_multi_ticket_checkout_session(socket, guest_info, order_items) do
    try do
      case Ticketing.create_guest_multi_ticket_checkout_session(guest_info.name, guest_info.email, order_items) do
        {:ok, %{orders: orders, checkout_url: checkout_url, session_id: session_id, user: _user}} ->
          Logger.info("Guest multi-ticket Stripe checkout session created",
            orders_count: length(orders),
            session_id: session_id,
            email: guest_info.email
          )

          # Redirect to Stripe Checkout
          {:noreply,
           socket
           |> assign(:processing, false)
           |> redirect(external: checkout_url)}

        {:error, :no_stripe_account} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "The event organizer has not set up payment processing. Please contact them directly.")}

        {:error, :ticket_unavailable} ->
          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Sorry, some of these tickets are no longer available.")}

        {:error, reason} when is_binary(reason) ->
          Logger.error("Guest multi-ticket Stripe checkout creation failed",
            email: guest_info.email,
            reason: reason
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Payment processing is temporarily unavailable. Please try again.")}

        {:error, reason} ->
          Logger.error("Guest multi-ticket order creation failed",
            email: guest_info.email,
            reason: inspect(reason)
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Unable to process payment. Please try again.")}
      end
    rescue
      error ->
        Logger.error("Exception during guest multi-ticket Stripe checkout creation",
          email: guest_info.email,
          error: inspect(error)
        )

        {:noreply,
         socket
         |> assign(:processing, false)
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <div class="container mx-auto px-6 py-8 max-w-6xl">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900 mb-2">Checkout</h1>
          <p class="text-gray-600">Complete your purchase for <span class="font-medium"><%= @event.title %></span></p>
        </div>

        <%= if @order_items == [] do %>
          <div class="bg-white rounded-xl p-8 text-center">
            <p class="text-gray-500 mb-4">No tickets selected</p>
            <.link navigate={"/events/#{@event.slug}"} class="inline-flex items-center text-blue-600 hover:text-blue-700 font-medium">
              ← Back to event
            </.link>
          </div>
        <% else %>
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <!-- Main Content Area -->
            <div class="lg:col-span-2 space-y-6">
              <!-- Authentication Choice (for guests) -->
              <%= if @is_guest do %>
                <div class="bg-white border border-gray-200 rounded-xl p-8 shadow-sm">
                  <%= if @show_guest_form do %>
                    <!-- Guest Checkout Form -->
                    <div class="text-center mb-8">
                      <h2 class="text-2xl font-bold text-gray-900 mb-2">Complete Your Purchase</h2>
                      <p class="text-gray-600">Enter your information to get your tickets</p>
                    </div>

                    <%= if @errors != [] do %>
                      <div class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
                        <ul class="text-sm text-red-600 space-y-1">
                          <%= for error <- @errors do %>
                            <li><%= error %></li>
                          <% end %>
                        </ul>
                      </div>
                    <% end %>

                    <div class="max-w-md mx-auto space-y-6">
                      <div>
                        <label for="guest_name" class="block text-lg font-medium text-gray-900 mb-3">
                          Full Name <span class="text-red-500">*</span>
                        </label>
                        <input
                          type="text"
                          id="guest_name"
                          value={@guest_form["name"]}
                          phx-keyup="update_guest_form"
                          phx-value-field="name"
                          phx-debounce="300"
                          class="w-full px-4 py-3 text-lg border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors"
                          placeholder="Enter your full name"
                          disabled={@processing}
                        />
                      </div>

                      <div>
                        <label for="guest_email" class="block text-lg font-medium text-gray-900 mb-3">
                          Email Address <span class="text-red-500">*</span>
                        </label>
                        <input
                          type="email"
                          id="guest_email"
                          value={@guest_form["email"]}
                          phx-keyup="update_guest_form"
                          phx-value-field="email"
                          phx-debounce="300"
                          class="w-full px-4 py-3 text-lg border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors"
                          placeholder="Enter your email address"
                          disabled={@processing}
                        />
                      </div>

                      <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                        <p class="text-sm text-blue-800">
                          <svg class="w-5 h-5 inline mr-2" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"></path>
                          </svg>
                          We'll create an account for you and send your tickets to this email address.
                        </p>
                      </div>

                      <button
                        type="button"
                        phx-click="proceed_with_checkout"
                        class="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-medium py-4 px-6 rounded-lg transition-colors duration-200 text-lg"
                        disabled={@processing}
                      >
                        <%= if @processing do %>
                          <div class="flex items-center justify-center">
                            <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                            </svg>
                            Processing...
                          </div>
                        <% else %>
                          <%= if @total_amount == 0 do %>
                            Reserve Free Tickets
                          <% else %>
                            Proceed to Payment
                          <% end %>
                        <% end %>
                      </button>

                      <!-- Alternative Options -->
                      <div class="relative">
                        <div class="absolute inset-0 flex items-center">
                          <div class="w-full border-t border-gray-300"></div>
                        </div>
                        <div class="relative flex justify-center text-sm">
                          <span class="px-2 bg-white text-gray-500">or</span>
                        </div>
                      </div>

                      <div class="space-y-3">
                        <a
                          href="/auth/login"
                          class="w-full border border-gray-300 bg-white hover:bg-gray-50 text-gray-700 font-medium py-3 px-4 rounded-lg transition-colors duration-200 text-center block"
                        >
                          Already have an account? Sign In
                        </a>

                        <a
                          href="/auth/facebook"
                          class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-4 rounded-lg transition-colors duration-200 text-center block flex items-center justify-center"
                        >
                          <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
                          </svg>
                          Continue with Facebook
                        </a>
                      </div>
                    </div>
                  <% else %>
                    <!-- Authentication Options (shown initially) -->
                    <div class="text-center mb-8">
                      <h2 class="text-2xl font-bold text-gray-900 mb-2">How would you like to continue?</h2>
                      <p class="text-gray-600">Choose an option to complete your purchase</p>
                    </div>

                    <div class="max-w-md mx-auto space-y-4">
                      <button
                        type="button"
                        phx-click="show_guest_form"
                        class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-4 px-6 rounded-lg transition-colors duration-200 text-lg"
                      >
                        Continue as Guest
                      </button>

                      <div class="relative">
                        <div class="absolute inset-0 flex items-center">
                          <div class="w-full border-t border-gray-300"></div>
                        </div>
                        <div class="relative flex justify-center text-sm">
                          <span class="px-2 bg-white text-gray-500">or</span>
                        </div>
                      </div>

                      <a
                        href="/auth/login"
                        class="w-full border border-gray-300 bg-white hover:bg-gray-50 text-gray-700 font-medium py-3 px-4 rounded-lg transition-colors duration-200 text-center block"
                      >
                        Sign In to Your Account
                      </a>

                      <a
                        href="/auth/facebook"
                        class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-4 rounded-lg transition-colors duration-200 text-center block flex items-center justify-center"
                      >
                        <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
                        </svg>
                        Continue with Facebook
                      </a>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <!-- Authenticated User - Direct to Payment -->
                <div class="bg-white border border-gray-200 rounded-xl p-8 shadow-sm text-center">
                  <h2 class="text-2xl font-bold text-gray-900 mb-4">Ready to Complete Your Purchase</h2>
                  <p class="text-gray-600 mb-6">Signed in as <%= @user.email %></p>

                  <button
                    type="button"
                    phx-click="proceed_with_checkout"
                    class="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-medium py-4 px-8 rounded-lg transition-colors duration-200 text-lg"
                    disabled={@processing}
                  >
                    <%= if @processing do %>
                      <div class="flex items-center justify-center">
                        <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                        Processing...
                      </div>
                    <% else %>
                      <%= if @total_amount == 0 do %>
                        Reserve Free Tickets
                      <% else %>
                        Proceed to Payment
                      <% end %>
                    <% end %>
                  </button>
                </div>
              <% end %>

              <!-- Order Summary (Detailed) -->
              <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
                <h3 class="text-xl font-semibold text-gray-900 mb-6">Order Details</h3>

                <div class="space-y-4">
                  <%= for item <- @order_items do %>
                    <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg">
                      <div class="flex-1">
                        <h4 class="font-medium text-gray-900"><%= item.ticket.title %></h4>
                        <p class="text-sm text-gray-600"><%= item.ticket.description %></p>

                        <div class="flex items-center gap-4 mt-2">
                          <div class="flex items-center space-x-2">
                            <button
                              type="button"
                              phx-click="update_quantity"
                              phx-value-ticket_id={item.ticket.id}
                              phx-value-quantity={item.quantity - 1}
                              class="w-8 h-8 rounded-full border border-gray-300 flex items-center justify-center text-gray-600 hover:bg-gray-50 disabled:opacity-50"
                              disabled={@processing}
                            >
                              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4"></path>
                              </svg>
                            </button>

                            <span class="w-8 text-center font-medium"><%= item.quantity %></span>

                            <button
                              type="button"
                              phx-click="update_quantity"
                              phx-value-ticket_id={item.ticket.id}
                              phx-value-quantity={item.quantity + 1}
                              class="w-8 h-8 rounded-full border border-gray-300 flex items-center justify-center text-gray-600 hover:bg-gray-50 disabled:opacity-50"
                              disabled={@processing}
                            >
                              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                              </svg>
                            </button>
                          </div>

                          <button
                            type="button"
                            phx-click="remove_ticket"
                            phx-value-ticket_id={item.ticket.id}
                            class="text-red-600 hover:text-red-700 text-sm font-medium"
                            disabled={@processing}
                          >
                            Remove
                          </button>
                        </div>
                      </div>

                      <div class="text-right ml-4">
                        <%= if item.unit_price == 0 do %>
                          <div class="text-lg font-semibold text-green-600">Free</div>
                        <% else %>
                          <div class="text-lg font-semibold text-gray-900">
                            <%= CurrencyHelpers.format_currency(item.total_price, "usd") %>
                          </div>
                          <div class="text-sm text-gray-500">
                            <%= CurrencyHelpers.format_currency(item.unit_price, "usd") %> each
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>

            <!-- Sidebar Summary -->
            <div class="lg:col-span-1">
              <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm sticky top-8">
                <h3 class="text-lg font-semibold text-gray-900 mb-4">Order Summary</h3>

                <div class="space-y-3 mb-6">
                  <%= for item <- @order_items do %>
                    <div class="flex justify-between text-sm">
                      <span class="text-gray-600"><%= item.ticket.title %> × <%= item.quantity %></span>
                      <span class="text-gray-900">
                        <%= if item.total_price == 0 do %>
                          Free
                        <% else %>
                          <%= CurrencyHelpers.format_currency(item.total_price, "usd") %>
                        <% end %>
                      </span>
                    </div>
                  <% end %>
                </div>

                <div class="border-t border-gray-200 pt-4 mb-6">
                  <div class="flex justify-between items-center">
                    <span class="text-lg font-semibold text-gray-900">Total</span>
                    <span class="text-xl font-bold text-gray-900">
                      <%= if @total_amount == 0 do %>
                        Free
                      <% else %>
                        <%= CurrencyHelpers.format_currency(@total_amount, "usd") %>
                      <% end %>
                    </span>
                  </div>
                </div>

                <div class="text-center">
                  <.link navigate={"/events/#{@event.slug}"} class="text-gray-600 hover:text-gray-700 text-sm">
                    ← Back to event
                  </.link>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper function to preserve authentication state during error handling
  defp preserve_auth_state(socket) do
    user = socket.assigns[:user]
    is_guest = is_nil(user)

    socket
    |> assign(:user, user)
    |> assign(:is_guest, is_guest)
    |> assign(:show_guest_form, is_guest)
  end
end
