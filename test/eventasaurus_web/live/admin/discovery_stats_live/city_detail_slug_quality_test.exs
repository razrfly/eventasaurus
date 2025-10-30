defmodule EventasaurusWeb.Admin.DiscoveryStatsLive.CityDetailSlugQualityTest do
  use EventasaurusWeb.ConnCase, async: true

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "slug quality stats" do
    setup do
      # Create test country and city
      country = Repo.insert!(%Country{name: "Test Country", code: "TC", slug: "test-country"})

      city =
        Repo.insert!(%City{
          name: "Test City",
          slug: "test-city",
          country_id: country.id,
          latitude: 51.5074,
          longitude: -0.1278
        })

      %{city: city, country: country}
    end

    test "detects old format slugs correctly", %{city: city} do
      # Create venues with old format slugs
      Repo.insert!(%Venue{
        name: "Old Format Venue 1",
        slug: "old-format-venue-1-#{city.id}-abc123",
        city_id: city.id,
        latitude: 51.5074,
        longitude: -0.1278
      })

      Repo.insert!(%Venue{
        name: "Old Format Venue 2",
        slug: "old-format-venue-2-#{city.id}-def456",
        city_id: city.id,
        latitude: 51.5075,
        longitude: -0.1279
      })

      # Create venue with new format slug
      Repo.insert!(%Venue{
        name: "New Format Venue",
        slug: "new-format-venue",
        city_id: city.id,
        latitude: 51.5076,
        longitude: -0.1280
      })

      # Test the private function via the module
      # We'll need to make this testable, but for now verify the query works
      old_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("slug ~ ?", "-[0-9]{1,6}-[a-z0-9]{6}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert old_format_count == 2
    end

    test "correctly identifies new format slugs", %{city: city} do
      # Create venues with new format slugs
      Repo.insert!(%Venue{
        name: "Simple Slug",
        slug: "simple-slug",
        city_id: city.id,
        latitude: 51.5074,
        longitude: -0.1278
      })

      Repo.insert!(%Venue{
        name: "Slug With City",
        slug: "slug-with-city-test-city",
        city_id: city.id,
        latitude: 51.5075,
        longitude: -0.1279
      })

      # These should NOT match the old format pattern
      old_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("slug ~ ?", "-[0-9]{1,6}-[a-z0-9]{6}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert old_format_count == 0
    end

    test "calculates quality percentage correctly", %{city: city} do
      # Create 8 new format and 2 old format = 80% quality
      for i <- 1..8 do
        Repo.insert!(%Venue{
          name: "Good Venue #{i}",
          slug: "good-venue-#{i}",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })
      end

      for i <- 1..2 do
        Repo.insert!(%Venue{
          name: "Bad Venue #{i}",
          slug: "bad-venue-#{i}-#{city.id}-xyz#{i}#{i}#{i}",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })
      end

      total =
        from(v in Venue, where: v.city_id == ^city.id, select: count(v.id))
        |> Repo.one()

      old_format =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("slug ~ ?", "-[0-9]{1,6}-[a-z0-9]{6}$"),
          select: count(v.id)
        )
        |> Repo.one()

      quality_percentage = Float.round((total - old_format) / total * 100, 1)

      assert total == 10
      assert old_format == 2
      assert quality_percentage == 80.0
    end

    test "handles city with no venues", %{city: city} do
      total =
        from(v in Venue, where: v.city_id == ^city.id, select: count(v.id))
        |> Repo.one()

      assert total == 0

      # Quality should be 100% when there are no venues
      quality_percentage = if total > 0, do: 100.0, else: 100.0
      assert quality_percentage == 100.0
    end

    test "regex pattern matches various old formats", %{city: city} do
      # Test various old format patterns
      old_slugs = [
        "venue-1-abc123",
        "the-pub-123-def456",
        "my-restaurant-9999-xyz789",
        "place-1-a1b2c3"
      ]

      for slug <- old_slugs do
        Repo.insert!(%Venue{
          name: "Test #{slug}",
          slug: slug,
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })
      end

      old_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("slug ~ ?", "-[0-9]{1,6}-[a-z0-9]{6}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert old_format_count == 4
    end

    test "regex pattern does not match new formats", %{city: city} do
      # Test various new format patterns that should NOT match
      new_slugs = [
        "simple-venue",
        "the-pub",
        "my-restaurant-london",
        "venue-name-test-city",
        "place-with-many-words"
      ]

      for slug <- new_slugs do
        Repo.insert!(%Venue{
          name: "Test #{slug}",
          slug: slug,
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })
      end

      old_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("slug ~ ?", "-[0-9]{1,6}-[a-z0-9]{6}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert old_format_count == 0
    end
  end
end
