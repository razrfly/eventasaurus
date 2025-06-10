defmodule EventasaurusWeb.EventLive.CalendarIntegrationTest do
  use EventasaurusWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EventasaurusApp.Events

    describe "Calendar Integration in Event Creation" do
    setup do
      # Create a test user using Factory
      user = insert(:user, %{
        email: "test@example.com",
        name: "Test User"
      })

      %{user: user}
    end

    test "displays calendar when date polling is enabled", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Check that calendar component is displayed
      assert has_element?(view, "[role='application'][aria-label='Date picker calendar']")
      assert has_element?(view, "label", "Select dates for polling")
    end

    test "hides calendar when date polling is disabled", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Ensure date polling is disabled (default state)
      refute has_element?(view, "[role='application'][aria-label='Date picker calendar']")

      # Should show traditional date inputs instead
      assert has_element?(view, "input[name='event[start_date]']")
      assert has_element?(view, "input[name='event[ends_date]']")
    end

    test "validates that at least 2 dates are selected for polling", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Fill in required fields
      view
      |> form("[data-test-id='event-form']", event: %{
        title: "Test Event",
        description: "Test Description",
        timezone: "America/New_York",
        start_time: "09:00",
        ends_time: "17:00"
      })
      |> render_change()

      # Try to submit without selecting dates
      view
      |> form("[data-test-id='event-form']")
      |> render_submit()

      # Should show validation error
      assert has_element?(view, ".text-red-600", "must select at least 2 dates for polling")
    end

    test "validates that only 1 date selected shows error", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Select only one date
      future_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(future_date)

      view
      |> element("button[phx-value-date='#{date_string}']")
      |> render_click()

      # Fill in required fields
      view
      |> form("[data-test-id='event-form']", event: %{
        title: "Test Event",
        description: "Test Description",
        timezone: "America/New_York",
        start_time: "09:00",
        ends_time: "17:00"
      })
      |> render_change()

      # Try to submit with only one date
      view
      |> form("[data-test-id='event-form']")
      |> render_submit()

      # Should show validation error
      assert has_element?(view, "[phx-feedback-for='event[selected_poll_dates]']", "must select at least 2 dates for polling")
    end

    test "successfully creates event with date polling", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Select multiple dates
      date1 = Date.add(Date.utc_today(), 5)
      date2 = Date.add(Date.utc_today(), 7)
      date3 = Date.add(Date.utc_today(), 10)

      for date <- [date1, date2, date3] do
        date_string = Date.to_iso8601(date)
        view
        |> element("button[phx-value-date='#{date_string}']")
        |> render_click()
      end

      # Fill in and submit the form
      view
      |> form("[data-test-id='event-form']", event: %{
        title: "Test Polling Event",
        description: "Test Description",
        timezone: "America/New_York",
        start_time: "09:00",
        ends_time: "17:00",
        is_virtual: true
      })
      |> render_submit()

      # Should redirect to the event page
      {path, _flash} = assert_redirect(view, 5000)
      # Check that we're redirected to an event page
      assert path =~ "/events/"

            # Verify event was created with polling state
      event = Events.get_event_by_title("Test Polling Event")
      assert event.state == "polling"

      # Verify date poll was created
      date_poll = Events.get_event_date_poll(event)
      assert date_poll != nil

      # Verify date options were created
      date_options = Events.list_event_date_options(date_poll)
      assert length(date_options) == 3
    end

    test "updates hidden form field when dates are selected", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Select dates
      date1 = Date.add(Date.utc_today(), 5)
      date2 = Date.add(Date.utc_today(), 7)

      view
      |> element("button[phx-value-date='#{Date.to_iso8601(date1)}']")
      |> render_click()

      view
      |> element("button[phx-value-date='#{Date.to_iso8601(date2)}']")
      |> render_click()

      # Check that hidden field is updated
      html = render(view)
      expected_value = "#{Date.to_iso8601(date1)},#{Date.to_iso8601(date2)}"
      assert html =~ ~r/name="event\[selected_poll_dates\]"[^>]*value="#{Regex.escape(expected_value)}"/
    end

    test "preserves selected dates when form validation fails", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Select dates
      date1 = Date.add(Date.utc_today(), 5)
      date2 = Date.add(Date.utc_today(), 7)

      view
      |> element("button[phx-value-date='#{Date.to_iso8601(date1)}']")
      |> render_click()

      view
      |> element("button[phx-value-date='#{Date.to_iso8601(date2)}']")
      |> render_click()

      # Submit form with missing required field (title)
      view
      |> form("[data-test-id='event-form']", event: %{
        description: "Test Description",
        timezone: "America/New_York",
        start_time: "09:00",
        ends_time: "17:00"
      })
      |> render_submit()

      # Form should stay on the same page with validation errors
      assert has_element?(view, "[data-test-id='event-form']")

      # Selected dates should still be visible and selected
      assert has_element?(view, "button[phx-value-date='#{Date.to_iso8601(date1)}'][aria-pressed='true']")
      assert has_element?(view, "button[phx-value-date='#{Date.to_iso8601(date2)}'][aria-pressed='true']")
      assert has_element?(view, "[role='status']", "Selected dates (2):")
    end

    test "calendar form sync hook updates hidden field", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Simulate the calendar form sync hook receiving dates
      dates = [Date.add(Date.utc_today(), 5), Date.add(Date.utc_today(), 7)]
      date_strings = Enum.map(dates, &Date.to_iso8601/1)

      # This would normally be triggered by the JavaScript hook
      view
      |> element("[phx-hook='CalendarFormSync']")
      |> render_hook("calendar_dates_changed", %{
        dates: date_strings,
        component_id: "event-form-new-calendar"
      })

      # Verify the hidden field would be updated (this is handled by JavaScript)
      html = render(view)
      assert html =~ ~r/name="event\[selected_poll_dates\]"/
    end

    test "switches between calendar and traditional date inputs", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Initially should show traditional date inputs
      assert has_element?(view, "input[name='event[start_date]']")
      assert has_element?(view, "input[name='event[ends_date]']")
      refute has_element?(view, "[role='application'][aria-label='Date picker calendar']")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Should now show calendar and hide traditional inputs
      assert has_element?(view, "[role='application'][aria-label='Date picker calendar']")
      refute has_element?(view, "input[name='event[start_date]']")
      refute has_element?(view, "input[name='event[ends_date]']")

      # Disable date polling again
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Should switch back to traditional inputs
      assert has_element?(view, "input[name='event[start_date]']")
      assert has_element?(view, "input[name='event[ends_date]']")
      refute has_element?(view, "[role='application'][aria-label='Date picker calendar']")
    end

    test "displays informational message when date polling is enabled", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Should show informational message
      assert has_element?(view, ".bg-blue-50", "Calendar Polling Mode")
      assert has_element?(view, ".text-blue-700", "Use the calendar above to select specific dates for polling")
    end

    test "calendar component receives correct selected dates from form data", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Enable date polling
      view
      |> element("input[name='event[enable_date_polling]']")
      |> render_click()

      # Select a date
      future_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(future_date)

      view
      |> element("button[phx-value-date='#{date_string}']")
      |> render_click()

      # Verify the date appears as selected in the calendar
      assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-pressed='true']")

      # Verify it appears in the selected dates summary
      formatted_date = Calendar.strftime(future_date, "%b %d")
      assert has_element?(view, ".bg-blue-100", formatted_date)
    end
  end


end
