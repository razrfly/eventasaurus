defmodule EventasaurusWeb.ParticipantStatusButtonComponent do
  @moduledoc """
  A reusable LiveView component for participant status buttons.

  Handles toggling between different participant statuses (going/interested)
  and integrates with the generic participant status API.

  ## Attributes:
  - event: Event struct (required)
  - user: User struct (nil for unauthenticated users)
  - current_status: Current user's participant status (:accepted, :interested, nil)
  - target_status: The status this button should toggle to (:accepted, :interested)
  - loading: Whether an API call is in progress
  - class: Additional CSS classes
  - size: Button size (:sm, :md, :lg)
  - variant: Button style (:primary, :secondary, :outline)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.ParticipantStatusButtonComponent}
        id="going-button"
        event={@event}
        user={@user}
        current_status={@current_status}
        target_status={:accepted}
        loading={@loading}
      />

      <.live_component
        module={EventasaurusWeb.ParticipantStatusButtonComponent}
        id="interested-button"
        event={@event}
        user={@user}
        current_status={@current_status}
        target_status={:interested}
        loading={@loading}
      />
  """

  use EventasaurusWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:loading, false)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:loading, fn -> false end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:size, fn -> :md end)
     |> assign_new(:variant, fn ->
       case assigns[:target_status] do
         :accepted -> :primary
         :interested -> :outline
         _ -> :secondary
       end
     end)
     |> assign_computed_properties()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <button
      phx-click="toggle_status"
      phx-target={@myself}
      phx-value-status={@target_status}
      disabled={@loading || @user == nil}
      class={[@base_classes, @variant_classes, @size_classes, @state_classes, @class]}
      aria-label={@aria_label}
      title={@title_text}
    >
      <%= if @loading do %>
        <svg class={@icon_size} fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
      <% else %>
        <%= if @is_active do %>
          <%= @active_icon %>
        <% else %>
          <%= @inactive_icon %>
        <% end %>
      <% end %>

      <span class="ml-2"><%= @button_text %></span>
    </button>
    """
  end

  @impl true
  def handle_event("toggle_status", %{"status" => status}, socket) do
    # Don't proceed if user is not authenticated
    if socket.assigns.user == nil do
      send(self(), {:show_auth_required_message})
      {:noreply, socket}
    else
      # Set loading state
      socket = assign(socket, :loading, true)

      # Send event to parent LiveView to handle the API call
      target_status = String.to_atom(status)

      if socket.assigns.current_status == target_status do
        # Remove status if clicking the same status
        send(self(), {:remove_participant_status, socket.assigns.event, socket.assigns.user})
      else
        # Set new status
        send(self(), {:update_participant_status, socket.assigns.event, socket.assigns.user, target_status})
      end

      {:noreply, socket}
    end
  end

  # Private functions

  defp assign_computed_properties(socket) do
    %{
      target_status: target_status,
      current_status: current_status,
      size: size,
      variant: variant,
      user: user
    } = socket.assigns

    is_active = current_status == target_status
    is_authenticated = user != nil

    {button_text, aria_label, title_text} = get_button_content(target_status, is_active, is_authenticated)
    {active_icon, inactive_icon} = get_button_icons(target_status, size)

    base_classes = get_base_classes()
    variant_classes = get_variant_classes(variant, is_active)
    size_classes = get_size_classes(size)
    state_classes = get_state_classes(is_active, is_authenticated)
    icon_size = get_icon_size(size)

    socket
    |> assign(:is_active, is_active)
    |> assign(:is_authenticated, is_authenticated)
    |> assign(:button_text, button_text)
    |> assign(:aria_label, aria_label)
    |> assign(:title_text, title_text)
    |> assign(:active_icon, active_icon)
    |> assign(:inactive_icon, inactive_icon)
    |> assign(:base_classes, base_classes)
    |> assign(:variant_classes, variant_classes)
    |> assign(:size_classes, size_classes)
    |> assign(:state_classes, state_classes)
    |> assign(:icon_size, icon_size)
  end

  defp get_button_content(:accepted, is_active, is_authenticated) do
    cond do
      !is_authenticated -> {"Going", "Sign in to indicate you're going", "Sign in required"}
      is_active -> {"Going", "You're going to this event", "Click to remove your going status"}
      true -> {"Going", "Indicate you're going to this event", "Click to mark yourself as going"}
    end
  end

  defp get_button_content(:interested, is_active, is_authenticated) do
    cond do
      !is_authenticated -> {"Interested", "Sign in to express interest", "Sign in required"}
      is_active -> {"Interested", "You're interested in this event", "Click to remove your interest"}
      true -> {"Interested", "Express interest in this event", "Click to mark yourself as interested"}
    end
  end

  defp get_button_content(_, _, _), do: {"Unknown", "Unknown status", "Unknown"}

  defp get_button_icons(:accepted, size) do
    icon_size = get_icon_size(size)

    active_icon = ~s"""
    <svg class="#{icon_size}" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
    </svg>
    """ |> Phoenix.HTML.raw()

    inactive_icon = ~s"""
    <svg class="#{icon_size}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
    </svg>
    """ |> Phoenix.HTML.raw()

    {active_icon, inactive_icon}
  end

  defp get_button_icons(:interested, size) do
    icon_size = get_icon_size(size)

    active_icon = ~s"""
    <svg class="#{icon_size}" fill="currentColor" viewBox="0 0 20 20">
      <path d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" />
    </svg>
    """ |> Phoenix.HTML.raw()

    inactive_icon = ~s"""
    <svg class="#{icon_size}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
    </svg>
    """ |> Phoenix.HTML.raw()

    {active_icon, inactive_icon}
  end

  defp get_button_icons(_, size) do
    icon_size = get_icon_size(size)
    default_icon = ~s"""
    <svg class="#{icon_size}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
    </svg>
    """ |> Phoenix.HTML.raw()
    {default_icon, default_icon}
  end

  defp get_base_classes do
    "inline-flex items-center rounded-md font-medium transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed"
  end

  defp get_variant_classes(:primary, is_active) do
    if is_active do
      "bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"
    else
      "bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500"
    end
  end

  defp get_variant_classes(:outline, is_active) do
    if is_active do
      "bg-red-50 text-red-700 border-2 border-red-300 hover:bg-red-100 focus:ring-red-500"
    else
      "bg-white text-gray-700 border-2 border-gray-300 hover:bg-gray-50 focus:ring-indigo-500"
    end
  end

  defp get_variant_classes(:secondary, is_active) do
    if is_active do
      "bg-green-100 text-green-700 border border-green-300 hover:bg-green-200 focus:ring-green-500"
    else
      "bg-gray-100 text-gray-700 border border-gray-300 hover:bg-gray-200 focus:ring-gray-500"
    end
  end

  defp get_size_classes(:sm), do: "px-3 py-1.5 text-sm"
  defp get_size_classes(:md), do: "px-4 py-2 text-sm"
  defp get_size_classes(:lg), do: "px-6 py-3 text-base"

  defp get_state_classes(is_active, is_authenticated) do
    cond do
      !is_authenticated -> "opacity-75"
      is_active -> "shadow-md"
      true -> "shadow-sm hover:shadow-md"
    end
  end

  defp get_icon_size(:sm), do: "w-4 h-4"
  defp get_icon_size(:md), do: "w-4 h-4"
  defp get_icon_size(:lg), do: "w-5 h-5"
end
