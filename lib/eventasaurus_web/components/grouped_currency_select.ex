defmodule EventasaurusWeb.Components.GroupedCurrencySelect do
  @moduledoc """
  A reusable component for grouped currency selection with search functionality.
  Displays currencies organized by geographic regions with live search filtering.
  """

  use EventasaurusWeb, :live_component
  alias EventasaurusWeb.Helpers.CurrencyHelpers

  # Component attributes
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: "usd"
  attr :label, :string, default: "Currency"
  attr :class, :string, default: ""
  attr :required, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :placeholder, :string, default: "Search currencies..."
  attr :show_search, :boolean, default: true
  attr :use_stripe_data, :boolean, default: true

  def render(assigns) do
    ~H"""
    <div class={["grouped-currency-select", @class]}>
      <label :if={@label} for={"#{@id}-search"} class="block text-sm font-medium text-gray-700 mb-1">
        <%= @label %>
        <span :if={@required} class="text-red-500 ml-1">*</span>
      </label>

      <div class="relative">
        <!-- Search Input -->
        <div :if={@show_search} class="relative mb-3">
          <input
            type="text"
            id={"#{@id}-search"}
            phx-keyup="search"
            phx-target={@myself}
            phx-debounce="300"
            value={@search}
            placeholder={@placeholder}
            disabled={@disabled}
            class="block w-full px-3 py-2 pl-10 pr-4 text-sm border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 disabled:bg-gray-50 disabled:text-gray-500"
          />
          <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
            <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
            </svg>
          </div>
          <div :if={@search != ""} class="absolute inset-y-0 right-0 flex items-center pr-3">
            <button
              type="button"
              phx-click="clear_search"
              phx-target={@myself}
              class="text-gray-400 hover:text-gray-600"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
        </div>

        <!-- Currency Selection -->
        <div class="max-h-64 overflow-y-auto border border-gray-300 rounded-md bg-white shadow-sm">
          <div :if={Enum.empty?(@filtered_currencies)} class="p-4 text-center text-gray-500">
            No currencies found matching "<%= @search %>"
          </div>

          <div :for={{region, currencies} <- @filtered_currencies} class="border-b border-gray-100 last:border-b-0">
            <div class="bg-gray-50 px-3 py-2 text-xs font-semibold text-gray-700 uppercase tracking-wide">
              <%= region %>
            </div>
            <div class="divide-y divide-gray-100">
              <label :for={{code, display_name} <- currencies} class="flex items-center px-3 py-2 hover:bg-gray-50 cursor-pointer">
                <input
                  type="radio"
                  name={@name}
                  value={code}
                  checked={@value == code}
                  disabled={@disabled}
                  phx-click="currency_selected"
                  phx-target={@myself}
                  phx-value-currency={code}
                  class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 disabled:bg-gray-50 disabled:border-gray-300"
                />
                <div class="ml-3 flex-1">
                  <div class="text-sm font-medium text-gray-900">
                    <%= String.upcase(code) %>
                  </div>
                  <div class="text-xs text-gray-500">
                    <%= display_name %>
                  </div>
                </div>
              </label>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, search: "", filtered_currencies: [])}
  end

  def update(assigns, socket) do
    # Get grouped currencies based on configuration
    grouped_currencies =
      if assigns[:use_stripe_data] do
        CurrencyHelpers.grouped_currencies_from_stripe()
      else
        CurrencyHelpers.supported_currencies()
      end

    socket =
      socket
      |> assign(assigns)
      |> assign(:grouped_currencies, grouped_currencies)
      |> assign(:filtered_currencies, grouped_currencies)

    {:ok, socket}
  end

  def handle_event("search", %{"value" => search}, socket) do
    filtered = filter_currencies(socket.assigns.grouped_currencies, search)

    socket =
      socket
      |> assign(:search, search)
      |> assign(:filtered_currencies, filtered)

    {:noreply, socket}
  end

  def handle_event("clear_search", _params, socket) do
    socket =
      socket
      |> assign(:search, "")
      |> assign(:filtered_currencies, socket.assigns.grouped_currencies)

    {:noreply, socket}
  end

  def handle_event("currency_selected", %{"currency" => currency}, socket) do
    # Send the selection back to the parent component/live view
    send(self(), {:currency_selected, socket.assigns.id, currency})
    {:noreply, assign(socket, :value, currency)}
  end

  # Private helper functions

  defp filter_currencies(grouped_currencies, "") do
    grouped_currencies
  end

  defp filter_currencies(grouped_currencies, search) do
    search_lower = String.downcase(search)

    grouped_currencies
    |> Enum.map(fn {region, currencies} ->
      filtered_currencies =
        currencies
        |> Enum.filter(fn {code, display_name} ->
          String.contains?(String.downcase(code), search_lower) or
            String.contains?(String.downcase(display_name), search_lower)
        end)

      {region, filtered_currencies}
    end)
    |> Enum.reject(fn {_region, currencies} -> Enum.empty?(currencies) end)
  end
end
