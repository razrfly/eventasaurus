defmodule EventasaurusWeb.TimeSelectorComponent do
  @moduledoc """
  A time selector component that provides a dropdown with 30-minute increments.
  Used for time-based polls where users need to select specific times.
  """

  use Phoenix.Component

  alias EventasaurusWeb.Utils.TimeUtils

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, default: "Time"
  attr :class, :string, default: ""
  attr :required, :boolean, default: false
  attr :rest, :global, include: ~w(id)

  def time_selector(assigns) do
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
          class="block w-full pl-3 pr-10 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm bg-white"
          {@rest}
        >
          <option value="" disabled selected={@field.value == nil or @field.value == ""}>Select a time...</option>
          <%= for time_option <- time_options() do %>
            <option value={time_option.value} selected={@field.value == time_option.value}>
              <%= time_option.display %>
            </option>
          <% end %>
        </select>
        <div class="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
          <svg class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
          </svg>
        </div>
      </div>
    </div>
    """
  end

  defp time_options do
    # Start at 10:00 AM (10:00) and go through 11:30 PM (23:30)
    # 30-minute increments
    10..23
    |> Enum.flat_map(fn hour ->
      [
        %{value: TimeUtils.format_time_value(hour, 0), display: TimeUtils.format_time_display(hour, 0)},
        %{value: TimeUtils.format_time_value(hour, 30), display: TimeUtils.format_time_display(hour, 30)}
      ]
    end)
  end


end
