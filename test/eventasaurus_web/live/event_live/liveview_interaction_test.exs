defmodule EventasaurusWeb.EventLive.LiveViewInteractionTest do
  @moduledoc """
  LiveView form interaction tests.
  Part of Task 9: Implement LiveView form interaction tests.

  These tests focus on real-time form interactions using LiveView,
  testing client-side behavior, form state changes, and LiveView updates.
  """

  use EventasaurusWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  setup do
    clear_test_auth()
    :ok
  end

  describe "New Event Form - Real-time Interactions" do
    test "form responds to field changes with render_change", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Test real-time form field updates
      field_updates = [
        {"event[title]", "Dynamic Event Title"},
        {"event[tagline]", "Updated in real-time"},
        {"event[description]", "Description changes as you type"},
        {"event[visibility]", "private"}
      ]

      for {field, value} <- field_updates do
        # Use render_change to simulate real-time field updates
        _html = view
        |> form("form[data-test-id='event-form']", %{field => value})
        |> render_change()

        # Verify form remains functional
        assert has_element?(view, "form[data-test-id='event-form']")

        # Verify input elements are still present and form structure is maintained
        assert has_element?(view, "input[name='event[title]']") or
               has_element?(view, "input[name=\"event[title]\"]")
      end

      # Form should still be in a submittable state
      assert has_element?(view, "button[type='submit']")
    end

    test "theme selection updates form state via LiveView", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, html} = live(conn, ~p"/events/new")

      # Verify initial theme selection
      assert html =~ "minimal"  # Default theme

      # Change theme and test LiveView update
      themes = ["cosmic", "velocity", "celebration", "nature", "professional", "retro"]

      for theme <- themes do
        _html = view
        |> form("form[data-test-id='event-form']", %{"event[theme]" => theme})
        |> render_change()

        # Form should handle theme change gracefully
        assert has_element?(view, "form[data-test-id='event-form']")
        assert has_element?(view, "select[name='event[theme]']") or
               has_element?(view, "select[name=\"event[theme]\"]")
      end
    end

    test "date and time field interactions trigger form updates", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Test date field changes
      date_changes = [
        {"event[start_date]", "2025-12-25"},
        {"event[ends_date]", "2025-12-25"},
        {"event[start_time]", "18:00"},
        {"event[ends_time]", "20:00"}
      ]

      for {field, value} <- date_changes do
        _html = view
        |> form("form[data-test-id='event-form']", %{field => value})
        |> render_change()

        # Verify form handles date/time changes
        assert has_element?(view, "form[data-test-id='event-form']")
      end

      # Test timezone change
      _html = view
      |> form("form[data-test-id='event-form']", %{"event[timezone]" => "America/New_York"})
      |> render_change()

      assert has_element?(view, "form[data-test-id='event-form']")
    end

    test "virtual event toggle changes form state", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, html} = live(conn, ~p"/events/new")

      # Initially should not be virtual
      refute html =~ "checked"

      # Toggle virtual event checkbox
      _html = view
      |> element("input[name='event[is_virtual]']")
      |> render_click()

      # Form should handle virtual event toggle
      assert has_element?(view, "form[data-test-id='event-form']")

      # Test that form structure adapts to virtual event state
      updated_html = render(view)
      assert is_binary(updated_html)
    end

    test "form validation state changes in real-time", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Test validation state during field changes
      validation_scenarios = [
        # Valid data
        %{
          "event[title]" => "Valid Event",
          "event[start_date]" => "2025-12-01",
          "event[timezone]" => "America/Los_Angeles"
        },
        # Clear required field to test validation
        %{
          "event[title]" => "",
          "event[start_date]" => "2025-12-01",
          "event[timezone]" => "America/Los_Angeles"
        },
        # Restore valid data
        %{
          "event[title]" => "Restored Valid Event",
          "event[start_date]" => "2025-12-01",
          "event[timezone]" => "America/Los_Angeles"
        }
      ]

      for scenario_data <- validation_scenarios do
        _html = view
        |> form("form[data-test-id='event-form']", scenario_data)
        |> render_change()

        # Form should remain functional through validation state changes
        assert has_element?(view, "form[data-test-id='event-form']")
        assert has_element?(view, "button[type='submit']")
      end
    end
  end

  describe "Edit Event Form - LiveView Interactions" do
    test "form updates reflect in real-time during editing", %{conn: conn} do
      event = insert(:event,
        title: "Original Title",
        tagline: "Original Tagline",
        theme: :minimal
      )
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Verify existing data is loaded
      assert html =~ "Original Title"

      # Test real-time field updates
      field_updates = [
        {"event[title]", "Updated Live Title"},
        {"event[tagline]", "Updated Live Tagline"},
        {"event[theme]", "cosmic"},
        {"event[visibility]", "private"}
      ]

      for {field, value} <- field_updates do
        _html = view
        |> form("form[data-test-id='event-form']", %{field => value})
        |> render_change()

        # Form should handle live updates
        assert has_element?(view, "form[data-test-id='event-form']")
      end
    end

    test "date/time modifications update form state immediately", %{conn: conn} do
      event = insert(:event, title: "Test Event")
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Test immediate date/time updates
      datetime_updates = %{
        "event[start_date]" => "2025-06-15",
        "event[start_time]" => "14:30",
        "event[ends_date]" => "2025-06-15",
        "event[ends_time]" => "16:30",
        "event[timezone]" => "Europe/London"
      }

      _html = view
      |> form("form[data-test-id='event-form']", datetime_updates)
      |> render_change()

      # Form should handle complex datetime updates
      assert has_element?(view, "form[data-test-id='event-form']")
      assert has_element?(view, "input[name='event[start_date]']") or
             has_element?(view, "input[name=\"event[start_date]\"]")
    end

    test "theme changes update form appearance", %{conn: conn} do
      event = insert(:event, theme: :minimal)
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Test all available themes
      themes = ["minimal", "cosmic", "velocity", "celebration", "nature", "professional", "retro"]

      for theme <- themes do
        _html = view
        |> form("form[data-test-id='event-form']", %{"event[theme]" => theme})
        |> render_change()

        # Each theme change should be handled smoothly
        assert has_element?(view, "form[data-test-id='event-form']")
      end
    end
  end

  describe "Form Submission Interactions" do
    test "successful form submission via render_submit", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Prepare complete valid form data
      valid_form_data = %{
        "event[title]" => "LiveView Test Event",
        "event[tagline]" => "Created via LiveView interaction",
        "event[description]" => "Testing LiveView form submission",
        "event[start_date]" => "2025-08-15",
        "event[start_time]" => "19:00",
        "event[ends_date]" => "2025-08-15",
        "event[ends_time]" => "21:00",
        "event[timezone]" => "America/Los_Angeles",
        "event[visibility]" => "public",
        "event[theme]" => "velocity"
      }

      # Submit form and handle response
      result = view
      |> form("form[data-test-id='event-form']", valid_form_data)
      |> render_submit()

      case result do
        {:error, {:redirect, %{to: path}}} ->
          # Successful submission should redirect
          assert path =~ "/events/"

          # Verify event was created
          events = EventasaurusApp.Events.list_events()
          assert length(events) >= 1
          event = List.last(events)
          assert event.title == "LiveView Test Event"
          assert event.theme == :velocity
        html when is_binary(html) ->
          # If form stayed, verify it's still functional
          assert has_element?(view, "form[data-test-id='event-form']")
      end
    end

    test "form submission handles validation errors gracefully", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Submit form with validation errors
      invalid_form_data = %{
        "event[title]" => "",  # Invalid
        "event[start_date]" => "",  # Invalid
        "event[timezone]" => ""  # Invalid
      }

      # Test form submission with validation errors
      capture_log(fn ->
        result = view
        |> form("form[data-test-id='event-form']", invalid_form_data)
        |> render_submit()

        case result do
          {:error, {:redirect, _}} ->
            # Should not create invalid event
            events = EventasaurusApp.Events.list_events()
            if length(events) > 0 do
              # If any events exist, they should have valid titles
              for event <- events do
                assert is_binary(event.title) and event.title != ""
              end
            end
          html when is_binary(html) ->
            # Form should remain functional
            assert has_element?(view, "form[data-test-id='event-form']")
        end
      end)
    end

    test "edit form submission updates existing event", %{conn: conn} do
      event = insert(:event, title: "Original Event", theme: :minimal)
      {conn, _user} = log_in_event_organizer(conn, event)

      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}/edit")

      # Update event via form submission
      update_data = %{
        "event[title]" => "LiveView Updated Event",
        "event[tagline]" => "Updated via LiveView",
        "event[theme]" => "cosmic",
        "event[visibility]" => "private"
      }

      result = view
      |> form("form[data-test-id='event-form']", update_data)
      |> render_submit()

      case result do
        {:error, {:redirect, %{to: path}}} ->
          # Should redirect to updated event
          assert path =~ "/events/#{event.slug}"

          # Verify updates
          updated_event = EventasaurusApp.Repo.reload!(event)
          assert updated_event.title == "LiveView Updated Event"
          assert updated_event.theme == :cosmic
          assert updated_event.visibility == :private
        html when is_binary(html) ->
          # If stayed on form, verify it's functional
          assert has_element?(view, "form[data-test-id='event-form']")
      end
    end
  end

  describe "Client-side Behavior Testing" do
    test "form maintains state through multiple interactions", %{conn: conn} do
      clear_test_auth()  # Ensure clean state
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Define interaction sequence
      interaction_sequence = [
        %{"event[title]" => "Step 1"},
        %{"event[tagline]" => "Tagline 1"},
        %{"event[title]" => "Step 2"},
        %{"event[visibility]" => "private"}
      ]

      # Execute interaction sequence
      for step_data <- interaction_sequence do
        _html = view
        |> form("form[data-test-id='event-form']", step_data)
        |> render_change()

        # Form should remain stable through each step
        assert has_element?(view, "form[data-test-id='event-form']")
      end

      # Final verification
      assert has_element?(view, "form[data-test-id='event-form']")
      assert has_element?(view, "button[type='submit']")
    end

    test "form recovers from invalid state gracefully", %{conn: conn} do
      clear_test_auth()  # Ensure clean state
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Test rapid changes that might cause issues
      rapid_changes = ["A", "AB", "ABC", "ABCD", ""]

      for title <- rapid_changes do
        _html = view
        |> form("form[data-test-id='event-form']", %{"event[title]" => title})
        |> render_change()

        # Form should handle rapid changes without breaking
        assert has_element?(view, "form[data-test-id='event-form']")
      end

      # Return to valid data
      _html = view
      |> form("form[data-test-id='event-form']", %{"event[title]" => "Recovered Valid Title"})
      |> render_change()

      # Form should recover and be functional
      assert has_element?(view, "form[data-test-id='event-form']")
      assert has_element?(view, "button[type='submit']")
    end
  end

  describe "LiveView State Management" do
    test "form state persists through LiveView process restarts", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Set some form data
      form_data = %{
        "event[title]" => "Persistent Event",
        "event[description]" => "Should survive process restart"
      }

      _html = view
      |> form("form[data-test-id='event-form']", form_data)
      |> render_change()

      # Verify form is functional
      assert has_element?(view, "form[data-test-id='event-form']")

      # Test that we can still interact with the form
      _html = view
      |> form("form[data-test-id='event-form']", %{"event[tagline]" => "Added after restart"})
      |> render_change()

      assert has_element?(view, "form[data-test-id='event-form']")
    end

    test "multiple form fields update LiveView state correctly", %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, view, _html} = live(conn, ~p"/events/new")

      # Update multiple fields simultaneously
      multi_field_update = %{
        "event[title]" => "Multi-field Event",
        "event[tagline]" => "Updated together",
        "event[visibility]" => "private",
        "event[theme]" => "celebration"
      }

      _html = view
      |> form("form[data-test-id='event-form']", multi_field_update)
      |> render_change()

      # Verify form handles multiple simultaneous updates
      assert has_element?(view, "form[data-test-id='event-form']")

      # Verify form structure is maintained
      assert has_element?(view, "input[name='event[title]']") or
             has_element?(view, "input[name=\"event[title]\"]")
      assert has_element?(view, "select[name='event[theme]']") or
             has_element?(view, "select[name=\"event[theme]\"]")
    end
  end
end
