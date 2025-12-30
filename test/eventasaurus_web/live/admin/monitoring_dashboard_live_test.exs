defmodule EventasaurusWeb.Admin.MonitoringDashboardLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest

  # Helper to wait for async data loading to complete
  # The mount sends :load_initial_data message, so we need to wait for it to be processed
  defp wait_for_loading(view) do
    # Send a ping and wait for response to ensure message queue is processed
    # This works because messages are processed in order
    send(view.pid, {:test_ping, self()})

    case receive do
           :test_pong -> :ok
         after
           5_000 -> :timeout
         end do
      :ok -> render(view)
      :timeout -> raise "Timeout waiting for async data loading to complete"
    end
  end

  describe "MonitoringDashboardLive" do
    test "renders monitoring dashboard page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/monitoring")

      # Wait for async loading to complete
      html = wait_for_loading(view)

      # Check page title and structure
      assert html =~ "Scraper Monitoring"
      assert html =~ "Health Score"
      assert html =~ "SLO Compliance"
      assert html =~ "Sources Health"
      assert html =~ "Top Errors"
    end

    test "displays sources table structure", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/monitoring")

      # Wait for async loading to complete
      html = wait_for_loading(view)

      # Verify the table structure exists (sources are loaded dynamically from job data)
      assert html =~ "Sources Health"
      # The table headers should still be present
      assert html =~ "Source"
    end

    test "displays sources dynamically from job execution data", %{conn: conn} do
      # Insert a job execution summary to test dynamic source discovery
      {:ok, _summary} =
        EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary.record_execution(%{
          job_id: 1,
          worker: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob",
          queue: "discovery",
          state: "completed",
          args: %{},
          results: %{},
          attempted_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now(),
          duration_ms: 1000
        })

      {:ok, view, _html} = live(conn, ~p"/admin/monitoring")

      # Wait for async loading to complete
      html = wait_for_loading(view)

      # The dynamically discovered source should appear
      assert html =~ "Cinema City"
    end

    test "time range filter updates data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/monitoring")

      # Wait for initial loading
      _ = wait_for_loading(view)

      # Change time range to 48 hours (phx-change is on the form, not the select)
      html =
        view
        |> element("form")
        |> render_change(%{time_range: "48"})

      # Page should still render properly with the selected option
      assert html =~ "value=\"48\""
    end

    @tag :skip
    test "source filter updates data", %{conn: conn} do
      # This test is skipped because the source filter was removed from the UI
      {:ok, view, _html} = live(conn, ~p"/admin/monitoring")

      # Filter to a specific source
      html =
        view
        |> element("select[name='source']")
        |> render_change(%{source: "cinema_city"})

      # Should still show the dashboard
      assert html =~ "Scraper Monitoring"
    end

    test "refresh button works", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/monitoring")

      # Wait for initial loading
      _ = wait_for_loading(view)

      # Click refresh button
      html = render_click(view, "refresh")

      # Page should still render properly
      assert html =~ "Scraper Monitoring"
    end
  end
end
