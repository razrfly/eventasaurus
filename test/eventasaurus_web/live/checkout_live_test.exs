defmodule EventasaurusWeb.CheckoutLiveTest do
  use EventasaurusWeb.ConnCase
  import Phoenix.LiveViewTest
  import EventasaurusApp.AccountsFixtures
  import EventasaurusApp.EventsFixtures

  alias EventasaurusApp.Ticketing

  describe "checkout flow" do
    test "redirects to event if no tickets selected", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      conn = log_in_user(conn, user)

      # Expect redirect when no tickets parameter is provided
      assert {:error, {:redirect, %{to: redirect_path, flash: flash}}} =
        live(conn, "/events/#{event.slug}/checkout")

      assert redirect_path == "/events/#{event.slug}"
      assert flash["error"] == "Please select tickets before proceeding to checkout."
    end

    test "displays checkout page with valid ticket selection", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      {:ok, ticket1} = Ticketing.create_ticket(event, %{title: "Free Ticket", base_price_cents: 0, quantity: 100})
      {:ok, ticket2} = Ticketing.create_ticket(event, %{title: "Paid Ticket", base_price_cents: 2500, quantity: 50})

      conn = log_in_user(conn, user)
      ticket_params = "#{ticket1.id}:2,#{ticket2.id}:1"

      {:ok, _view, html} = live(conn, "/events/#{event.slug}/checkout?tickets=#{ticket_params}")

      assert html =~ "Review your ticket selection for #{event.title}"
      assert html =~ "Free Ticket"
      assert html =~ "Paid Ticket"
      assert html =~ "$25.00"
    end

    test "validates ticket availability", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      {:ok, ticket} = Ticketing.create_ticket(event, %{title: "Free Ticket", base_price_cents: 0, quantity: 10})

      conn = log_in_user(conn, user)
      ticket_params = "#{ticket.id}:15"  # Request more than available

      # Expect redirect when quantity exceeds availability
      assert {:error, {:redirect, %{to: redirect_path, flash: flash}}} =
        live(conn, "/events/#{event.slug}/checkout?tickets=#{ticket_params}")

      assert redirect_path == "/events/#{event.slug}"
      assert flash["error"] == "Only 10 tickets available for Free Ticket"
    end

    test "handles invalid ticket IDs", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      conn = log_in_user(conn, user)
      ticket_params = "999999:1"  # Non-existent ticket ID

      # Expect redirect when ticket doesn't exist
      assert {:error, {:redirect, %{to: redirect_path, flash: flash}}} =
        live(conn, "/events/#{event.slug}/checkout?tickets=#{ticket_params}")

      assert redirect_path == "/events/#{event.slug}"
      assert flash["error"] == "Selected ticket no longer exists"
    end

    test "processes free ticket checkout successfully", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      {:ok, ticket} = Ticketing.create_ticket(event, %{title: "Free Ticket", base_price_cents: 0, quantity: 100})

      conn = log_in_user(conn, user)
      ticket_params = "#{ticket.id}:2"

      {:ok, view, _html} = live(conn, "/events/#{event.slug}/checkout?tickets=#{ticket_params}")

      # Click proceed with checkout for free tickets
      view
      |> element("button", "Reserve Free Tickets")
      |> render_click()

      # Should redirect back to event page with success message
      assert_redirect(view, "/events/#{event.slug}")
    end

    test "updates ticket quantities", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      {:ok, ticket} = Ticketing.create_ticket(event, %{title: "Free Ticket", base_price_cents: 0, quantity: 100})

      conn = log_in_user(conn, user)
      ticket_params = "#{ticket.id}:2"

      {:ok, view, _html} = live(conn, "/events/#{event.slug}/checkout?tickets=#{ticket_params}")

      # Increase quantity
      html = view
      |> element("button[phx-value-quantity='3']")
      |> render_click()

      assert html =~ "3"

      # Decrease quantity
      html = view
      |> element("button[phx-value-quantity='2']")
      |> render_click()

      assert html =~ "2"
    end

    test "removes tickets from cart", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      {:ok, ticket1} = Ticketing.create_ticket(event, %{title: "Free Ticket", base_price_cents: 0, quantity: 100})
      {:ok, ticket2} = Ticketing.create_ticket(event, %{title: "Paid Ticket", base_price_cents: 2500, quantity: 50})

      conn = log_in_user(conn, user)
      ticket_params = "#{ticket1.id}:2,#{ticket2.id}:1"

      {:ok, view, _html} = live(conn, "/events/#{event.slug}/checkout?tickets=#{ticket_params}")

      # Remove first ticket
      html = view
      |> element("button[phx-value-ticket_id='#{ticket1.id}']", "Remove")
      |> render_click()

      refute html =~ "Free Ticket"
      assert html =~ "Paid Ticket"
    end

    test "enforces 10 ticket limit per order", %{conn: conn} do
      user = user_fixture()
      event = event_fixture(user: user, status: :confirmed)

      {:ok, ticket} = Ticketing.create_ticket(event, %{title: "Free Ticket", base_price_cents: 0, quantity: 100})

      conn = log_in_user(conn, user)
      ticket_params = "#{ticket.id}:15"  # Request more than 10 ticket limit

      # Expect redirect when total quantity exceeds 10
      assert {:error, {:redirect, %{to: redirect_path, flash: flash}}} =
        live(conn, "/events/#{event.slug}/checkout?tickets=#{ticket_params}")

      assert redirect_path == "/events/#{event.slug}"
      assert flash["error"] =~ "cannot exceed 10 tickets per order"
    end
  end
end
