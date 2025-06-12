defmodule EventasaurusWeb.ActionDrivenApiIntegrationTest do
  use EventasaurusWeb.ConnCase

  import EventasaurusApp.EventsFixtures
  import EventasaurusApp.AccountsFixtures

  describe "Action-Driven Setup API Integration" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      %{user: user, event: event}
    end

    test "complete workflow: create event -> enable polling -> set threshold -> publish", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      # Step 1: Enable polling on the event
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)

      conn = post(conn, ~p"/events/#{event.slug}/enable-polling", %{
        "polling_deadline" => DateTime.to_iso8601(future_deadline)
      })

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["status"] == "polling"
      assert updated_event["polling_deadline"] != nil

      # Step 2: Try to set threshold while polling is active (should fail due to status inference)
      conn = post(conn, ~p"/events/#{event.slug}/set-threshold", %{
        "threshold_count" => "10"
      })

      assert %{"error" => "Validation failed", "details" => details} = json_response(conn, 422)
      assert details["status"] != nil

            # Step 3: Pick a specific date (this should work and override polling)
      future_date = DateTime.add(DateTime.utc_now(), 30, :day)

      conn = post(conn, ~p"/events/#{event.slug}/pick-date", %{
        "start_at" => DateTime.to_iso8601(future_date),
        "timezone" => "America/New_York"
      })

      assert %{"success" => true, "event" => date_event} = json_response(conn, 200)
      assert date_event["start_at"] != nil
      assert date_event["timezone"] == "America/New_York"
      # Picking a date should clear polling_deadline and change status
      assert date_event["polling_deadline"] == nil
      assert date_event["status"] == "confirmed"

      # Step 4: Now set threshold (should work since polling ended)
      conn = post(conn, ~p"/events/#{event.slug}/set-threshold", %{
        "threshold_count" => "15"
      })

      assert %{"success" => true, "event" => threshold_event} = json_response(conn, 200)
      assert threshold_event["threshold_count"] == 15
      assert threshold_event["status"] == "threshold"

      # Step 5: Add event details (this should work while maintaining threshold status)
      conn = post(conn, ~p"/events/#{event.slug}/add-details", %{
        "title" => "Updated Event Title",
        "description" => "This is an updated description",
        "tagline" => "Amazing event!"
      })

      assert %{"success" => true, "event" => detailed_event} = json_response(conn, 200)
      assert detailed_event["title"] == "Updated Event Title"
      assert detailed_event["description"] == "This is an updated description"
      assert detailed_event["tagline"] == "Amazing event!"
      assert detailed_event["status"] == "threshold"  # Status should remain threshold

      # Step 6: Enable ticketing (this will change status to confirmed)
      conn = post(conn, ~p"/events/#{event.slug}/enable-ticketing", %{})

      assert %{"success" => true, "event" => ticketing_event} = json_response(conn, 200)
      assert ticketing_event["status"] == "confirmed"

      # Step 7: Publish the event (should maintain confirmed status and set visibility)
      conn = post(conn, ~p"/events/#{event.slug}/publish", %{})

      assert %{"success" => true, "event" => published_event} = json_response(conn, 200)
      assert published_event["status"] == "confirmed"
      assert published_event["visibility"] == "public"
    end

    test "polling workflow: enable polling -> users vote -> finalize date", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      # Step 1: Enable polling
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)

      conn = post(conn, ~p"/events/#{event.slug}/enable-polling", %{
        "polling_deadline" => DateTime.to_iso8601(future_deadline)
      })

      assert %{"success" => true, "event" => polling_event} = json_response(conn, 200)
      assert polling_event["status"] == "polling"

      # Verify the existing polling system still works
      # (This would normally involve creating date options and votes, but we're testing the API integration)

            # Step 2: Later, pick the winning date from polling
      winning_date = DateTime.add(DateTime.utc_now(), 14, :day)

      conn = post(conn, ~p"/events/#{event.slug}/pick-date", %{
        "start_at" => DateTime.to_iso8601(winning_date),
        "timezone" => "UTC"
      })

      assert %{"success" => true, "event" => finalized_event} = json_response(conn, 200)
      assert finalized_event["start_at"] != nil
      assert finalized_event["timezone"] == "UTC"
      # Picking a date should end polling
      assert finalized_event["polling_deadline"] == nil
      assert finalized_event["status"] == "confirmed"

      # Step 3: Publish the finalized event
      conn = post(conn, ~p"/events/#{event.slug}/publish", %{})

      assert %{"success" => true, "event" => published_event} = json_response(conn, 200)
      assert published_event["status"] == "confirmed"
      assert published_event["visibility"] == "public"
    end

    test "error handling: unauthorized access", %{event: event} do
      conn = build_conn()

      endpoints = [
        {~p"/events/#{event.slug}/pick-date", %{"start_at" => DateTime.to_iso8601(DateTime.utc_now())}},
        {~p"/events/#{event.slug}/enable-polling", %{"polling_deadline" => DateTime.to_iso8601(DateTime.utc_now())}},
        {~p"/events/#{event.slug}/set-threshold", %{"threshold_count" => "10"}},
        {~p"/events/#{event.slug}/enable-ticketing", %{}},
        {~p"/events/#{event.slug}/add-details", %{"title" => "Test"}},
        {~p"/events/#{event.slug}/publish", %{}}
      ]

      for {path, params} <- endpoints do
        conn = post(conn, path, params)
        assert redirected_to(conn) == ~p"/auth/login"
      end
    end

    test "error handling: non-existent event", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      endpoints = [
        {~p"/events/nonexistent/pick-date", %{"start_at" => DateTime.to_iso8601(DateTime.utc_now())}},
        {~p"/events/nonexistent/enable-polling", %{"polling_deadline" => DateTime.to_iso8601(DateTime.utc_now())}},
        {~p"/events/nonexistent/set-threshold", %{"threshold_count" => "10"}},
        {~p"/events/nonexistent/enable-ticketing", %{}},
        {~p"/events/nonexistent/add-details", %{"title" => "Test"}},
        {~p"/events/nonexistent/publish", %{}}
      ]

      for {path, params} <- endpoints do
        conn = post(conn, path, params)
        assert %{"error" => "Event not found"} = json_response(conn, 404)
      end
    end

    test "validation errors: invalid parameters", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      # Test invalid date format
      conn = post(conn, ~p"/events/#{event.slug}/pick-date", %{
        "start_at" => "invalid-date"
      })
      assert %{"error" => error_msg} = json_response(conn, 400)
      assert String.contains?(error_msg, "Invalid datetime format")

      # Test missing required parameters
      conn = post(conn, ~p"/events/#{event.slug}/enable-polling", %{})
      assert %{"error" => "polling_deadline is required"} = json_response(conn, 400)

      # Test invalid threshold count
      conn = post(conn, ~p"/events/#{event.slug}/set-threshold", %{
        "threshold_count" => "0"
      })
      assert %{"error" => error_msg} = json_response(conn, 400)
      assert String.contains?(error_msg, "must be greater than 0")
    end

    test "state management: proper status transitions", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      # Start with confirmed status
      assert event.status == :confirmed

      # Enable polling -> status becomes polling
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)

      conn = post(conn, ~p"/events/#{event.slug}/enable-polling", %{
        "polling_deadline" => DateTime.to_iso8601(future_deadline)
      })

      assert %{"success" => true, "event" => polling_event} = json_response(conn, 200)
      assert polling_event["status"] == "polling"

            # Pick date -> this should end polling and set status to confirmed
      future_date = DateTime.add(DateTime.utc_now(), 30, :day)

      conn = post(conn, ~p"/events/#{event.slug}/pick-date", %{
        "start_at" => DateTime.to_iso8601(future_date)
      })

      assert %{"success" => true, "event" => dated_event} = json_response(conn, 200)
      # Picking a date should end polling and change status to confirmed
      assert dated_event["polling_deadline"] == nil
      assert dated_event["status"] == "confirmed"

      # Publish -> status becomes confirmed, visibility becomes public
      conn = post(conn, ~p"/events/#{event.slug}/publish", %{})

      assert %{"success" => true, "event" => published_event} = json_response(conn, 200)
      assert published_event["status"] == "confirmed"
      assert published_event["visibility"] == "public"
    end
  end
end
