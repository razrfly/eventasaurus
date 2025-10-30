defmodule EventasaurusApp.Venues.RegenerateSlugsByCityJobTest do
  use EventasaurusApp.DataCase, async: true
  use Oban.Testing, repo: EventasaurusApp.Repo

  import Ecto.Query

  alias EventasaurusApp.Venues.{Venue, RegenerateSlugsByCityJob}
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusApp.Repo

  describe "perform/1" do
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

    test "successfully regenerates slugs for all venues in city", %{city: city} do
      # Create venues with old-style slugs (simulated by direct insertion)
      venue1 =
        Repo.insert!(%Venue{
          name: "The Red Lion",
          slug: "the-red-lion-#{city.id}-abc123",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })

      venue2 =
        Repo.insert!(%Venue{
          name: "The Blue Dragon",
          slug: "the-blue-dragon-#{city.id}-def456",
          city_id: city.id,
          latitude: 51.5075,
          longitude: -0.1279
        })

      # Perform the job
      assert {:ok, result} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: city.id,
                 city_slug: city.slug
               })

      # Verify results
      assert result.total_venues == 2
      assert result.updated == 2
      assert result.skipped == 0
      assert result.failed == 0
      assert result.city_name == "Test City"

      # Verify slugs were actually updated
      updated_venue1 = Repo.get!(Venue, venue1.id)
      updated_venue2 = Repo.get!(Venue, venue2.id)

      # New slugs should follow current pattern (no city_id in slug)
      refute updated_venue1.slug == venue1.slug
      refute updated_venue2.slug == venue2.slug

      # New slugs should be simpler (just name or name-city)
      assert updated_venue1.slug == "the-red-lion" or
               updated_venue1.slug == "the-red-lion-test-city"

      assert updated_venue2.slug == "the-blue-dragon" or
               updated_venue2.slug == "the-blue-dragon-test-city"
    end

    test "skips venues where slug doesn't change", %{city: city} do
      # Create venue with already correct slug
      venue =
        Repo.insert!(%Venue{
          name: "The Green Pub",
          slug: "the-green-pub",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })

      assert {:ok, result} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: city.id,
                 city_slug: city.slug
               })

      assert result.total_venues == 1
      assert result.skipped == 1
      assert result.updated == 0
      assert result.failed == 0

      # Verify slug unchanged
      updated_venue = Repo.get!(Venue, venue.id)
      assert updated_venue.slug == venue.slug
    end

    test "force_all regenerates even unchanged slugs", %{city: city} do
      # Create venue with already correct slug
      _venue =
        Repo.insert!(%Venue{
          name: "The Yellow Tavern",
          slug: "the-yellow-tavern",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })

      assert {:ok, result} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: city.id,
                 city_slug: city.slug,
                 force_all: true
               })

      assert result.total_venues == 1
      # With force_all, it should update even if slug is same
      assert result.updated == 1
      assert result.skipped == 0
    end

    test "handles venues with duplicate names correctly", %{city: city} do
      # Create two venues with same name (should get different slugs)
      venue1 =
        Repo.insert!(%Venue{
          name: "The Crown",
          slug: "the-crown-#{city.id}-aaa111",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })

      venue2 =
        Repo.insert!(%Venue{
          name: "The Crown",
          slug: "the-crown-#{city.id}-bbb222",
          city_id: city.id,
          latitude: 51.5075,
          longitude: -0.1279
        })

      assert {:ok, result} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: city.id,
                 city_slug: city.slug
               })

      assert result.total_venues == 2
      assert result.updated == 2

      # Verify they got different slugs
      updated_venue1 = Repo.get!(Venue, venue1.id)
      updated_venue2 = Repo.get!(Venue, venue2.id)

      refute updated_venue1.slug == updated_venue2.slug

      # First one should get simple slug, second should get disambiguated
      assert updated_venue1.slug == "the-crown" or
               updated_venue1.slug == "the-crown-test-city"

      assert updated_venue2.slug != "the-crown"
    end

    test "processes large number of venues in batches", %{city: city} do
      # Create 150 venues (more than one batch of 100)
      _venues =
        for i <- 1..150 do
          Repo.insert!(%Venue{
            name: "Venue #{i}",
            slug: "venue-#{i}-#{city.id}-old",
            city_id: city.id,
            latitude: 51.5074,
            longitude: -0.1278
          })
        end

      assert {:ok, result} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: city.id,
                 city_slug: city.slug
               })

      assert result.total_venues == 150
      assert result.updated == 150
      assert result.failed == 0

      # Verify all were actually updated
      updated_count =
        Venue
        |> where([v], v.city_id == ^city.id)
        |> where([v], not like(v.slug, "%-old"))
        |> Repo.aggregate(:count)

      assert updated_count == 150
    end

    test "returns error when city not found" do
      assert {:error, error} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: 99999,
                 city_slug: "nonexistent"
               })

      assert error =~ "City not found"
    end

    test "returns error when city_id missing" do
      assert {:error, error} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_slug: "test"
               })

      assert error =~ "Missing required parameter: city_id"
    end

    test "tracks failed venues in metadata", %{city: city} do
      # Create a venue with invalid data that might cause update to fail
      # This is tricky to test without breaking constraints, but we can at least
      # verify the metadata structure is correct
      _venue =
        Repo.insert!(%Venue{
          name: "Normal Venue",
          slug: "normal-venue-old",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })

      assert {:ok, result} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: city.id,
                 city_slug: city.slug
               })

      # Verify metadata structure
      assert is_list(result.failed_venues)
      assert is_integer(result.duration_seconds)
      assert %DateTime{} = result.completed_at
    end

    test "handles UTF-8 venue names correctly", %{city: city} do
      # Create venue with UTF-8 characters
      venue =
        Repo.insert!(%Venue{
          name: "Café Müller",
          slug: "cafe-muller-#{city.id}-old",
          city_id: city.id,
          latitude: 51.5074,
          longitude: -0.1278
        })

      assert {:ok, result} =
               perform_job(RegenerateSlugsByCityJob, %{
                 city_id: city.id,
                 city_slug: city.slug
               })

      assert result.updated == 1
      assert result.failed == 0

      # Verify slug was properly generated
      updated_venue = Repo.get!(Venue, venue.id)
      assert updated_venue.slug =~ "cafe-muller"
    end
  end

  describe "enqueue/3" do
    test "successfully enqueues job with city_id" do
      assert {:ok, job} = RegenerateSlugsByCityJob.enqueue(123, "london")
      assert job.args[:city_id] == 123
      assert job.args[:city_slug] == "london"
      assert job.args[:force_all] == false
    end

    test "supports force_all option" do
      assert {:ok, job} = RegenerateSlugsByCityJob.enqueue(123, "london", force_all: true)
      assert job.args[:force_all] == true
    end

    test "works without city_slug" do
      assert {:ok, job} = RegenerateSlugsByCityJob.enqueue(123)
      assert job.args[:city_id] == 123
      assert is_nil(job.args[:city_slug])
    end
  end
end
