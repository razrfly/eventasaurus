defmodule EventasaurusWeb.Components.IndividualEmailInput do
  use EventasaurusWeb, :html

  @doc """
  Renders an individual email input component similar to Luma's interface.
  Allows adding emails one by one with visual chips and validation.
  """

  attr :id, :string, required: true
  attr :emails, :list, default: []
  attr :current_input, :string, default: ""
  attr :bulk_input, :string, default: ""
  attr :on_add_email, :any, required: true
  attr :on_remove_email, :any, required: true
  attr :on_input_change, :any, required: true
  attr :placeholder, :string, default: "Enter email address"
  attr :class, :string, default: ""

  def individual_email_input(assigns) do
    ~H"""
    <div class={["space-y-3", @class]}>
      <!-- Email input field -->
      <div class="flex gap-2">
        <div class="flex-1">
          <input
            type="email"
            id={"#{@id}-email-input"}
            name="email_input"
            value={@current_input}
            placeholder={@placeholder}
            class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            phx-input="email_input_change"
            phx-debounce="300"
            phx-hook="EmailInput"
            phx-keydown="add_email_on_enter"
            phx-key="Enter"
          />

          <!-- Validation message -->
          <div
            :if={@current_input != "" && !valid_email?(@current_input)}
            class="mt-1 text-sm text-red-600"
          >
            Please enter a valid email address
          </div>
        </div>

        <button
          type="button"
          phx-click={@on_add_email}
          disabled={@current_input == "" || !valid_email?(@current_input)}
          class="px-4 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-gray-300 disabled:cursor-not-allowed"
        >
          Add
        </button>
      </div>
    </div>
    """
  end

  # Helper function for email validation
  defp valid_email?(email) when is_binary(email) do
    String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
  end

  defp valid_email?(_), do: false
end
