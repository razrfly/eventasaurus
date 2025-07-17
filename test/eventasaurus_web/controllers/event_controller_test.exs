defmodule EventasaurusWeb.EventControllerTest do
  use EventasaurusWeb.ConnCase

  import EventasaurusApp.EventsFixtures

  describe "POST /api/events/:slug/add-details" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      event = event_fixture(%{"organizers" => [user]})
      %{conn: conn, user: user, event: event}
    end

    test "updates event details with valid taxation_type", %{conn: conn, event: event} do
      params = %{
        "title" => "Updated Event Title",
        "description" => "Updated description",
        "taxation_type" => "contribution_collection"
      }

      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", params)

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["event"]["title"] == "Updated Event Title"
      assert json["event"]["taxation_type"] == "contribution_collection"
    end

    test "updates event details without taxation_type parameter (backward compatibility)", %{
      conn: conn,
      event: event
    } do
      params = %{
        "title" => "Updated Title Only",
        "description" => "Updated description only"
      }

      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", params)

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["event"]["title"] == "Updated Title Only"
      # Should preserve existing taxation_type
      assert json["event"]["taxation_type"] == "ticketed_event"
    end

    test "returns validation error for invalid taxation_type", %{conn: conn, event: event} do
      params = %{
        "title" => "Updated Title",
        "taxation_type" => "invalid_type"
      }

      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", params)

      assert json = json_response(conn, 422)
      assert json["error"] == "Validation failed"

      assert json["details"]["taxation_type"] == [
               "must be one of: ticketed_event, contribution_collection"
             ]
    end

    test "returns 404 for non-existent event", %{conn: conn} do
      params = %{"title" => "Test"}

      conn = post(conn, ~p"/api/events/non-existent-slug/add-details", params)

      assert json = json_response(conn, 404)
      assert json["error"] == "Event not found"
    end

    test "returns 403 for unauthorized user", %{conn: _conn, event: event} do
      # Create different user (not an organizer)
      {conn, _other_user} = register_and_log_in_user(build_conn())
      params = %{"title" => "Unauthorized Update"}

      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", params)

      assert json = json_response(conn, 403)
      assert json["error"] == "You don't have permission to modify this event"
    end

    test "includes taxation_type in response for details profile", %{conn: conn, event: event} do
      params = %{"title" => "Test Response Format"}

      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", params)

      assert json = json_response(conn, 200)
      assert Map.has_key?(json["event"], "taxation_type")
      assert is_binary(json["event"]["taxation_type"])
    end
  end

  describe "POST /api/events/:slug/enable-ticketing" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      event = event_fixture(%{"organizers" => [user]})
      %{conn: conn, user: user, event: event}
    end

    test "enables ticketing successfully for ticketed_event", %{conn: conn, event: event} do
      conn = post(conn, ~p"/api/events/#{event.slug}/enable-ticketing")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert json["event"]["is_ticketed"] == true
      assert json["event"]["taxation_type"] == "ticketed_event"
    end

    test "returns validation error when enabling ticketing for contribution_collection", %{
      conn: conn,
      event: event
    } do
      # First update event to contribution_collection
      {:ok, updated_event} =
        EventasaurusApp.Events.add_details(event, %{taxation_type: "contribution_collection"})

      conn = post(conn, ~p"/api/events/#{updated_event.slug}/enable-ticketing")

      assert json = json_response(conn, 422)
      assert json["error"] == "Validation failed"

      assert json["details"]["is_ticketed"] == [
               "must be false for contribution collection events"
             ]
    end

    test "includes taxation_type in response", %{conn: conn, event: event} do
      conn = post(conn, ~p"/api/events/#{event.slug}/enable-ticketing")

      assert json = json_response(conn, 200)
      assert Map.has_key?(json["event"], "taxation_type")
      assert json["event"]["taxation_type"] == "ticketed_event"
    end
  end

  describe "POST /api/events/:slug/pick-date" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      event = event_fixture(%{"organizers" => [user]})
      %{conn: conn, user: user, event: event}
    end

    test "picks date and includes taxation_type in response", %{conn: conn, event: event} do
      future_date = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_iso8601()

      params = %{
        "start_at" => future_date,
        "timezone" => "UTC"
      }

      conn = post(conn, ~p"/api/events/#{event.slug}/pick-date", params)

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert Map.has_key?(json["event"], "taxation_type")
      assert json["event"]["taxation_type"] == "ticketed_event"
    end

    test "returns validation error for invalid datetime", %{conn: conn, event: event} do
      params = %{"start_at" => "invalid-datetime"}

      conn = post(conn, ~p"/api/events/#{event.slug}/pick-date", params)

      assert json = json_response(conn, 400)
      assert json["error"] == "Invalid datetime format. Use ISO8601 format."
    end
  end

  describe "POST /api/events/:slug/enable-polling" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      event = event_fixture(%{"organizers" => [user]})
      %{conn: conn, user: user, event: event}
    end

    test "enables polling and includes taxation_type in response", %{conn: conn, event: event} do
      future_date = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.to_iso8601()
      params = %{"polling_deadline" => future_date}

      conn = post(conn, ~p"/api/events/#{event.slug}/enable-polling", params)

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert Map.has_key?(json["event"], "taxation_type")
      assert json["event"]["taxation_type"] == "ticketed_event"
    end

    test "returns error when polling_deadline is missing", %{conn: conn, event: event} do
      conn = post(conn, ~p"/api/events/#{event.slug}/enable-polling")

      assert json = json_response(conn, 400)
      assert json["error"] == "polling_deadline is required"
    end
  end

  describe "POST /api/events/:slug/set-threshold" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      event = event_fixture(%{"organizers" => [user]})
      %{conn: conn, user: user, event: event}
    end

    test "sets threshold and includes taxation_type in response", %{conn: conn, event: event} do
      params = %{"threshold_count" => "10"}

      conn = post(conn, ~p"/api/events/#{event.slug}/set-threshold", params)

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert Map.has_key?(json["event"], "taxation_type")
      assert json["event"]["taxation_type"] == "ticketed_event"
    end

    test "returns error for invalid threshold_count", %{conn: conn, event: event} do
      params = %{"threshold_count" => "invalid"}

      conn = post(conn, ~p"/api/events/#{event.slug}/set-threshold", params)

      assert json = json_response(conn, 400)
      assert json["error"] == "threshold_count must be a positive integer"
    end

    test "returns error when threshold_count is missing", %{conn: conn, event: event} do
      conn = post(conn, ~p"/api/events/#{event.slug}/set-threshold")

      assert json = json_response(conn, 400)
      assert json["error"] == "threshold_count is required"
    end
  end

  describe "POST /api/events/:slug/publish" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      event = event_fixture(%{"organizers" => [user]})
      %{conn: conn, user: user, event: event}
    end

    test "publishes event and includes taxation_type in response", %{conn: conn, event: event} do
      conn = post(conn, ~p"/api/events/#{event.slug}/publish")

      assert json = json_response(conn, 200)
      assert json["success"] == true
      assert Map.has_key?(json["event"], "taxation_type")
      assert json["event"]["taxation_type"] == "ticketed_event"
    end
  end

  describe "integration tests" do
    setup do
      {conn, user} = register_and_log_in_user(build_conn())
      event = event_fixture(%{"organizers" => [user]})
      %{conn: conn, user: user, event: event}
    end

    test "complete workflow: create event → update taxation_type → enable ticketing fails", %{
      conn: conn,
      event: event
    } do
      # Step 1: Update event to contribution_collection
      update_params = %{"taxation_type" => "contribution_collection"}
      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", update_params)
      assert json_response(conn, 200)["event"]["taxation_type"] == "contribution_collection"

      # Step 2: Try to enable ticketing (should fail)
      conn = post(conn, ~p"/api/events/#{event.slug}/enable-ticketing")
      assert json = json_response(conn, 422)
      assert json["error"] == "Validation failed"

      assert json["details"]["is_ticketed"] == [
               "must be false for contribution collection events"
             ]
    end

    test "complete workflow: update between different taxation types", %{conn: conn, event: event} do
      # Start with default ticketed_event
      assert event.taxation_type == "ticketed_event"

      # Update to contribution_collection
      params1 = %{"taxation_type" => "contribution_collection"}
      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", params1)
      assert json_response(conn, 200)["event"]["taxation_type"] == "contribution_collection"

      # Update back to ticketed_event
      params2 = %{"taxation_type" => "ticketed_event"}
      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", params2)
      assert json_response(conn, 200)["event"]["taxation_type"] == "ticketed_event"
    end

    test "all action endpoints include taxation_type in their responses", %{
      conn: conn,
      event: event
    } do
      future_date_1 = DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_iso8601()
      future_date_2 = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.to_iso8601()

      # Test pick-date endpoint
      conn = post(conn, ~p"/api/events/#{event.slug}/pick-date", %{"start_at" => future_date_1})
      assert Map.has_key?(json_response(conn, 200)["event"], "taxation_type")

      # Test enable-polling endpoint
      conn =
        post(conn, ~p"/api/events/#{event.slug}/enable-polling", %{
          "polling_deadline" => future_date_2
        })

      assert Map.has_key?(json_response(conn, 200)["event"], "taxation_type")

      # Test set-threshold endpoint
      conn = post(conn, ~p"/api/events/#{event.slug}/set-threshold", %{"threshold_count" => "5"})
      assert Map.has_key?(json_response(conn, 200)["event"], "taxation_type")

      # Test enable-ticketing endpoint
      conn = post(conn, ~p"/api/events/#{event.slug}/enable-ticketing")
      assert Map.has_key?(json_response(conn, 200)["event"], "taxation_type")

      # Test add-details endpoint
      conn = post(conn, ~p"/api/events/#{event.slug}/add-details", %{"title" => "Updated Title"})
      assert Map.has_key?(json_response(conn, 200)["event"], "taxation_type")

      # Test publish endpoint
      conn = post(conn, ~p"/api/events/#{event.slug}/publish")
      assert Map.has_key?(json_response(conn, 200)["event"], "taxation_type")
    end
  end
end
