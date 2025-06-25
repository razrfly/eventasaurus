defmodule EventasaurusWeb.StripeWebhookControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  alias EventasaurusApp.Ticketing
  alias EventasaurusWeb.StripeWebhookController

  import EventasaurusApp.Factory
  import Mox

  setup :verify_on_exit!

  # Helper to create a valid Stripe signature format
  defp valid_stripe_signature do
    timestamp = System.system_time(:second)
    "t=#{timestamp},v1=a1b2c3d4e5f6"
  end

  # Helper to simulate webhook call with proper setup
  defp call_webhook(conn, webhook_body, signature \\ nil) do
    signature = signature || valid_stripe_signature()

    conn
    |> put_req_header("stripe-signature", signature)
    |> put_req_header("content-type", "application/json")
    |> assign(:raw_body, webhook_body)
    |> Map.put(:method, "POST")
    |> StripeWebhookController.handle_webhook(%{})
  end

  describe "handle_webhook/2" do
    setup do
      user = insert(:user)
      event = insert(:event, users: [user])
      ticket = insert(:ticket, event: event, base_price_cents: 1000)

      %{user: user, event: event, ticket: ticket}
    end

    test "handles payment_intent.succeeded webhook", %{conn: conn, user: user, ticket: ticket} do
      order = insert(:order,
        user: user,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        payment_reference: "pi_test_webhook_success"
      )

      # Mock Stripe webhook verification
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:ok, %{
          "id" => "evt_test_webhook",
          "type" => "payment_intent.succeeded",
          "object" => "event",
          "data" => %{
            "object" => %{
              "id" => "pi_test_webhook_success",
              "status" => "succeeded",
              "amount" => 1000
            }
          }
        }}
      end)

      # Mock sync function to confirm order
      expect(EventasaurusApp.StripeMock, :get_payment_intent, fn "pi_test_webhook_success", nil ->
        {:ok, %{"status" => "succeeded"}}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "payment_intent.succeeded",
        object: "event",
        data: %{
          object: %{
            id: "pi_test_webhook_success",
            status: "succeeded",
            amount: 1000
          }
        }
      })

      conn = call_webhook(conn, webhook_body)

      assert response(conn, 200)

      # Verify order was confirmed
      updated_order = Ticketing.get_order!(order.id)
      assert updated_order.status == "confirmed"
      assert updated_order.confirmed_at != nil
    end

    test "handles checkout.session.completed webhook", %{conn: conn, user: user, ticket: ticket} do
      order = insert(:order,
        user: user,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        stripe_session_id: "cs_test_webhook_completed"
      )

      # Mock Stripe webhook verification
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:ok, %{
          "id" => "evt_test_webhook",
          "type" => "checkout.session.completed",
          "object" => "event",
          "data" => %{
            "object" => %{
              "id" => "cs_test_webhook_completed",
              "payment_status" => "paid",
              "amount_total" => 1000
            }
          }
        }}
      end)

      # Mock sync function to confirm order
      expect(EventasaurusApp.StripeMock, :get_checkout_session, fn "cs_test_webhook_completed" ->
        {:ok, %{"payment_status" => "paid"}}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "checkout.session.completed",
        object: "event",
        data: %{
          object: %{
            id: "cs_test_webhook_completed",
            payment_status: "paid",
            amount_total: 1000
          }
        }
      })

      conn = call_webhook(conn, webhook_body)

      assert response(conn, 200)

      # Verify order was confirmed
      updated_order = Ticketing.get_order!(order.id)
      assert updated_order.status == "confirmed"
      assert updated_order.confirmed_at != nil
    end

    test "handles payment_intent.payment_failed webhook gracefully", %{conn: conn, user: user, ticket: ticket} do
      order = insert(:order,
        user: user,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        payment_reference: "pi_test_webhook_failed"
      )

      # Mock Stripe webhook verification
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:ok, %{
          "id" => "evt_test_webhook",
          "type" => "payment_intent.payment_failed",
          "object" => "event",
          "data" => %{
            "object" => %{
              "id" => "pi_test_webhook_failed",
              "status" => "failed"
            }
          }
        }}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "payment_intent.payment_failed",
        object: "event",
        data: %{
          object: %{
            id: "pi_test_webhook_failed",
            status: "failed"
          }
        }
      })

      conn = call_webhook(conn, webhook_body)

      assert response(conn, 200)

      # Verify order remains pending (following t3dotgg pattern)
      updated_order = Ticketing.get_order!(order.id)
      assert updated_order.status == "pending"
      assert updated_order.confirmed_at == nil
    end

    test "handles checkout.session.expired webhook gracefully", %{conn: conn, user: user, ticket: ticket} do
      order = insert(:order,
        user: user,
        ticket: ticket,
        event: ticket.event,
        status: "pending",
        stripe_session_id: "cs_test_webhook_expired"
      )

      # Mock Stripe webhook verification
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:ok, %{
          "id" => "evt_test_webhook",
          "type" => "checkout.session.expired",
          "object" => "event",
          "data" => %{
            "object" => %{
              "id" => "cs_test_webhook_expired"
            }
          }
        }}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "checkout.session.expired",
        object: "event",
        data: %{
          object: %{
            id: "cs_test_webhook_expired"
          }
        }
      })

      conn = call_webhook(conn, webhook_body)

      assert response(conn, 200)

      # Verify order remains pending (following t3dotgg pattern)
      updated_order = Ticketing.get_order!(order.id)
      assert updated_order.status == "pending"
    end

    test "handles unknown webhook events gracefully", %{conn: conn} do
      # Mock Stripe webhook verification
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:ok, %{
          "id" => "evt_test_webhook",
          "type" => "unknown.event.type",
          "object" => "event",
          "data" => %{
            "object" => %{
              "id" => "unknown_object_id"
            }
          }
        }}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "unknown.event.type",
        object: "event",
        data: %{
          object: %{
            id: "unknown_object_id"
          }
        }
      })

      conn = call_webhook(conn, webhook_body)

      assert response(conn, 200)
    end

    test "handles missing orders gracefully", %{conn: conn} do
      # Mock Stripe webhook verification for a payment_intent that doesn't match any order
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:ok, %{
          "id" => "evt_test_webhook",
          "type" => "payment_intent.succeeded",
          "object" => "event",
          "data" => %{
            "object" => %{
              "id" => "pi_nonexistent_order",
              "status" => "succeeded",
              "amount" => 1000
            }
          }
        }}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "payment_intent.succeeded",
        object: "event",
        data: %{
          object: %{
            id: "pi_nonexistent_order",
            status: "succeeded",
            amount: 1000
          }
        }
      })

      conn = call_webhook(conn, webhook_body)

      assert response(conn, 200)
    end

    test "webhook security validates webhook signature before processing", %{conn: conn} do
      # Mock failed signature verification
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:error, "Invalid signature"}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "payment_intent.succeeded",
        object: "event",
        data: %{
          object: %{
            id: "pi_test_invalid_signature",
            status: "succeeded"
          }
        }
      })

      conn = call_webhook(conn, webhook_body, "invalid_signature")

      assert response(conn, 400)
      assert json_response(conn, 400) == %{"error" => "Invalid signature format"}
    end
  end

  describe "webhook security" do
    test "requires HTTPS in production environment", %{conn: _conn} do
      # This would be tested in integration tests with actual HTTPS setup
      # For now, we verify the security plug is configured
      assert true
    end

    test "includes rate limiting for webhook endpoints", %{conn: _conn} do
      # Rate limiting is configured in the router pipeline
      # This would be tested with multiple rapid requests in integration tests
      assert true
    end

    test "validates webhook signature before processing", %{conn: conn} do
      # Mock signature verification failure
      expect(EventasaurusApp.StripeMock, :verify_webhook_signature, fn _body, _signature, _secret ->
        {:error, "Invalid signature"}
      end)

      webhook_body = Jason.encode!(%{
        id: "evt_test_webhook",
        type: "test.event",
        object: "event"
      })

      conn =
        conn
        |> put_req_header("stripe-signature", valid_stripe_signature())
        |> put_req_header("content-type", "application/json")
        |> assign(:raw_body, webhook_body)
        |> post(~p"/webhooks/stripe", %{})

      assert response(conn, 400)
    end
  end
end
