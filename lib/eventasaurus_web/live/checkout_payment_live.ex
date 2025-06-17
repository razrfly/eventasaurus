defmodule EventasaurusWeb.CheckoutPaymentLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Ticketing, Events}
  alias EventasaurusWeb.Helpers.CurrencyHelpers

  require Logger

  @impl true
  def mount(%{"order_id" => order_id} = params, _session, socket) do
    # User is already assigned by the auth hook

    case get_order_for_user(order_id, socket.assigns.user.id) do
      {:ok, order} ->
        payment_intent_id = Map.get(params, "payment_intent")
        client_secret = Map.get(params, "client_secret")

        if payment_intent_id && client_secret do
          event = Events.get_event!(order.ticket.event_id)

          {:ok,
           socket
           |> assign(:order, order)
           |> assign(:event, event)
           |> assign(:payment_intent_id, payment_intent_id)
           |> assign(:client_secret, client_secret)
           |> assign(:processing, false)
           |> assign(:payment_status, :pending)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Invalid payment session.")
           |> redirect(to: "/")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Order not found.")
         |> redirect(to: "/")}

      {:error, :unauthorized} ->
        {:ok,
         socket
         |> put_flash(:error, "You can only view your own orders.")
         |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_event("payment_succeeded", %{"payment_intent_id" => payment_intent_id}, socket) do
    Logger.info("Payment succeeded event received",
      user_id: socket.assigns.user.id,
      order_id: socket.assigns.order.id,
      payment_intent_id: payment_intent_id
    )

    case Ticketing.confirm_order(socket.assigns.order, payment_intent_id) do
      {:ok, confirmed_order} ->
        Logger.info("Order confirmed after payment success",
          user_id: socket.assigns.user.id,
          order_id: confirmed_order.id
        )

        {:noreply,
         socket
         |> assign(:payment_status, :succeeded)
         |> assign(:order, confirmed_order)
         |> put_flash(:success, "Payment successful! Your tickets have been confirmed.")
         |> redirect(to: "/events/#{socket.assigns.event.slug}")}

      {:error, reason} ->
        Logger.error("Failed to confirm order after payment",
          user_id: socket.assigns.user.id,
          order_id: socket.assigns.order.id,
          reason: inspect(reason)
        )

        {:noreply,
         socket
         |> assign(:payment_status, :error)
         |> put_flash(:error, "Payment was successful but there was an issue confirming your order. Please contact support.")}
    end
  end

  @impl true
  def handle_event("payment_failed", %{"error" => error}, socket) do
    Logger.warning("Payment failed",
      user_id: socket.assigns.user.id,
      order_id: socket.assigns.order.id,
      error: inspect(error)
    )

    {:noreply,
     socket
     |> assign(:payment_status, :failed)
     |> put_flash(:error, "Payment failed: #{Map.get(error, "message", "Unknown error")}")}
  end

  @impl true
  def handle_event("retry_payment", _params, socket) do
    {:noreply,
     socket
     |> assign(:payment_status, :pending)
     |> clear_flash()}
  end

  # Private helper functions

  defp get_order_for_user(order_id, user_id) do
    try do
      order_id = String.to_integer(order_id)

      case Ticketing.get_user_order(user_id, order_id) do
        nil -> {:error, :not_found}
        order ->
          if order.user_id == user_id do
            {:ok, order}
          else
            {:error, :unauthorized}
          end
      end
    rescue
      ArgumentError -> {:error, :not_found}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-6 py-8 max-w-2xl">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 mb-2">Complete Payment</h1>
        <p class="text-gray-600">Secure payment for <span class="font-medium"><%= @event.title %></span></p>
      </div>

      <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm mb-6">
        <h2 class="text-xl font-semibold text-gray-900 mb-4">Order Summary</h2>

        <div class="flex justify-between items-center p-4 border border-gray-200 rounded-lg mb-4">
          <div>
            <h3 class="font-medium text-gray-900"><%= @order.ticket.title %></h3>
            <p class="text-sm text-gray-600">Quantity: <%= @order.quantity %></p>
          </div>
          <div class="text-right">
            <div class="text-lg font-semibold text-gray-900">
              <%= CurrencyHelpers.format_currency(@order.total_cents, @order.currency) %>
            </div>
          </div>
        </div>
      </div>

      <%= if @payment_status == :pending do %>
        <div class="bg-white border border-gray-200 rounded-xl p-6 shadow-sm">
          <h3 class="text-lg font-semibold text-gray-900 mb-4">Payment Information</h3>

          <!-- Stripe Elements will be mounted here -->
          <div id="stripe-payment-element" class="mb-4"></div>

          <button
            id="stripe-submit-button"
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
              Pay <%= CurrencyHelpers.format_currency(@order.total_cents, @order.currency) %>
            <% end %>
          </button>
        </div>
      <% end %>

      <%= if @payment_status == :failed do %>
        <div class="bg-red-50 border border-red-200 rounded-xl p-6">
          <div class="flex items-center mb-4">
            <svg class="w-6 h-6 text-red-600 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
            </svg>
            <h3 class="text-lg font-semibold text-red-900">Payment Failed</h3>
          </div>
          <p class="text-red-700 mb-4">Your payment could not be processed.</p>
          <button
            phx-click="retry_payment"
            class="bg-red-600 hover:bg-red-700 text-white font-medium py-2 px-4 rounded-lg transition-colors duration-200"
          >
            Try Again
          </button>
        </div>
      <% end %>

      <div class="mt-6 text-center">
        <.link navigate={"/events/#{@event.slug}/checkout?tickets=#{@order.ticket.id}:#{@order.quantity}"}
              class="text-gray-600 hover:text-gray-700 text-sm">
          ← Back to checkout
        </.link>
      </div>
    </div>

    <script src="https://js.stripe.com/v3/"></script>
    <script>
      window.addEventListener('DOMContentLoaded', function() {
        if (typeof Stripe === 'undefined') {
          console.error('Stripe.js failed to load');
          return;
        }

        const stripe = Stripe('<%= Application.get_env(:eventasaurus, :stripe)[:publishable_key] %>');
        const elements = stripe.elements({
          clientSecret: '<%= @client_secret %>'
        });

        const paymentElement = elements.create('payment');
        paymentElement.mount('#stripe-payment-element');

        const submitButton = document.getElementById('stripe-submit-button');

        submitButton.addEventListener('click', async (event) => {
          event.preventDefault();

          submitButton.disabled = true;
          submitButton.innerHTML = `
            <div class="flex items-center justify-center">
              <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Processing...
            </div>
          `;

          const { error } = await stripe.confirmPayment({
            elements,
            confirmParams: {
              return_url: window.location.href
            },
            redirect: 'if_required'
          });

          if (error) {
            // Payment failed
            window.liveSocket.pushEvent('#stripe-submit-button', 'payment_failed', { error: error });

            submitButton.disabled = false;
            submitButton.innerHTML = 'Pay <%= CurrencyHelpers.format_currency(@order.total_cents, @order.currency) %>';
          } else {
            // Payment succeeded
            window.liveSocket.pushEvent('#stripe-submit-button', 'payment_succeeded', {
              payment_intent_id: '<%= @payment_intent_id %>'
            });
          }
        });
      });
    </script>
    """
  end
end
