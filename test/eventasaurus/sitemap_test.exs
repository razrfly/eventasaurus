defmodule Eventasaurus.SitemapTest do
  use EventasaurusApp.DataCase, async: true

  alias Eventasaurus.Sitemap
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "movie_urls/1" do
    setup do
      # Create country and city
      country = insert(:country, code: "PL", slug: "poland")
      city = insert(:city, slug: "krakow", discovery_enabled: true, country: country)

      # Create venue in the city (is_public: true for sitemap visibility)
      venue =
        insert(:venue, slug: "cinema-city", city_id: city.id, city_ref: city, is_public: true)

      # Create movie
      movie = insert(:movie, slug: "dune-part-two", updated_at: ~N[2024-12-15 10:00:00])

      # Create screening event
      event =
        insert(:public_event,
          slug: "dune-screening",
          venue_id: venue.id,
          venue: venue,
          starts_at: ~U[2024-12-20 19:00:00Z]
        )

      # Associate movie with event
      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: event.id,
        movie_id: movie.id
      })

      {:ok, movie: movie, city: city, venue: venue, event: event}
    end

    test "generates URLs for movies with screenings in active cities", %{movie: movie, city: city} do
      urls = Sitemap.stream_urls(host: "wombie.fyi") |> Enum.to_list()

      movie_url =
        Enum.find(urls, fn url ->
          url.loc == "https://wombie.fyi/c/#{city.slug}/movies/#{movie.slug}"
        end)

      assert movie_url != nil
      assert movie_url.changefreq == :weekly
      assert movie_url.priority == 0.8
      assert movie_url.lastmod == NaiveDateTime.to_date(movie.updated_at)
    end

    test "does not generate URLs for movies in cities with discovery disabled" do
      # Create city with discovery disabled
      country = insert(:country, code: "US", slug: "usa")

      disabled_city =
        insert(:city, slug: "inactive-city", discovery_enabled: false, country: country)

      # Create venue in disabled city (is_public: true for consistency)
      venue =
        insert(:venue,
          slug: "inactive-venue",
          city_id: disabled_city.id,
          city_ref: disabled_city,
          is_public: true
        )

      # Create movie and screening
      movie = insert(:movie, slug: "test-movie")
      event = insert(:public_event, venue_id: venue.id, venue: venue)

      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: event.id,
        movie_id: movie.id
      })

      urls = Sitemap.stream_urls(host: "wombie.fyi") |> Enum.to_list()

      # Should not include URL for movie in disabled city
      movie_url =
        Enum.find(urls, fn url ->
          String.contains?(url.loc, "/c/#{disabled_city.slug}/movies/#{movie.slug}")
        end)

      assert movie_url == nil
    end

    test "generates distinct URLs for movies shown in multiple cities", %{
      city: city1,
      venue: venue1
    } do
      # Create second city
      country = insert(:country, code: "PL", slug: "poland-2")
      city2 = insert(:city, slug: "warsaw", discovery_enabled: true, country: country)

      # Create venue in second city (is_public: true for sitemap visibility)
      venue2 =
        insert(:venue, slug: "cinema-warsaw", city_id: city2.id, city_ref: city2, is_public: true)

      # Create movie
      movie = insert(:movie, slug: "multi-city-movie")

      # Create screening in first city (reuse from setup)
      event1 = insert(:public_event, venue_id: venue1.id, venue: venue1)

      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: event1.id,
        movie_id: movie.id
      })

      # Create screening in second city
      event2 = insert(:public_event, venue_id: venue2.id, venue: venue2)

      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: event2.id,
        movie_id: movie.id
      })

      urls = Sitemap.stream_urls(host: "wombie.fyi") |> Enum.to_list()

      # Should have URLs for both cities
      krakow_url =
        Enum.find(urls, fn url ->
          url.loc == "https://wombie.fyi/c/#{city1.slug}/movies/#{movie.slug}"
        end)

      warsaw_url =
        Enum.find(urls, fn url ->
          url.loc == "https://wombie.fyi/c/warsaw/movies/#{movie.slug}"
        end)

      assert krakow_url != nil
      assert warsaw_url != nil
    end

    test "does not generate URLs for movies with nil or empty slugs" do
      country = insert(:country, code: "PL", slug: "poland")
      city = insert(:city, slug: "krakow", discovery_enabled: true, country: country)
      venue = insert(:venue, city_id: city.id, city_ref: city, is_public: true)

      # Movie with nil slug
      movie_nil = insert(:movie, slug: nil)
      event1 = insert(:public_event, venue_id: venue.id, venue: venue)

      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: event1.id,
        movie_id: movie_nil.id
      })

      # Movie with empty slug
      movie_empty = insert(:movie, slug: "")
      event2 = insert(:public_event, venue_id: venue.id, venue: venue)

      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: event2.id,
        movie_id: movie_empty.id
      })

      urls = Sitemap.stream_urls(host: "wombie.fyi") |> Enum.to_list()

      # Should not have any URLs with nil or empty slugs
      invalid_urls =
        Enum.filter(urls, fn url ->
          String.contains?(url.loc, "/movies/") and
            (String.ends_with?(url.loc, "/movies/") or String.contains?(url.loc, "/movies/nil"))
        end)

      assert invalid_urls == []
    end

    test "uses current date for lastmod when updated_at is nil" do
      country = insert(:country, code: "PL", slug: "poland")
      city = insert(:city, slug: "krakow", discovery_enabled: true, country: country)
      venue = insert(:venue, city_id: city.id, city_ref: city, is_public: true)

      # Movie with nil updated_at
      movie = insert(:movie, slug: "no-update-date", updated_at: nil)
      event = insert(:public_event, venue_id: venue.id, venue: venue)

      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: event.id,
        movie_id: movie.id
      })

      urls = Sitemap.stream_urls(host: "wombie.fyi") |> Enum.to_list()

      movie_url =
        Enum.find(urls, fn url ->
          String.contains?(url.loc, "/movies/#{movie.slug}")
        end)

      assert movie_url != nil
      assert movie_url.lastmod == Date.utc_today()
    end
  end

  # NOTE: aggregation_urls/1 tests removed because AggregatedEventGroup is a virtual struct
  # (not a database table), so it cannot be queried with Ecto. Aggregation URLs are
  # generated dynamically and don't need to be in the sitemap.

  describe "stream_urls/1 integration" do
    test "includes all URL types in stream" do
      country = insert(:country, code: "PL", slug: "poland")
      city = insert(:city, slug: "krakow", discovery_enabled: true, country: country)

      venue =
        insert(:venue, slug: "test-venue", city_id: city.id, city_ref: city, is_public: true)

      # Create an activity
      activity =
        insert(:public_event,
          slug: "test-activity",
          venue_id: venue.id,
          venue: venue,
          starts_at: ~U[2024-12-20 19:00:00Z],
          updated_at: ~N[2024-12-15 10:00:00]
        )

      # Create a movie with screening
      movie = insert(:movie, slug: "test-movie")

      Repo.insert!(%EventasaurusDiscovery.PublicEvents.EventMovie{
        event_id: activity.id,
        movie_id: movie.id
      })

      urls = Sitemap.stream_urls(host: "wombie.fyi") |> Enum.to_list()

      # Should include static URLs
      homepage = Enum.find(urls, fn url -> url.loc == "https://wombie.fyi" end)
      assert homepage != nil

      # Should include activity URLs
      activity_url =
        Enum.find(urls, fn url ->
          String.contains?(url.loc, "/activities/#{activity.slug}")
        end)

      assert activity_url != nil

      # Should include city URLs
      city_url = Enum.find(urls, fn url -> url.loc == "https://wombie.fyi/c/krakow" end)
      assert city_url != nil

      # Should include venue URLs
      venue_url =
        Enum.find(urls, fn url ->
          url.loc == "https://wombie.fyi/c/krakow/venues/#{venue.slug}"
        end)

      assert venue_url != nil

      # Should include movie URLs
      movie_url =
        Enum.find(urls, fn url ->
          url.loc == "https://wombie.fyi/c/krakow/movies/#{movie.slug}"
        end)

      assert movie_url != nil
    end
  end
end
