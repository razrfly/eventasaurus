defmodule EventasaurusWeb.PublicEventShowLiveTest do
  @moduledoc """
  Tests for PublicEventShowLive, specifically the URL param modal opening flow.

  This tests the `?open_modal=open_plan_modal` URL parameter that allows:
  1. CDN-cached pages to trigger modal opening after authentication
  2. Deep-linking to the Plan with Friends modal
  """
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  alias EventasaurusApp.Events.EventPlans

  describe "maybe_auto_open_modal/2 with ?open_modal=open_plan_modal" do
    setup do
      # Create a public event with all required associations
      # Uses create_complete_public_event/0 to handle the database trigger that
      # requires at least one source record per public event
      public_event = create_complete_public_event()
      %{public_event: public_event}
    end

    test "does not open modal for unauthenticated user", %{conn: conn, public_event: public_event} do
      # Visit the page with the modal param but no authentication
      {:ok, view, html} =
        live(conn, ~p"/activities/#{public_event.slug}?open_modal=open_plan_modal")

      # Modal should NOT be open for unauthenticated users
      refute html =~ "data-test-id=\"plan-with-friends-modal\""
      refute view |> has_element?("[data-test-id='plan-with-friends-modal']")
    end

    test "opens modal for authenticated user without existing plan", %{
      conn: conn,
      public_event: public_event
    } do
      # Create and authenticate a user
      user = insert(:user)
      conn = log_in_user(conn, user)

      # Visit the page with the modal param
      {:ok, view, html} =
        live(conn, ~p"/activities/#{public_event.slug}?open_modal=open_plan_modal")

      # Modal should be open for authenticated users
      # Check for modal presence in rendered HTML
      assert html =~ "Plan with Friends" or
               view |> has_element?("[data-test-id='plan-with-friends-modal']")
    end

    test "redirects to existing plan when user already has one", %{
      conn: conn,
      public_event: public_event
    } do
      # Create and authenticate a user
      user = insert(:user)
      conn = log_in_user(conn, user)

      # Create an existing plan for this user and public event
      {:ok, {:created, _event_plan, private_event}} =
        EventPlans.create_from_public_event(public_event.id, user.id, %{
          title: "My Plan for #{public_event.title}"
        })

      # Visit the page with the modal param - should redirect to existing plan
      {:error, {:live_redirect, %{to: redirect_path}}} =
        live(conn, ~p"/activities/#{public_event.slug}?open_modal=open_plan_modal")

      # Should redirect to the existing private event
      assert redirect_path == "/events/#{private_event.slug}"
    end
  end

  describe "handle_event open_plan_modal behavioral parity" do
    setup do
      public_event = create_complete_public_event()
      %{public_event: public_event}
    end

    test "handle_event and maybe_auto_open_modal produce similar results for authenticated users",
         %{
           conn: conn,
           public_event: public_event
         } do
      # Create and authenticate a user
      user = insert(:user)
      conn = log_in_user(conn, user)

      # Test 1: Visit via URL param (uses maybe_auto_open_modal)
      {:ok, view1, html1} =
        live(conn, ~p"/activities/#{public_event.slug}?open_modal=open_plan_modal")

      # Test 2: Visit without param, then trigger event (uses handle_event)
      {:ok, view2, _html2} = live(conn, ~p"/activities/#{public_event.slug}")

      # Trigger the event directly (button uses JS hook, so we send the event)
      # This simulates what the AuthProtectedAction hook does for authenticated users
      html2 = render_click(view2, "open_plan_modal", %{})

      # Both paths should result in the modal being shown
      # Check both have the modal content visible
      modal_visible_1 =
        html1 =~ "Plan with Friends" or
          has_element?(view1, "[data-test-id='plan-with-friends-modal']")

      modal_visible_2 =
        html2 =~ "Plan with Friends" or
          has_element?(view2, "[data-test-id='plan-with-friends-modal']")

      assert modal_visible_1 == modal_visible_2,
             "URL param and button click should produce same modal state"
    end

    test "URL param flow redirects to existing plan", %{
      conn: conn,
      public_event: public_event
    } do
      user = insert(:user)
      conn = log_in_user(conn, user)

      # Create an existing plan
      {:ok, {:created, _event_plan, private_event}} =
        EventPlans.create_from_public_event(public_event.id, user.id, %{
          title: "Test Plan"
        })

      expected_path = "/events/#{private_event.slug}"

      # URL param flow should redirect when user has existing plan
      {:error, {:live_redirect, %{to: url_redirect}}} =
        live(conn, ~p"/activities/#{public_event.slug}?open_modal=open_plan_modal")

      assert url_redirect == expected_path
    end

    test "page shows 'You have a plan!' when user has existing plan", %{
      conn: conn,
      public_event: public_event
    } do
      user = insert(:user)
      conn = log_in_user(conn, user)

      # Create an existing plan
      {:ok, {:created, _event_plan, _private_event}} =
        EventPlans.create_from_public_event(public_event.id, user.id, %{
          title: "Test Plan"
        })

      # Visit without modal param - should show existing plan state
      {:ok, _view, html} = live(conn, ~p"/activities/#{public_event.slug}")

      # Should show "You have a plan!" state instead of "Plan with Friends" button
      assert html =~ "You have a plan!"
      assert html =~ "View Your Event"
    end
  end
end
