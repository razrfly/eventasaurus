defmodule EventasaurusApp.Events.TicketTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events.Ticket
  alias EventasaurusApp.Events.Event

  describe "changeset/2" do
    test "valid changeset with required fields" do
      event = insert(:event)

      attrs = %{
        title: "General Admission",
        price_cents: 2500,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert changeset.valid?
    end

    test "requires title, price_cents, quantity, and event_id" do
      changeset = Ticket.changeset(%Ticket{}, %{})

      assert %{
        title: ["can't be blank"],
        price_cents: ["can't be blank"],
        quantity: ["can't be blank"],
        event_id: ["can't be blank"]
      } = errors_on(changeset)
    end

    test "allows free tickets (price_cents = 0)" do
      event = insert(:event)

      attrs = %{
        title: "Free Ticket",
        price_cents: 0,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert changeset.valid?
    end

    test "validates price_cents cannot be negative" do
      event = insert(:event)

      attrs = %{
        title: "Negative Price Ticket",
        price_cents: -100,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{price_cents: ["cannot be negative"]} = errors_on(changeset)
    end

    test "validates quantity > 0" do
      event = insert(:event)

      attrs = %{
        title: "No Quantity Ticket",
        price_cents: 2500,
        currency: "usd",
        quantity: 0,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{quantity: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates title length" do
      event = insert(:event)

      # Too short (empty string)
      attrs = %{
        title: "",
        price_cents: 2500,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{title: ["can't be blank"]} = errors_on(changeset)

      # Too long
      long_title = String.duplicate("a", 256)
      attrs = %{attrs | title: long_title}

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{title: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "validates supported currencies" do
      event = insert(:event)

      attrs = %{
        title: "Test Ticket",
        price_cents: 2500,
        currency: "xyz",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{currency: ["must be a supported currency"]} = errors_on(changeset)
    end

    test "validates availability window" do
      event = insert(:event)
      now = DateTime.utc_now()
      past_time = DateTime.add(now, -3600, :second)
      future_time = DateTime.add(now, 3600, :second)

      # starts_at in the past
      attrs = %{
        title: "Past Ticket",
        price_cents: 2500,
        currency: "usd",
        quantity: 100,
        starts_at: past_time,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{starts_at: ["cannot be in the past"]} = errors_on(changeset)

      # ends_at before starts_at
      attrs = %{
        title: "Invalid Window Ticket",
        price_cents: 2500,
        currency: "usd",
        quantity: 100,
        starts_at: future_time,
        ends_at: now,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{ends_at: ["must be after start time"]} = errors_on(changeset)
    end
  end

  describe "on_sale?/1" do
    test "returns true when starts_at is nil" do
      ticket = %Ticket{starts_at: nil}
      assert Ticket.on_sale?(ticket)
    end

    test "returns true when current time is after starts_at and ends_at is nil" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      ticket = %Ticket{starts_at: past_time, ends_at: nil}
      assert Ticket.on_sale?(ticket)
    end

    test "returns false when current time is before starts_at" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      ticket = %Ticket{starts_at: future_time, ends_at: nil}
      refute Ticket.on_sale?(ticket)
    end

    test "returns true when current time is within availability window" do
      now = DateTime.utc_now()
      past_time = DateTime.add(now, -3600, :second)
      future_time = DateTime.add(now, 3600, :second)

      ticket = %Ticket{starts_at: past_time, ends_at: future_time}
      assert Ticket.on_sale?(ticket)
    end

    test "returns false when current time is after ends_at" do
      now = DateTime.utc_now()
      past_start = DateTime.add(now, -7200, :second)
      past_end = DateTime.add(now, -3600, :second)

      ticket = %Ticket{starts_at: past_start, ends_at: past_end}
      refute Ticket.on_sale?(ticket)
    end
  end
end
