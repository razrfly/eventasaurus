defmodule EventasaurusWeb.EventComponents do
  use Phoenix.Component
  import EventasaurusWeb.CoreComponents

  @doc """
  Renders a time select dropdown with 30-minute increments.

  ## Examples
      <.time_select
        id="event_start_time"
        name="event[start_time]"
        value={@start_time}
        required={true}
        hook="TimeOptionsHook"
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
      class={["block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm", @class]}
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
      class={["block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm", @class]}
      required={@required}
      {@rest}
    />
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

  def event_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} phx-change="validate" phx-submit="submit">
      <div class="bg-white shadow-md rounded-lg p-6 mb-6 border border-gray-200">
        <!-- Basic Information -->
        <div class="mb-8">
          <h2 class="text-xl font-bold mb-4">Basic Information</h2>
          <div class="space-y-4">
            <.input field={f[:title]} type="text" label="Event Title" required />
            <.input field={f[:tagline]} type="text" label="Tagline" />
            <.input field={f[:description]} type="textarea" label="Description" />
            <.input field={f[:visibility]} type="select" label="Visibility" options={[{"Public", "public"}, {"Private", "private"}]} />
          </div>
        </div>

        <!-- Date & Time -->
        <div class="mb-8">
          <h2 class="text-xl font-bold mb-4">Date & Time</h2>
          <div class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
                <.date_input
                  id="event_start_date"
                  name="event[start_date]"
                  value={Map.get(@form_data, "start_date", "")}
                  required
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Start Time</label>
                <.time_select
                  id="event_start_time"
                  name="event[start_time]"
                  value={Map.get(@form_data, "start_time", "")}
                  required
                  hook="TimeOptionsHook"
                />
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
                <.date_input
                  id="event_ends_date"
                  name="event[ends_date]"
                  value={Map.get(@form_data, "ends_date", "")}
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">End Time</label>
                <.time_select
                  id="event_ends_time"
                  name="event[ends_time]"
                  value={Map.get(@form_data, "ends_time", "")}
                />
              </div>
            </div>

            <.input field={f[:timezone]} type="select" label="Timezone" options={[
              {"Pacific Time (PT)", "America/Los_Angeles"},
              {"Mountain Time (MT)", "America/Denver"},
              {"Central Time (CT)", "America/Chicago"},
              {"Eastern Time (ET)", "America/New_York"},
              {"UTC", "UTC"}
            ]} />

            <!-- Hidden fields to store the combined datetime values -->
            <input type="hidden" name="event[start_at]" id="event_start_at" />
            <input type="hidden" name="event[ends_at]" id="event_ends_at" />
          </div>
        </div>

        <!-- Venue -->
        <div class="mb-8">
          <h2 class="text-xl font-bold mb-4">Venue</h2>
          <div class="space-y-6">
            <div class="flex items-center mb-4">
              <label class="flex items-center cursor-pointer">
                <input
                  type="checkbox"
                  name="event[is_virtual]"
                  value="true"
                  checked={Map.get(@form_data, "is_virtual", false) == true}
                  phx-click="toggle_virtual"
                  class="h-4 w-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
                />
                <span class="ml-2 text-sm font-medium">This is a virtual/online event</span>
              </label>
            </div>

            <%= if !@is_virtual do %>
              <div>
                <label for="venue-search" class="block text-sm font-medium text-gray-700 mb-1">
                  Search for venue/address
                </label>
                <div id="venue-search-container" class="mt-1 relative">
                  <input
                    type="text"
                    id="venue-search"
                    placeholder="Start typing a venue or address..."
                    phx-hook="GooglePlacesAutocomplete"
                    class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  />
                  <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none text-gray-400">
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd" />
                    </svg>
                  </div>
                </div>
                <p class="mt-1 text-xs text-gray-500">Type to search for a venue or address</p>
              </div>

              <!-- Hidden fields for venue data -->
              <div>
                <input type="hidden" name="event[venue_name]" id="venue-name" value={Map.get(@form_data, "venue_name", "")} />
                <input type="hidden" name="event[venue_address]" id="venue-address" value={Map.get(@form_data, "venue_address", "")} />
                <input type="hidden" name="event[venue_city]" id="venue-city" value={Map.get(@form_data, "venue_city", "")} />
                <input type="hidden" name="event[venue_state]" id="venue-state" value={Map.get(@form_data, "venue_state", "")} />
                <input type="hidden" name="event[venue_country]" id="venue-country" value={Map.get(@form_data, "venue_country", "")} />
                <input type="hidden" name="event[venue_latitude]" id="venue-lat" value={Map.get(@form_data, "venue_latitude", "")} />
                <input type="hidden" name="event[venue_longitude]" id="venue-lng" value={Map.get(@form_data, "venue_longitude", "")} />
              </div>

              <!-- Selected venue display -->
              <%= if @selected_venue_name do %>
                <div class="mt-4 p-3 bg-blue-50 border border-blue-300 rounded-md">
                  <h3 class="font-medium text-blue-700 mb-1">Selected Venue:</h3>
                  <p class="font-bold"><%= @selected_venue_name %></p>
                  <p class="text-sm text-blue-600"><%= @selected_venue_address %></p>

                  <%= if Application.get_env(:eventasaurus, :environment) != :prod do %>
                    <div class="mt-2 text-xs text-blue-500">
                      <p>City: <%= Map.get(@form_data, "venue_city", "") %></p>
                      <p>State: <%= Map.get(@form_data, "venue_state", "") %></p>
                      <p>Country: <%= Map.get(@form_data, "venue_country", "") %></p>
                      <p>Coordinates: <%= Map.get(@form_data, "venue_latitude", "") %>, <%= Map.get(@form_data, "venue_longitude", "") %></p>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <!-- Debug info - show current form_data -->
              <%= if Application.get_env(:eventasaurus, :environment) != :prod do %>
                <div class="mt-4 p-3 bg-gray-100 text-xs font-mono">
                  <p class="font-bold">Debug - form_data in venue step:</p>
                  <p>venue_name: <%= Map.get(@form_data, "venue_name", "") %></p>
                  <p>venue_address: <%= Map.get(@form_data, "venue_address", "") %></p>
                  <p>is_virtual: <%= Map.get(@form_data, "is_virtual", "") %></p>
                </div>
              <% end %>
            <% else %>
              <div>
                <.input field={f[:virtual_venue_url]} type="text" label="Meeting URL" placeholder="https://..." />
                <p class="mt-1 text-xs text-gray-500">Enter the URL where attendees can join your virtual event</p>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Details -->
        <div class="mb-8">
          <h2 class="text-xl font-bold mb-4">Details</h2>
          <div class="space-y-4">
            <.input field={f[:cover_image_url]} type="text" label="Cover Image URL" />
          </div>
        </div>

        <!-- Venue Preview -->
        <div class="mb-8">
          <h2 class="text-xl font-bold mb-4">Venue Information</h2>

          <% is_virtual = Map.get(@form_data, "is_virtual", false) %>

          <div>
            <strong>Venue:</strong>
            <%= if is_virtual do %>
              Virtual Event - <%= Map.get(@form_data, "virtual_venue_url", "") %>
            <% else %>
              <%= if venue_name = Map.get(@form_data, "venue_name", nil) do %>
                <div class="p-2 bg-gray-50 border border-gray-200 rounded-md mt-1">
                  <div><%= venue_name %></div>
                  <div class="text-sm text-gray-500"><%= Map.get(@form_data, "venue_address", "") %></div>
                  <div class="text-sm text-gray-500">
                    <%= Map.get(@form_data, "venue_city", "") %><%= if Map.get(@form_data, "venue_city", "") != "" && Map.get(@form_data, "venue_state", "") != "", do: ", " %><%= Map.get(@form_data, "venue_state", "") %>
                    <%= if Map.get(@form_data, "venue_country", "") != "", do: ", #{Map.get(@form_data, "venue_country", "")}" %>
                  </div>
                </div>
              <% else %>
                <div class="p-2 bg-gray-50 border border-gray-200 rounded-md mt-1">
                  No venue selected
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <div class={@action == :edit && "flex justify-between" || "flex justify-end"}>
        <%= if @action == :edit && @cancel_path do %>
          <.link navigate={@cancel_path} class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50">
            Cancel
          </.link>
        <% end %>

        <button type="submit" class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500">
          <%= @submit_label %>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 ml-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
        </button>
      </div>
    </.form>
    """
  end
end
