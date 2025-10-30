defmodule EventasaurusDiscovery.Validation.VenueNameValidatorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Validation.VenueNameValidator

  doctest VenueNameValidator

  describe "validate_against_geocoded/2" do
    test "returns high similarity when names match well" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "La Lucy Cafe"}
        }
      }

      assert {:ok, :high_similarity, similarity} =
               VenueNameValidator.validate_against_geocoded("La Lucy", metadata)

      assert similarity >= 0.7
    end

    test "returns moderate similarity when names differ somewhat" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Madison Square Garden"}
        }
      }

      assert {:warning, :moderate_similarity, similarity} =
               VenueNameValidator.validate_against_geocoded("MSG", metadata)

      assert similarity >= 0.3 and similarity < 0.7
    end

    test "returns low similarity when names are very different" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Central Park Museum"}
        }
      }

      assert {:error, :low_similarity, similarity} =
               VenueNameValidator.validate_against_geocoded(
                 "00000",
                 metadata
               )

      assert similarity < 0.3
    end

    test "returns error when no geocoded name available" do
      metadata = %{"geocoding_metadata" => %{"provider" => "mapbox"}}

      assert {:error, :no_geocoded_name} =
               VenueNameValidator.validate_against_geocoded("Some Venue", metadata)
    end

    test "returns error when metadata is missing" do
      assert {:error, :no_geocoded_name} =
               VenueNameValidator.validate_against_geocoded("Some Venue", %{})
    end

    test "handles scraped names with extra words" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Central Park"}
        }
      }

      assert {:ok, :high_similarity, similarity} =
               VenueNameValidator.validate_against_geocoded("Central Park Zoo", metadata)

      assert similarity >= 0.7
    end

    test "is case insensitive" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "The Royal Theater"}
        }
      }

      assert {:ok, :high_similarity, _similarity} =
               VenueNameValidator.validate_against_geocoded("THE ROYAL THEATER", metadata)
    end

    test "handles punctuation differences" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "O'Reilly's Pub"}
        }
      }

      assert {:ok, :high_similarity, _similarity} =
               VenueNameValidator.validate_against_geocoded("OReillys Pub", metadata)
    end
  end

  describe "extract_geocoded_name/1" do
    test "extracts name from HERE provider (title field)" do
      metadata = %{
        "geocoding_metadata" => %{
          "provider" => "here",
          "raw_response" => %{"title" => "La Lucy"}
        }
      }

      assert "La Lucy" = VenueNameValidator.extract_geocoded_name(metadata)
    end

    test "extracts name from Google Places provider (name field)" do
      metadata = %{
        "geocoding_metadata" => %{
          "provider" => "google_places",
          "raw_response" => %{"name" => "Central Park"}
        }
      }

      assert "Central Park" = VenueNameValidator.extract_geocoded_name(metadata)
    end

    test "extracts name from Foursquare provider (name field)" do
      metadata = %{
        "geocoding_metadata" => %{
          "provider" => "foursquare",
          "raw_response" => %{"name" => "Brooklyn Museum"}
        }
      }

      assert "Brooklyn Museum" = VenueNameValidator.extract_geocoded_name(metadata)
    end

    test "handles atom keys in metadata" do
      metadata = %{
        geocoding_metadata: %{
          provider: "here",
          raw_response: %{title: "Warsaw Opera"}
        }
      }

      assert "Warsaw Opera" = VenueNameValidator.extract_geocoded_name(metadata)
    end

    test "returns nil when geocoding_metadata is missing" do
      assert is_nil(VenueNameValidator.extract_geocoded_name(%{}))
    end

    test "returns nil when raw_response is missing" do
      metadata = %{"geocoding_metadata" => %{"provider" => "here"}}
      assert is_nil(VenueNameValidator.extract_geocoded_name(metadata))
    end

    test "returns nil when neither title nor name fields exist" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"address" => "123 Main St"}
        }
      }

      assert is_nil(VenueNameValidator.extract_geocoded_name(metadata))
    end

    test "returns nil for empty string name" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => ""}
        }
      }

      assert is_nil(VenueNameValidator.extract_geocoded_name(metadata))
    end

    test "prefers title over name when both exist" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{
            "title" => "HERE Name",
            "name" => "Generic Name"
          }
        }
      }

      assert "HERE Name" = VenueNameValidator.extract_geocoded_name(metadata)
    end

    test "returns nil for non-map input" do
      assert is_nil(VenueNameValidator.extract_geocoded_name(nil))
      assert is_nil(VenueNameValidator.extract_geocoded_name("string"))
      assert is_nil(VenueNameValidator.extract_geocoded_name(123))
    end
  end

  describe "calculate_similarity/2" do
    test "returns 1.0 for identical strings" do
      similarity = VenueNameValidator.calculate_similarity("Central Park", "Central Park")
      assert similarity == 1.0
    end

    test "returns high similarity for similar strings" do
      similarity = VenueNameValidator.calculate_similarity("La Lucy", "La Lucy Cafe")
      assert similarity > 0.8
    end

    test "returns low similarity for very different strings" do
      similarity =
        VenueNameValidator.calculate_similarity(
          "00000",
          "Madison Square Garden"
        )

      assert similarity < 0.3
    end

    test "returns moderate similarity for abbreviations" do
      similarity = VenueNameValidator.calculate_similarity("MSG", "Madison Square Garden")
      # Abbreviations typically score in the moderate range
      assert similarity > 0.3 and similarity < 0.7
    end

    test "is case insensitive" do
      similarity1 =
        VenueNameValidator.calculate_similarity("Central Park", "central park")

      similarity2 = VenueNameValidator.calculate_similarity("CENTRAL PARK", "central park")

      assert similarity1 == 1.0
      assert similarity2 == 1.0
    end

    test "handles punctuation removal" do
      similarity =
        VenueNameValidator.calculate_similarity("O'Reilly's Pub", "OReillys Pub")

      assert similarity > 0.9
    end

    test "handles extra whitespace" do
      similarity =
        VenueNameValidator.calculate_similarity("  Central   Park  ", "Central Park")

      assert similarity > 0.95
    end

    test "handles non-ASCII characters" do
      similarity = VenueNameValidator.calculate_similarity("Café Nowy", "Cafe Nowy")
      assert similarity > 0.8
    end

    test "handles Polish characters" do
      similarity =
        VenueNameValidator.calculate_similarity("Teatr Wielki", "Teatr Wielki")

      assert similarity == 1.0
    end
  end

  describe "choose_name/2" do
    test "returns scraped name when similarity is high" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "La Lucy"}
        }
      }

      assert {:ok, "La Lucy Cafe", :scraped_validated} =
               VenueNameValidator.choose_name("La Lucy Cafe", metadata)
    end

    test "returns geocoded name when similarity is moderate" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Madison Square Garden"}
        }
      }

      assert {:ok, "Madison Square Garden", :geocoded_moderate_diff, score} =
               VenueNameValidator.choose_name("MSG", metadata)

      assert score >= 0.3 and score < 0.7
    end

    test "returns geocoded name when similarity is low" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Central Park Museum"}
        }
      }

      assert {:ok, "Central Park Museum", :geocoded_low_similarity, score} =
               VenueNameValidator.choose_name("00000", metadata)

      assert score < 0.3
    end

    test "returns scraped name with warning when no geocoded name available" do
      metadata = %{}

      assert {:warning, "Some Venue", :no_geocoded_name} =
               VenueNameValidator.choose_name("Some Venue", metadata)
    end

    test "falls back to scraped name when geocoded name is missing but validation fails" do
      # This tests the edge case where metadata exists but has no usable name
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"address" => "123 Main St"}
        }
      }

      assert {:warning, "Test Venue", :no_geocoded_name} =
               VenueNameValidator.choose_name("Test Venue", metadata)
    end
  end

  describe "edge cases and error handling" do
    test "handles nil metadata gracefully" do
      assert {:error, :no_geocoded_name} =
               VenueNameValidator.validate_against_geocoded("Test Venue", nil)
    end

    test "handles empty scraped name" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Real Venue"}
        }
      }

      assert {:error, :low_similarity, _} =
               VenueNameValidator.validate_against_geocoded("", metadata)
    end

    test "handles very long venue names" do
      long_name = String.duplicate("A", 200)

      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => long_name}
        }
      }

      assert {:ok, :high_similarity, _} =
               VenueNameValidator.validate_against_geocoded(long_name, metadata)
    end

    test "handles special characters in venue names" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Café & Restaurant «Le Paris»"}
        }
      }

      assert {:ok, :high_similarity, _} =
               VenueNameValidator.validate_against_geocoded(
                 "Cafe & Restaurant Le Paris",
                 metadata
               )
    end

    test "handles numeric venue names" do
      metadata = %{
        "geocoding_metadata" => %{
          "raw_response" => %{"title" => "Studio 54"}
        }
      }

      assert {:ok, :high_similarity, _} =
               VenueNameValidator.validate_against_geocoded("Studio 54", metadata)
    end
  end
end
