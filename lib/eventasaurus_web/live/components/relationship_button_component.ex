defmodule EventasaurusWeb.RelationshipButtonComponent do
  @moduledoc """
  A LiveComponent for connecting/disconnecting with other users.

  This component provides a reusable connection button that handles both
  authenticated and unauthenticated users with appropriate visual feedback.
  Unlike follows, relationships require context (how you know each other).

  ## Features

  - Real-time connect/disconnect toggle for authenticated users
  - Auth modal trigger for unauthenticated users
  - Loading state with spinner animation
  - Shows relationship context when connected
  - Triggers context modal for new connections
  - Rate limiting feedback (shows error message if rate limited)

  ## Required Assigns

  - `id` - Unique identifier for the component (e.g., "connect-user-123")
  - `other_user` - The user struct to connect with
  - `current_user` - The current user struct (nil if not logged in)

  ## Optional Assigns

  - `event` - The event where users met (for auto-generating context)
  - `class` - Additional CSS classes (default: "")
  - `size` - Button size: "sm", "md", or "lg" (default: "md")
  - `variant` - Button style: "primary" or "outline" (default: "primary")
  - `show_context` - Whether to show relationship context on hover (default: true)

  ## Usage

      <.live_component
        module={EventasaurusWeb.RelationshipButtonComponent}
        id={"connect-user-\#{user.id}"}
        other_user={user}
        current_user={@current_user}
        event={@event}
      />

  ## Events

  When the user is not authenticated and clicks the button, this component
  sends `{:show_auth_modal, :connect}` to the parent LiveView.

  When connecting and context is needed, this component sends
  `{:show_connect_modal, other_user, suggested_context}` to the parent.
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Relationships

  @impl true
  def mount(socket) do
    {:ok, assign(socket, loading: false, error: nil, confirming_disconnect: false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_connection_status()

    {:ok, socket}
  end

  @spec assign_connection_status(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_connection_status(socket) do
    current_user = socket.assigns[:current_user]
    other_user = socket.assigns[:other_user]

    {is_connected, relationship} =
      case current_user do
        nil ->
          {false, nil}

        user ->
          rel = Relationships.get_relationship_between(user, other_user)

          case rel do
            %{status: :active} = r -> {true, r}
            _ -> {false, nil}
          end
      end

    # Check if current user can connect with the other user
    can_connect_result = check_can_connect(current_user, other_user, is_connected)

    socket
    |> assign(:is_connected, is_connected)
    |> assign(:relationship, relationship)
    |> assign(:can_connect, can_connect_result)
  end

  # Check if the initiator can connect with the target
  # Returns :auto_accept, :request_required, :closed, :blocked, :pending_request, :already_connected, or nil (not logged in)
  @spec check_can_connect(map() | nil, map(), boolean()) ::
          :auto_accept
          | :request_required
          | :closed
          | :blocked
          | :pending_request
          | :already_connected
          | nil
  defp check_can_connect(nil, _other_user, _is_connected), do: nil
  defp check_can_connect(_current_user, _other_user, true), do: :already_connected

  defp check_can_connect(current_user, other_user, false) do
    case Relationships.can_connect?(current_user, other_user) do
      {:ok, result} -> result
      {:error, reason} -> reason
    end
  end

  @impl true
  def handle_event("connect", _params, socket) do
    current_user = socket.assigns.current_user
    can_connect = socket.assigns.can_connect

    cond do
      is_nil(current_user) ->
        # User not logged in - trigger auth modal via parent
        send(self(), {:show_auth_modal, :connect})
        {:noreply, socket}

      can_connect == :request_required ->
        # Create a connection request instead of connecting directly
        socket = create_connection_request(socket)
        {:noreply, socket}

      true ->
        # Auto-accept: Connect directly with auto-generated context from event
        event = socket.assigns[:event]
        context = generate_suggested_context(event)
        socket = connect_with_context(socket, context)

        # Notify parent so it can update other components if needed
        if socket.assigns.is_connected do
          send(self(), {:connection_created, socket.assigns.other_user})
        end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    # Show confirmation state
    {:noreply, assign(socket, :confirming_disconnect, true)}
  end

  @impl true
  def handle_event("confirm_disconnect", _params, socket) do
    socket =
      socket
      |> assign(:confirming_disconnect, false)
      |> disconnect()

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_disconnect", _params, socket) do
    {:noreply, assign(socket, :confirming_disconnect, false)}
  end

  @impl true
  def handle_event("connect_with_context", %{"context" => context}, socket) do
    socket = connect_with_context(socket, context)
    {:noreply, socket}
  end

  @spec disconnect(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp disconnect(socket) do
    socket = assign(socket, loading: true, error: nil)

    current_user = socket.assigns.current_user
    other_user = socket.assigns.other_user

    # remove_relationship always returns {:ok, count} - Repo.delete_all doesn't fail
    {:ok, _count} = Relationships.remove_relationship(current_user, other_user)

    socket
    |> assign(:is_connected, false)
    |> assign(:relationship, nil)
    |> assign(:loading, false)
    |> assign(:error, nil)
  end

  @spec create_connection_request(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp create_connection_request(socket) do
    socket = assign(socket, loading: true, error: nil)

    current_user = socket.assigns.current_user
    other_user = socket.assigns.other_user
    event = socket.assigns[:event]

    opts = if event, do: [event: event], else: []

    case Relationships.create_connection_request(current_user, other_user, opts) do
      {:ok, _request} ->
        # Notify parent about the request
        send(self(), {:connection_request_sent, other_user})

        socket
        |> assign(:can_connect, :pending_request)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, %Ecto.Changeset{} = changeset} ->
        error_message = format_changeset_error(changeset)

        socket
        |> assign(:loading, false)
        |> assign(:error, error_message)

      {:error, :already_connected} ->
        # Refresh the component state - they're already connected
        socket
        |> assign(:is_connected, true)
        |> assign(:can_connect, :already_connected)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, :pending_request} ->
        # Already has a pending request
        socket
        |> assign(:can_connect, :pending_request)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, _reason} ->
        assign(socket, loading: false, error: "Could not send request. Please try again.")
    end
  end

  @spec connect_with_context(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  defp connect_with_context(socket, context) do
    socket = assign(socket, loading: true, error: nil)

    current_user = socket.assigns.current_user
    other_user = socket.assigns.other_user
    event = socket.assigns[:event]

    alias EventasaurusApp.Events.Event

    result =
      case event do
        %Event{} = e ->
          # Full Event struct - use create_from_shared_event
          Relationships.create_from_shared_event(current_user, other_user, e, context)

        %{id: _event_id} = _event_map ->
          # Map with event info - use create_manual with context
          # The context will be generated from the event title
          Relationships.create_manual(current_user, other_user, context)

        nil ->
          Relationships.create_manual(current_user, other_user, context)
      end

    case result do
      {:ok, {relationship, _reverse}} ->
        socket
        |> assign(:is_connected, true)
        |> assign(:relationship, relationship)
        |> assign(:loading, false)
        |> assign(:error, nil)

      {:error, %Ecto.Changeset{} = changeset} ->
        error_message = format_changeset_error(changeset)

        socket
        |> assign(:loading, false)
        |> assign(:error, error_message)

      {:error, _reason} ->
        assign(socket, loading: false, error: "Could not connect. Please try again.")
    end
  end

  defp format_changeset_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        atom_key =
          try do
            String.to_existing_atom(key)
          rescue
            ArgumentError -> nil
          end

        opts |> Keyword.get(atom_key, key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  @spec generate_suggested_context(map() | nil) :: String.t()
  defp generate_suggested_context(nil), do: ""

  defp generate_suggested_context(event) do
    date =
      case event.start_at do
        %DateTime{} = dt -> Calendar.strftime(dt, "%B %Y")
        %NaiveDateTime{} = ndt -> Calendar.strftime(ndt, "%B %Y")
        _ -> ""
      end

    if date != "" do
      "Met at #{event.title} - #{date}"
    else
      "Met at #{event.title}"
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> "" end)
      |> assign_new(:size, fn -> "md" end)
      |> assign_new(:variant, fn -> "primary" end)
      |> assign_new(:show_context, fn -> true end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:event, fn -> nil end)
      |> assign_new(:confirming_disconnect, fn -> false end)
      |> assign_new(:can_connect, fn -> nil end)

    ~H"""
    <div class="relative">
      <%= if @confirming_disconnect do %>
        <!-- Confirmation state for disconnect -->
        <div class="flex items-center gap-2">
          <span class="text-sm text-gray-600">Remove?</span>
          <button
            type="button"
            phx-click="confirm_disconnect"
            phx-target={@myself}
            class="px-2 py-1 text-xs font-medium text-white bg-red-600 rounded hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500"
          >
            Yes
          </button>
          <button
            type="button"
            phx-click="cancel_disconnect"
            phx-target={@myself}
            class="px-2 py-1 text-xs font-medium text-gray-700 bg-gray-200 rounded hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-gray-500"
          >
            No
          </button>
        </div>
      <% else %>
        <%= if show_button?(@is_connected, @can_connect) do %>
          <button
            id={@id}
            type="button"
            phx-click={if @is_connected, do: "disconnect", else: "connect"}
            phx-target={@myself}
            disabled={@loading || button_disabled?(@is_connected, @can_connect)}
            class={button_classes(@is_connected, @can_connect, @size, @variant, @class)}
            title={connection_tooltip(@is_connected, @can_connect, @relationship, @show_context, @error)}
          >
            <%= if @loading do %>
              <svg class="animate-spin h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
            <% else %>
              <%= if @is_connected do %>
                <Heroicons.check class="h-4 w-4 mr-2" />
              <% else %>
                <%= if @can_connect == :pending_request do %>
                  <Heroicons.clock class="h-4 w-4 mr-2" />
                <% else %>
                  <Heroicons.users class="h-4 w-4 mr-2" />
                <% end %>
              <% end %>
            <% end %>
            <%= button_label(@is_connected, @can_connect, @relationship) %>
          </button>
        <% end %>
      <% end %>
      <%= if @error do %>
        <p class="absolute top-full left-0 mt-1 text-xs text-red-200 whitespace-nowrap">
          {@error}
        </p>
      <% end %>
    </div>
    """
  end

  # Determine if the button should be shown at all
  # Hide completely for blocked users, show for everything else
  @spec show_button?(boolean(), atom() | nil) :: boolean()
  defp show_button?(_is_connected, :blocked), do: false
  defp show_button?(_is_connected, _can_connect), do: true

  # Determine if the button should be disabled (but still visible)
  # Only :closed disables the button - :request_required and :pending_request are clickable states
  @spec button_disabled?(boolean(), atom() | nil) :: boolean()
  defp button_disabled?(true, _can_connect), do: false
  defp button_disabled?(_is_connected, :closed), do: true
  defp button_disabled?(_is_connected, :pending_request), do: true
  defp button_disabled?(_is_connected, _can_connect), do: false

  @spec connection_tooltip(boolean(), atom() | nil, map() | nil, boolean(), String.t() | nil) ::
          String.t() | nil
  defp connection_tooltip(_is_connected, _can_connect, _relationship, _show_context, error)
       when not is_nil(error) do
    error
  end

  # Permission-denied tooltips
  defp connection_tooltip(false, :closed, _relationship, _show_context, _error) do
    "This person prefers to reach out first"
  end

  # Request flow states
  defp connection_tooltip(false, :request_required, _relationship, _show_context, _error) do
    "Send an introduction"
  end

  defp connection_tooltip(false, :pending_request, _relationship, _show_context, _error) do
    "Waiting for response"
  end

  defp connection_tooltip(
         true,
         _can_connect,
         %{context: context, shared_event_count: count},
         true,
         _error
       )
       when not is_nil(context) do
    if count > 1 do
      "#{context} (#{count} events together)"
    else
      context
    end
  end

  defp connection_tooltip(true, _can_connect, _relationship, _show_context, _error),
    do: "You're keeping up with them"

  defp connection_tooltip(false, _can_connect, _relationship, _show_context, _error),
    do: "Keep up with their events"

  @spec button_classes(boolean(), atom() | nil, String.t(), String.t(), String.t()) :: String.t()
  defp button_classes(is_connected, can_connect, size, variant, custom_class) do
    base_classes =
      "inline-flex items-center justify-center font-medium rounded-lg transition shadow-md focus:outline-none focus:ring-2 focus:ring-offset-2"

    size_classes =
      case size do
        "sm" -> "px-3 py-1.5 text-sm"
        "md" -> "px-5 py-2.5 text-sm font-semibold"
        "lg" -> "px-6 py-3 text-base"
        _ -> "px-5 py-2.5 text-sm font-semibold"
      end

    # Teal/cyan theme for relationships (distinct from purple performer / slate venue)
    # Uses solid, readable colors that work on both dark and light backgrounds
    variant_classes =
      case {variant, is_connected, can_connect} do
        {_, true, _} ->
          # Connected state - solid teal background with white text (always readable)
          "bg-teal-600 text-white hover:bg-teal-700 focus:ring-teal-500"

        # Disabled state for closed permission
        {_, false, :closed} ->
          "bg-gray-300 text-gray-500 cursor-not-allowed opacity-60"

        # Pending request state - shows waiting state
        {_, false, :pending_request} ->
          "bg-amber-100 text-amber-700 cursor-default"

        # Request required state - amber/orange to indicate request flow
        {_, false, :request_required} ->
          "bg-amber-500 text-white hover:bg-amber-600 focus:ring-amber-500"

        {"primary", false, _} ->
          # Primary variant - teal button for auto-accept (matches site style)
          "bg-teal-600 text-white hover:bg-teal-700 focus:ring-teal-500"

        {"outline", false, _} ->
          # Outline variant - teal border and text on transparent
          "border border-teal-600 bg-transparent text-teal-600 hover:bg-teal-50 focus:ring-teal-500"

        _ ->
          "bg-teal-600 text-white hover:bg-teal-700 focus:ring-teal-500"
      end

    [base_classes, size_classes, variant_classes, custom_class]
    |> Enum.reject(&(&1 == "" || is_nil(&1)))
    |> Enum.join(" ")
  end

  @spec button_label(boolean(), atom() | nil, map() | nil) :: String.t()
  defp button_label(true, _can_connect, %{shared_event_count: count}) when count > 1 do
    "Keeping Up"
  end

  defp button_label(true, _can_connect, _relationship), do: "Keeping Up"
  defp button_label(false, :request_required, _relationship), do: "Keep Up"
  defp button_label(false, :pending_request, _relationship), do: "Request sent"
  defp button_label(false, _can_connect, _relationship), do: "Keep Up"
end
