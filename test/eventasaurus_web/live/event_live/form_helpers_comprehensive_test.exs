defmodule EventasaurusWeb.EventLive.FormHelpersComprehensiveTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.EventLive.FormHelpers

  @date_options ["confirmed", "polling", "planning"]
  @venue_options ["confirmed", "virtual", "polling", "tbd"]
  @participation_options ["free", "ticketed", "contribution", "crowdfunding", "interest"]

  describe "resolve_event_attributes/1 - All 60 combinations" do
    
    # Comprehensive test for all combinations using nested loops
    test "resolves all valid dropdown combinations correctly" do
      for date_certainty <- @date_options,
          venue_certainty <- @venue_options,
          participation_type <- @participation_options do
        
        params = %{
          "date_certainty" => date_certainty,
          "venue_certainty" => venue_certainty,
          "participation_type" => participation_type
        }
        
        result = FormHelpers.resolve_event_attributes(params)
        
        # All results should have required fields
        assert Map.has_key?(result, :status), 
          "Missing status for #{inspect(params)}"
        assert Map.has_key?(result, :is_ticketed), 
          "Missing is_ticketed for #{inspect(params)}"
        assert Map.has_key?(result, :taxation_type), 
          "Missing taxation_type for #{inspect(params)}"
        assert Map.has_key?(result, :is_virtual), 
          "Missing is_virtual for #{inspect(params)}"
        
        # Status should be valid
        assert result["status"] in ["confirmed", "polling", "draft", "threshold"],
          "Invalid status #{result["status"]} for #{inspect(params)}"
        
        # Boolean fields should be boolean
        assert is_boolean(result["is_ticketed"]),
          "is_ticketed should be boolean for #{inspect(params)}"
        assert is_boolean(result["is_virtual"]),
          "is_virtual should be boolean for #{inspect(params)}"
        
        # Taxation type should be valid
        assert result["taxation_type"] in ["ticketless", "ticketed_event", "contribution_collection"],
          "Invalid taxation_type #{result["taxation_type"]} for #{inspect(params)}"
      end
    end

    # Test specific high-risk combinations from the matrix
    test "combination 1: confirmed date, confirmed venue, free event" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed", 
        "participation_type" => "free"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "confirmed"
      assert result["is_ticketed"] == false
      assert result["taxation_type"] == "ticketless"
      assert result["is_virtual"] == false
    end

    test "combination 4: confirmed date, confirmed venue, crowdfunding (threshold override)" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "crowdfunding"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "threshold"  # Threshold overrides confirmed
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["threshold_type"] == "revenue"
      assert result["is_virtual"] == false
    end

    test "combination 9: confirmed date, virtual venue, crowdfunding" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "virtual",
        "participation_type" => "crowdfunding"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "threshold"
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["threshold_type"] == "revenue"
      assert result["is_virtual"] == true
      assert result["venue_id"] == nil
    end

    test "combination 14: confirmed date, venue polling, crowdfunding (threshold overrides polling)" do
      params = %{
        "date_certainty" => "confirmed",
        "venue_certainty" => "polling",
        "participation_type" => "crowdfunding"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "threshold"  # Threshold overrides polling
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["threshold_type"] == "revenue"
      assert result["is_virtual"] == false
    end

    test "combination 31: date polling, venue polling, free (double polling edge case)" do
      params = %{
        "date_certainty" => "polling",
        "venue_certainty" => "polling",
        "participation_type" => "free"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "polling"  # Both polling should result in polling status
      assert result["is_ticketed"] == false
      assert result["taxation_type"] == "ticketless"
      assert result["is_virtual"] == false
    end

    test "combination 34: date polling, venue polling, crowdfunding (threshold overrides double polling)" do
      params = %{
        "date_certainty" => "polling",
        "venue_certainty" => "polling",
        "participation_type" => "crowdfunding"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "threshold"  # Threshold overrides both polling
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["threshold_type"] == "revenue"
    end

    test "combination 46: planning date, virtual venue, free" do
      params = %{
        "date_certainty" => "planning",
        "venue_certainty" => "virtual",
        "participation_type" => "free"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "draft"
      assert result["is_ticketed"] == false
      assert result["taxation_type"] == "ticketless"
      assert result["is_virtual"] == true
      assert result["venue_id"] == nil
    end

    test "combination 54: planning date, venue polling, crowdfunding (threshold overrides all)" do
      params = %{
        "date_certainty" => "planning",
        "venue_certainty" => "polling",
        "participation_type" => "crowdfunding"
      }
      
      result = FormHelpers.resolve_event_attributes(params)
      
      assert result["status"] == "threshold"  # Threshold overrides draft and polling
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["threshold_type"] == "revenue"
    end
  end

  describe "status resolution priority" do
    test "threshold always takes precedence over other statuses" do
      # Test threshold overriding confirmed
      result1 = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "crowdfunding"
      })
      assert result1.status == :threshold

      # Test threshold overriding polling
      result2 = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "polling",
        "venue_certainty" => "confirmed",
        "participation_type" => "interest"
      })
      assert result2.status == :threshold

      # Test threshold overriding draft
      result3 = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "planning",
        "venue_certainty" => "confirmed",
        "participation_type" => "crowdfunding"
      })
      assert result3.status == :threshold
    end

    test "polling takes precedence over draft and confirmed" do
      # Test polling overriding confirmed via venue
      result1 = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "polling",
        "participation_type" => "free"
      })
      assert result1.status == :polling

      # Test polling overriding draft via venue
      result2 = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "planning",
        "venue_certainty" => "polling",
        "participation_type" => "free"
      })
      assert result2.status == :polling
    end

    test "draft status is preserved when no overrides" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "planning",
        "venue_certainty" => "confirmed",
        "participation_type" => "free"
      })
      assert result["status"] == "draft"
    end
  end

  describe "venue handling" do
    test "virtual events clear venue_id and set is_virtual" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "virtual",
        "participation_type" => "free"
      })
      
      assert result["is_virtual"] == true
      assert result["venue_id"] == nil
    end

    test "tbd venue clears venue_id but keeps is_virtual false" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "tbd",
        "participation_type" => "free"
      })
      
      assert result["is_virtual"] == false
      assert result["venue_id"] == nil
    end

    test "confirmed venue doesn't modify venue fields" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "free"
      })
      
      # Should not set venue_id (that's handled by venue selection)
      # Should not set is_virtual to true
      refute Map.has_key?(result, :venue_id)
      assert result["is_virtual"] == false
    end
  end

  describe "participation type mapping" do
    test "free events have correct taxation settings" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "free"
      })
      
      assert result["is_ticketed"] == false
      assert result["taxation_type"] == "ticketless"
    end

    test "ticketed events have correct taxation settings" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "ticketed"
      })
      
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
    end

    test "contribution events have correct taxation settings" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "contribution"
      })
      
      assert result["is_ticketed"] == false
      assert result["taxation_type"] == "contribution_collection"
    end

    test "crowdfunding events have threshold and taxation settings" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "crowdfunding"
      })
      
      assert result["status"] == "threshold"
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["threshold_type"] == "revenue"
    end

    test "interest events have threshold settings" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "interest"
      })
      
      assert result["status"] == "threshold"
      assert result["threshold_type"] == "attendee_count"
      # Default taxation should be ticketless for interest validation
      assert result["taxation_type"] == "ticketless"
    end
  end

  describe "default value handling" do
    test "handles missing parameters with defaults" do
      # Empty params
      result = FormHelpers.resolve_event_attributes(%{})
      
      assert result["status"] == "confirmed"
      assert result["is_ticketed"] == false
      assert result["taxation_type"] == "ticketless"
      assert result["is_virtual"] == false
    end

    test "handles partial parameters with defaults" do
      # Only date certainty provided
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "polling"
      })
      
      assert result["status"] == "polling"
      assert result["is_ticketed"] == false
      assert result["taxation_type"] == "ticketless"
      assert result["is_virtual"] == false
    end

    test "handles invalid values with defaults" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "invalid",
        "venue_certainty" => "invalid",
        "participation_type" => "invalid"
      })
      
      assert result["status"] == "confirmed"  # Default for invalid date_certainty
      assert result["is_ticketed"] == false  # Default for invalid participation_type
      assert result["taxation_type"] == "ticketless"
      assert result["is_virtual"] == false
    end
  end

  describe "edge cases and complex scenarios" do
    test "threshold revenue type with virtual venue" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "virtual",
        "participation_type" => "crowdfunding"
      })
      
      assert result["status"] == "threshold"
      assert result["threshold_type"] == "revenue"
      assert result["is_virtual"] == true
      assert result["venue_id"] == nil
      assert result["is_ticketed"] == true
    end

    test "threshold attendee type with TBD venue" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "planning",
        "venue_certainty" => "tbd",
        "participation_type" => "interest"
      })
      
      assert result["status"] == "threshold"
      assert result["threshold_type"] == "attendee_count"
      assert result["is_virtual"] == false
      assert result["venue_id"] == nil
    end

    test "multiple polling sources result in single polling status" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "polling",
        "venue_certainty" => "polling",
        "participation_type" => "ticketed"
      })
      
      assert result["status"] == "polling"
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
    end
  end

  describe "validation integration scenarios" do
    test "generates data that would pass Event validation - confirmed event" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "confirmed",
        "participation_type" => "ticketed"
      })
      
      # Should generate data suitable for Event.changeset validation
      assert result["status"] == "confirmed"
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["is_virtual"] == false
    end

    test "generates data that would pass Event validation - threshold event" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "virtual",
        "participation_type" => "crowdfunding"
      })
      
      # Should generate data suitable for threshold event validation
      assert result["status"] == "threshold"
      assert result["threshold_type"] == "revenue"
      assert result["is_ticketed"] == true
      assert result["taxation_type"] == "ticketed_event"
      assert result["is_virtual"] == true
      assert result["venue_id"] == nil
    end

    test "generates data that would pass Event validation - virtual event" do
      result = FormHelpers.resolve_event_attributes(%{
        "date_certainty" => "confirmed",
        "venue_certainty" => "virtual",
        "participation_type" => "free"
      })
      
      # Should generate data suitable for virtual event validation
      assert result["is_virtual"] == true
      assert result["venue_id"] == nil
      assert result["taxation_type"] == "ticketless"
    end
  end
end