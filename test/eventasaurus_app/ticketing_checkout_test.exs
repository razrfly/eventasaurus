defmodule EventasaurusApp.TicketingCheckoutTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Ticketing
  alias EventasaurusApp.Events.{Event, Ticket, Order}
  alias EventasaurusApp.Accounts.User

  import EventasaurusApp.Factory
  import Mox

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "create_checkout_session/3" do
    setup do
      user = insert(:user)
      event = insert(:event, users: [user])

      # Create a Stripe Connect account for the event organizer
      connect_account = insert(:stripe_connect_account, user: user)

      %{user: user, event: event, connect_account: connect_account}
    end

    test "creates checkout session for fixed pricing ticket", %{user: user, event: event} do
      # Mock Stripe checkout session creation for this test
      expect(EventasaurusApp.StripeMock, :create_checkout_session, fn _params ->
        {:ok, %{
          "id" => "cs_test_mock_session",
          "url" => "https://checkout.stripe.com/pay/cs_test_mock_session"
        }}
      end)

      ticket = insert(:ticket,
        event: event,
        base_price_cents: 2500,
        pricing_model: "fixed",
        quantity: 100,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      assert {:ok, result} = Ticketing.create_checkout_session(user, ticket, %{quantity: 2})

      assert %{order: order, checkout_url: checkout_url, session_id: session_id} = result
      assert order.user_id == user.id
      assert order.ticket_id == ticket.id
      assert order.quantity == 2
      assert order.subtotal_cents == 5000  # 2 * 2500
      # Total includes 10% tax: 5000 + 500 = 5500
      assert order.total_cents == 5500
      assert order.status == "pending"
      assert order.stripe_session_id == session_id
      assert is_binary(checkout_url)
      assert String.contains?(checkout_url, "checkout.stripe.com")
    end

    test "creates checkout session for flexible pricing ticket with custom price", %{user: user, event: event} do
      # Mock Stripe checkout session creation for this test
      expect(EventasaurusApp.StripeMock, :create_checkout_session, fn _params ->
        {:ok, %{
          "id" => "cs_test_mock_session",
          "url" => "https://checkout.stripe.com/pay/cs_test_mock_session"
        }}
      end)

      ticket = insert(:ticket,
        event: event,
        base_price_cents: 2000,
        minimum_price_cents: 1000,
        suggested_price_cents: 2000,
        pricing_model: "flexible",
        quantity: 50,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      custom_price = 2500  # Above minimum

      assert {:ok, result} = Ticketing.create_checkout_session(user, ticket, %{
        quantity: 1,
        custom_price_cents: custom_price
      })

      assert %{order: order} = result
      assert order.subtotal_cents == custom_price
      # Total includes 10% tax, so 2500 + 250 = 2750
      assert order.total_cents == 2750

      # Check pricing snapshot
      assert order.pricing_snapshot["custom_price_cents"] == custom_price
      assert order.pricing_snapshot["pricing_model"] == "flexible"
      assert order.pricing_snapshot["base_price_cents"] == 2000
      assert order.pricing_snapshot["minimum_price_cents"] == 1000
    end

    test "creates checkout session with tips", %{user: user, event: event} do
      # Mock Stripe checkout session creation for this test
      expect(EventasaurusApp.StripeMock, :create_checkout_session, fn _params ->
        {:ok, %{
          "id" => "cs_test_mock_session",
          "url" => "https://checkout.stripe.com/pay/cs_test_mock_session"
        }}
      end)

      ticket = insert(:ticket,
        event: event,
        base_price_cents: 1500,
        pricing_model: "fixed",
        tippable: true,
        quantity: 25,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      tip_amount = 300

      assert {:ok, result} = Ticketing.create_checkout_session(user, ticket, %{
        quantity: 1,
        tip_cents: tip_amount
      })

      assert %{order: order} = result
      assert order.subtotal_cents == 1800  # 1500 + 300 tip
      assert order.total_cents == 1950  # 1800 + 10% tax on ticket price only (150)

      # Check pricing snapshot includes tip
      assert order.pricing_snapshot["tip_cents"] == tip_amount
      assert order.pricing_snapshot["ticket_tippable"] == true
    end

    test "validates minimum price for flexible pricing", %{user: user, event: event} do
      ticket = insert(:ticket,
        event: event,
        base_price_cents: 2000,
        minimum_price_cents: 1000,
        pricing_model: "flexible",
        quantity: 10,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      # Price below minimum should fail
      assert {:error, :price_below_minimum} = Ticketing.create_checkout_session(user, ticket, %{
        quantity: 1,
        custom_price_cents: 500  # Below minimum of 1000
      })
    end

    test "validates ticket availability", %{user: user, event: event} do
      ticket = insert(:ticket,
        event: event,
        base_price_cents: 1000,
        quantity: 2,  # Only 2 tickets available
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      # Requesting more than available should fail
      assert {:error, :ticket_unavailable} = Ticketing.create_checkout_session(user, ticket, %{
        quantity: 5  # More than the 2 available
      })
    end

    test "requires custom price for flexible pricing tickets", %{user: user, event: event} do
      ticket = insert(:ticket,
        event: event,
        base_price_cents: 2000,
        minimum_price_cents: 1000,
        pricing_model: "flexible",
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      # No custom price provided for flexible pricing
      assert {:error, :custom_price_required} = Ticketing.create_checkout_session(user, ticket, %{
        quantity: 1
        # Missing custom_price_cents
      })
    end

    test "fails when event organizer has no Stripe account", %{event: event} do
      # Create a new event with an organizer who doesn't have a Stripe Connect account
      organizer_without_stripe = insert(:user)
      event_without_stripe = insert(:event, users: [organizer_without_stripe])

      # Create a user to purchase the ticket (different from organizer)
      purchaser = insert(:user)

      ticket = insert(:ticket,
        event: event_without_stripe,
        base_price_cents: 1000,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      assert {:error, :no_stripe_account} = Ticketing.create_checkout_session(purchaser, ticket, %{
        quantity: 1
      })
    end
  end

  describe "sync_order_with_stripe/1" do
    setup do
      # Create a separate user for purchasing to avoid organizer-participant conflict
      organizer = insert(:user)
      purchaser = insert(:user)
      event = insert(:event, users: [organizer])
      ticket = insert(:ticket, event: event, base_price_cents: 1000)

      %{organizer: organizer, purchaser: purchaser, event: event, ticket: ticket}
    end

    test "confirms order when payment intent is succeeded", %{purchaser: purchaser, ticket: ticket} do
      order = insert(:order,
        user: purchaser,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        payment_reference: "pi_test_succeeded"
      )

      # Mock successful payment intent response
      expect(EventasaurusApp.StripeMock, :get_payment_intent, fn "pi_test_succeeded", nil ->
        {:ok, %{"status" => "succeeded"}}
      end)

      assert {:ok, updated_order} = Ticketing.sync_order_with_stripe(order)
      assert updated_order.status == "confirmed"
      assert updated_order.confirmed_at != nil
    end

    test "keeps order pending when payment intent is not succeeded", %{purchaser: purchaser, ticket: ticket} do
      order = insert(:order,
        user: purchaser,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        payment_reference: "pi_test_pending"
      )

      # Mock pending payment intent response
      expect(EventasaurusApp.StripeMock, :get_payment_intent, fn "pi_test_pending", nil ->
        {:ok, %{"status" => "requires_payment_method"}}
      end)

      assert {:ok, updated_order} = Ticketing.sync_order_with_stripe(order)
      assert updated_order.status == "pending"
      assert updated_order.confirmed_at == nil
    end

    test "confirms order when checkout session is paid", %{purchaser: purchaser, ticket: ticket} do
      order = insert(:order,
        user: purchaser,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        stripe_session_id: "cs_test_paid"
      )

      # Mock successful checkout session response
      expect(EventasaurusApp.StripeMock, :get_checkout_session, fn "cs_test_paid" ->
        {:ok, %{"payment_status" => "paid"}}
      end)

      assert {:ok, updated_order} = Ticketing.sync_order_with_stripe(order)
      assert updated_order.status == "confirmed"
      assert updated_order.confirmed_at != nil
    end

    test "handles Stripe API errors gracefully", %{purchaser: purchaser, ticket: ticket} do
      order = insert(:order,
        user: purchaser,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        payment_reference: "pi_test_error"
      )

      # Mock Stripe API error
      expect(EventasaurusApp.StripeMock, :get_payment_intent, fn "pi_test_error", nil ->
        {:error, "Payment intent not found"}
      end)

      # Should not fail, just keep order pending when sync fails
      assert {:ok, updated_order} = Ticketing.sync_order_with_stripe(order)
      assert updated_order.status == "pending"
    end

    test "does nothing for already confirmed orders", %{purchaser: purchaser, ticket: ticket} do
      order = insert(:order,
        user: purchaser,
        ticket: ticket,
        event: ticket.event,
        status: "confirmed",
        confirmed_at: DateTime.utc_now(),
        payment_reference: "pi_test_already_confirmed"
      )

      # Should not call Stripe API for already confirmed orders
      assert {:ok, updated_order} = Ticketing.sync_order_with_stripe(order)
      assert updated_order.status == "confirmed"
      assert updated_order == order  # No changes
    end
  end

  describe "order pricing snapshots" do
    test "stores complete pricing information for historical tracking" do
      organizer = insert(:user)
      purchaser = insert(:user)
      event = insert(:event, users: [organizer])
      _connect_account = insert(:stripe_connect_account, user: organizer)

      # Mock Stripe checkout session creation
      expect(EventasaurusApp.StripeMock, :create_checkout_session, fn _params ->
        {:ok, %{
          "id" => "cs_test_mock_session",
          "url" => "https://checkout.stripe.com/pay/cs_test_mock_session"
        }}
      end)

      ticket = insert(:ticket,
        event: event,
        base_price_cents: 2000,
        minimum_price_cents: 1000,
        suggested_price_cents: 2000,
        pricing_model: "flexible",
        tippable: true,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),  # Make sure ticket is on sale
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      custom_price = 2500
      tip_amount = 300

      assert {:ok, result} = Ticketing.create_checkout_session(purchaser, ticket, %{
        quantity: 1,
        custom_price_cents: custom_price,
        tip_cents: tip_amount
      })

      order = result.order
      snapshot = order.pricing_snapshot

      # Verify all pricing information is captured
      assert snapshot["base_price_cents"] == 2000
      assert snapshot["minimum_price_cents"] == 1000
      assert snapshot["suggested_price_cents"] == 2000
      assert snapshot["custom_price_cents"] == custom_price
      assert snapshot["tip_cents"] == tip_amount
      assert snapshot["pricing_model"] == "flexible"
      assert snapshot["ticket_tippable"] == true
    end

    test "order helper functions work with pricing snapshots" do
      order = insert(:order,
        pricing_snapshot: %{
          "base_price_cents" => 1500,
          "custom_price_cents" => 2000,
          "tip_cents" => 250,
          "pricing_model" => "flexible",
          "ticket_tippable" => true
        }
      )

      alias EventasaurusApp.Events.Order

      assert Order.get_effective_price_from_snapshot(order) == 2000
      assert Order.get_tip_from_snapshot(order) == 250
      assert Order.flexible_pricing?(order) == true
      assert Order.has_tip?(order) == true
    end
  end

  describe "backwards compatibility" do
    test "works with existing orders without pricing snapshots" do
      user = insert(:user)
      event = insert(:event, users: [user])
      ticket = insert(:ticket, event: event, base_price_cents: 1000)

      # Create order without pricing snapshot (legacy order)
      order = insert(:order,
        user: user,
        ticket: ticket,
        event: event,
        pricing_snapshot: nil
      )

      alias EventasaurusApp.Events.Order

      # Helper functions should handle nil snapshots gracefully
      assert Order.get_effective_price_from_snapshot(order) == 0
      assert Order.get_tip_from_snapshot(order) == 0
      assert Order.flexible_pricing?(order) == false
      assert Order.has_tip?(order) == false
    end

    test "existing ticket creation still works with new pricing fields" do
      user = insert(:user)
      event = insert(:event, users: [user])

      # Create ticket with only basic pricing (legacy style)
      assert {:ok, ticket} = Ticketing.create_ticket(event, %{
        title: "Basic Ticket",
        base_price_cents: 1500,
        quantity: 50
      })

      assert ticket.base_price_cents == 1500
      assert ticket.pricing_model == "fixed"  # Default
      assert ticket.minimum_price_cents == 0  # Default value, not nil
      assert ticket.suggested_price_cents == nil
      assert ticket.tippable == false  # Default
    end
  end
end
