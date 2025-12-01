defmodule EventasaurusWeb.Components.GroupImageComponent do
  @moduledoc """
  Reusable component for displaying group images (avatars and cover images)
  with graceful fallback to placeholders when images are missing.
  """

  use Phoenix.LiveComponent
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.Helpers.ImageUrlHelper

  @doc """
  Renders a group avatar image with fallback placeholder.

  ## Attributes

  * `group` - Group struct with avatar_url field
  * `size` - Size class (e.g., "w-12 h-12", "w-16 h-16")
  * `class` - Additional CSS classes
  * `alt` - Alt text for accessibility (defaults to group name)

  ## Examples

      <.live_component module={GroupImageComponent} id="avatar" type="avatar" 
                       group={@group} size="w-12 h-12" />
  """
  def render(%{type: "avatar"} = assigns) do
    assigns = assign_defaults(assigns)

    ~H"""
    <%!-- PHASE 2 TODO: Remove resolve() wrapper after database migration normalizes URLs --%>
    <% resolved_avatar_url = resolve(@group.avatar_url) %>
    <div class={["inline-block relative", @size, @class]}>
      <%= if resolved_avatar_url do %>
        <img
          src={resolved_avatar_url}
          alt={@alt}
          class={["object-cover rounded-full", @size]}
          loading="lazy"
          onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';"
        />
        <!-- Fallback placeholder (hidden by default) -->
        <div class={["hidden items-center justify-center bg-gray-200 dark:bg-gray-700 text-gray-500 dark:text-gray-400 rounded-full", @size]} style="display: none;">
          <.icon name="hero-user-group" class="w-1/2 h-1/2" />
        </div>
      <% else %>
        <!-- Default placeholder -->
        <div class={["flex items-center justify-center bg-gray-200 dark:bg-gray-700 text-gray-500 dark:text-gray-400 rounded-full", @size]}>
          <.icon name="hero-user-group" class="w-1/2 h-1/2" />
        </div>
      <% end %>
    </div>
    """
  end

  def render(%{type: "cover"} = assigns) do
    assigns = assign_defaults(assigns)

    ~H"""
    <%!-- PHASE 2 TODO: Remove resolve() wrapper after database migration normalizes URLs --%>
    <% resolved_cover_url = resolve(@group.cover_image_url) %>
    <div class={["relative bg-gray-200 dark:bg-gray-700 overflow-hidden", @aspect_ratio, @class]}>
      <%= if resolved_cover_url do %>
        <img
          src={resolved_cover_url}
          alt={@alt}
          class="absolute inset-0 w-full h-full object-cover"
          loading="lazy"
          onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';"
        />
        <!-- Fallback placeholder (hidden by default) -->
        <div class="hidden absolute inset-0 flex items-center justify-center text-gray-500 dark:text-gray-400" style="display: none;">
          <.icon name="hero-photo" class="w-12 h-12" />
        </div>
      <% else %>
        <!-- Default placeholder -->
        <div class="absolute inset-0 flex items-center justify-center text-gray-500 dark:text-gray-400">
          <.icon name="hero-photo" class="w-12 h-12" />
        </div>
      <% end %>
    </div>
    """
  end

  def render(%{type: "full"} = assigns) do
    assigns =
      assigns
      |> assign_defaults()
      |> assign_new(:show_avatar, fn -> true end)
      |> assign_new(:avatar_size, fn -> "w-16 h-16" end)
      |> assign_new(:cover_aspect_ratio, fn -> "aspect-w-16 aspect-h-9" end)

    ~H"""
    <div class={["relative", @class]}>
      <!-- Cover Image -->
      <.live_component 
        module={__MODULE__} 
        id={"#{@id}_cover"} 
        type="cover" 
        group={@group} 
        aspect_ratio={@cover_aspect_ratio}
        alt={"#{@group.name} cover image"}
      />
      
      <!-- Avatar Overlay -->
      <%= if @show_avatar do %>
        <div class="absolute bottom-4 left-4">
          <.live_component 
            module={__MODULE__} 
            id={"#{@id}_avatar"} 
            type="avatar" 
            group={@group} 
            size={@avatar_size}
            class="ring-4 ring-white dark:ring-gray-800"
            alt={"#{@group.name} avatar"}
          />
        </div>
      <% end %>
    </div>
    """
  end

  # Default render for other types
  def render(assigns) do
    ~H"""
    <div class="text-red-500">
      Unknown image component type: <%= @type %>
    </div>
    """
  end

  defp assign_defaults(assigns) do
    assigns
    |> assign_new(:class, fn -> "" end)
    |> assign_new(:alt, fn -> (assigns[:group] && assigns.group.name) || "Group image" end)
    |> assign_new(:size, fn -> "w-12 h-12" end)
    |> assign_new(:aspect_ratio, fn -> "aspect-w-16 aspect-h-9" end)
  end
end
