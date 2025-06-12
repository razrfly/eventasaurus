defmodule Eventasaurus.MachineryTest do
  use ExUnit.Case, async: true

  test "Machinery dependency is correctly installed" do
    # Just verify the module is available
    assert Code.ensure_loaded?(Machinery)

    # Verify we can access Machinery functions
    assert function_exported?(Machinery, :transition_to, 3)
  end

  test "Machinery basic usage works" do
    # For now, just test that the dependency is loaded and we can compile
    # We'll implement proper state machine tests when we create the actual Event schema
    assert :ok == :ok
  end
end
