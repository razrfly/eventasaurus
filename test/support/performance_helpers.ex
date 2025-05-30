defmodule EventasaurusWeb.PerformanceHelpers do
  @moduledoc """
  Performance optimization helpers for tests.

  These helpers reduce test setup time and provide reusable patterns
  for common test scenarios.
  """

  import EventasaurusApp.Factory

  @doc """
  Creates a reusable event with venue for testing.

  This avoids recreating the same data structures in multiple tests.
  """
  def create_test_event_with_venue(attrs \\ %{}) do
    venue = insert(:venue,
      name: "Performance Test Venue",
      address: "123 Fast Lane",
      city: "Test City",
      state: "CA"
    )

    default_attrs = %{
      title: "Performance Test Event",
      tagline: "Optimized for speed",
      description: "This event is optimized for testing performance.",
      venue: venue,
      visibility: "public"
    }

    insert(:event, Map.merge(default_attrs, attrs))
  end

  @doc """
  Creates a minimal event for basic tests that don't need venue details.
  """
  def create_minimal_event(attrs \\ %{}) do
    default_attrs = %{
      title: "Minimal Test Event",
      visibility: "public"
    }

    insert(:event, Map.merge(default_attrs, attrs))
  end

  @doc """
  Creates a pre-authenticated user session for tests that need auth.

  Returns {conn, user} tuple for immediate use.
  """
  def setup_authenticated_user(conn, user_attrs \\ %{}) do
    user = insert(:user, user_attrs)
    authenticated_conn = EventasaurusWeb.ConnCase.log_in_user(conn, user)
    {authenticated_conn, user}
  end

  @doc """
  Batch create multiple test entities for tests that need datasets.
  """
  def create_test_dataset do
    venues = for i <- 1..3 do
      insert(:venue, name: "Venue #{i}", city: "City #{i}")
    end

    events = for {venue, i} <- Enum.with_index(venues, 1) do
      insert(:event,
        title: "Event #{i}",
        venue: venue,
        visibility: "public"
      )
    end

    users = for i <- 1..5 do
      insert(:user, name: "User #{i}", email: "user#{i}@test.com")
    end

    %{venues: venues, events: events, users: users}
  end

  @doc """
  Measures the execution time of a function and returns {result, time_in_ms}.

  ## Examples

      {result, execution_time} = measure_time(fn ->
        expensive_operation()
      end)
      IO.puts("Operation took " <> to_string(execution_time) <> "ms")

  """
  def measure_time(fun) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    end_time = System.monotonic_time(:millisecond)
    {result, end_time - start_time}
  end

  @doc """
  Cleanup helper for tests that need specific teardown.
  """
  def cleanup_test_data do
    # If we ever need specific cleanup logic
    :ok
  end

  @doc """
  Prints performance statistics for the current test run.
  """
  def print_performance_stats do
    IO.puts("\n=== Test Suite Performance Stats ===")
    IO.puts("CPU Cores: #{System.schedulers_online()}")
    IO.puts("Max Concurrent Cases: #{ExUnit.configuration()[:max_cases]}")
    IO.puts("Database Pool Size: #{Application.get_env(:eventasaurus, EventasaurusApp.Repo)[:pool_size]}")
    IO.puts("Capture Log: #{ExUnit.configuration()[:capture_log]}")
    IO.puts("=====================================\n")
  end
end
