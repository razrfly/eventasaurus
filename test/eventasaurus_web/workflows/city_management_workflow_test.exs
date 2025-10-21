defmodule EventasaurusWeb.Workflows.CityManagementWorkflowTest do
  @moduledoc """
  End-to-end workflow test for city management.

  This test verifies the complete user journey from issue #1899:
  1. Admin navigates to cities index
  2. Clicks "Create City"
  3. Fills in city name and country
  4. Clicks "Get Coordinates" to geocode
  5. Enables discovery
  6. Saves the city
  7. Verifies city appears in index
  8. Edits the city
  9. Deletes the city
  """
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  describe "Complete City Management Workflow" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")
      {:ok, australia: au}
    end

    test "admin can create, view, edit, and delete cities", %{conn: conn, australia: au} do
      # Step 1: Navigate to cities index
      {:ok, index_view, html} = live(conn, ~p"/admin/cities")
      assert html =~ "Cities"
      assert html =~ "Create City"

      # Step 2: Navigate to create form
      {:ok, form_view, html} = live(conn, ~p"/admin/cities/new")

      assert html =~ "New City"
      assert html =~ "Get Coordinates"

      # Step 3: Fill in city details
      city_params = %{
        "name" => "Melbourne",
        "country_id" => to_string(au.id),
        "latitude" => "-37.8136",
        "longitude" => "144.9631"
      }

      form_view
      |> form("form", %{"city" => city_params})
      |> render_change()

      # Step 4: Enable discovery
      form_view
      |> element("input[name='enable_discovery']")
      |> render_click(%{"value" => "true"})

      # Step 5: Submit the form
      {:ok, index_view, html} =
        form_view
        |> form("form", %{"city" => city_params})
        |> render_submit()
        |> follow_redirect(conn)

      # Step 6: Verify city appears in index
      assert html =~ "City created successfully"
      assert html =~ "Melbourne"
      assert html =~ "Australia"
      assert html =~ "-37.8136"
      assert html =~ "Enabled"  # Discovery enabled badge

      # Step 7: Verify city was created in database
      melbourne = Repo.get_by(City, name: "Melbourne")
      assert melbourne != nil
      assert melbourne.discovery_enabled == true

      # Step 8: Edit the city
      {:ok, edit_view, html} =
        index_view
        |> element("a[href='/admin/cities/#{melbourne.id}/edit']")
        |> render_click()
        |> follow_redirect(conn)

      assert html =~ "Edit City"
      assert html =~ "Melbourne"

      # Update city name
      {:ok, index_view, html} =
        edit_view
        |> form("form", %{"city" => %{"name" => "Greater Melbourne"}})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "City updated successfully"
      assert html =~ "Greater Melbourne"

      # Step 9: Delete the city
      html =
        index_view
        |> element("button[phx-value-id='#{melbourne.id}']")
        |> render_click()

      assert html =~ "deleted successfully"

      # Verify city is deleted from database
      assert Repo.get(City, melbourne.id) == nil
    end

    test "complete workflow with geocoding (mocked)", %{conn: conn, australia: au} do
      # Navigate to create form
      {:ok, form_view, _html} = live(conn, ~p"/admin/cities/new")

      # Fill in basic details
      form_view
      |> form("form", %{
        "city" => %{
          "name" => "Sydney",
          "country_id" => to_string(au.id)
        }
      })
      |> render_change()

      # Note: Actual geocoding would require mocking AddressGeocoder
      # For now, we verify the UI elements exist
      html = render(form_view)
      assert html =~ "Get Coordinates"
      assert html =~ "This will geocode"

      # Manually enter coordinates (simulating successful geocoding)
      city_params = %{
        "name" => "Sydney",
        "country_id" => to_string(au.id),
        "latitude" => "-33.8688",
        "longitude" => "151.2093"
      }

      # Submit form
      {:ok, _index_view, html} =
        form_view
        |> form("form", %{"city" => city_params})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "City created successfully"
      assert html =~ "Sydney"

      # Verify coordinates were saved
      sydney = Repo.get_by(City, name: "Sydney")
      assert Decimal.eq?(sydney.latitude, Decimal.new("-33.8688"))
      assert Decimal.eq?(sydney.longitude, Decimal.new("151.2093"))
    end

    test "workflow prevents deleting city with venues", %{conn: conn, australia: au} do
      # Create city with venues
      sydney = insert(:city, name: "Sydney", country: au)
      insert(:venue, city_id: sydney.id, name: "Opera House")

      # Navigate to cities index
      {:ok, index_view, _html} = live(conn, ~p"/admin/cities")

      # Try to delete city with venues
      html =
        index_view
        |> element("button[phx-value-id='#{sydney.id}']")
        |> render_click()

      assert html =~ "Cannot delete city with venues"

      # Verify city still exists
      assert Repo.get(City, sydney.id) != nil
    end

    test "workflow shows validation errors during creation", %{conn: conn} do
      # Navigate to create form
      {:ok, form_view, _html} = live(conn, ~p"/admin/cities/new")

      # Submit without required fields
      html =
        form_view
        |> form("form", %{"city" => %{"name" => ""}})
        |> render_submit()

      # Should show validation errors
      assert html =~ "can&#39;t be blank"
    end
  end

  describe "Integration with Discovery System" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")
      {:ok, australia: au}
    end

    test "creates city with discovery enabled", %{conn: conn, australia: au} do
      {:ok, form_view, _html} = live(conn, ~p"/admin/cities/new")

      # Toggle discovery checkbox
      form_view
      |> element("input[name='enable_discovery']")
      |> render_click(%{"value" => "true"})

      # Create city
      city_params = %{
        "name" => "Brisbane",
        "country_id" => to_string(au.id),
        "latitude" => "-27.4698",
        "longitude" => "153.0251"
      }

      form_view
      |> form("form", %{"city" => city_params})
      |> render_submit()

      # Verify discovery was enabled
      brisbane = Repo.get_by(City, name: "Brisbane")
      assert brisbane.discovery_enabled == true
      assert brisbane.discovery_config != nil
      assert brisbane.discovery_config["schedule"] != nil
    end
  end
end
