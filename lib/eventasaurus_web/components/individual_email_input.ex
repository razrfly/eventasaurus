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

      <!-- Email count and bulk actions -->
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

      <!-- Bulk paste support -->
      <div class="border-t border-gray-200 pt-3">
        <details class="group">
          <summary class="cursor-pointer text-sm text-gray-600 hover:text-gray-800 font-medium">
            <span class="group-open:hidden">+ Paste multiple emails</span>
            <span class="hidden group-open:inline">− Hide bulk paste</span>
          </summary>
          
          <div class="mt-3 space-y-2">
            <form phx-change="bulk_email_input">
              <textarea
                id={"#{@id}-bulk-input"}
                name="bulk_email_input"
                value={@bulk_input}
                rows="3"
                placeholder="Paste multiple emails separated by commas or new lines:&#10;user1@example.com, user2@example.com&#10;user3@example.com"
                class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              ></textarea>
            </form>
            
            <button
              type="button"
              phx-click="add_bulk_emails"
              class="px-3 py-2 text-sm font-medium text-blue-600 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Add all valid emails
            </button>
          </div>
        </details>
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