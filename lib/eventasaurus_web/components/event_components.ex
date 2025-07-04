defmodule EventasaurusWeb.EventComponents do
  use Phoenix.Component
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.Helpers.CurrencyHelpers
  alias EventasaurusWeb.TimezoneHelpers
  alias EventasaurusWeb.CalendarComponent
  import Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  @doc """
  Renders a time select dropdown with 30-minute increments.

  ## Examples
      <.time_select
        id="event_start_time"
        name="event[start_time]"
        value={@start_time}
        required={true}
      />
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: nil
  attr :required, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global
  attr :hook, :string, default: nil

  def time_select(assigns) do
    ~H"""
    <select
      id={@id}
      name={@name}
      class={["block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-2 focus:ring-blue-500 transition-colors duration-200 sm:text-sm", @class]}
      required={@required}
      phx-update="ignore"
      phx-hook={@hook}
      {@rest}
    >
      <option value="">Select time</option>
      <%= for hour <- 0..23 do %>
        <%= for minute <- [0, 30] do %>
          <%
            value = "#{String.pad_leading("#{hour}", 2, "0")}:#{String.pad_leading("#{minute}", 2, "0")}"
            display_hour = case hour do
              0 -> 12
              h when h > 12 -> h - 12
              h -> h
            end
            am_pm = if hour >= 12, do: "PM", else: "AM"
            display = "#{display_hour}:#{String.pad_leading("#{minute}", 2, "0")} #{am_pm}"
          %>
          <option value={value} selected={@value == value}><%= display %></option>
        <% end %>
      <% end %>
    </select>
    """
  end

  @doc """
  Renders a date input field with consistent styling.

  ## Examples
      <.date_input
        id="event_start_date"
        name="event[start_date]"
        value={@start_date}
        required={true}
      />
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: nil
  attr :required, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def date_input(assigns) do
    ~H"""
    <input
      type="date"
      id={@id}
      name={@name}
      value={@value}
      class={["block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-2 focus:ring-blue-500 transition-colors duration-200 sm:text-sm", @class]}
      required={@required}
      {@rest}
    />
    """
  end

  @doc """
  Renders a timezone select component with all available timezones.

  ## Examples
      <.timezone_select
        field={f[:timezone]}
        selected={@selected_timezone}
        id="event_timezone"
        show_all={true}
      />
  """
  attr :field, Phoenix.HTML.FormField
  attr :id, :string, default: nil
  attr :selected, :string, default: nil
  attr :show_all, :boolean, default: false
  attr :class, :string, default: nil
  attr :required, :boolean, default: false
  attr :rest, :global

  def timezone_select(assigns) do
    assigns = assign_new(assigns, :id, fn -> assigns.field.id end)

    ~H"""
    <div id={"timezone-detector-#{@id}"} phx-hook="TimezoneDetectionHook">
      <select
        id={@id}
        name={@field.name}
        class={["block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-2 focus:ring-blue-500 transition-colors duration-200 sm:text-sm", @class]}
        required={@required}
        {@rest}
      >
        <option value="">Select timezone</option>

        <%= if @show_all do %>
          <%= for {label, value} <- TimezoneHelpers.all_timezone_options() do %>
            <option value={value} selected={@field.value == value || @selected == value}>
              <%= label %>
            </option>
          <% end %>
        <% else %>
          <%= for {group_name, options} <- TimezoneHelpers.timezone_options() do %>
            <optgroup label={group_name}>
              <%= for {label, value} <- options do %>
                <option value={value} selected={@field.value == value || @selected == value}>
                  <%= label %>
                </option>
              <% end %>
            </optgroup>
          <% end %>
          <optgroup label="Show all timezones">
            <option value="__show_all__">Show all timezones...</option>
          </optgroup>
        <% end %>
      </select>
    </div>
    """
  end

  # ======== EVENT SETUP PATH SELECTOR ========

  @doc """
  Ticket Selection Component

  Displays available tickets for an event with quantity selection, pricing,
  and availability information. Handles both free and paid tickets with
  different pricing models.
  """
  attr :tickets, :list, required: true, doc: "list of available tickets"
  attr :selected_tickets, :map, default: %{}, doc: "map of ticket_id => quantity"
  attr :event, :map, required: true, doc: "the event these tickets belong to"
  attr :user, :map, default: nil, doc: "current user (nil if not authenticated)"
  attr :loading, :boolean, default: false, doc: "whether tickets are being updated"

  def ticket_selection_component(assigns) do
    ~H"""
    <div class="relative bg-white border border-gray-200 rounded-xl p-6 shadow-sm mb-6">
      <!-- Loading Overlay -->
      <%= if @loading do %>
        <div class="absolute inset-0 bg-white bg-opacity-75 rounded-xl flex items-center justify-center z-10">
          <div class="flex items-center space-x-2 text-gray-600">
            <svg class="animate-spin h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <span class="text-sm">Updating availability...</span>
          </div>
        </div>
      <% end %>

      <div class="flex items-center justify-between mb-6">
        <h3 class="text-lg font-semibold text-gray-900">Select Tickets</h3>
        <div class="text-sm text-gray-500">
          <%= if Enum.any?(@tickets, &(&1.base_price_cents && &1.base_price_cents > 0)) do %>
            Prices in USD
          <% else %>
            Free Event
          <% end %>
        </div>
      </div>

      <%= if @tickets == [] do %>
        <div class="text-center py-8 text-gray-500">
          <svg class="w-12 h-12 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z" />
          </svg>
          <p class="text-sm">No tickets available at this time</p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for ticket <- @tickets do %>
            <% available = EventasaurusApp.Ticketing.available_quantity(ticket) %>
            <% selected_qty = Map.get(@selected_tickets, ticket.id, 0) %>

            <div class="border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
              <div class="flex items-center justify-between">
                <div class="flex-1">
                  <h4 class="font-semibold text-gray-900"><%= ticket.title %></h4>
                  <p class="text-sm text-gray-600 mt-1"><%= ticket.description %></p>

                  <div class="flex items-center gap-4 mt-2">
                    <!-- Price Display -->
                    <%= if ticket.base_price_cents && ticket.base_price_cents > 0 do %>
                      <span class="text-lg font-bold text-gray-900">
                        <%= format_currency(ticket.base_price_cents, Map.get(ticket, :currency, "usd")) %>
                      </span>
                      <%= if ticket.pricing_model == "flexible" do %>
                        <span class="text-xs text-gray-500">(minimum)</span>
                      <% end %>
                    <% else %>
                      <span class="text-lg font-bold text-green-600">Free</span>
                    <% end %>

                    <!-- Availability Display -->
                    <%= if available > 0 do %>
                      <span class="text-sm text-gray-500">
                        <%= available %> available
                      </span>
                    <% else %>
                      <span class="text-sm font-medium text-red-600">
                        Sold Out
                      </span>
                    <% end %>
                  </div>
                </div>

                <!-- Quantity Controls -->
                <%= if available > 0 do %>
                  <div class="flex items-center space-x-3">
                    <button
                      type="button"
                      phx-click="decrease_ticket_quantity"
                      phx-value-ticket_id={ticket.id}
                      class="w-8 h-8 rounded-full border border-gray-300 flex items-center justify-center text-gray-600 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                      disabled={selected_qty == 0}
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4"></path>
                      </svg>
                    </button>

                    <span class="w-8 text-center font-medium text-gray-900">
                      <%= selected_qty %>
                    </span>

                    <% can_increase = selected_qty < available and selected_qty < 10 %>
                    <button
                      type="button"
                      phx-click="increase_ticket_quantity"
                      phx-value-ticket_id={ticket.id}
                      class="w-8 h-8 rounded-full border border-gray-300 flex items-center justify-center text-gray-600 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                      disabled={!can_increase}
                      title={if !can_increase, do: "Maximum quantity reached", else: "Add ticket"}
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                      </svg>
                    </button>
                  </div>
                <% else %>
                  <div class="text-sm font-medium text-red-600">
                    Sold Out
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Checkout Summary -->
        <%= if map_size(@selected_tickets) > 0 do %>
          <% total_amount = calculate_total_amount(@tickets, @selected_tickets) %>
          <% total_tickets = Enum.sum(Map.values(@selected_tickets)) %>

          <div class="mt-6 pt-6 border-t border-gray-200">
            <div class="flex items-center justify-between mb-4">
              <div class="text-sm text-gray-600">
                <%= total_tickets %> ticket<%= if total_tickets != 1, do: "s" %>
              </div>
              <div class="text-lg font-semibold text-gray-900">
                <%= if total_amount == 0 do %>
                  Free
                <% else %>
                  <%= format_currency(total_amount, "usd") %>
                <% end %>
              </div>
            </div>

            <button
              type="button"
              phx-click="proceed_to_checkout"
              class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-4 rounded-lg transition-colors duration-200"
            >
              <%= if total_amount == 0 do %>
                Reserve Free Tickets
              <% else %>
                Proceed to Checkout
              <% end %>
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # Helper function to calculate total amount for selected tickets
  defp calculate_total_amount(tickets, selected_tickets) do
    tickets
    |> Enum.reduce(0, fn ticket, acc ->
      quantity = Map.get(selected_tickets, ticket.id, 0)
      if quantity > 0 do
        case ticket.pricing_model do
          "fixed" -> acc + (ticket.base_price_cents * quantity)
          "flexible" -> acc + (ticket.minimum_price_cents * quantity)  # Use minimum for calculation
          "dynamic" -> acc + (ticket.base_price_cents * quantity)
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  @doc """
  Event Setup Path Selector Component

  Presents three distinct setup modes for event creation:
  1. Planning Stage (Polling) - for users still deciding on date
  2. Confirmed (Free/Ticketed) - for standard event publishing with optional ticketing
  3. Threshold-Based Pre-Sale - for demand validation before committing
  """
  attr :selected_path, :string, default: "confirmed", doc: "the currently selected setup path"
  attr :mode, :string, default: "full", doc: "display mode: 'full' for new events, 'compact' for edit"
  attr :show_stage_transitions, :boolean, default: false, values: [true, false], doc: "whether to show full selector in edit mode"

  def event_setup_path_selector(assigns) do
    ~H"""
    <%= if @mode == "compact" && !@show_stage_transitions do %>
      <!-- Stage indicator for edit forms -->
      <div class="bg-white rounded-lg border border-gray-200 p-4 mb-4 shadow-sm">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <div class="flex items-center space-x-2">
              <div class={stage_icon_class(@selected_path)}>
                <%= Phoenix.HTML.raw(stage_icon(@selected_path)) %>
              </div>
              <div>
                <h3 class="text-sm font-medium text-gray-900"><%= stage_title(@selected_path) %></h3>
                <p class="text-xs text-gray-500"><%= stage_description(@selected_path) %></p>
              </div>
            </div>
          </div>

          <!-- Transition button if transitions are available -->
          <%= if has_valid_transitions?(@selected_path) do %>
            <button
              type="button"
              phx-click="show_stage_transitions"
              class="inline-flex items-center px-3 py-1.5 border border-gray-300 shadow-sm text-xs font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
              </svg>
              Change Stage
            </button>
          <% else %>
            <div class="text-xs text-gray-400 font-medium">
              <%= lock_reason(@selected_path) %>
            </div>
          <% end %>
        </div>

        <!-- Progress indicator -->
        <div class="mt-3">
          <div class="flex items-center space-x-2">
            <div class="flex-1">
              <div class="flex items-center space-x-1">
                <!-- Planning Stage -->
                <div class={["w-3 h-3 rounded-full", if(@selected_path in ["polling"], do: "bg-blue-500", else: "bg-gray-300")]}></div>
                <div class={["flex-1 h-0.5", if(@selected_path in ["confirmed", "threshold"], do: "bg-gray-400", else: "bg-gray-200")]}></div>

                <!-- Confirmed Stage -->
                <div class={["w-3 h-3 rounded-full", if(@selected_path in ["confirmed", "threshold"], do: "bg-green-500", else: "bg-gray-300")]}></div>
                <div class={["flex-1 h-0.5", if(@selected_path in ["threshold"], do: "bg-gray-400", else: "bg-gray-200")]}></div>

                <!-- Threshold Stage -->
                <div class={["w-3 h-3 rounded-full", if(@selected_path in ["threshold"], do: stage_final_color(@selected_path), else: "bg-gray-300")]}></div>
              </div>
            </div>
            <div class="text-xs text-gray-500 ml-2">
              <%= progress_text(@selected_path) %>
            </div>
          </div>
        </div>
      </div>
    <% else %>
      <!-- Full version for new events or expanded edit mode -->
      <div class="bg-white rounded-xl border border-gray-200 p-6 mb-6 shadow-sm">
        <div class="mb-6">
          <div class="flex items-center justify-between">
            <div>
              <h2 class="text-xl font-semibold text-gray-900 mb-2">
                <%= if @mode == "compact" do %>
                  Change Event Type
                <% else %>
                  What type of event are you creating?
                <% end %>
              </h2>
              <p class="text-gray-600">Choose the setup that best matches your event planning needs.</p>
            </div>
            <%= if @mode == "compact" do %>
              <button
                type="button"
                phx-click="hide_stage_transitions"
                class="inline-flex items-center px-3 py-1.5 border border-gray-300 shadow-sm text-xs font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
              >
                <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
                Close
              </button>
            <% end %>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4" id="setup-path-selector" phx-hook="SetupPathSelector" data-selected-path={@selected_path}>
          <!-- Confirmed Event (Default) - Now First -->
          <label class="relative cursor-pointer group" title="Date is set, just collect RSVPs - ticketing available as free by default">
            <input
              type="radio"
              id="setup_path_confirmed"
              name="setup_path"
              value="confirmed"
              checked={@selected_path == "confirmed"}
              phx-click="select_setup_path"
              phx-value-path="confirmed"
              class="sr-only peer"
            />
            <div class={[
              "p-4 border-2 rounded-lg transition-all duration-300 hover:shadow-sm group-hover:scale-[1.01] min-h-[120px] flex flex-col",
              if(@selected_path == "confirmed", do: "border-green-500 bg-green-50 shadow-md", else: "border-gray-200 hover:border-gray-300")
            ]}>
              <div class="flex items-start space-x-3 flex-1">
                <div class="flex-shrink-0">
                  <div class={[
                    "w-10 h-10 rounded-lg flex items-center justify-center",
                    if(@selected_path == "confirmed", do: "bg-green-200", else: "bg-green-100")
                  ]}>
                    <svg class="w-5 h-5 text-green-600" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                    </svg>
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-base font-semibold text-gray-900 mb-1">✅ Confirmed Event</h3>
                  <p class="text-sm text-gray-600 mb-2">Date is set, just collect RSVPs</p>
                  <p class="text-xs text-gray-500">Free tickets by default. Add paid tickets if needed.</p>
                </div>
              </div>
            </div>
          </label>

          <!-- Planning Stage (Polling) -->
          <label class="relative cursor-pointer group" title="Let attendees vote on multiple date options">
            <input
              type="radio"
              id="setup_path_polling"
              name="setup_path"
              value="polling"
              checked={@selected_path == "polling"}
              phx-click="select_setup_path"
              phx-value-path="polling"
              class="sr-only peer"
            />
            <div class={[
              "p-4 border-2 rounded-lg transition-all duration-300 hover:shadow-sm group-hover:scale-[1.01] min-h-[120px] flex flex-col",
              if(@selected_path == "polling", do: "border-blue-500 bg-blue-50 shadow-md", else: "border-gray-200 hover:border-gray-300")
            ]}>
              <div class="flex items-start space-x-3 flex-1">
                <div class="flex-shrink-0">
                  <div class={[
                    "w-10 h-10 rounded-lg flex items-center justify-center",
                    if(@selected_path == "polling", do: "bg-blue-200", else: "bg-blue-100")
                  ]}>
                    <svg class="w-5 h-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M6 2a1 1 0 00-1 1v1H4a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2h-1V3a1 1 0 10-2 0v1H7V3a1 1 0 00-1-1zm0 5a1 1 0 000 2h8a1 1 0 100-2H6z" clip-rule="evenodd" />
                    </svg>
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-base font-semibold text-gray-900 mb-1">✨ Planning Stage</h3>
                  <p class="text-sm text-gray-600 mb-2">Let attendees vote on dates</p>
                  <p class="text-xs text-gray-500">Perfect when you have multiple date options and want community input.</p>
                </div>
              </div>
            </div>
          </label>

          <!-- Threshold Pre-Sale -->
          <label class="relative cursor-pointer group" title="Event only happens if enough people sign up - great for testing ideas">
            <input
              type="radio"
              id="setup_path_threshold"
              name="setup_path"
              value="threshold"
              checked={@selected_path == "threshold"}
              phx-click="select_setup_path"
              phx-value-path="threshold"
              class="sr-only peer"
            />
            <div class={[
              "p-4 border-2 rounded-lg transition-all duration-300 hover:shadow-sm group-hover:scale-[1.01] min-h-[120px] flex flex-col",
              if(@selected_path == "threshold", do: "border-orange-500 bg-orange-50 shadow-md", else: "border-gray-200 hover:border-gray-300")
            ]}>
              <div class="flex items-start space-x-3 flex-1">
                <div class="flex-shrink-0">
                  <div class={[
                    "w-10 h-10 rounded-lg flex items-center justify-center",
                    if(@selected_path == "threshold", do: "bg-orange-200", else: "bg-orange-100")
                  ]}>
                    <svg class="w-5 h-5 text-orange-600" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M3 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clip-rule="evenodd" />
                    </svg>
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <h3 class="text-base font-semibold text-gray-900 mb-1">🚦 Threshold Pre-Sale</h3>
                  <p class="text-sm text-gray-600 mb-2">Validate demand before committing</p>
                  <p class="text-xs text-gray-500">Event only happens if minimum signups reached.</p>
                </div>
              </div>
            </div>
          </label>
        </div>
      </div>
    <% end %>
    """
  end

  # ======== EXISTING EVENT FORM ========

  @doc """
  Renders an event form that can be used for both new and edit views.

  ## Examples
      <.event_form
        for={@changeset}
        form_data={@form_data}
        event={@event}
        is_virtual={@is_virtual}
        selected_venue_name={@selected_venue_name}
        selected_venue_address={@selected_venue_address}
        submit_label="Create Event"
        action={:new}
      />
  """
  attr :for, :map, required: true, doc: "the changeset for the event"
  attr :form_data, :map, required: true, doc: "the form data with field values"
  attr :event, :map, default: nil, doc: "the event to edit (nil for new)"
  attr :is_virtual, :boolean, required: true, doc: "whether the event is virtual"
  attr :selected_venue_name, :string, default: nil, doc: "the selected venue name"
  attr :selected_venue_address, :string, default: nil, doc: "the selected venue address"
  attr :submit_label, :string, default: "Submit", doc: "the submit button label"
  attr :cancel_path, :string, default: nil, doc: "path to redirect on cancel (edit only)"
  attr :action, :atom, required: true, values: [:new, :edit], doc: "whether this is a new or edit form"
  attr :show_all_timezones, :boolean, default: false, doc: "whether to show all timezones"
  attr :cover_image_url, :string, default: nil, doc: "the cover image URL"
  attr :external_image_data, :map, default: nil, doc: "external image data for Unsplash/TMDB attribution"
  attr :on_image_click, :string, default: nil, doc: "event name to trigger when clicking on the image picker"
  attr :id, :string, default: nil, doc: "unique id for the form element, required for hooks"
  attr :enable_date_polling, :boolean, default: false, doc: "whether date polling is enabled"
  attr :setup_path, :string, default: "confirmed", doc: "the selected setup path: polling, confirmed, or threshold"
  attr :mode, :string, default: "full", doc: "display mode: 'full' for new events, 'compact' for edit"
  attr :show_stage_transitions, :boolean, default: false, values: [true, false], doc: "whether to show full selector in edit mode"
  # Ticketing-related attributes
  attr :tickets, :list, default: [], doc: "list of existing tickets for the event"

  def event_form(assigns) do
    assigns = assign_new(assigns, :id, fn ->
      action_suffix = case Map.get(assigns, :action) do
        :new -> "new"
        :edit -> "edit"
        _ -> "default"
      end
      "event-form-#{action_suffix}"
    end)

    ~H"""
    <!-- Event Setup Path Selector -->
            <.event_setup_path_selector
          selected_path={Map.get(assigns, :setup_path, "confirmed")}
          mode={Map.get(assigns, :mode, "full")}
          show_stage_transitions={Map.get(assigns, :show_stage_transitions, false)}
        />

    <.form :let={f} for={@for} id={@id} phx-change="validate" phx-submit="submit" data-test-id="event-form">
      <!-- Responsive layout: Mobile stacked, Desktop two-column -->
      <div class="bg-white shadow-md rounded-lg p-4 sm:p-6 mb-6 border border-gray-200">
        <div class="grid grid-cols-1 xl:grid-cols-5 gap-6 lg:gap-8">

          <!-- Left Column: Cover Image & Theme (40% width = 2/5) -->
          <div class="xl:col-span-2 order-2 xl:order-1">
            <!-- Cover Image -->
            <div class="mb-6">
              <h2 class="text-lg font-semibold mb-3 text-gray-800">Cover Image</h2>
              <%= if is_nil(f[:cover_image_url].value) or f[:cover_image_url].value == "" do %>
                <button
                  type="button"
                  phx-click={JS.push(@on_image_click)}
                  class="w-full h-48 flex flex-col items-center justify-center border-2 border-dashed border-gray-300 rounded-lg hover:border-gray-400 transition-colors bg-gray-50"
                >
                  <svg class="w-12 h-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812-1.22A2 2 0 0118.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"></path>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"></path>
                  </svg>
                  <p class="mt-2 text-sm text-gray-600">Click to add a cover image</p>
                </button>
              <% else %>
                <div class="relative rounded-lg overflow-hidden h-48 bg-gray-100">
                  <img src={f[:cover_image_url].value} alt="Cover image" class="w-full h-full object-cover" />
                  <div class="absolute inset-0 flex items-center justify-center bg-black bg-opacity-0 hover:bg-opacity-30 transition-all">
                    <button
                      type="button"
                      phx-click={JS.push(@on_image_click)}
                      class="bg-white text-gray-800 px-4 py-2 rounded-lg shadow-sm opacity-0 hover:opacity-100 transition-opacity transform translate-y-2 hover:translate-y-0"
                    >
                      Change Image
                    </button>
                  </div>
                </div>
              <% end %>

              <%= if @external_image_data do %>
                <div class="mt-2 text-xs text-gray-500">
                  <%= if @external_image_data["source"] == "unsplash" && @external_image_data["photographer_name"] do %>
                    Photo by <a href={@external_image_data["photographer_url"]} target="_blank" rel="noopener noreferrer" class="underline"><%= @external_image_data["photographer_name"] %></a> on <a href="https://unsplash.com" target="_blank" rel="noopener noreferrer" class="underline">Unsplash</a>
                  <% end %>
                  <%= if @external_image_data["source"] == "tmdb" && @external_image_data["url"] do %>
                    Image from <a href="https://www.themoviedb.org/" target="_blank" rel="noopener noreferrer" class="underline">TMDB</a>
                  <% end %>
                </div>
              <% end %>

              <!-- Hidden fields for image data -->
              <%= hidden_input f, :cover_image_url %>
              <%= if @external_image_data do %>
                <% encoded_data =
                  if is_map(@external_image_data), do: Jason.encode!(@external_image_data), else: @external_image_data || "" %>
                <%= hidden_input f, :external_image_data, value: encoded_data %>
              <% end %>
            </div>

            <!-- Theme Selection -->
            <div>
              <h2 class="text-lg font-semibold mb-3 text-gray-800">Event Theme</h2>
              <select
                name="event[theme]"
                id={f[:theme].id}
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors text-sm"
              >
                <%= for theme <- EventasaurusWeb.ThemeComponents.available_themes() do %>
                  <option value={theme.value} selected={f[:theme].value == theme.value || f[:theme].value == String.to_atom(theme.value)}>
                    <%= theme.label %> - <%= theme.description %>
                  </option>
                <% end %>
              </select>
              <p class="mt-1 text-xs text-gray-500">
                Customize your event page appearance
              </p>
            </div>
          </div>

          <!-- Right Column: Form Fields (60% width = 3/5) -->
          <div class="xl:col-span-3 order-1 xl:order-2">
            <!-- Event Title (prominent) -->
            <div class="mb-4">
              <.input field={f[:title]} type="text" label="Event Title" required class="text-lg" />
            </div>

            <!-- Date & Time (compact) -->
            <div class="mb-4">
              <h3 class="text-sm font-semibold text-gray-700 mb-2">When</h3>

              <!-- Hidden input for date polling - controlled by setup path selector -->
              <input type="hidden" name="event[enable_date_polling]" value={if @enable_date_polling, do: "true", else: "false"} />

              <%= if @enable_date_polling do %>
                <!-- Time inputs for polling -->
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3" phx-hook="TimeSync" id={"time-sync-#{@id}"}>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Start Time</label>
                    <.time_select
                      id={"#{@id}-start_time"}
                      name="event[start_time]"
                      value={Map.get(@form_data, "start_time", "")}
                      required
                      data-role="start-time"
                      class="text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">End Time</label>
                    <.time_select
                      id={"#{@id}-ends_time"}
                      name="event[ends_time]"
                      value={Map.get(@form_data, "ends_time", "")}
                      data-role="end-time"
                      class="text-sm"
                    />
                  </div>
                </div>

                <!-- Calendar component for date selection -->
                <div class="mb-4" phx-hook="CalendarFormSync" id={"calendar-form-sync-#{@id}"}>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Select dates for polling
                  </label>
                  <p class="text-xs text-gray-500 mb-3">
                    Click on calendar dates to include them in the poll. Attendees will vote on these dates.
                  </p>
                  <.live_component
                    module={CalendarComponent}
                    id={"#{@id}-calendar"}
                    selected_dates={parse_selected_dates(@form_data)}
                  />
                  <!-- Hidden fields to store selected dates -->
                  <input type="hidden" name="event[selected_poll_dates]" id={"#{@id}-selected-dates"} value={encode_selected_dates(@form_data)} />
                  <!-- Validation error display -->
                  <%= if f[:selected_poll_dates] && f[:selected_poll_dates].errors != [] do %>
                    <div class="mt-2 text-sm text-red-600" phx-feedback-for="event[selected_poll_dates]">
                      <%= Enum.map(f[:selected_poll_dates].errors, fn {msg, _} -> msg end) |> Enum.join(", ") %>
                    </div>
                  <% end %>
                </div>

                <!-- Polling deadline input (simplified to date + time dropdowns) -->
                <div class="mb-4" phx-hook="DateTimeSync" id={"polling-deadline-sync-#{@id}"}>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    Voting Deadline
                  </label>
                  <div class="grid grid-cols-2 gap-3">
                    <div>
                      <.date_input
                        id={"#{@id}-polling_deadline_date"}
                        name="event[polling_deadline_date]"
                        value={get_polling_deadline_date(@form_data)}
                        required
                        data-role="polling-deadline-date"
                      />
                    </div>
                    <div>
                      <.time_select
                        id={"#{@id}-polling_deadline_time"}
                        name="event[polling_deadline_time]"
                        value={get_polling_deadline_time(@form_data)}
                        data-role="polling-deadline-time"
                      />
                    </div>
                  </div>
                  <p class="text-xs text-gray-500 mt-1">
                    When should voting close for date selection?
                  </p>
                  <!-- Hidden field to store the combined datetime -->
                  <input type="hidden" name="event[polling_deadline]" id={"#{@id}-polling_deadline"} value={format_polling_deadline_for_input(@form_data)} data-role="polling-deadline" />
                </div>
              <% else %>
                <!-- Traditional date range selection -->
                <div phx-hook="DateTimeSync" id="date-time-sync-hook">
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
                      <.date_input
                        id={"#{@id}-start_date"}
                        name="event[start_date]"
                        value={Map.get(@form_data, "start_date", "")}
                        required
                        data-role="start-date"
                        class="text-sm"
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">Start Time</label>
                      <.time_select
                        id={"#{@id}-start_time"}
                        name="event[start_time]"
                        value={Map.get(@form_data, "start_time", "")}
                        required
                        data-role="start-time"
                        class="text-sm"
                      />
                    </div>
                  </div>
                  <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
                      <.date_input
                        id={"#{@id}-ends_date"}
                        name="event[ends_date]"
                        value={Map.get(@form_data, "ends_date", "")}
                        data-role="end-date"
                        class="text-sm"
                      />
                    </div>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">End Time</label>
                      <.time_select
                        id={"#{@id}-ends_time"}
                        name="event[ends_time]"
                        value={Map.get(@form_data, "ends_time", "")}
                        data-role="end-time"
                        class="text-sm"
                      />
                    </div>
                  </div>
                </div>
              <% end %>

              <div>
                <label for={f[:timezone].id} class="block text-sm font-medium text-gray-700 mb-1">Timezone</label>
                <.timezone_select
                  field={f[:timezone]}
                  selected={Map.get(@form_data, "timezone", nil)}
                  show_all={@show_all_timezones}
                  class="text-sm"
                />
                <p class="mt-1 text-xs text-gray-500">Auto-detected if available</p>
              </div>

              <%= if @enable_date_polling do %>
                <div class="p-3 bg-blue-50 border border-blue-200 rounded-lg mt-3">
                  <div class="flex items-start">
                    <svg class="w-4 h-4 text-blue-600 mt-0.5 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M13 2a1 1 0 00-1-1H8a1 1 0 00-1 1v1H5a1 1 0 000 2h1v10a2 2 0 002 2h4a2 2 0 002-2V5h1a1 1 0 100-2h-2V2zM9 4h2v1H9V4z" clip-rule="evenodd" />
                    </svg>
                    <div>
                      <h4 class="text-sm font-medium text-blue-800">Calendar Polling Mode</h4>
                      <p class="text-xs text-blue-700 mt-1">
                        Use the calendar above to select specific dates for polling. Attendees will vote on the selected dates.
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>

              <!-- Hidden fields for combined datetime values -->
              <input type="hidden" name="event[start_at]" id={"#{@id}-start_at"} value={format_datetime_for_input(@event, :start_at)} />
              <input type="hidden" name="event[ends_at]" id={"#{@id}-ends_at"} value={format_datetime_for_input(@event, :ends_at)} />
            </div>

            <!-- Location -->
            <div class="mb-4">
              <h3 class="text-sm font-semibold text-gray-700 mb-2">Where</h3>

              <div class="flex items-center mb-2">
                <label class="flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    name="event[is_virtual]"
                    value="true"
                    checked={Map.get(@form_data, "is_virtual", false) == true}
                    phx-click="toggle_virtual"
                    class="h-4 w-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
                  />
                  <span class="ml-2 text-sm">Virtual/online event</span>
                </label>
              </div>

              <%= if !@is_virtual do %>
                <div>
                  <!-- Recent Locations Section -->
                  <%= if assigns[:recent_locations] && length(@recent_locations) > 0 do %>
                    <div class="mb-2">
                      <button
                        type="button"
                        phx-click="toggle_recent_locations"
                        class="flex items-center text-xs text-gray-600 hover:text-gray-800 mb-2"
                      >
                        <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                        Recent Locations (<%= length(@recent_locations) %>)
                        <svg class={"w-3 h-3 ml-1 transition-transform #{if @show_recent_locations, do: "rotate-180", else: ""}"} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                        </svg>
                      </button>

                      <%= if @show_recent_locations do %>
                        <div class="bg-gray-50 border border-gray-200 rounded-md p-2 mb-2 max-h-48 overflow-y-auto">
                          <%= for location <- @filtered_recent_locations do %>
                            <button
                              type="button"
                              phx-click="select_recent_location"
                              phx-value-location={Jason.encode!(location)}
                              class="w-full text-left p-2 hover:bg-white hover:shadow-sm rounded border-b border-gray-100 last:border-b-0"
                            >
                              <div class="flex items-start justify-between">
                                <div class="flex-1 min-w-0">
                                  <div class="text-sm font-medium text-gray-900 truncate">
                                    <%= if location.virtual_venue_url do %>
                                      <svg class="w-4 h-4 inline mr-1 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 10l4.553-2.276A1 1 0 0121 8.618v6.764a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
                                      </svg>
                                      Virtual Meeting
                                    <% else %>
                                      <svg class="w-4 h-4 inline mr-1 text-blue-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                      </svg>
                                      <%= location.name %>
                                    <% end %>
                                  </div>
                                  <%= if location.address do %>
                                    <div class="text-xs text-gray-500 truncate"><%= location.address %></div>
                                  <% end %>
                                  <%= if location.virtual_venue_url do %>
                                    <div class="text-xs text-gray-500 truncate"><%= location.virtual_venue_url %></div>
                                  <% end %>
                                </div>
                                <div class="ml-2 flex-shrink-0">
                                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
                                    <%= location.usage_count %>x
                                  </span>
                                </div>
                              </div>
                            </button>
                          <% end %>

                          <%= if length(@filtered_recent_locations) == 0 do %>
                            <div class="text-center py-3 text-gray-500 text-sm">
                              No matching recent locations found
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <input
                    type="text"
                    id={"venue-search-#{if @action == :new, do: "new", else: "edit"}"}
                    placeholder="Search for venue or address..."
                    phx-hook="VenueSearchWithFiltering"
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
                  />
                  <!-- Hidden venue fields remain the same -->
                  <input type="hidden" name="event[venue_name]" id={"venue-name-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_name", "")} />
                  <input type="hidden" name="event[venue_address]" id={"venue-address-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_address", "")} />
                  <input type="hidden" name="event[venue_city]" id={"venue-city-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_city", "")} />
                  <input type="hidden" name="event[venue_state]" id={"venue-state-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_state", "")} />
                  <input type="hidden" name="event[venue_country]" id={"venue-country-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_country", "")} />
                  <input type="hidden" name="event[venue_latitude]" id={"venue-lat-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_latitude", "")} />
                  <input type="hidden" name="event[venue_longitude]" id={"venue-lng-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_longitude", "")} />
                </div>

                <!-- Selected venue display -->
                <%= if @selected_venue_name do %>
                  <div class="mt-2 p-2 bg-blue-50 border border-blue-300 rounded-md text-sm">
                    <div class="font-medium text-blue-700"><%= @selected_venue_name %></div>
                    <div class="text-blue-600 text-xs"><%= @selected_venue_address %></div>
                  </div>
                <% end %>
              <% else %>
                <div>
                  <.input field={f[:virtual_venue_url]} type="text" label="Meeting URL" placeholder="https://..." class="text-sm" />

                  <!-- Quick Create Virtual Meeting Options -->
                  <div class="mt-3 flex gap-2">
                    <button
                      type="button"
                      phx-click="create_zoom_meeting"
                      class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                    >
                      <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M1.5 6A1.5 1.5 0 0 1 3 4.5h3.879a1.5 1.5 0 0 1 1.06.44l2.122 2.12a1.5 1.5 0 0 0 1.06.44H21a1.5 1.5 0 0 1 1.5 1.5v10.5A1.5 1.5 0 0 1 21 21H3a1.5 1.5 0 0 1-1.5-1.5V6z"/>
                      </svg>
                      Create Zoom Meeting
                    </button>

                    <button
                      type="button"
                      phx-click="create_google_meet"
                      class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                    >
                      <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M22 12c0-5.523-4.477-10-10-10S2 6.477 2 12c0 4.991 3.657 9.128 8.438 9.878v-6.987h-2.54V12h2.54V9.797c0-2.506 1.492-3.89 3.777-3.89 1.094 0 2.238.195 2.238.195v2.46h-1.26c-1.243 0-1.63.771-1.63 1.562V12h2.773l-.443 2.89h-2.33v6.988C18.343 21.128 22 16.991 22 12z"/>
                      </svg>
                      Create Google Meet
                    </button>
                  </div>

                  <p class="text-xs text-gray-500 mt-2">
                    Or enter a custom virtual meeting URL above
                  </p>
                </div>
              <% end %>
            </div>

            <!-- Description & Details -->
            <div class="mb-4">
              <.input field={f[:description]} type="textarea" label="Description" class="text-sm" />
            </div>

            <!-- Additional Options (compact) -->
            <div class="mb-4">
              <details class="group">
                <summary class="flex items-center justify-between cursor-pointer text-sm font-medium text-gray-700 mb-2">
                  <span>Additional Options</span>
                  <svg class="w-4 h-4 text-gray-500 group-open:rotate-180 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                  </svg>
                </summary>
                <div class="space-y-3 pl-4 border-l-2 border-gray-100">
                  <.input field={f[:tagline]} type="text" label="Tagline" class="text-sm" />
                  <.input field={f[:visibility]} type="select" label="Visibility" options={[{"Public", "public"}, {"Private", "private"}]} class="text-sm" />
                </div>
              </details>
            </div>

            <!-- Ticketing Section - Only show for confirmed and threshold events -->
            <%= if Map.get(@form_data, "setup_path", "confirmed") != "polling" do %>
              <div class="mb-4">
                <h3 class="text-sm font-semibold text-gray-700 mb-3">Ticketing</h3>

                <!-- Hidden input for ticketing - controlled by setup path selector -->
                <input type="hidden" name="event[is_ticketed]" value={if Map.get(@form_data, "is_ticketed", false) in [true, "true"], do: "true", else: "false"} />

                <!-- Threshold-specific fields -->
                <%= if Map.get(@form_data, "setup_path", "confirmed") == "threshold" do %>
                  <div class="mb-4 p-4 bg-orange-50 border border-orange-200 rounded-lg">
                    <h4 class="text-sm font-medium text-orange-800 mb-3">Threshold Pre-Sale Settings</h4>
                    <div class="space-y-3">
                      <div>
                        <label for="threshold_count" class="block text-sm font-medium text-gray-700 mb-1">
                          Minimum Attendees Required
                        </label>
                        <input
                          type="number"
                          id="threshold_count"
                          name="event[threshold_count]"
                          value={Map.get(@form_data, "threshold_count", "")}
                          min="1"
                          placeholder="e.g., 50"
                          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-orange-500 focus:ring-orange-500 text-sm"
                        />
                        <p class="text-xs text-gray-500 mt-1">
                          Event will only be confirmed if this many people buy tickets
                        </p>
                      </div>
                    </div>
                  </div>
                  <!-- Hidden field for requires_threshold -->
                  <input type="hidden" name="event[requires_threshold]" value="true" />
                <% else %>
                  <!-- Hidden field for requires_threshold -->
                  <input type="hidden" name="event[requires_threshold]" value="false" />
                <% end %>

                <%= if @setup_path in ["confirmed", "threshold"] do %>
                <!-- Tickets Management Section -->
                <div class="space-y-4" id="tickets-section">
                  <div class="flex items-center justify-between">
                    <h4 class="text-sm font-medium text-gray-700">Ticket Types</h4>
                    <button
                      type="button"
                      phx-click="add_ticket_form"
                      class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded-md text-indigo-700 bg-indigo-100 hover:bg-indigo-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      <svg class="w-4 h-4 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                      </svg>
                      Add Ticket
                    </button>
                  </div>

                  <!-- Existing Tickets List -->
                  <%= if assigns[:tickets] && length(@tickets) > 0 do %>
                    <div class="space-y-3">
                      <%= for {ticket, index} <- Enum.with_index(@tickets) do %>
                        <div class="border border-gray-200 rounded-lg p-4 bg-white shadow-sm hover:shadow-md transition-shadow">
                          <div class="flex items-start justify-between">
                            <div class="flex-1">
                              <div class="flex items-center space-x-2 mb-1">
                                <h5 class="text-sm font-semibold text-gray-900"><%= ticket.title %></h5>
                                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800">
                                  <%= if ticket.base_price_cents do
                                        format_currency(ticket.base_price_cents, Map.get(ticket, :currency, "usd"))
                                      else
                                        "Flexible"
                                      end %>
                                </span>
                              </div>
                              <%= if ticket.description && ticket.description != "" do %>
                                <p class="text-xs text-gray-600 mb-2"><%= ticket.description %></p>
                              <% end %>
                              <div class="flex items-center flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500">
                                <span class="flex items-center">
                                  <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
                                  </svg>
                                  <%= ticket.quantity %> available
                                </span>
                                <%= if ticket.starts_at do %>
                                  <span class="flex items-center">
                                    <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                    </svg>
                                    Sale starts: <%= Calendar.strftime(ticket.starts_at, "%m/%d %I:%M %p") %>
                                  </span>
                                <% end %>
                                <%= if ticket.tippable do %>
                                  <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
                                    Tips enabled
                                  </span>
                                <% end %>
                              </div>
                            </div>
                            <div class="flex space-x-2 ml-4">
                              <button
                                type="button"
                                phx-click="edit_ticket"
                                phx-value-id={Map.get(ticket, :id, index)}
                                class="inline-flex items-center px-2 py-1 border border-gray-300 rounded text-xs font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                              >
                                <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                                </svg>
                                Edit
                              </button>
                              <button
                                type="button"
                                phx-click="remove_ticket"
                                phx-value-id={Map.get(ticket, :id, index)}
                                class="inline-flex items-center px-2 py-1 border border-red-300 rounded text-xs font-medium text-red-700 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                              >
                                <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                </svg>
                                Remove
                              </button>
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="text-center py-6 text-gray-500">
                      <svg class="mx-auto h-8 w-8 text-gray-400 mb-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
                      </svg>
                      <%= if @setup_path == "confirmed" do %>
                        <p class="text-sm">Free tickets</p>
                        <p class="text-xs text-gray-400 mt-1">No paid tickets required. Click "Add Ticket" to create paid options if needed.</p>
                      <% else %>
                        <p class="text-sm">No tickets created yet</p>
                        <p class="text-xs text-gray-400 mt-1">Click "Add Ticket" to create your first ticket type</p>
                      <% end %>
                    </div>
                  <% end %>

                  <!-- Help text for ticketing -->
                  <div class="text-xs text-gray-500 p-3 bg-blue-50 border border-blue-200 rounded-lg">
                    <div class="flex items-start">
                      <svg class="w-4 h-4 text-blue-600 mt-0.5 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
                      </svg>
                      <div>
                        <p class="font-medium text-blue-800">Ticketing Tips</p>
                        <ul class="mt-1 text-blue-700 space-y-1">
                          <li>• Create different ticket types for early bird, general admission, VIP, etc.</li>
                          <li>• Set sale windows to create urgency and manage demand</li>
                          <li>• Enable tips to increase revenue from supporters</li>
                        </ul>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Action Buttons -->
      <div class={@action == :edit && "flex flex-col sm:flex-row sm:justify-between gap-3 sm:gap-0" || "flex justify-end"}>
        <%= if @action == :edit && @cancel_path do %>
          <.link navigate={@cancel_path} class="inline-flex items-center px-4 py-3 sm:py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 transition-colors duration-200 touch-manipulation min-h-[44px] sm:min-h-[auto]">
            Cancel
          </.link>
        <% end %>
        <button type="submit" class="inline-flex items-center px-4 py-3 sm:py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors duration-200 touch-manipulation min-h-[44px] sm:min-h-[auto]">
          <%= @submit_label %>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 ml-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
        </button>
      </div>
    </.form>
    """
  end

  # Helper function to format datetime for hidden input fields
  defp format_datetime_for_input(event, field) when is_map(event) do
    case Map.get(event, field) do
      %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
      nil -> ""
      _ -> ""
    end
  end

  defp format_datetime_for_input(_, _), do: ""

  # Helper functions for calendar date selection
  defp parse_selected_dates(form_data) do
    case Map.get(form_data, "selected_poll_dates") do
      nil -> []
      "" -> []
      dates_string when is_binary(dates_string) ->
        dates_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort()
      dates when is_list(dates) -> dates
      _ -> []
    end
  end

  defp encode_selected_dates(form_data) do
    case Map.get(form_data, "selected_poll_dates") do
      nil -> ""
      [] -> ""
      dates when is_list(dates) ->
        dates
        |> Enum.map(fn
          %Date{} = date -> Date.to_iso8601(date)
          date_str when is_binary(date_str) -> date_str
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.join(",")
      dates_string when is_binary(dates_string) -> dates_string
      _ -> ""
    end
  end

  defp get_polling_deadline_date(form_data) do
    case Map.get(form_data, "polling_deadline") do
      %DateTime{} = datetime ->
        Date.to_iso8601(DateTime.to_date(datetime))
      date_string when is_binary(date_string) and date_string != "" ->
        # If it's already a date string, extract just the date part
        case String.split(date_string, "T") do
          [date_part | _] -> date_part
          _ -> date_string
        end
      _ ->
        # Default to one week from today
        Date.add(Date.utc_today(), 7) |> Date.to_iso8601()
    end
  end

  defp get_polling_deadline_time(form_data) do
    case Map.get(form_data, "polling_deadline") do
      %DateTime{} = datetime ->
        # Format time as HH:MM for the time_select component
        time = DateTime.to_time(datetime)
        "#{String.pad_leading(Integer.to_string(time.hour), 2, "0")}:#{String.pad_leading(Integer.to_string(time.minute), 2, "0")}"
      iso when is_binary(iso) and iso != "" ->
        case String.split(iso, "T") do
          [_date, time_part] ->
            # Strip seconds/timezone → "HH:MM"
            String.slice(time_part, 0, 5)
          _ ->
            "22:00"
        end
      _ ->
        # Default to 10 PM
        "22:00"
    end
  end

  defp format_polling_deadline_for_input(form_data) do
    case Map.get(form_data, "polling_deadline") do
      %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
      iso when is_binary(iso) -> iso
      _ -> ""
    end
  end

  # ======== STAGE INDICATOR HELPERS ========

  defp stage_icon_class(path) do
    base_classes = "w-10 h-10 rounded-lg flex items-center justify-center"
    case path do
      "polling" -> "#{base_classes} bg-blue-100"
      "confirmed" -> "#{base_classes} bg-green-100"

      "threshold" -> "#{base_classes} bg-orange-100"
      _ -> "#{base_classes} bg-gray-100"
    end
  end

  defp stage_icon(path) do
    case path do
      "polling" ->
        """
        <svg class="w-5 h-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M6 2a1 1 0 00-1 1v1H4a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2h-1V3a1 1 0 10-2 0v1H7V3a1 1 0 00-1-1zm0 5a1 1 0 000 2h8a1 1 0 100-2H6z" clip-rule="evenodd" />
        </svg>
        """
      "confirmed" ->
        """
        <svg class="w-5 h-5 text-green-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
        </svg>
        """

      "threshold" ->
        """
        <svg class="w-5 h-5 text-orange-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M3 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zm0 4a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z" clip-rule="evenodd" />
        </svg>
        """
      _ ->
        """
        <svg class="w-5 h-5 text-gray-600" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
        </svg>
        """
    end
  end

  defp stage_title(path) do
    case path do
      "polling" -> "Planning Stage"
      "confirmed" -> "Confirmed Event"

      "threshold" -> "Threshold Pre-Sale"
      _ -> "Unknown Stage"
    end
  end

  defp stage_description(path) do
    case path do
      "polling" -> "Collecting date votes from attendees"
      "confirmed" -> "Event date is set, collecting RSVPs"

      "threshold" -> "Pre-sale validation in progress"
      _ -> "Status unknown"
    end
  end

  defp has_valid_transitions?(path) do
    case path do
      "polling" -> true  # Can go to confirmed or threshold
      "confirmed" -> true  # Can go to threshold
      "threshold" -> false  # No further transitions (managed by system)
      _ -> false
    end
  end

  defp lock_reason(path) do
    case path do

      "threshold" -> "Pre-sale locked"
      _ -> "No changes"
    end
  end

  defp stage_final_color(path) do
    case path do

      "threshold" -> "bg-orange-500"
      _ -> "bg-gray-300"
    end
  end

  defp progress_text(path) do
    case path do
      "polling" -> "Step 1 of 3"
      "confirmed" -> "Step 2 of 3"
      "threshold" -> "Final Stage"
      _ -> "Unknown"
    end
  end

end
