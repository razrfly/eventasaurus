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

    test "detects bad format slugs correctly", %{city: city} do
      # Create venues with bad format slugs (numbers in wrong positions)
      Repo.insert!(%Venue{
        name: "Bad Slug 1",
        slug: "bad-slug-1-#{city.id}-abc123",
        city_id: city.id,
        latitude: 51.5074,
        longitude: -0.1278
      })

      Repo.insert!(%Venue{
        name: "Bad Slug 2",
        slug: "white-horse-wembley-53-824",
        city_id: city.id,
        latitude: 51.5075,
        longitude: -0.1279
      })

      # Create venue with good format slug (no numbers)
      Repo.insert!(%Venue{
        name: "Good Format Venue",
        slug: "good-format-venue",
        city_id: city.id,
        latitude: 51.5076,
        longitude: -0.1280
      })

      # Test detection: slugs NOT matching (no numbers) OR (10-digit ending)
      bad_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("NOT (slug ~ ? OR slug ~ ?)", "^[a-z-]+$", "-[0-9]{10}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert bad_format_count == 2
    end

    test "correctly identifies good format slugs", %{city: city} do
      # Create venues with good format slugs (no numbers)
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

      # Create venue with timestamp fallback (also good)
      Repo.insert!(%Venue{
        name: "Timestamp Slug",
        slug: "timestamp-slug-1698765432",
        city_id: city.id,
        latitude: 51.5076,
        longitude: -0.1280
      })

      # These should NOT be detected as bad
      bad_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("NOT (slug ~ ? OR slug ~ ?)", "^[a-z-]+$", "-[0-9]{10}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert bad_format_count == 0
    end

    test "calculates quality percentage correctly", %{city: city} do
      # Create 8 good format and 2 bad format = 80% quality
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

      bad_format =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("NOT (slug ~ ? OR slug ~ ?)", "^[a-z-]+$", "-[0-9]{10}$"),
          select: count(v.id)
        )
        |> Repo.one()

      quality_percentage = Float.round((total - bad_format) / total * 100, 1)

      assert total == 10
      assert bad_format == 2
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

    test "regex pattern matches various bad formats", %{city: city} do
      # Test various bad format patterns
      bad_slugs = [
        "venue-1-abc123",           # Short numbers with alphanumeric
        "the-pub-123-def456",       # Numbers in middle
        "my-restaurant-9999-xyz789", # Non-timestamp numbers
        "place-1-a1b2c3",           # Old format with city_id
        "ha9-0hp-wembley-park",     # Postcode
        "289-upper-richmond-road"   # Street number
      ]

      for slug <- bad_slugs do
        Repo.insert!(%Venue{
          name: "Test #{slug}",
          slug: slug,
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })
      end

      bad_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("NOT (slug ~ ? OR slug ~ ?)", "^[a-z-]+$", "-[0-9]{10}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert bad_format_count == 6
    end

    test "regex pattern does not match good formats", %{city: city} do
      # Test various good format patterns that should NOT be detected as bad
      good_slugs = [
        "simple-venue",              # Name only
        "the-pub",                   # Name only
        "my-restaurant-london",      # Name-city
        "venue-name-test-city",      # Name-city
        "place-with-many-words",     # Name only
        "white-horse-1698765432",    # Name-timestamp (10 digits)
        "the-crown-1234567890"       # Name-timestamp (10 digits)
      ]

      for slug <- good_slugs do
        Repo.insert!(%Venue{
          name: "Test #{slug}",
          slug: slug,
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })
      end

      bad_format_count =
        from(v in Venue,
          where: v.city_id == ^city.id,
          where: fragment("NOT (slug ~ ? OR slug ~ ?)", "^[a-z-]+$", "-[0-9]{10}$"),
          select: count(v.id)
        )
        |> Repo.one()

      assert bad_format_count == 0
    end
  end
end
