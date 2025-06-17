defmodule EventasaurusWeb.Components.TicketModal do
  use EventasaurusWeb, :html
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.Helpers.CurrencyHelpers

  attr :id, :string, required: true, doc: "unique id for the modal"
  attr :show, :boolean, default: false, doc: "whether to show the modal"
  attr :ticket_form_data, :map, default: %{}, doc: "current ticket form data"
  attr :pricing_model, :string, default: "fixed", doc: "current pricing model selection"
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

    # Get pricing model, default to "fixed" for backward compatibility
    pricing_model = Map.get(assigns.ticket_form_data, "pricing_model", "fixed")

    assigns = assign(assigns, :tippable_checked, tippable_value)
    assigns = assign(assigns, :pricing_model, pricing_model)

    ~H"""
    <.modal
      id={@id}
      show={@show}
      on_cancel={@on_close}
      on_confirm={JS.dispatch("submit", to: "#ticket-form")}
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

          <!-- Pricing Model Selection -->
          <div class="space-y-3">
            <label class="block text-sm font-medium text-gray-700">
              Pricing Model *
            </label>
            <div class="space-y-2">
              <label class="flex items-center">
                <input
                  type="radio"
                  name="ticket[pricing_model]"
                  value="fixed"
                  checked={Map.get(@ticket_form_data, "pricing_model", "fixed") == "fixed"}
                  class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 focus:ring-blue-500"
                  phx-click="update_pricing_model"
                  phx-value-model="fixed"
                />
                <div class="ml-3">
                  <span class="text-sm font-medium text-gray-900">Fixed Price</span>
                  <p class="text-xs text-gray-500">Set a single price for this ticket</p>
                </div>
              </label>

              <label class="flex items-center">
                <input
                  type="radio"
                  name="ticket[pricing_model]"
                  value="flexible"
                  checked={Map.get(@ticket_form_data, "pricing_model", "fixed") == "flexible"}
                  class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 focus:ring-blue-500"
                  phx-click="update_pricing_model"
                  phx-value-model="flexible"
                />
                <div class="ml-3">
                  <span class="text-sm font-medium text-gray-900">Flexible Pricing</span>
                  <p class="text-xs text-gray-500">Let buyers choose what they pay (pay-what-you-want)</p>
                </div>
              </label>

              <label class="flex items-center opacity-50">
                <input
                  type="radio"
                  name="ticket[pricing_model]"
                  value="dynamic"
                  disabled
                  class="w-4 h-4 text-gray-400 bg-gray-100 border-gray-300 cursor-not-allowed"
                />
                <div class="ml-3">
                  <span class="text-sm font-medium text-gray-500">Dynamic Pricing</span>
                  <p class="text-xs text-gray-400">Price changes based on demand (coming soon)</p>
                </div>
              </label>
            </div>
          </div>

          <!-- Price and Currency -->
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">
                <%= if @pricing_model == "flexible" do %>
                  Base Price (Maximum) *
                <% else %>
                  Price *
                <% end %>
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
                phx-hook="PricingValidator"
                id="base-price-input"
              />
              <%= if @pricing_model == "flexible" do %>
                <p class="text-xs text-gray-500 mt-1">Maximum amount buyers can pay</p>
              <% end %>
              <div id="base-price-error" class="text-red-500 text-xs mt-1 hidden"></div>
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

          <!-- Flexible Pricing Fields -->
          <%= if @pricing_model == "flexible" do %>
            <div class="space-y-4 border rounded-lg p-4 bg-blue-50">
              <h4 class="text-sm font-medium text-blue-900 mb-2">Flexible Pricing Options</h4>

              <div class="grid grid-cols-2 gap-4">
                <!-- Minimum Price -->
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Minimum Price
                  </label>
                  <input
                    type="number"
                    name="ticket[minimum_price]"
                    value={Map.get(@ticket_form_data, "minimum_price", "0")}
                    step="0.01"
                    min="0"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0.00"
                    phx-hook="PricingValidator"
                    id="minimum-price-input"
                  />
                  <p class="text-xs text-gray-500 mt-1">Minimum amount buyers must pay (0 for free)</p>
                  <div id="minimum-price-error" class="text-red-500 text-xs mt-1 hidden"></div>
                </div>

                <!-- Suggested Price -->
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Suggested Price
                  </label>
                  <input
                    type="number"
                    name="ticket[suggested_price]"
                    value={Map.get(@ticket_form_data, "suggested_price", "")}
                    step="0.01"
                    min="0"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="Optional"
                    phx-hook="PricingValidator"
                    id="suggested-price-input"
                  />
                  <p class="text-xs text-gray-500 mt-1">Recommended amount (defaults to base price)</p>
                  <div id="suggested-price-error" class="text-red-500 text-xs mt-1 hidden"></div>
                </div>
              </div>

              <div class="text-xs text-blue-700 bg-blue-100 p-2 rounded">
                <strong>How it works:</strong> Buyers can choose any amount between the minimum and maximum price.
                The suggested price will be pre-filled but they can adjust it.
              </div>
            </div>
          <% end %>

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


end
