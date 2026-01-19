defmodule EventasaurusWeb.TimeSlotPickerComponent do
  @moduledoc """
  A comprehensive time slot picker component for Date+Time polling.

  Supports:
  - Single time point selection
  - Time slot ranges (start/end times)
  - All-day event configuration
  - Multiple time slots per date
  - Timezone support
  - 24-hour and 12-hour format display

  Integrates with the enhanced DateMetadata schema for the Date+Time polling system.

  ## Attributes:
  - field: Phoenix.HTML.FormField - The form field for time slots (required)
  - label: string - Label for the time picker (default: "Time Slots")
  - time_enabled: boolean - Whether time selection is enabled (default: true)
  - all_day: boolean - Whether this is an all-day event (default: false)
  - allow_multiple: boolean - Allow multiple time slots (default: true)
  - timezone: string - Timezone for display (default: "UTC")
  - format: atom - Time display format :12_hour or :24_hour (default: :12_hour)
  - class: string - Additional CSS classes
  - required: boolean - Whether field is required (default: false)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.TimeSlotPickerComponent}
        id="time-slot-picker"
        field={@form[:time_slots]}
        label="Available Times"
        time_enabled={true}
        all_day={false}
        allow_multiple={true}
        timezone="America/New_York"
        format={:12_hour}
      />
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusWeb.Utils.TimeUtils
  alias EventasaurusApp.Events.DateMetadata

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:time_slots, [])
     |> assign(:editing_slot_index, nil)
     |> assign(:new_slot, %{
       "start_time" => "12:00",
       "end_time" => "13:00",
       "display" => "12:00 - 13:00"
     })
     |> assign(:errors, [])}
  end

  @impl true
  def update(assigns, socket) do
    # Parse existing time slots from form field value or existing_slots
    time_slots =
      cond do
        Map.has_key?(assigns, :field) and assigns.field.value != nil ->
          parse_time_slots_from_field(assigns.field.value)

        Map.has_key?(assigns, :existing_slots) ->
          assigns.existing_slots || []

        true ->
          []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:label, fn -> "Time Slots" end)
     |> assign_new(:time_enabled, fn -> true end)
     |> assign_new(:all_day, fn -> false end)
     |> assign_new(:allow_multiple, fn -> true end)
     |> assign_new(:timezone, fn -> "UTC" end)
     |> assign_new(:format, fn -> "24_hour" end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:required, fn -> false end)
     |> assign(:time_slots, time_slots)
     |> assign(:new_slot, %{
       "start_time" => "12:00",
       "end_time" => "13:00",
       "display" => "12:00 - 13:00"
     })}
  end

  @impl true
  def handle_event("toggle_all_day", _params, socket) do
    new_all_day = not socket.assigns.all_day
    new_time_enabled = not new_all_day

    # Clear time slots if switching to all-day
    time_slots = if new_all_day, do: [], else: socket.assigns.time_slots

    # Update the parent (form or component)
    send_update_to_parent(socket, time_slots)

    {:noreply,
     socket
     |> assign(:all_day, new_all_day)
     |> assign(:time_enabled, new_time_enabled)
     |> assign(:time_slots, time_slots)
     |> assign(:errors, [])}
  end

  @impl true
  def handle_event("toggle_time_enabled", _params, socket) do
    new_time_enabled = not socket.assigns.time_enabled

    # Clear time slots if disabling time
    time_slots = if new_time_enabled, do: socket.assigns.time_slots, else: []

    # Update the parent (form or component)
    send_update_to_parent(socket, time_slots)

    {:noreply,
     socket
     |> assign(:time_enabled, new_time_enabled)
     |> assign(:time_slots, time_slots)
     |> assign(:errors, [])}
  end

  @impl true
  def handle_event("update_new_slot", %{"field" => field, "value" => value}, socket) do
    new_slot = Map.put(socket.assigns.new_slot, field, value)

    # Auto-adjust end time when start time changes
    new_slot =
      if field == "start_time" and value != "" do
        new_end_time = add_hour_to_time(value)
        Map.put(new_slot, "end_time", new_end_time)
      else
        new_slot
      end

    # Auto-generate display text if both start and end times are set
    new_slot =
      if field in ["start_time", "end_time"] and
           new_slot["start_time"] != "" and
           new_slot["end_time"] != "" do
        display =
          generate_time_slot_display(
            new_slot["start_time"],
            new_slot["end_time"],
            socket.assigns.format
          )

        Map.put(new_slot, "display", display)
      else
        new_slot
      end

    {:noreply, assign(socket, :new_slot, new_slot)}
  end

  # Catch-all for update_new_slot events with unexpected parameters
  @impl true
  def handle_event("update_new_slot", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_time_slot", _params, socket) do
    new_slot = socket.assigns.new_slot

    # Validate the new time slot
    case validate_time_slot(new_slot) do
      :ok ->
        # Add display text if not provided
        final_slot =
          if new_slot["display"] == "" do
            display =
              generate_time_slot_display(
                new_slot["start_time"],
                new_slot["end_time"],
                socket.assigns.format
              )

            Map.put(new_slot, "display", display)
          else
            new_slot
          end

        updated_slots = socket.assigns.time_slots ++ [final_slot]

        # Validate overall time slots for overlaps
        case validate_time_slots_metadata(updated_slots) do
          %Ecto.Changeset{valid?: true} ->
            # Update the parent (form or component)
            send_update_to_parent(socket, updated_slots)

            {:noreply,
             socket
             |> assign(:time_slots, updated_slots)
             |> assign(:new_slot, %{
               "start_time" => "12:00",
               "end_time" => "13:00",
               "display" => ""
             })
             |> assign(:errors, [])}

          %Ecto.Changeset{valid?: false} = changeset ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            {:noreply, assign(socket, :errors, format_errors(errors))}

          {:error, errors} ->
            {:noreply, assign(socket, :errors, errors)}
        end

      {:error, errors} ->
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  @impl true
  def handle_event("remove_time_slot", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    updated_slots = List.delete_at(socket.assigns.time_slots, index)

    # Update the parent (form or component)
    send_update_to_parent(socket, updated_slots)

    {:noreply,
     socket
     |> assign(:time_slots, updated_slots)
     |> assign(:errors, [])}
  end

  @impl true
  def handle_event("edit_time_slot", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    slot = Enum.at(socket.assigns.time_slots, index)

    {:noreply,
     socket
     |> assign(:editing_slot_index, index)
     |> assign(:new_slot, slot || %{"start_time" => "", "end_time" => "", "display" => ""})}
  end

  @impl true
  def handle_event("save_edited_slot", _params, socket) do
    index = socket.assigns.editing_slot_index
    updated_slot = socket.assigns.new_slot

    case validate_time_slot(updated_slot) do
      :ok ->
        # Add display text if not provided
        final_slot =
          if updated_slot["display"] == "" do
            display =
              generate_time_slot_display(
                updated_slot["start_time"],
                updated_slot["end_time"],
                socket.assigns.format
              )

            Map.put(updated_slot, "display", display)
          else
            updated_slot
          end

        updated_slots = List.replace_at(socket.assigns.time_slots, index, final_slot)

        # Validate overall time slots for overlaps
        case validate_time_slots_metadata(updated_slots) do
          %Ecto.Changeset{valid?: true} ->
            # Update the parent (form or component)
            send_update_to_parent(socket, updated_slots)

            {:noreply,
             socket
             |> assign(:time_slots, updated_slots)
             |> assign(:editing_slot_index, nil)
             |> assign(:new_slot, %{
               "start_time" => "12:00",
               "end_time" => "13:00",
               "display" => ""
             })
             |> assign(:errors, [])}

          %Ecto.Changeset{valid?: false} = changeset ->
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
            {:noreply, assign(socket, :errors, format_errors(errors))}

          {:error, errors} ->
            {:noreply, assign(socket, :errors, errors)}
        end

      {:error, errors} ->
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_slot_index, nil)
     |> assign(:new_slot, %{"start_time" => "12:00", "end_time" => "13:00", "display" => ""})
     |> assign(:errors, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["time-slot-picker-component", @class]}>
      <!-- Label -->
      <div class="mb-3">
        <label class="block text-sm font-medium text-gray-700">
          <%= @label %>
          <%= if @required do %>
            <span class="text-red-500">*</span>
          <% end %>
        </label>

        <%= if @timezone != "UTC" do %>
          <p class="text-xs text-gray-500 mt-1">
            Times in <%= @timezone %>
          </p>
        <% end %>
      </div>

      <!-- All-Day Toggle -->
      <div class="mb-4">
        <label class="inline-flex items-center">
          <input
            type="checkbox"
            checked={@all_day}
            phx-click="toggle_all_day"
            phx-target={@myself}
            class="rounded border-gray-300 text-indigo-600 shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50"
          />
          <span class="ml-2 text-sm text-gray-700">All-day event</span>
        </label>
      </div>

      <!-- Time Configuration (hidden when all-day) -->
      <%= if not @all_day do %>
        <div class="space-y-4">
          <!-- Time Enabled Toggle -->
          <div class="mb-4">
            <label class="inline-flex items-center">
              <input
                type="checkbox"
                checked={@time_enabled}
                phx-click="toggle_time_enabled"
                phx-target={@myself}
                class="rounded border-gray-300 text-indigo-600 shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50"
              />
              <span class="ml-2 text-sm text-gray-700">Include specific times</span>
            </label>
          </div>

          <!-- Time Slots Section (shown when time enabled) -->
          <%= if @time_enabled do %>
            <!-- Existing Time Slots -->
            <%= if length(@time_slots) > 0 do %>
              <div class="mb-4">
                <h4 class="text-sm font-medium text-gray-700 mb-2">Time Slots</h4>
                <div class="space-y-2">
                  <%= for {slot, index} <- Enum.with_index(@time_slots) do %>
                    <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg border">
                      <div class="flex-1">
                        <span class="text-sm font-medium text-gray-900">
                          <%= slot["display"] || generate_time_slot_display(slot["start_time"], slot["end_time"], @format) %>
                        </span>
                        <div class="text-xs text-gray-500">
                          <%= slot["start_time"] %> - <%= slot["end_time"] %>
                        </div>
                      </div>
                      <div class="flex items-center space-x-2">
                        <button
                          type="button"
                          phx-click="edit_time_slot"
                          phx-value-index={index}
                          phx-target={@myself}
                          class="text-indigo-600 hover:text-indigo-800 text-sm"
                        >
                          Edit
                        </button>
                        <button
                          type="button"
                          phx-click="remove_time_slot"
                          phx-value-index={index}
                          phx-target={@myself}
                          class="text-red-600 hover:text-red-800 text-sm"
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <!-- Add/Edit Time Slot Form -->
            <div class="p-4 border border-gray-200 rounded-lg bg-gray-50">
              <h4 class="text-sm font-medium text-gray-700 mb-3">
                <%= if @editing_slot_index, do: "Edit Time Slot", else: "Add Time Slot" %>
              </h4>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <!-- Start Time -->
                <div>
                  <label class="block text-xs font-medium text-gray-600 mb-1">Start Time</label>
                  <select
                    phx-change="update_new_slot"
                    phx-value-field="start_time"
                    phx-target={@myself}
                    class="block w-full text-sm border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50"
                  >
                    <option value="">Select start time...</option>
                    <%= for time_option <- time_options() do %>
                      <option value={time_option.value} selected={@new_slot["start_time"] == time_option.value}>
                        <%= time_option.display %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <!-- End Time -->
                <div>
                  <label class="block text-xs font-medium text-gray-600 mb-1">End Time</label>
                  <select
                    phx-change="update_new_slot"
                    phx-value-field="end_time"
                    phx-target={@myself}
                    class="block w-full text-sm border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50"
                  >
                    <option value="">Select end time...</option>
                    <%= for time_option <- time_options() do %>
                      <option value={time_option.value} selected={@new_slot["end_time"] == time_option.value}>
                        <%= time_option.display %>
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>

              <!-- Custom Display Text (Optional) -->
              <div class="mt-3">
                <label class="block text-xs font-medium text-gray-600 mb-1">
                  Custom Label (optional)
                </label>
                <input
                  type="text"
                  placeholder="e.g., Morning Session, Lunch Break..."
                  value={@new_slot["display"]}
                  phx-change="update_new_slot"
                  phx-value-field="display"
                  phx-target={@myself}
                  class="block w-full text-sm border-gray-300 rounded-md shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50"
                />
              </div>

              <!-- Action Buttons -->
              <div class="mt-4 flex justify-end space-x-2">
                <%= if @editing_slot_index do %>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    phx-target={@myself}
                    class="px-3 py-2 text-sm text-gray-600 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    phx-click="save_edited_slot"
                    phx-target={@myself}
                    disabled={@new_slot["start_time"] == "" or @new_slot["end_time"] == ""}
                    class="px-3 py-2 text-sm text-white bg-indigo-600 border border-transparent rounded-md hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Save Changes
                  </button>
                <% else %>
                  <button
                    type="button"
                    phx-click="add_time_slot"
                    phx-target={@myself}
                    disabled={@new_slot["start_time"] == "" or @new_slot["end_time"] == "" or (not @allow_multiple and length(@time_slots) > 0)}
                    class="px-3 py-2 text-sm text-white bg-indigo-600 border border-transparent rounded-md hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    <%= if not @allow_multiple and length(@time_slots) > 0 do %>
                      Replace Time Slot
                    <% else %>
                      Add Time Slot
                    <% end %>
                  </button>
                <% end %>
              </div>
            </div>

            <!-- Multiple Slots Help Text -->
            <%= if @allow_multiple and length(@time_slots) == 0 do %>
              <p class="text-xs text-gray-500 mt-2">
                💡 You can add multiple time slots for this date option (e.g., morning and evening sessions)
              </p>
            <% end %>
          <% end %>
        </div>
      <% end %>

      <!-- Error Messages -->
      <%= if length(@errors) > 0 do %>
        <div class="mt-3 p-3 bg-red-50 border border-red-200 rounded-md">
          <div class="flex">
            <svg class="w-5 h-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
            </svg>
            <div class="ml-2">
              <h4 class="text-sm font-medium text-red-800">Please fix the following:</h4>
              <ul class="mt-1 text-sm text-red-700 list-disc list-inside">
                <%= for error <- @errors do %>
                  <li><%= error %></li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Hidden form field to store the time slot data (only when used with forms) -->
      <%= if assigns[:field] do %>
        <input
          type="hidden"
          name={@field.name}
          value={encode_time_slots_for_field(@time_slots, @time_enabled, @all_day, @timezone)}
        />
      <% end %>
    </div>
    """
  end

  # Private helper functions

  defp parse_time_slots_from_field(nil), do: []

  defp parse_time_slots_from_field(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{"time_slots" => time_slots}} when is_list(time_slots) -> time_slots
      {:ok, %{}} -> []
      _ -> []
    end
  end

  defp parse_time_slots_from_field(value) when is_map(value) do
    Map.get(value, "time_slots", [])
  end

  defp parse_time_slots_from_field(_), do: []

  defp encode_time_slots_for_field(time_slots, time_enabled, all_day, timezone) do
    data = %{
      "time_enabled" => time_enabled,
      "all_day" => all_day,
      "time_slots" => time_slots,
      "timezone" => timezone,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Jason.encode!(data)
  end

  defp send_update_to_form(field, value) do
    # Send a message to the parent LiveView to update the form field
    send(self(), {:update_form_field, field.name, value})
  end

  defp send_update_to_parent(socket, time_slots) do
    if Map.has_key?(socket.assigns, :field) and socket.assigns.field != nil do
      # Form-based usage: encode time slots and update form field
      field_value =
        encode_time_slots_for_field(
          time_slots,
          socket.assigns.time_enabled,
          socket.assigns.all_day,
          socket.assigns.timezone
        )

      send_update_to_form(socket.assigns.field, field_value)
    else
      # Component-based usage: use send_update to communicate with target component
      if Map.has_key?(socket.assigns, :target) and Map.has_key?(socket.assigns, :on_save) do
        # Convert date to string if it's a Date struct
        date_string =
          case socket.assigns.date do
            %Date{} -> Date.to_iso8601(socket.assigns.date)
            date_str when is_binary(date_str) -> date_str
            _ -> to_string(socket.assigns.date)
          end

        send_update(socket.assigns.target, %{
          id: socket.assigns.target,
          event: socket.assigns.on_save,
          date: date_string,
          time_slots: time_slots
        })
      else
        # Fallback: send message to parent LiveView
        send(
          self(),
          {:save_date_time_slots,
           %{
             date: socket.assigns.date,
             time_slots: time_slots
           }}
        )
      end
    end
  end

  defp generate_time_slot_display(start_time, end_time, format) do
    start_formatted = format_time_for_display(start_time, format)
    end_formatted = format_time_for_display(end_time, format)
    "#{start_formatted} - #{end_formatted}"
  end

  defp format_time_for_display(time_string, "12_hour") when is_binary(time_string) do
    # Legacy 12-hour format support
    TimeUtils.format_time_12hour(time_string)
  end

  defp format_time_for_display(time_string, "24_hour") when is_binary(time_string) do
    time_string
  end

  # Default to 24-hour format (European standard)
  defp format_time_for_display(time_string, _) when is_binary(time_string), do: time_string
  defp format_time_for_display(_, _), do: ""

  defp validate_time_slot(%{"start_time" => start_time, "end_time" => end_time})
       when start_time != "" and end_time != "" do
    cond do
      not valid_time_format?(start_time) ->
        {:error, ["Invalid start time format"]}

      not valid_time_format?(end_time) ->
        {:error, ["Invalid end time format"]}

      time_to_minutes(start_time) >= time_to_minutes(end_time) ->
        {:error, ["End time must be after start time"]}

      true ->
        :ok
    end
  end

  defp validate_time_slot(_) do
    {:error, ["Both start and end times are required"]}
  end

  defp validate_time_slots_metadata(time_slots) do
    DateMetadata.validate_time_slots(time_slots)
  end

  defp valid_time_format?(time_string) when is_binary(time_string) do
    case String.split(time_string, ":") do
      [hour_str, minute_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str),
             true <- hour >= 0 and hour <= 23,
             true <- minute >= 0 and minute <= 59 do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp valid_time_format?(_), do: false

  defp time_to_minutes(time_string) when is_binary(time_string) do
    [hour_str, minute_str] = String.split(time_string, ":")
    hour = String.to_integer(hour_str)
    minute = String.to_integer(minute_str)
    hour * 60 + minute
  end

  # Generate time options (30-minute increments)
  defp time_options do
    for hour <- 0..23, minute <- [0, 30] do
      time_value =
        "#{String.pad_leading(to_string(hour), 2, "0")}:#{String.pad_leading(to_string(minute), 2, "0")}"

      # Use 24-hour format for display (European standard)
      %{value: time_value, display: time_value}
    end
  end

  # Format changeset errors into a flat list of error messages
  defp format_errors(errors) when is_map(errors) do
    errors
    |> Enum.flat_map(fn {_field, messages} ->
      case messages do
        msg when is_binary(msg) -> [msg]
        msgs when is_list(msgs) -> msgs
        _ -> []
      end
    end)
  end

  defp format_errors(errors) when is_list(errors), do: errors
  defp format_errors(_), do: []

  # Add one hour to a time string (HH:MM format)
  defp add_hour_to_time(time_string) do
    case String.split(time_string, ":") do
      [hour_str, minute_str] ->
        case {Integer.parse(hour_str), Integer.parse(minute_str)} do
          {{hour, ""}, {minute, ""}}
          when hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 ->
            # Wrap around at 24 hours
            new_hour = rem(hour + 1, 24)

            "#{String.pad_leading(to_string(new_hour), 2, "0")}:#{String.pad_leading(to_string(minute), 2, "0")}"

          _ ->
            # Return original if invalid
            time_string
        end

      _ ->
        # Return original if invalid format
        time_string
    end
  end
end
