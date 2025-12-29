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

    test "displays all sources in the table", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/monitoring")

      # Check that all 9 sources are listed
      assert html =~ "Cinema City"
      assert html =~ "Repertuary"
      assert html =~ "Karnet"
      assert html =~ "Week Pl"
      assert html =~ "Bandsintown"
      assert html =~ "Resident Advisor"
      assert html =~ "Sortiraparis"
      assert html =~ "Inquizition"
      assert html =~ "Waw4free"
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
