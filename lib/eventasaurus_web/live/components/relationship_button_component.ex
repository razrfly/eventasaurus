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

    socket
    |> assign(:is_connected, is_connected)
    |> assign(:relationship, relationship)
  end

  @impl true
  def handle_event("connect", _params, socket) do
    current_user = socket.assigns.current_user

    cond do
      is_nil(current_user) ->
        # User not logged in - trigger auth modal via parent
        send(self(), {:show_auth_modal, :connect})
        {:noreply, socket}

      true ->
        # Connect directly with auto-generated context from event
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

    {:ok, _count} = Relationships.remove_relationship(current_user, other_user)

    socket
    |> assign(:is_connected, false)
    |> assign(:relationship, nil)
    |> assign(:loading, false)
    |> assign(:error, nil)
  end

  @spec connect_with_context(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp connect_with_context(socket, context) do
    socket = assign(socket, loading: true, error: nil)

    current_user = socket.assigns.current_user
    other_user = socket.assigns.other_user
    event = socket.assigns[:event]

    result =
      if event do
        Relationships.create_from_shared_event(current_user, other_user, event, context)
      else
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
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
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
        <button
          id={@id}
          type="button"
          phx-click={if @is_connected, do: "disconnect", else: "connect"}
          phx-target={@myself}
          disabled={@loading}
          class={button_classes(@is_connected, @size, @variant, @class)}
          title={connection_tooltip(@is_connected, @relationship, @show_context, @error)}
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
              <Heroicons.user_group class="h-4 w-4 mr-2" />
            <% else %>
              <Heroicons.user_plus class="h-4 w-4 mr-2" />
            <% end %>
          <% end %>
          <%= button_label(@is_connected, @relationship) %>
        </button>
      <% end %>
      <%= if @error do %>
        <p class="absolute top-full left-0 mt-1 text-xs text-red-200 whitespace-nowrap">
          {@error}
        </p>
      <% end %>
    </div>
    """
  end

  @spec connection_tooltip(boolean(), map() | nil, boolean(), String.t() | nil) :: String.t() | nil
  defp connection_tooltip(_is_connected, _relationship, _show_context, error) when not is_nil(error) do
    error
  end

  defp connection_tooltip(true, %{context: context, shared_event_count: count}, true, _error)
       when not is_nil(context) do
    if count > 1 do
      "#{context} (#{count} events together)"
    else
      context
    end
  end

  defp connection_tooltip(true, _relationship, _show_context, _error), do: "In your people"
  defp connection_tooltip(false, _relationship, _show_context, _error), do: "Stay in touch"

  @spec button_classes(boolean(), String.t(), String.t(), String.t()) :: String.t()
  defp button_classes(is_connected, size, variant, custom_class) do
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
      case {variant, is_connected} do
        {_, true} ->
          # Connected state - solid teal background with white text (always readable)
          "bg-teal-600 text-white hover:bg-teal-700 focus:ring-teal-500"

        {"primary", false} ->
          # Primary variant - teal button (matches site style)
          "bg-teal-600 text-white hover:bg-teal-700 focus:ring-teal-500"

        {"outline", false} ->
          # Outline variant - teal border and text on transparent
          "border border-teal-600 bg-transparent text-teal-600 hover:bg-teal-50 focus:ring-teal-500"

        _ ->
          "bg-teal-600 text-white hover:bg-teal-700 focus:ring-teal-500"
      end

    [base_classes, size_classes, variant_classes, custom_class]
    |> Enum.reject(&(&1 == "" || is_nil(&1)))
    |> Enum.join(" ")
  end

  @spec button_label(boolean(), map() | nil) :: String.t()
  defp button_label(true, %{shared_event_count: count}) when count > 1 do
    "#{count} events together"
  end

  defp button_label(true, _relationship), do: "In your people"
  defp button_label(false, _relationship), do: "Stay in touch"
end
