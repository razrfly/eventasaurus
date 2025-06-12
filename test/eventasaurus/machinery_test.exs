defmodule Eventasaurus.MachineryTest do
  use ExUnit.Case, async: true

  # Define a minimal dummy state machine for testing
  defmodule TestStateMachine do
    use Machinery,
      field: :status,
      states: [:draft, :confirmed],
      transitions: %{
        draft: [:confirmed],
        confirmed: []
      }

    defstruct [:id, :status]

    def new(status \\ :draft) do
      %__MODULE__{id: 1, status: status}
    end
  end

  test "Machinery dependency is correctly installed and functional" do
    # Verify the module is available
    assert Code.ensure_loaded?(Machinery)

    # Create a test state machine instance
    machine = TestStateMachine.new(:draft)
    assert machine.status == :draft

    # Test a valid transition
    {:ok, updated_machine} = Machinery.transition_to(machine, TestStateMachine, :confirmed)
    assert updated_machine.status == :confirmed

    # Test an invalid transition
    assert {:error, _reason} = Machinery.transition_to(updated_machine, TestStateMachine, :draft)
  end
end
