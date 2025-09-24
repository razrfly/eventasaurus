defmodule EventasaurusWeb.Components.SimpleEmailInput do
  use EventasaurusWeb, :html

  @doc """
  Renders a simple email input component for public events.
  Similar to IndividualEmailInput but without bulk paste functionality.
  """

  attr :id, :string, required: true
  attr :emails, :list, default: []
  attr :current_input, :string, default: ""
  attr :on_add_email, :any, required: true
  attr :on_remove_email, :any, required: true
  attr :on_input_change, :any, required: true
  attr :placeholder, :string, default: "Enter email address"
  attr :class, :string, default: ""

  def simple_email_input(assigns) do
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

      <!-- Email chips/tags -->
      <div :if={length(@emails) > 0} class="flex flex-wrap gap-2">
        <div
          :for={{email, index} <- Enum.with_index(@emails)}
          class="inline-flex items-center gap-2 px-3 py-1 text-sm bg-blue-100 text-blue-800 rounded-full"
        >
          <!-- Email avatar -->
          <div class="flex-shrink-0">
            <div class="w-6 h-6 bg-blue-200 rounded-full flex items-center justify-center">
              <span class="text-xs font-medium text-blue-700">
                <%= String.first(email) |> String.upcase() %>
              </span>
            </div>
          </div>

          <!-- Email address -->
          <span class="font-medium"><%= email %></span>

          <!-- Remove button -->
          <button
            type="button"
            phx-click={@on_remove_email}
            phx-value-index={index}
            class="flex-shrink-0 ml-1 text-blue-600 hover:text-blue-800 hover:bg-blue-200 rounded-full p-1 transition-colors"
            aria-label={"Remove #{email}"}
          >
            <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      <!-- Email count -->
      <div :if={length(@emails) > 0} class="flex items-center justify-between text-sm text-gray-500">
        <span>
          <%= length(@emails) %> email<%= if length(@emails) != 1, do: "s" %> added
        </span>

        <button
          type="button"
          phx-click="clear_all_emails"
          class="text-red-600 hover:text-red-800 font-medium"
        >
          Clear all
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