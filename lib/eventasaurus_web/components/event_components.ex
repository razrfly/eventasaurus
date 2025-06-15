defmodule EventasaurusWeb.EventComponents do
  use Phoenix.Component
  import EventasaurusWeb.CoreComponents
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
  # Ticketing-related attributes
  attr :tickets, :list, default: [], doc: "list of existing tickets for the event"
  attr :show_ticket_form, :boolean, default: false, doc: "whether to show the ticket creation/edit form"
  attr :ticket_form_data, :map, default: %{}, doc: "data for the ticket form"
  attr :editing_ticket_index, :integer, default: nil, doc: "index of ticket being edited, nil for new ticket"

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

              <!-- Date Polling Toggle -->
              <div class="flex items-center mb-3 p-3 bg-blue-50 border border-blue-200 rounded-lg">
                <label class="flex items-start cursor-pointer w-full">
                  <input
                    type="checkbox"
                    name="event[enable_date_polling]"
                    value="true"
                    checked={@enable_date_polling}
                    phx-click="toggle_date_polling"
                    class="h-4 w-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500 mt-0.5 mr-3"
                  />
                  <div>
                    <span class="text-sm font-medium text-blue-900">Let attendees vote on the date</span>
                    <p class="text-xs text-blue-700 mt-1">Create a poll for attendees to choose their preferred dates</p>
                  </div>
                </label>
              </div>

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
                  <input
                    type="text"
                    id={"venue-search-#{if @action == :new, do: "new", else: "edit"}"}
                    placeholder="Search for venue or address..."
                    phx-hook="GooglePlacesAutocomplete"
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
                <.input field={f[:virtual_venue_url]} type="text" label="Meeting URL" placeholder="https://..." class="text-sm" />
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

            <!-- Ticketing Section -->
            <div class="mb-4">
              <h3 class="text-sm font-semibold text-gray-700 mb-3">Ticketing</h3>

              <!-- Enable Ticketing Toggle -->
              <div class="flex items-center mb-4 p-3 bg-green-50 border border-green-200 rounded-lg">
                <label class="flex items-start cursor-pointer w-full">
                  <input
                    type="checkbox"
                    name="event[is_ticketed]"
                    value="true"
                    checked={Map.get(@form_data, "is_ticketed", false) in [true, "true"]}
                    phx-click="toggle_ticketing"
                    class="h-4 w-4 text-green-600 border-gray-300 rounded focus:ring-green-500 mt-0.5 mr-3"
                  />
                  <div>
                    <span class="text-sm font-medium text-green-900">Enable Ticketing</span>
                    <p class="text-xs text-green-700 mt-1">Collect payments and manage attendee registration</p>
                  </div>
                </label>
              </div>

              <%= if Map.get(@form_data, "is_ticketed", false) in [true, "true"] do %>
                <!-- Tickets Management Section -->
                <div class="space-y-4" id="tickets-section">
                  <div class="flex items-center justify-between">
                    <h4 class="text-sm font-medium text-gray-700">Ticket Types</h4>
                    <button
                      type="button"
                      phx-click="add_ticket_form"
                      class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded-md text-green-700 bg-green-100 hover:bg-green-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                    >
                      <svg class="w-3 h-3 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                      </svg>
                      Add Ticket
                    </button>
                  </div>

                  <!-- Existing Tickets List -->
                  <%= if assigns[:tickets] && length(@tickets) > 0 do %>
                    <div class="space-y-3">
                      <%= for {ticket, index} <- Enum.with_index(@tickets) do %>
                        <div class="border border-gray-200 rounded-lg p-4 bg-gray-50">
                          <div class="flex items-start justify-between">
                            <div class="flex-1">
                              <h5 class="text-sm font-medium text-gray-900"><%= ticket.title %></h5>
                              <%= if ticket.description do %>
                                <p class="text-xs text-gray-600 mt-1"><%= ticket.description %></p>
                              <% end %>
                              <div class="flex items-center space-x-4 mt-2 text-xs text-gray-500">
                                <span>Price: $<%= Float.round(ticket.price_cents / 100, 2) %></span>
                                <span>Quantity: <%= ticket.quantity %></span>
                                <%= if ticket.starts_at do %>
                                  <span>Sale starts: <%= Calendar.strftime(ticket.starts_at, "%m/%d %I:%M %p") %></span>
                                <% end %>
                              </div>
                            </div>
                            <div class="flex space-x-2">
                              <button
                                type="button"
                                phx-click="edit_ticket"
                                phx-value-index={index}
                                class="text-blue-600 hover:text-blue-800 text-xs"
                              >
                                Edit
                              </button>
                              <button
                                type="button"
                                phx-click="remove_ticket"
                                phx-value-index={index}
                                class="text-red-600 hover:text-red-800 text-xs"
                              >
                                Remove
                              </button>
                            </div>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <!-- New/Edit Ticket Form -->
                  <%= if assigns[:show_ticket_form] do %>
                    <div class="border border-gray-300 rounded-lg p-4 bg-white">
                      <div class="flex items-center justify-between mb-3">
                        <h5 class="text-sm font-medium text-gray-900">
                          <%= if assigns[:editing_ticket_index], do: "Edit Ticket", else: "New Ticket" %>
                        </h5>
                        <button
                          type="button"
                          phx-click="cancel_ticket_form"
                          class="text-gray-400 hover:text-gray-600"
                        >
                          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                          </svg>
                        </button>
                      </div>

                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <!-- Ticket Title -->
                        <div class="sm:col-span-2">
                          <label class="block text-xs font-medium text-gray-700 mb-1">Ticket Name</label>
                          <input
                            type="text"
                            name="ticket[title]"
                            value={Map.get(@ticket_form_data || %{}, "title", "")}
                            placeholder="e.g., General Admission, VIP, Early Bird"
                            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 text-sm"
                            phx-change="validate_ticket"
                          />
                        </div>

                        <!-- Ticket Description -->
                        <div class="sm:col-span-2">
                          <label class="block text-xs font-medium text-gray-700 mb-1">Description (optional)</label>
                          <textarea
                            name="ticket[description]"
                            value={Map.get(@ticket_form_data || %{}, "description", "")}
                            placeholder="Describe what's included with this ticket..."
                            rows="2"
                            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 text-sm"
                            phx-change="validate_ticket"
                          ></textarea>
                        </div>

                        <!-- Price -->
                        <div>
                          <label class="block text-xs font-medium text-gray-700 mb-1">Price</label>
                          <div class="relative">
                            <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                              <span class="text-gray-500 text-sm">$</span>
                            </div>
                            <input
                              type="number"
                              name="ticket[price]"
                              value={format_price_for_input(@ticket_form_data)}
                              step="0.01"
                              min="0"
                              placeholder="0.00"
                              class="block w-full pl-7 rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 text-sm"
                              phx-change="validate_ticket"
                            />
                          </div>
                        </div>

                        <!-- Quantity -->
                        <div>
                          <label class="block text-xs font-medium text-gray-700 mb-1">Available Tickets</label>
                          <input
                            type="number"
                            name="ticket[quantity]"
                            value={Map.get(@ticket_form_data || %{}, "quantity", "")}
                            min="1"
                            placeholder="100"
                            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 text-sm"
                            phx-change="validate_ticket"
                          />
                        </div>

                        <!-- Sale Start Time (optional) -->
                        <div>
                          <label class="block text-xs font-medium text-gray-700 mb-1">Sale Starts (optional)</label>
                          <input
                            type="datetime-local"
                            name="ticket[starts_at]"
                            value={Map.get(@ticket_form_data || %{}, "starts_at", "")}
                            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 text-sm"
                            phx-change="validate_ticket"
                          />
                        </div>

                        <!-- Sale End Time (optional) -->
                        <div>
                          <label class="block text-xs font-medium text-gray-700 mb-1">Sale Ends (optional)</label>
                          <input
                            type="datetime-local"
                            name="ticket[ends_at]"
                            value={Map.get(@ticket_form_data || %{}, "ends_at", "")}
                            class="block w-full rounded-md border-gray-300 shadow-sm focus:border-green-500 focus:ring-green-500 text-sm"
                            phx-change="validate_ticket"
                          />
                        </div>
                      </div>

                      <!-- Tippable Option -->
                      <div class="mt-3">
                        <label class="flex items-center cursor-pointer">
                          <input
                            type="checkbox"
                            name="ticket[tippable]"
                            value="true"
                            checked={Map.get(@ticket_form_data || %{}, "tippable", false) == true}
                            class="h-3 w-3 text-green-600 border-gray-300 rounded focus:ring-green-500"
                            phx-change="validate_ticket"
                          />
                          <span class="ml-2 text-xs text-gray-700">Allow tips on this ticket</span>
                        </label>
                      </div>

                      <!-- Form Actions -->
                      <div class="flex justify-end space-x-2 mt-4 pt-3 border-t border-gray-200">
                        <button
                          type="button"
                          phx-click="cancel_ticket_form"
                          class="px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          phx-click="save_ticket"
                          class="px-3 py-1.5 text-xs font-medium text-white bg-green-600 border border-transparent rounded-md hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                        >
                          <%= if assigns[:editing_ticket_index], do: "Update Ticket", else: "Add Ticket" %>
                        </button>
                      </div>
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

  defp format_price_for_input(form_data) do
    case Map.get(form_data, "price") do
      nil -> ""
      price_str when is_binary(price_str) -> price_str
      _ -> ""
    end
  end
end
