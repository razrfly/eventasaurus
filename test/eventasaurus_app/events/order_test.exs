defmodule EventasaurusApp.Events.OrderTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events.Order

  describe "changeset/2" do
    test "valid changeset with required fields" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 2,
        subtotal_cents: 5000,
        tax_cents: 500,
        total_cents: 5500,
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert changeset.valid?
    end

        test "requires quantity, subtotal_cents, total_cents, user_id, event_id, and ticket_id" do
      changeset = Order.changeset(%Order{}, %{})

      assert %{
        quantity: ["can't be blank"],
        subtotal_cents: ["can't be blank"],
        total_cents: ["can't be blank"],
        user_id: ["can't be blank"],
        event_id: ["can't be blank"],
        ticket_id: ["can't be blank"]
      } = errors_on(changeset)
    end

    test "validates quantity is greater than 0" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 0,
        subtotal_cents: 5000,
        total_cents: 5000,
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert %{quantity: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates subtotal_cents is non-negative" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: -100,
        total_cents: 5000,
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert %{subtotal_cents: ["cannot be negative"]} = errors_on(changeset)
    end

    test "validates tax_cents is non-negative" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: 5000,
        tax_cents: -100,
        total_cents: 5000,
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert %{tax_cents: ["cannot be negative"]} = errors_on(changeset)
    end

    test "validates total_cents is greater than 0" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: 5000,
        total_cents: 0,
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      errors = errors_on(changeset)
      assert "must be greater than 0" in errors.total_cents
    end

    test "validates currency is supported" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: 5000,
        total_cents: 5000,
        currency: "xyz",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert %{currency: ["must be a supported currency"]} = errors_on(changeset)
    end

    test "validates status is valid" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: 5000,
        total_cents: 5000,
        currency: "usd",
        status: "invalid_status",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert %{status: ["must be a valid status"]} = errors_on(changeset)
    end

    test "validates total calculation" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: 5000,
        tax_cents: 500,
        total_cents: 4000,  # Should be 5500
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert %{total_cents: ["must equal subtotal plus tax"]} = errors_on(changeset)
    end

    test "allows valid total calculation with tax" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: 5000,
        tax_cents: 500,
        total_cents: 5500,
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert changeset.valid?
    end

    test "allows valid total calculation without tax" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      attrs = %{
        quantity: 1,
        subtotal_cents: 5000,
        total_cents: 5000,
        currency: "usd",
        status: "pending",
        user_id: user.id,
        event_id: event.id,
        ticket_id: ticket.id
      }

      changeset = Order.changeset(%Order{}, attrs)
      assert changeset.valid?
    end
  end

  describe "status helper functions" do
    test "pending?/1" do
      assert Order.pending?(%Order{status: "pending"})
      refute Order.pending?(%Order{status: "confirmed"})
      refute Order.pending?(%Order{status: "refunded"})
      refute Order.pending?(%Order{status: "canceled"})
    end

    test "confirmed?/1" do
      refute Order.confirmed?(%Order{status: "pending"})
      assert Order.confirmed?(%Order{status: "confirmed"})
      refute Order.confirmed?(%Order{status: "refunded"})
      refute Order.confirmed?(%Order{status: "canceled"})
    end

    test "refunded?/1" do
      refute Order.refunded?(%Order{status: "pending"})
      refute Order.refunded?(%Order{status: "confirmed"})
      assert Order.refunded?(%Order{status: "refunded"})
      refute Order.refunded?(%Order{status: "canceled"})
    end

    test "canceled?/1" do
      refute Order.canceled?(%Order{status: "pending"})
      refute Order.canceled?(%Order{status: "confirmed"})
      refute Order.canceled?(%Order{status: "refunded"})
      assert Order.canceled?(%Order{status: "canceled"})
    end

    test "can_cancel?/1" do
      assert Order.can_cancel?(%Order{status: "pending"})
      refute Order.can_cancel?(%Order{status: "confirmed"})  # Confirmed orders cannot be canceled, only refunded
      refute Order.can_cancel?(%Order{status: "refunded"})
      refute Order.can_cancel?(%Order{status: "canceled"})
    end

    test "can_refund?/1" do
      refute Order.can_refund?(%Order{status: "pending"})
      assert Order.can_refund?(%Order{status: "confirmed"})
      assert Order.can_refund?(%Order{status: "canceled"})  # Canceled orders can be refunded if payment was captured
      refute Order.can_refund?(%Order{status: "refunded"})
    end
  end

  describe "associations" do
    test "belongs_to user" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      order = insert(:order, user: user, event: event, ticket: ticket)
      order = Repo.preload(order, :user)

      assert order.user.id == user.id
    end

    test "belongs_to event" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      order = insert(:order, user: user, event: event, ticket: ticket)
      order = Repo.preload(order, :event)

      assert order.event.id == event.id
    end

    test "belongs_to ticket" do
      user = insert(:user)
      event = insert(:event)
      ticket = insert(:ticket, event: event)

      order = insert(:order, user: user, event: event, ticket: ticket)
      order = Repo.preload(order, :ticket)

      assert order.ticket.id == ticket.id
    end
  end
end
