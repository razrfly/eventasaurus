defmodule EventasaurusWeb.CheckoutControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  alias EventasaurusApp.Ticketing
  alias EventasaurusApp.Events.Order

  import EventasaurusApp.Factory
  import Mox

  setup :verify_on_exit!

  describe "create_session/2" do
    setup do
      organizer = insert(:user)
      buyer = insert(:user)
      event = insert(:event, users: [organizer])
      _connect_account = insert(:stripe_connect_account, user: organizer)

      %{organizer: organizer, buyer: buyer, event: event}
    end

    test "creates checkout session for valid ticket", %{conn: conn, buyer: buyer, event: event} do
      ticket =
        insert(:ticket,
          event: event,
          base_price_cents: 2500,
          pricing_model: "fixed",
          quantity: 100,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # Mock successful Stripe checkout session creation
      expect(EventasaurusApp.StripeMock, :create_checkout_session, fn _params ->
        {:ok,
         %{
           "id" => "cs_test_session_123",
           "url" => "https://checkout.stripe.com/pay/cs_test_session_123"
         }}
      end)

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sessions", %{
          "ticket_id" => ticket.id,
          "quantity" => 2
        })

      assert %{
               "success" => true,
               "checkout_url" => checkout_url,
               "session_id" => session_id,
               "order_id" => order_id
             } = json_response(conn, 200)

      assert String.contains?(checkout_url, "checkout.stripe.com")
      assert session_id == "cs_test_session_123"
      assert is_binary(order_id)

      # Verify order was created
      order = Ticketing.get_order!(order_id)
      assert order.user_id == buyer.id
      assert order.ticket_id == ticket.id
      assert order.quantity == 2
      assert order.status == "pending"
      assert order.stripe_session_id == session_id
    end

    test "creates checkout session with flexible pricing", %{
      conn: conn,
      buyer: buyer,
      event: event
    } do
      ticket =
        insert(:ticket,
          event: event,
          base_price_cents: 2000,
          minimum_price_cents: 1000,
          pricing_model: "flexible",
          quantity: 50,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # Mock successful Stripe checkout session creation
      expect(EventasaurusApp.StripeMock, :create_checkout_session, fn _params ->
        {:ok,
         %{
           "id" => "cs_test_flexible_123",
           "url" => "https://checkout.stripe.com/pay/cs_test_flexible_123"
         }}
      end)

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sessions", %{
          "ticket_id" => ticket.id,
          "quantity" => 1,
          "custom_price_cents" => 2500
        })

      assert %{
               "success" => true,
               "checkout_url" => _checkout_url,
               "session_id" => _session_id,
               "order_id" => order_id
             } = json_response(conn, 200)

      # Verify order has correct pricing
      order = Ticketing.get_order!(order_id)
      assert order.subtotal_cents == 2500
      assert order.total_cents == 2500
      assert order.pricing_snapshot["custom_price_cents"] == 2500
      assert order.pricing_snapshot["pricing_model"] == "flexible"
    end

    test "creates checkout session with tips", %{conn: conn, buyer: buyer, event: event} do
      ticket =
        insert(:ticket,
          event: event,
          base_price_cents: 1500,
          pricing_model: "fixed",
          tippable: true,
          quantity: 25,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # Mock successful Stripe checkout session creation
      expect(EventasaurusApp.StripeMock, :create_checkout_session, fn _params ->
        {:ok,
         %{
           "id" => "cs_test_tip_123",
           "url" => "https://checkout.stripe.com/pay/cs_test_tip_123"
         }}
      end)

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sessions", %{
          "ticket_id" => ticket.id,
          "quantity" => 1,
          "tip_cents" => 300
        })

      assert %{
               "success" => true,
               "order_id" => order_id
             } = json_response(conn, 200)

      # Verify order includes tip
      order = Ticketing.get_order!(order_id)
      assert order.subtotal_cents == 1500
      # 1500 + 300 tip
      assert order.total_cents == 1800
      assert order.pricing_snapshot["tip_cents"] == 300
    end

    test "validates minimum price for flexible pricing", %{conn: conn, buyer: buyer, event: event} do
      ticket =
        insert(:ticket,
          event: event,
          base_price_cents: 2000,
          minimum_price_cents: 1000,
          pricing_model: "flexible",
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sessions", %{
          "ticket_id" => ticket.id,
          "quantity" => 1,
          # Below minimum
          "custom_price_cents" => 500
        })

      assert %{"error" => "Price is below minimum required amount"} = json_response(conn, 422)
    end

    test "requires authentication", %{conn: conn, event: event} do
      ticket = insert(:ticket, event: event, base_price_cents: 1000)

      conn =
        post(conn, ~p"/api/checkout/sessions", %{
          "ticket_id" => ticket.id,
          "quantity" => 1
        })

      assert json_response(conn, 401)
    end

    test "validates ticket existence", %{conn: conn, buyer: buyer} do
      # Use a non-existent integer ID
      nonexistent_id = 999_999

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sessions", %{
          "ticket_id" => nonexistent_id,
          "quantity" => 1
        })

      assert %{"error" => "Ticket not found"} = json_response(conn, 404)
    end

    test "validates ticket availability", %{conn: conn, buyer: buyer, event: event} do
      ticket =
        insert(:ticket,
          event: event,
          base_price_cents: 1000,
          # Only 2 available
          quantity: 2,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sessions", %{
          "ticket_id" => ticket.id,
          # More than available
          "quantity" => 5
        })

      assert %{"error" => "Ticket is no longer available"} = json_response(conn, 422)
    end
  end

  describe "sync_after_success/2" do
    setup do
      organizer = insert(:user)
      buyer = insert(:user)
      event = insert(:event, users: [organizer])
      _connect_account = insert(:stripe_connect_account, user: organizer)

      ticket =
        insert(:ticket,
          event: event,
          base_price_cents: 1000,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      %{organizer: organizer, buyer: buyer, event: event, ticket: ticket}
    end

    test "syncs order status after successful payment", %{
      conn: conn,
      buyer: buyer,
      ticket: ticket
    } do
      order =
        insert(:order,
          user: buyer,
          ticket: ticket,
          event: ticket.event,
          status: "pending",
          payment_reference: "pi_test_sync_success"
        )

      # Mock successful sync
      expect(EventasaurusApp.StripeMock, :get_payment_intent, fn "pi_test_sync_success", nil ->
        {:ok, %{"status" => "succeeded"}}
      end)

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sync/#{order.id}")

      assert %{
               "order_id" => order_id,
               "status" => "confirmed",
               "confirmed" => true
             } = json_response(conn, 200)

      assert order_id == order.id

      # Verify order was actually confirmed
      updated_order = Ticketing.get_order!(order.id)
      assert updated_order.status == "confirmed"
      assert updated_order.confirmed_at != nil
    end

    test "returns current status when payment is still pending", %{
      conn: conn,
      buyer: buyer,
      ticket: ticket
    } do
      order =
        insert(:order,
          user: buyer,
          ticket: ticket,
          event: ticket.event,
          status: "pending",
          payment_reference: "pi_test_sync_pending"
        )

      # Mock pending payment
      expect(EventasaurusApp.StripeMock, :get_payment_intent, fn "pi_test_sync_pending", nil ->
        {:ok, %{"status" => "requires_payment_method"}}
      end)

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sync/#{order.id}")

      assert %{
               "order_id" => order_id,
               "status" => "pending",
               "confirmed" => false
             } = json_response(conn, 200)

      assert order_id == order.id
    end

    test "requires authentication", %{conn: conn, buyer: buyer, ticket: ticket} do
      order =
        insert(:order,
          user: buyer,
          ticket: ticket,
          event: ticket.event,
          status: "pending"
        )

      conn = post(conn, ~p"/api/checkout/sync/#{order.id}")

      assert json_response(conn, 401)
    end

    test "validates order ownership", %{conn: conn, buyer: buyer, ticket: ticket} do
      other_user = insert(:user)

      order =
        insert(:order,
          # Different user
          user: other_user,
          ticket: ticket,
          event: ticket.event,
          status: "pending"
        )

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sync/#{order.id}")

      assert %{"error" => "Access denied"} = json_response(conn, 403)
    end

    test "handles nonexistent orders", %{conn: conn, buyer: buyer} do
      # Use a non-existent integer ID
      nonexistent_id = 999_999

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sync/#{nonexistent_id}")

      assert %{"error" => "Order not found"} = json_response(conn, 404)
    end

    test "handles Stripe API errors gracefully", %{conn: conn, buyer: buyer, ticket: ticket} do
      order =
        insert(:order,
          user: buyer,
          ticket: ticket,
          event: ticket.event,
          status: "pending",
          payment_reference: "pi_test_sync_error"
        )

      # Mock Stripe API error
      expect(EventasaurusApp.StripeMock, :get_payment_intent, fn "pi_test_sync_error", nil ->
        {:error, "Payment intent not found"}
      end)

      conn =
        conn
        |> setup_user_session(buyer)
        |> post(~p"/api/checkout/sync/#{order.id}")

      # Should still return current order status
      assert %{
               "order_id" => order_id,
               "status" => "pending",
               "confirmed" => false
             } = json_response(conn, 200)

      assert order_id == order.id
    end
  end

  describe "success/2" do
    setup do
      organizer = insert(:user)
      buyer = insert(:user)
      event = insert(:event, users: [organizer])
      _connect_account = insert(:stripe_connect_account, user: organizer)

      ticket =
        insert(:ticket,
          event: event,
          base_price_cents: 1000,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      %{organizer: organizer, buyer: buyer, event: event, ticket: ticket}
    end

    test "displays success page for valid order and session", %{
      conn: conn,
      buyer: buyer,
      ticket: ticket
    } do
      # Insert order with proper associations
      order =
        insert(:order,
          user: buyer,
          ticket: ticket,
          event: ticket.event,
          status: "confirmed",
          stripe_session_id: "cs_test_success_123"
        )

      # Reload with associations for the controller
      order = EventasaurusApp.Ticketing.get_order!(order.id)

      conn =
        conn
        |> setup_user_session(buyer)
        |> get(~p"/orders/#{order.id}/success?session_id=cs_test_success_123")

      assert html_response(conn, 200)
      assert conn.resp_body =~ "Payment Successful"
    end

    test "handles session ID mismatch", %{conn: conn, buyer: buyer, ticket: ticket} do
      order =
        insert(:order,
          user: buyer,
          ticket: ticket,
          event: ticket.event,
          status: "confirmed",
          stripe_session_id: "cs_test_correct_123"
        )

      conn =
        conn
        |> setup_user_session(buyer)
        |> get(~p"/orders/#{order.id}/success?session_id=cs_test_wrong_456")

      assert redirected_to(conn) == "/"
    end

    test "handles nonexistent orders", %{conn: conn, buyer: buyer} do
      # Use a non-existent integer ID
      nonexistent_id = 999_999

      conn =
        conn
        |> setup_user_session(buyer)
        |> get(~p"/orders/#{nonexistent_id}/success?session_id=cs_test_123")

      assert redirected_to(conn) == "/"
    end
  end

  describe "cancel/2" do
    test "handles checkout cancellation", %{conn: conn} do
      buyer = insert(:user)

      conn =
        conn
        |> setup_user_session(buyer)
        |> get(~p"/orders/cancel?session_id=cs_test_cancelled_123")

      assert redirected_to(conn) == "/"
    end
  end

  # Helper function to log in a user
  defp setup_user_session(conn, user) do
    log_in_user(conn, user)
  end
end
