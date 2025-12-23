defmodule EventasaurusWeb.EventComponents do
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.Helpers.CurrencyHelpers
  import EventasaurusWeb.Helpers.ImageUrlHelper
  alias EventasaurusWeb.TimezoneHelpers
  alias EventasaurusApp.DateTimeHelper
  alias Eventasaurus.Integrations.Cinegraph
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
            <% currencies = @tickets |> Enum.map(&(&1.currency || "usd")) |> Enum.uniq %>
            <%= if length(currencies) == 1 do %>
              Prices in <%= String.upcase(hd(currencies)) %>
            <% else %>
              Prices vary by ticket
            <% end %>
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
                  <% currency = case Enum.find(@tickets, &(Map.get(@selected_tickets, &1.id, 0) > 0)) do
                    nil -> "usd"
                    ticket -> Map.get(ticket, :currency, "usd")
                  end %>
                  <%= format_currency(total_amount, currency) %>
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
          "fixed" -> acc + ticket.base_price_cents * quantity
          # Use minimum for calculation
          "flexible" -> acc + ticket.minimum_price_cents * quantity
          "dynamic" -> acc + ticket.base_price_cents * quantity
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

  attr :mode, :string,
    default: "full",
    doc: "display mode: 'full' for new events, 'compact' for edit"

  attr :show_stage_transitions, :boolean,
    default: false,
    values: [true, false],
    doc: "whether to show full selector in edit mode"

  attr :date_certainty, :string, default: "confirmed", doc: "date selection status"
  attr :venue_certainty, :string, default: "confirmed", doc: "venue selection status"
  attr :participation_type, :string, default: "free", doc: "participation type"

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

          <!-- Status display for confirmed events, transition button for others -->
          <%= case @selected_path do %>
            <% "confirmed" -> %>
              <div class="inline-flex items-center px-3 py-1.5 bg-green-100 border border-green-300 text-xs font-medium rounded-md text-green-800">
                <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                Event Confirmed
              </div>
            <% "threshold" -> %>
              <div class="inline-flex items-center px-3 py-1.5 bg-purple-100 border border-purple-300 text-xs font-medium rounded-md text-purple-800">
                <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
                Validating Interest
              </div>
            <% path when path in ["polling", "draft"] -> %>
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
            <% _ -> %>
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

  attr :action, :atom,
    required: true,
    values: [:new, :edit],
    doc: "whether this is a new or edit form"

  attr :show_all_timezones, :boolean, default: false, doc: "whether to show all timezones"
  attr :cover_image_url, :string, default: nil, doc: "the cover image URL"

  attr :external_image_data, :map,
    default: nil,
    doc: "external image data for Unsplash/TMDB attribution"

  attr :on_image_click, :string,
    default: nil,
    doc: "event name to trigger when clicking on the image picker"

  attr :id, :string, default: nil, doc: "unique id for the form element, required for hooks"
  # Legacy enable_date_polling attribute removed - using generic polling system
  attr :setup_path, :string,
    default: "confirmed",
    doc: "the selected setup path: polling, confirmed, or threshold"

  attr :mode, :string,
    default: "full",
    doc: "display mode: 'full' for new events, 'compact' for edit"

  attr :show_stage_transitions, :boolean,
    default: false,
    values: [true, false],
    doc: "whether to show full selector in edit mode"

  # Ticketing-related attributes
  attr :tickets, :list, default: [], doc: "list of existing tickets for the event"
  # Recent locations attributes
  attr :recent_locations, :list, default: [], doc: "list of recent locations for the user"

  attr :show_recent_locations, :boolean,
    default: false,
    doc: "whether to show the recent locations dropdown"

  attr :filtered_recent_locations, :list,
    default: [],
    doc: "filtered list of recent locations based on search"

  attr :rich_external_data, :map,
    default: %{},
    doc: "rich data imported from external APIs (TMDB, Spotify, etc.)"

  attr :user_groups, :list, default: [], doc: "list of groups the user can assign the event to"
  attr :date_certainty, :string, default: "confirmed", doc: "date selection status"
  attr :venue_certainty, :string, default: "confirmed", doc: "venue selection status"
  attr :participation_type, :string, default: "free", doc: "participation type"

  def event_form(assigns) do
    assigns =
      assign_new(assigns, :id, fn ->
        action_suffix =
          case Map.get(assigns, :action) do
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
          date_certainty={Map.get(assigns, :date_certainty, "confirmed")}
          venue_certainty={Map.get(assigns, :venue_certainty, "confirmed")}
          participation_type={Map.get(assigns, :participation_type, "free")}
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
                <%!-- PHASE 2 TODO: Remove resolve() wrapper after database migration normalizes URLs --%>
                <div class="relative rounded-lg overflow-hidden h-48 bg-gray-100">
                  <img src={resolve(f[:cover_image_url].value)} alt="Cover image" class="w-full h-full object-cover" />
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

              <!-- Image attribution -->
              <.image_attribution external_image_data={@external_image_data} />

              <!-- Hidden fields for image data -->
              <%= hidden_input f, :cover_image_url, value: Phoenix.HTML.Form.input_value(f, :cover_image_url) || @cover_image_url %>
              <%= if @external_image_data || Phoenix.HTML.Form.input_value(f, :external_image_data) do %>
                <% encoded_data = case Phoenix.HTML.Form.input_value(f, :external_image_data) do
                  nil -> if is_map(@external_image_data), do: safe_json_encode(@external_image_data), else: ""
                  data when is_map(data) -> safe_json_encode(data)
                  data -> data
                end %>
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

            <!-- Rich Data Import Section -->
            <div class="mt-6">
              <h2 class="text-lg font-semibold mb-3 text-gray-800">Rich Data</h2>

              <!-- Current rich data display -->
              <%= if @rich_external_data && @rich_external_data != %{} do %>
                <div class="mb-4">
                  <div class="bg-green-50 border border-green-200 rounded-lg p-4">
                    <div class="flex items-start justify-between">
                      <div class="flex items-start">
                        <svg class="w-5 h-5 text-green-600 mt-0.5 mr-3 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                        </svg>
                        <div class="flex-1">
                          <h4 class="text-sm font-semibold text-green-800">Rich Data Imported</h4>

                          <!-- TMDB Data Display -->
                          <%= if @rich_external_data["title"] do %>
                            <div class="mt-2">
                              <p class="text-sm font-medium text-green-900"><%= @rich_external_data["title"] %></p>
                              <div class="flex items-center gap-2 mt-1">
                                <%= if @rich_external_data["metadata"] && @rich_external_data["metadata"]["release_date"] do %>
                                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                    <%= String.slice(@rich_external_data["metadata"]["release_date"], 0, 4) %>
                                  </span>
                                <% end %>
                                <%= if @rich_external_data["type"] do %>
                                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                                    <%= String.capitalize(to_string(@rich_external_data["type"])) %>
                                  </span>
                                <% end %>
                                <%= if @rich_external_data["provider"] do %>
                                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                                    <%= String.upcase(to_string(@rich_external_data["provider"])) %>
                                  </span>
                                <% end %>
                              </div>
                              <%= if @rich_external_data["description"] && String.length(@rich_external_data["description"]) > 0 do %>
                                <p class="text-xs text-green-700 mt-2 line-clamp-2"><%= @rich_external_data["description"] %></p>
                              <% end %>
                            </div>
                          <% else %>
                            <p class="text-xs text-green-700 mt-1">External data successfully imported</p>
                          <% end %>
                        </div>
                      </div>

                      <!-- Clear/Remove button -->
                      <button
                        type="button"
                        phx-click="clear_rich_data"
                        class="text-green-600 hover:text-green-800 transition-colors ml-2"
                        title="Remove imported data"
                      >
                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>

              <!-- Import button -->
              <button
                type="button"
                phx-click="show_rich_data_import"
                class="w-full flex items-center justify-center px-4 py-2 border border-gray-300 rounded-lg text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 transition-colors"
              >
                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                </svg>
                <%= if @rich_external_data && @rich_external_data != %{} do %>
                  Change Rich Data
                <% else %>
                  Import Rich Data
                <% end %>
              </button>

              <p class="mt-2 text-xs text-gray-500">
                Import comprehensive details from movies, TV shows, music, and more
              </p>

              <!-- Hidden field for rich data -->
              <%= if @rich_external_data do %>
                <% encoded_rich_data =
                  if is_map(@rich_external_data), do: safe_json_encode(@rich_external_data), else: @rich_external_data || "{}" %>
                <%= hidden_input f, :rich_external_data, value: encoded_rich_data %>
              <% end %>
            </div>
          </div>

          <!-- Right Column: Form Fields (60% width = 3/5) -->
          <div class="xl:col-span-3 order-1 xl:order-2">
            <!-- Event Title (prominent) -->
            <div class="mb-4">
              <.input field={f[:title]} type="text" label="Event Title" required class="text-lg" />
            </div>

            <!-- Group Assignment -->
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                Assign to Group (optional)
              </label>
              <select
                name="event[group_id]"
                class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
              >
                <option value="">No group - personal event</option>
                <%= for group <- @user_groups do %>
                  <option value={group.id} selected={to_string(group.id) == to_string(@form_data["group_id"] || "")}>
                    <%= group.name %>
                  </option>
                <% end %>
              </select>
              <p class="mt-1 text-xs text-gray-500">Events assigned to groups will appear on the group's calendar and be visible to all members.</p>
            </div>

            <!-- Date & Time -->
            <div class="mb-4">
              <div class="mb-4">
                <label class="block text-sm font-medium text-gray-700 mb-2">When is your event?</label>
                <select 
                  id="date-certainty-select" 
                  name="event[date_certainty]" 
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
                  phx-change="update_date_certainty"
                >
                  <option value="confirmed" selected={Map.get(assigns, :date_certainty, "confirmed") == "confirmed"}>✓ I have a specific date</option>
                  <option value="polling" selected={Map.get(assigns, :date_certainty, "confirmed") == "polling"}>? Not sure - let attendees vote</option>
                  <option value="planning" selected={Map.get(assigns, :date_certainty, "confirmed") == "planning"}>○ Still planning - date TBD</option>
                </select>
                
                <!-- Error display for date certainty -->
                <.changeset_error :if={@for} changeset={@for} field={:date_certainty} class="mt-2" />
                
                <!-- Conditional: Polling Fields -->
                <%= if Map.get(assigns, :date_certainty, "confirmed") == "polling" do %>
                  <div class="mt-4 p-4 bg-blue-50 rounded-lg space-y-4">
                    <div>
                      <label class="text-sm font-medium text-gray-700">When should voting end?</label>
                      <input type="datetime-local" name="event[polling_deadline]" class="mt-1 w-full px-3 py-2 border border-gray-300 rounded-lg text-sm">
                      <p class="text-xs text-gray-500 mt-1">Attendees can vote on dates until this deadline</p>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Date/Time Pickers - Show for confirmed dates with regular labels, for TBD dates with different labels -->
              <%= cond do %>
                <% Map.get(assigns, :date_certainty, "confirmed") == "confirmed" -> %>
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

                <% Map.get(assigns, :date_certainty, "confirmed") == "planning" -> %>
                  <!-- For TBD dates, show date fields as "Planning Deadline" -->
                  <div class="mt-4 p-4 bg-gray-50 rounded-lg">
                    <p class="text-sm font-medium text-gray-700 mb-3">When do you plan to finalize the date?</p>
                    <div phx-hook="DateTimeSync" id="date-time-sync-hook-tbd">
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
                        <div>
                          <label class="block text-sm font-medium text-gray-600 mb-1">Target Date</label>
                          <.date_input
                            id={"#{@id}-start_date"}
                            name="event[start_date]"
                            value={Map.get(@form_data, "start_date", Date.utc_today() |> Date.add(30) |> Date.to_iso8601())}
                            required
                            data-role="start-date"
                            class="text-sm"
                          />
                        </div>
                        <div>
                          <label class="block text-sm font-medium text-gray-600 mb-1">Target Time</label>
                          <.time_select
                            id={"#{@id}-start_time"}
                            name="event[start_time]"
                            value={Map.get(@form_data, "start_time", "17:00")}
                            required
                            data-role="start-time"
                            class="text-sm"
                          />
                        </div>
                      </div>
                      <p class="text-xs text-gray-500">This will be used as a planning target. You can update it later when you have a confirmed date.</p>
                    </div>
                  </div>

                <% true -> %>
                  <!-- For polling or other states, no date fields shown -->
              <% end %>

              <!-- Hidden fields for combined datetime values - always include for TBD and confirmed -->
              <%= if Map.get(assigns, :date_certainty, "confirmed") in ["confirmed", "planning"] do %>
                <input type="hidden" name="event[start_at]" id={"#{@id}-start_at"} value={format_datetime_for_input(@event, :start_at)} />
                <input type="hidden" name="event[ends_at]" id={"#{@id}-ends_at"} value={format_datetime_for_input(@event, :ends_at)} />
              <% end %>
              
              <!-- Timezone field - always show regardless of date_certainty -->
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
            </div>

            <!-- Location -->
            <div class="mb-4 venue-search-container">
              <div class="mb-4">
                <label class="block text-sm font-medium text-gray-700 mb-2">Where is your event?</label>
                <select 
                  id="venue-certainty-select" 
                  name="event[venue_certainty]" 
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
                  phx-change="update_venue_certainty"
                >
                  <option value="confirmed" selected={Map.get(assigns, :venue_certainty, "confirmed") == "confirmed"}>✓ I have a venue</option>
                  <option value="polling" selected={Map.get(assigns, :venue_certainty, "confirmed") == "polling"}>? Let attendees vote on location</option>
                  <option value="virtual" selected={Map.get(assigns, :venue_certainty, "confirmed") == "virtual"}>💻 Virtual event</option>
                  <option value="tbd" selected={Map.get(assigns, :venue_certainty, "confirmed") == "tbd"}>○ Location TBD</option>
                </select>
                
                <!-- Error display for venue certainty -->
                <.changeset_error :if={@for} changeset={@for} field={:venue_certainty} class="mt-2" />
              </div>

              <!-- Virtual Event Fields -->
              <%= if Map.get(assigns, :venue_certainty, "confirmed") == "virtual" do %>
                <div class="mt-4 p-4 bg-gray-50 rounded-lg">
                  <label class="text-sm font-medium text-gray-700">Meeting Link</label>
                  <input type="url" name="event[virtual_link]" class="mt-1 w-full px-3 py-2 border border-gray-300 rounded-lg text-sm" placeholder="Zoom, Google Meet, etc.">
                  <p class="text-xs text-gray-500 mt-1">This will be shared with registered attendees</p>
                </div>
              <% end %>

              <!-- Physical Venue Fields -->
              <%= if Map.get(assigns, :venue_certainty, "confirmed") == "confirmed" do %>
                <div>
                  <!-- Recent Locations Section -->
                  <%= if assigns[:recent_locations] && length(@recent_locations) > 0 do %>
                    <div class="mb-2">
                      <div class="flex gap-2 mb-2">
                        <button
                          type="button"
                          phx-click="toggle_recent_locations"
                          class="flex items-center text-xs text-gray-600 hover:text-gray-800 recent-locations-toggle"
                        >
                          <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                          </svg>
                          Recent Locations (<%= length(@recent_locations) %>)
                          <svg class={"w-3 h-3 ml-1 transition-transform #{if @show_recent_locations, do: "rotate-180", else: ""}"} fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                          </svg>
                        </button>

                        <button
                          type="button"
                          phx-click="enable_google_places"
                          class="flex items-center text-xs text-blue-600 hover:text-blue-800 places-search-toggle"
                          title="Enable Google Places suggestions"
                        >
                          <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                          </svg>
                          Search Places
                        </button>
                      </div>

                      <%= if @show_recent_locations do %>
                        <div class="recent-locations-dropdown">
                          <%= for location <- @filtered_recent_locations do %>
                            <button
                              type="button"
                              phx-click="select_recent_location"
                              phx-value-location={case Jason.encode(location) do
                                {:ok, json} -> json
                                {:error, _} -> "{}"
                              end}
                              class="w-full text-left p-2 recent-location-item border-b border-gray-100 last:border-b-0"
                            >
                              <div class="flex items-start justify-between">
                                <div class="flex-1 min-w-0">
                                  <div class="text-sm font-medium text-gray-900 truncate">
                                    <svg class="w-4 h-4 inline mr-1 text-blue-600 location-icon" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                    <%= Map.get(location, :name) %>
                                  </div>
                                  <%= if Map.get(location, :address) do %>
                                    <div class="text-xs text-gray-500 truncate"><%= Map.get(location, :address) %></div>
                                  <% end %>
                                </div>
                                <div class="ml-2 flex-shrink-0">
                                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium usage-count-badge">
                                    <%= Map.get(location, :usage_count) %>x
                                  </span>
                                </div>
                              </div>
                            </button>
                          <% end %>

                          <%= if length(@filtered_recent_locations) == 0 do %>
                            <div class="no-results-message">
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
                    phx-hook="EventLocationSearch"
                    class="block w-full border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm venue-search-input"
                  />
                  <!-- Complete JSON data for consistency across all place selections -->
                  <input type="hidden" name="event[venue_data]" id={"venue-data-#{if @action == :new, do: "new", else: "edit"}"} value={Map.get(@form_data, "venue_data", "")} />
                  <!-- Hidden venue fields remain for backward compatibility -->
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
                  <div class="mt-2 p-3 bg-blue-50 border border-blue-300 rounded-md text-sm selected-venue-display">
                    <div class="font-medium text-blue-700"><%= @selected_venue_name %></div>
                    <div class="text-blue-600 text-xs"><%= @selected_venue_address %></div>
                  </div>
                <% end %>
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

            <!-- Participation Method -->
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-2">How will people join your event?</label>
              <select
                id="participation-type-select"
                name="event[participation_type]"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
                phx-change="update_participation_type"
              >
                <option value="free" selected={Map.get(assigns, :participation_type, "free") == "free"}>🤝 Free event - just RSVPs</option>
                <option value="ticketed" selected={Map.get(assigns, :participation_type, "free") == "ticketed"}>🎟️ Paid tickets</option>
                <option value="contribution" selected={Map.get(assigns, :participation_type, "free") == "contribution"}>🎁 Free with optional donations</option>
                <option value="crowdfunding" selected={Map.get(assigns, :participation_type, "free") == "crowdfunding"}>💰 Needs funding to happen</option>
                <option value="interest" selected={Map.get(assigns, :participation_type, "free") == "interest"}>📊 Testing interest first</option>
              </select>

              <!-- Error display for participation type -->
              <.changeset_error :if={@for} changeset={@for} field={:participation_type} class="mt-2" />
            </div>

            <!-- Ticketing Section - Only show for ticketed events -->
            <%= if Map.get(assigns, :participation_type, "free") == "ticketed" do %>
              <div class="mb-4">

                <!-- Hidden input for ticketing - controlled by setup path selector -->
                <input type="hidden" name="event[is_ticketed]" value={if Map.get(@form_data, "is_ticketed", false) in [true, "true"], do: "true", else: "false"} />

                <!-- Threshold-specific fields -->
                <%= if Map.get(@form_data, "setup_path", "confirmed") == "threshold" do %>
                  <div class="mb-4 p-4 bg-orange-50 border border-orange-200 rounded-lg" phx-hook="ThresholdForm" id="threshold-form">
                    <h4 class="text-sm font-medium text-orange-800 mb-3">Threshold Pre-Sale Settings</h4>
                    <div class="space-y-4">
                      <!-- Threshold Type Selection -->
                      <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">
                          Threshold Type
                        </label>
                        <div class="space-y-2">
                          <label class="inline-flex items-center">
                            <input
                              type="radio"
                              name="event[threshold_type]"
                              value="attendee_count"
                              checked={Map.get(@form_data, "threshold_type", "attendee_count") == "attendee_count"}
                              class="form-radio text-orange-600 focus:ring-orange-500"
                              data-threshold-radio="attendee_count"
                            />
                            <span class="ml-2 text-sm text-gray-700">Attendee Count</span>
                          </label>
                          <label class="inline-flex items-center">
                            <input
                              type="radio"
                              name="event[threshold_type]"
                              value="revenue"
                              checked={Map.get(@form_data, "threshold_type") == "revenue"}
                              class="form-radio text-orange-600 focus:ring-orange-500"
                              data-threshold-radio="revenue"
                            />
                            <span class="ml-2 text-sm text-gray-700">Revenue Target</span>
                          </label>
                          <label class="inline-flex items-center">
                            <input
                              type="radio"
                              name="event[threshold_type]"
                              value="both"
                              checked={Map.get(@form_data, "threshold_type") == "both"}
                              class="form-radio text-orange-600 focus:ring-orange-500"
                              data-threshold-radio="both"
                            />
                            <span class="ml-2 text-sm text-gray-700">Both (Attendees + Revenue)</span>
                          </label>
                        </div>
                        <p class="text-xs text-gray-500 mt-1">
                          Choose what must be met for the event to be confirmed
                        </p>
                      </div>

                      <!-- Attendee Count Field -->
                      <div id="attendee-threshold" class={
                        case Map.get(@form_data, "threshold_type", "attendee_count") do
                          "revenue" -> "hidden"
                          _ -> ""
                        end
                      }>
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

                      <!-- Revenue Field -->
                      <div id="revenue-threshold" class={
                        case Map.get(@form_data, "threshold_type", "attendee_count") do
                          "attendee_count" -> "hidden"
                          _ -> ""
                        end
                      }>
                        <label for="threshold_revenue_dollars" class="block text-sm font-medium text-gray-700 mb-1">
                          Minimum Revenue Required
                        </label>
                        <div class="mt-1 relative rounded-md shadow-sm">
                          <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                            <span class="text-gray-500 sm:text-sm">$</span>
                          </div>
                          <input
                            type="number"
                            id="threshold_revenue_dollars"
                            name="event[threshold_revenue_dollars]"
                            value={format_cents_as_dollars(Map.get(@form_data, "threshold_revenue_cents"))}
                            min="0"
                            step="0.01"
                            placeholder="0.00"
                            class="block w-full pl-7 pr-12 rounded-md border-gray-300 shadow-sm focus:border-orange-500 focus:ring-orange-500 text-sm"
                            data-revenue-input="true"
                          />
                          <div class="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                            <span class="text-gray-500 sm:text-sm">USD</span>
                          </div>
                        </div>
                        <p class="text-xs text-gray-500 mt-1">
                          Event will only be confirmed if this much revenue is generated
                        </p>
                        <!-- Hidden field to store cents value -->
                        <input
                          type="hidden"
                          name="event[threshold_revenue_cents]"
                          id="threshold_revenue_cents"
                          value={Map.get(@form_data, "threshold_revenue_cents", "")}
                        />
                      </div>
                    </div>
                  </div>
                  <!-- Hidden field for requires_threshold -->
                  <input type="hidden" name="event[requires_threshold]" value="true" />
                <% else %>
                  <!-- Hidden field for requires_threshold -->
                  <input type="hidden" name="event[requires_threshold]" value="false" />
                <% end %>

                <%= if Map.get(assigns, :participation_type, "free") == "ticketed" do %>
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
                                    Sale starts: <%= format_ticket_datetime(ticket.starts_at, @event) %>
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

                <!-- Event Taxation Classification (show only when tickets exist) -->
                <%= if length(@tickets || []) > 0 do %>
                  <div class="mt-3 p-3 bg-blue-50 border border-blue-200 rounded-lg">
                    <div class="flex items-center mb-2">
                      <svg class="w-4 h-4 text-blue-600 mr-2" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M4 4a2 2 0 00-2 2v4a2 2 0 002 2V6h10a2 2 0 00-2-2H4zm2 6a2 2 0 012-2h8a2 2 0 012 2v4a2 2 0 01-2 2H8a2 2 0 01-2-2v-4zm6 4a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd" />
                      </svg>
                      <h4 class="text-sm font-medium text-blue-800">Payment Processing Type</h4>
                    </div>
                    <.taxation_type_selector
                      field={f[:taxation_type]}
                      value={Map.get(@form_data, "taxation_type", "ticketed_event")}
                      errors={f[:taxation_type].errors}
                      required={true}
                      reasoning={Map.get(@form_data, "taxation_type_reasoning", "")}
                      hide_ticketless={true}
                    />
                  </div>
                <% end %>
              <% end %>
              </div>
            <% end %>

            <!-- Crowdfunding Configuration -->
            <%= if Map.get(assigns, :participation_type, "free") == "crowdfunding" do %>
            <div class="space-y-4 mt-6">
              <h4 class="text-sm font-medium text-gray-700">Crowdfunding Settings</h4>
              <div class="p-4 bg-purple-50 rounded-lg space-y-4">
                <div>
                  <label class="text-sm text-gray-700">Minimum funding goal <span class="text-red-500">*</span></label>
                  <div class="mt-1 relative">
                    <span class="absolute left-3 top-2 text-gray-500">$</span>
                    <input
                      type="number"
                      name="event[funding_goal]"
                      value={get_funding_goal_form_value(@event, @form_data)}
                      class="pl-8 w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                      placeholder="5,000"
                      required
                      min="1"
                    >
                  </div>
                  <p class="text-xs text-gray-500 mt-1">Event will only happen if this goal is reached</p>
                </div>
                <div>
                  <label class="text-sm text-gray-700">Campaign deadline <span class="text-red-500">*</span></label>
                  <input
                    type="date"
                    name="event[funding_deadline]"
                    value={get_threshold_deadline_value(@event, @form_data)}
                    min={Date.to_iso8601(Date.utc_today())}
                    max={get_max_deadline_date(@form_data)}
                    class="mt-1 w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                    required
                  >
                  <p class="text-xs text-gray-500 mt-1">Must be before the event start date</p>
                </div>
              </div>
            </div>
            <% end %>

            <!-- Interest Validation Configuration -->
            <%= if Map.get(assigns, :participation_type, "free") == "interest" do %>
            <div class="space-y-4 mt-6">
              <h4 class="text-sm font-medium text-gray-700">Interest Validation Settings</h4>
              <div class="p-4 bg-orange-50 rounded-lg space-y-4">
                <div>
                  <label class="text-sm text-gray-700">Minimum attendees needed <span class="text-red-500">*</span></label>
                  <input
                    type="number"
                    name="event[minimum_attendees]"
                    value={get_minimum_attendees_form_value(@event, @form_data)}
                    class="mt-1 w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                    placeholder="20"
                    required
                    min="1"
                  >
                </div>
                <div>
                  <label class="text-sm text-gray-700">Decision deadline <span class="text-red-500">*</span></label>
                  <input
                    type="date"
                    name="event[decision_deadline]"
                    value={get_threshold_deadline_value(@event, @form_data)}
                    min={Date.to_iso8601(Date.utc_today())}
                    max={get_max_deadline_date(@form_data)}
                    class="mt-1 w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                    required
                  >
                  <p class="text-xs text-gray-500 mt-1">Must be before the event start date</p>
                </div>
              </div>
            </div>
            <% end %>

            <!-- Hidden field to ensure taxation_type is submitted for truly ticketless events -->
            <!-- Don't set to ticketless for threshold events (crowdfunding/interest) since they need ticketed_event -->
            <%= if should_force_ticketless?(assigns) do %>
              <input type="hidden" name="event[taxation_type]" value="ticketless" />
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

  # Helper function to format ticket datetime with event timezone
  defp format_ticket_datetime(nil, _event), do: ""

  defp format_ticket_datetime(%DateTime{} = datetime, event) do
    timezone = if event && event.timezone, do: event.timezone, else: "UTC"

    datetime
    |> DateTimeHelper.utc_to_timezone(timezone)
    |> Calendar.strftime("%m/%d %I:%M %p %Z")
  end

  defp format_ticket_datetime(_, _), do: ""

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

  # ============================================================================
  # Threshold Progress Component
  # ============================================================================

  @doc """
  Renders a threshold progress display showing current progress toward the event threshold.

  ## Examples

      <.threshold_progress event={@event} />
      <.threshold_progress event={@event} class="mb-4" />
  """
  attr :event, :map, required: true, doc: "The event with threshold data"
  attr :class, :string, default: "", doc: "Additional CSS classes"
  attr :show_details, :boolean, default: true, doc: "Whether to show detailed progress text"

  def threshold_progress(assigns) do
    # Only show progress for events with valid threshold requirements
    if threshold_has_valid_targets?(assigns.event) do
      current_attendees =
        EventasaurusApp.EventStateMachine.get_current_attendee_count(assigns.event)

      current_revenue = EventasaurusApp.EventStateMachine.get_current_revenue(assigns.event)
      threshold_met = EventasaurusApp.EventStateMachine.threshold_met?(assigns.event)

      assigns =
        assign(assigns, %{
          current_attendees: current_attendees,
          current_revenue: current_revenue,
          threshold_met: threshold_met,
          show_progress: true
        })

      ~H"""
      <div class={["threshold-progress", @class]}>
        <%= if @show_progress do %>
          <%= case @event.threshold_type do %>
            <% "attendee_count" -> %>
              <.render_attendee_progress
                current={@current_attendees}
                target={@event.threshold_count}
                met={@threshold_met}
                show_details={@show_details}
              />
            <% "revenue" -> %>
              <.render_revenue_progress
                current={@current_revenue}
                target={@event.threshold_revenue_cents}
                met={@threshold_met}
                show_details={@show_details}
                currency={Map.get(@event, :currency, "USD")}
              />
            <% "both" -> %>
              <div class="space-y-3">
                <.render_attendee_progress
                  current={@current_attendees}
                  target={@event.threshold_count}
                  met={@current_attendees >= (@event.threshold_count || 0)}
                  show_details={@show_details}
                  label="Attendees"
                />
                <.render_revenue_progress
                  current={@current_revenue}
                  target={@event.threshold_revenue_cents}
                  met={@current_revenue >= (@event.threshold_revenue_cents || 0)}
                  show_details={@show_details}
                  currency={Map.get(@event, :currency, "USD")}
                  label="Revenue"
                />
                <div class={[
                  "text-center text-sm font-medium mt-2",
                  if(@threshold_met, do: "text-green-600", else: "text-orange-600")
                ]}>
                  <%= if @threshold_met do %>
                    ✅ Both thresholds met!
                  <% else %>
                    ⏳ Both thresholds must be met
                  <% end %>
                </div>
              </div>
            <% _ -> %>
              <!-- Unknown threshold type, show nothing -->
          <% end %>
        <% end %>
      </div>
      """
    else
      assigns = assign(assigns, show_progress: false)

      ~H"""
      <div class={@class}>
        <!-- No threshold requirements for this event -->
      </div>
      """
    end
  end

  # Helper component for rendering attendee progress
  attr :current, :integer, required: true
  attr :target, :integer, required: true
  attr :met, :boolean, required: true
  attr :show_details, :boolean, default: true
  attr :label, :string, default: "Attendees"

  defp render_attendee_progress(assigns) do
    percentage =
      if assigns.target && assigns.target > 0 do
        min(round(assigns.current / assigns.target * 100), 100)
      else
        0
      end

    assigns = assign(assigns, percentage: percentage)

    ~H"""
    <div class="attendee-progress">
      <div class="flex justify-between items-center mb-2">
        <span class="text-sm font-medium text-gray-700"><%= @label %></span>
        <%= if @show_details do %>
          <span class={[
            "text-sm font-semibold",
            if(@met, do: "text-green-600", else: "text-gray-600")
          ]}>
            <%= @current %> / <%= @target %>
            <%= if @met, do: "✅", else: "" %>
          </span>
        <% end %>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-3">
        <div
          class={[
            "h-3 rounded-full transition-all duration-300 ease-in-out",
            if(@met, do: "bg-green-500", else: "bg-orange-500")
          ]}
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
      <%= if @show_details do %>
        <div class="text-xs text-gray-500 mt-1 text-center">
          <%= @percentage %>% towards goal
        </div>
      <% end %>
    </div>
    """
  end

  # Helper component for rendering revenue progress
  attr :current, :integer, required: true
  attr :target, :integer, required: true
  attr :met, :boolean, required: true
  attr :show_details, :boolean, default: true
  attr :currency, :string, default: "USD"
  attr :label, :string, default: "Revenue"

  defp render_revenue_progress(assigns) do
    percentage =
      if assigns.target && assigns.target > 0 do
        min(round(assigns.current / assigns.target * 100), 100)
      else
        0
      end

    current_formatted =
      EventasaurusWeb.Helpers.CurrencyHelpers.format_currency(assigns.current, assigns.currency)

    target_formatted =
      EventasaurusWeb.Helpers.CurrencyHelpers.format_currency(assigns.target, assigns.currency)

    assigns =
      assign(assigns, %{
        percentage: percentage,
        current_formatted: current_formatted,
        target_formatted: target_formatted
      })

    ~H"""
    <div class="revenue-progress">
      <div class="flex justify-between items-center mb-2">
        <span class="text-sm font-medium text-gray-700"><%= @label %></span>
        <%= if @show_details do %>
          <span class={[
            "text-sm font-semibold",
            if(@met, do: "text-green-600", else: "text-gray-600")
          ]}>
            <%= @current_formatted %> / <%= @target_formatted %>
            <%= if @met, do: "✅", else: "" %>
          </span>
        <% end %>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-3">
        <div
          class={[
            "h-3 rounded-full transition-all duration-300 ease-in-out",
            if(@met, do: "bg-green-500", else: "bg-orange-500")
          ]}
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>
      <%= if @show_details do %>
        <div class="text-xs text-gray-500 mt-1 text-center">
          <%= @percentage %>% towards goal
        </div>
      <% end %>
    </div>
    """
  end

  # Helper function to format cents as dollars for display
  defp format_cents_as_dollars(nil), do: ""
  defp format_cents_as_dollars(""), do: ""

  defp format_cents_as_dollars(cents) when is_integer(cents) and cents > 0 do
    Float.round(cents / 100, 2) |> Float.to_string()
  end

  defp format_cents_as_dollars(cents) when is_binary(cents) do
    case Integer.parse(cents) do
      {parsed, ""} when parsed > 0 ->
        Float.round(parsed / 100, 2) |> Float.to_string()

      _ ->
        ""
    end
  end

  defp format_cents_as_dollars(_), do: ""

  # Helper to get funding goal value (cents to dollars) for form display
  defp get_funding_goal_value(nil), do: ""

  defp get_funding_goal_value(event) do
    case Map.get(event, :threshold_revenue_cents) do
      cents when is_integer(cents) and cents > 0 -> cents / 100
      _ -> ""
    end
  end

  # Helper to get funding goal value from either event or form_data (for LiveView forms)
  # Priority: 1) form_data value, 2) existing event value
  defp get_funding_goal_form_value(event, form_data) do
    # First check form_data (for values entered by user during form editing)
    form_value = Map.get(form_data, "funding_goal")

    if form_value && form_value != "" do
      form_value
    else
      # Fall back to existing event value
      get_funding_goal_value(event)
    end
  end

  # Helper to get minimum attendees value from either event or form_data (for LiveView forms)
  # Priority: 1) form_data value, 2) existing event value
  defp get_minimum_attendees_form_value(event, form_data) do
    # First check form_data (for values entered by user during form editing)
    form_value = Map.get(form_data, "minimum_attendees")

    if form_value && form_value != "" do
      form_value
    else
      # Fall back to existing event value
      Map.get(event || %{}, :threshold_count, "")
    end
  end

  # Helper to get threshold deadline as date string for form display (legacy - used for existing events only)
  defp get_threshold_deadline_date(nil), do: ""

  defp get_threshold_deadline_date(event) do
    # Note: The Event schema uses polling_deadline for threshold deadlines
    case Map.get(event, :polling_deadline) do
      %DateTime{} = datetime -> Date.to_iso8601(DateTime.to_date(datetime))
      _ -> ""
    end
  end

  # Helper to get threshold deadline value, with auto-population based on start_date
  # Priority: 1) existing event value, 2) form_data value, 3) computed default (48h before start)
  defp get_threshold_deadline_value(event, form_data) do
    # First check if event already has a polling_deadline
    existing_deadline = get_threshold_deadline_date(event)

    if existing_deadline != "" do
      existing_deadline
    else
      # Check if form_data has a deadline set
      form_deadline =
        Map.get(form_data, "funding_deadline") || Map.get(form_data, "decision_deadline")

      if form_deadline && form_deadline != "" do
        form_deadline
      else
        # Compute default: 48 hours before start_date
        compute_default_deadline(form_data)
      end
    end
  end

  # Compute default deadline as 48 hours (2 days) before the event start date
  # Returns today's date if start_date is not set or too close
  defp compute_default_deadline(form_data) do
    start_date_str = Map.get(form_data, "start_date")
    today = Date.utc_today()

    case parse_date(start_date_str) do
      {:ok, start_date} ->
        # Default to 2 days before start date
        default_deadline = Date.add(start_date, -2)

        # Ensure deadline is at least today
        if Date.compare(default_deadline, today) == :lt do
          Date.to_iso8601(today)
        else
          Date.to_iso8601(default_deadline)
        end

      :error ->
        # No valid start date, return empty (let user set it when they set start date)
        ""
    end
  end

  # Helper to get maximum deadline date (must be before event start date)
  defp get_max_deadline_date(form_data) do
    start_date_str = Map.get(form_data, "start_date")

    case parse_date(start_date_str) do
      {:ok, start_date} ->
        # Max deadline is 1 day before start date (campaign must end before event)
        max_date = Date.add(start_date, -1)
        Date.to_iso8601(max_date)

      :error ->
        # No start date set, allow any future date (far future)
        Date.to_iso8601(Date.add(Date.utc_today(), 365))
    end
  end

  # Parse a date string safely
  defp parse_date(nil), do: :error
  defp parse_date(""), do: :error

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  defp parse_date(_), do: :error

  # Helper to determine if we should force taxation_type to "ticketless"
  # Returns false for threshold events (crowdfunding/interest) that need ticketed_event
  defp should_force_ticketless?(assigns) do
    tickets = Map.get(assigns, :tickets, [])
    participation_type = Map.get(assigns, :participation_type, "free")

    # Only force ticketless if:
    # 1. No tickets exist
    # 2. participation_type is "free" (not crowdfunding, interest, ticketed, or contribution)
    length(tickets || []) == 0 and participation_type == "free"
  end

  def threshold_has_valid_targets?(%{threshold_type: "attendee_count"} = event),
    do: event.threshold_count && event.threshold_count > 0

  def threshold_has_valid_targets?(%{threshold_type: "revenue"} = event),
    do: event.threshold_revenue_cents && event.threshold_revenue_cents > 0

  def threshold_has_valid_targets?(%{threshold_type: "both"} = event),
    do:
      event.threshold_count && event.threshold_count > 0 &&
        (event.threshold_revenue_cents && event.threshold_revenue_cents > 0)

  def threshold_has_valid_targets?(_), do: false

  # Image attribution component for Unsplash and TMDB images
  attr :external_image_data, :map, required: true
  attr :class, :string, default: "text-xs text-gray-500 mt-2"

  def image_attribution(assigns) do
    ~H"""
    <%= if @external_image_data do %>
      <div class={@class}>
        <%= if @external_image_data["source"] == "unsplash" && get_in(@external_image_data, ["metadata", "user"]) do %>
          <% user = @external_image_data["metadata"]["user"] %>
          Photo by
          <a
            href={user["profile_url"] <> "?utm_source=eventasaurus&utm_medium=referral"}
            target="_blank"
            rel="noopener noreferrer"
            class="underline hover:text-gray-700 transition-colors"
          >
            <%= user["name"] %>
          </a>
          on
          <a
            href="https://unsplash.com?utm_source=eventasaurus&utm_medium=referral"
            target="_blank"
            rel="noopener noreferrer"
            class="underline hover:text-gray-700 transition-colors"
          >
            Unsplash
          </a>
        <% end %>

        <%= if @external_image_data["source"] == "tmdb" && get_in(@external_image_data, ["metadata"]) do %>
          <% metadata = @external_image_data["metadata"] %>
          <% movie_data = %{tmdb_id: parse_tmdb_id(metadata["id"])} %>
          <div class="flex flex-col space-y-1">
            <div>
              "<%= metadata["title"] %>" (<%= format_tmdb_year(metadata["release_date"]) %>) -
              <%= if metadata["type"] == "movie" && Cinegraph.linkable?(movie_data) do %>
                <a
                  href={Cinegraph.movie_url(movie_data)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="underline hover:text-indigo-700 transition-colors text-indigo-600"
                >
                  View on Cinegraph
                </a>
                <span class="text-gray-400">|</span>
              <% end %>
              <a
                href={"https://www.themoviedb.org/#{metadata["type"]}/#{metadata["id"]}"}
                target="_blank"
                rel="noopener noreferrer"
                class="underline hover:text-gray-700 transition-colors"
              >
                View on TMDB
              </a>
            </div>
            <div class="text-gray-400">
              This product uses the TMDB API but is not endorsed or certified by TMDB.
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Helper function to format TMDB release year
  defp format_tmdb_year(nil), do: "N/A"
  defp format_tmdb_year(""), do: "N/A"

  defp format_tmdb_year(date_string) when is_binary(date_string) do
    case String.split(date_string, "-") do
      [year | _] -> year
      _ -> "N/A"
    end
  end

  defp format_tmdb_year(_), do: "N/A"

  # Helper function to safely encode JSON data
  defp safe_json_encode(data) do
    case Jason.encode(data) do
      {:ok, json} -> json
      {:error, _} -> "{}"
    end
  end

  @doc """
  Renders a date range filter button with optional count badge.

  ## Examples

      <.date_range_button
        range={:today}
        label={gettext("Today")}
        active={@active_date_range == :today}
        count={Map.get(@date_range_counts, :today, 0)}
      />
  """
  attr :range, :atom, required: true, doc: "date range identifier (e.g., :today, :tomorrow)"
  attr :label, :string, required: true, doc: "button label text"
  attr :active, :boolean, default: false, doc: "whether this range is currently active"
  attr :count, :integer, default: 0, doc: "number of events in this range"

  def date_range_button(assigns) do
    ~H"""
    <button
      phx-click="quick_date_filter"
      phx-value-range={@range}
      class={[
        "px-3 py-2 rounded-lg font-medium text-sm transition-all",
        if(@active,
          do: "bg-blue-600 text-white shadow-md",
          else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
        )
      ]}
    >
      <%= @label %>
      <%= if @count > 0 do %>
        <span class={[
          "ml-1.5 px-1.5 py-0.5 rounded-full text-xs",
          if(@active, do: "bg-blue-700", else: "bg-gray-200 text-gray-600")
        ]}>
          <%= @count %>
        </span>
      <% end %>
    </button>
    """
  end

  @doc """
  Renders active filter tags with remove buttons.

  Displays tags for:
  - Search term
  - Radius (if different from default and provided)
  - Date range (if active_date_range provided)
  - Categories
  - Sort order (if different from default :starts_at)

  ## Examples

      <.active_filter_tags
        filters={@filters}
        categories={@categories}
        active_date_range={@active_date_range}
        radius_km={@radius_km}
        default_radius={50}
        sort_by={@sort_by}
      />
  """
  attr :filters, :map, required: true, doc: "current filter values"
  attr :categories, :list, required: true, doc: "list of available categories"
  attr :active_date_range, :atom, default: nil, doc: "currently active date range atom"
  attr :radius_km, :integer, default: nil, doc: "current radius in km (city page only)"
  attr :default_radius, :integer, default: 50, doc: "default radius to compare against"

  attr :sort_by, :atom,
    default: nil,
    doc: "currently active sort field (:starts_at, :title, :relevance, :popularity)"

  @spec active_filter_tags(map()) :: Phoenix.LiveView.Rendered.t()
  def active_filter_tags(assigns) do
    # Calculate all filter conditions for self-contained visibility
    has_search = assigns.filters[:search] && assigns.filters[:search] != ""
    has_non_default_radius = assigns.radius_km && assigns.radius_km != assigns.default_radius

    has_date_range =
      (assigns.filters[:start_date] || assigns.filters[:end_date]) && assigns.active_date_range

    has_categories = (assigns.filters[:categories] || []) != []
    has_non_default_sort = assigns.sort_by != nil && assigns.sort_by != :starts_at

    # Component shows itself when ANY filter is active (self-contained like simple_filter_tags)
    has_any_filter =
      has_search || has_non_default_radius || has_date_range || has_categories ||
        has_non_default_sort

    assigns =
      assigns
      |> assign(:has_non_default_sort, has_non_default_sort)
      |> assign(:has_any_filter, has_any_filter)

    ~H"""
    <div :if={@has_any_filter} class="flex flex-wrap gap-2">
      <%= if @filters[:search] && @filters[:search] != "" do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          Search: <%= @filters[:search] %>
          <button phx-click="clear_search" class="ml-2">
            <Heroicons.x_mark class="w-3 h-3" />
          </button>
        </span>
      <% end %>

      <%= if @radius_km && @radius_km != @default_radius do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          Radius: <%= @radius_km %>km
        </span>
      <% end %>

      <%= if (@filters[:start_date] || @filters[:end_date]) && @active_date_range do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          <%= EventasaurusWeb.Live.Helpers.EventFilters.date_range_label(@active_date_range, @filters) %>
          <button phx-click="clear_date_filter" class="ml-2">
            <Heroicons.x_mark class="w-3 h-3" />
          </button>
        </span>
      <% end %>

      <%= for category_id <- @filters[:categories] || [] do %>
        <% category = Enum.find(@categories, & &1.id == category_id) %>
        <%= if category do %>
          <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
            <%= category.name %>
            <button phx-click="remove_category" phx-value-id={category_id} class="ml-2">
              <Heroicons.x_mark class="w-3 h-3" />
            </button>
          </span>
        <% end %>
      <% end %>

      <%= if @has_non_default_sort do %>
        <span class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-blue-100 text-blue-800">
          Sorted by: <%= active_filter_sort_label(@sort_by) %>
          <button phx-click="sort" phx-value-sort_by="starts_at" class="ml-2 hover:text-blue-600" title="Reset sort">
            <Heroicons.x_mark class="w-3 h-3" />
          </button>
        </span>
      <% end %>
    </div>
    """
  end

  # Helper to get human-readable sort label for active_filter_tags
  defp active_filter_sort_label(:title), do: "Title"
  defp active_filter_sort_label(:relevance), do: "Relevance"
  defp active_filter_sort_label(:popularity), do: "Popularity"
  defp active_filter_sort_label(_), do: "Date"

  # Private helper to parse TMDb ID from various formats
  defp parse_tmdb_id(value) when is_integer(value), do: value

  defp parse_tmdb_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> nil
    end
  end

  defp parse_tmdb_id(_), do: nil

  @doc """
  Renders a visual countdown timer for threshold event deadlines.

  The component uses a JavaScript hook for real-time updates (every second)
  and provides visual urgency cues based on time remaining:
  - Normal (green): > 72 hours
  - Warning (amber): 24-72 hours
  - Urgent (orange): 1-24 hours
  - Critical (red with pulse): < 1 hour

  ## Attributes
  - `deadline` - DateTime for the deadline (required)
  - `class` - Additional CSS classes (optional)
  - `variant` - Display variant: "compact" (text only), "segmented" (boxes), or "full" (both). Default: "compact"
  - `label` - Optional label to display above the countdown

  ## Examples

      <.countdown_timer deadline={@event.polling_deadline} />
      <.countdown_timer deadline={@event.polling_deadline} variant="segmented" />
      <.countdown_timer deadline={@event.polling_deadline} label="Campaign ends in:" />
  """
  attr :deadline, :any, required: true, doc: "DateTime for the deadline"
  attr :class, :string, default: "", doc: "Additional CSS classes"
  attr :variant, :string, default: "compact", doc: "Display variant: compact, segmented, or full"
  attr :label, :string, default: nil, doc: "Optional label above the countdown"

  def countdown_timer(assigns) do
    # Handle nil deadline
    if is_nil(assigns.deadline) do
      assigns = assign(assigns, show_countdown: false)

      ~H"""
      <div class={@class}>
        <!-- No deadline set -->
      </div>
      """
    else
      # Convert deadline to ISO8601 string for JavaScript
      deadline_iso =
        case assigns.deadline do
          %DateTime{} = dt -> DateTime.to_iso8601(dt)
          dt when is_binary(dt) -> dt
          _ -> nil
        end

      # Calculate initial values for server-side render
      {days, hours, minutes, seconds, expired} = calculate_time_remaining(assigns.deadline)

      assigns =
        assign(assigns, %{
          deadline_iso: deadline_iso,
          days: days,
          hours: hours,
          minutes: minutes,
          seconds: seconds,
          expired: expired,
          show_countdown: deadline_iso != nil
        })

      ~H"""
      <div
        :if={@show_countdown}
        id={"countdown-#{System.unique_integer([:positive])}"}
        phx-hook="CountdownTimer"
        data-deadline={@deadline_iso}
        class={["countdown-timer", @class]}
      >
        <%= if @label do %>
          <div class="text-sm text-gray-600 mb-2 flex items-center gap-2">
            <svg class="w-4 h-4 text-amber-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span><%= @label %></span>
          </div>
        <% end %>

        <%= case @variant do %>
          <% "segmented" -> %>
            <.countdown_segmented
              days={@days}
              hours={@hours}
              minutes={@minutes}
              seconds={@seconds}
              expired={@expired}
            />
          <% "full" -> %>
            <div class="space-y-2">
              <.countdown_segmented
                days={@days}
                hours={@hours}
                minutes={@minutes}
                seconds={@seconds}
                expired={@expired}
              />
              <.countdown_text
                days={@days}
                hours={@hours}
                minutes={@minutes}
                seconds={@seconds}
                expired={@expired}
              />
            </div>
          <% _ -> %>
            <.countdown_text
              days={@days}
              hours={@hours}
              minutes={@minutes}
              seconds={@seconds}
              expired={@expired}
            />
        <% end %>
      </div>
      """
    end
  end

  # Private component for segmented countdown display
  attr :days, :integer, required: true
  attr :hours, :integer, required: true
  attr :minutes, :integer, required: true
  attr :seconds, :integer, required: true
  attr :expired, :boolean, required: true

  defp countdown_segmented(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-2">
      <div class="flex flex-col items-center">
        <div class="bg-gray-100 rounded-lg px-3 py-2 min-w-[3rem] text-center">
          <span data-days class="text-2xl font-bold text-gray-800">
            <%= String.pad_leading(Integer.to_string(@days), 2, "0") %>
          </span>
        </div>
        <span class="text-xs text-gray-500 mt-1">days</span>
      </div>
      <span class="text-xl text-gray-400 font-light">:</span>
      <div class="flex flex-col items-center">
        <div class="bg-gray-100 rounded-lg px-3 py-2 min-w-[3rem] text-center">
          <span data-hours class="text-2xl font-bold text-gray-800">
            <%= String.pad_leading(Integer.to_string(@hours), 2, "0") %>
          </span>
        </div>
        <span class="text-xs text-gray-500 mt-1">hours</span>
      </div>
      <span class="text-xl text-gray-400 font-light">:</span>
      <div class="flex flex-col items-center">
        <div class="bg-gray-100 rounded-lg px-3 py-2 min-w-[3rem] text-center">
          <span data-minutes class="text-2xl font-bold text-gray-800">
            <%= String.pad_leading(Integer.to_string(@minutes), 2, "0") %>
          </span>
        </div>
        <span class="text-xs text-gray-500 mt-1">min</span>
      </div>
      <span class="text-xl text-gray-400 font-light">:</span>
      <div class="flex flex-col items-center">
        <div class="bg-gray-100 rounded-lg px-3 py-2 min-w-[3rem] text-center">
          <span data-seconds class="text-2xl font-bold text-gray-800">
            <%= String.pad_leading(Integer.to_string(@seconds), 2, "0") %>
          </span>
        </div>
        <span class="text-xs text-gray-500 mt-1">sec</span>
      </div>
    </div>
    """
  end

  # Private component for compact text countdown display
  attr :days, :integer, required: true
  attr :hours, :integer, required: true
  attr :minutes, :integer, required: true
  attr :seconds, :integer, required: true
  attr :expired, :boolean, required: true

  defp countdown_text(assigns) do
    urgency_class =
      cond do
        assigns.expired -> "text-red-600 font-bold"
        assigns.days == 0 and assigns.hours < 1 -> "text-red-600 font-bold animate-pulse"
        assigns.days == 0 and assigns.hours < 24 -> "text-orange-600 font-semibold"
        assigns.days < 3 -> "text-amber-600"
        true -> "text-gray-600"
      end

    assigns = assign(assigns, urgency_class: urgency_class)

    ~H"""
    <div class="flex items-center gap-2">
      <svg class="w-4 h-4 text-amber-500 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
      <span data-text class={["text-sm", @urgency_class]}>
        <%= if @expired do %>
          Deadline has passed
        <% else %>
          <%= format_countdown_text(@days, @hours, @minutes, @seconds) %>
        <% end %>
      </span>
    </div>
    """
  end

  # Helper to calculate time remaining from deadline
  defp calculate_time_remaining(nil), do: {0, 0, 0, 0, true}

  defp calculate_time_remaining(%DateTime{} = deadline) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(deadline, now, :second)

    if diff_seconds <= 0 do
      {0, 0, 0, 0, true}
    else
      days = div(diff_seconds, 86400)
      hours = div(rem(diff_seconds, 86400), 3600)
      minutes = div(rem(diff_seconds, 3600), 60)
      seconds = rem(diff_seconds, 60)
      {days, hours, minutes, seconds, false}
    end
  end

  defp calculate_time_remaining(deadline) when is_binary(deadline) do
    case DateTime.from_iso8601(deadline) do
      {:ok, dt, _} -> calculate_time_remaining(dt)
      _ -> {0, 0, 0, 0, true}
    end
  end

  defp calculate_time_remaining(_), do: {0, 0, 0, 0, true}

  # Helper to format countdown as human-readable text
  defp format_countdown_text(days, hours, minutes, seconds) do
    parts = []
    parts = if days > 0, do: parts ++ ["#{days}d"], else: parts
    parts = if hours > 0 or days > 0, do: parts ++ ["#{hours}h"], else: parts
    parts = if minutes > 0 or hours > 0 or days > 0, do: parts ++ ["#{minutes}m"], else: parts
    parts = parts ++ ["#{seconds}s"]
    Enum.join(parts, " ") <> " remaining"
  end
end
