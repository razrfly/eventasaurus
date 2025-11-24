defmodule EventasaurusApp.Planning.OccurrencePlanningTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusApp.Planning.OccurrencePlanning

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        event_id: 1,
        poll_id: 2
      }

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :event_id) == 1
      assert get_change(changeset, :poll_id) == 2
    end

    test "valid changeset with series reference" do
      attrs = %{
        event_id: 1,
        poll_id: 2,
        series_type: "movie",
        series_id: 123
      }

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :series_type) == "movie"
      assert get_change(changeset, :series_id) == 123
    end

    test "valid changeset for discovery mode (nil series)" do
      attrs = %{
        event_id: 1,
        poll_id: 2,
        series_type: nil,
        series_id: nil
      }

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      assert changeset.valid?
    end

    test "invalid when event_id is missing" do
      attrs = %{poll_id: 2}

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_id
    end

    test "invalid when poll_id is missing" do
      attrs = %{event_id: 1}

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).poll_id
    end

    test "invalid when series_type set but series_id is nil" do
      attrs = %{
        event_id: 1,
        poll_id: 2,
        series_type: "movie",
        series_id: nil
      }

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      refute changeset.valid?
      assert "must be set when series_type is present" in errors_on(changeset).series_id
    end

    test "invalid when series_id set but series_type is nil" do
      attrs = %{
        event_id: 1,
        poll_id: 2,
        series_type: nil,
        series_id: 123
      }

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      refute changeset.valid?
      assert "must be set when series_id is present" in errors_on(changeset).series_type
    end

    test "invalid when series_type is unsupported" do
      attrs = %{
        event_id: 1,
        poll_id: 2,
        series_type: "invalid_type",
        series_id: 123
      }

      changeset = OccurrencePlanning.changeset(%OccurrencePlanning{}, attrs)

      refute changeset.valid?

      assert "must be one of: movie, venue, activity_series, quiz_series" in errors_on(changeset).series_type
    end
  end

  describe "finalization_changeset/2" do
    test "valid finalization changeset" do
      occurrence_planning = %OccurrencePlanning{
        event_id: 1,
        poll_id: 2
      }

      changeset = OccurrencePlanning.finalization_changeset(occurrence_planning, 123)

      assert changeset.valid?
      assert get_change(changeset, :event_plan_id) == 123
    end

    test "invalid when event_plan_id is nil" do
      occurrence_planning = %OccurrencePlanning{
        event_id: 1,
        poll_id: 2
      }

      changeset = OccurrencePlanning.finalization_changeset(occurrence_planning, nil)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_plan_id
    end
  end

  describe "series_types/0" do
    test "returns all supported series types" do
      types = OccurrencePlanning.series_types()

      assert "movie" in types
      assert "venue" in types
      assert "activity_series" in types
      assert "quiz_series" in types
      assert length(types) == 4
    end
  end

  describe "series_type_display/1" do
    test "returns display names for series types" do
      assert OccurrencePlanning.series_type_display(nil) == "Discovery"
      assert OccurrencePlanning.series_type_display("movie") == "Movie"
      assert OccurrencePlanning.series_type_display("venue") == "Venue"
      assert OccurrencePlanning.series_type_display("activity_series") == "Activity"
      assert OccurrencePlanning.series_type_display("quiz_series") == "Quiz"
    end

    test "capitalizes unknown types" do
      assert OccurrencePlanning.series_type_display("custom_type") == "Custom type"
    end
  end
end
