defmodule EventasaurusWeb.PublicEventLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events
  alias EventasaurusApp.Auth.TestClient

  setup do
    event = event_fixture()

    # Clean up any existing test users
    TestClient.clear_test_users()

    %{event: event}
  end

  # Helper function to simulate authenticated user session
  defp authenticate_user(conn, user) do
    # Create a test token
    token = "test_token_#{user.id}"

    # Set up the mock user data that the TestClient will return
    # Convert the User struct to the format that Supabase would return
    supabase_user = %{
      "id" => user.supabase_id,
      "email" => user.email,
      "user_metadata" => %{"name" => user.name}
    }
    TestClient.set_test_user(token, supabase_user)

    # Add the token to the session
    conn = conn |> Plug.Test.init_test_session(%{"access_token" => token})
    {conn, token}
  end

  # Helper function to create a registration for testing
  defp registration_fixture(attrs) do
    event_participant_fixture(attrs)
  end

  describe "Phase 1: Basic State Display Tests" do
    test "anonymous user shows register button", %{conn: conn, event: event} do
      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show Register for Event button for anonymous users
      assert html =~ "Register for Event"
      assert html =~ "Register for this event"
      # Should NOT show One-Click Register
      refute html =~ "One-Click Register"
      # Should show registration card title
      assert html =~ "Register for this event"
    end

    test "authenticated user not registered shows one-click register", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show user info
      assert html =~ user.name
      assert html =~ user.email
      # Should show One-Click Register button
      assert html =~ "One-Click Register"
      # Should NOT show Register for Event
      refute html =~ "Register for Event"
    end

    test "registered user shows you're in status", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create an accepted registration for this user (accepted = registered)
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :accepted})

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show You're In status (HTML entity encoded)
      assert html =~ "You&#39;re In"
      assert html =~ "You&#39;re registered for this event"
      # Should NOT show register buttons
      refute html =~ "Register for Event"
      refute html =~ "One-Click Register"
      # Should show Cancel registration option (HTML entity encoded)
      assert html =~ "Can&#39;t attend? Cancel registration"
    end

    test "cancelled user shows you're not going status", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create a cancelled registration for this user
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :cancelled})

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show You're Not Going status (HTML entity encoded)
      assert html =~ "You&#39;re Not Going"
      assert html =~ "We hope to see you next time!"
      # Should show Register Again button
      assert html =~ "Register Again"
      # Should NOT show other registration buttons
      refute html =~ "Register for Event"
      refute html =~ "One-Click Register"
    end

    test "event organizer shows organizer status", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Make this user the organizer by adding them to event.users
      # First remove existing organizer, then add our test user
      Events.remove_user_from_event(event, hd(event.users))
      Events.add_user_to_event(event, user)

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show Event Organizer status
      assert html =~ "Event Organizer"
      assert html =~ "You&#39;re hosting this event"
      # Should NOT show register buttons
      refute html =~ "Register for Event"
      refute html =~ "One-Click Register"
      refute html =~ "Register Again"
      # Should show management options
      assert html =~ "Manage Event"
    end
  end

  describe "Phase 2: Interactive Functionality Tests" do
    test "anonymous user registration modal opens", %{conn: conn, event: event} do
      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show Register for Event button
      assert html =~ "Register for Event"
      assert has_element?(view, "#register-now-btn")
      # Should not show the modal initially
      refute has_element?(view, "#registration-modal")

      # Click the Register for Event button using the phx-click event
      html = render_click(view, "show_registration_modal")

      # Should show the registration modal component with unique text
      assert html =~ "Register for Event"
      assert html =~ "Your Info"
      assert html =~ "We&#39;ll create an account for you"
      # Should contain form elements for registration
      assert html =~ "registration[name]"
      assert html =~ "registration[email]"
    end

    test "one-click register works", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show One-Click Register button
      assert html =~ "One-Click Register"

      # Click the One-Click Register button
      html = render_click(view, "one_click_register")

      # Should show registration success
      assert html =~ "You&#39;re In"
      assert html =~ "You&#39;re registered for this event"
      # Should no longer show registration buttons
      refute html =~ "One-Click Register"
      refute html =~ "Register for Event"
    end

    test "cancel registration works", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create a registration for this user first
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :accepted})

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show registered status
      assert html =~ "You&#39;re In"
      assert html =~ "Can&#39;t attend? Cancel registration"

      # Click the cancel registration button
      html = render_click(view, "cancel_registration")

      # Should show cancelled status
      assert html =~ "You&#39;re Not Going"
      assert html =~ "We hope to see you next time!"
      assert html =~ "Register Again"
      # Should no longer show registered status
      refute html =~ "You&#39;re In"
    end

    test "re-register works for cancelled user", %{conn: conn, event: event} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      # Create a cancelled registration for this user
      registration_fixture(%{event_id: event.id, user_id: user.id, status: :cancelled})

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show cancelled status
      assert html =~ "You&#39;re Not Going"
      assert html =~ "Register Again"

      # Click the Register Again button
      html = render_click(view, "reregister")

      # Should show registered status
      assert html =~ "You&#39;re In"
      assert html =~ "You&#39;re registered for this event"
      # Should no longer show cancelled status
      refute html =~ "You&#39;re Not Going"
      refute html =~ "Register Again"
    end

    test "registration modal contains required form elements", %{conn: conn, event: event} do
      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Open the registration modal
      html = render_click(view, "show_registration_modal")

      # Verify the modal opens and contains all required form elements
      assert html =~ "Register for Event"
      assert html =~ "Your Info"
      assert html =~ "We&#39;ll create an account for you so you can manage your registration."

      # Check form elements are present
      assert has_element?(view, "form#registration-form")
      assert has_element?(view, "input[name='registration[name]']")
      assert has_element?(view, "input[name='registration[email]']")
      assert has_element?(view, "button[type='submit']")

      # Check that the form has proper attributes for component targeting
      assert html =~ "phx-submit=\"submit\""
      assert html =~ "phx-change=\"validate\""

      # Verify the modal can be interacted with
      assert has_element?(view, "button", "Register for Event")
    end
  end

  describe "Phase 3: Date Polling Voting Interface Tests" do
    setup %{event: event} do
      # Create an event with date polling enabled
      user = user_fixture()

      # Update event to polling state
      {:ok, polling_event} = Events.update_event(event, %{state: "polling"})

      # Create a date poll for the event
      {:ok, poll} = Events.create_event_date_poll(polling_event, user, %{})

      # Create some date options (using future dates to avoid validation issues)
      start_date = Date.add(Date.utc_today(), 7)  # 1 week from now
      end_date = Date.add(start_date, 7)          # 2 weeks from now
      {:ok, _options} = Events.create_date_options_from_range(poll, start_date, end_date)

      # Reload the poll with options
      poll = Events.get_event_date_poll!(poll.id) |> EventasaurusApp.Repo.preload(:date_options)

      %{polling_event: polling_event, poll: poll, organizer: user}
    end

    test "anonymous user sees voting summary but cannot vote", %{conn: conn, polling_event: event, poll: poll} do
      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show the voting interface section
      assert html =~ "Vote on Event Date"
      assert html =~ "Help us find the best date that works for everyone"

      # Should show date options with vote tallies
      for option <- poll.date_options do
        formatted_date = Calendar.strftime(option.date, "%A, %B %d, %Y")
        assert html =~ formatted_date
        assert html =~ "0 votes"  # No votes yet
        assert html =~ "0.0% positive"
      end

      # Should NOT show voting buttons for anonymous users
      refute html =~ "phx-click=\"cast_vote\""

      # Should show call-to-action to register
      assert html =~ "Want to vote on the event date?"
      assert html =~ "Register to Vote"
    end

    test "authenticated user sees voting interface with voting buttons", %{conn: conn, polling_event: event, poll: poll} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/#{event.slug}")

      # Should show the voting interface section
      assert html =~ "Vote on Event Date"
      assert html =~ "Help us find the best date that works for everyone"

      # Should show date options with voting buttons
      for option <- poll.date_options do
        formatted_date = Calendar.strftime(option.date, "%A, %B %d, %Y")
        assert html =~ formatted_date
        assert html =~ "0 votes"  # No votes yet

        # Should show voting buttons for each option
        assert has_element?(view, "button[phx-click='cast_vote'][phx-value-option_id='#{option.id}'][phx-value-vote_type='yes']", "Yes")
        assert has_element?(view, "button[phx-click='cast_vote'][phx-value-option_id='#{option.id}'][phx-value-vote_type='if_need_be']", "If needed")
        assert has_element?(view, "button[phx-click='cast_vote'][phx-value-option_id='#{option.id}'][phx-value-vote_type='no']", "No")
      end

      # Should NOT show register to vote call-to-action
      refute html =~ "Register to Vote"
    end

    test "user can cast votes on date options", %{conn: conn, polling_event: event, poll: poll} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      # Get the first date option
      first_option = hd(poll.date_options)

      # Cast a "yes" vote
      html = render_click(view, "cast_vote", %{
        "option_id" => to_string(first_option.id),
        "vote_type" => "yes"
      })

      # Should show success message
      assert html =~ "Your vote has been recorded!"

      # Should show the user's vote
      assert html =~ "Your vote: Yes"

      # Should show updated vote tally
      assert html =~ "1 vote"
      assert html =~ "100.0% positive"

      # Should show remove vote button
      assert has_element?(view, "button[phx-click='remove_vote'][phx-value-option_id='#{first_option.id}']")
    end

    test "user can change their vote", %{conn: conn, polling_event: event, poll: poll} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      first_option = hd(poll.date_options)

      # Cast initial "yes" vote
      render_click(view, "cast_vote", %{
        "option_id" => to_string(first_option.id),
        "vote_type" => "yes"
      })

      # Change to "if_need_be" vote
      html = render_click(view, "cast_vote", %{
        "option_id" => to_string(first_option.id),
        "vote_type" => "if_need_be"
      })

      # Should show updated vote
      assert html =~ "Your vote: If needed"
      assert html =~ "Your vote has been recorded!"

      # Should show updated percentage (if_need_be = 0.5 score)
      assert html =~ "50.0% positive"
    end

    test "user can remove their vote", %{conn: conn, polling_event: event, poll: poll} do
      user = user_fixture()
      {conn, _token} = authenticate_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      first_option = hd(poll.date_options)

      # Cast initial vote
      render_click(view, "cast_vote", %{
        "option_id" => to_string(first_option.id),
        "vote_type" => "yes"
      })

      # Remove the vote
      html = render_click(view, "remove_vote", %{
        "option_id" => to_string(first_option.id)
      })

      # Should show removal confirmation
      assert html =~ "Your vote has been removed."

      # Should no longer show user's vote
      refute html =~ "Your vote:"

      # Should show zero votes again
      assert html =~ "0 votes"
      assert html =~ "0.0% positive"

      # Should not show remove vote button
      refute has_element?(view, "button[phx-click='remove_vote'][phx-value-option_id='#{first_option.id}']")
    end

    test "vote tallies display correctly with multiple users", %{conn: conn, polling_event: event, poll: poll} do
      user1 = user_fixture()
      user2 = user_fixture()

      first_option = hd(poll.date_options)

      # Create votes directly in the database to simulate multiple users
      {:ok, _vote1} = Events.cast_vote(first_option, user1, :yes)
      {:ok, _vote2} = Events.cast_vote(first_option, user2, :if_need_be)

      # Now view as a third user
      user3 = user_fixture()
      {conn, _token} = authenticate_user(conn, user3)

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show correct vote counts
      assert html =~ "2 votes"

      # Should show correct breakdown (1 yes + 1 if_need_be = 75% positive)
      assert html =~ "75.0% positive"

      # Should show individual vote counts in the visualization
      assert html =~ "Yes: 1"
      assert html =~ "If needed: 1"
      assert html =~ "No: 0"
    end

    test "non-polling events do not show voting interface", %{conn: conn} do
      # Create a completely separate event for this test (not using the modified event from setup)
      separate_event = event_fixture()

      # Ensure the event is not in polling state
      {:ok, regular_event} = Events.update_event(separate_event, %{state: "confirmed"})

      # Visit the event page
      {:ok, view, html} = live(conn, ~p"/#{regular_event.slug}")

      # Should not show voting interface
      refute html =~ "Vote on Event Date"
      refute has_element?(view, "[data-testid='voting-interface']")
    end

    test "voting requires authentication", %{conn: conn, polling_event: event, poll: poll} do
      {:ok, view, _html} = live(conn, ~p"/#{event.slug}")

      first_option = hd(poll.date_options)

      # Try to vote as anonymous user (should fail gracefully)
      html = render_click(view, "cast_vote", %{
        "option_id" => to_string(first_option.id),
        "vote_type" => "yes"
      })

      # Should show error message
      assert html =~ "Please log in to vote on event dates."

      # Vote count should remain zero
      assert html =~ "0 votes"
    end

    test "vote tally visualization shows correct proportions", %{conn: conn, polling_event: event, poll: poll} do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      first_option = hd(poll.date_options)

      # Create a mix of votes: 2 yes, 1 if_need_be, 1 no
      {:ok, _vote1} = Events.cast_vote(first_option, user1, :yes)
      {:ok, _vote2} = Events.cast_vote(first_option, user2, :yes)
      {:ok, _vote3} = Events.cast_vote(first_option, user3, :if_need_be)

      # View as another user
      user4 = user_fixture()
      {conn, _token} = authenticate_user(conn, user4)

      {:ok, _view, html} = live(conn, ~p"/#{event.slug}")

      # Should show correct total
      assert html =~ "3 votes"

      # Should show correct percentage: (2*1.0 + 1*0.5) / 3 = 83.3%
      assert html =~ "83.3% positive"

      # Should show correct individual counts
      assert html =~ "Yes: 2"
      assert html =~ "If needed: 1"
      assert html =~ "No: 0"

      # Should show visualization bars (checking for style attributes)
      # Yes: 2/3 = 66.67%
      assert html =~ "width: 66.66666666666666%"
      # If needed: 1/3 = 33.33%
      assert html =~ "width: 33.33333333333333%"
    end
  end
end
