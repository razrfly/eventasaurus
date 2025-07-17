defmodule EventasaurusWeb.InterestAuthModal do
  @moduledoc """
  A LiveView component that handles authentication flow for anonymous users expressing interest.

  This modal captures an email address, sends a magic link via Supabase, and guides the user
  through the authentication process to register their interest in an event.

  ## Attributes:
  - event: Event struct (required)
  - show: Whether to show the modal
  - on_close: Event to close modal
  - class: Additional CSS classes

  ## Usage:
      <.live_component
        module={EventasaurusWeb.InterestAuthModal}
        id="interest-auth-modal"
        event={@event}
        show={@show_interest_modal}
        on_close="close_interest_modal"
      />
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents

  alias EventasaurusApp.Auth

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:step, :email_capture)
     |> assign(:email, "")
     |> assign(:form_errors, %{})}
  end

  @impl true
  def update(assigns, socket) do
    form = to_form(%{"email" => socket.assigns.email}, as: :interest_auth)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show, fn -> false end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:on_close, fn -> nil end)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"interest_auth" => %{"email" => email}}, socket) do
    errors = validate_email(email)
    form = to_form(%{"email" => email}, errors: errors, as: :interest_auth)

    {:noreply,
     socket
     |> assign(:email, email)
     |> assign(:form_errors, errors)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("submit", %{"interest_auth" => %{"email" => email}}, socket) do
    case validate_email(email) do
      errors when map_size(errors) == 0 ->
        # Valid email, send magic link
        socket = assign(socket, :loading, true)

        # Include event ID in user metadata for post-auth processing
        user_metadata = %{
          "name" => email |> String.split("@") |> List.first(),
          "pending_interest_event_id" => socket.assigns.event.id
        }

        case Auth.send_magic_link(email, user_metadata) do
          {:ok, _} ->
            # Send message to parent LiveView
            send(socket.parent_pid, {:magic_link_sent, email})

            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:step, :check_email)
             |> assign(:email, email)}

          {:error, reason} ->
            error_message = case reason do
              %{message: msg} -> msg
              %{status: 422} -> "Invalid email address. Please check and try again."
              %{status: 429} -> "Too many requests. Please wait a moment and try again."
              _ -> "Unable to send magic link. Please try again."
            end

            # Send error to parent LiveView
            send(socket.parent_pid, {:magic_link_error, error_message})

            {:noreply,
             socket
             |> assign(:loading, false)}
        end

      errors ->
        # Invalid email, show errors
        form = to_form(%{"email" => email}, errors: errors, as: :interest_auth)
        {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    # Send close event to parent LiveView
    send(socket.parent_pid, {:close_interest_modal})
    {:noreply, reset_modal_state(socket)}
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # Prevent click events from bubbling up to overlay close handler
    {:noreply, socket}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply, reset_modal_state(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @show do %>
      <.modal
        id={@myself}
        show={@show}
        on_cancel={if @on_close, do: JS.push(@on_close), else: JS.push("close", target: @myself)}
      >
        <:title>
          <%= case @step do %>
            <% :email_capture -> %>
              Express Interest in <%= @event.title %>
            <% :check_email -> %>
              Check Your Email
          <% end %>
        </:title>

        <%= case @step do %>
          <% :email_capture -> %>
            <div class="space-y-6">
              <p class="text-gray-600">
                Enter your email address to receive a magic link. Once you click the link,
                we'll automatically register your interest in this event.
              </p>

              <.form
                for={@form}
                phx-submit="submit"
                phx-change="validate"
                phx-target={@myself}
                class="space-y-4"
              >
                <.input
                  field={@form[:email]}
                  type="email"
                  label="Email Address"
                  placeholder="Enter your email address"
                  required
                  autocomplete="email"
                  phx-debounce="300"
                />

                <.button
                  type="submit"
                  phx-disable-with="Sending magic link..."
                  disabled={@loading}
                  class="w-full"
                >
                  <%= if @loading do %>
                    <svg class="animate-spin -ml-1 mr-3 h-4 w-4 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    Sending...
                  <% else %>
                    Send Magic Link
                  <% end %>
                </.button>
              </.form>
            </div>

          <% :check_email -> %>
            <div class="space-y-6 text-center">
              <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-green-100">
                <svg class="h-6 w-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
              </div>

              <div>
                <h3 class="text-lg font-medium text-gray-900 mb-2">Magic Link Sent!</h3>
                <p class="text-gray-600 mb-4">
                  We've sent a magic link to <strong><%= @email %></strong>
                </p>
                <p class="text-sm text-gray-500">
                  Click the link in your email to complete authentication and register your interest.
                  The link will expire in 1 hour.
                </p>
              </div>

              <div class="flex space-x-3 justify-center">
                <.button
                  phx-click="reset"
                  phx-target={@myself}
                  class="bg-gray-100 hover:bg-gray-200 text-gray-800"
                >
                  Try Different Email
                </.button>
                <.button
                  phx-click={if @on_close, do: @on_close, else: "close"}
                  phx-target={if @on_close, do: nil, else: @myself}
                >
                  Got It
                </.button>
              </div>
            </div>
        <% end %>
      </.modal>
    <% end %>
    """
  end

  # ============ PRIVATE FUNCTIONS ============

  defp validate_email(email) when is_binary(email) do
    email = String.trim(email)

    cond do
      email == "" ->
        [email: "Email is required"]

      not String.contains?(email, "@") ->
        [email: "Please enter a valid email address"]

      String.length(email) > 255 ->
        [email: "Email address is too long"]

      not Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email) ->
        [email: "Please enter a valid email address"]

      true ->
        %{}
    end
  end

  defp validate_email(_), do: [email: "Email is required"]

  defp reset_modal_state(socket) do
    form = to_form(%{"email" => ""}, as: :interest_auth)

    socket
    |> assign(:loading, false)
    |> assign(:step, :email_capture)
    |> assign(:email, "")
    |> assign(:form_errors, %{})
    |> assign(:form, form)
  end
end
