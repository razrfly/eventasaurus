defmodule EventasaurusWeb.EventParticipantStatusControllerTest do
  use EventasaurusWeb.ConnCase

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  alias EventasaurusApp.Events

  describe "PUT /api/events/:slug/participant-status" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      # Create event with a different organizer to avoid constraint issues
      organizer = user_fixture(%{name: "Event Organizer", email: "organizer@example.com"})
      event = event_fixture(%{"organizers" => [organizer]})
      %{conn: conn, user: user, organizer: organizer, event: event}
    end

    test "updates user status to interested successfully", %{conn: conn, event: event} do
      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "interested"})

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "interested"
      assert json["data"]["event"]["slug"] == event.slug
      assert json["data"]["event"]["participant_count"] == 1
      assert is_binary(json["data"]["updated_at"])
    end

    test "updates user status to accepted successfully", %{conn: conn, event: event} do
      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "accepted"})

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "accepted"
      assert json["data"]["event"]["participant_count"] == 1
    end

    test "updates user status to declined successfully", %{conn: conn, event: event} do
      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "declined"})

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "declined"
      assert json["data"]["event"]["participant_count"] == 1
    end

    test "updates existing participant status", %{conn: conn, event: event, user: user} do
      # Create participant with interested status
      event_participant_fixture(%{
        event: event,
        user: user,
        status: :interested
      })

      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "accepted"})

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "accepted"

      # Verify the participant status was updated
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.status == :accepted
      assert participant.metadata["previous_status"] == "interested"
    end

    test "handles already existing status gracefully", %{conn: conn, event: event, user: user} do
      # Create participant already accepted
      event_participant_fixture(%{
        event: event,
        user: user,
        status: :accepted
      })

      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "accepted"})

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "accepted"
    end

    test "returns 400 for invalid status", %{conn: conn, event: event} do
      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{
          "status" => "invalid_status"
        })

      assert json = json_response(conn, 400)
      assert json["error"] =~ "Invalid status"

      assert json["error"] =~
               "pending, accepted, declined, cancelled, confirmed_with_order, interested"
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      conn =
        put(conn, ~p"/api/events/non-existent-slug/participant-status", %{
          "status" => "interested"
        })

      assert json = json_response(conn, 404)
      assert json["error"] == "Event not found"
    end

    test "returns 401 for unauthenticated user" do
      event = event_fixture()
      conn = build_conn()

      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "interested"})

      assert json = json_response(conn, 401)
      assert json["error"] == "unauthorized"
    end

    test "works for all valid statuses", %{conn: _conn, event: event} do
      valid_statuses = [
        "pending",
        "accepted",
        "declined",
        "cancelled",
        "confirmed_with_order",
        "interested"
      ]

      for status <- valid_statuses do
        # Create a new user for each test to avoid conflicts
        {new_conn, _new_user} = register_and_log_in_user(build_conn())

        conn_result =
          put(new_conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => status})

        assert json = json_response(conn_result, 200)
        assert json["success"] == true
        assert json["data"]["status"] == status
      end
    end
  end

  describe "DELETE /api/events/:slug/participant-status" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      # Create event with a different organizer
      organizer = user_fixture(%{name: "Event Organizer", email: "organizer@example.com"})
      event = event_fixture(%{"organizers" => [organizer]})
      %{conn: conn, user: user, organizer: organizer, event: event}
    end

    test "removes any participant status successfully", %{conn: conn, event: event, user: user} do
      # Create interested participant
      event_participant_fixture(%{
        event: event,
        user: user,
        status: :interested
      })

      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "removed"
      assert json["data"]["event"]["slug"] == event.slug

      # Verify participant was deleted
      assert Events.get_event_participant_by_event_and_user(event, user) == nil
    end

    test "removes specific status with query parameter", %{conn: conn, event: event, user: user} do
      # Create accepted participant
      event_participant_fixture(%{
        event: event,
        user: user,
        status: :accepted
      })

      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status?status=accepted")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "removed"

      # Verify participant was deleted
      assert Events.get_event_participant_by_event_and_user(event, user) == nil
    end

    test "doesn't remove participant with different status when filtered", %{
      conn: conn,
      event: event,
      user: user
    } do
      # Create accepted participant
      event_participant_fixture(%{
        event: event,
        user: user,
        status: :accepted
      })

      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status?status=interested")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "not_participant"

      # Verify participant still exists with original status
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.status == :accepted
    end

    test "returns not_participant for user with no participation", %{conn: conn, event: event} do
      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "not_participant"
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      conn = delete(conn, ~p"/api/events/non-existent-slug/participant-status")

      assert json = json_response(conn, 404)
      assert json["error"] == "Event not found"
    end

    test "returns 401 for unauthenticated user" do
      event = event_fixture()
      conn = build_conn()

      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status")

      assert json = json_response(conn, 401)
      assert json["error"] == "unauthorized"
    end
  end

  describe "GET /api/events/:slug/participant-status" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      # Create event with a different organizer
      organizer = user_fixture(%{name: "Event Organizer", email: "organizer@example.com"})
      event = event_fixture(%{"organizers" => [organizer]})
      %{conn: conn, user: user, organizer: organizer, event: event}
    end

    test "returns interested status with metadata", %{conn: conn, event: event, user: user} do
      # Create interested participant with metadata
      participant =
        event_participant_fixture(%{
          event: event,
          user: user,
          status: :interested
        })

      # Update metadata to include timestamp
      Events.update_event_participant(participant, %{
        metadata: %{"interested_at" => DateTime.utc_now()}
      })

      conn = get(conn, ~p"/api/events/#{event.slug}/participant-status")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "interested"
      assert is_binary(json["data"]["updated_at"])
      assert is_map(json["data"]["metadata"])
    end

    test "returns accepted status for accepted user", %{conn: conn, event: event, user: user} do
      event_participant_fixture(%{
        event: event,
        user: user,
        status: :accepted
      })

      conn = get(conn, ~p"/api/events/#{event.slug}/participant-status")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "accepted"
      assert is_binary(json["data"]["updated_at"])
    end

    test "returns not_participant for non-participant user", %{conn: conn, event: event} do
      conn = get(conn, ~p"/api/events/#{event.slug}/participant-status")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "not_participant"
      assert json["data"]["updated_at"] == nil
      assert json["data"]["metadata"] == nil
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      conn = get(conn, ~p"/api/events/non-existent-slug/participant-status")

      assert json = json_response(conn, 404)
      assert json["error"] == "Event not found"
    end

    test "returns 401 for unauthenticated user" do
      event = event_fixture()
      conn = build_conn()

      conn = get(conn, ~p"/api/events/#{event.slug}/participant-status")

      assert json = json_response(conn, 401)
      assert json["error"] == "unauthorized"
    end
  end

  describe "GET /api/events/:slug/participants/:status" do
    setup do
      {conn, organizer} =
        register_and_log_in_user(build_conn(), %{
          name: "Event Organizer",
          email: "organizer@example.com"
        })

      event = event_fixture(%{"organizers" => [organizer]})
      %{conn: conn, organizer: organizer, event: event}
    end

    test "lists interested participants successfully", %{conn: conn, event: event} do
      # Create interested participants
      user1 = user_fixture(%{name: "User 1", email: "user1@example.com"})
      user2 = user_fixture(%{name: "User 2", email: "user2@example.com"})

      event_participant_fixture(%{event: event, user: user1, status: :interested})
      event_participant_fixture(%{event: event, user: user2, status: :interested})

      conn = get(conn, ~p"/api/events/#{event.slug}/participants/interested")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "interested"
      assert length(json["data"]["participants"]) == 2

      participant = List.first(json["data"]["participants"])
      assert Map.has_key?(participant, "id")
      assert Map.has_key?(participant, "name")
      assert Map.has_key?(participant, "email")
      assert participant["status"] == "interested"
      assert is_binary(participant["updated_at"])
    end

    test "lists accepted participants successfully", %{conn: conn, event: event} do
      # Create accepted participant
      user = user_fixture(%{name: "Accepted User", email: "accepted@example.com"})
      event_participant_fixture(%{event: event, user: user, status: :accepted})

      conn = get(conn, ~p"/api/events/#{event.slug}/participants/accepted")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "accepted"
      assert length(json["data"]["participants"]) == 1
      assert List.first(json["data"]["participants"])["status"] == "accepted"
    end

    test "returns empty list for status with no participants", %{conn: conn, event: event} do
      conn = get(conn, ~p"/api/events/#{event.slug}/participants/declined")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["data"]["status"] == "declined"
      assert json["data"]["participants"] == []
      assert json["data"]["pagination"]["total_count"] == 0
    end

    test "supports pagination", %{conn: conn, event: event} do
      # Create multiple interested participants
      for i <- 1..25 do
        user = user_fixture(%{name: "User #{i}", email: "user#{i}@example.com"})
        event_participant_fixture(%{event: event, user: user, status: :interested})
      end

      # Get first page
      conn = get(conn, ~p"/api/events/#{event.slug}/participants/interested?page=1&per_page=10")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert length(json["data"]["participants"]) == 10
      assert json["data"]["pagination"]["current_page"] == 1
      assert json["data"]["pagination"]["total_count"] == 25
      assert json["data"]["pagination"]["total_pages"] == 3
    end

    test "returns 400 for invalid status", %{conn: conn, event: event} do
      conn = get(conn, ~p"/api/events/#{event.slug}/participants/invalid_status")

      assert json = json_response(conn, 400)
      assert json["error"] =~ "Invalid status"
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      conn = get(conn, ~p"/api/events/non-existent-slug/participants/interested")

      assert json = json_response(conn, 404)
      assert json["error"] == "Event not found"
    end

    test "returns 403 for non-organizer user", %{event: event} do
      # Create different user (not an organizer)
      {conn, _other_user} = register_and_log_in_user(build_conn())

      conn = get(conn, ~p"/api/events/#{event.slug}/participants/interested")

      assert json = json_response(conn, 403)
      assert json["error"] == "You don't have permission to view this event's data"
    end

    test "returns 401 for unauthenticated user" do
      event = event_fixture()
      conn = build_conn()

      conn = get(conn, ~p"/api/events/#{event.slug}/participants/interested")

      assert json = json_response(conn, 401)
      assert json["error"] == "unauthorized"
    end
  end

  describe "GET /api/events/:slug/participant-analytics" do
    setup do
      {conn, organizer} =
        register_and_log_in_user(build_conn(), %{
          name: "Event Organizer",
          email: "organizer@example.com"
        })

      event = event_fixture(%{"organizers" => [organizer]})
      %{conn: conn, organizer: organizer, event: event}
    end

    test "returns comprehensive participant analytics", %{conn: conn, event: event} do
      # Create participants with different statuses
      user1 = user_fixture(%{name: "User 1", email: "user1@example.com"})
      user2 = user_fixture(%{name: "User 2", email: "user2@example.com"})
      user3 = user_fixture(%{name: "User 3", email: "user3@example.com"})
      user4 = user_fixture(%{name: "User 4", email: "user4@example.com"})

      event_participant_fixture(%{event: event, user: user1, status: :interested})
      event_participant_fixture(%{event: event, user: user2, status: :accepted})
      event_participant_fixture(%{event: event, user: user3, status: :declined})
      event_participant_fixture(%{event: event, user: user4, status: :confirmed_with_order})

      conn = get(conn, ~p"/api/events/#{event.slug}/participant-analytics")

      assert json = json_response(conn, 200)
      assert json["success"] == true

      analytics = json["data"]["analytics"]
      assert analytics["total_participants"] == 4
      assert analytics["status_counts"]["interested"] == 1
      assert analytics["status_counts"]["accepted"] == 1
      assert analytics["status_counts"]["declined"] == 1
      assert analytics["status_counts"]["confirmed_with_order"] == 1
      assert analytics["status_counts"]["pending"] == 0
      assert analytics["status_counts"]["cancelled"] == 0

      # Check engagement metrics
      metrics = analytics["engagement_metrics"]
      assert is_float(metrics["response_rate"])
      assert is_float(metrics["conversion_rate"])
      assert is_float(metrics["interest_ratio"])

      # Check trends placeholder
      assert Map.has_key?(json["data"], "trends")
      assert is_list(json["data"]["trends"]["daily_changes"])
    end

    test "handles empty event analytics", %{conn: conn, event: event} do
      conn = get(conn, ~p"/api/events/#{event.slug}/participant-analytics")

      assert json = json_response(conn, 200)
      assert json["success"] == true

      analytics = json["data"]["analytics"]
      assert analytics["total_participants"] == 0
      assert analytics["status_counts"]["interested"] == 0
      assert analytics["engagement_metrics"]["response_rate"] == 0
      assert analytics["engagement_metrics"]["conversion_rate"] == 0
      assert analytics["engagement_metrics"]["interest_ratio"] == 0
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      conn = get(conn, ~p"/api/events/non-existent-slug/participant-analytics")

      assert json = json_response(conn, 404)
      assert json["error"] == "Event not found"
    end

    test "returns 403 for non-organizer user", %{event: event} do
      # Create different user (not an organizer)
      {conn, _other_user} = register_and_log_in_user(build_conn())

      conn = get(conn, ~p"/api/events/#{event.slug}/participant-analytics")

      assert json = json_response(conn, 403)
      assert json["error"] == "You don't have permission to view this event's data"
    end

    test "returns 401 for unauthenticated user" do
      event = event_fixture()
      conn = build_conn()

      conn = get(conn, ~p"/api/events/#{event.slug}/participant-analytics")

      assert json = json_response(conn, 401)
      assert json["error"] == "unauthorized"
    end
  end

  # Integration tests for complete workflows
  describe "Integration: Complete participant status workflows" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())

      {organizer_conn, organizer} =
        register_and_log_in_user(build_conn(), %{
          name: "Event Organizer",
          email: "organizer@example.com"
        })

      event = event_fixture(%{"organizers" => [organizer]})

      %{
        conn: conn,
        user: user,
        organizer: organizer,
        organizer_conn: organizer_conn,
        event: event
      }
    end

    test "full participant lifecycle: interested -> accepted -> confirmed", %{
      conn: conn,
      organizer_conn: organizer_conn,
      event: event,
      user: user
    } do
      # 1. User marks interest
      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "interested"})

      assert json_response(conn, 200)["data"]["status"] == "interested"

      # 2. Check analytics shows 1 interested
      analytics_conn = get(organizer_conn, ~p"/api/events/#{event.slug}/participant-analytics")
      analytics = json_response(analytics_conn, 200)["data"]["analytics"]
      assert analytics["status_counts"]["interested"] == 1
      assert analytics["total_participants"] == 1

      # 3. User accepts invitation
      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "accepted"})

      assert json_response(conn, 200)["data"]["status"] == "accepted"

      # 4. Check participant was updated
      participant = Events.get_event_participant_by_event_and_user(event, user)
      assert participant.status == :accepted
      assert participant.metadata["previous_status"] == "interested"

      # 5. User confirms with order
      conn =
        put(conn, ~p"/api/events/#{event.slug}/participant-status", %{
          "status" => "confirmed_with_order"
        })

      assert json_response(conn, 200)["data"]["status"] == "confirmed_with_order"

      # 6. Final analytics check
      analytics_conn = get(organizer_conn, ~p"/api/events/#{event.slug}/participant-analytics")
      final_analytics = json_response(analytics_conn, 200)["data"]["analytics"]
      assert final_analytics["status_counts"]["interested"] == 0
      assert final_analytics["status_counts"]["confirmed_with_order"] == 1
      assert final_analytics["total_participants"] == 1
    end

    test "organizer can view participants at each status", %{
      conn: conn,
      organizer_conn: organizer_conn,
      event: event
    } do
      # Create participants with different statuses
      {conn2, _user2} =
        register_and_log_in_user(build_conn(), %{name: "User 2", email: "user2@example.com"})

      {conn3, _user3} =
        register_and_log_in_user(build_conn(), %{name: "User 3", email: "user3@example.com"})

      # Set different statuses
      put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "interested"})
      put(conn2, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "accepted"})
      put(conn3, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "declined"})

      # Organizer views each status list
      interested_conn = get(organizer_conn, ~p"/api/events/#{event.slug}/participants/interested")
      accepted_conn = get(organizer_conn, ~p"/api/events/#{event.slug}/participants/accepted")
      declined_conn = get(organizer_conn, ~p"/api/events/#{event.slug}/participants/declined")

      assert length(json_response(interested_conn, 200)["data"]["participants"]) == 1
      assert length(json_response(accepted_conn, 200)["data"]["participants"]) == 1
      assert length(json_response(declined_conn, 200)["data"]["participants"]) == 1
    end

    test "participant removal works across all statuses", %{
      conn: conn,
      event: event,
      user: user
    } do
      # Set to interested
      put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "interested"})

      # Remove only interested status (should work)
      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status?status=interested")
      assert json_response(conn, 200)["data"]["status"] == "removed"
      assert Events.get_event_participant_by_event_and_user(event, user) == nil

      # Set to accepted
      put(conn, ~p"/api/events/#{event.slug}/participant-status", %{"status" => "accepted"})

      # Try to remove interested status (should not work)
      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status?status=interested")
      assert json_response(conn, 200)["data"]["status"] == "not_participant"
      assert Events.get_event_participant_by_event_and_user(event, user).status == :accepted

      # Remove any status (should work)
      conn = delete(conn, ~p"/api/events/#{event.slug}/participant-status")
      assert json_response(conn, 200)["data"]["status"] == "removed"
      assert Events.get_event_participant_by_event_and_user(event, user) == nil
    end
  end
end
