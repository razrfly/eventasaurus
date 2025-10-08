defmodule EventasaurusDiscovery.Sources.QuestionOne.TransformerTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.QuestionOne.Transformer

  describe "transform_event/1" do
    test "transforms venue data to unified format" do
      venue_data = %{
        title: "The Red Lion",
        raw_title: "PUB QUIZ – The Red Lion",
        address: "123 High Street, London, SW1A 1AA",
        time_text: "Wednesdays at 8pm",
        fee_text: "£2 per person",
        phone: "020 1234 5678",
        website: "https://redlion.com",
        description: "Weekly trivia night with great prizes",
        hero_image_url: "https://questionone.com/wp-content/uploads/image.jpg",
        source_url: "https://questionone.com/venues/red-lion"
      }

      transformed = Transformer.transform_event(venue_data)

      # Check required fields
      assert transformed.external_id =~ "question_one_"
      assert transformed.title == "Trivia Night at The Red Lion"
      assert %DateTime{} = transformed.starts_at
      assert %DateTime{} = transformed.ends_at

      # Check venue data
      assert transformed.venue_data.name == "The Red Lion"
      assert transformed.venue_data.address == "123 High Street, London, SW1A 1AA"
      assert transformed.venue_data.country == "United Kingdom"
      # GPS coordinates should be nil (VenueProcessor geocodes)
      assert is_nil(transformed.venue_data.latitude)
      assert is_nil(transformed.venue_data.longitude)
      assert transformed.venue_data.phone == "020 1234 5678"
      assert transformed.venue_data.website == "https://redlion.com"

      # Check pricing
      assert transformed.is_free == false
      assert transformed.is_ticketed == true
      assert transformed.currency == "GBP"

      # Check metadata
      assert transformed.category == "trivia"
      assert transformed.metadata.recurring == true
      assert transformed.metadata.frequency == "weekly"
      assert transformed.metadata.time_text == "Wednesdays at 8pm"

      # Check optional fields
      assert transformed.description == "Weekly trivia night with great prizes"
      assert transformed.image_url == "https://questionone.com/wp-content/uploads/image.jpg"
      assert transformed.source_url == "https://questionone.com/venues/red-lion"
    end

    test "handles free events correctly" do
      venue_data = %{
        title: "The Crown",
        raw_title: "PUB QUIZ: The Crown",
        address: "456 Main St, Manchester, M1 1AA",
        time_text: "Mondays at 7pm",
        fee_text: "Free entry",
        phone: nil,
        website: nil,
        description: nil,
        hero_image_url: nil,
        source_url: "https://questionone.com/venues/crown"
      }

      transformed = Transformer.transform_event(venue_data)

      assert transformed.is_free == true
      assert transformed.is_ticketed == false
      assert is_nil(transformed.min_price)
    end

    test "handles missing optional fields" do
      venue_data = %{
        title: "The Ship",
        raw_title: "The Ship",
        address: "789 Harbor Rd, Bristol, BS1 1AA",
        time_text: "Thursdays at 8:30pm",
        fee_text: nil,
        phone: nil,
        website: nil,
        description: nil,
        hero_image_url: nil,
        source_url: "https://questionone.com/venues/ship"
      }

      transformed = Transformer.transform_event(venue_data)

      assert transformed.title == "Trivia Night at The Ship"
      assert transformed.venue_data.name == "The Ship"
      # Should default to free when no fee_text
      assert transformed.is_free == true
      assert is_nil(transformed.venue_data.phone)
      assert is_nil(transformed.venue_data.website)
      assert is_nil(transformed.description)
      assert is_nil(transformed.image_url)
    end

    test "decodes HTML entities in venue titles and descriptions" do
      venue_data = %{
        title: "Royal Oak, Twickenham &#8211; Every Thursday",
        raw_title: "PUB QUIZ &#8211; Royal Oak, Twickenham &#8211; Every Thursday",
        address: "13 Richmond Road, Twickenham England TW1 3AB, United Kingdom",
        time_text: "Thursdays at 6:30pm",
        fee_text: "£2 per person",
        phone: nil,
        website: nil,
        description: "Join us for trivia &#038; prizes every Thursday!",
        hero_image_url: nil,
        source_url: "https://questionone.com/venues/royal-oak-twickenham"
      }

      transformed = Transformer.transform_event(venue_data)

      # HTML entities should be decoded
      assert transformed.title == "Trivia Night at Royal Oak, Twickenham – Every Thursday"
      assert transformed.venue_data.name == "Royal Oak, Twickenham – Every Thursday"
      assert transformed.venue_data.metadata.raw_title == "PUB QUIZ – Royal Oak, Twickenham – Every Thursday"
      assert transformed.description == "Join us for trivia & prizes every Thursday!"
    end
  end
end
