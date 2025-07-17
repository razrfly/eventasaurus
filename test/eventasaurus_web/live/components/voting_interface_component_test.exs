defmodule EventasaurusWeb.VotingInterfaceComponentTest do
  use EventasaurusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.{Poll, PollOption}
  alias EventasaurusWeb.VotingInterfaceComponent

  # Test setup
  setup do
    user = user_fixture()
    event = event_fixture()

    # Create polls for different voting systems
    {:ok, binary_poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Binary Poll",
        description: "A binary poll for testing",
        voting_system: "binary",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

    {:ok, approval_poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Approval Poll",
        description: "An approval poll for testing",
        voting_system: "approval",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

    {:ok, ranked_poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Ranked Poll",
        description: "A ranked choice poll for testing",
        voting_system: "ranked",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

    {:ok, star_poll} =
      Events.create_poll(%{
        event_id: event.id,
        title: "Star Poll",
        description: "A star rating poll for testing",
        voting_system: "star",
        poll_type: "general",
        status: "voting",
        created_by_id: user.id
      })

    # Create options for each poll
    for poll <- [binary_poll, approval_poll, ranked_poll, star_poll] do
      {:ok, _} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Option 1",
          description: "First option"
        })

      {:ok, _} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Option 2",
          description: "Second option"
        })

      {:ok, _} =
        Events.create_poll_option(%{
          poll_id: poll.id,
          title: "Option 3",
          description: "Third option"
        })
    end

    %{
      user: user,
      event: event,
      binary_poll: Events.get_poll!(binary_poll.id),
      approval_poll: Events.get_poll!(approval_poll.id),
      ranked_poll: Events.get_poll!(ranked_poll.id),
      star_poll: Events.get_poll!(star_poll.id)
    }
  end

  describe "VotingInterfaceComponent rendering" do
    test "renders binary voting interface", %{user: user, binary_poll: poll} do
      assigns = %{
        poll: poll,
        user: user,
        user_votes: [],
        show_results: false
      }

      html =
        render_component(VotingInterfaceComponent, assigns)

      assert html =~ "Binary Poll"
      assert html =~ "Option 1"
      assert html =~ "Option 2"
      assert html =~ "Option 3"
      assert html =~ "phx-click=\"vote_binary\""
      assert html =~ "Yes"
      assert html =~ "No"
    end

    test "renders approval voting interface", %{user: user, approval_poll: poll} do
      assigns = %{
        poll: poll,
        user: user,
        user_votes: [],
        show_results: false
      }

      html = render_component(VotingInterfaceComponent, assigns)

      assert html =~ "Approval Poll"
      assert html =~ "phx-click=\"toggle_approval\""
      assert html =~ "type=\"checkbox\""
    end

    test "renders ranked choice voting interface", %{user: user, ranked_poll: poll} do
      assigns = %{
        poll: poll,
        user: user,
        user_votes: [],
        show_results: false
      }

      html = render_component(VotingInterfaceComponent, assigns)

      assert html =~ "Ranked Poll"
      assert html =~ "Drag to rank"
      assert html =~ "phx-click=\"move_rank_up\""
      assert html =~ "phx-click=\"move_rank_down\""
    end

    test "renders star rating interface", %{user: user, star_poll: poll} do
      assigns = %{
        poll: poll,
        user: user,
        user_votes: [],
        show_results: false
      }

      html = render_component(VotingInterfaceComponent, assigns)

      assert html =~ "Star Poll"
      assert html =~ "phx-click=\"star_vote\""
      assert html =~ "⭐"
    end
  end

  describe "accessibility features" do
    test "includes proper ARIA labels for binary voting", %{user: user, binary_poll: poll} do
      assigns = %{poll: poll, user: user, user_votes: [], show_results: false}
      html = render_component(VotingInterfaceComponent, assigns)

      assert html =~ "role=\"group\""
      assert html =~ "aria-label=\"Vote on poll options\""
      assert html =~ "aria-describedby=\""
    end

    test "includes keyboard navigation support", %{user: user, approval_poll: poll} do
      assigns = %{poll: poll, user: user, user_votes: [], show_results: false}
      html = render_component(VotingInterfaceComponent, assigns)

      assert html =~ "tabindex=\"0\""
      assert html =~ "role=\"checkbox\""
    end

    test "provides screen reader announcements", %{user: user, ranked_poll: poll} do
      assigns = %{poll: poll, user: user, user_votes: [], show_results: false}
      html = render_component(VotingInterfaceComponent, assigns)

      assert html =~ "aria-live=\"polite\""
      assert html =~ "sr-only"
    end
  end

  describe "mobile responsiveness" do
    test "renders touch-friendly interfaces", %{user: user, star_poll: poll} do
      assigns = %{poll: poll, user: user, user_votes: [], show_results: false}
      html = render_component(VotingInterfaceComponent, assigns)

      # Check for mobile-friendly classes
      assert html =~ "touch-"
      # Larger text for mobile
      assert html =~ "text-lg"
      # Adequate padding for touch targets
      assert html =~ "p-4"
    end

    test "shows responsive design elements", %{user: user, approval_poll: poll} do
      assigns = %{poll: poll, user: user, user_votes: [], show_results: false}
      html = render_component(VotingInterfaceComponent, assigns)

      # Check for responsive grid/layout classes
      assert html =~ "grid"
      assert html =~ "md:"
      assert html =~ "lg:"
    end
  end

  describe "user vote state management" do
    test "shows existing user votes correctly", %{user: user, binary_poll: poll} do
      option = List.first(poll.poll_options)

      # Cast a vote first
      {:ok, _vote} = Events.cast_binary_vote(poll, option, user, "yes")

      # Get updated votes
      user_votes = Events.get_user_poll_votes(poll, user)

      assigns = %{
        poll: poll,
        user: user,
        user_votes: user_votes,
        show_results: false
      }

      html = render_component(VotingInterfaceComponent, assigns)

      # Should show the vote state
      # Voted state styling
      assert html =~ "bg-green-"
    end

    test "handles multiple approval votes", %{user: user, approval_poll: poll} do
      [option1, option2 | _] = poll.poll_options

      # Cast approval votes on multiple options
      {:ok, _} = Events.cast_approval_vote(poll, option1, user, true)
      {:ok, _} = Events.cast_approval_vote(poll, option2, user, true)

      user_votes = Events.get_user_poll_votes(poll, user)

      assigns = %{
        poll: poll,
        user: user,
        user_votes: user_votes,
        show_results: false
      }

      html = render_component(VotingInterfaceComponent, assigns)

      # Should show multiple selected states
      selected_count = Regex.scan(~r/checked/, html) |> length()
      assert selected_count >= 2
    end
  end

  describe "event handler testing" do
    test "binary vote event updates correctly" do
      # This would be tested in a LiveView test context
      # Here we verify the component structure supports the events
      assert function_exported?(VotingInterfaceComponent, :handle_event, 3)
    end
  end

  describe "performance and real-time updates" do
    test "component updates efficiently with new vote data", %{user: user, binary_poll: poll} do
      initial_assigns = %{poll: poll, user: user, user_votes: [], show_results: false}

      # Render initial state
      initial_html = render_component(VotingInterfaceComponent, initial_assigns)

      # Simulate vote
      option = List.first(poll.poll_options)
      {:ok, _vote} = Events.cast_binary_vote(poll, option, user, "yes")

      # Update assigns with vote
      updated_votes = Events.get_user_poll_votes(poll, user)
      updated_assigns = %{initial_assigns | user_votes: updated_votes}

      # Render updated state
      updated_html = render_component(VotingInterfaceComponent, updated_assigns)

      # Should show different states
      refute initial_html == updated_html
    end
  end
end
