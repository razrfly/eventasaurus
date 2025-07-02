defmodule EventasaurusWeb.UsernameInputComponent do
  use EventasaurusWeb, :live_component

  @doc """
  A reusable username input component with real-time availability checking.

  ## Attributes:
  - field: Phoenix.HTML.FormField (required) - The form field for username
  - debounce: integer (default: 500) - Debounce delay in milliseconds
  - placeholder: string (default: "Enter a username") - Input placeholder
  - required: boolean (default: false) - Whether the field is required
  - class: string (default: "") - Additional CSS classes

  ## Usage:
      <.live_component
        module={EventasaurusWeb.UsernameInputComponent}
        id="username-input"
        field={@form[:username]}
        debounce={500}
        placeholder="Choose your username"
        required={true}
      />
  """

  def mount(socket) do
    {:ok,
     socket
     |> assign(:checking, false)
     |> assign(:check_result, nil)
     |> assign(:last_checked_username, nil)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:debounce, fn -> 500 end)
     |> assign_new(:placeholder, fn -> "Enter a username" end)
     |> assign_new(:required, fn -> false end)
     |> assign_new(:class, fn -> "" end)}
  end

  def handle_event("check_username", %{"value" => username}, socket) do
    username = String.trim(username)

    # Don't check if it's the same username we just checked
    if username == socket.assigns.last_checked_username do
      {:noreply, socket}
    else
      # Clear previous results and show loading state for non-empty usernames
      socket = if username != "" do
        socket
        |> assign(:checking, true)
        |> assign(:check_result, nil)
      else
        socket
        |> assign(:checking, false)
        |> assign(:check_result, nil)
      end

      if username != "" do
        # Make HTTP request to check availability
        send(self(), {:check_username_async, username, socket.assigns.id})
      end

      {:noreply, assign(socket, :last_checked_username, username)}
    end
  end

  def handle_info({:username_check_result, username, result, component_id}, socket) do
    # Only process if this result is for our component and the current username
    if component_id == socket.assigns.id and username == socket.assigns.last_checked_username do
      {:noreply,
       socket
       |> assign(:checking, false)
       |> assign(:check_result, result)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div phx-feedback-for={@field.name}>
      <.label for={@field.id}>
        Username
        <%= if @required do %>
          <span class="text-red-500">*</span>
        <% end %>
      </.label>

      <div class="relative mt-1">
        <input
          type="text"
          name={@field.name}
          id={@field.id}
          value={@field.value || ""}
          placeholder={@placeholder}
          required={@required}
          phx-change="check_username"
          phx-debounce={@debounce}
          phx-target={@myself}
          class={[
            "block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 pr-10",
            "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
            get_input_border_class(@check_result, @field.errors),
            @class
          ]}
        />

        <!-- Status indicator -->
        <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none">
          <%= cond do %>
            <% @checking -> %>
              <!-- Loading spinner -->
              <svg class="animate-spin h-4 w-4 text-gray-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>

            <% @check_result && @check_result["available"] == true -> %>
              <!-- Available/success checkmark -->
              <svg class="h-4 w-4 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
              </svg>

            <% @check_result && @check_result["available"] == false -> %>
              <!-- Not available/error X -->
              <svg class="h-4 w-4 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>

            <% true -> %>
              <!-- No status -->
          <% end %>
        </div>
      </div>

      <!-- Validation messages -->
      <div class="mt-1 text-sm">
        <%= if @check_result && @check_result["errors"] && length(@check_result["errors"]) > 0 do %>
          <div class="text-red-600">
            <%= for error <- @check_result["errors"] do %>
              <p><%= error %></p>
            <% end %>
          </div>
        <% end %>

        <%= if @check_result && @check_result["available"] == true do %>
          <p class="text-green-600">✓ Username is available</p>
        <% end %>

        <!-- Suggestions -->
        <%= if @check_result && @check_result["suggestions"] && length(@check_result["suggestions"]) > 0 do %>
          <div class="mt-2">
            <p class="text-gray-600 text-xs mb-1">Suggestions:</p>
            <div class="flex flex-wrap gap-1">
              <%= for suggestion <- @check_result["suggestions"] do %>
                <button
                  type="button"
                  phx-click={JS.dispatch("input", detail: %{value: suggestion}, to: "##{@field.id}")}
                  class="px-2 py-1 text-xs bg-gray-100 hover:bg-gray-200 rounded text-gray-700 transition-colors"
                >
                  <%= suggestion %>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Form validation errors (fallback) -->
        <%= for error <- @field.errors do %>
          <p class="text-red-600"><%= elem(error, 0) %></p>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper function to determine input border color based on validation state
  defp get_input_border_class(check_result, form_errors) do
    cond do
      # Form validation errors take precedence
      form_errors != [] ->
        "border-red-400 focus:border-red-400"

      # API validation results
      check_result && check_result["available"] == true ->
        "border-green-400 focus:border-green-400"

      check_result && check_result["available"] == false ->
        "border-red-400 focus:border-red-400"

      # Default state
      true ->
        "border-zinc-300 focus:border-zinc-400"
    end
  end
end
