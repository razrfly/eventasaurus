defmodule EventasaurusWeb.EventControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  import Ecto.Query
  import EventasaurusApp.{AccountsFixtures, EventsFixtures}

  alias EventasaurusApp.Events

  describe "show" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      %{user: user, event: event}
    end

    test "shows polling status and vote results for polling events", %{conn: conn, user: user, event: event} do
      # Update event to polling state by adding a polling deadline
      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)
      {:ok, polling_event} = Events.update_event(event, %{polling_deadline: future_deadline})

      # Create a date poll for the event
      {:ok, poll} = Events.create_event_date_poll(polling_event, user, %{})

      # Create some date options
      date1 = Date.add(Date.utc_today(), 7)
      date2 = Date.add(Date.utc_today(), 14)
      {:ok, [option1, option2]} = Events.create_date_options_from_list(poll, [date1, date2])

      # Create some votes
      voter1 = user_fixture()
      voter2 = user_fixture()
      {:ok, _vote1} = Events.create_event_date_vote(option1, voter1, :yes)
      {:ok, _vote2} = Events.create_event_date_vote(option2, voter2, :if_need_be)

      # Test the manager view
      conn = log_in_user(conn, user)
      response = get(conn, ~p"/events/#{polling_event.slug}")

      assert response.status == 200
      assert response.resp_body =~ "Date Polling Active"
      assert response.resp_body =~ "Date Poll Results"
      assert response.resp_body =~ "🟢 100%" # option1 has 1 yes vote (100%)
      assert response.resp_body =~ "🟡 100%" # option2 has 1 if_need_be vote (100%)
      assert response.resp_body =~ "Preferred"
      assert response.resp_body =~ "Acceptable"
    end

    test "shows confirmed date for non-polling events", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)
      response = get(conn, ~p"/events/#{event.slug}")

      assert response.status == 200
      refute response.resp_body =~ "Date Polling Active"
      refute response.resp_body =~ "Date Poll Results"
      # Should show the actual date/time
      assert response.resp_body =~ Calendar.strftime(event.start_at, "%A, %B %d, %Y")
    end
  end

  describe "cancel" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      %{user: user, event: event}
    end

    test "successfully cancels an event for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/cancel")

      assert redirected_to(conn) == ~p"/#{event.slug}"
      assert get_flash(conn, :info) == "Event canceled successfully"

      # Verify event is actually canceled - reload from database
      updated_event = Events.get_event!(event.id)
      assert updated_event.status == :canceled
      assert updated_event.canceled_at != nil
    end

    test "denies access for unauthorized user", %{conn: conn, event: event} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      conn = post(conn, ~p"/events/#{event.slug}/cancel")

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :error) == "You don't have permission to cancel this event"

      # Verify event is not canceled
      unchanged_event = Events.get_event(event.id)
      assert unchanged_event.status != :canceled
    end

    test "redirects unauthenticated user to login", %{conn: conn, event: event} do
      conn = post(conn, ~p"/events/#{event.slug}/cancel")

      assert redirected_to(conn) == ~p"/auth/login"
      assert get_flash(conn, :error) == "You must log in to access this page."
    end

    test "handles non-existent event", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/nonexistent/cancel")

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :error) == "Event not found"
    end
  end

  describe "auto_correct_status" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      %{user: user, event: event}
    end

    test "corrects inconsistent event status", %{conn: conn, user: user, event: event} do
      # Force wrong status in database
      EventasaurusApp.Repo.update_all(
        from(e in EventasaurusApp.Events.Event, where: e.id == ^event.id),
        set: [status: :polling]
      )

      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/auto-correct-status")

      assert redirected_to(conn) == ~p"/#{event.slug}"
      assert get_flash(conn, :info) =~ "Event status corrected from polling to"

      # Verify status was corrected
      corrected_event = Events.get_event(event.id)
      assert corrected_event.status != :polling
    end

    test "reports when status is already correct", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/auto-correct-status")

      assert redirected_to(conn) == ~p"/#{event.slug}"
      assert get_flash(conn, :info) == "Event status is already correct"
    end

    test "denies access for unauthorized user", %{conn: conn, event: event} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      conn = post(conn, ~p"/events/#{event.slug}/auto-correct-status")

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :error) == "You don't have permission to modify this event"
    end

    test "redirects unauthenticated user to login", %{conn: conn, event: event} do
      conn = post(conn, ~p"/events/#{event.slug}/auto-correct-status")

      assert redirected_to(conn) == ~p"/auth/login"
      assert get_flash(conn, :error) == "You must log in to access this page."
    end
  end

  describe "delete" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      %{user: user, event: event}
    end

    test "successfully deletes event for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = delete(conn, ~p"/events/#{event.slug}")

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :info) == "Event deleted successfully"

      # Verify event is actually deleted
      assert Events.get_event(event.id) == nil
    end

    test "denies access for unauthorized user", %{conn: conn, event: event} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      conn = delete(conn, ~p"/events/#{event.slug}")

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_flash(conn, :error) == "You don't have permission to delete this event"

      # Verify event still exists
      assert Events.get_event(event.id) != nil
    end
  end

  describe "Action-Driven Setup API" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      %{user: user, event: event}
    end

    test "pick_date successfully updates event date for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      future_date = DateTime.add(DateTime.utc_now(), 30, :day)

      conn = post(conn, ~p"/events/#{event.slug}/pick-date", %{
        "start_at" => DateTime.to_iso8601(future_date),
        "timezone" => "America/New_York"
      })

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["start_at"] != nil
      assert updated_event["timezone"] == "America/New_York"
    end

    test "pick_date returns error for invalid datetime format", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/pick-date", %{
        "start_at" => "invalid-date"
      })

      assert %{"error" => "Invalid datetime format. Use ISO8601 format."} = json_response(conn, 400)
    end

    test "pick_date returns error for unauthorized user", %{conn: conn, event: event} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      future_date = DateTime.add(DateTime.utc_now(), 30, :day)

      conn = post(conn, ~p"/events/#{event.slug}/pick-date", %{
        "start_at" => DateTime.to_iso8601(future_date)
      })

      assert %{"error" => "You don't have permission to modify this event"} = json_response(conn, 403)
    end

    test "enable_polling successfully enables polling for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      future_deadline = DateTime.add(DateTime.utc_now(), 7, :day)

      conn = post(conn, ~p"/events/#{event.slug}/enable-polling", %{
        "polling_deadline" => DateTime.to_iso8601(future_deadline)
      })

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["status"] == "polling"
      assert updated_event["polling_deadline"] != nil
    end

    test "enable_polling returns error when polling_deadline is missing", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/enable-polling", %{})

      assert %{"error" => "polling_deadline is required"} = json_response(conn, 400)
    end

    test "enable_polling returns error for invalid datetime format", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/enable-polling", %{
        "polling_deadline" => "invalid-date"
      })

      assert %{"error" => "Invalid datetime format. Use ISO8601 format."} = json_response(conn, 400)
    end

    test "set_threshold successfully sets threshold for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/set-threshold", %{
        "threshold_count" => "10"
      })

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["status"] == "threshold"
      assert updated_event["threshold_count"] == 10
    end

    test "set_threshold returns error when threshold_count is missing", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/set-threshold", %{})

      assert %{"error" => "threshold_count is required"} = json_response(conn, 400)
    end

    test "set_threshold returns error for invalid threshold_count", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/set-threshold", %{
        "threshold_count" => "invalid"
      })

      assert %{"error" => "threshold_count must be a positive integer"} = json_response(conn, 400)
    end

    test "set_threshold returns error for zero threshold_count", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/set-threshold", %{
        "threshold_count" => "0"
      })

      assert %{"error" => "threshold_count must be greater than 0"} = json_response(conn, 400)
    end

    test "enable_ticketing successfully enables ticketing for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/enable-ticketing", %{})

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["status"] == "confirmed"
    end

    test "enable_ticketing accepts ticketing options", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/enable-ticketing", %{
        "ticketing_options" => %{
          "price" => "25.00",
          "currency" => "USD"
        }
      })

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["status"] == "confirmed"
    end

    test "add_details successfully updates event details for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/add-details", %{
        "title" => "Updated Event Title",
        "description" => "Updated description",
        "tagline" => "New tagline",
        "theme" => "cosmic"
      })

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["title"] == "Updated Event Title"
      assert updated_event["description"] == "Updated description"
      assert updated_event["tagline"] == "New tagline"
      assert updated_event["theme"] == "cosmic"
    end

    test "add_details ignores non-allowed fields", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/add-details", %{
        "title" => "Updated Title",
        "status" => "canceled",  # This should be ignored
        "id" => 999  # This should be ignored
      })

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["title"] == "Updated Title"
      # Status should not be changed to canceled
      assert updated_event["status"] != "canceled"
    end

    test "publish successfully publishes event for authorized user", %{conn: conn, user: user, event: event} do
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/events/#{event.slug}/publish", %{})

      assert %{"success" => true, "event" => updated_event} = json_response(conn, 200)
      assert updated_event["status"] == "confirmed"
      assert updated_event["visibility"] == "public"
    end

    test "publish returns error for unauthorized user", %{conn: conn, event: event} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      conn = post(conn, ~p"/events/#{event.slug}/publish", %{})

      assert %{"error" => "You don't have permission to modify this event"} = json_response(conn, 403)
    end

    test "all endpoints require authentication", %{event: event} do
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

    test "all endpoints return 404 for non-existent events", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      endpoints = [
        {~p"/events/non-existent/pick-date", %{"start_at" => DateTime.to_iso8601(DateTime.utc_now())}},
        {~p"/events/non-existent/enable-polling", %{"polling_deadline" => DateTime.to_iso8601(DateTime.utc_now())}},
        {~p"/events/non-existent/set-threshold", %{"threshold_count" => "10"}},
        {~p"/events/non-existent/enable-ticketing", %{}},
        {~p"/events/non-existent/add-details", %{"title" => "Test"}},
        {~p"/events/non-existent/publish", %{}}
      ]

      for {path, params} <- endpoints do
        conn = post(conn, path, params)
        assert %{"error" => "Event not found"} = json_response(conn, 404)
      end
    end
  end
end
