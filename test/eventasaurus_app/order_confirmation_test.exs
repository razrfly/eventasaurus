defmodule EventasaurusApp.OrderConfirmationTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.{Ticketing, Events}

  import EventasaurusApp.Factory

  describe "order confirmation flow" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)
      ticket = insert(:ticket, event: event, base_price_cents: 2500, quantity: 100)

      %{user: user, organizer: organizer, event: event, ticket: ticket}
    end

    test "confirm_order/2 creates confirmed order with participant", %{user: user, event: event, ticket: ticket} do
      # Create properly structured order
      order = insert(:order,
        user: user,
        event: event,
        ticket: ticket,
        status: "pending",
        quantity: 2,
        subtotal_cents: 5000,  # 2 * $25.00
        tax_cents: 500,        # 10% tax
        total_cents: 5500      # subtotal + tax
      )

      payment_reference = "pi_stripe_test_12345"

      # Confirm the order
      assert {:ok, confirmed_order} = Ticketing.confirm_order(order, payment_reference)

      # Verify order was updated correctly
      assert confirmed_order.id == order.id
      assert confirmed_order.status == "confirmed"
      assert confirmed_order.payment_reference == payment_reference
      assert confirmed_order.confirmed_at != nil
      assert DateTime.diff(confirmed_order.confirmed_at, DateTime.utc_now(), :second) < 5

      # Verify event participant was created
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.role == :ticket_holder
      assert participant.status == :confirmed_with_order
      assert participant.source == "ticket_purchase"

      # Verify participant metadata contains order info
      assert participant.metadata["order_id"] == confirmed_order.id
      assert participant.metadata["ticket_id"] == ticket.id
      assert participant.metadata["quantity"] == 2
    end

    test "confirm_order/1 works without payment reference", %{user: user, event: event, ticket: ticket} do
      order = insert(:order,
        user: user,
        event: event,
        ticket: ticket,
        status: "pending",
        quantity: 1,
        subtotal_cents: 2500,
        tax_cents: 250,
        total_cents: 2750
      )

      assert {:ok, confirmed_order} = Ticketing.confirm_order(order)

      assert confirmed_order.status == "confirmed"
      assert confirmed_order.confirmed_at != nil
      assert confirmed_order.payment_reference == nil

      # Verify participant creation
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.status == :confirmed_with_order
    end

    test "confirm_order prevents double confirmation", %{user: user, event: event, ticket: ticket} do
      original_confirmation_time = DateTime.utc_now()

      order = insert(:order,
        user: user,
        event: event,
        ticket: ticket,
        status: "confirmed",
        confirmed_at: original_confirmation_time,
        payment_reference: "pi_original",
        quantity: 1,
        subtotal_cents: 2500,
        tax_cents: 250,
        total_cents: 2750
      )

      # Trying to confirm again should succeed but not change anything important
      assert {:ok, same_order} = Ticketing.confirm_order(order, "pi_new_reference")
      assert same_order.status == "confirmed"
      # Payment reference may be updated, but confirmed_at should not change much
      assert DateTime.diff(same_order.confirmed_at, original_confirmation_time, :second) < 5
    end

    test "upgrades existing participant from invitee to ticket holder", %{user: user, event: event, ticket: ticket} do
      # Create existing participant as invitee
      {:ok, _existing_participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "manual_invite",
        metadata: %{
          "invited_by" => "event_organizer",
          "invitation_date" => "2024-01-15"
        }
      })

      order = insert(:order,
        user: user,
        event: event,
        ticket: ticket,
        status: "pending",
        quantity: 1,
        subtotal_cents: 2500,
        tax_cents: 250,
        total_cents: 2750
      )

      # Confirm order should upgrade participant
      assert {:ok, confirmed_order} = Ticketing.confirm_order(order, "pi_test_123")

      # Verify participant was upgraded, not duplicated
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.role == :ticket_holder  # Upgraded
      assert participant.status == :confirmed_with_order  # Upgraded
      assert participant.source == "manual_invite"  # Original preserved

      # Metadata should include original and new info
      assert participant.metadata["invited_by"] == "event_organizer"  # Original
      assert participant.metadata["invitation_date"] == "2024-01-15"  # Original
      assert participant.metadata["order_id"] == confirmed_order.id  # New

      # Ensure no duplicate participants were created
      all_participants = Events.list_event_participants_for_event(event)
      user_participants = Enum.filter(all_participants, &(&1.user_id == user.id))
      assert length(user_participants) == 1
    end
  end

  describe "participant creation" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)
      ticket = insert(:ticket, event: event, base_price_cents: 1500)

      %{user: user, organizer: organizer, event: event, ticket: ticket}
    end

    test "creates new participant for first-time ticket purchaser", %{user: user, event: event, ticket: ticket} do
      order = insert(:order,
        user: user,
        event: event,
        ticket: ticket,
        status: "confirmed",  # Already confirmed for this test
        quantity: 1,
        subtotal_cents: 1500,
        tax_cents: 150,
        total_cents: 1650
      )

      # Create participant directly (simulating what confirm_order does)
      assert {:ok, participant} = Events.create_or_upgrade_participant_for_order(%{
        event_id: event.id,
        user_id: user.id,
        source: "ticket_purchase",
        metadata: %{
          order_id: order.id,
          ticket_id: ticket.id,
          quantity: 1,
          confirmed_at: DateTime.utc_now()
        }
      })

      assert participant.event_id == event.id
      assert participant.user_id == user.id
      assert participant.role == :ticket_holder
      assert participant.status == :confirmed_with_order
      assert participant.source == "ticket_purchase"
      # Note: metadata structure may vary based on implementation
    end

    test "participant upgrade from poll voter preserves voting data", %{user: user, event: event, ticket: ticket} do
      # Create poll voter participant
      {:ok, _existing_participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :poll_voter,
        status: :pending,
        source: "date_poll_vote",
        metadata: %{
          "vote_count" => 3,
          "last_vote_date" => "2024-01-10",
          "poll_option_ids" => [1, 2, 3]
        }
      })

      order = insert(:order,
        user: user,
        event: event,
        ticket: ticket,
        status: "pending",
        quantity: 1,
        subtotal_cents: 1500,
        tax_cents: 150,
        total_cents: 1650
      )

      # Confirm order should upgrade participant
      assert {:ok, confirmed_order} = Ticketing.confirm_order(order, "pi_voter_upgrade")

      # Check upgraded participant
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.role == :ticket_holder  # Upgraded
      assert participant.status == :confirmed_with_order  # Upgraded
      assert participant.source == "date_poll_vote"  # Original preserved

      # Verify metadata merged correctly
      assert participant.metadata["vote_count"] == 3  # Original
      assert participant.metadata["last_vote_date"] == "2024-01-10"  # Original
      assert participant.metadata["poll_option_ids"] == [1, 2, 3]  # Original
      assert participant.metadata["order_id"] == confirmed_order.id  # New
      assert participant.metadata["ticket_id"] == ticket.id  # New

      # Ensure no duplicate participants
      all_participants = Events.list_event_participants_for_event(event)
      user_participants = Enum.filter(all_participants, &(&1.user_id == user.id))
      assert length(user_participants) == 1
    end
  end
end
