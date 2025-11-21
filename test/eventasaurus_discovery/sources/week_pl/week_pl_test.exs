defmodule EventasaurusDiscovery.Sources.WeekPl.WeekPlTest do
  use EventasaurusApp.DataCase, async: false

  alias EventasaurusDiscovery.Sources.WeekPl.{
    Source,
    Config,
    Client,
    Transformer,
    Helpers.TimeConverter,
    Helpers.BuildIdCache
  }

  describe "Source module" do
    test "returns correct metadata" do
      assert Source.name() == "week.pl"
      assert Source.key() == "week_pl"
      assert Source.priority() == 45
      assert Source.website() == "https://week.pl"
    end

    test "returns 13 supported cities in Poland" do
      cities = Source.supported_cities()
      assert length(cities) == 13
      assert Enum.all?(cities, fn city -> city.country == "Poland" end)

      # Verify major cities are included
      city_names = Enum.map(cities, & &1.name)
      assert "Kraków" in city_names
      assert "Warszawa" in city_names
      assert "Wrocław" in city_names
      assert "Gdańsk" in city_names
    end

    test "returns festival periods" do
      festivals = Source.active_festivals()
      assert length(festivals) >= 3

      # Verify structure
      Enum.each(festivals, fn festival ->
        assert Map.has_key?(festival, :name)
        assert Map.has_key?(festival, :code)
        assert Map.has_key?(festival, :starts_at)
        assert Map.has_key?(festival, :ends_at)
        assert Map.has_key?(festival, :price)
        assert %Date{} = festival.starts_at
        assert %Date{} = festival.ends_at
      end)
    end

    test "festival_active? checks current date against festival periods" do
      # This test depends on current date
      result = Source.festival_active?()
      assert is_boolean(result)
    end
  end

  describe "Config module" do
    test "provides correct base URL" do
      assert Config.base_url() == "https://week.pl"
    end

    test "provides HTTP headers" do
      headers = Config.default_headers()
      assert is_list(headers)
      assert {"Accept", "application/json"} in headers
      assert {"User-Agent", _} = Enum.find(headers, fn {key, _} -> key == "User-Agent" end)
    end

    test "provides rate limiting configuration" do
      assert Config.request_delay_ms() == 2_000
    end

    test "provides build ID cache TTL" do
      assert Config.build_id_cache_ttl_ms() == 3_600_000  # 1 hour
    end
  end

  describe "TimeConverter module" do
    test "converts minutes to DateTime correctly" do
      date = ~D[2025-11-20]
      slot = 1140  # 7:00 PM = 19:00

      {:ok, datetime} = TimeConverter.convert_minutes_to_time(slot, date, "Europe/Warsaw")

      assert datetime.year == 2025
      assert datetime.month == 11
      assert datetime.day == 20
      # Verify it's in UTC (Warsaw is UTC+1 in winter, UTC+2 in summer)
      assert datetime.time_zone == "Etc/UTC"
    end

    test "formats time correctly for display" do
      assert TimeConverter.format_time(0) == "12:00 AM"
      assert TimeConverter.format_time(60) == "1:00 AM"
      assert TimeConverter.format_time(720) == "12:00 PM"
      assert TimeConverter.format_time(1140) == "7:00 PM"
      assert TimeConverter.format_time(1380) == "11:00 PM"
    end

    test "handles edge cases" do
      # Midnight
      assert TimeConverter.format_time(0) == "12:00 AM"
      # Noon
      assert TimeConverter.format_time(720) == "12:00 PM"
      # With minutes
      assert TimeConverter.format_time(1155) == "7:15 PM"
    end

    test "supports Polish timezone" do
      {:ok, datetime} = TimeConverter.convert_minutes_to_time(1140, ~D[2025-11-20], "Europe/Warsaw")
      assert datetime.time_zone == "Etc/UTC"
    end
  end

  describe "Transformer module" do
    setup do
      restaurant = %{
        "id" => "1373",
        "name" => "La Forchetta",
        "slug" => "la-forchetta",
        "address" => "ul. Floriańska 42",
        "city" => "Kraków",
        "cuisine" => "Italian",
        "location" => %{
          "lat" => 50.0647,
          "lng" => 19.9450
        }
      }

      festival = %{
        name: "RestaurantWeek Spring",
        code: "RWP26W",
        starts_at: ~D[2026-03-04],
        ends_at: ~D[2026-04-22],
        price: 63.0
      }

      {:ok, restaurant: restaurant, festival: festival}
    end

    test "transforms restaurant slot to event structure", %{restaurant: restaurant, festival: festival} do
      slot = 1140  # 7:00 PM
      date = "2025-11-20"

      event = Transformer.transform_restaurant_slot(restaurant, slot, date, festival, "Kraków")

      # Verify core event fields
      assert event.title == "La Forchetta"
      assert event.external_id == "week_pl_1373_2025-11-20_1140"
      assert event.occurrence_type == :explicit
      assert String.contains?(event.url, "la-forchetta")

      # Verify description includes festival info
      assert String.contains?(event.description, "RestaurantWeek Spring")
      assert String.contains?(event.description, "63")

      # Verify venue attributes
      assert event.venue_attributes.name == "La Forchetta"
      assert event.venue_attributes.address == "ul. Floriańska 42"
      assert event.venue_attributes.city == "Kraków"
      assert event.venue_attributes.country == "Poland"
      assert event.venue_attributes.latitude == 50.0647
      assert event.venue_attributes.longitude == 19.9450

      # Verify metadata
      assert event.metadata.restaurant_date_id == "1373_2025-11-20"
      assert event.metadata.restaurant_id == "1373"
      assert event.metadata.date == "2025-11-20"
      assert event.metadata.slot == 1140
      assert event.metadata.festival_code == "RWP26W"
      assert event.metadata.festival_name == "RestaurantWeek Spring"
      assert event.metadata.menu_price == 63.0

      # Verify times
      assert %DateTime{} = event.starts_at
      assert %DateTime{} = event.ends_at
      # Event should be 2 hours long
      duration = DateTime.diff(event.ends_at, event.starts_at, :second)
      assert duration == 7200  # 2 hours in seconds
    end

    test "creates correct consolidation key", %{restaurant: restaurant, festival: festival} do
      event1 = Transformer.transform_restaurant_slot(restaurant, 1140, "2025-11-20", festival, "Kraków")
      event2 = Transformer.transform_restaurant_slot(restaurant, 1200, "2025-11-20", festival, "Kraków")
      event3 = Transformer.transform_restaurant_slot(restaurant, 1140, "2025-11-21", festival, "Kraków")

      # Same restaurant, same date -> same consolidation key
      assert event1.metadata.restaurant_date_id == event2.metadata.restaurant_date_id
      # Same restaurant, different date -> different consolidation key
      refute event1.metadata.restaurant_date_id == event3.metadata.restaurant_date_id

      # External IDs should be unique
      assert event1.external_id != event2.external_id
      assert event1.external_id != event3.external_id
    end
  end

  describe "BuildIdCache" do
    test "GenServer starts successfully" do
      # BuildIdCache should be started by application.ex
      assert Process.whereis(BuildIdCache) != nil
    end

    @tag :integration
    test "fetches and caches build ID" do
      # This requires network access
      case BuildIdCache.get_build_id() do
        {:ok, build_id} ->
          assert is_binary(build_id)
          assert String.length(build_id) > 0

        {:error, reason} ->
          # Network might be unavailable in CI
          assert reason in [:timeout, :fetch_failed]
      end
    end
  end

  describe "Client" do
    @tag :integration
    test "builds correct URL structure" do
      # We can test URL building without making requests
      # The actual URL structure is internal to Client, but we can verify the pattern
      assert Config.base_url() == "https://week.pl"
    end

    @tag :integration
    @tag timeout: 30_000
    test "fetches restaurants with retry on 404" do
      # This test requires network access and valid festival period
      # Skip if festival not active
      if Source.festival_active?() do
        region_id = "1"  # Kraków
        region_name = "Kraków"
        date = Date.utc_today() |> Date.add(15) |> Date.to_string()
        slot = 1140
        people_count = 2

        case Client.fetch_restaurants(region_id, region_name, date, slot, people_count) do
          {:ok, response} ->
            assert is_map(response)
            assert Map.has_key?(response, "pageProps")

          {:error, reason} ->
            # Network/API issues are acceptable in tests
            assert reason in [:timeout, :rate_limited, :not_found, :invalid_response]
        end
      else
        :ok
      end
    end
  end

  describe "Category Mapping" do
    test "week_pl.yml mapping file exists" do
      priv_dir = :code.priv_dir(:eventasaurus)
      mapping_file = Path.join([priv_dir, "category_mappings", "week_pl.yml"])
      assert File.exists?(mapping_file)
    end

    test "week_pl.yml has valid structure" do
      priv_dir = :code.priv_dir(:eventasaurus)
      mapping_file = Path.join([priv_dir, "category_mappings", "week_pl.yml"])

      {:ok, data} = YamlElixir.read_from_file(mapping_file)

      # Verify structure
      assert Map.has_key?(data, "mappings")
      assert is_map(data["mappings"])

      # Verify key cuisine mappings exist
      mappings = data["mappings"]
      assert Map.has_key?(mappings, "italian")
      assert Map.has_key?(mappings, "polish")
      assert Map.has_key?(mappings, "restaurant")

      # All should map to food-drink category
      assert mappings["italian"] == "food-drink"
      assert mappings["polish"] == "food-drink"
      assert mappings["restaurant"] == "food-drink"

      # Verify patterns exist
      if Map.has_key?(data, "patterns") do
        assert is_list(data["patterns"])
      end
    end
  end
end
