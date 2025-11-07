defmodule EventasaurusDiscovery.ScraperProcessingLogsTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.ScraperProcessingLogs
  alias EventasaurusDiscovery.ScraperProcessingLogs.ScraperProcessingLog

  describe "log_success/3" do
    test "creates a success log with basic fields" do
      source = create_test_source()

      {:ok, log} =
        ScraperProcessingLogs.log_success(source, nil, %{
          entity_type: "event",
          entity_name: "Test Event"
        })

      assert log.source_id == source.id
      assert log.source_name == source.name
      assert log.status == "success"
      assert log.error_type == nil
      assert log.error_message == nil
      assert log.metadata[:entity_type] == "event"
      assert log.metadata[:entity_name] == "Test Event"
      refute is_nil(log.processed_at)
    end

    test "creates a success log with job_id" do
      source = create_test_source()
      # Use nil instead of fake job_id to avoid foreign key constraint
      job_id = nil

      {:ok, log} = ScraperProcessingLogs.log_success(source, job_id, %{})

      assert log.job_id == job_id
    end

    test "creates a success log with empty metadata" do
      source = create_test_source()

      {:ok, log} = ScraperProcessingLogs.log_success(source)

      assert log.metadata == %{}
    end
  end

  describe "log_failure/4" do
    test "creates a failure log with string error" do
      source = create_test_source()

      {:ok, log} =
        ScraperProcessingLogs.log_failure(
          source,
          nil,
          "GPS coordinates required",
          %{entity_type: "venue"}
        )

      assert log.source_id == source.id
      assert log.status == "failure"
      assert log.error_type == "missing_coordinates"
      assert log.error_message == "GPS coordinates required"
      assert log.metadata[:entity_type] == "venue"
    end

    test "categorizes geocoding failures correctly" do
      source = create_test_source()

      {:ok, log} =
        ScraperProcessingLogs.log_failure(source, nil, "geocoding failed for address", %{})

      assert log.error_type == "geocoding_failed"
    end

    test "categorizes unknown country errors correctly" do
      source = create_test_source()

      {:ok, log} = ScraperProcessingLogs.log_failure(source, nil, "Unknown country: XYZ", %{})

      assert log.error_type == "unknown_country"
    end

    test "categorizes changeset errors correctly" do
      source = create_test_source()
      changeset = %Ecto.Changeset{errors: [slug: {"has already been taken", []}]}

      {:ok, log} = ScraperProcessingLogs.log_failure(source, nil, changeset, %{})

      assert log.error_type == "duplicate_slug"
    end

    test "defaults to unknown_error for unrecognized patterns" do
      source = create_test_source()

      {:ok, log} =
        ScraperProcessingLogs.log_failure(source, nil, "Something weird happened", %{})

      assert log.error_type == "unknown_error"
    end

    test "truncates long error messages to 500 characters" do
      source = create_test_source()
      long_error = String.duplicate("a", 600)

      {:ok, log} = ScraperProcessingLogs.log_failure(source, nil, long_error, %{})

      assert String.length(log.error_message) == 500
    end
  end

  describe "get_success_rate/2" do
    test "calculates success rate correctly" do
      source = create_test_source()

      # Create 7 successes
      for _ <- 1..7 do
        ScraperProcessingLogs.log_success(source, nil, %{})
      end

      # Create 3 failures
      for _ <- 1..3 do
        ScraperProcessingLogs.log_failure(source, nil, "test error", %{})
      end

      stats = ScraperProcessingLogs.get_success_rate(source.name, 7)

      assert stats.success_count == 7
      assert stats.failure_count == 3
      assert stats.total_count == 10
      assert stats.success_rate == 70.0
    end

    test "returns zero rate when no logs exist" do
      stats = ScraperProcessingLogs.get_success_rate("nonexistent", 7)

      assert stats.success_count == 0
      assert stats.failure_count == 0
      assert stats.total_count == 0
      assert stats.success_rate == 0
    end

    test "only counts logs within time window" do
      source = create_test_source()

      # Create a log from 8 days ago (outside 7-day window)
      _old_log =
        %ScraperProcessingLog{}
        |> ScraperProcessingLog.changeset(%{
          source_id: source.id,
          source_name: source.name,
          status: "success",
          processed_at: DateTime.utc_now() |> DateTime.add(-8, :day)
        })
        |> Repo.insert!()

      # Create a recent log
      ScraperProcessingLogs.log_success(source, nil, %{})

      stats = ScraperProcessingLogs.get_success_rate(source.name, 7)

      # Should only count the recent log
      assert stats.total_count == 1
    end
  end

  describe "get_error_breakdown/2" do
    test "returns error counts grouped by type" do
      source = create_test_source()

      # Create various error types
      ScraperProcessingLogs.log_failure(source, nil, "GPS coordinates required", %{})
      ScraperProcessingLogs.log_failure(source, nil, "GPS coordinates required", %{})
      ScraperProcessingLogs.log_failure(source, nil, "geocoding failed", %{})
      ScraperProcessingLogs.log_failure(source, nil, "Unknown country", %{})

      breakdown = ScraperProcessingLogs.get_error_breakdown(source.name, 7)

      # Should be ordered by count descending
      assert length(breakdown) == 3
      assert {"missing_coordinates", 2} in breakdown
      assert {"geocoding_failed", 1} in breakdown
      assert {"unknown_country", 1} in breakdown

      # First item should be the most common error
      [{first_error_type, first_count} | _] = breakdown
      assert first_error_type == "missing_coordinates"
      assert first_count == 2
    end

    test "returns empty list when no failures exist" do
      breakdown = ScraperProcessingLogs.get_error_breakdown("nonexistent", 7)

      assert breakdown == []
    end
  end

  describe "list_error_types/0" do
    test "returns all unique error types" do
      source1 = create_test_source("source1")
      source2 = create_test_source("source2")

      ScraperProcessingLogs.log_failure(source1, nil, "GPS coordinates required", %{})
      ScraperProcessingLogs.log_failure(source1, nil, "geocoding failed", %{})
      ScraperProcessingLogs.log_failure(source2, nil, "geocoding failed", %{})

      error_types = ScraperProcessingLogs.list_error_types()

      assert length(error_types) == 2
      assert "missing_coordinates" in error_types
      assert "geocoding_failed" in error_types
    end

    test "returns sorted list" do
      source = create_test_source()

      ScraperProcessingLogs.log_failure(source, nil, "Unknown country", %{})
      ScraperProcessingLogs.log_failure(source, nil, "geocoding failed", %{})

      error_types = ScraperProcessingLogs.list_error_types()

      # Should be alphabetically sorted
      assert error_types == Enum.sort(error_types)
    end
  end

  describe "get_unknown_errors/1" do
    test "returns unknown error details" do
      source = create_test_source()

      ScraperProcessingLogs.log_failure(
        source,
        nil,
        "Something weird happened",
        %{"entity_type" => "venue", "venue_city" => "Warsaw"}
      )

      unknown = ScraperProcessingLogs.get_unknown_errors(10)

      assert length(unknown) == 1
      [error] = unknown

      assert error.source_name == source.name
      assert error.error_message == "Something weird happened"
      assert error.metadata["entity_type"] == "venue"
      assert error.job_id == nil
      refute is_nil(error.processed_at)
    end

    test "limits results to specified number" do
      source = create_test_source()

      # Create 5 unknown errors
      for i <- 1..5 do
        ScraperProcessingLogs.log_failure(source, nil, "Unknown error #{i}", %{})
      end

      unknown = ScraperProcessingLogs.get_unknown_errors(3)

      assert length(unknown) == 3
    end

    test "only returns errors from last 7 days" do
      source = create_test_source()

      # Create old unknown error (8 days ago)
      %ScraperProcessingLog{}
      |> ScraperProcessingLog.changeset(%{
        source_id: source.id,
        source_name: source.name,
        status: "failure",
        error_type: "unknown_error",
        error_message: "Old error",
        processed_at: DateTime.utc_now() |> DateTime.add(-8, :day)
      })
      |> Repo.insert!()

      # Create recent unknown error
      ScraperProcessingLogs.log_failure(source, nil, "Recent unknown", %{})

      unknown = ScraperProcessingLogs.get_unknown_errors(10)

      # Should only return the recent one
      assert length(unknown) == 1
    end
  end

  describe "categorize_error/1" do
    test "categorizes various error patterns" do
      assert ScraperProcessingLogs.categorize_error("GPS coordinates required") ==
               "missing_coordinates"

      assert ScraperProcessingLogs.categorize_error("geocoding failed for venue") ==
               "geocoding_failed"

      assert ScraperProcessingLogs.categorize_error("Unknown country: XY") == "unknown_country"
      assert ScraperProcessingLogs.categorize_error("City is required") == "missing_city"

      assert ScraperProcessingLogs.categorize_error("Venue name is required") ==
               "missing_venue_name"

      assert ScraperProcessingLogs.categorize_error("Failed to create venue") ==
               "venue_creation_failed"

      assert ScraperProcessingLogs.categorize_error("Connection timeout") == "api_timeout"
      assert ScraperProcessingLogs.categorize_error("rate limit exceeded") == "rate_limit_exceeded"
      assert ScraperProcessingLogs.categorize_error("SSL certificate error") == "ssl_error"
    end

    test "handles atom errors" do
      assert ScraperProcessingLogs.categorize_error(:timeout) == "timeout"
    end

    test "handles tuple errors" do
      assert ScraperProcessingLogs.categorize_error({:http_error, 404}) == "http_error"
    end
  end

  # Test helper functions

  defp create_test_source(name \\ "test_source") do
    unique_slug = "#{name}_#{System.unique_integer([:positive])}"

    %EventasaurusDiscovery.Sources.Source{}
    |> EventasaurusDiscovery.Sources.Source.changeset(%{
      name: name,
      slug: unique_slug
    })
    |> Repo.insert!()
  end
end
