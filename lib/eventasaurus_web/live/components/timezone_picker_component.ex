defmodule EventasaurusWeb.TimezonePickerComponent do
  @moduledoc """
  A simple timezone picker component for Date+Time polling.

  Provides a dropdown selection of common timezones with user-friendly display names.

  ## Attributes:
  - field: Phoenix.HTML.FormField - The form field for timezone (required)
  - label: string - Label for the picker (default: "Timezone")
  - class: string - Additional CSS classes
  - required: boolean - Whether field is required (default: false)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.TimezonePickerComponent}
        id="timezone-picker"
        field={@form[:timezone]}
        label="Event Timezone"
        required={true}
      />
  """

  use Phoenix.Component

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, default: "Timezone"
  attr :class, :string, default: ""
  attr :required, :boolean, default: false
  attr :rest, :global, include: ~w(id)

  def timezone_picker(assigns) do
    ~H"""
    <div class={@class}>
      <label for={@field.id} class="block text-sm font-medium text-gray-700">
        <%= @label %>
        <%= if @required do %>
          <span class="text-red-500">*</span>
        <% end %>
      </label>

      <div class="mt-1 relative">
        <select
          id={@field.id}
          name={@field.name}
          value={@field.value || "UTC"}
          class="block w-full pl-3 pr-10 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm bg-white"
          {@rest}
        >
          <%= for timezone <- common_timezones() do %>
            <option value={timezone.value} selected={@field.value == timezone.value}>
              <%= timezone.display %>
            </option>
          <% end %>
        </select>

        <div class="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
          </svg>
        </div>
      </div>

      <p class="mt-1 text-xs text-gray-500">
        This timezone will be used for displaying all times to users.
      </p>
    </div>
    """
  end

  # Common timezones with user-friendly names
  defp common_timezones do
    [
      %{value: "UTC", display: "UTC (Coordinated Universal Time)"},
      %{value: "America/New_York", display: "Eastern Time (ET)"},
      %{value: "America/Chicago", display: "Central Time (CT)"},
      %{value: "America/Denver", display: "Mountain Time (MT)"},
      %{value: "America/Los_Angeles", display: "Pacific Time (PT)"},
      %{value: "America/Anchorage", display: "Alaska Time (AKT)"},
      %{value: "Pacific/Honolulu", display: "Hawaii Time (HST)"},
      %{value: "Europe/London", display: "Greenwich Mean Time (GMT)"},
      %{value: "Europe/Paris", display: "Central European Time (CET)"},
      %{value: "Europe/Berlin", display: "Central European Time (CET)"},
      %{value: "Europe/Rome", display: "Central European Time (CET)"},
      %{value: "Europe/Madrid", display: "Central European Time (CET)"},
      %{value: "Europe/Moscow", display: "Moscow Standard Time (MSK)"},
      %{value: "Asia/Tokyo", display: "Japan Standard Time (JST)"},
      %{value: "Asia/Shanghai", display: "China Standard Time (CST)"},
      %{value: "Asia/Hong_Kong", display: "Hong Kong Time (HKT)"},
      %{value: "Asia/Singapore", display: "Singapore Standard Time (SGT)"},
      %{value: "Asia/Dubai", display: "Gulf Standard Time (GST)"},
      %{value: "Asia/Kolkata", display: "India Standard Time (IST)"},
      %{value: "Australia/Sydney", display: "Australian Eastern Time (AET)"},
      %{value: "Australia/Melbourne", display: "Australian Eastern Time (AET)"},
      %{value: "Australia/Perth", display: "Australian Western Time (AWT)"},
      %{value: "Pacific/Auckland", display: "New Zealand Standard Time (NZST)"}
    ]
  end
end
