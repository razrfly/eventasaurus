defmodule EventasaurusApp.Events.TicketTest do
  use EventasaurusApp.DataCase

  alias EventasaurusApp.Events.Ticket
  alias EventasaurusApp.Events.Event

  describe "changeset/2" do
    test "valid changeset with required fields" do
      event = insert(:event)

      attrs = %{
        title: "General Admission",
        base_price_cents: 2500,
        minimum_price_cents: 2500,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert changeset.valid?
    end

    test "requires title, base_price_cents, quantity, and event_id" do
      changeset = Ticket.changeset(%Ticket{}, %{})

      assert %{
        title: ["can't be blank"],
        base_price_cents: ["can't be blank"],
        quantity: ["can't be blank"],
        event_id: ["can't be blank"]
      } = errors_on(changeset)
    end

    test "allows free tickets (base_price_cents = 0)" do
      event = insert(:event)

      attrs = %{
        title: "Free Ticket",
        base_price_cents: 0,
        minimum_price_cents: 0,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert changeset.valid?
    end

    test "validates base_price_cents cannot be negative" do
      event = insert(:event)

      attrs = %{
        title: "Negative Price Ticket",
        base_price_cents: -100,
        minimum_price_cents: 0,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{base_price_cents: ["cannot be negative"]} = errors_on(changeset)
    end

    test "validates minimum_price_cents cannot be negative" do
      event = insert(:event)

      attrs = %{
        title: "Negative Minimum Price Ticket",
        base_price_cents: 100,
        minimum_price_cents: -50,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{minimum_price_cents: ["cannot be negative"]} = errors_on(changeset)
    end

    test "validates flexible pricing: minimum_price_cents cannot be greater than base_price_cents" do
      event = insert(:event)

      attrs = %{
        title: "Invalid Flexible Ticket",
        base_price_cents: 1000,
        minimum_price_cents: 1500,
        pricing_model: "flexible",
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{minimum_price_cents: ["cannot be greater than base price"]} = errors_on(changeset)
    end

    test "validates suggested_price_cents cannot be negative" do
      event = insert(:event)

      attrs = %{
        title: "Negative Suggested Price Ticket",
        base_price_cents: 1000,
        minimum_price_cents: 500,
        suggested_price_cents: -100,
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      errors = errors_on(changeset)
      assert "cannot be negative" in errors.suggested_price_cents
    end

    test "validates pricing_model inclusion" do
      event = insert(:event)

      attrs = %{
        title: "Invalid Pricing Model Ticket",
        base_price_cents: 1000,
        minimum_price_cents: 1000,
        pricing_model: "invalid_model",
        currency: "usd",
        quantity: 100,
        event_id: event.id
      }

      changeset = Ticket.changeset(%Ticket{}, attrs)
      assert %{pricing_model: ["must be a valid pricing model"]} = errors_on(changeset)
    end

    test "validates quantity > 0" do
      event = insert(:event)

      attrs = %{
        title: "No Quantity Ticket",
        base_price_cents: 2500,
        minimum_price_cents: 2500,
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
        base_price_cents: 2500,
        minimum_price_cents: 2500,
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
        base_price_cents: 2500,
        minimum_price_cents: 2500,
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
        base_price_cents: 2500,
        minimum_price_cents: 2500,
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
        base_price_cents: 2500,
        minimum_price_cents: 2500,
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

  describe "pricing helper functions" do
    test "effective_price/1 for fixed pricing model" do
      ticket = %Ticket{pricing_model: "fixed", base_price_cents: 2500}
      assert Ticket.effective_price(ticket) == 2500
    end

    test "effective_price/1 for flexible pricing model" do
      ticket = %Ticket{pricing_model: "flexible", minimum_price_cents: 1000, base_price_cents: 2500}
      assert Ticket.effective_price(ticket) == 1000
    end

    test "effective_price/1 for dynamic pricing model" do
      ticket = %Ticket{pricing_model: "dynamic", base_price_cents: 3000}
      assert Ticket.effective_price(ticket) == 3000
    end

    test "max_flexible_price/1 returns base price for flexible tickets" do
      ticket = %Ticket{pricing_model: "flexible", base_price_cents: 2500}
      assert Ticket.max_flexible_price(ticket) == 2500
    end

    test "max_flexible_price/1 returns nil for non-flexible tickets" do
      ticket = %Ticket{pricing_model: "fixed", base_price_cents: 2500}
      assert Ticket.max_flexible_price(ticket) == nil
    end

    test "flexible_pricing?/1 returns true for flexible tickets" do
      ticket = %Ticket{pricing_model: "flexible"}
      assert Ticket.flexible_pricing?(ticket) == true
    end

    test "flexible_pricing?/1 returns false for fixed tickets" do
      ticket = %Ticket{pricing_model: "fixed"}
      assert Ticket.flexible_pricing?(ticket) == false
    end

    test "suggested_price/1 returns explicit suggested price" do
      ticket = %Ticket{suggested_price_cents: 1500}
      assert Ticket.suggested_price(ticket) == 1500
    end

    test "suggested_price/1 returns base price for flexible tickets without explicit suggestion" do
      ticket = %Ticket{pricing_model: "flexible", base_price_cents: 2000, suggested_price_cents: nil}
      assert Ticket.suggested_price(ticket) == 2000
    end

    test "suggested_price/1 returns nil for fixed tickets without explicit suggestion" do
      ticket = %Ticket{pricing_model: "fixed", base_price_cents: 2000, suggested_price_cents: nil}
      assert Ticket.suggested_price(ticket) == nil
    end
  end

  describe "on_sale?/1" do
    test "returns true when starts_at is nil" do
      now = DateTime.utc_now()
      ticket = %Ticket{starts_at: nil, ends_at: DateTime.add(now, 3600, :second)}
      assert Ticket.on_sale?(ticket)
    end

    test "returns true when current time is after starts_at and ends_at is nil" do
      now = DateTime.utc_now()
      ticket = %Ticket{starts_at: DateTime.add(now, -3600, :second), ends_at: nil}
      assert Ticket.on_sale?(ticket)
    end

    test "returns true when current time is within availability window" do
      now = DateTime.utc_now()
      ticket = %Ticket{
        starts_at: DateTime.add(now, -3600, :second),
        ends_at: DateTime.add(now, 3600, :second)
      }
      assert Ticket.on_sale?(ticket)
    end

    test "returns false when current time is before starts_at" do
      now = DateTime.utc_now()
      ticket = %Ticket{
        starts_at: DateTime.add(now, 3600, :second),
        ends_at: DateTime.add(now, 7200, :second)
      }
      refute Ticket.on_sale?(ticket)
    end

    test "returns false when current time is after ends_at" do
      now = DateTime.utc_now()
      ticket = %Ticket{
        starts_at: DateTime.add(now, -7200, :second),
        ends_at: DateTime.add(now, -3600, :second)
      }
      refute Ticket.on_sale?(ticket)
    end
  end
end
