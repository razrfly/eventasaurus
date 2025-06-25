defmodule EventasaurusWeb.CheckoutLiveTest do
  use EventasaurusWeb.ConnCase, async: true

  alias EventasaurusApp.{Ticketing, Events}
  alias EventasaurusApp.Events.{Event, Ticket, Order}
  alias EventasaurusApp.Accounts.User

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory
  import Mox

  setup :verify_on_exit!

  describe "checkout page access" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)
      ticket = insert(:ticket, event: event, base_price_cents: 2500, quantity: 100)

      %{user: user, organizer: organizer, event: event, ticket: ticket}
    end

    test "authenticated user can access checkout page", %{conn: conn, user: user, event: event} do
      conn = authenticate_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}/checkout")

      assert html =~ "Checkout"
      assert html =~ event.title
    end

    test "unauthenticated user is redirected to login", %{conn: conn, event: event} do
      assert {:error, {:redirect, %{to: "/auth/login"}}} =
               live(conn, ~p"/events/#{event.slug}/checkout")
    end

    test "redirects to event page for non-ticketed events", %{conn: conn, user: user, organizer: organizer} do
      conn = authenticate_user(conn, user)
      non_ticketed_event = insert(:event, users: [organizer], is_ticketed: false)

      assert {:error, {:redirect, %{to: redirect_path}}} =
               live(conn, ~p"/events/#{non_ticketed_event.slug}/checkout")

      assert redirect_path == ~p"/events/#{non_ticketed_event.slug}"
    end
  end

  describe "ticket selection and ordering" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)

      # Create Stripe Connect account for organizer
      _connect_account = insert(:stripe_connect_account, user: organizer)

      ticket = insert(:ticket,
        event: event,
        title: "General Admission",
        base_price_cents: 2500,
        quantity: 100,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      %{user: user, organizer: organizer, event: event, ticket: ticket}
    end

    test "displays available tickets with pricing", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/events/#{event.slug}/checkout")

      assert html =~ ticket.title
      assert html =~ "$25.00"  # Base price display
      assert html =~ "100 available"  # Quantity display
    end

    test "allows quantity selection", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Increase quantity for the ticket
      view
      |> element("[data-testid='increase-quantity-#{ticket.id}']")
      |> render_click()

      # Check that quantity was updated in the view state
      assert has_element?(view, "[data-testid='quantity-#{ticket.id}'][value='2']")

      # Check that total price was updated
      assert has_element?(view, "[data-testid='total-price']", "$55.00")  # 2 * $25 + 10% tax
    end

    test "validates quantity limits", %{conn: conn, user: user, event: event} do
      conn = authenticate_user(conn, user)

      # Create ticket with limited quantity
      limited_ticket = insert(:ticket,
        event: event,
        quantity: 2,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Try to exceed available quantity
      view
      |> element("[data-testid='quantity-input-#{limited_ticket.id}']")
      |> render_change(%{"quantity" => "5"})

      # Should show error or limit to available quantity
      assert has_element?(view, "[data-testid='quantity-error']") or
             has_element?(view, "[data-testid='quantity-#{limited_ticket.id}'][value='2']")
    end

    test "handles flexible pricing tickets", %{conn: conn, user: user, event: event} do
      conn = authenticate_user(conn, user)

      flexible_ticket = insert(:ticket,
        event: event,
        title: "Pay What You Want",
        base_price_cents: 2000,
        minimum_price_cents: 1000,
        pricing_model: "flexible",
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}/checkout")

      assert html =~ "Pay What You Want"
      assert html =~ "Minimum: $10.00"

      # Test custom price input
      view
      |> element("[data-testid='custom-price-#{flexible_ticket.id}']")
      |> render_change(%{"custom_price" => "25.00"})

      # Check that total was updated with custom price
      assert has_element?(view, "[data-testid='total-price']", "$27.50")  # $25 + 10% tax
    end

    test "validates minimum price for flexible pricing", %{conn: conn, user: user, event: event} do
      conn = authenticate_user(conn, user)

      flexible_ticket = insert(:ticket,
        event: event,
        minimum_price_cents: 1000,
        pricing_model: "flexible",
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Try to set price below minimum
      view
      |> element("[data-testid='custom-price-#{flexible_ticket.id}']")
      |> render_change(%{"custom_price" => "5.00"})

      assert has_element?(view, "[data-testid='price-error']", "Price must be at least $10.00")
    end
  end

  describe "free ticket checkout" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)

      free_ticket = insert(:ticket,
        event: event,
        title: "Free Admission",
        base_price_cents: 0,
        quantity: 50,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      %{user: user, organizer: organizer, event: event, ticket: free_ticket}
    end

    test "processes free ticket checkout immediately", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Select ticket and checkout
      view
      |> element("[data-testid='checkout-free-#{ticket.id}']")
      |> render_click()

      # Should redirect to success page or show confirmation
      flash = assert_redirected(view, ~p"/events/#{event.slug}")
      assert flash["info"] =~ "confirmed"

      # Verify order was created and confirmed
      order = Ticketing.get_orders_for_user(user) |> List.first()
      assert order != nil
      assert order.status == "confirmed"
      assert order.total_cents == 0

      # Verify participant was created
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant != nil
      assert participant.role == :ticket_holder
      assert participant.status == :confirmed_with_order
      assert participant.source == "ticket_purchase"
    end

    test "creates event participant with correct metadata", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      view
      |> element("[data-testid='checkout-free-#{ticket.id}']")
      |> render_click()

      participant = Events.get_event_participant_by_event_and_user(event, user)
      order = Ticketing.get_orders_for_user(user) |> List.first()

      assert participant.metadata["order_id"] == order.id
      assert participant.metadata["ticket_id"] == ticket.id
      assert participant.metadata["quantity"] == 1
      assert participant.metadata["confirmed_at"] != nil
    end

    test "upgrades existing participant on free ticket purchase", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      # Create existing participant with different status
      {:ok, existing_participant} = Events.create_event_participant(%{
        event_id: event.id,
        user_id: user.id,
        role: :invitee,
        status: :pending,
        source: "manual_invite",
        metadata: %{"invited_by" => "admin"}
      })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      view
      |> element("[data-testid='checkout-free-#{ticket.id}']")
      |> render_click()

      # Verify participant was upgraded, not duplicated
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.id == existing_participant.id  # Same record
      assert participant.role == :ticket_holder  # Upgraded
      assert participant.status == :confirmed_with_order  # Upgraded
      assert participant.source == "manual_invite"  # Original preserved

      # Check metadata was merged
      assert participant.metadata["invited_by"] == "admin"  # Original preserved
      assert participant.metadata["order_id"] != nil  # New metadata added

      # Ensure no duplicate participants
      all_participants = Events.list_event_participants_for_event(event)
      user_participants = Enum.filter(all_participants, &(&1.user_id == user.id))
      assert length(user_participants) == 1
    end
  end

  describe "paid ticket checkout" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)

      # Create Stripe Connect account for organizer
      _connect_account = insert(:stripe_connect_account, user: organizer)

      paid_ticket = insert(:ticket,
        event: event,
        title: "Premium Access",
        base_price_cents: 5000,
        quantity: 25,
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      %{user: user, organizer: organizer, event: event, ticket: paid_ticket}
    end

    test "initiates Stripe payment flow", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      # Mock Stripe payment intent creation
      expect(EventasaurusApp.StripeMock, :create_payment_intent, fn _params, _connect_account ->
        {:ok, %{
          "id" => "pi_test_payment_intent",
          "client_secret" => "pi_test_secret_123"
        }}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Initiate checkout
      view
      |> element("[data-testid='checkout-paid-#{ticket.id}']")
      |> render_click()

      # Should redirect to payment page with payment intent
      assert_redirected(view, ~p"/checkout/payment?order_id=#{:erlang.term_to_binary("mock_order_id")}")

      # Verify pending order was created
      order = Ticketing.get_orders_for_user(user) |> List.first()
      assert order != nil
      assert order.status == "pending"
      assert order.stripe_session_id != nil
    end

    test "handles Stripe payment intent creation failure", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      # Mock Stripe payment intent creation failure
      expect(EventasaurusApp.StripeMock, :create_payment_intent, fn _params, _connect_account ->
        {:error, "Payment processing unavailable"}
      end)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      view
      |> element("[data-testid='checkout-paid-#{ticket.id}']")
      |> render_click()

      # Should show error message
      assert has_element?(view, "[data-testid='error-message']", "payment processing")
    end
  end

  describe "real-time updates during checkout" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)

      ticket = insert(:ticket,
        event: event,
        quantity: 5,  # Limited quantity for testing
        starts_at: DateTime.utc_now() |> DateTime.add(-1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      %{user: user, organizer: organizer, event: event, ticket: ticket}
    end

    test "updates available quantity when tickets are purchased", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Verify initial quantity display
      assert has_element?(view, "[data-testid='available-quantity-#{ticket.id}']", "5 available")

      # Simulate another user purchasing tickets (triggering PubSub update)
      other_user = insert(:user)
      {:ok, _order} = Ticketing.create_order(other_user, ticket, %{quantity: 2})

      # Check that the view updated the available quantity
      assert has_element?(view, "[data-testid='available-quantity-#{ticket.id}']", "3 available")
    end

    test "disables checkout when tickets become unavailable", %{conn: conn, user: user, event: event, ticket: ticket} do
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Simulate all tickets being purchased
      other_user = insert(:user)
      {:ok, _order} = Ticketing.create_order(other_user, ticket, %{quantity: 5})

      # Check that checkout button is disabled
      assert has_element?(view, "[data-testid='checkout-disabled-#{ticket.id}']", "Sold Out")
    end
  end

  describe "error handling" do
    setup do
      user = insert(:user)
      organizer = insert(:user)
      event = insert(:event, users: [organizer], is_ticketed: true)

      %{user: user, organizer: organizer, event: event}
    end

    test "handles ticket not found", %{conn: conn, user: user, event: event} do
      conn = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Try to checkout non-existent ticket
      assert_raise(ArgumentError, fn ->
        view
        |> element("[data-testid='checkout-999']")
        |> render_click()
      end)
    end

    test "handles ticket sales period validation", %{conn: conn, user: user, event: event} do
      conn = authenticate_user(conn, user)

      # Create ticket not yet on sale
      future_ticket = insert(:ticket,
        event: event,
        starts_at: DateTime.utc_now() |> DateTime.add(1, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(30, :day)
      )

      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}/checkout")

      # Should show "Not Yet Available" state
      assert html =~ "Not Yet Available"
      refute has_element?(view, "[data-testid='checkout-#{future_ticket.id}']")

      # Create expired ticket
      expired_ticket = insert(:ticket,
        event: event,
        starts_at: DateTime.utc_now() |> DateTime.add(-30, :day),
        ends_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      # Reload view to see expired ticket
      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}/checkout")

      assert html =~ "Sale Ended"
      refute has_element?(view, "[data-testid='checkout-#{expired_ticket.id}']")
    end
  end

  # Helper function to log in user for tests
  defp authenticate_user(conn, user) do
    conn
    |> assign(:current_user, user)
    |> init_test_session(%{
      "access_token" => "mock_token",
      "user_id" => user.id
    })
  end
end
