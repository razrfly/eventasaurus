defmodule EventasaurusWeb.CheckoutLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Ticketing, Events}
  alias EventasaurusWeb.Helpers.CurrencyHelpers

  require Logger

  @impl true
  def mount(%{"slug" => event_slug} = params, _session, socket) do
    # User is already assigned by the auth hook since we're in the :authenticated live_session

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

              {:ok,
               socket
               |> assign(:event, event)
               |> assign(:tickets, tickets)
               |> assign(:selected_tickets, validated_selection)
               |> assign(:order_items, order_items)
               |> assign(:total_amount, total_amount)
               |> assign(:processing, false)
               |> assign(:errors, [])}

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
      total_amount: total_amount
    } = socket.assigns

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

  # Private helper functions

  defp get_event_by_slug(slug) do
    case Events.get_event_by_slug(slug) do
      nil -> {:error, :event_not_found}
      event -> {:ok, event}
    end
  end

  defp parse_tickets_from_params(params) do
    # Parse tickets from URL parameter format: "ticket_id:quantity,ticket_id:quantity"
    case Map.get(params, "tickets") do
      nil -> %{}
      "" -> %{}
      ticket_string ->
        ticket_string
        |> String.split(",")
        |> Enum.reduce(%{}, fn pair, acc ->
          case String.split(pair, ":") do
            [ticket_id_str, quantity_str] ->
              with {ticket_id, ""} <- Integer.parse(ticket_id_str),
                   {quantity, ""} <- Integer.parse(quantity_str),
                   true <- quantity > 0 do
                Map.put(acc, ticket_id, quantity)
              else
                _ -> acc
              end
            _ -> acc
          end
        end)
    end
  end

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
        total_amount = calculate_total_amount(multiple_items)

        # Create a combined order description
        description = multiple_items
        |> Enum.map(fn item -> "#{item.quantity}x #{item.ticket.title}" end)
        |> Enum.join(", ")

        # Use the first ticket's event for organization context
        first_ticket = hd(multiple_items).ticket

        # For multiple items, we'll need to create orders separately but redirect to a combined payment
        create_combined_stripe_checkout(socket, user, multiple_items, total_amount, description, first_ticket)
    end
  end

  defp create_stripe_checkout_session(socket, user, order_item) do
    try do
      case Ticketing.create_order_with_stripe_connect(user, order_item.ticket, %{quantity: order_item.quantity}) do
        {:ok, %{order: order, payment_intent: payment_intent}} ->
          Logger.info("Stripe payment intent created",
            user_id: user.id,
            order_id: order.id,
            payment_intent_id: payment_intent["id"],
            amount: payment_intent["amount"]
          )

          # Redirect to Stripe Checkout or handle client-side payment
          redirect_to_stripe_checkout(socket, order, payment_intent)

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
          Logger.error("Stripe checkout creation failed",
            user_id: user.id,
            ticket_id: order_item.ticket.id,
            reason: reason
          )

          {:noreply,
           socket
           |> assign(:processing, false)
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
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  defp create_combined_stripe_checkout(socket, user, order_items, _total_amount, _description, _first_ticket) do
    # For multiple ticket types, we need to create orders for each ticket type
    # then create a combined payment intent (this is a simplified approach)

    try do
      # Create orders for each ticket type
      order_results = Enum.map(order_items, fn item ->
        Logger.info("Creating order for ticket type",
          user_id: user.id,
          ticket_id: item.ticket.id,
          quantity: item.quantity
        )

        Ticketing.create_order_with_stripe_connect(user, item.ticket, %{quantity: item.quantity})
      end)

      # Check if any order creation failed
      case Enum.find(order_results, fn result -> match?({:error, _}, result) end) do
        nil ->
          # All orders created successfully
          orders_and_intents = Enum.map(order_results, fn {:ok, result} -> result end)
          orders = Enum.map(orders_and_intents, fn %{order: order} -> order end)

          # For now, redirect to the first order's payment intent
          # In production, you might want to create a consolidated payment
          first_result = hd(orders_and_intents)

          Logger.info("Multiple orders created, redirecting to first payment",
            user_id: user.id,
            total_orders: length(orders),
            first_order_id: first_result.order.id
          )

          redirect_to_stripe_checkout(socket, first_result.order, first_result.payment_intent)

        {:error, reason} ->
          Logger.error("Failed to create multiple orders",
            user_id: user.id,
            reason: inspect(reason)
          )

          {:noreply,
           socket
           |> assign(:processing, false)
           |> put_flash(:error, "Unable to process multiple ticket orders. Please try purchasing one ticket type at a time.")}
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
         |> put_flash(:error, "An error occurred. Please try again.")}
    end
  end

  defp redirect_to_stripe_checkout(socket, order, payment_intent) do
    # Redirect to our payment page with Stripe Elements
    query_params = URI.encode_query(%{
      "order_id" => order.id,
      "payment_intent" => payment_intent["id"],
      "client_secret" => payment_intent["client_secret"]
    })
    checkout_url = "/checkout/payment?" <> query_params

    {:noreply,
     socket
     |> assign(:processing, false)
     |> redirect(to: checkout_url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-6 py-8 max-w-4xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 mb-2">Checkout</h1>
        <p class="text-gray-600">Review your ticket selection for <span class="font-medium"><%= @event.title %></span></p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <!-- Order Summary -->
        <div class="lg:col-span-2">
          <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
            <h2 class="text-xl font-semibold text-gray-900 mb-6">Order Summary</h2>

            <%= if @order_items == [] do %>
              <div class="text-center py-8">
                <p class="text-gray-500">No tickets selected</p>
                <.link navigate={"/events/#{@event.slug}"} class="text-blue-600 hover:text-blue-700 font-medium">
                  ← Back to event
                </.link>
              </div>
            <% else %>
              <div class="space-y-4">
                <%= for item <- @order_items do %>
                  <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg">
                    <div class="flex-1">
                      <h3 class="font-medium text-gray-900"><%= item.ticket.title %></h3>
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
            <% end %>
          </div>
        </div>

        <!-- Payment Summary -->
        <div class="lg:col-span-1">
          <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm sticky top-8">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Payment Summary</h3>

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

            <%= if @order_items != [] do %>
              <button
                type="button"
                phx-click="proceed_with_checkout"
                class="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 text-white font-medium py-3 px-4 rounded-lg transition-colors duration-200"
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
            <% end %>

            <div class="mt-4 text-center">
              <.link navigate={"/events/#{@event.slug}"} class="text-gray-600 hover:text-gray-700 text-sm">
                ← Back to event
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
