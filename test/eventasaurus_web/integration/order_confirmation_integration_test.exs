defmodule EventasaurusWeb.OrderConfirmationIntegrationTest do
  use EventasaurusWeb.ConnCase
  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory
  import Mox

  alias EventasaurusApp.{Events, Ticketing}

  setup :verify_on_exit!

  describe "order confirmation integration" do
    setup do
      # Create event organizer
      organizer = insert(:user, email: "organizer@example.com")

      # Create event
      event =
        insert(:event,
          users: [organizer],
          title: "Tech Conference 2024",
          is_ticketed: true,
          status: :confirmed
        )

      # Create ticket (make sure it's currently on sale)
      ticket =
        insert(:ticket,
          event: event,
          title: "General Admission",
          base_price_cents: 5000,
          quantity: 100,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # Create regular user
      user = insert(:user, email: "attendee@example.com")

      # Create Stripe Connect account for organizer
      _connect_account =
        insert(:stripe_connect_account,
          user: organizer,
          stripe_user_id: "acct_test_organizer"
        )

      %{user: user, event: event, ticket: ticket, organizer: organizer}
    end

    test "order confirmation creates participant with proper metadata", %{
      user: user,
      event: event,
      ticket: ticket
    } do
      # Create order
      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 2})
      assert order.status == "pending"

      # Confirm the order (no Stripe mocking needed for direct confirmation)
      {:ok, confirmed_order} = Ticketing.confirm_order(order, "pi_test_success")

      # Verify order confirmation
      assert confirmed_order.status == "confirmed"
      assert confirmed_order.confirmed_at != nil
      assert DateTime.diff(confirmed_order.confirmed_at, DateTime.utc_now(), :second) < 10

      # Verify participant creation
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.role == :ticket_holder
      assert participant.status == :confirmed_with_order
      assert participant.source == "ticket_purchase"

      # Verify participant metadata
      assert participant.metadata["order_id"] == confirmed_order.id
      assert participant.metadata["ticket_id"] == ticket.id
      assert participant.metadata["quantity"] == 2
    end

    test "checkout page loads correctly with ticket selection", %{
      conn: conn,
      user: user,
      event: event,
      ticket: ticket
    } do
      conn = log_in_user(conn, user)

      # Load checkout page with pre-selected ticket
      {:ok, _checkout_view, html} =
        live(conn, "/events/#{event.slug}/checkout?#{URI.encode_query(%{"#{ticket.id}" => 1})}")

      # Verify page content
      assert html =~ "Checkout"
      assert html =~ "Tech Conference 2024"
      assert html =~ "General Admission"
      assert html =~ "$50.00"
      assert html =~ "Proceed to Payment"
    end

    test "payment page loads correctly for valid order", %{
      conn: conn,
      user: user,
      event: _event,
      ticket: ticket
    } do
      conn = log_in_user(conn, user)

      # Create a pending order
      {:ok, order} = Ticketing.create_order(user, ticket, %{quantity: 1})

      # Load payment page
      {:ok, _payment_view, html} =
        live(
          conn,
          "/checkout/payment?order_id=#{order.id}&payment_intent=pi_test_intent&client_secret=pi_test_secret"
        )

      # Verify page content
      assert html =~ "Complete Payment"
      assert html =~ "Tech Conference 2024"
      assert html =~ "General Admission"
      # Including tax
      assert html =~ "Pay $55.00"
    end

    test "participant upgrade flow for existing invitee", %{event: event, ticket: ticket} do
      # Create a user who was previously invited
      invitee_user = insert(:user, email: "invitee@example.com")

      # Create existing participant as invitee
      {:ok, existing_participant} =
        Events.create_event_participant(%{
          event_id: event.id,
          user_id: invitee_user.id,
          role: :invitee,
          status: :pending,
          source: "manual_invite",
          metadata: %{
            "invited_by" => "organizer@example.com",
            "invitation_date" => "2024-01-15",
            "custom_note" => "VIP guest"
          }
        })

      # Create and confirm order
      {:ok, order} = Ticketing.create_order(invitee_user, ticket, %{quantity: 1})

      # Confirm order (no Stripe mocking needed for direct confirmation)
      {:ok, confirmed_order} = Ticketing.confirm_order(order, "pi_upgrade_test")

      # Verify participant was upgraded, not duplicated
      updated_participant = Events.get_event_participant_by_event_and_user(event, invitee_user)
      # Same record
      assert updated_participant.id == existing_participant.id
      # Upgraded
      assert updated_participant.role == :ticket_holder
      # Upgraded
      assert updated_participant.status == :confirmed_with_order
      # Original preserved
      assert updated_participant.source == "manual_invite"

      # Verify metadata was merged correctly
      # Original
      assert updated_participant.metadata["invited_by"] == "organizer@example.com"
      # Original
      assert updated_participant.metadata["custom_note"] == "VIP guest"
      # New
      assert updated_participant.metadata["order_id"] == confirmed_order.id
      # New
      assert updated_participant.metadata["ticket_id"] == ticket.id

      # Ensure no duplicate participants
      all_participants = Events.list_event_participants_for_event(event)
      invitee_participants = Enum.filter(all_participants, &(&1.user_id == invitee_user.id))
      assert length(invitee_participants) == 1
    end

    test "concurrent order attempts for limited tickets", %{event: event} do
      # Create ticket with limited quantity (make sure it's currently on sale)
      limited_ticket =
        insert(:ticket,
          event: event,
          # Only 2 tickets available
          quantity: 2,
          base_price_cents: 1000,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # Create two users
      user1 = insert(:user, email: "user1@example.com")
      user2 = insert(:user, email: "user2@example.com")

      # Both users try to buy 2 tickets each (total 4, but only 2 available)
      tasks = [
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(EventasaurusApp.Repo, self(), self())

          case Ticketing.create_order(user1, limited_ticket, %{quantity: 2}) do
            {:ok, order1} ->
              Ticketing.confirm_order(order1, "pi_user1_test")

            {:error, reason} ->
              {:error, reason}
          end
        end),
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(EventasaurusApp.Repo, self(), self())
          # Small delay to create race condition
          Process.sleep(50)

          case Ticketing.create_order(user2, limited_ticket, %{quantity: 2}) do
            {:ok, order2} ->
              Ticketing.confirm_order(order2, "pi_user2_test")

            {:error, reason} ->
              {:error, reason}
          end
        end)
      ]

      results = Task.await_many(tasks, 5000)

      # One should succeed, one should fail due to insufficient tickets
      success_count =
        Enum.count(results, fn
          {:ok, _order} -> true
          _ -> false
        end)

      error_count =
        Enum.count(results, fn
          {:error, _reason} -> true
          _ -> false
        end)

      assert success_count + error_count == 2
      # At least one should succeed
      assert success_count >= 1

      # Verify ticket quantity is respected
      confirmed_orders =
        Ticketing.list_orders_for_event(limited_ticket.event_id)
        |> Enum.filter(&(&1.status == "confirmed" and &1.ticket_id == limited_ticket.id))

      total_confirmed_quantity = Enum.sum(Enum.map(confirmed_orders, & &1.quantity))
      assert total_confirmed_quantity <= limited_ticket.quantity
    end

    test "order confirmation with complex event setup", %{user: user} do
      # Create event with multiple organizers
      organizer1 = insert(:user, email: "org1@example.com")
      organizer2 = insert(:user, email: "org2@example.com")

      complex_event =
        insert(:event,
          users: [organizer1, organizer2],
          title: "Multi-Day Conference",
          is_ticketed: true,
          status: :confirmed
        )

      # Multiple ticket types (make sure they're currently on sale)
      _early_bird =
        insert(:ticket,
          event: complex_event,
          title: "Early Bird",
          base_price_cents: 15000,
          quantity: 50,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      vip_ticket =
        insert(:ticket,
          event: complex_event,
          title: "VIP Pass",
          base_price_cents: 25000,
          quantity: 20,
          starts_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
        )

      # Create Stripe Connect for organizer
      _connect_account = insert(:stripe_connect_account, user: organizer1)

      # User buys VIP ticket
      {:ok, order} = Ticketing.create_order(user, vip_ticket, %{quantity: 1})

      # Confirm order (no Stripe mocking needed for direct confirmation)
      {:ok, confirmed_order} = Ticketing.confirm_order(order, "pi_vip_purchase")

      # Verify order confirmation
      assert confirmed_order.status == "confirmed"

      # Verify participant with VIP-specific metadata
      participant = Events.get_event_participant_by_event_and_user(complex_event, user)
      assert participant != nil
      assert participant.role == :ticket_holder
      assert participant.metadata["ticket_id"] == vip_ticket.id
      assert participant.metadata["quantity"] == 1

      # Verify event attendance tracking
      event_participants = Events.list_event_participants_for_event(complex_event)

      vip_participants =
        Enum.filter(event_participants, fn p ->
          p.metadata["ticket_id"] == vip_ticket.id
        end)

      assert length(vip_participants) == 1
    end
  end
end
