defmodule EventasaurusWeb.JsonLd.MovieSchemaTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.JsonLd.MovieSchema
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "build_movie_schema/3" do
    setup do
      # Create country, city
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      # Create venues
      venue1 = %Venue{
        id: 1,
        name: "Cinema City",
        address: "Main Street 123",
        slug: "cinema-city",
        latitude: 50.0647,
        longitude: 19.9450,
        city_id: 1,
        city_ref: city
      }

      venue2 = %Venue{
        id: 2,
        name: "Kino Pod Baranami",
        address: "Market Square 27",
        slug: "kino-pod-baranami",
        city_id: 1,
        city_ref: city
      }

      # Create minimal movie
      movie = %Movie{
        id: 1,
        title: "Dune: Part Two",
        slug: "dune-part-two",
        tmdb_metadata: nil,
        metadata: nil
      }

      # Create venues with info
      venues_with_info = [
        {venue1,
         %{
           count: 15,
           slug: "dune-part-two-cinema-city",
           date_range: "Mar 1-15",
           formats: ["IMAX", "3D"]
         }},
        {venue2, %{count: 8, slug: "dune-part-two-baranami", date_range: "Mar 1-10", formats: []}}
      ]

      {:ok,
       movie: movie,
       city: city,
       venues_with_info: venues_with_info,
       venue1: venue1,
       venue2: venue2}
    end

    test "generates basic movie schema", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "Movie"
      assert schema["name"] == "Dune: Part Two"
      assert String.contains?(schema["url"], "/c/krakow/movies/dune-part-two")
    end

    test "generates description with showtime count", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["description"] ==
               "Watch Dune: Part Two in Kraków. 23 showtimes available at 2 cinemas."
    end

    test "uses singular 'cinema' for single venue", %{movie: movie, city: city, venue1: venue1} do
      single_venue = [
        {venue1, %{count: 10, slug: "test-slug", date_range: "Mar 1-5", formats: []}}
      ]

      schema = MovieSchema.build_movie_schema(movie, city, single_venue)

      assert String.contains?(schema["description"], "1 cinema")
    end

    test "omits image when no poster_url or metadata", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      # Google requires real images, so we omit the field rather than using placeholder
      refute Map.has_key?(schema, "image")
    end

    test "generates JSON-LD string", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      json_ld = MovieSchema.generate(movie, city, venues_with_info)

      assert is_binary(json_ld)
      assert String.contains?(json_ld, "\"@context\":\"https://schema.org\"")
      assert String.contains?(json_ld, "\"@type\":\"Movie\"")
    end
  end

  describe "TMDb metadata integration" do
    setup do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Test Cinema",
        slug: "test-cinema",
        city_ref: city
      }

      venues_with_info = [
        {venue, %{count: 5, slug: "test-slug", date_range: "Mar 1-5", formats: []}}
      ]

      tmdb_metadata = %{
        "poster_path" => "/poster.jpg",
        "release_date" => "2024-03-01",
        "runtime" => 166,
        "vote_average" => 8.5,
        "vote_count" => 12_345,
        "genres" => [
          %{"id" => 878, "name" => "Science Fiction"},
          %{"id" => 12, "name" => "Adventure"}
        ],
        "credits" => %{
          "crew" => [
            %{"job" => "Director", "name" => "Denis Villeneuve"},
            %{"job" => "Producer", "name" => "Mary Parent"}
          ],
          "cast" => [
            %{"name" => "Timothée Chalamet", "character" => "Paul Atreides"},
            %{"name" => "Zendaya", "character" => "Chani"},
            %{"name" => "Rebecca Ferguson", "character" => "Lady Jessica"}
          ]
        }
      }

      movie = %Movie{
        id: 1,
        title: "Dune: Part Two",
        slug: "dune-part-two",
        tmdb_metadata: tmdb_metadata,
        metadata: nil
      }

      {:ok, movie: movie, city: city, venues_with_info: venues_with_info}
    end

    test "includes image from poster_url field (CDN wrapped)", %{
      city: city,
      venues_with_info: venues_with_info
    } do
      # Movie with poster_url set (as stored in DB)
      movie_with_poster = %Movie{
        id: 1,
        title: "Dune: Part Two",
        slug: "dune-part-two",
        poster_url: "https://image.tmdb.org/t/p/w500/poster.jpg",
        tmdb_metadata: nil,
        metadata: nil
      }

      schema = MovieSchema.build_movie_schema(movie_with_poster, city, venues_with_info)

      # Should use CDN-wrapped poster_url
      assert String.contains?(schema["image"], "/poster.jpg")
    end

    test "falls back to metadata poster_path when no poster_url", %{
      city: city,
      venues_with_info: venues_with_info
    } do
      # Movie with only metadata poster_path (no poster_url)
      # Note: poster_path is stored in metadata map, not tmdb_metadata (which is virtual)
      movie_with_metadata = %Movie{
        id: 1,
        title: "Dune: Part Two",
        slug: "dune-part-two",
        poster_url: nil,
        tmdb_metadata: nil,
        metadata: %{"poster_path" => "/tmdb-poster.jpg"}
      }

      schema = MovieSchema.build_movie_schema(movie_with_metadata, city, venues_with_info)

      # Should use CDN-wrapped poster path from metadata
      assert String.contains?(schema["image"], "/tmdb-poster.jpg")
    end

    test "includes release date", %{movie: movie, city: city, venues_with_info: venues_with_info} do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["datePublished"] == "2024-03-01"
    end

    test "includes runtime in ISO 8601 format", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["duration"] == "PT2H46M"
    end

    test "includes genres as array", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["genre"] == ["Science Fiction", "Adventure"]
    end

    test "includes director as Person", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["director"]["@type"] == "Person"
      assert schema["director"]["name"] == "Denis Villeneuve"
    end

    test "includes actors as array (max 10)", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert is_list(schema["actor"])
      assert length(schema["actor"]) == 3
      assert Enum.at(schema["actor"], 0)["@type"] == "Person"
      assert Enum.at(schema["actor"], 0)["name"] == "Timothée Chalamet"
    end

    test "includes TMDb aggregate rating", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["aggregateRating"]["@type"] == "AggregateRating"
      assert schema["aggregateRating"]["ratingValue"] == 8.5
      assert schema["aggregateRating"]["ratingCount"] == 12_345
      assert schema["aggregateRating"]["bestRating"] == 10
      assert schema["aggregateRating"]["worstRating"] == 0
    end
  end

  describe "image field precedence" do
    test "poster_url takes precedence over metadata poster_path" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Test Cinema",
        slug: "test-cinema",
        city_ref: city
      }

      venues_with_info = [
        {venue, %{count: 5, slug: "test-slug", date_range: "Mar 1-5", formats: []}}
      ]

      tmdb_metadata = %{
        "poster_path" => "/tmdb-poster.jpg",
        "release_date" => "2024-03-01",
        "runtime" => 150
      }

      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        poster_url: "https://image.tmdb.org/t/p/w500/stored-poster.jpg",
        tmdb_metadata: tmdb_metadata,
        metadata: nil
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      # poster_url should be used (CDN wrapped), not tmdb_metadata poster_path
      assert String.contains?(schema["image"], "/stored-poster.jpg")

      # TMDb values should still be used for other metadata
      assert schema["datePublished"] == "2024-03-01"
      assert schema["duration"] == "PT2H30M"
    end

    test "falls back to metadata poster_path when poster_url is nil" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Test Cinema",
        slug: "test-cinema",
        city_ref: city
      }

      venues_with_info = [
        {venue, %{count: 5, slug: "test-slug", date_range: "Mar 1-5", formats: []}}
      ]

      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        poster_url: nil,
        tmdb_metadata: %{
          "release_date" => "2024-03-01",
          "runtime" => 150
        },
        metadata: %{
          "poster_path" => "/metadata-poster.jpg"
        }
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      # Should fall back to metadata poster_path
      assert String.contains?(schema["image"], "/metadata-poster.jpg")

      # TMDb metadata values should be used for date and duration
      assert schema["datePublished"] == "2024-03-01"
      assert schema["duration"] == "PT2H30M"
    end
  end

  describe "duration formatting" do
    test "formats hours and minutes" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Cinema", slug: "test-cinema", city_ref: city}
      venues_with_info = [{venue, %{count: 5, slug: "test", date_range: "Mar 1-5", formats: []}}]

      movie = %Movie{
        id: 1,
        title: "Test",
        slug: "test",
        tmdb_metadata: %{"runtime" => 125},
        metadata: nil
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)
      assert schema["duration"] == "PT2H5M"
    end

    test "formats only hours when no minutes" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Cinema", slug: "test-cinema", city_ref: city}
      venues_with_info = [{venue, %{count: 5, slug: "test", date_range: "Mar 1-5", formats: []}}]

      movie = %Movie{
        id: 1,
        title: "Test",
        slug: "test",
        tmdb_metadata: %{"runtime" => 120},
        metadata: nil
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)
      assert schema["duration"] == "PT2H"
    end

    test "formats only minutes when less than hour" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Cinema", slug: "test-cinema", city_ref: city}
      venues_with_info = [{venue, %{count: 5, slug: "test", date_range: "Mar 1-5", formats: []}}]

      movie = %Movie{
        id: 1,
        title: "Test",
        slug: "test",
        tmdb_metadata: %{"runtime" => 45},
        metadata: nil
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)
      assert schema["duration"] == "PT45M"
    end
  end

  describe "screening events ItemList (carousel)" do
    setup do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue1 = %Venue{
        id: 1,
        name: "Cinema City",
        address: "Main Street 123",
        slug: "cinema-city",
        city_id: 1,
        city_ref: city,
        venue_type: "cinema",
        latitude: 50.0647,
        longitude: 19.9450
      }

      venue2 = %Venue{
        id: 2,
        name: "Kino Pod Baranami",
        address: "Market Square 27",
        slug: "kino-pod-baranami",
        city_id: 1,
        city_ref: city,
        venue_type: "cinema"
      }

      movie = %Movie{
        id: 1,
        title: "Dune: Part Two",
        slug: "dune-part-two",
        poster_url: "https://image.tmdb.org/t/p/w500/dune2.jpg",
        tmdb_metadata: nil,
        metadata: nil
      }

      venues_with_info = [
        {venue1,
         %{
           count: 15,
           slug: "dune-part-two-cinema-city",
           date_range: "Mar 1-15",
           formats: ["IMAX", "3D"],
           dates: [~D[2024-03-01], ~D[2024-03-02], ~D[2024-03-03]]
         }},
        {venue2,
         %{
           count: 8,
           slug: "dune-part-two-baranami",
           date_range: "Mar 1-10",
           formats: [],
           dates: [~D[2024-03-01], ~D[2024-03-05]]
         }}
      ]

      {:ok, movie: movie, city: city, venues_with_info: venues_with_info}
    end

    test "includes subjectOf with ItemList of ScreeningEvents", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["subjectOf"]["@type"] == "ItemList"
      assert schema["subjectOf"]["name"] == "Screenings of Dune: Part Two in Kraków"
      assert schema["subjectOf"]["numberOfItems"] == 2
    end

    test "includes ListItem with ScreeningEvent for each venue", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      items = schema["subjectOf"]["itemListElement"]
      assert length(items) == 2

      first_item = Enum.at(items, 0)
      assert first_item["@type"] == "ListItem"
      assert first_item["position"] == 1
      assert first_item["item"]["@type"] == "ScreeningEvent"
      assert first_item["item"]["name"] == "Dune: Part Two at Cinema City"
    end

    test "ScreeningEvent includes MovieTheater location for cinema venues", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      location = first_item["item"]["location"]

      assert location["@type"] == "MovieTheater"
      assert location["name"] == "Cinema City"
      assert String.contains?(location["@id"], "/c/krakow/venues/cinema-city")
    end

    test "ScreeningEvent location includes PostalAddress", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      address = first_item["item"]["location"]["address"]

      assert address["@type"] == "PostalAddress"
      assert address["streetAddress"] == "Main Street 123"
      assert address["addressLocality"] == "Kraków"
      assert address["addressCountry"] == "PL"
    end

    test "ScreeningEvent location includes geo coordinates when available", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      geo = first_item["item"]["location"]["geo"]

      assert geo["@type"] == "GeoCoordinates"
      assert geo["latitude"] == 50.0647
      assert geo["longitude"] == 19.9450

      # Second venue has no coordinates
      second_item = Enum.at(schema["subjectOf"]["itemListElement"], 1)
      refute Map.has_key?(second_item["item"]["location"], "geo")
    end

    test "ScreeningEvent includes workPresented movie reference with image", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      work = first_item["item"]["workPresented"]

      assert work["@type"] == "Movie"
      assert work["name"] == "Dune: Part Two"
      # Google requires image field on all Movie objects, including nested references
      assert String.contains?(work["image"], "/dune2.jpg")
    end

    test "ScreeningEvent includes activity URL", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      assert String.contains?(first_item["item"]["url"], "/activities/dune-part-two-cinema-city")
    end

    test "ScreeningEvent includes showtime count in description", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      assert String.contains?(first_item["item"]["description"], "15 showtimes available")
      assert String.contains?(first_item["item"]["description"], "Mar 1-15")

      second_item = Enum.at(schema["subjectOf"]["itemListElement"], 1)
      assert String.contains?(second_item["item"]["description"], "8 showtimes available")
    end

    test "ScreeningEvent includes startDate from first available date", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      assert first_item["item"]["startDate"] == "2024-03-01"
    end

    test "ScreeningEvent includes videoFormat when formats available", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      # Multiple formats returns array
      assert first_item["item"]["videoFormat"] == ["IMAX", "3D"]

      # Second venue has no formats
      second_item = Enum.at(schema["subjectOf"]["itemListElement"], 1)
      refute Map.has_key?(second_item["item"], "videoFormat")
    end

    test "ScreeningEvent includes image from movie", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      assert String.contains?(first_item["item"]["image"], "/dune2.jpg")
    end

    test "ScreeningEvent includes eventAttendanceMode and eventStatus", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)

      assert first_item["item"]["eventAttendanceMode"] ==
               "https://schema.org/OfflineEventAttendanceMode"

      assert first_item["item"]["eventStatus"] == "https://schema.org/EventScheduled"
    end

    test "uses singular 'showtime' for single screening" do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Test Cinema",
        slug: "test-cinema",
        city_ref: city,
        venue_type: "cinema"
      }

      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_metadata: nil,
        metadata: nil
      }

      venues_with_info = [
        {venue, %{count: 1, slug: "test-slug", date_range: "Mar 1", formats: [], dates: []}}
      ]

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["subjectOf"]["itemListElement"], 0)
      assert String.contains?(first_item["item"]["description"], "1 showtime available")
    end

    test "does not include subjectOf when no venues" do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_metadata: nil,
        metadata: nil
      }

      schema = MovieSchema.build_movie_schema(movie, city, [])

      refute Map.has_key?(schema, "subjectOf")
    end
  end

  describe "multiple directors" do
    test "returns array when multiple directors" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Cinema", slug: "test-cinema", city_ref: city}
      venues_with_info = [{venue, %{count: 5, slug: "test", date_range: "Mar 1-5", formats: []}}]

      tmdb_metadata = %{
        "credits" => %{
          "crew" => [
            %{"job" => "Director", "name" => "Lana Wachowski"},
            %{"job" => "Director", "name" => "Lilly Wachowski"},
            %{"job" => "Producer", "name" => "Joel Silver"}
          ]
        }
      }

      movie = %Movie{
        id: 1,
        title: "The Matrix",
        slug: "the-matrix",
        tmdb_metadata: tmdb_metadata,
        metadata: nil
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert is_list(schema["director"])
      assert length(schema["director"]) == 2
      assert Enum.at(schema["director"], 0)["name"] == "Lana Wachowski"
      assert Enum.at(schema["director"], 1)["name"] == "Lilly Wachowski"
    end
  end
end
