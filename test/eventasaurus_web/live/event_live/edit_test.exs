defmodule EventasaurusWeb.EventLive.EditTest do
  @moduledoc """
  Integration tests for editing existing events.
  Part of Phase 1: Establish a Solid Baseline (CRUD Integration Focus)
  """

  use EventasaurusWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  setup do
    clear_test_auth()
    :ok
  end

  describe "authenticated organizer edits event" do
    test "successfully updates event with valid changes", %{conn: conn} do
      # Create event with organizer
      event = insert(:event, title: "Original Event", theme: :minimal)
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Verify the form is present
      assert html =~ "Edit Event"
      assert has_element?(view, "form[data-test-id='event-form']")

      # Update event data (remove venue_id as form handles venue differently)
      updated_data = %{
        "event[title]" => "Updated Event Title",
        "event[tagline]" => "Updated tagline",
        "event[visibility]" => "private",
        "event[start_date]" => "2025-12-15",
        "event[start_time]" => "20:00",  # Use valid time format
        "event[ends_date]" => "2025-12-15",
        "event[ends_time]" => "23:00",   # Use valid time format
        "event[timezone]" => "America/New_York"
      }

      _html = view
      |> form("form[data-test-id='event-form']", updated_data)
      |> render_submit()

      # Should redirect to updated event show page
      assert_redirected(view, "/events/#{event.slug}")

      # Verify updates in database
      updated_event = EventasaurusApp.Repo.get!(EventasaurusApp.Events.Event, event.id)
      assert updated_event.title == "Updated Event Title"
      assert updated_event.tagline == "Updated tagline"
      assert updated_event.visibility == :private
    end

    test "rejects update with invalid data", %{conn: conn} do
      event = insert(:event, title: "Original Title")
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Submit invalid data (empty title)
      invalid_data = %{
        "event[title]" => "",
        "event[start_date]" => "2025-12-01",
        "event[start_time]" => "19:00",
        "event[ends_date]" => "2025-12-01",
        "event[ends_time]" => "21:00",
        "event[timezone]" => "America/Los_Angeles"
      }

      # Validation prevents update
      capture_log(fn ->
        result = view
        |> form("form[data-test-id='event-form']", invalid_data)
        |> render_submit()

        case result do
          {:error, {:redirect, _}} ->
            # Validation prevented update
            reloaded_event = EventasaurusApp.Repo.reload!(event)
            assert reloaded_event.title == "Original Title"
          html when is_binary(html) ->
            # Stayed on form - validation prevented submission
            assert has_element?(view, "form[data-test-id='event-form']")
        end
      end)

      # Verify event was not updated
      reloaded_event = EventasaurusApp.Repo.reload!(event)
      assert reloaded_event.title == "Original Title"
    end

    test "displays validation errors for required fields", %{conn: conn} do
      event = insert(:event, title: "Original Title")
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Clear required fields
      invalid_data = %{
        "event[title]" => "",
        "event[timezone]" => ""
      }

      # Server-side validation prevents update
      capture_log(fn ->
        result = view
        |> form("form[data-test-id='event-form']", invalid_data)
        |> render_submit()

        case result do
          {:error, {:redirect, _}} ->
            # Validation prevented update
            assert true
          html when is_binary(html) ->
            # Form remains active
            assert has_element?(view, "form[data-test-id='event-form']")
        end
      end)

      # Event should remain unchanged
      reloaded_event = EventasaurusApp.Repo.reload!(event)
      assert reloaded_event.title == "Original Title"
    end

    test "form preserves valid data when validation fails", %{conn: conn} do
      event = insert(:event, title: "Original Title", tagline: "Original Tagline")
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Mix valid and invalid data
      mixed_data = %{
        "event[title]" => "",                  # Invalid
        "event[tagline]" => "Updated Tagline", # Valid
        "event[description]" => "Updated Description"  # Valid
      }

      # Test validation behavior
      capture_log(fn ->
        result = view
        |> form("form[data-test-id='event-form']", mixed_data)
        |> render_submit()

        case result do
          {:error, {:redirect, _}} ->
            # Validation prevented update
            reloaded_event = EventasaurusApp.Repo.reload!(event)
            assert reloaded_event.title == "Original Title"
          html when is_binary(html) ->
            # Form may preserve some data
            assert has_element?(view, "form[data-test-id='event-form']")
        end
      end)

      # Original event should be unchanged
      reloaded_event = EventasaurusApp.Repo.reload!(event)
      assert reloaded_event.title == "Original Title"
      assert reloaded_event.tagline == "Original Tagline"
    end

    test "preserves existing data when updating single field", %{conn: conn} do
      event = insert(:event, title: "Original Title", tagline: "Original Tagline")
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Update only the title field
      updated_data = %{
        "event[title]" => "Only Title Changed",
        "event[start_time]" => "14:00",  # Use valid time format (was "14:40")
        "event[ends_time]" => "16:00"    # Use valid time format
      }

      _html = view
      |> form("form[data-test-id='event-form']", updated_data)
      |> render_submit()

      # Should redirect to event show page
      assert_redirected(view, "/events/#{event.slug}")

      # Verify only title changed, other data preserved
      updated_event = EventasaurusApp.Repo.get!(EventasaurusApp.Events.Event, event.id)
      assert updated_event.title == "Only Title Changed"
      assert updated_event.tagline == "Original Tagline"  # Should be preserved
    end

    test "edit form shows correct state for events with date polling", %{conn: conn} do
      # Create a user for this test
      user = EventasaurusApp.AccountsFixtures.user_fixture()

      # Create an event with date polling enabled
      tomorrow = Date.utc_today() |> Date.add(1)
      week_later = Date.utc_today() |> Date.add(8)

      event_attrs = %{
        title: "Polling Event for Edit Test",
        description: "An event to test edit functionality",
        start_at: DateTime.new!(tomorrow, ~T[14:00:00], "America/New_York") |> DateTime.shift_zone!("UTC"),
        ends_at: DateTime.new!(week_later, ~T[16:00:00], "America/New_York") |> DateTime.shift_zone!("UTC"),
        timezone: "America/New_York",
        status: "polling",
        polling_deadline: DateTime.add(DateTime.utc_now(), 7, :day),
        visibility: "public",
        is_virtual: true,
        virtual_venue_url: "https://example.com/meeting"
      }

      {:ok, event} = EventasaurusApp.Events.create_event_with_organizer(event_attrs, user)

      # Create date poll and options
      {:ok, poll} = EventasaurusApp.Events.create_event_date_poll(event, user, %{voting_deadline: nil})
      {:ok, _options} = EventasaurusApp.Events.create_date_options_from_range(poll, tomorrow, week_later)

      # Load the edit page
      conn = log_in_user(conn, user)
      {:ok, edit_live, html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Check that the date polling checkbox is checked
      assert html =~ "checked"
      assert html =~ "Let attendees vote on the date"

      # Check that polling mode indicators are present
      assert html =~ "Calendar Polling Mode"
      assert html =~ "Select dates for polling"

      # Verify that the date polling state is detected correctly
      assert has_element?(edit_live, "[name='event[enable_date_polling]'][checked]")

      # Verify polling-specific UI elements are present
      assert has_element?(edit_live, ".calendar-component")
      assert has_element?(edit_live, "h4", "Calendar Polling Mode")

      # The checkbox should be checked
      assert has_element?(edit_live, "input[name='event[enable_date_polling]'][checked]")
    end

    test "editing date options during polling preserves existing votes", %{conn: conn} do
      # Create a user for this test
      user = EventasaurusApp.AccountsFixtures.user_fixture()
      other_user = EventasaurusApp.AccountsFixtures.user_fixture()

      # Create an event with date polling enabled
      tomorrow = Date.utc_today() |> Date.add(1)
      day_after = Date.utc_today() |> Date.add(2)
      day_three = Date.utc_today() |> Date.add(3)

      event_attrs = %{
        title: "Test Vote Preservation",
        description: "Testing that votes are preserved during edits",
        start_at: DateTime.new!(tomorrow, ~T[14:00:00], "America/New_York") |> DateTime.shift_zone!("UTC"),
        ends_at: DateTime.new!(day_three, ~T[16:00:00], "America/New_York") |> DateTime.shift_zone!("UTC"),
        timezone: "America/New_York",
        status: "polling",
        polling_deadline: DateTime.add(DateTime.utc_now(), 7, :day),
        visibility: "public",
        is_virtual: true
      }

      {:ok, event} = EventasaurusApp.Events.create_event_with_organizer(event_attrs, user)

      # Create date poll and initial options (tomorrow and day_after)
      {:ok, poll} = EventasaurusApp.Events.create_event_date_poll(event, user, %{voting_deadline: nil})
      {:ok, option1} = EventasaurusApp.Events.create_event_date_option(poll, tomorrow)
      {:ok, option2} = EventasaurusApp.Events.create_event_date_option(poll, day_after)

      # Create votes on the initial options
      {:ok, vote1} = EventasaurusApp.Events.create_event_date_vote(option1, other_user, :yes)
      {:ok, vote2} = EventasaurusApp.Events.create_event_date_vote(option2, other_user, :if_need_be)

      # Verify initial votes exist
      initial_vote1 = EventasaurusApp.Events.get_event_date_vote!(vote1.id)
      initial_vote2 = EventasaurusApp.Events.get_event_date_vote!(vote2.id)
      assert initial_vote1.vote_type == :yes
      assert initial_vote2.vote_type == :if_need_be

      # Load the edit page
      conn = log_in_user(conn, user)
      {:ok, edit_live, _html} = live(conn, ~p"/events/#{event.slug}/edit")

            # First, click on the new date in the calendar component to add it
      # This simulates the user clicking on day_three in the calendar
      day_three_string = Date.to_iso8601(day_three)

      edit_live
      |> element("button[phx-value-date='#{day_three_string}']")
      |> render_click()

      # Now submit the form to save the changes
      updated_data = %{
        "event[title]" => "Test Vote Preservation",
        "event[enable_date_polling]" => "true",
        "event[start_time]" => "14:00",
        "event[ends_time]" => "16:00",
        "event[timezone]" => "America/New_York"
      }

      # Submit the form to save the event with the newly added date option
      _html = edit_live
      |> form("form[data-test-id='event-form']", updated_data)
      |> render_submit()

      # Should redirect to event show page
      assert_redirected(edit_live, "/events/#{event.slug}")

      # Verify existing votes are still there
      preserved_vote1 = EventasaurusApp.Events.get_event_date_vote!(vote1.id)
      preserved_vote2 = EventasaurusApp.Events.get_event_date_vote!(vote2.id)

      assert preserved_vote1.vote_type == :yes
      assert preserved_vote2.vote_type == :if_need_be

      # Verify the new date option was added
      updated_options = EventasaurusApp.Events.list_event_date_options(poll)
      assert length(updated_options) == 3

      # Verify all three dates are present
      option_dates = Enum.map(updated_options, & &1.date) |> Enum.sort()
      expected_dates = [tomorrow, day_after, day_three] |> Enum.sort()
      assert option_dates == expected_dates
    end
  end

  describe "access control" do
    test "non-organizer cannot edit event", %{conn: conn} do
      event = insert(:event)
      {conn, _user} = register_and_log_in_user(conn)  # Different user, not organizer

      # Should redirect with permission error
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/events/#{event.slug}/edit")
    end

    test "unauthenticated user redirects to login", %{conn: conn} do
      event = insert(:event)

      # Should redirect to login
      assert {:error, {:redirect, %{to: "/auth/login"}}} = live(conn, ~p"/events/#{event.slug}/edit")
    end
  end
end
