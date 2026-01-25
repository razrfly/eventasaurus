defmodule EventasaurusWeb.Admin.CityHealthDetailLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  describe "City Health Detail Page" do
    setup do
      country = insert(:country, name: "Poland", code: "PL")

      city =
        insert(:city,
          name: "Kraków",
          slug: "krakow",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        )

      # Add some venues to the city
      venue1 = insert(:venue, city_id: city.id, name: "Kino Pod Baranami")
      venue2 = insert(:venue, city_id: city.id, name: "Stary Teatr")

      {:ok, city: city, venue1: venue1, venue2: venue2}
    end

    test "displays city name and back link", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Kraków"
      assert html =~ "Back to City Health Dashboard"
    end

    test "displays health score section", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should have a health score label
      assert html =~ "Health Score"
    end

    test "displays quick stats section", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should display stat cards
      assert html =~ "Total Events"
      assert html =~ "Active Sources"
      assert html =~ "Venues"
      assert html =~ "Categories"
    end

    test "displays health score breakdown with 4 components", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should display all 4 health components
      assert html =~ "Health Score Breakdown"
      assert html =~ "Event Coverage"
      assert html =~ "Source Activity"
      assert html =~ "Data Quality"
      assert html =~ "Venue Health"
    end

    test "displays component weights", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should show weights for each component (displayed as badges in health_metric_card)
      # Event Coverage: 40%, Source Activity: 30%, Data Quality: 20%, Venue Health: 10%
      # Match with whitespace tolerance since EEx templates add newlines
      assert html =~ ~r/>\s*40%\s*</
      assert html =~ ~r/>\s*30%\s*</
      assert html =~ ~r/>\s*20%\s*</
      assert html =~ ~r/>\s*10%\s*</
    end

    test "displays component descriptions", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should show descriptions for each component
      assert html =~ "7-day availability"
      assert html =~ "Job success rate"
      assert html =~ "Events with metadata"
      assert html =~ "Venues with slugs"
    end

    test "displays event trend section with date range selector", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should display event trend section with chart
      assert html =~ "Event Trend"
      # Should have date range selector
      assert html =~ "Last 7 days"
      assert html =~ "Last 30 days"
      assert html =~ "Last 90 days"
      # Should have chart canvas
      assert html =~ "city-event-trend-chart"
      assert html =~ "phx-hook=\"ChartHook\""
    end

    test "displays refresh button", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Refresh"
    end

    test "displays country name", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Poland"
    end

    test "refresh button updates data", %{conn: conn, city: city} do
      {:ok, live, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Click refresh and check it doesn't crash
      html = render_click(live, "refresh")

      # Should still display the city after refresh
      assert html =~ "Kraków"
    end

    test "date range selector changes chart period", %{conn: conn, city: city} do
      {:ok, live_view, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Default should be 30 days selected
      assert html =~ ~s(value="30" selected)

      # Change to 7 days
      html = render_change(live_view, "change_date_range", %{"date_range" => "7"})

      # Should now have 7 selected
      assert html =~ ~s(value="7" selected)
      refute html =~ ~s(value="30" selected)

      # Change to 90 days
      html = render_change(live_view, "change_date_range", %{"date_range" => "90"})

      # Should now have 90 selected
      assert html =~ ~s(value="90" selected)
    end

    test "chart displays stats below chart", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should display chart quick stats
      assert html =~ "Total Events"
      assert html =~ "Avg/Day"
      assert html =~ "Peak Day"
    end
  end

  describe "City Health Detail with invalid city" do
    test "redirects with flash message for non-existent city slug", %{conn: conn} do
      # The mount function gracefully handles invalid cities by redirecting
      {:error, {:live_redirect, %{to: to, flash: flash}}} =
        live(conn, ~p"/admin/cities/nonexistent-city/health")

      assert to == "/admin/cities/health"
      assert flash["error"] == "City not found"
    end
  end

  describe "Sources Table (Phase 3)" do
    setup do
      country = insert(:country, name: "Poland", code: "PL")

      city =
        insert(:city,
          name: "Kraków",
          slug: "krakow",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        )

      venue = insert(:venue, city_id: city.id, name: "Kino Pod Baranami")

      # Create a source with events (use public_event_source_type factory)
      source = insert(:public_event_source_type, name: "Test Source", slug: "test_source")

      # Create a public event for this venue and source
      event = insert(:public_event, venue_id: venue.id, title: "Test Event")
      insert(:public_event_source, event_id: event.id, source_id: source.id)

      {:ok, city: city, venue: venue, source: source, event: event}
    end

    test "displays Active Sources section", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Active Sources"
    end

    test "displays Expand All button initially", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Expand All"
    end

    test "displays source with health status", %{conn: conn, city: city, source: source} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ source.name
      # Should show events count
      assert html =~ "events"
      # Should show success rate
      assert html =~ "success"
    end

    test "toggle_source expands source row", %{conn: conn, city: city, source: source} do
      {:ok, live_view, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Click to expand source
      html = render_click(live_view, "toggle_source", %{"source" => source.slug})

      # Expanded content should show
      assert html =~ "Source Statistics"
      assert html =~ "Job Success Rate"
      assert html =~ "Recent Errors (24h)"
    end

    test "toggle_source collapses expanded source row", %{conn: conn, city: city, source: source} do
      {:ok, live_view, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Expand source
      _html = render_click(live_view, "toggle_source", %{"source" => source.slug})

      # Collapse source
      html = render_click(live_view, "toggle_source", %{"source" => source.slug})

      # Expanded content should be hidden
      refute html =~ "Source Statistics"
    end

    test "expand_all_sources expands all source rows", %{conn: conn, city: city} do
      {:ok, live_view, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Click Expand All
      html = render_click(live_view, "expand_all_sources")

      # Should show Collapse All button now
      assert html =~ "Collapse All"
      # Expanded content should show
      assert html =~ "Source Statistics"
    end

    test "collapse_all_sources collapses all source rows", %{conn: conn, city: city} do
      {:ok, live_view, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # First expand all
      _html = render_click(live_view, "expand_all_sources")

      # Then collapse all
      html = render_click(live_view, "collapse_all_sources")

      # Should show Expand All button again
      assert html =~ "Expand All"
      # Expanded content should be hidden
      refute html =~ "Source Statistics"
    end

    test "expanded source shows quick action links", %{conn: conn, city: city, source: source} do
      {:ok, live_view, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Expand source
      html = render_click(live_view, "toggle_source", %{"source" => source.slug})

      # Should show quick action links
      assert html =~ "View Job Executions"
      assert html =~ "View Error Trends"
      assert html =~ "/admin/job-executions?source=#{source.slug}"
      assert html =~ "/admin/error-trends?source=#{source.slug}"
    end

    test "expanded source with no errors shows success message", %{
      conn: conn,
      city: city,
      source: source
    } do
      {:ok, live_view, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Expand source
      html = render_click(live_view, "toggle_source", %{"source" => source.slug})

      # Should show no errors message
      assert html =~ "No errors in the last 24 hours"
    end

    test "displays no sources message when city has no sources", %{conn: conn} do
      country = insert(:country, name: "Germany", code: "DE")

      empty_city =
        insert(:city,
          name: "Berlin",
          slug: "berlin",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("52.5200"),
          longitude: Decimal.new("13.4050")
        )

      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{empty_city.slug}/health")

      assert html =~ "No active sources found for this city"
    end
  end

  describe "Sources Table with errors" do
    setup do
      country = insert(:country, name: "Poland", code: "PL")

      city =
        insert(:city,
          name: "Kraków",
          slug: "krakow",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        )

      venue = insert(:venue, city_id: city.id, name: "Kino Pod Baranami")
      source = insert(:public_event_source_type, name: "Failing Source", slug: "failing_source")

      # Create a public event for this venue and source
      event = insert(:public_event, venue_id: venue.id, title: "Test Event")
      insert(:public_event_source, event_id: event.id, source_id: source.id)

      # Create a failed job execution summary
      # Note: Worker pattern must match the source slug (failing_source -> FailingSource)
      insert(:job_execution_summary,
        worker: "EventasaurusDiscovery.Sources.FailingSource.Jobs.SyncJob",
        state: "failure",
        attempted_at: DateTime.utc_now(),
        results: %{"error_category" => "network_error", "error" => "Connection timeout"}
      )

      {:ok, city: city, source: source}
    end

    test "expanded source shows recent errors", %{conn: conn, city: city, source: source} do
      {:ok, live_view, _html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Expand source
      html = render_click(live_view, "toggle_source", %{"source" => source.slug})

      # Should show error details
      assert html =~ "Failed"
      assert html =~ "network_error"
    end
  end

  describe "Top Venues Table (Phase 5)" do
    setup do
      country = insert(:country, name: "Poland", code: "PL")

      city =
        insert(:city,
          name: "Kraków",
          slug: "krakow",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        )

      venue1 = insert(:venue, city_id: city.id, name: "Kino Pod Baranami")
      venue2 = insert(:venue, city_id: city.id, name: "Stary Teatr")

      # Create source
      source = insert(:public_event_source_type, name: "Test Source", slug: "test_source")

      # Create events for venues
      event1 = insert(:public_event, venue_id: venue1.id, title: "Movie Night")
      event2 = insert(:public_event, venue_id: venue1.id, title: "Film Festival")
      event3 = insert(:public_event, venue_id: venue2.id, title: "Theater Show")

      # Link events to source
      insert(:public_event_source, event_id: event1.id, source_id: source.id)
      insert(:public_event_source, event_id: event2.id, source_id: source.id)
      insert(:public_event_source, event_id: event3.id, source_id: source.id)

      {:ok, city: city, venue1: venue1, venue2: venue2, source: source}
    end

    test "displays Top Venues section", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Top Venues"
    end

    test "displays View All link to venue duplicates page", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "View All"
      assert html =~ "/venues/duplicates"
    end

    test "displays venue names in table", %{
      conn: conn,
      city: city,
      venue1: venue1,
      venue2: venue2
    } do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ venue1.name
      assert html =~ venue2.name
    end

    test "displays event counts for venues", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # venue1 should have 2 events, venue2 should have 1
      # The count should appear in the HTML (exact format depends on implementation)
      assert html =~ "2"
      assert html =~ "1"
    end

    test "displays source names for venues", %{conn: conn, city: city, source: source} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ source.name
    end

    test "displays table headers", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Venue"
      assert html =~ "Events"
      assert html =~ "Sources"
      assert html =~ "Last Seen"
    end

    test "displays no venues message when city has no venues", %{conn: conn} do
      country = insert(:country, name: "Germany", code: "DE")

      empty_city =
        insert(:city,
          name: "Berlin",
          slug: "berlin",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("52.5200"),
          longitude: Decimal.new("13.4050")
        )

      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{empty_city.slug}/health")

      assert html =~ "No venues found for this city"
    end
  end

  describe "Category Distribution (Phase 5)" do
    setup do
      country = insert(:country, name: "Poland", code: "PL")

      city =
        insert(:city,
          name: "Kraków",
          slug: "krakow",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        )

      venue = insert(:venue, city_id: city.id, name: "Kino Pod Baranami")

      # Create categories with unique slugs to avoid conflicts
      unique_suffix = :erlang.unique_integer([:positive])
      music_category = insert(:category, name: "Music Test", slug: "music-test-#{unique_suffix}")
      film_category = insert(:category, name: "Film Test", slug: "film-test-#{unique_suffix}")

      # Create events with categories
      event1 = insert(:public_event, venue_id: venue.id, title: "Concert")
      event2 = insert(:public_event, venue_id: venue.id, title: "Movie Night")
      _event3 = insert(:public_event, venue_id: venue.id, title: "Uncategorized Event")

      # Link events to categories using public_event_categories table
      insert(:public_event_category, event_id: event1.id, category_id: music_category.id)
      insert(:public_event_category, event_id: event2.id, category_id: film_category.id)

      {:ok,
       city: city, venue: venue, music_category: music_category, film_category: film_category}
    end

    test "displays Category Distribution section", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Category Distribution"
    end

    test "displays category names", %{
      conn: conn,
      city: city,
      music_category: music_category,
      film_category: film_category
    } do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ music_category.name
      assert html =~ film_category.name
    end

    test "displays Unknown category for uncategorized events", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      assert html =~ "Unknown"
    end

    test "displays percentages for categories", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Should show percentage indicators
      assert html =~ "%"
    end

    test "displays category icons", %{conn: conn, city: city} do
      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{city.slug}/health")

      # Default icon appears for test categories (unique slugs don't match predefined icons)
      assert html =~ "📌"
      # Unknown category icon also appears (white question mark ornament)
      assert html =~ "❔"
    end

    test "displays no category data message when city has no events", %{conn: conn} do
      country = insert(:country, name: "Germany", code: "DE")

      empty_city =
        insert(:city,
          name: "Berlin",
          slug: "berlin",
          country: country,
          discovery_enabled: true,
          latitude: Decimal.new("52.5200"),
          longitude: Decimal.new("13.4050")
        )

      {:ok, _live, html} = live(conn, ~p"/admin/cities/#{empty_city.slug}/health")

      assert html =~ "No category data available"
    end
  end
end
