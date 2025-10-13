defmodule EventasaurusWeb.JsonLd.BreadcrumbListSchemaTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.JsonLd.BreadcrumbListSchema

  describe "generate/1" do
    test "generates valid BreadcrumbList JSON-LD" do
      breadcrumbs = [
        %{name: "Home", url: "https://eventasaurus.com"},
        %{name: "Kraków", url: "https://eventasaurus.com/cities/krakow"},
        %{
          name: "Arctic Monkeys",
          url: "https://eventasaurus.com/activities/arctic-monkeys-krakow"
        }
      ]

      json = BreadcrumbListSchema.generate(breadcrumbs)
      schema = Jason.decode!(json)

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "BreadcrumbList"
      assert length(schema["itemListElement"]) == 3

      # Check first item
      first_item = Enum.at(schema["itemListElement"], 0)
      assert first_item["@type"] == "ListItem"
      assert first_item["position"] == 1
      assert first_item["name"] == "Home"
      assert first_item["item"] == "https://eventasaurus.com"

      # Check last item
      last_item = Enum.at(schema["itemListElement"], 2)
      assert last_item["position"] == 3
      assert last_item["name"] == "Arctic Monkeys"
      assert String.contains?(last_item["item"], "arctic-monkeys-krakow")
    end

    test "handles single breadcrumb" do
      breadcrumbs = [
        %{name: "Home", url: "https://eventasaurus.com"}
      ]

      json = BreadcrumbListSchema.generate(breadcrumbs)
      schema = Jason.decode!(json)

      assert length(schema["itemListElement"]) == 1
      item = Enum.at(schema["itemListElement"], 0)
      assert item["position"] == 1
    end

    test "handles empty breadcrumb list" do
      breadcrumbs = []

      json = BreadcrumbListSchema.generate(breadcrumbs)
      schema = Jason.decode!(json)

      assert schema["itemListElement"] == []
    end
  end

  describe "build_breadcrumb_schema/1" do
    test "returns map structure without encoding" do
      breadcrumbs = [
        %{name: "Home", url: "https://eventasaurus.com"},
        %{name: "Test", url: "https://eventasaurus.com/test"}
      ]

      schema = BreadcrumbListSchema.build_breadcrumb_schema(breadcrumbs)

      assert is_map(schema)
      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "BreadcrumbList"
      assert is_list(schema["itemListElement"])
    end
  end

  describe "build_event_breadcrumbs/2" do
    test "builds breadcrumbs for event with venue and city" do
      event = %{
        title: "Arctic Monkeys Concert",
        slug: "arctic-monkeys-krakow-241215",
        venue: %{
          city_ref: %{
            name: "Kraków",
            slug: "krakow"
          }
        }
      }

      base_url = "https://eventasaurus.com"
      breadcrumbs = BreadcrumbListSchema.build_event_breadcrumbs(event, base_url)

      assert length(breadcrumbs) == 3
      assert Enum.at(breadcrumbs, 0) == %{name: "Home", url: "https://eventasaurus.com"}

      assert Enum.at(breadcrumbs, 1) == %{
               name: "Kraków",
               url: "https://eventasaurus.com/cities/krakow"
             }

      assert Enum.at(breadcrumbs, 2) == %{
               name: "Arctic Monkeys Concert",
               url: "https://eventasaurus.com/activities/arctic-monkeys-krakow-241215"
             }
    end

    test "builds breadcrumbs for event without venue" do
      event = %{
        title: "Virtual Event",
        slug: "virtual-event",
        venue: nil
      }

      base_url = "https://eventasaurus.com"
      breadcrumbs = BreadcrumbListSchema.build_event_breadcrumbs(event, base_url)

      assert length(breadcrumbs) == 2
      assert Enum.at(breadcrumbs, 0) == %{name: "Home", url: "https://eventasaurus.com"}

      assert Enum.at(breadcrumbs, 1) == %{
               name: "Virtual Event",
               url: "https://eventasaurus.com/activities/virtual-event"
             }
    end

    test "builds breadcrumbs for event with venue but no city" do
      event = %{
        title: "Test Event",
        slug: "test-event",
        venue: %{
          city_ref: nil
        }
      }

      base_url = "https://eventasaurus.com"
      breadcrumbs = BreadcrumbListSchema.build_event_breadcrumbs(event, base_url)

      assert length(breadcrumbs) == 2
    end
  end

  describe "build_city_breadcrumbs/2" do
    test "builds breadcrumbs for city page" do
      city = %{
        name: "Kraków",
        slug: "krakow"
      }

      base_url = "https://eventasaurus.com"
      breadcrumbs = BreadcrumbListSchema.build_city_breadcrumbs(city, base_url)

      assert length(breadcrumbs) == 2
      assert Enum.at(breadcrumbs, 0) == %{name: "Home", url: "https://eventasaurus.com"}

      assert Enum.at(breadcrumbs, 1) == %{
               name: "Kraków",
               url: "https://eventasaurus.com/cities/krakow"
             }
    end
  end

  describe "build_venue_breadcrumbs/2" do
    test "builds breadcrumbs for venue with city" do
      venue = %{
        name: "Tauron Arena",
        slug: "tauron-arena-krakow",
        city_ref: %{
          name: "Kraków",
          slug: "krakow"
        }
      }

      base_url = "https://eventasaurus.com"
      breadcrumbs = BreadcrumbListSchema.build_venue_breadcrumbs(venue, base_url)

      assert length(breadcrumbs) == 3
      assert Enum.at(breadcrumbs, 0) == %{name: "Home", url: "https://eventasaurus.com"}

      assert Enum.at(breadcrumbs, 1) == %{
               name: "Kraków",
               url: "https://eventasaurus.com/cities/krakow"
             }

      assert Enum.at(breadcrumbs, 2) == %{
               name: "Tauron Arena",
               url: "https://eventasaurus.com/venues/tauron-arena-krakow"
             }
    end

    test "builds breadcrumbs for venue without city" do
      venue = %{
        name: "Virtual Venue",
        slug: "virtual-venue",
        city_ref: nil
      }

      base_url = "https://eventasaurus.com"
      breadcrumbs = BreadcrumbListSchema.build_venue_breadcrumbs(venue, base_url)

      assert length(breadcrumbs) == 2
      assert Enum.at(breadcrumbs, 0) == %{name: "Home", url: "https://eventasaurus.com"}

      assert Enum.at(breadcrumbs, 1) == %{
               name: "Virtual Venue",
               url: "https://eventasaurus.com/venues/virtual-venue"
             }
    end
  end
end
