defmodule EventasaurusDiscovery.Sources.Inquizition.Extractors.VenueExtractorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Inquizition.Extractors.VenueExtractor

  describe "extract_venues/1" do
    test "extracts valid venues with all required fields" do
      response = %{
        "stores" => [
          %{
            "storeid" => "97520779",
            "name" => "Andrea Ludgate Hill",
            "data" => %{
              "address" => "47 Ludgate Hill\r\nLondon\r\nEC4M 7JZ",
              "description" => "Tuesdays, 6.30pm",
              "map_lat" => "51.513898",
              "map_lng" => "-0.1026125",
              "phone" => "020 7236 1942",
              "website" => "https://andreabars.com/bookings/",
              "email" => "ludgatehill@andreabars.com"
            },
            "filters" => ["Tuesday"],
            "timezone" => "Europe/London",
            "country" => "GB"
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.venue_id == "97520779"
      assert venue.name == "Andrea Ludgate Hill"
      assert venue.address == "47 Ludgate Hill\nLondon\nEC4M 7JZ"
      assert venue.latitude == 51.513898
      assert venue.longitude == -0.1026125
      assert venue.phone == "020 7236 1942"
      assert venue.website == "https://andreabars.com/bookings/"
      assert venue.email == "ludgatehill@andreabars.com"
      assert venue.schedule_text == "Tuesdays, 6.30pm"
      assert venue.day_filters == ["Tuesday"]
      assert venue.timezone == "Europe/London"
      assert venue.country == "GB"
    end

    test "extracts multiple venues" do
      response = %{
        "stores" => [
          %{
            "storeid" => "1",
            "name" => "Venue One",
            "data" => %{
              "address" => "Address 1",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          },
          %{
            "storeid" => "2",
            "name" => "Venue Two",
            "data" => %{
              "address" => "Address 2",
              "map_lat" => "51.6",
              "map_lng" => "-0.2"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 2
      assert Enum.at(venues, 0).venue_id == "1"
      assert Enum.at(venues, 1).venue_id == "2"
    end

    test "handles empty stores array" do
      response = %{"stores" => []}

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "returns error for missing stores key" do
      response = %{"other_key" => "value"}

      result = VenueExtractor.extract_venues(response)

      assert result == {:error, :missing_stores_key}
    end

    test "returns error for non-map response" do
      result = VenueExtractor.extract_venues("not a map")

      assert result == {:error, :missing_stores_key}
    end

    test "filters out venue with missing storeid" do
      response = %{
        "stores" => [
          %{
            "name" => "No ID Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with empty storeid" do
      response = %{
        "stores" => [
          %{
            "storeid" => "",
            "name" => "Empty ID Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with missing name" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with empty name" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "   ",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with missing address" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "No Address Venue",
            "data" => %{
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with empty address" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Empty Address Venue",
            "data" => %{
              "address" => "",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with missing latitude" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "No Lat Venue",
            "data" => %{
              "address" => "Address",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with invalid latitude" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Invalid Lat Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "not a number",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with missing longitude" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "No Lng Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "filters out venue with invalid longitude" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Invalid Lng Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "not a number"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "handles venue with missing data object" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "No Data Venue"
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert venues == []
    end

    test "parses coordinates as floats from strings" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.513898",
              "map_lng" => "-0.1026125"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.latitude == 51.513898
      assert venue.longitude == -0.1026125
    end

    test "parses coordinates from numeric values" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => 51.513898,
              "map_lng" => -0.1026125
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.latitude == 51.513898
      assert venue.longitude == -0.1026125
    end

    test "parses coordinates from integers" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => 51,
              "map_lng" => -1
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.latitude == 51.0
      assert venue.longitude == -1.0
    end

    test "normalizes address line breaks" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Line 1\r\nLine 2\r\nLine 3",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.address == "Line 1\nLine 2\nLine 3"
    end

    test "handles optional phone field - present" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1",
              "phone" => "020 7236 1942"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.phone == "020 7236 1942"
    end

    test "handles optional phone field - missing" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.phone == nil
    end

    test "handles optional phone field - empty string" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1",
              "phone" => ""
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.phone == nil
    end

    test "handles optional website field - present" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1",
              "website" => "https://example.com"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.website == "https://example.com"
    end

    test "handles optional website field - missing" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.website == nil
    end

    test "handles optional email field - present" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1",
              "email" => "venue@example.com"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.email == "venue@example.com"
    end

    test "handles optional email field - missing" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.email == nil
    end

    test "handles optional schedule_text field - present" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1",
              "description" => "Tuesdays, 6.30pm"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.schedule_text == "Tuesdays, 6.30pm"
    end

    test "handles optional schedule_text field - missing" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.schedule_text == nil
    end

    test "parses day_filters - single day" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            },
            "filters" => ["Tuesday"]
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.day_filters == ["Tuesday"]
    end

    test "parses day_filters - multiple days" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            },
            "filters" => ["Tuesday", "Thursday"]
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.day_filters == ["Tuesday", "Thursday"]
    end

    test "parses day_filters - empty array" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            },
            "filters" => []
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.day_filters == []
    end

    test "parses day_filters - missing" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.day_filters == []
    end

    test "filters out nil and empty string from day_filters" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            },
            "filters" => ["Tuesday", nil, "", "Thursday", "  "]
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.day_filters == ["Tuesday", "Thursday"]
    end

    test "defaults timezone to Europe/London when missing" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.timezone == "Europe/London"
    end

    test "uses provided timezone when present" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            },
            "timezone" => "America/New_York"
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.timezone == "America/New_York"
    end

    test "defaults country to GB when missing" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.country == "GB"
    end

    test "uses provided country when present" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "Venue",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            },
            "country" => "US"
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.country == "US"
    end

    test "trims whitespace from name" do
      response = %{
        "stores" => [
          %{
            "storeid" => "123",
            "name" => "  Venue Name  ",
            "data" => %{
              "address" => "Address",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 1
      venue = List.first(venues)

      assert venue.name == "Venue Name"
    end

    test "mixed valid and invalid venues - extracts only valid ones" do
      response = %{
        "stores" => [
          # Valid venue
          %{
            "storeid" => "1",
            "name" => "Valid Venue",
            "data" => %{
              "address" => "Address 1",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          },
          # Missing storeid
          %{
            "name" => "Invalid - No ID",
            "data" => %{
              "address" => "Address 2",
              "map_lat" => "51.5",
              "map_lng" => "-0.1"
            }
          },
          # Valid venue
          %{
            "storeid" => "2",
            "name" => "Another Valid Venue",
            "data" => %{
              "address" => "Address 3",
              "map_lat" => "51.6",
              "map_lng" => "-0.2"
            }
          },
          # Invalid coordinates
          %{
            "storeid" => "3",
            "name" => "Invalid - Bad Coords",
            "data" => %{
              "address" => "Address 4",
              "map_lat" => "not a number",
              "map_lng" => "-0.3"
            }
          }
        ]
      }

      venues = VenueExtractor.extract_venues(response)

      assert length(venues) == 2
      assert Enum.at(venues, 0).venue_id == "1"
      assert Enum.at(venues, 1).venue_id == "2"
    end
  end
end
