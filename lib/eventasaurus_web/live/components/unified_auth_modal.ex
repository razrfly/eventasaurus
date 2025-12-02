defmodule EventasaurusWeb.UnifiedAuthModal do
  @moduledoc """
  A unified LiveView component that handles all authentication flows for anonymous users.

  This modal preserves the original email/magic link functionality and adds social auth options
  (Facebook, Google) as supplementary authentication methods for different use cases.

  ## Attributes:
  - mode: :interest | :registration | :voting (required)
  - event: Event struct (required for interest/registration modes)
  - poll: Poll struct (required for voting mode)
  - show: Whether to show the modal
  - on_close: Event to close modal
  - class: Additional CSS classes
  - temp_votes: Temporary votes for voting mode (optional)
  - poll_options: Poll options for voting mode (optional)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.UnifiedAuthModal}
        id="auth-modal"
        mode={:interest}
        event={@event}
        show={@show_auth_modal}
        on_close="close_auth_modal"
      />
  """

  use EventasaurusWeb, :live_component
  import EventasaurusWeb.CoreComponents

  alias EventasaurusApp.Services.UserRegistrationService

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)
     |> assign(:step, :email_capture)
     |> assign(:email, "")
     |> assign(:name, "")
     |> assign(:form_errors, %{})}
  end

  @impl true
  def update(assigns, socket) do
    mode = Map.get(assigns, :mode, :interest)

    # Build the form based on mode - registration/voting need name, interest only needs email
    form_data =
      case mode do
        mode when mode in [:registration, :voting] ->
          %{"email" => socket.assigns[:email] || "", "name" => socket.assigns[:name] || ""}

        _ ->
          %{"email" => socket.assigns[:email] || ""}
      end

    form = to_form(form_data, as: :auth)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show, fn -> false end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:temp_votes, fn -> %{} end)
     |> assign_new(:poll_options, fn -> [] end)
     |> assign(:mode, mode)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"auth" => params}, socket) do
    errors = validate_params(params, socket.assigns.mode)
    # Convert our error map to the format Phoenix forms expect
    # Phoenix forms expect a keyword list with {message, opts} tuples
    form_errors = Enum.map(errors, fn {field, message} -> {field, {message, []}} end)
    form = to_form(params, errors: form_errors, as: :auth)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:form_errors, errors)}
  end

  @impl true
  def handle_event("submit", %{"auth" => params}, socket) do
    case validate_params(params, socket.assigns.mode) do
      errors when map_size(errors) == 0 ->
        handle_magic_link_submission(socket, params)

      errors ->
        # Convert our error map to the format Phoenix forms expect
        # Phoenix forms expect a keyword list with {message, opts} tuples
        form_errors = Enum.map(errors, fn {field, message} -> {field, {message, []}} end)
        form = to_form(params, errors: form_errors, as: :auth)
        {:noreply, assign(socket, :form, form)}
    end
  end

  @impl true
  def handle_event("facebook_auth", _params, socket) do
    handle_social_auth(socket, :facebook)
  end

  @impl true
  def handle_event("google_auth", _params, socket) do
    handle_social_auth(socket, :google)
  end

  @impl true
  def handle_event("close", _params, socket) do
    # Send close event to parent LiveView
    close_event = socket.assigns.on_close

    # Use existing atoms for known events, otherwise send as string
    message =
      case close_event do
        "close_interest_modal" -> :close_interest_modal
        "close_registration_modal" -> :close_registration_modal
        "close_vote_modal" -> :close_vote_modal
        event when is_atom(event) -> event
        event when is_binary(event) -> {:close_modal, event}
        _ -> :close_modal
      end

    send(self(), message)
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
    <div class={if @show, do: "", else: "hidden"} phx-hook="ModalCleanup" id={"modal-cleanup-#{@id}"}>
      <style>
        #modal-<%= @id %> [class*="max-w-"] {
          max-width: 24rem !important; /* 384px - standard modal width */
        }
        @media (min-width: 640px) {
          #modal-<%= @id %> [class*="max-w-"] {
            max-width: 28rem !important; /* 448px - standard modal width */
          }
        }
        @media (min-width: 768px) {
          #modal-<%= @id %> [class*="max-w-"] {
            max-width: 27rem !important; /* ~432px (85% of 32rem/512px) */
          }
        }
        @media (min-width: 1024px) {
          #modal-<%= @id %> [class*="max-w-"] {
            max-width: 36rem !important; /* ~576px (85% of 42rem/672px) */
          }
        }
        @media (min-width: 1280px) {
          #modal-<%= @id %> [class*="max-w-"] {
            max-width: 41rem !important; /* ~656px (85% of 48rem/768px) */
          }
        }
      </style>
      <.modal
        id={"modal-#{@id}"}
        show={@show}
        on_cancel={JS.push("close", target: @myself) |> hide_modal("modal-#{@id}")}
      >
        <:title>
          <%= get_modal_title(assigns) %>
        </:title>

        <%= case @step do %>
          <% :email_capture -> %>
            <%= render_email_form(assigns) %>
          <% :check_email -> %>
            <%= render_check_email(assigns) %>
        <% end %>
      </.modal>
    </div>
    """
  end

  # ============ HELPER FUNCTIONS ============

  defp get_modal_title(assigns) do
    mode_config = get_mode_config(assigns.mode, assigns)
    mode_config.title
  end

  defp render_email_form(assigns) do
    ~H"""
    <div class="space-y-6">
      <p class="text-gray-600">
        <%= get_mode_config(@mode, assigns).form_description %>
      </p>

      <%= if @mode == :voting and has_temp_votes?(@temp_votes) do %>
        <!-- Vote Summary for voting mode -->
        <div class="p-4 bg-gray-50 rounded-lg border border-gray-200">
          <h4 class="text-sm font-medium text-gray-900 mb-2">Your votes:</h4>
          <%= render_vote_summary(assigns) %>
        </div>
      <% end %>

      <.form
        for={@form}
        phx-submit="submit"
        phx-change="validate"
        phx-target={@myself}
        class="space-y-4"
      >
        <%= if @mode != :interest do %>
          <.input
            field={@form[:name]}
            type="text"
            label="Name"
            placeholder="Enter your name"
            required
            autocomplete="name"
            phx-debounce="300"
          />
        <% end %>

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
          phx-disable-with="Registering..."
          disabled={@loading}
          class="w-full"
        >
          <%= if @loading do %>
            <svg class="animate-spin -ml-1 mr-3 h-4 w-4 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Registering...
          <% else %>
            Register
          <% end %>
        </.button>
      </.form>

      <!-- Social Auth Buttons as Alternative Options -->
      <div class="mt-6">
        <div class="relative">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-gray-300"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="px-2 bg-white text-gray-500">or sign in with</span>
          </div>
        </div>

        <div class="mt-4 space-y-3">
          <!-- Facebook Auth Button -->
          <button
            phx-click="facebook_auth"
            phx-target={@myself}
            disabled={@loading}
            class="w-full bg-white hover:bg-gray-50 disabled:opacity-50 text-gray-700 font-medium py-2 px-3 text-sm rounded-lg border border-gray-300 transition-colors duration-200 flex items-center justify-center"
          >
            <svg class="w-4 h-4 mr-2 text-blue-600" fill="currentColor" viewBox="0 0 24 24">
              <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
            </svg>
            Continue with Facebook
          </button>

          <!-- Google Auth Button -->
          <button
            phx-click="google_auth"
            phx-target={@myself}
            disabled={@loading}
            class="w-full bg-white hover:bg-gray-50 disabled:opacity-50 text-gray-700 font-medium py-2 px-3 text-sm rounded-lg border border-gray-300 transition-colors duration-200 flex items-center justify-center"
          >
            <svg class="w-4 h-4 mr-2" viewBox="0 0 24 24">
              <path fill="#4285f4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
              <path fill="#34a853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
              <path fill="#fbbc05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
              <path fill="#ea4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
            </svg>
            Continue with Google
          </button>
        </div>
      </div>

      <p class="text-xs text-gray-500 text-center">
        We'll create an account for you and send a magic link to your email.
        No password required - just click the link to access your account.
      </p>
    </div>
    """
  end

  defp render_check_email(assigns) do
    ~H"""
    <div class="space-y-6 text-center">
      <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-green-100">
        <svg class="h-6 w-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
        </svg>
      </div>

      <div>
        <h3 class="text-base font-medium text-gray-900 mb-2">Magic Link Sent!</h3>
        <p class="text-gray-600 mb-4">
          We've sent a magic link to <strong><%= @email %></strong>
        </p>
        <p class="text-sm text-gray-500">
          Click the link in your email to complete authentication and 
          <%= get_mode_config(@mode, assigns).completion_text %>.
          The link will expire in 1 hour.
        </p>
      </div>

      <div class="flex space-x-3 justify-center">
        <.button
          phx-click="reset"
          phx-target={@myself}
          class="bg-gray-100 hover:bg-gray-200 text-gray-800"
        >
          Try Again
        </.button>
        <.button
          phx-click="close"
          phx-target={@myself}
        >
          Got It
        </.button>
      </div>
    </div>
    """
  end

  defp render_vote_summary(assigns) do
    ~H"""
    <%= case @temp_votes do %>
      <% votes when is_map(votes) and not is_map_key(votes, :poll_type) -> %>
        <!-- Legacy format - simple map -->
        <%= for {option_id, vote_value} <- votes do %>
          <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
          <%= if option do %>
            <div class="flex justify-between items-center text-sm py-1">
              <span class="text-gray-700">
                <%= option.title %>
              </span>
              <span class="font-medium text-blue-600">
                <%= format_vote_value(vote_value) %>
              </span>
            </div>
          <% end %>
        <% end %>

      <% %{poll_type: poll_type, votes: votes} -> %>
        <!-- New format with poll_type -->
        <%= render_typed_vote_summary(assigns, poll_type, votes) %>

      <% _ -> %>
        <div class="text-sm text-gray-500">No votes to display</div>
    <% end %>
    """
  end

  defp render_typed_vote_summary(assigns, poll_type, votes) do
    case poll_type do
      :binary ->
        render_binary_vote_summary(assigns, votes)

      :approval ->
        render_approval_vote_summary(assigns, votes)

      :ranked ->
        render_ranked_vote_summary(assigns, votes)

      :star ->
        render_star_vote_summary(assigns, votes)
    end
  end

  defp render_binary_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for {option_id, vote_value} <- @votes do %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700">
            <%= option.title %>
          </span>
          <span class={"font-medium " <> get_binary_vote_color(vote_value)}>
            <%= get_binary_vote_display(vote_value) %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp render_approval_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for {option_id, _vote_value} <- @votes do %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700">
            <%= option.title %>
          </span>
          <span class="font-medium text-green-600">
            ✓ Selected
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp render_ranked_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for vote <- @votes |> Enum.sort_by(fn
          %{rank: rank} -> rank
          {_id, rank} -> rank
        end) do %>
      <% {option_id, rank} = case vote do
          %{option_id: oid, rank: r} -> {oid, r}
          {oid, r} -> {oid, r}
         end %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700">
            <%= option.title %>
          </span>
          <span class="font-medium text-blue-600">
            #<%= rank %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp render_star_vote_summary(assigns, votes) do
    assigns = assign(assigns, :votes, votes)

    ~H"""
    <%= for {option_id, stars} <- @votes do %>
      <% option = Enum.find(@poll_options, &(&1.id == option_id)) %>
      <%= if option do %>
        <div class="flex justify-between items-center text-sm py-1">
          <span class="text-gray-700">
            <%= option.title %>
          </span>
          <span class="font-medium text-yellow-600">
            <%= String.duplicate("⭐", stars) %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  # ============ PRIVATE FUNCTIONS ============

  defp get_mode_config(:interest, assigns) do
    %{
      title: "Express Interest in #{assigns.event.title}",
      form_description:
        "Enter your email address to receive a magic link. Once you click the link, we'll automatically register your interest in this event.",
      completion_text: "register your interest"
    }
  end

  defp get_mode_config(:registration, assigns) do
    intended_status = Map.get(assigns, :intended_status, :accepted)

    case intended_status do
      :interested ->
        %{
          title: "Register Your Interest",
          form_description: "We'll create an account for you so you can manage your interest.",
          completion_text: "register your interest"
        }

      _ ->
        %{
          title: "Register for #{assigns.event.title}",
          form_description:
            "We'll create an account for you so you can manage your registration.",
          completion_text: "complete your registration"
        }
    end
  end

  defp get_mode_config(:voting, _assigns) do
    %{
      title: "Save Your Votes",
      form_description:
        "Enter your details to save these votes. You'll receive a magic link via email to create your account.",
      completion_text: "save your votes"
    }
  end

  defp validate_params(params, mode) do
    errors = %{}

    # Email is always required
    errors =
      if params["email"] == nil or String.trim(params["email"]) == "" do
        Map.put(errors, :email, "Email is required")
      else
        # More robust email validation pattern
        if String.match?(params["email"], ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/) do
          errors
        else
          Map.put(errors, :email, "Please enter a valid email address")
        end
      end

    # Name is required for registration and voting modes
    errors =
      if mode in [:registration, :voting] do
        if params["name"] == nil or String.trim(params["name"]) == "" do
          Map.put(errors, :name, "Name is required")
        else
          errors
        end
      else
        errors
      end

    errors
  end

  defp handle_magic_link_submission(socket, form_data) do
    socket = assign(socket, :loading, true)

    case socket.assigns.mode do
      :interest ->
        handle_interest_magic_link(socket, form_data)

      :registration ->
        handle_registration_magic_link(socket, form_data)

      :voting ->
        handle_voting_magic_link(socket, form_data)
    end
  end

  defp handle_interest_magic_link(socket, form_data) do
    email = form_data["email"]
    # Use email prefix as name for interest registration
    name = email |> String.split("@") |> List.first()
    event_id = socket.assigns.event.id

    case UserRegistrationService.register_user(email, name, :interest, event_id: event_id) do
      {:ok, %{user: _user, participant: _participant}} ->
        send(socket.parent_pid, {:interest_registered, email})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:step, :check_email)
         |> assign(:email, email)}

      {:error, reason} ->
        error_message = format_auth_error(reason)
        send(socket.parent_pid, {:interest_error, error_message})

        {:noreply, assign(socket, :loading, false)}
    end
  end

  defp handle_registration_magic_link(socket, form_data) do
    %{"name" => name, "email" => email} = form_data

    case EventasaurusApp.Events.register_user_for_event(socket.assigns.event.id, name, email) do
      {:ok, :new_registration, _participant} ->
        intended_status = Map.get(socket.assigns, :intended_status, :accepted)
        send(self(), {:registration_success, :new_registration, name, email, intended_status})
        {:noreply, assign(socket, :loading, false)}

      {:ok, :existing_user_registered, _participant} ->
        intended_status = Map.get(socket.assigns, :intended_status, :accepted)

        send(
          self(),
          {:registration_success, :existing_user_registered, name, email, intended_status}
        )

        {:noreply, assign(socket, :loading, false)}

      {:error, :already_registered} ->
        send(self(), {:registration_error, :already_registered})
        {:noreply, assign(socket, :loading, false)}

      {:error, reason} ->
        send(self(), {:registration_error, reason})
        {:noreply, assign(socket, :loading, false)}
    end
  end

  defp handle_voting_magic_link(socket, form_data) do
    %{"name" => name, "email" => email} = form_data
    temp_votes = socket.assigns.temp_votes

    if has_temp_votes?(temp_votes) do
      # Send appropriate message based on poll type
      case socket.assigns[:poll] do
        nil ->
          send(self(), {:vote_error, :no_poll})

        %{poll_type: "date_selection"} ->
          send(
            self(),
            {:save_all_votes_for_user, socket.assigns.event.id, name, email, temp_votes,
             socket.assigns.poll_options}
          )

        poll ->
          send(
            self(),
            {:save_all_poll_votes_for_user, poll.id, name, email, temp_votes,
             socket.assigns.poll_options}
          )
      end

      {:noreply, assign(socket, :loading, false)}
    else
      send(self(), {:vote_error, :no_votes})
      {:noreply, assign(socket, :loading, false)}
    end
  end

  defp handle_social_auth(socket, provider) do
    # Build context for social auth
    context = %{
      mode: socket.assigns.mode,
      event_id: if(socket.assigns[:event], do: socket.assigns.event.id, else: nil),
      poll_id: if(socket.assigns[:poll], do: socket.assigns.poll.id, else: nil),
      temp_votes: socket.assigns.temp_votes,
      intended_status: Map.get(socket.assigns, :intended_status, :accepted)
    }

    # Create auth URL with context parameters
    auth_url =
      case provider do
        :facebook -> "/auth/facebook"
        :google -> "/auth/google"
      end

    # Build full URL with context
    context_json = context |> Jason.encode!() |> URI.encode()
    action = Atom.to_string(socket.assigns.mode)
    full_url = "#{auth_url}?action=#{action}&context=#{context_json}"

    # Use JavaScript redirect to navigate with context
    {:noreply, push_navigate(socket, to: full_url, replace: false)}
  end

  defp format_auth_error(reason) do
    case reason do
      %{message: msg} -> msg
      %Ecto.Changeset{} = changeset ->
        Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
        |> Enum.join("; ")
      %{status: 422} -> "Invalid email address. Please check and try again."
      %{status: 429} -> "Too many requests. Please wait a moment and try again."
      :already_registered -> "You're already registered for this event."
      _ -> "Unable to complete registration. Please try again."
    end
  end

  defp has_temp_votes?(temp_votes) when is_map(temp_votes) do
    case temp_votes do
      %{poll_type: _type, votes: votes} when is_map(votes) ->
        map_size(votes) > 0

      votes when is_map(votes) ->
        map_size(votes) > 0

      _ ->
        false
    end
  end

  defp reset_modal_state(socket) do
    form = to_form(%{"name" => "", "email" => ""}, as: :auth)

    socket
    |> assign(:loading, false)
    |> assign(:step, :email_capture)
    |> assign(:email, "")
    |> assign(:name, "")
    |> assign(:form_errors, %{})
    |> assign(:form, form)
  end

  # Helper functions for vote display (copied from AnonymousVoterComponent)

  defp get_binary_vote_color(vote_value) do
    case vote_value do
      "yes" -> "text-green-600"
      "no" -> "text-red-600"
      "maybe" -> "text-yellow-600"
    end
  end

  defp get_binary_vote_display(vote_value) do
    case vote_value do
      "yes" -> "👍 Yes"
      "no" -> "👎 No"
      "maybe" -> "🤷 Maybe"
    end
  end

  defp format_vote_value(vote_value) when is_binary(vote_value), do: vote_value
  defp format_vote_value(vote_value) when is_atom(vote_value), do: Atom.to_string(vote_value)
  defp format_vote_value(vote_value), do: inspect(vote_value)
end
