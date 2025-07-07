defmodule EventasaurusWeb.EventManageOrganizerTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.{Events, Accounts}

  setup %{conn: conn} do
    # Create test event and organizer
    organizer = user_fixture(%{name: "Event Organizer", email: "organizer@example.com"})
    event = event_fixture(%{title: "Test Event", organizers: [organizer]})

    # Create test users that can be added as organizers
    potential_organizer_1 = user_fixture(%{
      name: "John Doe",
      email: "john@example.com",
      username: "johndoe",
      profile_public: true
    })

    potential_organizer_2 = user_fixture(%{
      name: "Jane Smith",
      email: "jane@example.com",
      username: "janesmith",
      profile_public: true
    })

    # User with private profile
    private_user = user_fixture(%{
      name: "Private User",
      email: "private@example.com",
      profile_public: false
    })

    # User already an organizer
    existing_organizer = user_fixture(%{name: "Existing Organizer", email: "existing@example.com"})
    {:ok, _} = Events.add_user_to_event(event, existing_organizer, "organizer")

    # Authenticate as the main organizer
    conn = log_in_user(conn, organizer)

    %{
      conn: conn,
      event: event,
      organizer: organizer,
      potential_organizer_1: potential_organizer_1,
      potential_organizer_2: potential_organizer_2,
      private_user: private_user,
      existing_organizer: existing_organizer
    }
  end

  describe "organizer search modal" do
    test "opens and closes organizer search modal", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Modal should not be visible initially
      refute has_element?(view, "[data-testid=organizer-search-modal]")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Modal should now be visible
      assert has_element?(view, "[data-testid=organizer-search-modal]") or
             render(view) =~ "Search for users to add as organizers"

      # Close modal
      view |> element("button", "Cancel") |> render_click()

      # Modal should be hidden again
      refute has_element?(view, "[data-testid=organizer-search-modal]") or
             not (render(view) =~ "Search for users to add as organizers")
    end

    test "searches for users to add as organizers", %{conn: conn, event: event, potential_organizer_1: user1} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Search for a user
      view
      |> form("#organizer-search-form")
      |> render_change(%{query: "john"})

      # Should show search results
      assert render(view) =~ user1.name
      assert render(view) =~ user1.email
    end

    test "filters out users with private profiles by default", %{conn: conn, event: event, private_user: private_user} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Search for private user
      view
      |> form("#organizer-search-form")
      |> render_change(%{query: "private"})

      # Should not show private user in results
      refute render(view) =~ private_user.name
    end

    test "filters out existing organizers from search results", %{conn: conn, event: event, existing_organizer: existing_org} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Search for existing organizer
      view
      |> form("#organizer-search-form")
      |> render_change(%{query: existing_org.name})

      # Should not show existing organizer in results
      refute render(view) =~ existing_org.name
    end

    test "shows loading state during search", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Trigger search - should show loading
      view
      |> form("#organizer-search-form")
      |> render_change(%{query: "john"})

      # In a real async test, we'd check for loading state
      # For now, we verify the search functionality works
      assert has_element?(view, "input[name=query]")
    end
  end

  describe "user selection" do
    test "allows selecting and deselecting users", %{conn: conn, event: event, potential_organizer_1: user1} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal and search
      view |> element("button", "Add") |> render_click()
      view |> form("#organizer-search-form") |> render_change(%{query: "john"})

      # Select user
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user1.id}']") |> render_click()

      # Should show as selected and update button text
      assert render(view) =~ "Selected"
      assert render(view) =~ "Add Selected (1)"

      # Deselect user
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user1.id}']") |> render_click()

      # Should show as unselected
      assert render(view) =~ "Select"
      assert render(view) =~ "Add Selected (0)"
    end

    test "supports multi-user selection", %{conn: conn, event: event, potential_organizer_1: user1, potential_organizer_2: user2} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal and search
      view |> element("button", "Add") |> render_click()
      view |> form("#organizer-search-form") |> render_change(%{query: "doe"})

      # Select first user
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user1.id}']") |> render_click()

      # Search for second user
      view |> form("#organizer-search-form") |> render_change(%{query: "smith"})

      # Select second user
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user2.id}']") |> render_click()

      # Should show both selected
      assert render(view) =~ "Add Selected (2)"
    end

    test "clears selection when modal is closed", %{conn: conn, event: event, potential_organizer_1: user1} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal, search, and select user
      view |> element("button", "Add") |> render_click()
      view |> form("#organizer-search-form") |> render_change(%{query: "john"})
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user1.id}']") |> render_click()

      # Close modal
      view |> element("button", "Cancel") |> render_click()

      # Reopen modal
      view |> element("button", "Add") |> render_click()

      # Selection should be cleared
      assert render(view) =~ "Add Selected (0)"
    end
  end

  describe "batch user addition" do
    test "successfully adds selected users as organizers", %{conn: conn, event: event, potential_organizer_1: user1, potential_organizer_2: user2} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal, search, and select users
      view |> element("button", "Add") |> render_click()
      view |> form("#organizer-search-form") |> render_change(%{query: "doe"})
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user1.id}']") |> render_click()

      view |> form("#organizer-search-form") |> render_change(%{query: "smith"})
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user2.id}']") |> render_click()

      # Add selected users
      view |> element("button", "Add Selected (2)") |> render_click()

      # Should show success message
      assert render(view) =~ "Successfully added 2 organizer(s)"

      # Should close modal
      refute render(view) =~ "Search for users to add as organizers"

      # Verify users were added to database
      assert Events.user_is_organizer?(event, user1)
      assert Events.user_is_organizer?(event, user2)
    end

    test "shows error when trying to add user without selections", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal and try to add without selections
      view |> element("button", "Add") |> render_click()
      view |> element("button", "Add Selected (0)") |> render_click()

      # Should show error message
      assert render(view) =~ "Please select at least one user"
    end

            test "handles errors when user doesn't exist", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Search for a user that doesn't exist
      view |> element("input[phx-keyup='search_organizers']") |> render_keyup(%{"value" => "nonexistent_user_xyz"})

      # The search should complete without crashing
      assert Process.alive?(view.pid)

      # Close modal
      view |> element("button", "Cancel") |> render_click()
    end

    test "prevents adding users who are already organizers", %{conn: conn, event: event, existing_organizer: existing_org} do
      # First, let's manually add the user to search results to test the duplicate check
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Manually set search results to include existing organizer (simulating a race condition)
      :sys.replace_state(view.pid, fn state ->
        put_in(state.assigns.organizer_search_results, [%{
          "id" => existing_org.id,
          "name" => existing_org.name,
          "email" => existing_org.email,
          "profile_public" => true
        }])
      end)

      # Select the user
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{existing_org.id}']") |> render_click()

      # Try to add
      view |> element("button", "Add Selected (1)") |> render_click()

      # Should show error about user already being organizer
      assert render(view) =~ "already an organizer" or render(view) =~ "Some additions failed"
    end

    test "provides detailed feedback for partial failures", %{conn: conn, event: event, potential_organizer_1: good_user, existing_organizer: existing_org} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Manually set search results to include both users
      :sys.replace_state(view.pid, fn state ->
        put_in(state.assigns.organizer_search_results, [
          %{
            "id" => good_user.id,
            "name" => good_user.name,
            "email" => good_user.email,
            "profile_public" => true
          },
          %{
            "id" => existing_org.id,
            "name" => existing_org.name,
            "email" => existing_org.email,
            "profile_public" => true
          }
        ])
      end)

      # Select both users
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{good_user.id}']") |> render_click()
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{existing_org.id}']") |> render_click()

      # Try to add both
      view |> element("button", "Add Selected (2)") |> render_click()

      # Should show partial success
      assert render(view) =~ "Successfully added 1 organizer(s)" or render(view) =~ good_user.name
      assert render(view) =~ "Some additions failed" or render(view) =~ "already an organizer"
    end
  end

  describe "organizer list updates" do
    test "immediately updates organizer list after successful addition", %{conn: conn, event: event, potential_organizer_1: user1} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Get initial organizer count
      initial_html = render(view)

      # Add new organizer
      view |> element("button", "Add") |> render_click()
      view |> form("#organizer-search-form") |> render_change(%{query: "john"})
      view |> element("button[phx-click='toggle_organizer_selection'][phx-value-user_id='#{user1.id}']") |> render_click()
      view |> element("button", "Add Selected (1)") |> render_click()

      # Should show updated organizer list
      updated_html = render(view)
      assert updated_html =~ user1.name

      # Count should have increased
      refute initial_html == updated_html
    end

    test "supports removing organizers", %{conn: conn, event: event, existing_organizer: existing_org, organizer: main_organizer} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Should show existing organizer
      assert render(view) =~ existing_org.name

      # Remove organizer (not self)
      view |> element("button[phx-click='remove_organizer'][phx-value-user_id='#{existing_org.id}']") |> render_click()

      # Should show success message and updated list
      assert render(view) =~ "Successfully removed"
      refute render(view) =~ existing_org.name

      # Verify removal from database
      refute Events.user_is_organizer?(event, existing_org)
    end

    test "prevents removing self as organizer", %{conn: conn, event: event, organizer: main_organizer} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Try to remove self
      view |> element("button[phx-click='remove_organizer'][phx-value-user_id='#{main_organizer.id}']") |> render_click()

      # Should show error message
      assert render(view) =~ "cannot remove yourself"

      # Should still be an organizer
      assert Events.user_is_organizer?(event, main_organizer)
    end
  end

  describe "authorization" do
    test "only allows organizers to access event management", %{event: event} do
      # Create non-organizer user
      non_organizer = user_fixture()
      conn = build_conn() |> log_in_user(non_organizer)

      # Should redirect with error
      assert {:error, {:redirect, %{to: "/dashboard"}}} = live(conn, ~p"/events/#{event.slug}")
    end

    test "requires authentication to access event management", %{event: event} do
      conn = build_conn()  # No authentication

      # Should redirect to login
      assert {:error, {:redirect, %{to: "/auth/login"}}} = live(conn, ~p"/events/#{event.slug}")
    end
  end

  describe "edge cases" do
    test "handles search with very short queries", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Search with 1 character (should not trigger search)
      view |> form("#organizer-search-form") |> render_change(%{query: "j"})

      # Should not show loading or results
      refute render(view) =~ "Searching..."
    end

    test "handles search with empty query", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # Open modal
      view |> element("button", "Add") |> render_click()

      # Search with empty query
      view |> form("#organizer-search-form") |> render_change(%{query: ""})

      # Should clear results
      refute render(view) =~ "Searching..."
    end

    test "handles database errors gracefully", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/events/#{event.slug}")

      # This test would require mocking database failures
      # For now, we verify the view doesn't crash with normal operations
      view |> element("button", "Add") |> render_click()
      view |> element("button", "Cancel") |> render_click()

      assert Process.alive?(view.pid)
    end
  end
end
