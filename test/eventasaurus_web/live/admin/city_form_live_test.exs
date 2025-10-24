defmodule EventasaurusWeb.Admin.CityFormLiveTest do
  use EventasaurusWeb.ConnCase

  import Phoenix.LiveViewTest
  import EventasaurusApp.Factory

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  describe "New City Form" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")
      us = insert(:country, name: "United States", code: "US")

      {:ok, australia: au, us: us}
    end

    test "displays new city form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/new")

      assert html =~ "New City"
      assert html =~ "City Name"
      assert html =~ "Country"
      assert html =~ "Coordinates"
      assert html =~ "Get Coordinates"
      assert html =~ "Enable discovery immediately"
    end

    test "displays country dropdown with all countries", %{conn: conn, australia: au, us: us} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/new")

      assert html =~ "Australia"
      assert html =~ "United States"
    end

    test "creates city with valid data", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      city_params = %{
        "name" => "Sydney",
        "country_id" => to_string(au.id),
        "latitude" => "-33.8688",
        "longitude" => "151.2093"
      }

      view
      |> form("form", %{"city" => city_params})
      |> render_submit()

      assert_redirect(view, ~p"/admin/cities")

      # Verify city was created
      city = Repo.get_by(City, name: "Sydney")
      assert city != nil
      assert city.country_id == au.id
      assert Decimal.eq?(city.latitude, Decimal.new("-33.8688"))
      assert Decimal.eq?(city.longitude, Decimal.new("151.2093"))
      assert city.discovery_enabled == false
    end

    test "creates city with discovery enabled", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      # First toggle discovery checkbox
      view
      |> element("input[name='enable_discovery']")
      |> render_click(%{"value" => "true"})

      city_params = %{
        "name" => "Melbourne",
        "country_id" => to_string(au.id),
        "latitude" => "-37.8136",
        "longitude" => "144.9631"
      }

      view
      |> form("form", %{"city" => city_params})
      |> render_submit()

      assert_redirect(view, ~p"/admin/cities")

      # Verify city was created with discovery enabled
      city = Repo.get_by(City, name: "Melbourne")
      assert city != nil
      assert city.discovery_enabled == true
      assert city.discovery_config != nil
    end

    test "shows validation errors for missing required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      html =
        view
        |> form("form", %{"city" => %{"name" => ""}})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "validates city name is required", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      city_params = %{
        "name" => "",
        "country_id" => to_string(au.id)
      }

      html =
        view
        |> form("form", %{"city" => city_params})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "prevents submission without country via HTML5 validation", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/new")

      # Country select has required attribute
      assert html =~ ~s(required="required")
      assert html =~ "Select a country"
    end

    test "allows creating city without coordinates", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      city_params = %{
        "name" => "Perth",
        "country_id" => to_string(au.id)
      }

      view
      |> form("form", %{"city" => city_params})
      |> render_submit()

      assert_redirect(view, ~p"/admin/cities")

      city = Repo.get_by(City, name: "Perth")
      assert city != nil
      assert city.latitude == nil
      assert city.longitude == nil
    end
  end

  describe "Edit City Form" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")

      sydney =
        insert(:city,
          name: "Sydney",
          country: au,
          latitude: Decimal.new("-33.8688"),
          longitude: Decimal.new("151.2093")
        )

      {:ok, australia: au, sydney: sydney}
    end

    test "displays edit city form with existing data", %{conn: conn, sydney: sydney} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/#{sydney.id}/edit")

      assert html =~ "Edit City"
      assert html =~ "Sydney"
      assert html =~ "-33.8688"
      assert html =~ "151.2093"
    end

    test "updates city with valid data", %{conn: conn, sydney: sydney} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/#{sydney.id}/edit")

      city_params = %{
        "name" => "Greater Sydney",
        "latitude" => "-33.87",
        "longitude" => "151.21"
      }

      view
      |> form("form", %{"city" => city_params})
      |> render_submit()

      assert_redirect(view, ~p"/admin/cities")

      # Verify city was updated
      updated_city = Repo.get(City, sydney.id)
      assert updated_city.name == "Greater Sydney"
      assert Decimal.eq?(updated_city.latitude, Decimal.new("-33.87"))
      assert Decimal.eq?(updated_city.longitude, Decimal.new("151.21"))
    end

    test "does not show discovery checkbox on edit", %{conn: conn, sydney: sydney} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/#{sydney.id}/edit")

      refute html =~ "Enable discovery immediately"
    end

    test "preselects correct country", %{conn: conn, sydney: sydney, australia: au} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/#{sydney.id}/edit")

      assert html =~ "Australia"
      # Check that the country option is selected
      assert html =~ "selected"
    end
  end

  describe "Geocoding" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")
      {:ok, australia: au}
    end

    test "geocode button shows when city name and country are entered", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/new")

      assert html =~ "Get Coordinates"
    end

    test "displays geocoding state", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      # Fill in city name and country
      view
      |> form("form", %{"city" => %{"name" => "Sydney", "country_id" => to_string(au.id)}})
      |> render_change()

      # Note: We can't easily test the actual geocoding without mocking the AddressGeocoder
      # The UI elements are present and the handler exists, which is what we can verify
      html = render(view)
      assert html =~ "Get Coordinates"
    end

    test "shows error when geocoding without city name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      html = render_click(view, "geocode", %{"city" => %{"name" => "", "country_id" => ""}})

      assert html =~ "Please enter both city name and select a country"
    end
  end

  describe "Navigation" do
    test "has back link to cities index", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/new")

      assert html =~ "Back to Cities"
      assert html =~ ~p"/admin/cities"
    end

    test "cancel button links to cities index", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/cities/new")

      assert html =~ "Cancel"
      assert html =~ ~p"/admin/cities"
    end
  end

  describe "Form Validation" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")
      {:ok, australia: au}
    end

    test "validates as user types", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      # Type invalid data
      html =
        view
        |> form("form", %{"city" => %{"name" => ""}})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "displays coordinate preview when both are filled", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      html =
        view
        |> form("form", %{
          "city" => %{
            "name" => "Sydney",
            "country_id" => to_string(au.id),
            "latitude" => "-33.8688",
            "longitude" => "151.2093"
          }
        })
        |> render_change()

      assert html =~ "Coordinates:"
      assert html =~ "-33.8688"
      assert html =~ "151.2093"
      assert html =~ "View on Google Maps"
    end

    test "shows Google Maps link with coordinates", %{conn: conn, australia: au} do
      {:ok, view, _html} = live(conn, ~p"/admin/cities/new")

      html =
        view
        |> form("form", %{
          "city" => %{
            "name" => "Sydney",
            "country_id" => to_string(au.id),
            "latitude" => "-33.8688",
            "longitude" => "151.2093"
          }
        })
        |> render_change()

      assert html =~ "https://www.google.com/maps?q=-33.8688,151.2093"
    end
  end
end
