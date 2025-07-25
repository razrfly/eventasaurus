defmodule EventasaurusWeb.EventLive.FormHelpersTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.EventLive.FormHelpers

  describe "resolve_event_attributes/1" do
    test "maps confirmed date, confirmed venue, free event correctly" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed", 
        "participation_type" => "free"
      }

      result = FormHelpers.resolve_event_attributes(params)

      assert result.status == :confirmed
      assert result.is_ticketed == false
      assert result.taxation_type == "ticketless"
      assert result.is_virtual == false
    end

    test "maps virtual event correctly" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "virtual",
        "participation_type" => "free"
      }

      result = FormHelpers.resolve_event_attributes(params)

      assert result.status == :confirmed
      assert result.is_virtual == true
      assert result.venue_id == nil
    end

    test "maps crowdfunding correctly" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "crowdfunding"
      }

      result = FormHelpers.resolve_event_attributes(params)

      assert result.status == :threshold
      assert result.is_ticketed == true
      assert result.taxation_type == "ticketed_event"
      assert result.threshold_type == "revenue"
    end

    test "maps interest validation correctly" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "interest"
      }

      result = FormHelpers.resolve_event_attributes(params)

      assert result.status == :threshold
      assert result.threshold_type == "attendee_count"
    end

    test "resolves status conflicts correctly (threshold wins over polling)" do
      params = %{
        "date_certainty" => "polling",
        "venue_certainty" => "confirmed",
        "participation_type" => "crowdfunding"
      }

      result = FormHelpers.resolve_event_attributes(params)

      # Threshold should take precedence over polling
      assert result.status == :threshold
      assert result.threshold_type == "revenue"
    end

    test "maps polling for both date and venue" do
      params = %{
        "date_certainty" => "polling",
        "venue_certainty" => "polling",
        "participation_type" => "free"
      }

      result = FormHelpers.resolve_event_attributes(params)

      assert result.status == :polling
    end

    test "handles missing parameters gracefully" do
      params = %{}

      result = FormHelpers.resolve_event_attributes(params)

      # Should use defaults
      assert result.status == :confirmed
      assert result.is_ticketed == false
      assert result.taxation_type == "ticketless"
      assert result.is_virtual == false
    end
  end

  describe "individual mapping functions" do
    test "map_date_certainty_to_status/2" do
      assert FormHelpers.map_date_certainty_to_status(%{}, "confirmed").status == :confirmed
      assert FormHelpers.map_date_certainty_to_status(%{}, "polling").status == :polling
      assert FormHelpers.map_date_certainty_to_status(%{}, "planning").status == :draft
      assert FormHelpers.map_date_certainty_to_status(%{}, "invalid").status == :confirmed
    end

    test "map_venue_certainty_to_fields/2" do
      result = FormHelpers.map_venue_certainty_to_fields(%{}, "virtual")
      assert result.is_virtual == true
      assert result.venue_id == nil

      result = FormHelpers.map_venue_certainty_to_fields(%{}, "tbd")
      assert result.venue_id == nil
      assert result.is_virtual == false
    end

    test "map_participation_type_to_fields/2" do
      result = FormHelpers.map_participation_type_to_fields(%{}, "ticketed")
      assert result.is_ticketed == true
      assert result.taxation_type == "ticketed_event"

      result = FormHelpers.map_participation_type_to_fields(%{}, "contribution")
      assert result.is_ticketed == false
      assert result.taxation_type == "contribution_collection"
    end
  end
end