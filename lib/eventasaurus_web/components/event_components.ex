defmodule EventasaurusWeb.EventComponents do
  use Phoenix.Component
  import EventasaurusWeb.CoreComponents
  alias EventasaurusWeb.TimezoneHelpers
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
        class={["block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm", @class]}
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

  def event_form(assigns) do
    assigns = assign_new(assigns, :id, fn -> "event-form-#{if assigns.action == :new, do: "new", else: "edit"}" end)

    ~H"""
    <.form :let={f} for={@for} id={@id} phx-change="validate" phx-submit="submit" data-test-id="event-form">
      <div class="bg-white shadow-md rounded-lg p-6 mb-6 border border-gray-200">
        <!-- Cover Image -->
        <div class="mb-8">
          <h2 class="text-xl font-bold mb-4">Cover Image</h2>

          <div class="space-y-4">
            <%= if is_nil(f[:cover_image_url].value) or f[:cover_image_url].value == "" do %>
              <div class="mb-4">
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
              </div>
            <% else %>
              <div class="mb-4">
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
              </div>
            <% end %>

            <%= hidden_input f, :cover_image_url %>
            <%= if @external_image_data do %>
              <% encoded_data =
                if is_map(@external_image_data), do: Jason.encode!(@external_image_data), else: @external_image_data || "" %>
              <%= hidden_input f, :external_image_data, value: encoded_data %>
            <% end %>
          </div>
        </div>

        <!-- Theme Selection -->
        <div class="mb-8">
          <h2 class="text-xl font-bold mb-4">Event Theme</h2>
          <div class="space-y-4">
            <div class="form-group">
              <label for={f[:theme].id} class="block text-sm font-medium text-gray-700 mb-2">
                Choose a theme for your event page
              </label>
              <select
                name="event[theme]"
                id={f[:theme].id}
                class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors"
              >
                <%= for theme <- EventasaurusWeb.ThemeComponents.available_themes() do %>
                  <option value={theme.value} selected={f[:theme].value == theme.value || f[:theme].value == String.to_atom(theme.value)}>
                    <%= theme.label %> - <%= theme.description %>
                  </option>
                <% end %>
              </select>
              <p class="mt-2 text-sm text-gray-500">
                The theme will customize the appearance of your public event page
              </p>
            </div>
          </div>
        </div>

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
            <div phx-hook="DateTimeSync" id="date-time-sync-hook">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
                  <.date_input
                    id={"#{@id}-start_date"}
                    name="event[start_date]"
                    value={Map.get(@form_data, "start_date", "")}
                    required
                    data-role="start-date"
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
                  />
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4 mt-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
                  <.date_input
                    id={"#{@id}-ends_date"}
                    name="event[ends_date]"
                    value={Map.get(@form_data, "ends_date", "")}
                    data-role="end-date"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">End Time</label>
                  <.time_select
                    id={"#{@id}-ends_time"}
                    name="event[ends_time]"
                    value={Map.get(@form_data, "ends_time", "")}
                    data-role="end-time"
                  />
                </div>
              </div>
            </div>

            <div class="form-group">
              <label for={f[:timezone].id} class="block text-sm font-medium text-gray-700 mb-1">Timezone</label>
              <.timezone_select
                field={f[:timezone]}
                selected={Map.get(@form_data, "timezone", nil)}
                show_all={@show_all_timezones}
              />
              <p class="mt-1 text-xs text-gray-500">Your local timezone will be auto-detected if available</p>
            </div>

            <!-- Hidden fields to store the combined datetime values -->
            <input
              type="hidden"
              name="event[start_at]"
              id={"#{@id}-start_at"}
              value={format_datetime_for_input(@event, :start_at)}
            />
            <input
              type="hidden"
              name="event[ends_at]"
              id={"#{@id}-ends_at"}
              value={format_datetime_for_input(@event, :ends_at)}
            />
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
                    id={"venue-search-#{if @action == :new, do: "new", else: "edit"}"}
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
            <.input field={f[:cover_image_url]} type="text" label="Cover Image URL" id="details_cover_image_url" />
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

  # Helper function to format datetime for hidden input fields
  defp format_datetime_for_input(event, field) when is_map(event) do
    case Map.get(event, field) do
      %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
      nil -> ""
      _ -> ""
    end
  end

  defp format_datetime_for_input(_, _), do: ""
end
