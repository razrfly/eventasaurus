defmodule EventasaurusWeb.TicketingSmokeTest do
  @moduledoc """
  High-level smoke tests for ticketing functionality.
  These tests verify core ticketing flows work without being brittle to UI changes.
  """

  use EventasaurusWeb.ConnCase
  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  alias EventasaurusApp.{Events, Ticketing}

  describe "basic ticketing smoke tests" do
    setup do
      organizer = insert(:user)
      user = insert(:user)

      event =
        insert(:event,
          users: [organizer],
          is_ticketed: true,
          status: :confirmed
        )

      ticket =
        insert(:ticket,
          event: event,
          quantity: 50,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      %{user: user, event: event, ticket: ticket, organizer: organizer}
    end

    test "can view event page", %{conn: conn, event: event, user: user} do
      # Should be able to load event page (might redirect but shouldn't error)
      conn = log_in_user(conn, user)
      conn = get(conn, ~p"/events/#{event.slug}")
      # Just verify we get a response, don't worry about exact status
      assert conn.status in [200, 302]
      assert is_binary(conn.resp_body)
    end

    test "can create order programmatically", %{user: user, ticket: ticket} do
      # Core business logic should work
      assert {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 1})
      assert order.status == "pending"
      assert order.quantity == 1
    end

    test "can confirm order and create participant", %{user: user, ticket: ticket, event: event} do
      # Full order lifecycle should work
      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 1})
      {:ok, confirmed_order} = Ticketing.confirm_order(order, "test_payment_id")

      assert confirmed_order.status == "confirmed"
      assert confirmed_order.confirmed_at != nil

      # Should create participant
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.role == :ticket_holder
    end

    test "very low cost tickets work", %{user: user, event: event} do
      # Very low cost tickets should work (avoiding 0 due to validation)
      low_cost_ticket =
        insert(:ticket,
          event: event,
          # 1 cent
          base_price_cents: 1,
          minimum_price_cents: 1,
          quantity: 100,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      {:ok, order} = Ticketing.create_order(user, low_cost_ticket, %{quantity: 1})
      {:ok, confirmed_order} = Ticketing.confirm_order(order, "test_payment")

      assert confirmed_order.status == "confirmed"
      assert confirmed_order.subtotal_cents == 1
    end

    test "sold out logic works", %{user: user, event: event} do
      # Create ticket with 1 quantity, then sell it out
      limited_ticket =
        insert(:ticket,
          event: event,
          quantity: 1,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # First order should work
      {:ok, _order1} = Ticketing.create_order(user, limited_ticket, %{quantity: 1})

      # Second order should fail
      user2 = insert(:user)
      assert {:error, _reason} = Ticketing.create_order(user2, limited_ticket, %{quantity: 1})
    end
  end

  describe "flexible pricing smoke tests" do
    test "flexible pricing tickets accept custom amounts" do
      event = insert(:event, is_ticketed: true)
      user = insert(:user)

      flexible_ticket =
        insert(:ticket,
          event: event,
          pricing_model: "flexible",
          base_price_cents: 5000,
          minimum_price_cents: 1000,
          suggested_price_cents: 3000,
          quantity: 100,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # Should accept amount between min and max
      {:ok, order} =
        Ticketing.create_order(user, flexible_ticket, %{
          quantity: 1,
          custom_price_cents: 2500
        })

      assert order.subtotal_cents == 2500
    end
  end

  describe "dashboard smoke tests" do
    setup do
      user = insert(:user)
      event = insert(:event, is_ticketed: true)

      ticket =
        insert(:ticket,
          event: event,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      %{user: user, event: event, ticket: ticket}
    end

    test "user can view their orders", %{conn: conn, user: user, ticket: ticket} do
      # Create a confirmed order
      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 1})
      {:ok, _confirmed} = Ticketing.confirm_order(order, "test_payment")

      # Should be able to view dashboard
      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # Basic smoke test - just verify dashboard loads and contains expected content
      assert html =~ "Dashboard"
      # Dashboard should have some content (very generic check)
      assert String.length(html) > 1000
    end
  end
end
