defmodule EventasaurusWeb.FollowButtonComponent do
  @moduledoc """
  A LiveComponent for following/unfollowing performers and venues.

  This component provides a reusable follow button that handles both
  authenticated and unauthenticated users with appropriate visual feedback.

  ## Features

  - Real-time follow/unfollow toggle for authenticated users
  - Auth modal trigger for unauthenticated users
  - Loading state with spinner animation
  - Dynamic styling based on entity type (performer/venue)
  - Rate limiting feedback (shows error message if rate limited)

  ## Required Assigns

  - `id` - Unique identifier for the component (e.g., "follow-performer-123")
  - `entity` - The performer or venue struct to follow
  - `entity_type` - `:performer` or `:venue`
  - `current_user` - The current user struct (nil if not logged in)

  ## Optional Assigns

  - `class` - Additional CSS classes (default: "")
  - `size` - Button size: "sm", "md", or "lg" (default: "md")
  - `variant` - Button style: "primary" or "outline" (default: "primary")

  ## Usage

      <.live_component
        module={EventasaurusWeb.FollowButtonComponent}
        id={"follow-performer-\#{performer.id}"}
        entity={performer}
        entity_type={:performer}
        current_user={@current_user}
      />

  ## Styling

  The button uses a white background with colored text that matches the
  HeroCardTheme patterns, ensuring good contrast against dark gradient
  hero card backgrounds.

  - Performer: Purple text on white
  - Venue: Slate text on white
  - Following state: Semi-transparent white on gradient

  ## Events

  When the user is not authenticated and clicks the button, this component
  sends `{:show_auth_modal, :follow}` to the parent LiveView to trigger
  an authentication flow.
  """

  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Follows

  @impl true
  def mount(socket) do
    {:ok, assign(socket, loading: false, error: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_following_status()

    {:ok, socket}
  end

  @spec assign_following_status(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
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

  @spec toggle_follow(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp toggle_follow(socket) do
    socket = assign(socket, loading: true, error: nil)

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
        |> assign(:error, nil)

      {:error, :rate_limited} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, "Too many requests. Please wait a moment.")

      {:error, _reason} ->
        # On other errors, keep current state
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
      |> assign_new(:error, fn -> nil end)

    ~H"""
    <div class="relative">
      <button
        id={@id}
        type="button"
        phx-click="toggle_follow"
        phx-target={@myself}
        disabled={@loading}
        class={button_classes(@is_following, @entity_type, @size, @variant, @class)}
        title={@error}
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
      <%= if @error do %>
        <p class="absolute top-full left-0 mt-1 text-xs text-red-200 whitespace-nowrap">
          {@error}
        </p>
      <% end %>
    </div>
    """
  end

  @spec button_classes(boolean(), atom(), String.t(), String.t(), String.t()) :: String.t()
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

    # Theme colors based on entity type - matching HeroCardTheme button patterns
    # White background with colored text contrasts well against dark gradient backgrounds
    {text_color, hover_bg, focus_ring} =
      case entity_type do
        :performer ->
          {"text-purple-900", "hover:bg-purple-50", "focus:ring-purple-500"}

        :venue ->
          {"text-slate-900", "hover:bg-slate-50", "focus:ring-slate-500"}

        _ ->
          {"text-purple-900", "hover:bg-purple-50", "focus:ring-purple-500"}
      end

    variant_classes =
      case {variant, is_following} do
        {_, true} ->
          # Following state - subtle background to indicate "already following"
          "bg-white/20 text-white hover:bg-white/30 focus:ring-white/50"

        {"primary", false} ->
          # Primary variant - white button matching HeroCardTheme button style
          "bg-white #{text_color} #{hover_bg} #{focus_ring}"

        {"outline", false} ->
          "border border-white/50 bg-white/10 text-white hover:bg-white/20 focus:ring-white/50"

        _ ->
          "bg-white #{text_color} #{hover_bg} #{focus_ring}"
      end

    [base_classes, size_classes, variant_classes, custom_class]
    |> Enum.reject(&(&1 == "" || is_nil(&1)))
    |> Enum.join(" ")
  end

  @spec button_label(boolean(), atom()) :: String.t()
  defp button_label(true, :performer), do: "Following"
  defp button_label(false, :performer), do: "Follow"
  defp button_label(true, :venue), do: "Following"
  defp button_label(false, :venue), do: "Follow"
  defp button_label(_, _), do: "Follow"
end
