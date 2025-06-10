defmodule EventasaurusWeb.EventControllerTest do
  use EventasaurusWeb.ConnCase, async: true

  import EventasaurusApp.{AccountsFixtures, EventsFixtures}

  alias EventasaurusApp.Events

  describe "show" do
    setup do
      user = user_fixture()
      event = event_fixture(organizers: [user])
      %{user: user, event: event}
    end

    test "shows polling status and vote results for polling events", %{conn: conn, user: user, event: event} do
      # Update event to polling state
      {:ok, polling_event} = Events.update_event(event, %{state: "polling"})

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
end
