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

  def ticket_modal(assigns) do
    ~H"""
    <.modal
      id={@id}
      show={@show}
      on_cancel={@on_close}
      on_confirm={JS.push("save_ticket")}
    >
      <:title>
        <%= if @editing_ticket_index, do: "Edit Ticket", else: "Add New Ticket" %>
      </:title>

      <form id="ticket-form" phx-submit="save_ticket">
        <div class="space-y-4">
        <!-- Ticket Title -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Ticket Name</label>
          <input
            type="text"
            name="ticket[title]"
            value={Map.get(@ticket_form_data, "title", "")}
            placeholder="e.g., General Admission, VIP, Early Bird"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            phx-change="validate_ticket"
          />
        </div>

        <!-- Ticket Description -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Description (optional)</label>
          <textarea
            name="ticket[description]"
            value={Map.get(@ticket_form_data, "description", "")}
            placeholder="Describe what's included with this ticket..."
            rows="3"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            phx-change="validate_ticket"
          ><%= Map.get(@ticket_form_data, "description", "") %></textarea>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <!-- Price -->
          <div class="sm:col-span-2">
            <label class="block text-sm font-medium text-gray-700 mb-1">Price</label>
            <div class="relative">
              <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <span class="text-gray-500 sm:text-sm"><%= currency_symbol(Map.get(@ticket_form_data, "currency", @default_currency)) %></span>
              </div>
              <input
                type="number"
                name="ticket[price]"
                value={Map.get(@ticket_form_data, "price", "")}
                step="0.01"
                min="0"
                placeholder="0.00"
                class="block w-full pl-7 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                phx-change="validate_ticket"
              />
            </div>
          </div>

          <!-- Currency -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Currency</label>
            <select
              name="ticket[currency]"
              class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              phx-change="validate_ticket"
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

        <!-- Quantity (separate row for better spacing) -->
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Available Tickets</label>
          <input
            type="number"
            name="ticket[quantity]"
            value={Map.get(@ticket_form_data, "quantity", "")}
            min="1"
            placeholder="100"
            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            phx-change="validate_ticket"
          />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <!-- Sale Start Time (optional) -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Sale Starts (optional)</label>
            <input
              type="datetime-local"
              name="ticket[starts_at]"
              value={Map.get(@ticket_form_data, "starts_at", "")}
              class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              phx-change="validate_ticket"
            />
          </div>

          <!-- Sale End Time (optional) -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Sale Ends (optional)</label>
            <input
              type="datetime-local"
              name="ticket[ends_at]"
              value={Map.get(@ticket_form_data, "ends_at", "")}
              class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              phx-change="validate_ticket"
            />
          </div>
        </div>

        <!-- Tippable Option -->
        <div class="flex items-center">
          <input
            type="checkbox"
            name="ticket[tippable]"
            value="true"
            checked={Map.get(@ticket_form_data, "tippable", false) == true}
            class="h-4 w-4 text-indigo-600 border-gray-300 rounded focus:ring-indigo-500"
            phx-change="validate_ticket"
          />
          <label class="ml-2 block text-sm text-gray-700">
            Allow tips on this ticket
          </label>
        </div>

        <!-- Help text -->
        <div class="bg-blue-50 border border-blue-200 rounded-md p-3">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"></path>
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-blue-700">
                Set specific sale times to control when tickets become available. Leave blank to make tickets available immediately.
              </p>
            </div>
          </div>
        </div>
        </div>
      </form>

      <:confirm>
        <%= if @editing_ticket_index, do: "Update Ticket", else: "Add Ticket" %>
      </:confirm>

      <:cancel>Cancel</:cancel>
    </.modal>
    """
  end
end
