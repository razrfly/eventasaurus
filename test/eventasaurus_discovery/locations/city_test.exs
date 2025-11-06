defmodule EventasaurusDiscovery.Locations.CityTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "changeset/2 with GeoNames validation (Phase 3 - Schema Level)" do
    setup do
      gb = insert(:country, name: "United Kingdom", code: "GB")
      au = insert(:country, name: "Australia", code: "AU")
      us = insert(:country, name: "United States", code: "US")
      {:ok, gb: gb, au: au, us: us}
    end

    test "accepts valid UK city from GeoNames", %{gb: gb} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "London",
          country_id: gb.id,
          latitude: Decimal.new("51.5074"),
          longitude: Decimal.new("-0.1278")
        })

      assert changeset.valid?
      assert {:ok, city} = Repo.insert(changeset)
      assert city.name == "London"
      assert city.country_id == gb.id
    end

    test "accepts valid AU city from GeoNames", %{au: au} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "Sydney",
          country_id: au.id,
          latitude: Decimal.new("-33.8688"),
          longitude: Decimal.new("151.2093")
        })

      assert changeset.valid?
      assert {:ok, city} = Repo.insert(changeset)
      assert city.name == "Sydney"
      assert city.country_id == au.id
    end

    test "accepts valid US city from GeoNames", %{us: us} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "New York City",
          country_id: us.id
        })

      assert changeset.valid?
      assert {:ok, city} = Repo.insert(changeset)
      assert city.name == "New York City"
    end

    test "rejects UK street address from bug report (10-16 Botchergate)", %{gb: gb} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "10-16 Botchergate",
          country_id: gb.id
        })

      refute changeset.valid?
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "rejects UK street address (168 Lower Briggate)", %{gb: gb} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "168 Lower Briggate",
          country_id: gb.id
        })

      refute changeset.valid?
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "rejects UK street address (48 Chapeltown)", %{gb: gb} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "48 Chapeltown",
          country_id: gb.id
        })

      refute changeset.valid?
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "rejects AU street address from bug report (425 Burwood Hwy)", %{au: au} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "425 Burwood Hwy",
          country_id: au.id
        })

      refute changeset.valid?
      assert "is not a valid city in Australia" in errors_on(changeset).name
    end

    test "rejects AU street address (46-54 Collie St)", %{au: au} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "46-54 Collie St",
          country_id: au.id
        })

      refute changeset.valid?
      assert "is not a valid city in Australia" in errors_on(changeset).name
    end

    test "rejects UK postcode (SW18 2SS)", %{gb: gb} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "SW18 2SS",
          country_id: gb.id
        })

      refute changeset.valid?
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "rejects US ZIP code (90210)", %{us: us} do
      changeset =
        %City{}
        |> City.changeset(%{
          name: "90210",
          country_id: us.id
        })

      refute changeset.valid?
      assert "is not a valid city in United States" in errors_on(changeset).name
    end

    test "validates on city creation", %{gb: gb} do
      # Try to create city with street address
      changeset =
        %City{}
        |> City.changeset(%{
          name: "10-16 Botchergate",
          country_id: gb.id
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "validates on city update", %{gb: gb} do
      # Create valid city first
      {:ok, city} =
        %City{}
        |> City.changeset(%{
          name: "London",
          country_id: gb.id
        })
        |> Repo.insert()

      # Try to update to invalid name
      changeset =
        city
        |> City.changeset(%{name: "10-16 Botchergate"})

      refute changeset.valid?
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "skips validation when name is not changed", %{gb: gb} do
      # Create valid city first
      {:ok, city} =
        %City{}
        |> City.changeset(%{
          name: "London",
          country_id: gb.id
        })
        |> Repo.insert()

      # Update other fields without changing name - should succeed
      changeset =
        city
        |> City.changeset(%{
          latitude: Decimal.new("51.5074"),
          longitude: Decimal.new("-0.1278")
        })

      assert changeset.valid?
      assert {:ok, updated} = Repo.update(changeset)
      assert updated.name == "London"
    end

    test "skips validation when country is not available", %{gb: gb} do
      # Create changeset with name but no country_id
      changeset =
        %City{}
        |> City.changeset(%{
          name: "10-16 Botchergate"
        })

      # Validation should fail on required country_id, not on GeoNames
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).country_id
      # GeoNames validation should not run
      refute Map.has_key?(errors_on(changeset), :name)
    end

    test "all three validation layers work together", %{gb: gb} do
      # This demonstrates the defense-in-depth approach
      # Layer 1: Transformers (not tested here)
      # Layer 2: VenueProcessor/CityManager (tested in other files)
      # Layer 3: Schema validation (tested here)

      invalid_cities = [
        "10-16 Botchergate",
        "168 Lower Briggate",
        "48 Chapeltown"
      ]

      for invalid_city <- invalid_cities do
        changeset =
          %City{}
          |> City.changeset(%{
            name: invalid_city,
            country_id: gb.id
          })

        refute changeset.valid?,
               "Schema validation (Layer 3) failed to reject: #{invalid_city}"

        assert "is not a valid city in United Kingdom" in errors_on(changeset).name
      end
    end
  end
end
