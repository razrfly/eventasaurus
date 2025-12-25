defmodule EventasaurusDiscovery.ExternalIdGeneratorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.ExternalIdGenerator

  describe "generate/3 for :recurring events" do
    test "generates external_id without date" do
      assert {:ok, "inquizition_97520779"} =
               ExternalIdGenerator.generate(:recurring, "inquizition", %{venue_id: "97520779"})
    end

    test "normalizes source name to lowercase with underscores" do
      assert {:ok, "pub_quiz_123"} =
               ExternalIdGenerator.generate(:recurring, "Pub-Quiz", %{venue_id: "123"})
    end

    test "requires venue_id param" do
      assert {:error, message} = ExternalIdGenerator.generate(:recurring, "test", %{})
      assert message =~ "venue_id"
    end
  end

  describe "generate/3 for :single events" do
    test "generates external_id with type and source_id" do
      assert {:ok, "bandsintown_event_12345"} =
               ExternalIdGenerator.generate(:single, "bandsintown", %{
                 type: "event",
                 source_id: "12345"
               })
    end

    test "requires type and source_id params" do
      assert {:error, message} =
               ExternalIdGenerator.generate(:single, "test", %{source_id: "123"})

      assert message =~ "type"
    end
  end

  describe "generate/3 for :multi_date events" do
    test "generates external_id with date suffix" do
      assert {:ok, "karnet_event_abc123_2025-01-15"} =
               ExternalIdGenerator.generate(:multi_date, "karnet", %{
                 type: "event",
                 source_id: "abc123",
                 date: ~D[2025-01-15]
               })
    end

    test "accepts date as string" do
      assert {:ok, "karnet_event_abc123_2025-01-15"} =
               ExternalIdGenerator.generate(:multi_date, "karnet", %{
                 type: "event",
                 source_id: "abc123",
                 date: "2025-01-15"
               })
    end

    test "rejects invalid date format" do
      assert {:error, message} =
               ExternalIdGenerator.generate(:multi_date, "karnet", %{
                 type: "event",
                 source_id: "abc123",
                 date: "01-15-2025"
               })

      assert message =~ "Invalid date format"
    end

    test "requires all params" do
      assert {:error, message} =
               ExternalIdGenerator.generate(:multi_date, "karnet", %{
                 type: "event",
                 source_id: "abc123"
               })

      assert message =~ "date"
    end
  end

  describe "generate/3 for :showtime events" do
    test "generates simple showtime external_id" do
      assert {:ok, "cinema_city_showtime_789"} =
               ExternalIdGenerator.generate(:showtime, "cinema_city", %{showtime_id: "789"})
    end

    test "generates complex showtime external_id with venue/movie/datetime" do
      assert {:ok, "cinema_city_v1_m1_2025-01-15T14:30:00"} =
               ExternalIdGenerator.generate(:showtime, "cinema_city", %{
                 venue_id: "v1",
                 movie_id: "m1",
                 datetime: ~U[2025-01-15 14:30:00Z]
               })
    end

    test "accepts datetime as string" do
      assert {:ok, "cinema_city_v1_m1_2025-01-15T14:30:00"} =
               ExternalIdGenerator.generate(:showtime, "cinema_city", %{
                 venue_id: "v1",
                 movie_id: "m1",
                 datetime: "2025-01-15T14:30:00"
               })
    end

    test "requires showtime_id or venue/movie/datetime" do
      assert {:error, message} = ExternalIdGenerator.generate(:showtime, "test", %{})
      assert message =~ "showtime_id"
    end
  end

  describe "generate/3 with unknown event type" do
    test "returns error for unknown type" do
      assert {:error, message} = ExternalIdGenerator.generate(:unknown, "test", %{})
      assert message =~ "Unknown event type"
    end
  end

  describe "valid?/2" do
    test "returns true for valid recurring external_id" do
      assert ExternalIdGenerator.valid?(:recurring, "inquizition_97520779")
    end

    test "returns false for recurring external_id with date" do
      refute ExternalIdGenerator.valid?(:recurring, "inquizition_97520779_2025-01-15")
    end

    test "returns true for valid single external_id" do
      assert ExternalIdGenerator.valid?(:single, "bandsintown_event_12345")
    end

    test "returns false for single external_id with date suffix" do
      refute ExternalIdGenerator.valid?(:single, "bandsintown_event_12345_2025-01-15")
    end

    test "returns true for valid multi_date external_id" do
      assert ExternalIdGenerator.valid?(:multi_date, "karnet_event_abc123_2025-01-15")
    end

    test "returns false for multi_date external_id without date" do
      refute ExternalIdGenerator.valid?(:multi_date, "karnet_event_abc123")
    end

    test "returns true for valid simple showtime external_id" do
      assert ExternalIdGenerator.valid?(:showtime, "cinema_city_showtime_789")
    end

    test "returns true for valid complex showtime external_id" do
      assert ExternalIdGenerator.valid?(:showtime, "cinema_city_v1_m1_2025-01-15T14:30:00")
    end

    test "returns false for nil" do
      refute ExternalIdGenerator.valid?(:recurring, nil)
    end
  end

  describe "validate/2" do
    test "returns :ok for valid recurring external_id" do
      assert :ok = ExternalIdGenerator.validate(:recurring, "inquizition_97520779")
    end

    test "returns error with helpful message for recurring with date" do
      assert {:error, message} =
               ExternalIdGenerator.validate(:recurring, "inquizition_97520779_2025-01-15")

      assert message =~ "must NOT contain date suffix"
      assert message =~ "_2025-01-15"
      assert message =~ "recurrence_rule"
    end

    test "returns :ok for valid multi_date external_id" do
      assert :ok = ExternalIdGenerator.validate(:multi_date, "karnet_event_abc_2025-01-15")
    end

    test "returns error for multi_date without date" do
      assert {:error, message} = ExternalIdGenerator.validate(:multi_date, "karnet_event_abc")
      assert message =~ "YYYY-MM-DD"
    end

    test "returns error for unknown event type" do
      assert {:error, message} = ExternalIdGenerator.validate(:unknown, "test_123")
      assert message =~ "Unknown event type"
    end
  end

  describe "detect_type/1" do
    test "detects multi_date from date suffix" do
      assert {:ok, :multi_date} =
               ExternalIdGenerator.detect_type("karnet_event_123_2025-01-15")
    end

    test "detects simple showtime" do
      assert {:ok, :showtime} =
               ExternalIdGenerator.detect_type("cinema_city_showtime_789")
    end

    test "detects complex showtime" do
      assert {:ok, :showtime} =
               ExternalIdGenerator.detect_type("cinema_city_v1_m1_2025-01-15T14:30:00")
    end

    test "detects single from known type word" do
      assert {:ok, :single} =
               ExternalIdGenerator.detect_type("bandsintown_event_12345")

      assert {:ok, :single} =
               ExternalIdGenerator.detect_type("karnet_activity_abc")
    end

    test "returns ambiguous for pattern that could be single or recurring" do
      # "test_venue_123" could be recurring (source_venue_id) or single (source_type_id)
      assert {:error, :ambiguous} = ExternalIdGenerator.detect_type("test_venue_123")
    end

    test "detects recurring for simple pattern" do
      assert {:ok, :recurring} = ExternalIdGenerator.detect_type("inquizition_97520779")
    end

    test "returns unknown for invalid patterns" do
      assert {:error, :unknown} = ExternalIdGenerator.detect_type("invalid")
      assert {:error, :unknown} = ExternalIdGenerator.detect_type("")
      assert {:error, :unknown} = ExternalIdGenerator.detect_type(nil)
    end
  end

  describe "has_date_suffix?/1" do
    test "returns true for external_id with date suffix" do
      assert ExternalIdGenerator.has_date_suffix?("inquizition_97520779_2025-01-15")
      assert ExternalIdGenerator.has_date_suffix?("pubquiz_warszawa_venue_2025-12-31")
    end

    test "returns false for external_id without date suffix" do
      refute ExternalIdGenerator.has_date_suffix?("inquizition_97520779")
      refute ExternalIdGenerator.has_date_suffix?("geeks_who_drink_12345")
    end

    test "returns false for nil" do
      refute ExternalIdGenerator.has_date_suffix?(nil)
    end

    test "does not match datetime suffixes" do
      # Datetime has time component, not just date
      refute ExternalIdGenerator.has_date_suffix?("cinema_city_v1_m1_2025-01-15T14:30:00")
    end
  end

  describe "strip_date_suffix/1" do
    test "removes date suffix" do
      assert "inquizition_97520779" =
               ExternalIdGenerator.strip_date_suffix("inquizition_97520779_2025-01-15")
    end

    test "returns unchanged if no date suffix" do
      assert "inquizition_97520779" =
               ExternalIdGenerator.strip_date_suffix("inquizition_97520779")
    end

    test "handles nil" do
      assert nil == ExternalIdGenerator.strip_date_suffix(nil)
    end
  end

  describe "real-world violation detection" do
    # These tests verify we can detect the actual violations from issue #2929

    test "detects Inquizition violation pattern" do
      # This is the WRONG pattern that was added
      wrong_id = "inquizition_97520779_2025-01-15"

      # Should fail recurring validation
      refute ExternalIdGenerator.valid?(:recurring, wrong_id)

      # Should detect date suffix
      assert ExternalIdGenerator.has_date_suffix?(wrong_id)

      # Validate returns helpful error
      assert {:error, message} = ExternalIdGenerator.validate(:recurring, wrong_id)
      assert message =~ "must NOT contain date suffix"
    end

    test "detects Question One violation pattern" do
      wrong_id = "question_one_the_crown_2025-01-15"

      refute ExternalIdGenerator.valid?(:recurring, wrong_id)
      assert ExternalIdGenerator.has_date_suffix?(wrong_id)
    end

    test "detects PubQuiz violation pattern" do
      wrong_id = "pubquiz-pl_warszawa_centrum_2025-01-07"

      refute ExternalIdGenerator.valid?(:recurring, wrong_id)
      assert ExternalIdGenerator.has_date_suffix?(wrong_id)
    end

    test "validates correct recurring patterns" do
      # These are the CORRECT patterns
      assert ExternalIdGenerator.valid?(:recurring, "inquizition_97520779")
      assert ExternalIdGenerator.valid?(:recurring, "geeks_who_drink_12345")
      assert ExternalIdGenerator.valid?(:recurring, "quizmeisters_venue_abc")
    end
  end

  describe "integration with transformers" do
    # Tests that show how transformers should use this module

    test "recurring event transformer pattern" do
      # Simulating what a transformer should do
      venue_id = "97520779"
      source = "inquizition"

      # CORRECT: Generate without date
      assert {:ok, external_id} =
               ExternalIdGenerator.generate(:recurring, source, %{venue_id: venue_id})

      assert external_id == "inquizition_97520779"
      refute ExternalIdGenerator.has_date_suffix?(external_id)
    end

    test "multi-date event transformer pattern" do
      # For events that SHOULD have dates (like Karnet multi-day festivals)
      source_id = "festival_123"
      source = "karnet"
      date = ~D[2025-06-15]

      assert {:ok, external_id} =
               ExternalIdGenerator.generate(:multi_date, source, %{
                 type: "event",
                 source_id: source_id,
                 date: date
               })

      assert external_id == "karnet_event_festival_123_2025-06-15"
      assert ExternalIdGenerator.has_date_suffix?(external_id)
      assert ExternalIdGenerator.valid?(:multi_date, external_id)
    end
  end
end
