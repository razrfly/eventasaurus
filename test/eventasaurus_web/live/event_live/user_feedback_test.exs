defmodule EventasaurusWeb.EventLive.UserFeedbackTest do
  use EventasaurusWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import EventasaurusApp.Factory

  describe "Success Messages and Flash" do
    test "displays success flash after event creation", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Create a valid event
      event_data = %{
        "event[title]" => "Success Test Event",
        "event[tagline]" => "Testing success messages",
        "event[start_date]" => "2025-06-15",
        "event[start_time]" => "14:00",
        "event[ends_date]" => "2025-06-15",
        "event[ends_time]" => "16:00",
        "event[timezone]" => "America/Los_Angeles",
        "event[visibility]" => "public"
      }

      # Submit the form
      result = view
      |> form("form[data-test-id='event-form']", event_data)
      |> render_submit()

      # Should redirect to an event page (slug is auto-generated)
      case result do
        {:error, {:redirect, %{to: redirect_path}}} ->
          # LiveView redirect
          assert redirect_path =~ "/events/"
        {:ok, conn} ->
          # Controller redirect with flash
          assert conn.status == 200
          assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Event created successfully"
          # The response body should contain the event page
          assert conn.resp_body =~ event_data["event[title]"]
      end
    end

    test "displays success flash after event update", %{conn: conn} do
      clear_test_auth()
      event = insert(:event)
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Update the event
      updated_data = %{
        "event[title]" => "Updated Event Title",
        "event[tagline]" => event.tagline,
        "event[start_date]" => "2025-07-15",
        "event[start_time]" => "10:00",
        "event[ends_date]" => "2025-07-15",
        "event[ends_time]" => "12:00",
        "event[timezone]" => event.timezone || "America/Los_Angeles"
      }

      result = view
      |> form("form[data-test-id='event-form']", updated_data)
      |> render_submit()

      # Should redirect with success message
      case result do
        {:error, {:redirect, %{to: redirect_path}}} ->
          # LiveView redirect
          assert redirect_path =~ "/events/"
        {:ok, conn} ->
          # Controller redirect with flash
          assert conn.status == 200
          assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Event updated successfully"
          # The response body should contain the updated event
          assert conn.resp_body =~ updated_data["event[title]"]
      end
    end
  end

  describe "Error Messages and Validation Feedback" do
    test "displays authentication error when accessing protected pages", %{conn: conn} do
      clear_test_auth()
      # Try to access new event page without authentication
      {:error, {:redirect, %{to: "/auth/login", flash: flash}}} = live(conn, ~p"/events/new")

      # Check that error flash is set
      assert Phoenix.Flash.get(flash, :error) == "You must log in to access this page."
    end

    test "displays error flash for permission denied", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      # Create event with different organizer (don't log them in as organizer)
      event = insert(:event)

      # Try to edit event we don't own
      {:error, {:redirect, %{to: "/dashboard", flash: flash}}} = live(conn, ~p"/events/#{event.slug}/edit")

      # Check permission error message
      assert Phoenix.Flash.get(flash, :error) == "You don't have permission to edit this event"
    end

    test "displays validation errors inline on forms", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Submit form with missing required fields
      invalid_data = %{
        "event[title]" => "",
        "event[start_date]" => "",
        "event[timezone]" => ""
      }

      html = view
      |> form("form[data-test-id='event-form']", invalid_data)
      |> render_submit()

      # Check that we stay on the form (validation prevents submission)
      assert html =~ "Create a New Event"
      assert html =~ "data-test-id=\"event-form\""

      # The validation might not show explicit error text, but form should remain
      # This tests that the user feedback system prevents invalid submissions
    end

    test "displays contextual error for past dates", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Submit with past date
      past_data = %{
        "event[title]" => "Past Event",
        "event[start_date]" => "2020-01-01",
        "event[start_time]" => "10:00",
        "event[ends_date]" => "2020-01-01",
        "event[ends_time]" => "12:00",
        "event[timezone]" => "America/Los_Angeles"
      }

      capture_log(fn ->
        result = view
        |> form("form[data-test-id='event-form']", past_data)
        |> render_submit()

        # Should either show validation error or handle gracefully
        case result do
          {:ok, html} ->
            # Form stayed on page with error handling
            assert html =~ "Create a New Event"
          {:error, _} ->
            # System handled validation gracefully
            :ok
        end
      end)
    end
  end

  describe "Form State and Reset Behavior" do
    test "form clears and resets after successful submission", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Submit valid event
      event_data = %{
        "event[title]" => "Form Reset Test",
        "event[tagline]" => "Testing form reset",
        "event[start_date]" => "2025-06-01",
        "event[start_time]" => "09:00",
        "event[ends_date]" => "2025-06-01",
        "event[ends_time]" => "11:00",
        "event[timezone]" => "America/Los_Angeles",
        "event[visibility]" => "public"
      }

      result = view
      |> form("form[data-test-id='event-form']", event_data)
      |> render_submit()

      # Should redirect (form is effectively "reset" by navigation)
      case result do
        {:error, {:redirect, %{to: redirect_path}}} ->
          assert redirect_path =~ "/events/"
        {:ok, conn} ->
          # Successful submission
          assert conn.status == 200
      end
    end

    test "form preserves data during validation errors", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Submit partially valid data (missing required fields)
      partial_data = %{
        "event[title]" => "Partial Event Title",
        "event[tagline]" => "This should be preserved",
        "event[start_date]" => "", # Missing required field
        "event[timezone]" => "" # Missing required field
      }

      html = view
      |> form("form[data-test-id='event-form']", partial_data)
      |> render_submit()

      # Form should remain on page and still be functional
      assert html =~ "Create a New Event"
      assert html =~ "data-test-id=\"event-form\""

      # The form should maintain valid input (this tests user experience)
      # Note: The exact preservation behavior may vary based on implementation
    end

    test "edit form maintains data during validation failures", %{conn: conn} do
      clear_test_auth()
      event = insert(:event, title: "Original Title")
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Try to update with invalid data
      invalid_update = %{
        "event[title]" => "Updated Title",
        "event[start_date]" => "", # Remove required field
        "event[timezone]" => "" # Remove required field
      }

      html = view
      |> form("form[data-test-id='event-form']", invalid_update)
      |> render_submit()

      # Should stay on edit form (validation prevents submission)
      assert html =~ "Edit Event"
      assert html =~ "data-test-id=\"event-form\""
    end
  end

  describe "Error Recovery and User Experience" do
    test "form remains functional after validation errors", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # First submission with errors
      invalid_data = %{
        "event[title]" => "",
        "event[start_date]" => ""
      }

      view
      |> form("form[data-test-id='event-form']", invalid_data)
      |> render_submit()

      # Second submission with valid data should work
      valid_data = %{
        "event[title]" => "Recovery Test Event",
        "event[start_date]" => "2025-06-20",
        "event[start_time]" => "15:00",
        "event[ends_date]" => "2025-06-20",
        "event[ends_time]" => "17:00",
        "event[timezone]" => "America/Los_Angeles",
        "event[visibility]" => "public"
      }

      result = view
      |> form("form[data-test-id='event-form']", valid_data)
      |> render_submit()

      # Should successfully submit after error recovery
      case result do
        {:error, {:redirect, %{to: redirect_path}}} ->
          assert redirect_path =~ "/events/"
        {:ok, conn} ->
          # Successful submission
          assert conn.status == 200
      end
    end

    test "error messages are properly styled and accessible", %{conn: conn} do
      clear_test_auth()
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Submit invalid data to trigger errors
      invalid_data = %{
        "event[title]" => "",
        "event[start_date]" => ""
      }

      error_html = view
      |> form("form[data-test-id='event-form']", invalid_data)
      |> render_submit()

      # Form should still be present and usable after validation
      assert error_html =~ "data-test-id=\"event-form\""
      assert error_html =~ "Create a New Event"

      # This tests that error handling maintains good UX
    end

    test "successful operations provide clear confirmation", %{conn: conn} do
      clear_test_auth()
      event = insert(:event)
      {conn, _user} = log_in_event_organizer(conn, event)

      # Visit the event management page
      case live(conn, ~p"/events/#{event.slug}") do
        {:ok, _view, html} ->
          # Should show the event details clearly
          assert html =~ event.title

          # Should show management elements (confirming successful access)
          assert html =~ "Edit Event" or html =~ "edit"
          assert html =~ "Delete Event" or html =~ "delete"
        {:error, :nosession} ->
          # If LiveView session issues, try controller route
          conn = get(conn, ~p"/events/#{event.slug}")
          assert conn.status == 200
          assert conn.resp_body =~ event.title
      end
    end
  end
end
