defmodule EventasaurusWeb.Admin.MonitoringDashboardLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "MonitoringDashboardLive" do
    test "renders monitoring dashboard page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/monitoring")

      # Check page title and structure
      assert html =~ "Scraper Monitoring"
      assert html =~ "Health Score"
      assert html =~ "SLO Compliance"
      assert html =~ "Sources Health"
      assert html =~ "Top Errors"
    end

    test "displays sources table structure", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/monitoring")

      # Verify the table structure exists (sources are loaded dynamically from job data)
      assert html =~ "Sources Health"
      # When no job execution data exists, the table should show empty state
      # The table headers should still be present
      assert html =~ "Source"
      assert html =~ "Health"
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

      {:ok, _view, html} = live(conn, ~p"/admin/monitoring")

      # The dynamically discovered source should appear
      assert html =~ "Cinema City"
    end

    test "time range filter updates data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/monitoring")

      # Change time range to 48 hours
      html =
        view
        |> element("select[name='time_range']")
        |> render_change(%{time_range: "48"})

      # Page should still render properly
      assert html =~ "Last 48 hours"
    end

    test "source filter updates data", %{conn: conn} do
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

      # Click refresh button
      html = render_click(view, "refresh")

      # Page should still render properly
      assert html =~ "Scraper Monitoring"
    end
  end
end
