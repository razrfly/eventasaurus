defmodule EventasaurusApp.Ticketing do
  @moduledoc """
  The Ticketing context.

  This context handles all ticketing-related operations including:
  - Ticket management (creation, updates, availability)
  - Order processing (creation, confirmation, cancellation)
  - Integration with EventParticipant system
  - Real-time updates via PubSub
  """

  import Ecto.Query, warn: false
  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Events.{Event, Ticket, Order}
  alias EventasaurusApp.Accounts.User

  # PubSub topic for real-time updates
  @pubsub_topic "ticketing_updates"

  ## Ticket Management

  @doc """
  Returns the list of tickets for an event.

  ## Examples

      iex> list_tickets_for_event(event_id)
      [%Ticket{}, ...]

  """
  def list_tickets_for_event(event_id) do
    Ticket
    |> where([t], t.event_id == ^event_id)
    |> order_by([t], t.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single ticket.

  Raises `Ecto.NoResultsError` if the Ticket does not exist.

  ## Examples

      iex> get_ticket!(123)
      %Ticket{}

      iex> get_ticket!(456)
      ** (Ecto.NoResultsError)

  """
  def get_ticket!(id), do: Repo.get!(Ticket, id)

  @doc """
  Gets a single ticket with preloaded associations.

  ## Examples

      iex> get_ticket_with_event!(123)
      %Ticket{event: %Event{}}

  """
  def get_ticket_with_event!(id) do
    Ticket
    |> preload([:event])
    |> Repo.get!(id)
  end

  @doc """
  Creates a ticket for an event.

  ## Examples

      iex> create_ticket(event, %{title: "General Admission", base_price_cents: 2500})
      {:ok, %Ticket{}}

      iex> create_ticket(event, %{title: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_ticket(%Event{} = event, attrs \\ %{}) do
    %Ticket{}
    |> Ticket.changeset(Map.put(attrs, :event_id, event.id))
    |> Repo.insert()
    |> case do
      {:ok, ticket} ->
        maybe_broadcast_ticket_update(ticket, :created)
        {:ok, ticket}
      error ->
        error
    end
  end

  @doc """
  Updates a ticket.

  ## Examples

      iex> update_ticket(ticket, %{title: "VIP Access"})
      {:ok, %Ticket{}}

      iex> update_ticket(ticket, %{title: ""})
      {:error, %Ecto.Changeset{}}

  """
  def update_ticket(%Ticket{} = ticket, attrs) do
    ticket
    |> Ticket.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_ticket} ->
        maybe_broadcast_ticket_update(updated_ticket, :updated)
        {:ok, updated_ticket}
      error ->
        error
    end
  end

  @doc """
  Deletes a ticket.

  ## Examples

      iex> delete_ticket(ticket)
      {:ok, %Ticket{}}

      iex> delete_ticket(ticket)
      {:error, %Ecto.Changeset{}}

  """
  def delete_ticket(%Ticket{} = ticket) do
    Repo.delete(ticket)
    |> case do
      {:ok, deleted_ticket} ->
        maybe_broadcast_ticket_update(deleted_ticket, :deleted)
        {:ok, deleted_ticket}
      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ticket changes.

  ## Examples

      iex> change_ticket(ticket)
      %Ecto.Changeset{data: %Ticket{}}

  """
  def change_ticket(%Ticket{} = ticket, attrs \\ %{}) do
    Ticket.changeset(ticket, attrs)
  end

  @doc """
  Checks if a ticket is available for purchase.

  ## Examples

      iex> ticket_available?(ticket, 2)
      true

      iex> ticket_available?(ticket, 200)
      false

  """
  def ticket_available?(%Ticket{} = ticket, quantity \\ 1) do
    cond do
      not Ticket.on_sale?(ticket) -> false
      quantity <= 0 -> false
      quantity > available_quantity(ticket) -> false
      true -> true
    end
  end

  @doc """
  Returns the number of tickets available for purchase.

  ## Examples

      iex> available_quantity(ticket)
      45

  """
  def available_quantity(%Ticket{} = ticket) do
    sold_count = count_sold_tickets(ticket.id)
    max(0, ticket.quantity - sold_count)
  end

  @doc """
  Counts the number of sold tickets for a given ticket type.

  ## Examples

      iex> count_sold_tickets(ticket_id)
      55

  """
  def count_sold_tickets(ticket_id) do
    # Only count confirmed orders and pending orders created within the last hour
    # This prevents abandoned checkouts from blocking inventory indefinitely
    one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)

    Order
    |> where([o], o.ticket_id == ^ticket_id)
    |> where([o],
      o.status == "confirmed" or
      (o.status == "pending" and o.inserted_at > ^one_hour_ago)
    )
    |> select([o], sum(o.quantity))
    |> Repo.one()
    |> case do
      nil -> 0
      count -> count
    end
  end

  ## Order Management

  @doc """
  Returns the list of orders for a user.

  ## Examples

      iex> list_orders_for_user(user_id)
      [%Order{}, ...]

  """
  def list_orders_for_user(user_id) do
    Order
    |> where([o], o.user_id == ^user_id)
    |> order_by([o], desc: o.inserted_at)
    |> preload([:event, :ticket])
    |> Repo.all()
  end

  @doc """
  Returns the list of orders for an event.

  ## Examples

      iex> list_orders_for_event(event_id)
      [%Order{}, ...]

  """
  def list_orders_for_event(event_id) do
    Order
    |> where([o], o.event_id == ^event_id)
    |> order_by([o], desc: o.inserted_at)
    |> preload([:user, :ticket])
    |> Repo.all()
  end

  @doc """
  Gets a single order.

  Raises `Ecto.NoResultsError` if the Order does not exist.

  ## Examples

      iex> get_order!(123)
      %Order{}

      iex> get_order!(456)
      ** (Ecto.NoResultsError)

  """
  def get_order!(id), do: Repo.get!(Order, id)

  @doc """
  Gets a single order with preloaded associations.

  ## Examples

      iex> get_order_with_associations!(123)
      %Order{user: %User{}, event: %Event{}, ticket: %Ticket{}}

  """
  def get_order_with_associations!(id) do
    Order
    |> preload([:user, :event, :ticket])
    |> Repo.get!(id)
  end

  @doc """
  Gets an order by user and order ID for security.

  ## Examples

      iex> get_user_order!(user_id, order_id)
      %Order{}

      iex> get_user_order!(user_id, other_user_order_id)
      ** (Ecto.NoResultsError)

  """
  def get_user_order!(user_id, order_id) do
    Order
    |> where([o], o.user_id == ^user_id and o.id == ^order_id)
    |> preload([:event, :ticket])
    |> Repo.one!()
  end

  @doc """
  Gets a user's order by payment intent ID.

  ## Examples

      iex> get_user_order_by_payment_intent(user_id, "pi_123")
      %Order{}

  """
  def get_user_order_by_payment_intent(user_id, payment_intent_id) do
    Order
    |> where([o], o.user_id == ^user_id and o.stripe_session_id == ^payment_intent_id)
    |> preload([:ticket, :event, :user])
    |> Repo.one()
  end

  @doc """
  Gets a user's order by ID.

  ## Examples

      iex> get_user_order(user_id, order_id)
      %Order{}

      iex> get_user_order(user_id, invalid_id)
      nil

  """
  def get_user_order(user_id, order_id) do
    Order
    |> where([o], o.user_id == ^user_id and o.id == ^order_id)
    |> preload([:ticket, :event, :user])
    |> Repo.one()
  end

  @doc """
  Lists orders for a user with optional filtering and pagination.

  ## Examples

      iex> list_user_orders(user_id, nil, 10, 0)
      [%Order{}, ...]

      iex> list_user_orders(user_id, "completed", 5, 10)
      [%Order{}, ...]

  """
  def list_user_orders(user_id, status_filter \\ nil, limit \\ 20, offset \\ 0) do
    query =
      Order
      |> where([o], o.user_id == ^user_id)
      |> preload([:ticket, :event])
      |> order_by([o], desc: o.inserted_at)
      |> limit(^limit)
      |> offset(^offset)

    query =
      if status_filter do
        where(query, [o], o.status == ^status_filter)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Creates an order for a ticket purchase.

  This function handles the complete order creation process:
  1. Validates ticket availability
  2. Calculates pricing (subtotal, tax, total) with flexible pricing support
  3. Creates the order record with pricing snapshot
  4. Broadcasts real-time updates

  ## Examples

      iex> create_order(user, ticket, %{quantity: 2})
      {:ok, %Order{}}

      iex> create_order(user, ticket, %{quantity: 1, custom_price_cents: 2000, tip_cents: 500})
      {:ok, %Order{}}

      iex> create_order(user, unavailable_ticket, %{quantity: 1})
      {:error, :ticket_unavailable}

  """
  def create_order(%User{} = user, %Ticket{} = ticket, attrs \\ %{}) do
    quantity = Map.get(attrs, :quantity, 1)
    custom_price_cents = Map.get(attrs, :custom_price_cents)
    tip_cents = Map.get(attrs, :tip_cents, 0)

    # Use transaction with row locking to prevent overselling
    case Repo.transaction(fn ->
      # Lock the ticket row to prevent concurrent modifications
      locked_ticket = Repo.get!(Ticket, ticket.id, lock: "FOR UPDATE")

      with :ok <- validate_ticket_availability(locked_ticket, quantity),
           :ok <- validate_flexible_pricing(locked_ticket, custom_price_cents),
           {:ok, pricing} <- calculate_order_pricing(locked_ticket, quantity, custom_price_cents, tip_cents),
           {:ok, order} <- insert_order(user, locked_ticket, quantity, pricing, attrs) do
        # Return both order and ticket for post-commit broadcasting
        {order, locked_ticket}
      else
        {:error, reason} -> Repo.rollback(reason)
        error -> Repo.rollback(error)
      end
    end) do
      {:ok, {order, ticket}} ->
        # Broadcast after transaction commits to ensure data visibility
        maybe_broadcast_order_update(order, :created)
        maybe_broadcast_ticket_update(ticket, :order_created)
        {:ok, order}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates an order with Stripe Connect payment intent.

  This function:
  1. Creates a pending order
  2. Finds the event organizer's Stripe Connect account
  3. Creates a Stripe Payment Intent with application fees
  4. Associates the payment intent with the order

  ## Examples

      iex> create_order_with_stripe_connect(user, ticket, %{quantity: 2})
      {:ok, %{order: %Order{}, payment_intent: %{}}}

  """
  def create_order_with_stripe_connect(%User{} = user, %Ticket{} = ticket, attrs \\ %{}) do
    quantity = Map.get(attrs, :quantity, 1)
    custom_price_cents = Map.get(attrs, :custom_price_cents)
    tip_cents = Map.get(attrs, :tip_cents, 0)

    # Use transaction with row locking to prevent overselling
    case Repo.transaction(fn ->
      # Lock the ticket row to prevent concurrent modifications
      locked_ticket = Repo.get!(Ticket, ticket.id, lock: "FOR UPDATE")

      with :ok <- validate_ticket_availability(locked_ticket, quantity),
           :ok <- validate_flexible_pricing(locked_ticket, custom_price_cents),
           {:ok, pricing} <- calculate_order_pricing(locked_ticket, quantity, custom_price_cents, tip_cents),
           {:ok, connect_account} <- get_event_organizer_stripe_account(locked_ticket.event_id),
           {:ok, order} <- insert_order_with_stripe_connect(user, locked_ticket, quantity, pricing, connect_account, attrs),
           {:ok, payment_intent} <- create_stripe_payment_intent(order, connect_account) do

        # Update order with payment intent ID
        {:ok, updated_order} =
          order
          |> Order.changeset(%{stripe_session_id: payment_intent["id"]})
          |> Repo.update()

        # Return order, ticket, and payment intent for post-commit broadcasting
        {updated_order, locked_ticket, payment_intent}
      else
        {:error, reason} -> Repo.rollback(reason)
        error -> Repo.rollback(error)
      end
    end) do
      {:ok, {order, ticket, payment_intent}} ->
        # Broadcast after transaction commits to ensure data visibility
        maybe_broadcast_order_update(order, :created)
        maybe_broadcast_ticket_update(ticket, :order_created)
        {:ok, %{order: order, payment_intent: payment_intent}}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Confirms an order after successful payment.

  This function:
  1. Updates order status to "confirmed"
  2. Sets confirmed_at timestamp
  3. Creates EventParticipant record for ticket holder
  4. Broadcasts updates

  ## Examples

      iex> confirm_order(order, "pi_stripe_payment_intent")
      {:ok, %Order{}}

  """
  def confirm_order(%Order{} = order, payment_reference) do
    case Repo.transaction(fn ->
      # Preload ticket for broadcasting
      order_with_ticket = Repo.preload(order, :ticket)

      # Update order
      {:ok, confirmed_order} =
        order
        |> Order.changeset(%{
          status: "confirmed",
          payment_reference: payment_reference,
          confirmed_at: DateTime.utc_now()
        })
        |> Repo.update()

      # Create EventParticipant record
      {:ok, _participant} = create_event_participant(confirmed_order)

      # Return order and ticket for post-commit broadcasting
      {confirmed_order, order_with_ticket.ticket}
    end) do
      {:ok, {confirmed_order, ticket}} ->
        # Broadcast updates after transaction commits
        maybe_broadcast_order_update(confirmed_order, :confirmed)
        maybe_broadcast_ticket_update(ticket, :order_confirmed)
        {:ok, confirmed_order}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Cancels an order.

  ## Examples

      iex> cancel_order(order)
      {:ok, %Order{}}

  """
  def cancel_order(%Order{} = order) do
    if Order.can_cancel?(order) do
      # Preload ticket for broadcasting
      order_with_ticket = Repo.preload(order, :ticket)

      order
      |> Order.changeset(%{status: "canceled"})
      |> Repo.update()
      |> case do
        {:ok, canceled_order} ->
          maybe_broadcast_order_update(canceled_order, :canceled)
          maybe_broadcast_ticket_update(order_with_ticket.ticket, :order_canceled)
          {:ok, canceled_order}
        error ->
          error
      end
    else
      {:error, :cannot_cancel}
    end
  end

  @doc """
  Marks an order as failed due to payment failure.

  ## Examples

      iex> mark_order_failed(order)
      {:ok, %Order{}}

  """
  def mark_order_failed(%Order{} = order) do
    # Preload ticket for broadcasting
    order_with_ticket = Repo.preload(order, :ticket)

    order
    |> Order.changeset(%{status: "failed"})
    |> Repo.update()
    |> case do
      {:ok, failed_order} ->
        maybe_broadcast_order_update(failed_order, :failed)
        maybe_broadcast_ticket_update(order_with_ticket.ticket, :order_failed)
        {:ok, failed_order}
      error ->
        error
    end
  end

  @doc """
  Refunds an order.

  ## Examples

      iex> refund_order(order)
      {:ok, %Order{}}

  """
  def refund_order(%Order{} = order) do
    if Order.can_refund?(order) do
      order
      |> Order.changeset(%{status: "refunded"})
      |> Repo.update()
      |> case do
        {:ok, refunded_order} ->
          maybe_broadcast_order_update(refunded_order, :refunded)
          {:ok, refunded_order}
        error ->
          error
      end
    else
      {:error, :cannot_refund}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking order changes.

  ## Examples

      iex> change_order(order)
      %Ecto.Changeset{data: %Order{}}

  """
  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  @doc """
  Gets an order by its Stripe Payment Intent ID.

  ## Examples

      iex> get_order_by_payment_intent("pi_1234567890")
      %Order{}

      iex> get_order_by_payment_intent("nonexistent")
      nil

  """
  def get_order_by_payment_intent(payment_intent_id) do
    Order
    |> where([o], o.payment_reference == ^payment_intent_id)
    |> Repo.one()
  end

  @doc """
  Gets an order by Stripe session ID.

  ## Examples

      iex> get_order_by_session_id("cs_1234567890")
      %Order{}

      iex> get_order_by_session_id("nonexistent")
      nil

  """
  def get_order_by_session_id(session_id) do
    Order
    |> where([o], o.stripe_session_id == ^session_id)
    |> Repo.one()
  end

  @doc """
  Syncs order status with Stripe's current state.

  This is the single source of truth for order status - following t3dotgg pattern.
  Only confirms orders when Stripe says they're paid.

  ## Examples

      iex> sync_order_with_stripe(order)
      {:ok, %Order{}}

  """
  def sync_order_with_stripe(%Order{} = order) do
    cond do
      # If already confirmed, no need to sync
      order.status == "confirmed" ->
        {:ok, order}

      # If we have a payment intent, check its status
      order.payment_reference ->
        sync_order_via_payment_intent(order)

      # If we have a session ID, check the session
      order.stripe_session_id ->
        sync_order_via_checkout_session(order)

      # No Stripe reference, can't sync
      true ->
        {:ok, order}
    end
  end

  @doc """
  Confirms an order without requiring a payment reference (for webhook processing).

  ## Examples

      iex> confirm_order(order)
      {:ok, %Order{}}

  """
  def confirm_order(%Order{} = order) do
    Repo.transaction(fn ->
      # Update order
      {:ok, confirmed_order} =
        order
        |> Order.changeset(%{
          status: "confirmed",
          confirmed_at: DateTime.utc_now()
        })
        |> Repo.update()

      # Create EventParticipant record
      {:ok, _participant} = create_event_participant(confirmed_order)

      # Broadcast updates
      maybe_broadcast_order_update(confirmed_order, :confirmed)

      confirmed_order
    end)
  end

  defp sync_order_via_payment_intent(%Order{} = order) do
    case stripe_impl().get_payment_intent(order.payment_reference, nil) do
      {:ok, %{"status" => "succeeded"}} ->
        confirm_order(order)

      {:ok, %{"status" => status}} ->
        Logger.info("Payment intent not succeeded, keeping order pending",
          order_id: order.id,
          payment_intent_id: order.payment_reference,
          status: status
        )
        {:ok, order}

      {:error, reason} ->
        Logger.error("Failed to fetch payment intent from Stripe",
          order_id: order.id,
          payment_intent_id: order.payment_reference,
          reason: inspect(reason)
        )
        {:ok, order}  # Don't fail the order, just keep it pending
    end
  end

  defp sync_order_via_checkout_session(%Order{} = order) do
    case stripe_impl().get_checkout_session(order.stripe_session_id) do
      {:ok, %{"payment_status" => "paid"}} ->
        confirm_order(order)

      {:ok, %{"payment_status" => status}} ->
        Logger.info("Checkout session not paid, keeping order pending",
          order_id: order.id,
          session_id: order.stripe_session_id,
          payment_status: status
        )
        {:ok, order}

      {:error, reason} ->
        Logger.error("Failed to fetch checkout session from Stripe",
          order_id: order.id,
          session_id: order.stripe_session_id,
          reason: inspect(reason)
        )
        {:ok, order}  # Don't fail the order, just keep it pending
    end
  end

  ## Private Helper Functions

  defp get_event_organizer_stripe_account(event_id) do
    # Get the event with its organizer
    event =
      EventasaurusApp.Events.get_event!(event_id)
      |> Repo.preload(:users)

    # Find the event organizer (assuming the first user is the organizer)
    # In a more complex system, you might have a specific organizer field
    case event.users do
      [organizer | _] ->
        case EventasaurusApp.Stripe.get_connect_account(organizer.id) do
          nil -> {:error, :no_stripe_account}
          connect_account -> {:ok, connect_account}
        end
      [] ->
        {:error, :no_organizer}
    end
  end

  defp insert_order_with_stripe_connect(%User{} = user, %Ticket{} = ticket, quantity, pricing, connect_account, attrs) do
    # Calculate platform fee (5% of total)
    application_fee_amount = EventasaurusApp.Events.Order.calculate_platform_fee(pricing.total_cents)

    order_attrs = Map.merge(attrs, %{
      user_id: user.id,
      event_id: ticket.event_id,
      ticket_id: ticket.id,
      quantity: quantity,
      subtotal_cents: pricing.subtotal_cents,
      tax_cents: pricing.tax_cents,
      total_cents: pricing.total_cents,
      currency: pricing.currency,
      status: "pending",
      stripe_connect_account_id: connect_account.id,
      application_fee_amount: application_fee_amount,
      pricing_snapshot: pricing.pricing_snapshot
    })

    %Order{}
    |> Order.changeset(order_attrs)
    |> Repo.insert()
  end

  defp create_stripe_payment_intent(%Order{} = order, connect_account) do
    metadata = %{
      "order_id" => to_string(order.id),
      "event_id" => to_string(order.event_id),
      "ticket_id" => to_string(order.ticket_id),
      "user_id" => to_string(order.user_id),
      "quantity" => to_string(order.quantity)
    }

    EventasaurusApp.Stripe.create_payment_intent(
      order.total_cents,
      order.currency,
      connect_account,
      order.application_fee_amount,
      metadata
    )
  end

  @doc """
  Creates a Stripe Checkout Session with dynamic pricing support.

  This function handles the complete checkout session creation process:
  1. Validates ticket availability
  2. Calculates pricing with flexible pricing support
  3. Creates the order record
  4. Creates a Stripe checkout session with appropriate pricing
  5. Returns checkout URL for redirect

  ## Examples

      iex> create_checkout_session(user, ticket, %{quantity: 2, custom_price_cents: 2000})
      {:ok, %{order: order, checkout_url: url}}

      iex> create_checkout_session(user, ticket, %{pricing_model: "flexible", custom_price_cents: 1500})
      {:ok, %{order: order, checkout_url: url}}

  """
  def create_checkout_session(%User{} = user, %Ticket{} = ticket, attrs \\ %{}) do
    quantity = Map.get(attrs, :quantity, 1)
    custom_price_cents = Map.get(attrs, :custom_price_cents)
    tip_cents = Map.get(attrs, :tip_cents, 0)

    # Use transaction with row locking to prevent overselling
    case Repo.transaction(fn ->
      # Lock the ticket row to prevent concurrent modifications
      locked_ticket = Repo.get!(Ticket, ticket.id, lock: "FOR UPDATE")

      with :ok <- validate_ticket_availability(locked_ticket, quantity),
           :ok <- validate_flexible_pricing(locked_ticket, custom_price_cents),
           {:ok, pricing} <- calculate_order_pricing(locked_ticket, quantity, custom_price_cents, tip_cents),
           {:ok, connect_account} <- get_event_organizer_stripe_account(locked_ticket.event_id),
           {:ok, order} <- insert_order_with_checkout_session(user, locked_ticket, quantity, pricing, connect_account, attrs),
           {:ok, checkout_session} <- create_stripe_checkout_session(order, locked_ticket, connect_account) do

        # Update order with checkout session ID
        {:ok, updated_order} =
          order
          |> Order.changeset(%{stripe_session_id: checkout_session["id"]})
          |> Repo.update()

        maybe_broadcast_order_update(updated_order, :created)

        {:ok, %{
          order: updated_order,
          checkout_url: checkout_session["url"],
          session_id: checkout_session["id"]
        }}
      else
        error ->
          # Force transaction rollback by calling Repo.rollback
          case error do
            {:error, reason} -> Repo.rollback(reason)
            atom when is_atom(atom) -> Repo.rollback(atom)
            other -> Repo.rollback(other)
          end
      end
    end) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_order_with_checkout_session(%User{} = user, %Ticket{} = ticket, quantity, pricing, connect_account, attrs) do
    # Calculate platform fee (5% of total)
    application_fee_amount = Order.calculate_platform_fee(pricing.total_cents)

    order_attrs = Map.merge(attrs, %{
      user_id: user.id,
      event_id: ticket.event_id,
      ticket_id: ticket.id,
      quantity: quantity,
      subtotal_cents: pricing.subtotal_cents,
      tax_cents: pricing.tax_cents,
      total_cents: pricing.total_cents,
      currency: pricing.currency,
      status: "pending",
      stripe_connect_account_id: connect_account.id,
      application_fee_amount: application_fee_amount,
      pricing_snapshot: pricing.pricing_snapshot
    })

    %Order{}
    |> Order.changeset(order_attrs)
    |> Repo.insert()
  end

  defp create_stripe_checkout_session(%Order{} = order, %Ticket{} = ticket, connect_account) do
    # Get pricing details from snapshot
    pricing_snapshot = order.pricing_snapshot || %{}
    pricing_model = Map.get(pricing_snapshot, "pricing_model", "fixed")

    # Get ticket info for session
    ticket = Repo.preload(ticket, :event)

    # Generate idempotency key
    idempotency_key = "order_#{order.id}_#{DateTime.utc_now() |> DateTime.to_unix()}"

    # Build URLs
    base_url = get_base_url()
    success_url = "#{base_url}/orders/#{order.id}/success?session_id={CHECKOUT_SESSION_ID}"
    cancel_url = "#{base_url}/events/#{ticket.event.slug}/tickets"

    metadata = %{
      "order_id" => to_string(order.id),
      "user_id" => to_string(order.user_id),
      "event_id" => to_string(order.event_id),
      "ticket_id" => to_string(order.ticket_id),
      "pricing_model" => pricing_model
    }

    checkout_params = %{
      amount_cents: order.total_cents,
      currency: order.currency,
      connect_account: connect_account,
      application_fee_amount: order.application_fee_amount,
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: metadata,
      idempotency_key: idempotency_key,
      pricing_model: pricing_model,
      allow_promotion_codes: false,
      quantity: order.quantity,
      ticket_name: ticket.title,
      ticket_description: "#{ticket.event.title} - #{ticket.title}"
    }

    # Add minimum price for flexible pricing
    checkout_params = if pricing_model == "flexible" do
      Map.put(checkout_params, :minimum_price_cents, Map.get(pricing_snapshot, "minimum_price_cents"))
    else
      checkout_params
    end

    stripe_impl().create_checkout_session(checkout_params)
  end

  defp get_base_url do
    # Get base URL from application config or environment
    case Application.get_env(:eventasaurus_app, EventasaurusAppWeb.Endpoint)[:url] do
      nil -> "http://localhost:4000"  # Development fallback
      url_config ->
        scheme = if url_config[:scheme] == "https", do: "https", else: "http"
        host = url_config[:host] || "localhost"
        port = url_config[:port]

        if port && port != 80 && port != 443 do
          "#{scheme}://#{host}:#{port}"
        else
          "#{scheme}://#{host}"
        end
    end
  end

  defp validate_ticket_availability(%Ticket{} = ticket, quantity) do
    if ticket_available?(ticket, quantity) do
      :ok
    else
      {:error, :ticket_unavailable}
    end
  end

  defp validate_flexible_pricing(%Ticket{} = ticket, custom_price_cents) do
    case {ticket.pricing_model, custom_price_cents} do
      {"flexible", custom_price} when is_integer(custom_price) ->
        if custom_price >= ticket.minimum_price_cents do
          :ok
        else
          {:error, :price_below_minimum}
        end
      {"flexible", nil} ->
        {:error, :custom_price_required}
      {_other_model, _} ->
        :ok
    end
  end

  defp calculate_order_pricing(%Ticket{} = ticket, quantity, custom_price_cents, tip_cents) do
    # Determine effective price per ticket
    price_per_ticket = case ticket.pricing_model do
      "flexible" when is_integer(custom_price_cents) -> custom_price_cents
      _ -> ticket.base_price_cents
    end

    # Calculate base amounts
    base_subtotal_cents = price_per_ticket * quantity
    tip_total_cents = tip_cents * quantity
    subtotal_cents = base_subtotal_cents + tip_total_cents

    tax_cents = calculate_tax(base_subtotal_cents) # Tax only on ticket price, not tips
    total_cents = subtotal_cents + tax_cents

    {:ok, %{
      subtotal_cents: subtotal_cents,
      tax_cents: tax_cents,
      total_cents: total_cents,
      currency: ticket.currency,
      pricing_snapshot: Order.create_pricing_snapshot(ticket, custom_price_cents, tip_cents)
    }}
  end

  defp calculate_tax(subtotal_cents) do
    # Simple tax calculation - 10% for now
    # In a real app, this would be more sophisticated based on location, etc.
    round(subtotal_cents * 0.10)
  end

  defp insert_order(%User{} = user, %Ticket{} = ticket, quantity, pricing, attrs) do
    order_attrs = Map.merge(attrs, %{
      user_id: user.id,
      event_id: ticket.event_id,
      ticket_id: ticket.id,
      quantity: quantity,
      subtotal_cents: pricing.subtotal_cents,
      tax_cents: pricing.tax_cents,
      total_cents: pricing.total_cents,
      currency: pricing.currency,
      status: "pending",
      pricing_snapshot: pricing.pricing_snapshot
    })

    %Order{}
    |> Order.changeset(order_attrs)
    |> Repo.insert()
  end

  defp create_event_participant(%Order{} = order) do
    # Load the order with associations if needed
    order = Repo.preload(order, [:user, :event])

    EventasaurusApp.Events.create_or_upgrade_participant_for_order(%{
      event_id: order.event_id,
      user_id: order.user_id,
      source: "ticket_purchase",
      metadata: %{
        order_id: order.id,
        ticket_id: order.ticket_id,
        quantity: order.quantity,
        confirmed_at: DateTime.utc_now()
      }
    })
  end

  defp maybe_broadcast_ticket_update(%Ticket{} = ticket, action) do
    if pubsub_available?() do
      broadcast_ticket_update(ticket, action)
    end
  end

  defp maybe_broadcast_order_update(%Order{} = order, action) do
    if pubsub_available?() do
      broadcast_order_update(order, action)
    end
  end

  defp pubsub_available?() do
    case Process.whereis(Eventasaurus.PubSub) do
      nil -> false
      _pid -> true
    end
  end

  ## PubSub Broadcasting

  defp broadcast_ticket_update(%Ticket{} = ticket, action) do
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      @pubsub_topic,
      {:ticket_update, %{ticket: ticket, action: action}}
    )
  end

  defp broadcast_order_update(%Order{} = order, action) do
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      @pubsub_topic,
      {:order_update, %{order: order, action: action}}
    )
  end

  @doc """
  Subscribes to ticketing updates.

  ## Examples

      iex> subscribe()
      :ok

  """
  def subscribe do
    Phoenix.PubSub.subscribe(Eventasaurus.PubSub, @pubsub_topic)
  end

  @doc """
  Unsubscribes from ticketing updates.

  ## Examples

      iex> unsubscribe()
      :ok

  """
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(Eventasaurus.PubSub, @pubsub_topic)
  end

  # Get the configured Stripe implementation (for testing vs production)
  defp stripe_impl do
    Application.get_env(:eventasaurus_app, :stripe_module, EventasaurusApp.Stripe)
  end

end
