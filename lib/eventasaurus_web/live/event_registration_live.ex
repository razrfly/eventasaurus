defmodule EventasaurusWeb.EventRegistrationComponent do
  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Events

  def update(assigns, socket) do
    initial_data = %{"name" => "", "email" => ""}
    form = to_form(initial_data)
    intended_status = Map.get(assigns, :intended_status, :accepted)
    modal_texts = get_modal_texts(intended_status)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:form_data, initial_data)
     |> assign(:loading, false)
     |> assign(:intended_status, intended_status)
     |> assign(:modal_texts, modal_texts)
    }
  end

  def handle_event("validate", %{"registration" => params}, socket) do
    # Merge new params with existing form data to preserve all fields
    existing_data = socket.assigns.form_data
    merged_data = Map.merge(existing_data, params)

    IO.puts("=== VALIDATE DEBUG ===")
    IO.inspect(params, label: "Incoming params")
    IO.inspect(existing_data, label: "Existing data")
    IO.inspect(merged_data, label: "Merged data")

    # Basic client-side validation
    errors = validate_registration_params(merged_data)
    form = to_form(merged_data, errors: errors)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:form_data, merged_data)
    }
  end

  def handle_event("submit", %{"registration" => params}, socket) do
    # Use the stored form data merged with final params
    existing_data = socket.assigns.form_data
    final_data = Map.merge(existing_data, params)
    %{"name" => name, "email" => email} = final_data

    # Validate inputs
    case validate_registration_params(final_data) do
      errors when map_size(errors) == 0 ->
        # Valid input, proceed with registration
        socket = assign(socket, :loading, true)

        case Events.register_user_for_event(socket.assigns.event.id, name, email) do
          {:ok, :new_registration, _participant} ->
            send(self(), {:registration_success, :new_registration, name, email, socket.assigns.intended_status})
            {:noreply, assign(socket, :loading, false)}

          {:ok, :existing_user_registered, _participant} ->
            send(self(), {:registration_success, :existing_user_registered, name, email, socket.assigns.intended_status})
            {:noreply, assign(socket, :loading, false)}

          {:error, :already_registered} ->
            send(self(), {:registration_error, :already_registered})
            {:noreply, assign(socket, :loading, false)}

          {:error, reason} ->
            send(self(), {:registration_error, reason})
            {:noreply, assign(socket, :loading, false)}
        end

      errors ->
        # Invalid input, show errors
        form = to_form(final_data, errors: errors)
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("close", _params, socket) do
    send(self(), :close_registration_modal)
    {:noreply, socket}
  end

  def handle_event("stop_propagation", _params, socket) do
    # This handler exists to prevent click event propagation
    # When someone clicks inside the modal, this stops the event from
    # bubbling up to the overlay's close handler
    {:noreply, socket}
  end

  defp validate_registration_params(%{"name" => name, "email" => email}) do
    errors = %{}

    errors = if name == nil or String.trim(name) == "" do
      Map.put(errors, :name, "Name is required")
    else
      errors
    end

    errors = if email == nil or String.trim(email) == "" do
      Map.put(errors, :email, "Email is required")
    else
      # Basic email validation
      if String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
        errors
      else
        Map.put(errors, :email, "Please enter a valid email address")
      end
    end

    errors
  end

  defp get_modal_texts(intended_status) do
    case intended_status do
      :interested ->
        %{
          title: "Register Your Interest",
          description: "We'll create an account for you so you can manage your interest.",
          button: "Register Interest"
        }
      _ ->
        %{
          title: "Register for Event",
          description: "We'll create an account for you so you can manage your registration.",
          button: "Register for Event"
        }
    end
  end

  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50" phx-click="close" phx-target={@myself}>
      <!-- Registration Modal Overlay -->
      <div class="bg-white rounded-xl max-w-md w-full mx-auto shadow-2xl" phx-click="stop_propagation" phx-target={@myself}>
        <!-- Modal Header -->
        <div class="flex items-center justify-between p-6 border-b border-gray-100">
          <div>
            <h2 class="text-xl font-semibold text-gray-900"><%= @modal_texts.title %></h2>
            <p class="text-sm text-gray-500 mt-1"><%= @event.title %></p>
          </div>
          <button
            phx-click="close"
            phx-target={@myself}
            class="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <!-- Modal Body -->
        <div class="p-6">
          <div class="mb-6">
            <h3 class="text-lg font-medium text-gray-900 mb-2">Your Info</h3>
            <p class="text-sm text-gray-600"><%= @modal_texts.description %></p>
          </div>

          <.form
            for={@form}
            phx-change="validate"
            phx-submit="submit"
            phx-target={@myself}
            class="space-y-4"
            id="registration-form"
          >
            <!-- Name Field -->
            <div>
              <label for="registration_name" class="block text-sm font-medium text-gray-700 mb-2">
                Name <span class="text-red-500">*</span>
              </label>
              <input
                type="text"
                name="registration[name]"
                id="registration_name"
                value={@form_data["name"] || ""}
                placeholder="Your Name"
                required
                phx-change="validate"
                phx-debounce="300"
                phx-target={@myself}
                class="w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors"
                disabled={@loading}
              />
              <%= if @form.errors[:name] do %>
                <p class="text-red-500 text-sm mt-1"><%= @form.errors[:name] %></p>
              <% end %>
            </div>

            <!-- Email Field -->
            <div>
              <label for="registration_email" class="block text-sm font-medium text-gray-700 mb-2">
                Email <span class="text-red-500">*</span>
              </label>
              <input
                type="email"
                name="registration[email]"
                id="registration_email"
                value={@form_data["email"] || ""}
                placeholder="your@email.com"
                required
                phx-change="validate"
                phx-debounce="300"
                phx-target={@myself}
                class="w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors"
                disabled={@loading}
              />
              <%= if @form.errors[:email] do %>
                <p class="text-red-500 text-sm mt-1"><%= @form.errors[:email] %></p>
              <% end %>
            </div>

            <!-- Submit Button -->
            <div class="pt-4">
              <button
                type="submit"
                disabled={@loading}
                class="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed text-white font-semibold py-3 px-6 rounded-xl transition-colors flex items-center justify-center"
              >
                <%= if @loading do %>
                  <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  <%= if @intended_status == :interested, do: "Registering Interest...", else: "Registering..." %>
                <% else %>
                  <%= @modal_texts.button %>
                <% end %>
              </button>
            </div>
          </.form>

          <!-- Info Text -->
          <div class="mt-6 space-y-2 text-center">
            <p class="text-xs text-gray-500">
              By registering, you'll receive a magic link via email to create your account.
            </p>
            <p class="text-xs text-gray-500">
              No password required - just click the link to access your account.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
