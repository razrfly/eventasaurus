defmodule EventasaurusWeb.Components.TicketModal do
  use EventasaurusWeb, :html
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.Helpers.CurrencyHelpers

  attr :id, :string, required: true, doc: "unique id for the modal"
  attr :show, :boolean, default: false, doc: "whether to show the modal"
  attr :ticket_form_data, :map, default: %{}, doc: "current ticket form data"
  attr :editing_ticket_index, :integer, default: nil, doc: "index if editing existing ticket"
  attr :on_close, :any, required: true, doc: "event to close modal"
  attr :default_currency, :string, default: "usd", doc: "default currency for tickets"
  attr :show_additional_options, :boolean, default: false, doc: "whether to show additional options section"

  def ticket_modal(assigns) do
    # Ensure tippable is properly handled as boolean
    tippable_value = case Map.get(assigns.ticket_form_data, "tippable") do
      true -> true
      "true" -> true
      _ -> false
    end
    assigns = assign(assigns, :tippable_checked, tippable_value)

    ~H"""
    <.modal
      id={@id}
      show={@show}
      on_cancel={@on_close}
    >
      <:title>
        <%= if @editing_ticket_index, do: "Edit Ticket", else: "Add New Ticket" %>
      </:title>

      <form id="ticket-form" phx-submit="save_ticket" phx-change="validate_ticket">
        <div class="space-y-4">
          <!-- Ticket Name -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Ticket Name *
            </label>
            <input
              type="text"
              name="ticket[title]"
              value={Map.get(@ticket_form_data, "title", "")}
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="e.g., General Admission, VIP, Early Bird"
              required
            />
          </div>

          <!-- Description -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Description
            </label>
            <textarea
              name="ticket[description]"
              rows="2"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Optional description of what's included"
            ><%= Map.get(@ticket_form_data, "description", "") %></textarea>
          </div>

          <!-- Price and Currency -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Price *
              </label>
              <input
                type="number"
                name="ticket[price]"
                value={Map.get(@ticket_form_data, "price", "")}
                step="0.01"
                min="0"
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="0.00"
                required
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Currency
              </label>
              <select
                name="ticket[currency]"
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <%= for {code, name} <- supported_currencies() do %>
                  <option
                    value={code}
                    selected={Map.get(@ticket_form_data, "currency", @default_currency) == code}
                  >
                    <%= name %>
                  </option>
                <% end %>
              </select>
            </div>
          </div>

          <!-- Available Tickets -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">
              Available Tickets *
            </label>
            <input
              type="number"
              name="ticket[quantity]"
              value={Map.get(@ticket_form_data, "quantity", "")}
              min="1"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="100"
              required
            />
          </div>

          <!-- Tippable Checkbox -->
          <div class="flex items-center space-x-2">
            <input
              type="checkbox"
              id="ticket-tippable"
              name="ticket[tippable]"
              value="true"
              checked={@tippable_checked}
              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
            />
            <label for="ticket-tippable" class="text-sm font-medium text-gray-700">
              Allow tips on this ticket
            </label>
          </div>

          <!-- Additional Options Toggle -->
          <div class="border-t pt-4">
            <button
              type="button"
              phx-click="toggle_additional_options"
              class="flex items-center space-x-2 text-sm font-medium text-gray-600 hover:text-gray-800"
            >
              <span>Additional Options</span>
              <svg class="w-4 h-4 transform transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
              </svg>
            </button>
            <p class="text-xs text-gray-500 mt-1">Set custom sale start and end times</p>
          </div>

          <!-- Additional Options Content -->
          <div
            id={"additional-options-#{@id}"}
            class={"space-y-4 #{if @show_additional_options, do: "", else: "hidden"}"}
          >
            <!-- Sale Start Date -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Sale Starts
              </label>
              <input
                type="datetime-local"
                name="ticket[starts_at]"
                value={Map.get(@ticket_form_data, "starts_at", "")}
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <p class="text-xs text-gray-500 mt-1">When this ticket becomes available for purchase</p>
            </div>

            <!-- Sale End Date -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                Sale Ends
              </label>
              <input
                type="datetime-local"
                name="ticket[ends_at]"
                value={Map.get(@ticket_form_data, "ends_at", "")}
                class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <p class="text-xs text-gray-500 mt-1">When this ticket stops being available for purchase</p>
            </div>
          </div>

          <!-- Add spacing before buttons -->
          <div class="mb-6"></div>
        </div>
      </form>

      <:confirm><%= if @editing_ticket_index, do: "Update Ticket", else: "Add Ticket" %></:confirm>
      <:cancel>Cancel</:cancel>
    </.modal>
    """
  end

  # Helper function to check if additional options data exists
  defp has_additional_options_data?(form_data) do
    starts_at = Map.get(form_data, "starts_at", "")
    ends_at = Map.get(form_data, "ends_at", "")
    starts_at != "" || ends_at != ""
  end
end
