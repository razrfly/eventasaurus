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
    # Validate that tickets can be created for this event
    case validate_ticketing_allowed(event) do
      :ok ->
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

      {:error, reason} ->
        # Create a changeset with the validation error
        changeset =
          %Ticket{}
          |> Ticket.changeset(Map.put(attrs, :event_id, event.id))
          |> Ecto.Changeset.add_error(:event_id, reason)
        {:error, changeset}
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
  Gets a single order by ID.

  ## Examples

      iex> get_order(123)
      %Order{}

      iex> get_order(invalid_id)
      nil

  """
  def get_order(id) do
    Order
    |> preload([:user, :event, :ticket, event: :venue])
    |> Repo.get(id)
  end

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
      |> preload([:ticket, event: :venue])
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

      # Load event to check taxation type
      event = Repo.get!(Event, locked_ticket.event_id)

      with :ok <- validate_payment_processing_allowed(event),
           :ok <- validate_ticket_availability(locked_ticket, quantity),
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
  Confirms an order without payment reference (e.g., for free tickets).

  For orders with Stripe checkout sessions, this syncs amounts from Stripe.
  For legacy orders, this simply marks the order as confirmed.

  ## Examples

      iex> confirm_order(order)
      {:ok, %Order{status: "confirmed"}}

  """
  def confirm_order(%Order{} = order) do
    # If this order has a Stripe session, use the new sync flow
    if order.stripe_session_id do
      sync_order_with_stripe(order)
    else
      # Legacy flow for non-Stripe orders
      case order
           |> Order.changeset(%{
             status: "confirmed",
             confirmed_at: DateTime.utc_now()
           })
           |> Repo.update() do
        {:ok, updated_order} ->
          create_event_participant(updated_order)
          maybe_broadcast_order_update(updated_order, :confirmed)
          {:ok, updated_order}

        {:error, changeset} ->
          Logger.error("Failed to confirm order", order_id: order.id, errors: inspect(changeset.errors))
          {:error, changeset}
      end
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
  Confirms an order with a payment reference (e.g., payment intent ID or "free_ticket").

  ## Examples

      iex> confirm_order(order, "pi_1234567890")
      {:ok, %Order{}}

      iex> confirm_order(order, "free_ticket")
      {:ok, %Order{}}

  """
  def confirm_order(%Order{} = order, payment_reference) do
    Repo.transaction(fn ->
      # Update order with payment reference
      attrs = %{
        status: "confirmed",
        confirmed_at: DateTime.utc_now()
      }

      # Add payment reference if it's not a free ticket
      attrs = if payment_reference != "free_ticket" do
        Map.put(attrs, :payment_reference, payment_reference)
      else
        attrs
      end

      {:ok, confirmed_order} =
        order
        |> Order.changeset(attrs)
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
      {:ok, %{"payment_status" => "paid"} = session} ->
        # Extract final amounts from Stripe including tax
        amount_subtotal = Map.get(session, "amount_subtotal", order.subtotal_cents)
        amount_tax = Map.get(session, "amount_tax", 0)
        amount_total = Map.get(session, "amount_total", order.total_cents)

        # Update order with Stripe's calculated amounts
        updated_attrs = %{
          status: "confirmed",
          confirmed_at: DateTime.utc_now(),
          # Sync final amounts from Stripe
          subtotal_cents: amount_subtotal,
          tax_cents: amount_tax,
          total_cents: amount_total
        }

        # If we have a payment_intent from the session, store it
        updated_attrs = case Map.get(session, "payment_intent") do
          nil -> updated_attrs
          payment_intent_id when is_binary(payment_intent_id) ->
            Map.put(updated_attrs, :payment_reference, payment_intent_id)
          %{"id" => payment_intent_id} ->
            Map.put(updated_attrs, :payment_reference, payment_intent_id)
          _ -> updated_attrs
        end

        case order
             |> Order.changeset(updated_attrs)
             |> Repo.update() do
          {:ok, updated_order} ->
            Logger.info("Order confirmed with Stripe amounts",
              order_id: updated_order.id,
              original_total: order.total_cents,
              stripe_total: amount_total,
              stripe_tax: amount_tax
            )

            # Create event participant for confirmed orders
            create_event_participant(updated_order)
            maybe_broadcast_order_update(updated_order, :confirmed)
            {:ok, updated_order}

          {:error, changeset} ->
            Logger.error("Failed to update order with Stripe amounts",
              order_id: order.id,
              errors: inspect(changeset.errors)
            )
            {:error, changeset}
        end

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
    # Query for the first organizer directly via EventUser join table
    # This is more efficient and handles the case where there might be no organizer role
    organizer_query = from(u in EventasaurusApp.Accounts.User,
      join: eu in EventasaurusApp.Events.EventUser,
      on: u.id == eu.user_id,
      where: eu.event_id == ^event.id,
      limit: 1,
      select: u
    )

    case Repo.one(organizer_query) do
      %EventasaurusApp.Accounts.User{} = organizer ->
        case EventasaurusApp.Stripe.get_connect_account(organizer.id) do
          nil -> {:error, :no_stripe_account}
          connect_account -> {:ok, connect_account}
        end
      nil ->
        {:error, :no_organizer}
    end
  end

  defp insert_order_with_stripe_connect(%User{} = user, %Ticket{} = ticket, quantity, pricing, connect_account, attrs) do
    # Calculate platform fee (5% of base amount before tax)
    application_fee_amount = calculate_application_fee(pricing.subtotal_cents)

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
    # Get the event to pass taxation information to Stripe
    event = Repo.get!(Event, order.event_id)

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
      metadata,
      event
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

      # Load event to check taxation type
      event = Repo.get!(Event, locked_ticket.event_id)

      with :ok <- validate_payment_processing_allowed(event),
           :ok <- validate_ticket_availability(locked_ticket, quantity),
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

  @doc """
  Creates a combined checkout session for multiple ticket types.

  This function handles purchasing multiple different ticket types in a single
  Stripe checkout session. It:
  1. Validates availability for all ticket types
  2. Creates separate orders for each ticket type
  3. Creates a single Stripe checkout session with multiple line items
  4. Returns checkout URL for redirect

  ## Examples

      iex> order_items = [%{ticket: ticket1, quantity: 2}, %{ticket: ticket2, quantity: 1}]
      iex> create_multi_ticket_checkout_session(user, order_items)
      {:ok, %{orders: [order1, order2], checkout_url: url, session_id: session_id}}

  """
  def create_multi_ticket_checkout_session(%User{} = user, order_items) when is_list(order_items) and length(order_items) > 0 do
    require Logger

    Logger.info("Creating multi-ticket checkout session", %{
      user_id: user.id,
      ticket_count: length(order_items)
    })

    # Use transaction to ensure atomicity for all tickets
    case Repo.transaction(fn ->
      # First, validate all tickets and get connect account
      # All tickets must be from the same event for a single checkout session
      event_ids = order_items |> Enum.map(& &1.ticket.event_id) |> Enum.uniq()

      if length(event_ids) > 1 do
        Repo.rollback(:multiple_events_not_supported)
      else
        event_id = hd(event_ids)

        # Load event to check taxation type
        event = Repo.get!(Event, event_id)

        with :ok <- validate_payment_processing_allowed(event),
             {:ok, connect_account} <- get_event_organizer_stripe_account(event_id),
             {:ok, {orders, total_amount, line_items}} <- create_orders_and_line_items(user, order_items, connect_account),
             {:ok, checkout_session} <- create_multi_line_stripe_checkout_session(orders, line_items, connect_account, event_id) do

          # Update all orders with checkout session ID
          updated_orders = Enum.map(orders, fn order ->
            {:ok, updated_order} =
              order
              |> Order.changeset(%{stripe_session_id: checkout_session["id"]})
              |> Repo.update()

            maybe_broadcast_order_update(updated_order, :created)
            updated_order
          end)

          Logger.info("Successfully created multi-ticket checkout session", %{
            user_id: user.id,
            session_id: checkout_session["id"],
            total_amount: total_amount,
            order_count: length(updated_orders)
          })

          {:ok, %{
            orders: updated_orders,
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
      end
    end) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a checkout session for a guest user with a ticket.

  This function follows the same pattern as Events.register_user_for_event/3
  but for ticket purchases. It will:
  - Find or create a Supabase user via OTP
  - Sync the user to the local database
  - Create the order and checkout session
  - Register the user for the event when the order is confirmed

  ## Examples

      iex> create_guest_checkout_session(ticket, "John Doe", "john@example.com", %{quantity: 2})
      {:ok, %{order: %Order{}, checkout_url: "https://checkout.stripe.com/...", session_id: "cs_...", user: %User{}}}

  """
  def create_guest_checkout_session(%Ticket{} = ticket, name, email, attrs \\ %{}) do
    require Logger

    Logger.info("Starting guest checkout session creation", %{
      ticket_id: ticket.id,
      email: email,
      name: name
    })

    Repo.transaction(fn ->
      with {:ok, ticket} <- lock_and_validate_ticket(ticket, attrs),
           {:ok, user} <- find_or_create_guest_user(email, name),
           {:ok, order} <- create_guest_order(user, ticket, attrs, name, email),
           {:ok, session} <- create_checkout_session_for_order(order, ticket) do
        {:ok, %{order: order, checkout_url: session["url"], session_id: session["id"], user: user}}
      else
        error -> handle_transaction_error(error)
      end
    end)
    |> case do
      {:ok, {:ok, result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a combined checkout session for multiple ticket types for a guest user.

  This function follows the same pattern as create_guest_checkout_session but handles
  multiple different ticket types in a single Stripe checkout session. It:
  - Finds or creates a Supabase user via OTP
  - Syncs the user to the local database
  - Creates multiple orders and a combined checkout session
  - Registers the user for the event when the order is confirmed

  ## Examples

      iex> order_items = [%{ticket: ticket1, quantity: 2}, %{ticket: ticket2, quantity: 1}]
      iex> create_guest_multi_ticket_checkout_session("John Doe", "john@example.com", order_items)
      {:ok, %{orders: [order1, order2], checkout_url: "https://checkout.stripe.com/...", session_id: "cs_...", user: %User{}}}

  """
  def create_guest_multi_ticket_checkout_session(name, email, order_items) when is_list(order_items) and length(order_items) > 0 do
    alias EventasaurusApp.Auth.SupabaseSync
    alias EventasaurusApp.Accounts
    alias EventasaurusApp.Events
    require Logger

    Logger.info("Starting guest multi-ticket checkout session creation", %{
      email: email,
      name: name,
      ticket_count: length(order_items)
    })

    # Use transaction to ensure atomicity
    case Repo.transaction(fn ->
      # Validate all tickets are from the same event
      event_ids = order_items |> Enum.map(& &1.ticket.event_id) |> Enum.uniq()

      if length(event_ids) > 1 do
        Repo.rollback(:multiple_events_not_supported)
      else
        event_id = hd(event_ids)

        # Check if user exists in our local database first
        existing_user = Accounts.get_user_by_email(email)

        user = case existing_user do
          nil ->
            # User doesn't exist locally, check Supabase and create if needed
            Logger.info("User not found locally, attempting Supabase user creation/lookup")
            case Events.create_or_find_supabase_user(email, name) do
              {:ok, supabase_user} ->
                Logger.info("Successfully created/found user in Supabase")
                # Sync with local database
                case SupabaseSync.sync_user(supabase_user) do
                  {:ok, user} ->
                    Logger.info("Successfully synced user to local database", %{user_id: user.id})
                    user
                  {:error, reason} ->
                    Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
                    Repo.rollback(reason)
                end
              {:error, :user_confirmation_required} ->
                # User was created via OTP but email confirmation is required
                Logger.info("User created via OTP but email confirmation required, creating temporary local user record")
                # Create user with temporary supabase_id - will be updated when they confirm email
                temp_supabase_id = "pending_confirmation_#{Ecto.UUID.generate()}"
                case Accounts.create_user(%{
                  email: email,
                  name: name,
                  supabase_id: temp_supabase_id  # Temporary ID - will be updated when user confirms email
                }) do
                  {:ok, user} ->
                    Logger.info("Successfully created temporary local user", %{user_id: user.id, temp_supabase_id: temp_supabase_id})
                    user
                  {:error, reason} ->
                    Logger.error("Failed to create temporary local user", %{reason: inspect(reason)})
                    Repo.rollback(reason)
                end
              {:error, :invalid_user_data} ->
                Logger.error("Invalid user data from Supabase after OTP creation")
                Repo.rollback(:invalid_user_data)
              {:error, reason} ->
                Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
                Repo.rollback(reason)
            end

          user ->
            # User exists locally
            Logger.debug("Using existing local user", %{user_id: user.id})
            user
        end

        # Now create the multi-ticket checkout session
        # Load event to check taxation type
        event = Repo.get!(Event, event_id)

        with :ok <- validate_payment_processing_allowed(event),
             {:ok, connect_account} <- get_event_organizer_stripe_account(event_id),
             {:ok, {orders, total_amount, line_items}} <- create_guest_orders_and_line_items(user, order_items, connect_account, name, email),
             {:ok, checkout_session} <- create_multi_line_stripe_checkout_session(orders, line_items, connect_account, event_id, customer_email: email) do

          # Update all orders with checkout session ID
          updated_orders = Enum.map(orders, fn order ->
            {:ok, updated_order} =
              order
              |> Order.changeset(%{stripe_session_id: checkout_session["id"]})
              |> Repo.update()

            maybe_broadcast_order_update(updated_order, :created)
            updated_order
          end)

          Logger.info("Successfully created guest multi-ticket checkout session", %{
            user_id: user.id,
            session_id: checkout_session["id"],
            total_amount: total_amount,
            order_count: length(updated_orders)
          })

          {:ok, %{
            orders: updated_orders,
            checkout_url: checkout_session["url"],
            session_id: checkout_session["id"],
            user: user
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
      end
    end) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_order_with_checkout_session(%User{} = user, %Ticket{} = ticket, quantity, pricing, connect_account, attrs) do
    # Calculate application fee based on the base amount (before tax)
    application_fee_amount = calculate_application_fee(pricing.subtotal_cents)

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
      pricing_snapshot: pricing.pricing_snapshot,
      stripe_connect_account_id: connect_account.id,
      application_fee_amount: application_fee_amount
    })

    %Order{}
    |> Order.changeset(order_attrs)
    |> Repo.insert()
  end

  defp create_stripe_checkout_session(%Order{} = order, %Ticket{} = ticket, connect_account, opts \\ []) do
    # Get pricing details from snapshot
    pricing_snapshot = order.pricing_snapshot || %{}
    pricing_model = Map.get(pricing_snapshot, "pricing_model", "fixed")

    # Get ticket info for session
    ticket = Repo.preload(ticket, :event)

    # Load event for tax configuration and enhanced product information
    event = ticket.event

    # Get user information for pre-filling Stripe checkout
    user = Repo.get!(User, order.user_id)

    # Use provided customer info from opts, or fall back to user record
    customer_email = Keyword.get(opts, :customer_email, user.email)

    # Generate idempotency key
    idempotency_key = "order_#{order.id}_#{DateTime.utc_now() |> DateTime.to_unix()}"

    # Build URLs
    base_url = get_base_url()
    success_url = "#{base_url}/orders/#{order.id}/success?session_id={CHECKOUT_SESSION_ID}"
    cancel_url = "#{base_url}/#{event.slug}"

    metadata = %{
      "order_id" => to_string(order.id),
      "user_id" => to_string(order.user_id),
      "event_id" => to_string(order.event_id),
      "ticket_id" => to_string(order.ticket_id),
      "pricing_model" => pricing_model
    }

    # Calculate application fee as a percentage of the base amount (before tax)
    application_fee_amount = calculate_application_fee(order.subtotal_cents)

    checkout_params = %{
      # Use subtotal (base amount) - Stripe will add tax automatically
      amount_cents: order.subtotal_cents,
      currency: order.currency,
      connect_account: connect_account,
      application_fee_amount: application_fee_amount,
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: metadata,
      idempotency_key: idempotency_key,
      pricing_model: pricing_model,
      allow_promotion_codes: false,
      quantity: order.quantity,
      ticket_name: ticket.title,
      ticket_description: "#{event.title} - #{ticket.title}",
      # Pre-fill customer information
      customer_email: customer_email,
      # Pass event for tax configuration and enhanced product information
      event: event
    }

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

    # Calculate base amounts (no tax - let Stripe handle tax calculation)
    base_subtotal_cents = price_per_ticket * quantity
    tip_total_cents = tip_cents * quantity
    subtotal_cents = base_subtotal_cents + tip_total_cents

    # No tax calculation - Stripe will handle this automatically
    # Store the subtotal as the total since tax will be calculated by Stripe
    total_cents = subtotal_cents

    {:ok, %{
      subtotal_cents: subtotal_cents,
      tax_cents: 0, # Tax will be calculated by Stripe
      total_cents: total_cents,
      currency: ticket.currency,
      pricing_snapshot: Order.create_pricing_snapshot(ticket, custom_price_cents, tip_cents)
    }}
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

    # Validates whether ticketing functionality is allowed for an event
  defp validate_ticketing_allowed(%Event{taxation_type: "ticketless"}) do
    {:error, "Tickets cannot be created for ticketless events. Change the event's taxation type to 'Ticketed Event' or 'Contribution Collection' to enable ticketing."}
  end

  defp validate_ticketing_allowed(%Event{}), do: :ok

  # Validates whether payment processing is allowed for an event
  defp validate_payment_processing_allowed(%Event{taxation_type: "ticketless"}) do
    {:error, :ticketless_payment_blocked}
  end

  defp validate_payment_processing_allowed(%Event{}), do: :ok

  # Guest checkout helper functions

  defp lock_and_validate_ticket(%Ticket{} = ticket, attrs) do
    quantity = Map.get(attrs, :quantity, 1)
    custom_price_cents = Map.get(attrs, :custom_price_cents)

    # Lock the ticket row to prevent concurrent modifications
    locked_ticket = Repo.get!(Ticket, ticket.id, lock: "FOR UPDATE")

    # Validate ticket availability
    with :ok <- validate_ticket_availability(locked_ticket, quantity),
         :ok <- validate_flexible_pricing(locked_ticket, custom_price_cents) do
      {:ok, locked_ticket}
    end
  end

  defp find_or_create_guest_user(email, name) do
    alias EventasaurusApp.Auth.SupabaseSync
    alias EventasaurusApp.Accounts
    alias EventasaurusApp.Events

    # Check if user exists in our local database first
    existing_user = Accounts.get_user_by_email(email)

    if existing_user do
      Logger.debug("Existing user found in local database", %{user_id: existing_user.id})
      {:ok, existing_user}
    else
      Logger.debug("No existing user found in local database")

      # User doesn't exist locally, check Supabase and create if needed
      Logger.info("User not found locally, attempting Supabase user creation/lookup")
      case Events.create_or_find_supabase_user(email, name) do
        {:ok, supabase_user} ->
          Logger.info("Successfully created/found user in Supabase")
          # Sync with local database
          case SupabaseSync.sync_user(supabase_user) do
            {:ok, user} ->
              Logger.info("Successfully synced user to local database", %{user_id: user.id})
              {:ok, user}
            {:error, reason} ->
              Logger.error("Failed to sync user to local database", %{reason: inspect(reason)})
              {:error, reason}
          end
        {:error, :user_confirmation_required} ->
          # User was created via OTP but email confirmation is required
          Logger.info("User created via OTP but email confirmation required, creating temporary local user record")
          # Create user with temporary supabase_id - will be updated when they confirm email
          temp_supabase_id = "pending_confirmation_#{Ecto.UUID.generate()}"
          case Accounts.create_user(%{
            email: email,
            name: name,
            supabase_id: temp_supabase_id  # Temporary ID - will be updated when user confirms email
          }) do
            {:ok, user} ->
              Logger.info("Successfully created temporary local user", %{user_id: user.id, temp_supabase_id: temp_supabase_id})
              {:ok, user}
            {:error, reason} ->
              Logger.error("Failed to create temporary local user", %{reason: inspect(reason)})
              {:error, reason}
          end
        {:error, :invalid_user_data} ->
          Logger.error("Invalid user data from Supabase after OTP creation")
          {:error, :invalid_user_data}
        {:error, reason} ->
          Logger.error("Failed to create/find user in Supabase", %{reason: inspect(reason)})
          {:error, reason}
      end
    end
  end

  defp create_guest_order(user, ticket, attrs, name, email) do
    quantity = Map.get(attrs, :quantity, 1)
    custom_price_cents = Map.get(attrs, :custom_price_cents)
    tip_cents = Map.get(attrs, :tip_cents, 0)

    # Proceed with order creation using the standard flow
    with {:ok, pricing} <- calculate_order_pricing(ticket, quantity, custom_price_cents, tip_cents),
         {:ok, connect_account} <- get_event_organizer_stripe_account(ticket.event_id),
         {:ok, order} <- insert_order_with_checkout_session(user, ticket, quantity, pricing, connect_account, Map.put(attrs, :guest_metadata, %{name: name, email: email})) do
      {:ok, order}
    end
  end

  defp create_checkout_session_for_order(order, ticket) do
    # Extract guest metadata if this is a guest order
    guest_metadata = get_in(order, [Access.key(:guest_metadata), Access.all()]) || %{}
    guest_email = Map.get(guest_metadata, :email) || Map.get(guest_metadata, "email")

    # Prepare customer options if we have guest data
    customer_opts = []
    customer_opts = if guest_email, do: [{:customer_email, guest_email} | customer_opts], else: customer_opts

    with {:ok, connect_account} <- get_event_organizer_stripe_account(ticket.event_id),
         {:ok, checkout_session} <- create_stripe_checkout_session(order, ticket, connect_account, customer_opts) do

      # Update order with checkout session ID
      {:ok, updated_order} =
        order
        |> Order.changeset(%{stripe_session_id: checkout_session["id"]})
        |> Repo.update()

      maybe_broadcast_order_update(updated_order, :created)

      Logger.info("Successfully created guest checkout session", %{
        order_id: updated_order.id,
        user_id: order.user_id,
        session_id: checkout_session["id"]
      })

      {:ok, checkout_session}
    end
  end

  defp handle_transaction_error(error) do
    # Force transaction rollback by calling Repo.rollback
    case error do
      {:error, reason} -> Repo.rollback(reason)
      atom when is_atom(atom) -> Repo.rollback(atom)
      other -> Repo.rollback(other)
    end
  end

  # Multi-ticket checkout helper functions

  defp create_orders_and_line_items(user, order_items, connect_account) do
    # Process each ticket type and create orders + line items
    case Enum.reduce_while(order_items, {:ok, {[], 0, []}}, fn order_item, {:ok, {orders_acc, total_acc, line_items_acc}} ->
      # Lock the ticket row to prevent concurrent modifications
      locked_ticket = Repo.get!(Ticket, order_item.ticket.id, lock: "FOR UPDATE")

      with :ok <- validate_ticket_availability(locked_ticket, order_item.quantity),
           :ok <- validate_flexible_pricing(locked_ticket, order_item[:custom_price_cents]),
           {:ok, pricing} <- calculate_order_pricing(locked_ticket, order_item.quantity, order_item[:custom_price_cents], order_item[:tip_cents] || 0),
           {:ok, order} <- insert_order_with_checkout_session(user, locked_ticket, order_item.quantity, pricing, connect_account, %{}) do

        # Create line item for Stripe
        line_item = create_line_item_for_order(order, locked_ticket)

        {:cont, {:ok, {[order | orders_acc], total_acc + order.total_cents, [line_item | line_items_acc]}}}
      else
        error -> {:halt, error}
      end
    end) do
      {:ok, {orders, total_amount, line_items}} ->
        {:ok, {Enum.reverse(orders), total_amount, Enum.reverse(line_items)}}
      error -> error
    end
  end

  defp create_line_item_for_order(order, ticket) do
    ticket = Repo.preload(ticket, :event)
    event = ticket.event
    pricing_snapshot = order.pricing_snapshot || %{}
    pricing_model = Map.get(pricing_snapshot, "pricing_model", "fixed")

    # Use subtotal (base amount before tax) for unit amount calculation
    # Let Stripe handle tax calculation automatically
    unit_amount = case order.quantity do
      0 ->
        Logger.error("Order quantity is zero for order #{order.id}")
        0
      quantity ->
        # Use subtotal which is the base amount before tax
        # Stripe will add tax automatically during checkout
        div(order.subtotal_cents, quantity)
    end

    # Enhanced product description with event details
    product_description = if event.description && String.trim(event.description) != "" do
      # Include event date if available
      date_info = if event.start_at do
        formatted_date = Calendar.strftime(event.start_at, "%B %d, %Y at %I:%M %p")
        "Event Date: #{formatted_date}\n\n"
      else
        ""
      end

      event_desc = String.slice(event.description, 0, 500) # Stripe has limits on description length
      "#{date_info}#{event_desc}"
    else
      "#{event.title} - #{ticket.title}"
    end

    # Build base product data
    product_data = %{
      name: ticket.title,
      description: product_description
    }

    # Add event image if available
    product_data = if event.cover_image_url do
      # Get full image URL for Stripe
      full_image_url = get_full_image_url(event.cover_image_url)
      Map.put(product_data, :images, [full_image_url])
    else
      product_data
    end

    %{
      price_data: %{
        currency: order.currency,
        unit_amount: unit_amount,
        product_data: product_data
      },
      quantity: order.quantity,
      metadata: %{
        "order_id" => to_string(order.id),
        "ticket_id" => to_string(order.ticket_id),
        "pricing_model" => pricing_model
      }
    }
  end

  # Helper function to get full image URL for Stripe
  defp get_full_image_url(image_url) do
    case URI.parse(image_url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        # Already a full URL
        image_url
      %URI{path: "/" <> _rest} ->
        # Absolute path, prepend base URL
        "#{get_base_url()}#{image_url}"
      _ ->
        # Relative path, prepend base URL with /
        "#{get_base_url()}/#{image_url}"
    end
  end

  defp create_multi_line_stripe_checkout_session(orders, line_items, connect_account, event_id, opts \\ []) do
    # Get event for cancel URL and tax configuration
    event = Repo.get!(Event, event_id)

    # Calculate total application fee from base amounts (before tax)
    total_application_fee = Enum.reduce(orders, 0, fn order, acc ->
      acc + calculate_application_fee(order.subtotal_cents)
    end)

        # Use the first order's ID for the session metadata and success URL
    primary_order = hd(orders)

    # Get user information for pre-filling Stripe checkout
    user = Repo.get!(User, primary_order.user_id)

    # Use provided customer info from opts, or fall back to user record
    customer_email = Keyword.get(opts, :customer_email, user.email)

    # Generate idempotency key
    order_ids = orders |> Enum.map(&to_string(&1.id)) |> Enum.join("_")
    idempotency_key = "multi_order_#{order_ids}_#{DateTime.utc_now() |> DateTime.to_unix()}"

    # Build URLs
    base_url = get_base_url()
    success_url = "#{base_url}/orders/#{primary_order.id}/success?session_id={CHECKOUT_SESSION_ID}&multi_order=true"
    cancel_url = "#{base_url}/#{event.slug}"

    metadata = %{
      "primary_order_id" => to_string(primary_order.id),
      "order_ids" => order_ids,
      "user_id" => to_string(primary_order.user_id),
      "event_id" => to_string(event_id),
      "multi_ticket_purchase" => "true"
    }

    checkout_params = %{
      line_items: line_items,
      connect_account: connect_account,
      application_fee_amount: total_application_fee,
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: metadata,
      idempotency_key: idempotency_key,
      # Pre-fill customer information
      customer_email: customer_email,
      # Pass event for tax configuration
      event: event
    }

    stripe_impl().create_multi_line_checkout_session(checkout_params)
  end

  defp create_guest_orders_and_line_items(user, order_items, connect_account, name, email) do
    # Process each ticket type and create orders + line items for guest checkout
    case Enum.reduce_while(order_items, {:ok, {[], 0, []}}, fn order_item, {:ok, {orders_acc, total_acc, line_items_acc}} ->
      # Lock the ticket row to prevent concurrent modifications
      locked_ticket = Repo.get!(Ticket, order_item.ticket.id, lock: "FOR UPDATE")

      with :ok <- validate_ticket_availability(locked_ticket, order_item.quantity),
           :ok <- validate_flexible_pricing(locked_ticket, order_item[:custom_price_cents]),
           {:ok, pricing} <- calculate_order_pricing(locked_ticket, order_item.quantity, order_item[:custom_price_cents], order_item[:tip_cents] || 0),
           {:ok, order} <- insert_order_with_checkout_session(user, locked_ticket, order_item.quantity, pricing, connect_account, %{guest_metadata: %{name: name, email: email}}) do

        # Create line item for Stripe
        line_item = create_line_item_for_order(order, locked_ticket)

        {:cont, {:ok, {[order | orders_acc], total_acc + order.total_cents, [line_item | line_items_acc]}}}
      else
        error -> {:halt, error}
      end
    end) do
      {:ok, {orders, total_amount, line_items}} ->
        {:ok, {Enum.reverse(orders), total_amount, Enum.reverse(line_items)}}
      error -> error
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

  # Calculate application fee as a percentage of the base amount (before tax)
  # This is more accurate than applying fee to the total amount including tax
  defp calculate_application_fee(base_amount_cents, fee_percentage \\ 0.05) do
    round(base_amount_cents * fee_percentage)
  end

end
