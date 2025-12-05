defmodule EventasaurusDiscovery.Utils.UTF8Test do
  use ExUnit.Case, async: true
  alias EventasaurusDiscovery.Utils.UTF8

  describe "ensure_valid_utf8/1" do
    test "preserves valid UTF-8 strings" do
      valid = "Teatr Ludowy – Scena Pod Ratuszem"
      assert UTF8.ensure_valid_utf8(valid) == valid
    end

    test "preserves Polish characters" do
      polish = "Niedzielne poranki z muzyką wiedeńską"
      assert UTF8.ensure_valid_utf8(polish) == polish
    end

    test "preserves various special characters" do
      special = "Café — Théâtre « L'Œuvre »"
      assert UTF8.ensure_valid_utf8(special) == special
    end

    test "removes invalid UTF-8 sequences" do
      # Simulating corrupted en-dash (0xe2 0x80 0x93 becomes 0xe2 0x20 0x53)
      broken = "Teatr Ludowy " <> <<0xe2, 0x20, 0x53>> <> "cena Pod Ratuszem"
      result = UTF8.ensure_valid_utf8(broken)

      # Should remove the invalid sequence
      assert String.valid?(result)
      # The invalid bytes should be removed
      refute String.contains?(result, <<0xe2, 0x20, 0x53>>)
    end

    test "handles incomplete UTF-8 sequences" do
      # Incomplete 3-byte sequence
      incomplete = "Test " <> <<0xe2, 0x80>> <> " text"
      result = UTF8.ensure_valid_utf8(incomplete)

      assert String.valid?(result)
      assert result == "Test  text"
    end

    test "handles nil input" do
      assert UTF8.ensure_valid_utf8(nil) == nil
    end

    test "converts non-string input to string" do
      assert UTF8.ensure_valid_utf8(123) == "123"
      assert UTF8.ensure_valid_utf8(:atom) == "atom"
    end
  end

  describe "validate_map_strings/1" do
    test "validates strings in a flat map" do
      input = %{
        "name" => "Teatr " <> <<0xe2, 0x20, 0x53>> <> "cena",
        "address" => "Valid address",
        "count" => 42
      }

      result = UTF8.validate_map_strings(input)

      assert String.valid?(result["name"])
      assert result["address"] == "Valid address"
      assert result["count"] == 42
    end

    test "validates strings in nested maps" do
      input = %{
        "venue" => %{
          "name" => "Teatr " <> <<0xe2, 0x20, 0x53>> <> "cena",
          "city" => "Kraków"
        },
        "metadata" => %{
          "tags" => ["tag1", "tag2"]
        }
      }

      result = UTF8.validate_map_strings(input)

      assert String.valid?(result["venue"]["name"])
      assert result["venue"]["city"] == "Kraków"
      assert result["metadata"]["tags"] == ["tag1", "tag2"]
    end

    test "validates strings in lists within maps" do
      broken_str = "Test " <> <<0xe2, 0x20, 0x53>>
      input = %{
        "items" => [broken_str, "valid", 123],
        "nested" => [
          %{"name" => broken_str},
          %{"name" => "valid"}
        ]
      }

      result = UTF8.validate_map_strings(input)

      assert String.valid?(Enum.at(result["items"], 0))
      assert Enum.at(result["items"], 1) == "valid"
      assert Enum.at(result["items"], 2) == 123
      assert String.valid?(Enum.at(result["nested"], 0)["name"])
    end

    test "handles non-map input gracefully" do
      assert UTF8.validate_map_strings("string") == "string"
      assert UTF8.validate_map_strings(nil) == nil
      assert UTF8.validate_map_strings([1, 2, 3]) == [1, 2, 3]
    end
  end

  describe "valid_utf8?/1" do
    test "returns true for valid UTF-8" do
      assert UTF8.valid_utf8?("Valid UTF-8 – string")
      assert UTF8.valid_utf8?("Kraków")
    end

    test "returns false for invalid UTF-8" do
      broken = <<84, 101, 115, 116, 226, 32, 83>>
      refute UTF8.valid_utf8?(broken)
    end

    test "returns false for non-binary input" do
      refute UTF8.valid_utf8?(nil)
      refute UTF8.valid_utf8?(123)
      refute UTF8.valid_utf8?(:atom)
    end
  end

  describe "ensure_valid_utf8_with_logging/2" do
    import ExUnit.CaptureLog

    test "logs when invalid UTF-8 is detected" do
      broken = "Test " <> <<0xe2, 0x20, 0x53>>

      log =
        capture_log(fn ->
          result = UTF8.ensure_valid_utf8_with_logging(broken, "test context")
          assert String.valid?(result)
        end)

      assert log =~ "Invalid UTF-8 detected in test context"
      assert log =~ "Bytes removed:"
    end

    test "does not log for valid UTF-8" do
      valid = "Valid UTF-8 – string"

      log =
        capture_log(fn ->
          result = UTF8.ensure_valid_utf8_with_logging(valid, "test context")
          assert result == valid
        end)

      refute log =~ "Invalid UTF-8 detected"
    end
  end

  describe "real-world scenarios" do
    test "handles Karnet venue names from production" do
      # These are actual venue names that caused issues
      venues = [
        "Teatr Ludowy – Scena Pod Ratuszem",
        "Krakowska Pijalnia Zdrojowa, ul. Wadowicka 1b",
        "Muzeum Narodowe w Krakowie – Gmach Główny",
        "Kino \u{201E}Kijów.Centrum\u{201D}",
        "Centrum Kultury \u{201E}Dworek Białoprądnicki\u{201D}"
      ]

      Enum.each(venues, fn venue ->
        result = UTF8.ensure_valid_utf8(venue)
        assert String.valid?(result)
        assert result == venue  # Should preserve valid UTF-8
      end)
    end

    test "simulates the production error case" do
      # This simulates exactly what was happening in production
      # The en-dash (–) UTF-8 bytes [226, 128, 147] get corrupted to [226, 32, 83]
      corrupted_venue = "Teatr Ludowy " <> <<226, 32, 83>> <> "cena Pod Ratuszem"

      # Our fix should clean this
      result = UTF8.ensure_valid_utf8(corrupted_venue)

      assert String.valid?(result)
      # The corrupted bytes should be removed
      refute result =~ <<226, 32, 83>>
    end
  end
end