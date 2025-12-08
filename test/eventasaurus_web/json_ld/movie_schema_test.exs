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

    test "includes placeholder image when no metadata", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert String.contains?(schema["image"], "placehold.co")
      assert String.contains?(schema["image"], URI.encode("Dune: Part Two"))
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

    test "includes TMDb poster image", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["image"] == "https://image.tmdb.org/t/p/w500/poster.jpg"
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

  describe "OMDb metadata integration" do
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

      omdb_metadata = %{
        "Poster" => "https://example.com/poster.jpg",
        "Released" => "01 Mar 2024",
        "Runtime" => "166 min",
        "Genre" => "Sci-Fi, Adventure, Drama",
        "Director" => "Denis Villeneuve",
        "Actors" => "Timothée Chalamet, Zendaya, Rebecca Ferguson",
        "imdbRating" => "8.5",
        "imdbVotes" => "123,456"
      }

      movie = %Movie{
        id: 1,
        title: "Dune: Part Two",
        slug: "dune-part-two",
        tmdb_metadata: nil,
        metadata: omdb_metadata
      }

      {:ok, movie: movie, city: city, venues_with_info: venues_with_info}
    end

    test "includes OMDb poster image", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["image"] == "https://example.com/poster.jpg"
    end

    test "includes release date from OMDb", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["datePublished"] == "01 Mar 2024"
    end

    test "includes runtime parsed from OMDb", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["duration"] == "PT2H46M"
    end

    test "includes genres parsed from OMDb", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["genre"] == ["Sci-Fi", "Adventure", "Drama"]
    end

    test "includes director as Person from OMDb", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["director"]["@type"] == "Person"
      assert schema["director"]["name"] == "Denis Villeneuve"
    end

    test "includes actors parsed from OMDb", %{
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

    test "includes IMDb rating from OMDb", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["aggregateRating"]["@type"] == "AggregateRating"
      assert schema["aggregateRating"]["ratingValue"] == 8.5
      assert schema["aggregateRating"]["ratingCount"] == 123_456
      assert schema["aggregateRating"]["bestRating"] == 10
      assert schema["aggregateRating"]["worstRating"] == 1
    end

    test "handles N/A values gracefully" do
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

      omdb_metadata = %{
        "Poster" => "N/A",
        "Released" => "N/A",
        "Runtime" => "N/A",
        "Genre" => "N/A",
        "Director" => "N/A",
        "Actors" => "N/A",
        "imdbRating" => "N/A",
        "imdbVotes" => "N/A"
      }

      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_metadata: nil,
        metadata: omdb_metadata
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      # Should use placeholder image when poster is N/A
      assert String.contains?(schema["image"], "placehold.co")

      # Should not include fields with N/A values
      refute Map.has_key?(schema, "datePublished")
      refute Map.has_key?(schema, "genre")
      refute Map.has_key?(schema, "director")
      refute Map.has_key?(schema, "actor")
      refute Map.has_key?(schema, "duration")
      refute Map.has_key?(schema, "aggregateRating")
    end
  end

  describe "TMDb metadata takes precedence over OMDb" do
    test "TMDb metadata is preferred when both exist" do
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

      omdb_metadata = %{
        "Poster" => "https://example.com/omdb-poster.jpg",
        "Released" => "15 Mar 2024",
        "Runtime" => "180 min"
      }

      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_metadata: tmdb_metadata,
        metadata: omdb_metadata
      }

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      # TMDb values should be used
      assert schema["image"] == "https://image.tmdb.org/t/p/w500/tmdb-poster.jpg"
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

  describe "screening events ItemList" do
    setup do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue1 = %Venue{
        id: 1,
        name: "Cinema City",
        address: "Main Street 123",
        slug: "cinema-city",
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

      movie = %Movie{
        id: 1,
        title: "Dune: Part Two",
        slug: "dune-part-two",
        tmdb_metadata: nil,
        metadata: nil
      }

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

      {:ok, movie: movie, city: city, venues_with_info: venues_with_info}
    end

    test "includes potentialAction with ItemList of screenings", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      assert schema["potentialAction"]["@type"] == "ItemList"
      assert schema["potentialAction"]["name"] == "Screenings of Dune: Part Two in Kraków"
      assert schema["potentialAction"]["numberOfItems"] == 2
    end

    test "includes ListItem for each venue with position", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      items = schema["potentialAction"]["itemListElement"]
      assert length(items) == 2

      first_item = Enum.at(items, 0)
      assert first_item["@type"] == "ListItem"
      assert first_item["position"] == 1
      assert first_item["item"]["@type"] == "Place"
      assert first_item["item"]["name"] == "Cinema City"
    end

    test "includes venue address in ListItem", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["potentialAction"]["itemListElement"], 0)
      address = first_item["item"]["address"]

      assert address["@type"] == "PostalAddress"
      assert address["streetAddress"] == "Main Street 123"
      assert address["addressLocality"] == "Kraków"
      assert address["addressCountry"] == "PL"
    end

    test "includes venue URL and activity URL in ListItem", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["potentialAction"]["itemListElement"], 0)

      assert String.contains?(first_item["item"]["@id"], "/c/krakow/venues/cinema-city")
      assert String.contains?(first_item["item"]["url"], "/activities/dune-part-two-cinema-city")
    end

    test "includes showtime count description", %{
      movie: movie,
      city: city,
      venues_with_info: venues_with_info
    } do
      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["potentialAction"]["itemListElement"], 0)
      assert first_item["item"]["description"] == "15 showtimes available"

      second_item = Enum.at(schema["potentialAction"]["itemListElement"], 1)
      assert second_item["item"]["description"] == "8 showtimes available"
    end

    test "uses singular 'showtime' for single screening" do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Test Cinema",
        slug: "test-cinema",
        city_ref: city
      }

      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_metadata: nil,
        metadata: nil
      }

      venues_with_info = [
        {venue, %{count: 1, slug: "test-slug", date_range: "Mar 1", formats: []}}
      ]

      schema = MovieSchema.build_movie_schema(movie, city, venues_with_info)

      first_item = Enum.at(schema["potentialAction"]["itemListElement"], 0)
      assert first_item["item"]["description"] == "1 showtime available"
    end

    test "does not include potentialAction when no venues" do
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

      refute Map.has_key?(schema, "potentialAction")
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
