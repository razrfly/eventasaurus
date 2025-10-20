defmodule Eventasaurus.Discovery.OccurrenceValidatorTest do
  use ExUnit.Case, async: true

  alias Eventasaurus.Discovery.OccurrenceValidator

  doctest OccurrenceValidator

  describe "validate_type/1" do
    test "accepts 'explicit' as valid type" do
      assert {:ok, "explicit"} = OccurrenceValidator.validate_type("explicit")
    end

    test "accepts 'pattern' as valid type" do
      assert {:ok, "pattern"} = OccurrenceValidator.validate_type("pattern")
    end

    test "accepts 'exhibition' as valid type" do
      assert {:ok, "exhibition"} = OccurrenceValidator.validate_type("exhibition")
    end

    test "accepts 'recurring' as valid type" do
      assert {:ok, "recurring"} = OccurrenceValidator.validate_type("recurring")
    end

    test "rejects 'one_time' as invalid type" do
      assert {:error, message} = OccurrenceValidator.validate_type("one_time")
      assert message =~ "Invalid occurrence type 'one_time'"
      assert message =~ "Allowed types: explicit, pattern, exhibition, recurring"
    end

    test "rejects 'unknown' as invalid type" do
      assert {:error, message} = OccurrenceValidator.validate_type("unknown")
      assert message =~ "Invalid occurrence type 'unknown'"
    end

    test "rejects 'movie' as invalid type" do
      assert {:error, message} = OccurrenceValidator.validate_type("movie")
      assert message =~ "Invalid occurrence type 'movie'"
    end

    test "rejects arbitrary string as invalid type" do
      assert {:error, message} = OccurrenceValidator.validate_type("invalid_type")
      assert message =~ "Invalid occurrence type 'invalid_type'"
    end

    test "rejects non-string values" do
      assert {:error, message} = OccurrenceValidator.validate_type(123)
      assert message =~ "Must be a string"

      assert {:error, message} = OccurrenceValidator.validate_type(nil)
      assert message =~ "Must be a string"

      assert {:error, message} = OccurrenceValidator.validate_type(%{})
      assert message =~ "Must be a string"
    end

    test "error messages reference documentation" do
      assert {:error, message} = OccurrenceValidator.validate_type("bad_type")
      assert message =~ "docs/OCCURRENCE_TYPES.md"
    end
  end

  describe "normalize_legacy_type/1" do
    test "normalizes 'one_time' to 'explicit'" do
      assert {:ok, "explicit"} = OccurrenceValidator.normalize_legacy_type("one_time")
    end

    test "normalizes 'unknown' to 'exhibition'" do
      assert {:ok, "exhibition"} = OccurrenceValidator.normalize_legacy_type("unknown")
    end

    test "normalizes 'movie' to 'explicit'" do
      assert {:ok, "explicit"} = OccurrenceValidator.normalize_legacy_type("movie")
    end

    test "passes through valid types unchanged" do
      assert {:ok, "explicit"} = OccurrenceValidator.normalize_legacy_type("explicit")
      assert {:ok, "pattern"} = OccurrenceValidator.normalize_legacy_type("pattern")
      assert {:ok, "exhibition"} = OccurrenceValidator.normalize_legacy_type("exhibition")
      assert {:ok, "recurring"} = OccurrenceValidator.normalize_legacy_type("recurring")
    end

    test "rejects invalid types" do
      assert {:error, _} = OccurrenceValidator.normalize_legacy_type("invalid")
    end
  end

  describe "validate_structure/1" do
    test "validates explicit occurrence with dates" do
      occurrence = %{
        "type" => "explicit",
        "dates" => [
          %{"date" => "2024-06-15", "time" => "19:00", "external_id" => "test-123"}
        ]
      }

      assert {:ok, ^occurrence} = OccurrenceValidator.validate_structure(occurrence)
    end

    test "rejects explicit occurrence without dates" do
      occurrence = %{"type" => "explicit"}

      assert {:error, message} = OccurrenceValidator.validate_structure(occurrence)
      assert message =~ "missing required field 'dates'"
    end

    test "rejects explicit occurrence with empty dates" do
      occurrence = %{"type" => "explicit", "dates" => []}

      assert {:error, message} = OccurrenceValidator.validate_structure(occurrence)
      assert message =~ "missing required field 'dates'"
    end

    test "validates pattern occurrence with pattern" do
      occurrence = %{
        "type" => "pattern",
        "pattern" => %{"frequency" => "weekly", "days_of_week" => ["tuesday"]}
      }

      assert {:ok, ^occurrence} = OccurrenceValidator.validate_structure(occurrence)
    end

    test "rejects pattern occurrence without pattern" do
      occurrence = %{"type" => "pattern"}

      assert {:error, message} = OccurrenceValidator.validate_structure(occurrence)
      assert message =~ "missing required field 'pattern'"
    end

    test "validates exhibition occurrence with dates" do
      occurrence = %{
        "type" => "exhibition",
        "dates" => [%{"date" => "2024-06-15", "end_date" => "2024-09-30"}]
      }

      assert {:ok, ^occurrence} = OccurrenceValidator.validate_structure(occurrence)
    end

    test "rejects exhibition occurrence without dates" do
      occurrence = %{"type" => "exhibition"}

      assert {:error, message} = OccurrenceValidator.validate_structure(occurrence)
      assert message =~ "missing required field 'dates'"
    end

    test "validates recurring occurrence with dates" do
      occurrence = %{
        "type" => "recurring",
        "dates" => [%{"date" => "2024-06-01"}],
        "pattern_description" => "Every weekend"
      }

      assert {:ok, ^occurrence} = OccurrenceValidator.validate_structure(occurrence)
    end

    test "rejects recurring occurrence without dates" do
      occurrence = %{"type" => "recurring", "pattern_description" => "Every weekend"}

      assert {:error, message} = OccurrenceValidator.validate_structure(occurrence)
      assert message =~ "missing required field 'dates'"
    end

    test "rejects occurrence without type field" do
      occurrence = %{"dates" => [%{"date" => "2024-06-15"}]}

      assert {:error, message} = OccurrenceValidator.validate_structure(occurrence)
      assert message =~ "must have a 'type' field"
    end

    test "rejects occurrence with invalid type" do
      occurrence = %{"type" => "invalid_type", "dates" => []}

      assert {:error, message} = OccurrenceValidator.validate_structure(occurrence)
      assert message =~ "Invalid occurrence type 'invalid_type'"
    end
  end

  describe "allowed_types/0" do
    test "returns list of allowed types" do
      types = OccurrenceValidator.allowed_types()

      assert is_list(types)
      assert "explicit" in types
      assert "pattern" in types
      assert "exhibition" in types
      assert "recurring" in types
      assert length(types) == 4
    end

    test "does not include legacy types" do
      types = OccurrenceValidator.allowed_types()

      refute "one_time" in types
      refute "unknown" in types
      refute "movie" in types
    end
  end
end
