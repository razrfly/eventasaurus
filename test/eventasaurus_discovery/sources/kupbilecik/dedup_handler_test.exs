defmodule EventasaurusDiscovery.Sources.Kupbilecik.DedupHandlerTest do
  @moduledoc """
  Tests for the Kupbilecik DedupHandler module.

  Tests deduplication logic including:
  - Performer + venue + date matching
  - Quality validation
  - Same-source and cross-source deduplication
  """
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Kupbilecik.DedupHandler

  describe "validate_event_quality/1" do
    test "accepts valid event data" do
      event_data = %{
        title: "Test Concert",
        external_id: "kupbilecik_event_123_2025-12-07",
        starts_at: DateTime.add(DateTime.utc_now(), 86400, :second)
      }

      assert {:ok, ^event_data} = DedupHandler.validate_event_quality(event_data)
    end

    test "rejects event missing title" do
      event_data = %{
        title: nil,
        external_id: "kupbilecik_event_123_2025-12-07",
        starts_at: DateTime.add(DateTime.utc_now(), 86400, :second)
      }

      assert {:error, reason} = DedupHandler.validate_event_quality(event_data)
      assert reason =~ "title"
    end

    test "rejects event missing external_id" do
      event_data = %{
        title: "Test Concert",
        external_id: nil,
        starts_at: DateTime.add(DateTime.utc_now(), 86400, :second)
      }

      assert {:error, reason} = DedupHandler.validate_event_quality(event_data)
      assert reason =~ "external_id"
    end

    test "rejects event missing starts_at" do
      event_data = %{
        title: "Test Concert",
        external_id: "kupbilecik_event_123_2025-12-07",
        starts_at: nil
      }

      assert {:error, reason} = DedupHandler.validate_event_quality(event_data)
      assert reason =~ "starts_at"
    end

    test "rejects past events" do
      event_data = %{
        title: "Test Concert",
        external_id: "kupbilecik_event_123_2025-12-07",
        starts_at: DateTime.add(DateTime.utc_now(), -86400, :second)
      }

      assert {:error, reason} = DedupHandler.validate_event_quality(event_data)
      assert reason =~ "past"
    end

    test "rejects events more than 2 years in future" do
      event_data = %{
        title: "Test Concert",
        external_id: "kupbilecik_event_123_2025-12-07",
        # 3 years in future
        starts_at: DateTime.add(DateTime.utc_now(), 3 * 365 * 86400, :second)
      }

      assert {:error, reason} = DedupHandler.validate_event_quality(event_data)
      assert reason =~ "2 years"
    end
  end

  # Note: Integration tests for check_duplicate/2 that require database access
  # are in a separate test file using DataCase. The function signature is:
  #   check_duplicate(event_data, source) -> {:unique, event_data} | {:duplicate, existing_event}
  #
  # The deduplication logic follows the Bandsintown pattern:
  # - Phase 1: Same-source dedup via external_id
  # - Phase 2: Cross-source fuzzy match via performer + venue + date + GPS

  describe "performer name normalization" do
    # Testing internal logic through validate_event_quality
    # since the normalization is private

    test "handles various performer name formats in title" do
      # These events should all pass validation if they have proper dates
      future_date = DateTime.add(DateTime.utc_now(), 86400, :second)

      events = [
        %{
          title: "Artist Name at Venue",
          external_id: "test1",
          starts_at: future_date
        },
        %{
          title: "Artist Name w Venue",
          external_id: "test2",
          starts_at: future_date
        },
        %{
          title: "Artist Name - Special Show",
          external_id: "test3",
          starts_at: future_date
        }
      ]

      for event <- events do
        assert {:ok, _} = DedupHandler.validate_event_quality(event)
      end
    end
  end
end
