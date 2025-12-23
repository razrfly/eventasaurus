defmodule EventasaurusWeb.FollowButtonComponent do
  @moduledoc """
  A LiveComponent for following/unfollowing performers and venues.

  Handles both authenticated and unauthenticated users:
  - Authenticated: Shows follow/unfollow button with real-time toggle
  - Unauthenticated: Shows follow button that opens auth modal

  ## Attributes:
  - id: Unique identifier for the component (required)
  - entity: The performer or venue struct to follow (required)
  - entity_type: :performer or :venue (required)
  - current_user: The current user struct (nil if not logged in)
  - class: Additional CSS classes (optional)
  - size: Button size - "sm", "md", or "lg" (default: "md")
  - variant: Button style - "primary" or "outline" (default: "primary")

  ## Usage:

      <.live_component
        module={EventasaurusWeb.FollowButtonComponent}
        id={"follow-performer-\#{performer.id}"}
        entity={performer}
        entity_type={:performer}
        current_user={user}
      />
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Follows

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :loading, false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_following_status()

    {:ok, socket}
  end

  defp assign_following_status(socket) do
    current_user = socket.assigns[:current_user]
    entity = socket.assigns[:entity]
    entity_type = socket.assigns[:entity_type]

    is_following =
      case {current_user, entity_type} do
        {nil, _} ->
          false

        {user, :performer} ->
          Follows.following_performer?(user, entity)

        {user, :venue} ->
          Follows.following_venue?(user, entity)

        _ ->
          false
      end

    assign(socket, :is_following, is_following)
  end

  @impl true
  def handle_event("toggle_follow", _params, socket) do
    current_user = socket.assigns.current_user

    if current_user do
      socket = toggle_follow(socket)
      {:noreply, socket}
    else
      # User not logged in - trigger auth modal via parent
      send(self(), {:show_auth_modal, :follow})
      {:noreply, socket}
    end
  end

  defp toggle_follow(socket) do
    socket = assign(socket, :loading, true)

    entity = socket.assigns.entity
    entity_type = socket.assigns.entity_type
    current_user = socket.assigns.current_user
    is_following = socket.assigns.is_following

    result =
      case {entity_type, is_following} do
        {:performer, true} ->
          Follows.unfollow_performer(current_user, entity)

        {:performer, false} ->
          Follows.follow_performer(current_user, entity)

        {:venue, true} ->
          Follows.unfollow_venue(current_user, entity)

        {:venue, false} ->
          Follows.follow_venue(current_user, entity)
      end

    case result do
      {:ok, _} ->
        socket
        |> assign(:is_following, !is_following)
        |> assign(:loading, false)

      {:error, _reason} ->
        # On error, keep current state
        assign(socket, :loading, false)
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> "" end)
      |> assign_new(:size, fn -> "md" end)
      |> assign_new(:variant, fn -> "primary" end)

    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="toggle_follow"
      phx-target={@myself}
      disabled={@loading}
      class={button_classes(@is_following, @entity_type, @size, @variant, @class)}
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
        <%= if @is_following do %>
          <Heroicons.check class="h-4 w-4 mr-2" />
        <% else %>
          <Heroicons.plus class="h-4 w-4 mr-2" />
        <% end %>
      <% end %>
      <%= button_label(@is_following, @entity_type) %>
    </button>
    """
  end

  defp button_classes(is_following, entity_type, size, variant, custom_class) do
    base_classes =
      "inline-flex items-center justify-center font-medium rounded-lg transition shadow-md focus:outline-none focus:ring-2 focus:ring-offset-2"

    size_classes =
      case size do
        "sm" -> "px-3 py-1.5 text-sm"
        "md" -> "px-5 py-2.5 text-sm font-semibold"
        "lg" -> "px-6 py-3 text-base"
        _ -> "px-5 py-2.5 text-sm font-semibold"
      end

    # Theme colors based on entity type (matching HeroCardTheme but inverted for Follow action)
    # Follow button uses colored background to stand out from other white buttons
    {bg_color, hover_bg, text_color, focus_ring} =
      case entity_type do
        :performer ->
          {"bg-purple-600", "hover:bg-purple-700", "text-white", "focus:ring-purple-500"}

        :venue ->
          {"bg-slate-700", "hover:bg-slate-800", "text-white", "focus:ring-slate-500"}

        _ ->
          {"bg-purple-600", "hover:bg-purple-700", "text-white", "focus:ring-purple-500"}
      end

    variant_classes =
      case {variant, is_following} do
        {_, true} ->
          # Following state - white button with check mark to indicate "already following"
          "bg-white text-gray-700 hover:bg-gray-100 focus:ring-gray-500"

        {"primary", false} ->
          # Primary variant - colored button to stand out as primary action
          "#{bg_color} #{text_color} #{hover_bg} #{focus_ring}"

        {"outline", false} ->
          "border border-white/50 bg-white/10 text-white hover:bg-white/20 focus:ring-white/50"

        _ ->
          "#{bg_color} #{text_color} #{hover_bg} #{focus_ring}"
      end

    [base_classes, size_classes, variant_classes, custom_class]
    |> Enum.reject(&(&1 == "" || is_nil(&1)))
    |> Enum.join(" ")
  end

  defp button_label(true, :performer), do: "Following"
  defp button_label(false, :performer), do: "Follow"
  defp button_label(true, :venue), do: "Following"
  defp button_label(false, :venue), do: "Follow"
  defp button_label(_, _), do: "Follow"
end
