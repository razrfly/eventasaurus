defmodule EventasaurusWeb.JsonLd.HelpersTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.JsonLd.Helpers

  describe "maybe_add/3" do
    test "adds field when value is present" do
      result = Helpers.maybe_add(%{}, "name", "Test")
      assert result == %{"name" => "Test"}
    end

    test "does not add field when value is nil" do
      result = Helpers.maybe_add(%{"existing" => "value"}, "name", nil)
      assert result == %{"existing" => "value"}
    end

    test "does not add field when value is empty list" do
      result = Helpers.maybe_add(%{}, "tags", [])
      assert result == %{}
    end

    test "does not add field when value is empty string" do
      result = Helpers.maybe_add(%{}, "name", "")
      assert result == %{}
    end

    test "preserves existing fields" do
      result = Helpers.maybe_add(%{"existing" => "value"}, "name", "Test")
      assert result == %{"existing" => "value", "name" => "Test"}
    end
  end

  describe "maybe_add_if_missing/3" do
    test "adds field when key doesn't exist" do
      result = Helpers.maybe_add_if_missing(%{}, "name", "Fallback")
      assert result == %{"name" => "Fallback"}
    end

    test "does not overwrite existing field" do
      result = Helpers.maybe_add_if_missing(%{"name" => "Primary"}, "name", "Fallback")
      assert result == %{"name" => "Primary"}
    end

    test "does not add field when value is nil" do
      result = Helpers.maybe_add_if_missing(%{}, "name", nil)
      assert result == %{}
    end

    test "does not add field when value is empty list" do
      result = Helpers.maybe_add_if_missing(%{}, "tags", [])
      assert result == %{}
    end

    test "does not add field when value is empty string" do
      result = Helpers.maybe_add_if_missing(%{}, "name", "")
      assert result == %{}
    end

    test "does not add field when value is N/A" do
      result = Helpers.maybe_add_if_missing(%{}, "name", "N/A")
      assert result == %{}
    end
  end

  describe "get_base_url/0" do
    test "returns a valid URL string" do
      result = Helpers.get_base_url()
      assert is_binary(result)
      assert String.starts_with?(result, "http")
    end
  end

  describe "build_url/1" do
    test "builds full URL from path" do
      result = Helpers.build_url("/movies/test-12345")
      assert String.ends_with?(result, "/movies/test-12345")
      assert String.starts_with?(result, "http")
    end

    test "handles paths with multiple segments" do
      result = Helpers.build_url("/c/krakow/movies/inception")
      assert String.contains?(result, "/c/krakow/movies/inception")
    end
  end

  describe "add_geo_coordinates/2" do
    test "adds geo coordinates when both lat and lng are present" do
      entity = %{latitude: 50.06, longitude: 19.94}
      result = Helpers.add_geo_coordinates(%{"name" => "Place"}, entity)

      assert result["geo"]["@type"] == "GeoCoordinates"
      assert result["geo"]["latitude"] == 50.06
      assert result["geo"]["longitude"] == 19.94
    end

    test "does not add geo when latitude is nil" do
      entity = %{latitude: nil, longitude: 19.94}
      result = Helpers.add_geo_coordinates(%{"name" => "Place"}, entity)

      refute Map.has_key?(result, "geo")
    end

    test "does not add geo when longitude is nil" do
      entity = %{latitude: 50.06, longitude: nil}
      result = Helpers.add_geo_coordinates(%{"name" => "Place"}, entity)

      refute Map.has_key?(result, "geo")
    end

    test "does not add geo when both are nil" do
      entity = %{latitude: nil, longitude: nil}
      result = Helpers.add_geo_coordinates(%{"name" => "Place"}, entity)

      refute Map.has_key?(result, "geo")
    end

    test "works with string keys in entity" do
      entity = %{"latitude" => 50.06, "longitude" => 19.94}
      result = Helpers.add_geo_coordinates(%{}, entity)

      assert result["geo"]["latitude"] == 50.06
    end
  end

  describe "pluralize/2" do
    test "returns singular for count of 1" do
      assert Helpers.pluralize("movie", 1) == "movie"
      assert Helpers.pluralize("city", 1) == "city"
      assert Helpers.pluralize("cinema", 1) == "cinema"
    end

    test "pluralizes city to cities" do
      assert Helpers.pluralize("city", 2) == "cities"
      assert Helpers.pluralize("city", 10) == "cities"
    end

    test "pluralizes category to categories" do
      assert Helpers.pluralize("category", 3) == "categories"
    end

    test "adds s for regular words" do
      assert Helpers.pluralize("movie", 2) == "movies"
      assert Helpers.pluralize("cinema", 5) == "cinemas"
      assert Helpers.pluralize("screening", 100) == "screenings"
    end

    test "handles zero count as plural" do
      assert Helpers.pluralize("movie", 0) == "movies"
    end
  end

  describe "cdn_url/1" do
    test "wraps URL with CDN" do
      result = Helpers.cdn_url("https://image.tmdb.org/t/p/w500/poster.jpg")
      assert is_binary(result)
      # CDN returns a URL (may be same URL in test env or wrapped in production)
      assert String.contains?(result, "poster.jpg")
    end

    test "returns nil for nil input" do
      assert Helpers.cdn_url(nil) == nil
    end

    test "returns nil for empty string" do
      assert Helpers.cdn_url("") == nil
    end
  end

  describe "format_iso_duration/1" do
    test "formats hours and minutes" do
      assert Helpers.format_iso_duration(142) == "PT2H22M"
      assert Helpers.format_iso_duration(90) == "PT1H30M"
    end

    test "formats hours only" do
      assert Helpers.format_iso_duration(60) == "PT1H"
      assert Helpers.format_iso_duration(120) == "PT2H"
    end

    test "formats minutes only" do
      assert Helpers.format_iso_duration(45) == "PT45M"
      assert Helpers.format_iso_duration(30) == "PT30M"
    end

    test "returns nil for nil input" do
      assert Helpers.format_iso_duration(nil) == nil
    end

    test "returns nil for zero" do
      assert Helpers.format_iso_duration(0) == nil
    end

    test "returns nil for negative values" do
      assert Helpers.format_iso_duration(-10) == nil
    end
  end

  describe "extract_genres/1" do
    test "extracts genre names from TMDb format" do
      genres = [%{"name" => "Action"}, %{"name" => "Drama"}]
      assert Helpers.extract_genres(genres) == ["Action", "Drama"]
    end

    test "returns nil for nil input" do
      assert Helpers.extract_genres(nil) == nil
    end

    test "returns nil for empty list" do
      assert Helpers.extract_genres([]) == nil
    end

    test "handles single genre" do
      genres = [%{"name" => "Comedy"}]
      assert Helpers.extract_genres(genres) == ["Comedy"]
    end
  end

  describe "extract_directors/1" do
    test "extracts single director as map" do
      credits = %{
        "crew" => [
          %{"job" => "Director", "name" => "Christopher Nolan"},
          %{"job" => "Producer", "name" => "Emma Thomas"}
        ]
      }

      result = Helpers.extract_directors(credits)
      assert result["@type"] == "Person"
      assert result["name"] == "Christopher Nolan"
    end

    test "extracts multiple directors as list" do
      credits = %{
        "crew" => [
          %{"job" => "Director", "name" => "The Wachowskis"},
          %{"job" => "Director", "name" => "Lana Wachowski"}
        ]
      }

      result = Helpers.extract_directors(credits)
      assert is_list(result)
      assert length(result) == 2
    end

    test "returns nil for nil input" do
      assert Helpers.extract_directors(nil) == nil
    end

    test "returns nil when no directors in crew" do
      credits = %{
        "crew" => [
          %{"job" => "Producer", "name" => "Emma Thomas"}
        ]
      }

      assert Helpers.extract_directors(credits) == nil
    end

    test "returns nil when crew is nil" do
      credits = %{"cast" => []}
      assert Helpers.extract_directors(credits) == nil
    end
  end

  describe "extract_actors/1" do
    test "extracts actors as Person list" do
      credits = %{
        "cast" => [
          %{"name" => "Leonardo DiCaprio"},
          %{"name" => "Marion Cotillard"}
        ]
      }

      result = Helpers.extract_actors(credits)
      assert is_list(result)
      assert length(result) == 2
      assert Enum.at(result, 0)["@type"] == "Person"
      assert Enum.at(result, 0)["name"] == "Leonardo DiCaprio"
    end

    test "limits to 10 actors by default" do
      credits = %{
        "cast" => Enum.map(1..15, fn i -> %{"name" => "Actor #{i}"} end)
      }

      result = Helpers.extract_actors(credits)
      assert length(result) == 10
    end

    test "respects custom limit" do
      credits = %{
        "cast" => Enum.map(1..15, fn i -> %{"name" => "Actor #{i}"} end)
      }

      result = Helpers.extract_actors(credits, 5)
      assert length(result) == 5
    end

    test "returns nil for nil input" do
      assert Helpers.extract_actors(nil) == nil
    end

    test "returns nil for empty cast" do
      credits = %{"cast" => []}
      assert Helpers.extract_actors(credits) == nil
    end

    test "returns nil when cast is nil" do
      credits = %{"crew" => []}
      assert Helpers.extract_actors(credits) == nil
    end
  end

  describe "build_aggregate_rating/1" do
    test "builds rating from TMDb metadata" do
      metadata = %{"vote_average" => 8.2, "vote_count" => 5000}
      result = Helpers.build_aggregate_rating(metadata)

      assert result["@type"] == "AggregateRating"
      assert result["ratingValue"] == 8.2
      assert result["ratingCount"] == 5000
      assert result["bestRating"] == 10
      assert result["worstRating"] == 0
    end

    test "returns nil for nil input" do
      assert Helpers.build_aggregate_rating(nil) == nil
    end

    test "returns nil when vote_average is missing" do
      metadata = %{"vote_count" => 5000}
      assert Helpers.build_aggregate_rating(metadata) == nil
    end

    test "returns nil when vote_count is missing" do
      metadata = %{"vote_average" => 8.2}
      assert Helpers.build_aggregate_rating(metadata) == nil
    end

    test "returns nil when vote_count is zero" do
      metadata = %{"vote_average" => 8.2, "vote_count" => 0}
      assert Helpers.build_aggregate_rating(metadata) == nil
    end
  end

  describe "build_postal_address/2" do
    test "builds address from venue and city" do
      venue = %{address: "123 Main St"}
      city = %{name: "Krakow", country: %{code: "PL"}}

      result = Helpers.build_postal_address(venue, city)

      assert result["@type"] == "PostalAddress"
      assert result["streetAddress"] == "123 Main St"
      assert result["addressLocality"] == "Krakow"
      assert result["addressCountry"] == "PL"
    end

    test "uses country_code if country struct not present" do
      venue = %{address: "456 Oak Ave"}
      city = %{name: "Warsaw", country_code: "PL"}

      result = Helpers.build_postal_address(venue, city)

      assert result["addressCountry"] == "PL"
    end

    test "defaults to US if no country info" do
      venue = %{address: "789 Elm St"}
      city = %{name: "Unknown City"}

      result = Helpers.build_postal_address(venue, city)

      assert result["addressCountry"] == "US"
    end

    test "handles nil address" do
      venue = %{address: nil}
      city = %{name: "Krakow", country: %{code: "PL"}}

      result = Helpers.build_postal_address(venue, city)

      assert result["streetAddress"] == ""
    end
  end
end
