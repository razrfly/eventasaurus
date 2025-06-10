defmodule EventasaurusWeb.CalendarComponentTest do
  use EventasaurusWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EventasaurusWeb.CalendarComponent

  describe "CalendarComponent" do
    test "renders calendar with current month" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      today = Date.utc_today()
      month_year = Calendar.strftime(today, "%B %Y")

      assert has_element?(view, "h3", month_year)
      assert has_element?(view, "[role='application'][aria-label='Date picker calendar']")
    end

    test "renders day headers with proper accessibility" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      # Check for day headers with proper ARIA labels
      assert has_element?(view, "[role='columnheader'][aria-label='Sunday']")
      assert has_element?(view, "[role='columnheader'][aria-label='Monday']")
      assert has_element?(view, "[role='columnheader'][aria-label='Tuesday']")
      assert has_element?(view, "[role='columnheader'][aria-label='Wednesday']")
      assert has_element?(view, "[role='columnheader'][aria-label='Thursday']")
      assert has_element?(view, "[role='columnheader'][aria-label='Friday']")
      assert has_element?(view, "[role='columnheader'][aria-label='Saturday']")
    end

    test "renders calendar grid with proper ARIA structure" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      assert has_element?(view, "[role='grid'][aria-labelledby='calendar-month-year']")
      assert has_element?(view, "button[role='gridcell']")
    end

    test "selects a date when clicked" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      today = Date.utc_today()
      future_date = Date.add(today, 5)
      date_string = Date.to_iso8601(future_date)

      # Click on a future date
      view
      |> element("button[phx-value-date='#{date_string}']")
      |> render_click()

      # Check that the date is now selected (has aria-pressed="true")
      assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-pressed='true']")
    end

    test "deselects a date when clicked again" do
      future_date = Date.add(Date.utc_today(), 5)

      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: [future_date]
      })

      date_string = Date.to_iso8601(future_date)

      # Verify date is initially selected
      assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-pressed='true']")

      # Click on the selected date to deselect it
      view
      |> element("button[phx-value-date='#{date_string}']")
      |> render_click()

      # Check that the date is now deselected
      assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-pressed='false']")
    end

    test "displays selected dates in chronological order" do
      date1 = Date.add(Date.utc_today(), 10)
      date2 = Date.add(Date.utc_today(), 5)
      date3 = Date.add(Date.utc_today(), 15)

      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: [date1, date2, date3]  # Unsorted order
      })

      # Check that selected dates summary is displayed
      assert has_element?(view, "[role='status'][aria-live='polite']", "Selected dates (3):")

      # Verify dates are displayed in chronological order
      html = render(view)
      date2_formatted = Calendar.strftime(date2, "%b %d")
      date1_formatted = Calendar.strftime(date1, "%b %d")
      date3_formatted = Calendar.strftime(date3, "%b %d")

      # Check that the dates appear in the correct order in the HTML
      assert html =~ ~r/#{date2_formatted}.*#{date1_formatted}.*#{date3_formatted}/s
    end

    test "navigates to previous month" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      current_month = Date.utc_today()
      prev_month = Date.add(current_month, -Date.days_in_month(current_month))
      expected_month_year = Calendar.strftime(prev_month, "%B %Y")

      # Click previous month button
      view
      |> element("button[aria-label='Previous month']")
      |> render_click()

      # Check that the month has changed
      assert has_element?(view, "h3", expected_month_year)
    end

    test "navigates to next month" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      current_month = Date.utc_today()
      next_month = Date.add(current_month, Date.days_in_month(current_month))
      expected_month_year = Calendar.strftime(next_month, "%B %Y")

      # Click next month button
      view
      |> element("button[aria-label='Next month']")
      |> render_click()

      # Check that the month has changed
      assert has_element?(view, "h3", expected_month_year)
    end

    test "disables past dates" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      yesterday = Date.add(Date.utc_today(), -1)
      date_string = Date.to_iso8601(yesterday)

      # Check that past dates are disabled
      assert has_element?(view, "button[phx-value-date='#{date_string}'][disabled]")
    end

    test "disables dates from other months" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      # Navigate to next month to get dates from current month that appear in the grid
      view
      |> element("button[aria-label='Next month']")
      |> render_click()

      current_month = Date.utc_today()

      # Find a date from the current month that would appear in next month's grid
      # This would be a date from the end of current month
      last_day_current_month = Date.end_of_month(current_month)

      # Check if this date appears in the grid and is disabled
      date_string = Date.to_iso8601(last_day_current_month)

      # The date should either not be present or be disabled
      if has_element?(view, "button[phx-value-date='#{date_string}']") do
        assert has_element?(view, "button[phx-value-date='#{date_string}'][disabled]")
      end
    end

    test "highlights today's date" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      today = Date.utc_today()
      date_string = Date.to_iso8601(today)

      # Check that today's date has special styling (contains "Today" in screen reader text)
      assert has_element?(view, "button[phx-value-date='#{date_string}'] .sr-only", ~r/Today/)
    end

    test "provides proper ARIA labels for date buttons" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      future_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(future_date)
      expected_label = "Select #{Calendar.strftime(future_date, "%B %d, %Y")}"

      assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-label='#{expected_label}']")
    end

    test "updates ARIA labels when date is selected" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      future_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(future_date)

      # Click to select the date
      view
      |> element("button[phx-value-date='#{date_string}']")
      |> render_click()

      # Check that ARIA label has changed to "Deselect"
      expected_label = "Deselect #{Calendar.strftime(future_date, "%B %d, %Y")}"
      assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-label='#{expected_label}']")
    end

    test "allows removing selected dates from summary" do
      future_date = Date.add(Date.utc_today(), 5)

      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: [future_date]
      })

      date_string = Date.to_iso8601(future_date)
      formatted_date = Calendar.strftime(future_date, "%B %d, %Y")

      # Click the remove button in the selected dates summary
      view
      |> element("button[aria-label='Remove #{formatted_date} from selection']")
      |> render_click()

      # Check that the date is no longer selected
      assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-pressed='false']")
    end

    test "sends selected_dates_changed message to parent" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      future_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(future_date)

      # Click on a date
      view
      |> element("button[phx-value-date='#{date_string}']")
      |> render_click()

      # Check that the parent process received the message
      assert_received {:selected_dates_changed, [^future_date]}
    end

    test "handles keyboard navigation events" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      current_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(current_date)

      # Test arrow key navigation
      view
      |> element("div[phx-hook='CalendarKeyboardNav']")
      |> render_hook("key_navigation", %{"key" => "ArrowRight", "date" => date_string})

      # Should push focus_date event for the next day
      next_date = Date.add(current_date, 1)
      expected_date = Date.to_iso8601(next_date)

      # The component should have pushed a focus_date event
      assert_push_event(view, "focus_date", %{date: ^expected_date})
    end

    test "handles Enter key to toggle date selection" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      future_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(future_date)

      # Test Enter key to select date
      view
      |> element("div[phx-hook='CalendarKeyboardNav']")
      |> render_hook("key_navigation", %{"key" => "Enter", "date" => date_string})

      # Check that the parent process received the toggle message
      assert_received {:selected_dates_changed, [^future_date]}
    end

    test "handles Space key to toggle date selection" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      future_date = Date.add(Date.utc_today(), 5)
      date_string = Date.to_iso8601(future_date)

      # Test Space key to select date
      view
      |> element("div[phx-hook='CalendarKeyboardNav']")
      |> render_hook("key_navigation", %{"key" => "Space", "date" => date_string})

      # Check that the parent process received the toggle message
      assert_received {:selected_dates_changed, [^future_date]}
    end

    test "responsive design shows abbreviated day names on mobile" do
      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: []
      })

      html = render(view)

      # Check that both full and abbreviated day names are present
      assert html =~ ~r/<span class="hidden sm:inline">Sun<\/span>/
      assert html =~ ~r/<span class="sm:hidden">S<\/span>/
    end

    test "responsive design shows different date formats" do
      future_date = Date.add(Date.utc_today(), 5)

      {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
        id: "test-calendar",
        selected_dates: [future_date]
      })

      html = render(view)

      # Check that both desktop and mobile date formats are present
      desktop_format = Calendar.strftime(future_date, "%b %d")
      mobile_format = Calendar.strftime(future_date, "%m/%d")

      assert html =~ ~r/<span class="hidden sm:inline">#{Regex.escape(desktop_format)}<\/span>/
      assert html =~ ~r/<span class="sm:hidden">#{Regex.escape(mobile_format)}<\/span>/
    end
  end
end
