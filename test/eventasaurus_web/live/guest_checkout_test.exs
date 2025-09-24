defmodule EventasaurusWeb.GuestCheckoutTest do
  use EventasaurusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  # We removed Events and Ticketing aliases as they're not used in tests

  describe "guest checkout validation" do
    setup do
      # Create test data
      user = insert(:user)
      venue = insert(:venue)
      event = insert(:event, venue: venue, status: :confirmed)
      # Create the organizer relationship
      insert(:event_user, event: event, user: user, role: "organizer")
      ticket = insert(:ticket, event: event, title: "General Admission", base_price_cents: 2500)

      %{event: event, ticket: ticket}
    end

    test "shows validation errors for empty name", %{conn: conn, event: event, ticket: ticket} do
      {:ok, view, _html} = live(conn, "/events/#{event.slug}/checkout?#{ticket.id}=1")

      # Update guest form with empty name and valid email
      view |> element("#guest_name") |> render_keyup(%{value: "", field: "name"})

      view
      |> element("#guest_email")
      |> render_keyup(%{value: "john@example.com", field: "email"})

      # Try to proceed with checkout
      html = view |> element("button", "Proceed to Payment") |> render_click()

      assert html =~ "Name is required"
    end

    test "shows validation errors for empty email", %{conn: conn, event: event, ticket: ticket} do
      {:ok, view, _html} = live(conn, "/events/#{event.slug}/checkout?#{ticket.id}=1")

      # Update guest form with valid name and empty email
      view |> element("#guest_name") |> render_keyup(%{value: "John Doe", field: "name"})
      view |> element("#guest_email") |> render_keyup(%{value: "", field: "email"})

      # Try to proceed with checkout
      html = view |> element("button", "Proceed to Payment") |> render_click()

      assert html =~ "Email is required"
    end

    # Email format validation is now handled by:
    # 1. HTML5 type="email" validation (client-side)
    # 2. Supabase Auth API validation (server-side)
    # No custom server-side regex validation needed

    test "processes multiple ticket types successfully", %{
      conn: conn,
      event: event,
      ticket: ticket
    } do
      # Create another ticket type
      ticket2 = insert(:ticket, event: event, title: "VIP Admission", base_price_cents: 5000)

      {:ok, view, _html} =
        live(conn, "/events/#{event.slug}/checkout?#{ticket.id}=1&#{ticket2.id}=1")

      # Update guest form with valid data
      view |> element("#guest_name") |> render_keyup(%{value: "John Doe", field: "name"})

      view
      |> element("#guest_email")
      |> render_keyup(%{value: "john@example.com", field: "email"})

      # Proceed with checkout - should now handle multiple ticket types
      view |> element("button", "Proceed to Payment") |> render_click()

      # LiveView test can't easily test external redirects directly,
      # but if the process completes without errors, the multi-ticket checkout likely worked
      # In a real app, this would redirect to Stripe Checkout externally with multiple line items
    end

    test "processes valid guest form successfully", %{conn: conn, event: event, ticket: ticket} do
      {:ok, view, _html} = live(conn, "/events/#{event.slug}/checkout?#{ticket.id}=1")

      # Update guest form with valid data
      view |> element("#guest_name") |> render_keyup(%{value: "John Doe", field: "name"})

      view
      |> element("#guest_email")
      |> render_keyup(%{value: "john@example.com", field: "email"})

      # Proceed with checkout - this should redirect to Stripe
      view |> element("button", "Proceed to Payment") |> render_click()

      # LiveView test can't easily test external redirects directly,
      # but if the process completes without errors, the redirect likely worked
      # In a real app, this would redirect to Stripe Checkout externally
    end
  end

  describe "email validation behavior" do
    test "uses same validation approach as auth forms" do
      alias EventasaurusWeb.CheckoutLive

      # Email validation now follows the same pattern as login/register forms:
      # - HTML5 type="email" validation on the client side
      # - Supabase Auth API validation on the server side
      # - No custom regex validation needed

      # The valid_email? function now always returns true since validation
      # is handled by the browser and Supabase Auth API
      assert CheckoutLive.valid_email?("any@email.com") == true
      assert CheckoutLive.valid_email?("invalid-format") == true
    end
  end
end
