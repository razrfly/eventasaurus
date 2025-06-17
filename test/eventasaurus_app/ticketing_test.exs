defmodule EventasaurusApp.TicketingTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Ticketing
  alias EventasaurusApp.Events.{Ticket, Order}

  import EventasaurusApp.Factory

  describe "tickets" do
    setup do
      event = insert(:event, is_ticketed: true)
      %{event: event}
    end

    test "list_tickets_for_event/1 returns all tickets for an event", %{event: event} do
      ticket1 = insert(:ticket, event: event)
      ticket2 = insert(:ticket, event: event)
      other_event = insert(:event, is_ticketed: true)
      _other_ticket = insert(:ticket, event: other_event)

      tickets = Ticketing.list_tickets_for_event(event.id)

      assert length(tickets) == 2
      assert Enum.any?(tickets, &(&1.id == ticket1.id))
      assert Enum.any?(tickets, &(&1.id == ticket2.id))
    end

    test "get_ticket!/1 returns the ticket with given id", %{event: event} do
      ticket = insert(:ticket, event: event)
      assert Ticketing.get_ticket!(ticket.id).id == ticket.id
    end

    test "get_ticket!/1 raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn -> Ticketing.get_ticket!(0) end
    end

    test "get_ticket_with_event!/1 returns ticket with preloaded event", %{event: event} do
      ticket = insert(:ticket, event: event)
      result = Ticketing.get_ticket_with_event!(ticket.id)

      assert result.id == ticket.id
      assert result.event.id == event.id
      assert result.event.title == event.title
    end

    test "create_ticket/2 with valid data creates a ticket", %{event: event} do
      now = DateTime.utc_now()
      valid_attrs = %{
        title: "General Admission",
        description: "Standard entry ticket",
        base_price_cents: 2500,
        quantity: 100,
        starts_at: DateTime.add(now, 1, :hour),
        ends_at: DateTime.add(now, 7, :day)
      }

      assert {:ok, %Ticket{} = ticket} = Ticketing.create_ticket(event, valid_attrs)
      assert ticket.title == "General Admission"
      assert ticket.description == "Standard entry ticket"
      assert ticket.base_price_cents == 2500
      assert ticket.quantity == 100
      assert ticket.event_id == event.id
    end

    test "create_ticket/2 with invalid data returns error changeset", %{event: event} do
      assert {:error, %Ecto.Changeset{}} = Ticketing.create_ticket(event, %{})
    end

    test "update_ticket/2 with valid data updates the ticket", %{event: event} do
      ticket = insert(:ticket, event: event)
      update_attrs = %{title: "VIP Access", base_price_cents: 5000}

      assert {:ok, %Ticket{} = updated_ticket} = Ticketing.update_ticket(ticket, update_attrs)
      assert updated_ticket.title == "VIP Access"
              assert updated_ticket.base_price_cents == 5000
    end

    test "update_ticket/2 with invalid data returns error changeset", %{event: event} do
      ticket = insert(:ticket, event: event)
      assert {:error, %Ecto.Changeset{}} = Ticketing.update_ticket(ticket, %{title: ""})

      # Compare without preloaded associations
      original_ticket = Ticketing.get_ticket!(ticket.id)
      assert ticket.id == original_ticket.id
      assert ticket.title == original_ticket.title
    end

    test "delete_ticket/1 deletes the ticket", %{event: event} do
      ticket = insert(:ticket, event: event)
      assert {:ok, %Ticket{}} = Ticketing.delete_ticket(ticket)
      assert_raise Ecto.NoResultsError, fn -> Ticketing.get_ticket!(ticket.id) end
    end

    test "change_ticket/1 returns a ticket changeset", %{event: event} do
      ticket = insert(:ticket, event: event)
      assert %Ecto.Changeset{} = Ticketing.change_ticket(ticket)
    end
  end

  describe "ticket availability" do
    setup do
      event = insert(:event, is_ticketed: true)
      now = DateTime.utc_now()

      # Available ticket (on sale now, ends in future)
      available_ticket = insert(:ticket,
        event: event,
        quantity: 10,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :hour)
      )

      # Sold out ticket
      sold_out_ticket = insert(:ticket,
        event: event,
        quantity: 2,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :hour)
      )

      # Create orders that consume all sold_out_ticket quantity
      user = insert(:user)
      insert(:confirmed_order,
        user: user,
        event: event,
        ticket: sold_out_ticket,
        quantity: 2
      )

      # Not yet on sale ticket
      future_ticket = insert(:ticket,
        event: event,
        quantity: 10,
        starts_at: DateTime.add(now, 1, :hour),
        ends_at: DateTime.add(now, 2, :hour)
      )

      # Sale ended ticket
      past_ticket = insert(:ticket,
        event: event,
        quantity: 10,
        starts_at: DateTime.add(now, -2, :hour),
        ends_at: DateTime.add(now, -1, :hour)
      )

      %{
        event: event,
        available_ticket: available_ticket,
        sold_out_ticket: sold_out_ticket,
        future_ticket: future_ticket,
        past_ticket: past_ticket
      }
    end

    test "ticket_available?/2 returns true for available tickets", %{available_ticket: ticket} do
      assert Ticketing.ticket_available?(ticket, 1) == true
      assert Ticketing.ticket_available?(ticket, 5) == true
      assert Ticketing.ticket_available?(ticket, 10) == true
    end

    test "ticket_available?/2 returns false for sold out tickets", %{sold_out_ticket: ticket} do
      assert Ticketing.ticket_available?(ticket, 1) == false
    end

    test "ticket_available?/2 returns false for tickets not yet on sale", %{future_ticket: ticket} do
      assert Ticketing.ticket_available?(ticket, 1) == false
    end

    test "ticket_available?/2 returns false for tickets past sale period", %{past_ticket: ticket} do
      assert Ticketing.ticket_available?(ticket, 1) == false
    end

    test "ticket_available?/2 returns false for invalid quantities", %{available_ticket: ticket} do
      assert Ticketing.ticket_available?(ticket, 0) == false
      assert Ticketing.ticket_available?(ticket, -1) == false
      assert Ticketing.ticket_available?(ticket, 11) == false
    end

    test "available_quantity/1 returns correct available count", %{available_ticket: ticket, sold_out_ticket: sold_out_ticket} do
      assert Ticketing.available_quantity(ticket) == 10
      assert Ticketing.available_quantity(sold_out_ticket) == 0
    end

    test "count_sold_tickets/1 returns correct sold count", %{sold_out_ticket: ticket} do
      assert Ticketing.count_sold_tickets(ticket.id) == 2
    end

    test "count_sold_tickets/1 returns 0 for tickets with no orders", %{available_ticket: ticket} do
      assert Ticketing.count_sold_tickets(ticket.id) == 0
    end
  end

    describe "orders" do
    setup do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        base_price_cents: 2500,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :day)
      )

      %{event: event, user: user, ticket: ticket}
    end

    test "list_orders_for_user/1 returns all orders for a user", %{user: user, event: event, ticket: ticket} do
      order1 = insert(:order, user: user, event: event, ticket: ticket)
      order2 = insert(:order, user: user, event: event, ticket: ticket)
      other_user = insert(:user)
      _other_order = insert(:order, user: other_user, event: event, ticket: ticket)

      orders = Ticketing.list_orders_for_user(user.id)

      assert length(orders) == 2
      assert Enum.any?(orders, &(&1.id == order1.id))
      assert Enum.any?(orders, &(&1.id == order2.id))
    end

    test "list_orders_for_event/1 returns all orders for an event", %{user: user, event: event, ticket: ticket} do
      order1 = insert(:order, user: user, event: event, ticket: ticket)
      order2 = insert(:order, user: user, event: event, ticket: ticket)
      other_event = insert(:event, is_ticketed: true)
      other_ticket = insert(:ticket, event: other_event)
      _other_order = insert(:order, user: user, event: other_event, ticket: other_ticket)

      orders = Ticketing.list_orders_for_event(event.id)

      assert length(orders) == 2
      assert Enum.any?(orders, &(&1.id == order1.id))
      assert Enum.any?(orders, &(&1.id == order2.id))
    end

    test "get_order!/1 returns the order with given id", %{user: user, event: event, ticket: ticket} do
      order = insert(:order, user: user, event: event, ticket: ticket)
      assert Ticketing.get_order!(order.id).id == order.id
    end

    test "get_order!/1 raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn -> Ticketing.get_order!(0) end
    end

    test "get_order_with_associations!/1 returns order with preloaded associations", %{user: user, event: event, ticket: ticket} do
      order = insert(:order, user: user, event: event, ticket: ticket)
      result = Ticketing.get_order_with_associations!(order.id)

      assert result.id == order.id
      assert result.user.id == user.id
      assert result.event.id == event.id
      assert result.ticket.id == ticket.id
    end

    test "get_user_order!/2 returns order for specific user", %{user: user, event: event, ticket: ticket} do
      order = insert(:order, user: user, event: event, ticket: ticket)
      result = Ticketing.get_user_order!(user.id, order.id)

      assert result.id == order.id
      assert result.user_id == user.id
    end

    test "get_user_order!/2 raises if order belongs to different user", %{user: user, event: event, ticket: ticket} do
      other_user = insert(:user)
      order = insert(:order, user: other_user, event: event, ticket: ticket)

      assert_raise Ecto.NoResultsError, fn ->
        Ticketing.get_user_order!(user.id, order.id)
      end
    end

    test "create_order/3 with valid data creates an order", %{user: user, ticket: ticket} do
      attrs = %{quantity: 2}

      assert {:ok, %Order{} = order} = Ticketing.create_order(user, ticket, attrs)
      assert order.user_id == user.id
      assert order.event_id == ticket.event_id
      assert order.ticket_id == ticket.id
      assert order.quantity == 2
      assert order.subtotal_cents == 5000  # 2500 * 2
      assert order.tax_cents == 500        # 10% of subtotal
      assert order.total_cents == 5500     # subtotal + tax
      assert order.currency == "usd"
      assert order.status == "pending"
    end

    test "create_order/3 with default quantity creates single ticket order", %{user: user, ticket: ticket} do
      assert {:ok, %Order{} = order} = Ticketing.create_order(user, ticket)
      assert order.quantity == 1
      assert order.subtotal_cents == 2500
      assert order.tax_cents == 250
      assert order.total_cents == 2750
    end

    test "create_order/3 fails when ticket is not available", %{user: user, event: event} do
      # Create a sold out ticket
      sold_out_ticket = insert(:ticket, event: event, quantity: 1)
      insert(:confirmed_order, user: user, event: event, ticket: sold_out_ticket, quantity: 1)

      assert {:error, :ticket_unavailable} = Ticketing.create_order(user, sold_out_ticket, %{quantity: 1})
    end

    test "create_order/3 fails when requesting more tickets than available", %{user: user, ticket: ticket} do
      # Ticket has default quantity of 100, request more
      assert {:error, :ticket_unavailable} = Ticketing.create_order(user, ticket, %{quantity: 101})
    end

    test "change_order/1 returns an order changeset", %{user: user, event: event, ticket: ticket} do
      order = insert(:order, user: user, event: event, ticket: ticket)
      assert %Ecto.Changeset{} = Ticketing.change_order(order)
    end
  end

    describe "order status management" do
    setup do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :day)
      )

      %{event: event, user: user, ticket: ticket}
    end

    test "confirm_order/2 updates order status and creates event participant", %{user: user, event: event, ticket: ticket} do
      order = insert(:order, user: user, event: event, ticket: ticket, status: "pending")
      payment_reference = "pi_test_payment_intent"

      assert {:ok, confirmed_order} = Ticketing.confirm_order(order, payment_reference)
      assert confirmed_order.status == "confirmed"
      assert confirmed_order.payment_reference == payment_reference
      assert confirmed_order.confirmed_at != nil

      # Check that EventParticipant was created
      participant = EventasaurusApp.Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.role == :ticket_holder
      assert participant.status == :confirmed_with_order
      assert participant.source == "ticket_purchase"
    end

    test "confirm_order/2 upgrades existing event participant", %{user: user, event: event, ticket: ticket} do
      # Create an existing participant with different status
      {:ok, existing_participant} = EventasaurusApp.Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "manual_invite",
        metadata: %{invited_by: "admin"}
      })

      order = insert(:order, user: user, event: event, ticket: ticket, status: "pending")
      payment_reference = "pi_test_payment_intent"

      assert {:ok, confirmed_order} = Ticketing.confirm_order(order, payment_reference)
      assert confirmed_order.status == "confirmed"

      # Check that existing participant was upgraded, not duplicated
      participant = EventasaurusApp.Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.id == existing_participant.id  # Same record
      assert participant.role == :ticket_holder  # Upgraded role
      assert participant.status == :confirmed_with_order  # Upgraded status
      assert participant.source == "manual_invite"  # Original source preserved

      # Metadata should be merged
      assert participant.metadata["invited_by"] == "admin"  # Original metadata preserved
      assert participant.metadata["order_id"] == confirmed_order.id  # New metadata added

      # Ensure no duplicate participants were created
      participants = EventasaurusApp.Events.list_event_participants_for_event(event)
      user_participants = Enum.filter(participants, &(&1.user_id == user.id))
      assert length(user_participants) == 1
    end

    test "cancel_order/1 cancels a pending order", %{user: user, event: event, ticket: ticket} do
      order = insert(:order, user: user, event: event, ticket: ticket, status: "pending")

      assert {:ok, canceled_order} = Ticketing.cancel_order(order)
      assert canceled_order.status == "canceled"
    end

    test "cancel_order/1 fails for confirmed orders", %{user: user, event: event, ticket: ticket} do
      order = insert(:confirmed_order, user: user, event: event, ticket: ticket)

      assert {:error, :cannot_cancel} = Ticketing.cancel_order(order)
    end

    test "refund_order/1 refunds a confirmed order", %{user: user, event: event, ticket: ticket} do
      order = insert(:confirmed_order, user: user, event: event, ticket: ticket)

      assert {:ok, refunded_order} = Ticketing.refund_order(order)
      assert refunded_order.status == "refunded"
    end

    test "refund_order/1 fails for pending orders", %{user: user, event: event, ticket: ticket} do
      order = insert(:order, user: user, event: event, ticket: ticket, status: "pending")

      assert {:error, :cannot_refund} = Ticketing.refund_order(order)
    end
  end

  describe "pricing calculations" do
    test "calculates correct pricing for single ticket" do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        base_price_cents: 1000,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :day)
      )

      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 1})

      assert order.subtotal_cents == 1000
      assert order.tax_cents == 100      # 10% tax
      assert order.total_cents == 1100   # subtotal + tax
    end

    test "calculates correct pricing for multiple tickets" do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        base_price_cents: 1500,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :day)
      )

      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 3})

      assert order.subtotal_cents == 4500  # 1500 * 3
      assert order.tax_cents == 450        # 10% tax
      assert order.total_cents == 4950     # subtotal + tax
    end

    test "handles currency from ticket" do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        base_price_cents: 2000,
        currency: "eur",
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :day)
      )

      {:ok, order} = Ticketing.create_order(user, ticket)

      assert order.currency == "eur"
    end
  end

  describe "pubsub integration" do
    @tag :skip_pubsub
    test "broadcasts ticket updates on create" do
      event = insert(:event, is_ticketed: true)
      Ticketing.subscribe()

             now = DateTime.utc_now()
       {:ok, ticket} = Ticketing.create_ticket(event, %{
         title: "Test Ticket",
         base_price_cents: 1000,
         quantity: 10,
         starts_at: DateTime.add(now, 1, :hour),
         ends_at: DateTime.add(now, 1, :day)
       })

      assert_receive {:ticket_update, %{ticket: ^ticket, action: :created}}
    end

    @tag :skip_pubsub
    test "broadcasts order updates on create" do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :day)
      )
      Ticketing.subscribe()

      {:ok, order} = Ticketing.create_order(user, ticket)

      assert_receive {:order_update, %{order: ^order, action: :created}}
    end

    @tag :skip_pubsub
    test "broadcasts order updates on confirm" do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :day)
      )
      order = insert(:order, user: user, event: event, ticket: ticket, status: "pending")
      Ticketing.subscribe()

      {:ok, confirmed_order} = Ticketing.confirm_order(order, "pi_test")

      assert_receive {:order_update, %{order: ^confirmed_order, action: :confirmed}}
    end
  end

  describe "real-time updates" do
    @tag :real_time_updates
    test "broadcasts ticket updates when orders are created" do
      user = insert(:user)
      event = insert(:event, is_ticketed: true)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        quantity: 10,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :hour)
      )

      # Subscribe to updates - use the correct PubSub name
      Ticketing.subscribe()

      # Create an order
      {:ok, _order} = Ticketing.create_order(user, ticket, %{quantity: 2})

      # Should receive ticket update
      assert_receive {:ticket_update, %{ticket: updated_ticket, action: :order_created}}, 1000
      assert updated_ticket.id == ticket.id
    end

    @tag :real_time_updates
    test "broadcasts ticket updates when orders are confirmed" do
      user = insert(:user)
      event = insert(:event, is_ticketed: true)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        quantity: 10,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :hour)
      )

      # Create an order first
      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 2})

      # Subscribe to updates - use the correct PubSub name
      Ticketing.subscribe()

      # Confirm the order
      {:ok, _confirmed_order} = Ticketing.confirm_order(order, "test_payment_reference")

      # Should receive ticket update
      assert_receive {:ticket_update, %{ticket: updated_ticket, action: :order_confirmed}}, 1000
      assert updated_ticket.id == ticket.id
    end

    @tag :real_time_updates
    test "broadcasts ticket updates when orders are canceled" do
      user = insert(:user)
      event = insert(:event, is_ticketed: true)
      now = DateTime.utc_now()
      ticket = insert(:ticket,
        event: event,
        quantity: 10,
        starts_at: DateTime.add(now, -1, :hour),
        ends_at: DateTime.add(now, 1, :hour)
      )

      # Create an order first
      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 2})

      # Subscribe to updates - use the correct PubSub name
      Ticketing.subscribe()

      # Cancel the order
      {:ok, _canceled_order} = Ticketing.cancel_order(order)

      # Should receive ticket update
      assert_receive {:ticket_update, %{ticket: updated_ticket, action: :order_canceled}}, 1000
      assert updated_ticket.id == ticket.id
    end
  end
end
