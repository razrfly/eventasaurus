defmodule EventasaurusWeb.OptionListComponent do
  @moduledoc """
  Option list component for displaying and managing poll options.
  
  Handles option display, editing, deletion, and management functionality.
  """

  use EventasaurusWeb, :live_component
  require Logger
  alias EventasaurusApp.Events
  alias EventasaurusApp.Events.PollOption
  alias EventasaurusWeb.OptionSuggestionHelpers

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:editing_option_id, fn -> nil end)
     |> assign_new(:edit_changeset, fn -> nil end)
     |> assign_new(:participants, fn -> [] end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="divide-y divide-gray-200 min-h-[100px] relative option-list-component"
      phx-hook={if @poll.poll_type in ["time", "date_selection"], do: "", else: "PollOptionDragDrop"}
      data-can-reorder={if(@is_creator && @poll.poll_type not in ["time", "date_selection"], do: "true", else: "false")}
      id={"option-list-#{@id}"}
    >
      <%= if safe_poll_options_empty?(@poll.poll_options) do %>
        <%= render_empty_state(assigns) %>
      <% else %>
        <%= render_options_list(assigns) %>
      <% end %>
    </div>
    """
  end

  defp render_empty_state(assigns) do
    ~H"""
    <div class="px-6 py-16 text-center">
      <div class="mx-auto w-20 h-20 bg-indigo-100 rounded-full flex items-center justify-center mb-6">
        <svg class="w-10 h-10 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"/>
        </svg>
      </div>

      <h3 class="text-xl font-semibold text-gray-900 mb-2">
        <%= OptionSuggestionHelpers.get_empty_state_title(@poll.poll_type) %>
      </h3>

      <p class="text-gray-600 mb-2 max-w-md mx-auto">
        <%= OptionSuggestionHelpers.get_empty_state_description(@poll.poll_type, @poll.voting_system) %>
      </p>

      <div class="text-sm text-gray-500 mb-8 max-w-lg mx-auto">
        <%= OptionSuggestionHelpers.get_empty_state_guidance(@poll.poll_type) %>
      </div>

      <%= if assigns[:can_suggest_more] do %>
        <button
          type="button"
          phx-click="toggle_suggestion_form"
          phx-target={@myself}
          class="inline-flex items-center px-8 py-4 border border-transparent text-lg font-medium rounded-lg shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors duration-200"
        >
          <svg class="w-6 h-6 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
          </svg>
          <%= OptionSuggestionHelpers.get_empty_state_button_text(@poll.poll_type) %>
        </button>
      <% else %>
        <div class="text-gray-500 mb-4">
          <%= assigns[:phase_suggestion_message] || "No options have been added yet." %>
        </div>
      <% end %>

      <div class="mt-8 text-center">
        <p class="text-sm text-gray-500">
          <%= OptionSuggestionHelpers.get_empty_state_help_text(@poll.poll_type) %>
        </p>
      </div>
    </div>
    """
  end

  # List of existing options
  defp render_options_list(assigns) do
    ~H"""
    <div data-role="options-container">
      <%= for option <- sort_poll_options(@poll.poll_options, @poll.poll_type) do %>
        <div
          class="px-6 py-4 transition-all duration-200 ease-out option-card mobile-optimized-animation hover:bg-gray-50 focus-within:ring-2 focus-within:ring-indigo-500 focus-within:ring-offset-2"
          data-draggable={if(@is_creator && @poll.poll_type not in ["time", "date_selection"], do: "true", else: "false")}
          data-option-id={option.id}
        >
          <!-- Edit Form (only shown when editing this specific option) -->
          <%= if @editing_option_id == option.id && @edit_changeset do %>
            <%= render_edit_form(assigns, option) %>
          <% else %>
            <%= render_option_display(assigns, option) %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Edit form for option
  defp render_edit_form(assigns, option) do
    assigns = assign(assigns, :option, option)

    ~H"""
    <.form for={@edit_changeset} phx-submit="save_edit" phx-target={@myself} phx-change="validate_edit">
      <div class="space-y-4">
        <input type="hidden" name="option_id" value={@option.id} />

        <%= if @poll.poll_type == "date_selection" do %>
          <!-- For date selection polls, show the date as read-only -->
          <div>
            <label class="block text-sm font-medium text-gray-700">
              Date
            </label>
            <div class="mt-1 text-sm text-gray-900 bg-gray-50 border border-gray-300 rounded-md px-3 py-2">
              <%= @option.title %>
            </div>
          </div>
        <% else %>
          <div>
            <label for={"edit_title_#{@option.id}"} class="block text-sm font-medium text-gray-700">
              Title
            </label>
            <input
              type="text"
              name="poll_option[title]"
              id={"edit_title_#{@option.id}"}
              value={Phoenix.HTML.Form.input_value(@edit_changeset, :title)}
              class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
            />
            <%= if @edit_changeset.errors[:title] do %>
              <div class="mt-1 text-sm text-red-600">
                <%= translate_error(@edit_changeset.errors[:title]) %>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @poll.poll_type != "time" do %>
          <div>
            <label for={"edit_description_#{@option.id}"} class="block text-sm font-medium text-gray-700">
              Description
            </label>
            <textarea
              name="poll_option[description]"
              id={"edit_description_#{@option.id}"}
              rows="2"
              class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
            ><%= Phoenix.HTML.Form.input_value(@edit_changeset, :description) %></textarea>
          </div>
        <% end %>

        <%= if @is_creator do %>
          <div>
            <label for={"edit_suggested_by_#{@option.id}"} class="block text-sm font-medium text-gray-700">Suggested by</label>
            <select name="poll_option[suggested_by_id]" id={"edit_suggested_by_#{@option.id}"} class="mt-1 block w-full border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm">
              <option value={@user.id} selected={Phoenix.HTML.Form.input_value(@edit_changeset, :suggested_by_id) == @user.id}>
                <%= get_user_display_name(@user) %> (Organizer)
              </option>
              <%= if @participants do %>
                <%= for participant <- @participants, participant.user_id != @user.id do %>
                  <option value={participant.user_id} selected={Phoenix.HTML.Form.input_value(@edit_changeset, :suggested_by_id) == participant.user_id}>
                    <%= get_user_display_name(participant.user) %>
                  </option>
                <% end %>
              <% end %>
            </select>
          </div>
          <div class="flex items-center">
            <input type="checkbox" name="poll_option[status]" id={"edit_hidden_#{@option.id}"} value="hidden" checked={Phoenix.HTML.Form.input_value(@edit_changeset, :status) == "hidden"} class="h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded" />
            <label for={"edit_hidden_#{@option.id}"} class="ml-2 block text-sm text-gray-900">Hide this option from voters</label>
          </div>
        <% end %>

        <div class="flex justify-end space-x-3">
          <button
            type="button"
            phx-click="cancel_edit"
            phx-target={@myself}
            class="px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={not @edit_changeset.valid?}
            class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:bg-gray-300 disabled:cursor-not-allowed"
          >
            Save Changes
          </button>
        </div>
      </div>
    </.form>
    """
  end

  # Display view for option
  defp render_option_display(assigns, option) do
    assigns = assign(assigns, :option, option)

    ~H"""
    <div class="flex items-start justify-between">
      <!-- Drag handle for creators -->
      <%= if @is_creator && @poll.poll_type not in ["time", "date_selection"] do %>
        <div class="drag-handle mr-3 mt-1 flex-shrink-0 touch-target" title="Drag to reorder">
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true">
            <path d="M7 2a1 1 0 011-1h4a1 1 0 011 1v2a1 1 0 11-2 0V3H9v1a1 1 0 11-2 0V2zM7 6a1 1 0 011-1h4a1 1 0 011 1v2a1 1 0 11-2 0V7H9v1a1 1 0 11-2 0V6zM7 10a1 1 0 011-1h4a1 1 0 011 1v2a1 1 0 11-2 0v-1H9v1a1 1 0 11-2 0v-2zM7 14a1 1 0 011-1h4a1 1 0 011 1v2a1 1 0 11-2 0v-1H9v1a1 1 0 11-2 0v-2z"/>
          </svg>
        </div>
      <% end %>

      <div class="flex-1 min-w-0">
        <!-- Option Content -->
        <div class="mb-2">
          <h4 class="text-sm font-medium text-gray-900 truncate">
            <%= case @poll.poll_type do %>
              <% "time" -> %>
                <%= OptionSuggestionHelpers.format_time_for_display(@option.title) %>
              <% "date_selection" -> %>
                <span class="inline-flex items-center group">
                  <svg class="w-4 h-4 mr-1 text-gray-500 group-hover:text-indigo-600 transition-colors duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                  </svg>
                  <%= OptionSuggestionHelpers.format_date_for_display(@option.title) %>
                </span>
              <% _ -> %>
                <%= @option.title %>
            <% end %>
            
            <%= if @option.status == "hidden" do %>
              <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.878 9.878L18 12"/>
                </svg>
                Hidden
              </span>
            <% end %>
          </h4>
          
          <%= if @option.description && String.trim(@option.description) != "" do %>
            <p class="mt-1 text-sm text-gray-600 line-clamp-2"><%= @option.description %></p>
          <% end %>
        </div>

        <!-- Option Meta Information -->
        <div class="flex items-center text-xs text-gray-500 space-x-1">
          <span>Suggested by <%= get_user_display_name(@option.suggested_by) %></span>
          <%= if @option.inserted_at do %>
            <span class="mx-1">•</span>
            <span><%= OptionSuggestionHelpers.format_relative_time(@option.inserted_at) %></span>
          <% end %>
          <%= if @poll.poll_type not in ["time", "date_selection"] do %>
            <span class="mx-1">•</span>
            <span>Order: <%= @option.order_index %></span>
          <% end %>
        </div>
      </div>

      <!-- Option Actions -->
      <div class="ml-4 flex-shrink-0 flex items-center space-x-2 option-card-actions">
        <%= if @is_creator || @option.suggested_by_id == @user.id do %>
          <!-- Edit option button -->
          <button
            type="button"
            phx-click="edit_option"
            phx-value-option-id={@option.id}
            phx-target={@myself}
            class="text-indigo-600 hover:text-indigo-900 text-sm font-medium"
            title="Edit option"
          >
            Edit
          </button>
        <% end %>

        <%= if @is_creator || Events.can_delete_option_based_on_poll_settings?(@option, @user) do %>
          <!-- Remove option button -->
          <div class="flex items-center space-x-2">
            <button
              type="button"
              phx-click="delete_option"
              phx-value-option-id={@option.id}
              phx-target={@myself}
              data-confirm="Are you sure you want to remove this option? This action cannot be undone."
              class="text-red-600 hover:text-red-900 text-sm font-medium"
              title="Remove option"
            >
              Remove
            </button>
            <%= if !@is_creator && @option.suggested_by_id == @user.id do %>
              <% time_remaining = OptionSuggestionHelpers.get_deletion_time_remaining(@option.inserted_at) %>
              <%= if time_remaining > 0 do %>
                <span class="text-xs text-gray-500">
                  (<%= OptionSuggestionHelpers.format_deletion_time_remaining(time_remaining) %> left)
                </span>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("edit_option", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        option = case socket.assigns.poll.poll_options do
          %Ecto.Association.NotLoaded{} -> nil
          poll_options when is_list(poll_options) ->
            Enum.find(poll_options, fn opt -> opt.id == option_id_int end)
          _ -> nil
        end

        if option do
          edit_changeset = PollOption.changeset(option, %{})
          {:noreply,
           socket
           |> assign(:editing_option_id, option_id_int)
           |> assign(:edit_changeset, edit_changeset)}
        else
          send(self(), {:show_error, "Option not found"})
          {:noreply, socket}
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_option_id, nil)}
  end

  @impl true
  def handle_event("validate_edit", %{"poll_option" => option_params}, socket) do
    if socket.assigns.editing_option_id do
      option = case socket.assigns.poll.poll_options do
        %Ecto.Association.NotLoaded{} -> nil
        poll_options when is_list(poll_options) ->
          Enum.find(poll_options, fn opt -> opt.id == socket.assigns.editing_option_id end)
        _ -> nil
      end

      if option do
        changeset = PollOption.changeset(option, option_params)
        {:noreply, assign(socket, :edit_changeset, changeset)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_edit", %{"poll_option" => option_params, "option_id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        case Events.get_poll_option(option_id_int) do
          nil ->
            send(self(), {:show_error, "Option not found"})
            {:noreply, socket}

          poll_option ->
            # Check authorization
            if socket.assigns.is_creator || poll_option.suggested_by_id == socket.assigns.user.id do
              case Events.update_poll_option(poll_option, option_params) do
                {:ok, updated_option} ->
                  # Note: Broadcasting handled by parent component

                  send(self(), {:option_updated, updated_option})
                  {:noreply, assign(socket, :editing_option_id, nil)}

                {:error, changeset} ->
                  {:noreply, assign(socket, :edit_changeset, changeset)}
              end
            else
              send(self(), {:show_error, "Not authorized to edit this option"})
              {:noreply, socket}
            end
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_option", %{"option-id" => option_id}, socket) do
    case safe_string_to_integer(option_id) do
      {:ok, option_id_int} ->
        case Events.get_poll_option(option_id_int) do
          nil -> 
            send(self(), {:show_error, "Option not found"})
            {:noreply, socket}
          poll_option ->
            if socket.assigns.is_creator || Events.can_delete_option_based_on_poll_settings?(poll_option, socket.assigns.user) do
              case Events.delete_poll_option(poll_option) do
                {:ok, _} ->
                  # Note: Broadcasting handled by parent component
                  send(self(), {:option_deleted, poll_option})
                  {:noreply, socket}
                {:error, _} ->
                  send(self(), {:show_error, "Failed to delete option"})
                  {:noreply, socket}
              end
            else
              send(self(), {:show_error, "Not authorized to delete this option"})
              {:noreply, socket}
            end
        end
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_suggestion_form", _params, socket) do
    send(self(), {:toggle_suggestion_form})
    {:noreply, socket}
  end

  defp safe_poll_options_empty?(poll_options) do
    case poll_options do
      %Ecto.Association.NotLoaded{} -> true
      poll_options when is_list(poll_options) -> Enum.empty?(poll_options)
      _ -> true
    end
  end

  defp sort_poll_options(poll_options, poll_type) do
    case poll_options do
      %Ecto.Association.NotLoaded{} -> []
      poll_options when is_list(poll_options) ->
        case poll_type do
          "time" ->
            # Sort time options chronologically
            Enum.sort_by(poll_options, fn option ->
              case Time.from_iso8601("#{option.title}:00") do
                {:ok, time} -> Time.to_seconds_after_midnight(time)
                {:error, _} -> 0
              end
            end)
          "date_selection" ->
            # Sort date options chronologically
            Enum.sort_by(poll_options, fn option ->
              case Date.from_iso8601(option.title) do
                {:ok, date} -> Date.to_erl(date)
                {:error, _} -> {0, 0, 0}
              end
            end)
          _ ->
            # Sort by order_index for other poll types
            Enum.sort_by(poll_options, & &1.order_index)
        end
      _ -> []
    end
  end

  defp get_user_display_name(nil), do: "Unknown"
  defp get_user_display_name(user) do
    user.name || user.username || user.email || "Unknown"
  end

  defp safe_string_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_format}
    end
  end
  defp safe_string_to_integer(_), do: {:error, :invalid_input}

end