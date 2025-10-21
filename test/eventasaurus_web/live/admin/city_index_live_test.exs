defmodule EventasaurusWeb.Admin.CityIndexLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  describe "Index" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")
      us = insert(:country, name: "United States", code: "US")

      sydney = insert(:city, name: "Sydney", country: au, discovery_enabled: true,
        latitude: Decimal.new("-33.8688"), longitude: Decimal.new("151.2093"))
      melbourne = insert(:city, name: "Melbourne", country: au, discovery_enabled: false)
      new_york = insert(:city, name: "New York", country: us, discovery_enabled: true)

      # Add venues to Sydney
      insert(:venue, city_id: sydney.id, name: "Opera House")
      insert(:venue, city_id: sydney.id, name: "Harbour Bridge")

      {:ok, australia: au, us: us, sydney: sydney, melbourne: melbourne, new_york: new_york}
    end

    test "displays all cities with venue counts", %{conn: conn, sydney: sydney, melbourne: melbourne, new_york: new_york} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      assert html =~ "Cities"
      assert html =~ "Sydney"
      assert html =~ "Melbourne"
      assert html =~ "New York"

      # Check venue count for Sydney
      assert html =~ "2"  # Sydney has 2 venues

      # Check coordinates display
      assert html =~ "-33.8688"
      assert html =~ "151.2093"
    end

    test "displays empty state when no cities", %{conn: conn} do
      # Delete all venues first, then cities
      Repo.delete_all(EventasaurusApp.Venues.Venue)
      Repo.delete_all(City)

      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      assert html =~ "No cities"
      assert html =~ "Get started by creating a new city"
    end

    test "search filters cities", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      html =
        index_live
        |> form("form[phx-change='search']", %{search: "sydney"})
        |> render_change()

      assert html =~ "Sydney"
      refute html =~ "Melbourne"
      refute html =~ "New York"
    end

    test "search is case-insensitive", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      html =
        index_live
        |> form("form[phx-change='search']", %{search: "SYDNEY"})
        |> render_change()

      assert html =~ "Sydney"
    end

    test "country filter works", %{conn: conn, australia: au} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      html =
        index_live
        |> form("form[phx-change='filter_country']", %{country_id: au.id})
        |> render_change()

      assert html =~ "Sydney"
      assert html =~ "Melbourne"
      refute html =~ "New York"
    end

    test "discovery filter works for enabled cities", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      html =
        index_live
        |> form("form[phx-change='filter_discovery']", %{discovery_enabled: "true"})
        |> render_change()

      assert html =~ "Sydney"
      assert html =~ "New York"
      refute html =~ "Melbourne"
    end

    test "discovery filter works for disabled cities", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      html =
        index_live
        |> form("form[phx-change='filter_discovery']", %{discovery_enabled: "false"})
        |> render_change()

      assert html =~ "Melbourne"
      refute html =~ "Sydney"
      refute html =~ "New York"
    end

    test "multiple filters work together", %{conn: conn, australia: au} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      # Search for "ney" (should match Sydney) + Australia + Discovery enabled
      html =
        index_live
        |> form("form[phx-change='search']", %{search: "ney"})
        |> render_change()

      html =
        index_live
        |> form("form[phx-change='filter_country']", %{country_id: au.id})
        |> render_change()

      html =
        index_live
        |> form("form[phx-change='filter_discovery']", %{discovery_enabled: "true"})
        |> render_change()

      assert html =~ "Sydney"
      refute html =~ "Melbourne"  # Disabled
      refute html =~ "New York"   # Different country
    end

    test "displays discovery status badges", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      assert html =~ "Enabled"
      assert html =~ "Disabled"
    end

    test "displays action links", %{conn: conn, sydney: sydney} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      assert html =~ "Edit"
      assert html =~ "Configure"
      assert html =~ "Delete"
      assert html =~ ~p"/admin/cities/#{sydney.id}/edit"
      assert html =~ ~p"/admin/discovery/config/#{sydney.slug}"
    end

    test "delete button shows for city without venues", %{conn: conn, melbourne: melbourne} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      # Melbourne has no venues, so delete should be available
      assert html =~ "Delete"
    end

    test "deletes city successfully", %{conn: conn, melbourne: melbourne} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      # Delete Melbourne (has no venues)
      html =
        index_live
        |> element("button[phx-value-id='#{melbourne.id}']")
        |> render_click()

      # Check flash message
      assert html =~ "deleted successfully"

      # Verify city is deleted
      assert Repo.get(City, melbourne.id) == nil
    end

    test "shows error when deleting city with venues", %{conn: conn, sydney: sydney} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      # Try to delete Sydney (has venues)
      html =
        index_live
        |> element("button[phx-value-id='#{sydney.id}']")
        |> render_click()

      assert html =~ "Cannot delete city with venues"

      # Verify city still exists
      assert Repo.get(City, sydney.id) != nil
    end

    test "displays coordinates when present", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      # Sydney has coordinates
      assert html =~ "-33.8688"
      assert html =~ "151.2093"
    end

    test "displays 'No coordinates' when absent", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      # Melbourne has no coordinates
      assert html =~ "No coordinates"
    end

    test "displays Create City button", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      assert html =~ "Create City"
      assert html =~ ~p"/admin/cities/new"
    end

    test "displays country names", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities")

      assert html =~ "Australia"
      assert html =~ "United States"
    end

    test "URL params persist filters", %{conn: conn, australia: au} do
      # Navigate with URL params
      {:ok, _index_live, html} = live(conn, ~p"/admin/cities?search=sydney&country_id=#{au.id}&discovery_enabled=true")

      assert html =~ "Sydney"
      refute html =~ "Melbourne"
      refute html =~ "New York"
    end

    test "clearing search filter shows all cities", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/cities")

      # Apply search
      html =
        index_live
        |> form("form[phx-change='search']", %{search: "sydney"})
        |> render_change()

      assert html =~ "Sydney"
      refute html =~ "Melbourne"

      # Clear search
      html =
        index_live
        |> form("form[phx-change='search']", %{search: ""})
        |> render_change()

      assert html =~ "Sydney"
      assert html =~ "Melbourne"
      assert html =~ "New York"
    end

  end
end
