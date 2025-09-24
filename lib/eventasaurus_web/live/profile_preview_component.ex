defmodule EventasaurusWeb.ProfilePreviewComponent do
  use EventasaurusWeb, :live_component

  alias EventasaurusWeb.ProfileHTML

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_preview_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white border border-gray-200 rounded-lg p-6 sticky top-6">
      <h3 class="text-lg font-medium text-gray-900 mb-4 flex items-center">
        <svg class="w-5 h-5 mr-2 text-indigo-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"></path>
        </svg>
        Profile Preview
      </h3>

      <div class="border border-gray-100 rounded-lg p-4 bg-gray-50">
        <!-- Avatar and basic info -->
        <div class="flex items-start space-x-4">
          <!-- Real Avatar -->
          <div class="flex-shrink-0">
            <%= avatar_img_size(@user, :lg, class: "w-16 h-16 rounded-full border-2 border-gray-200") %>
          </div>

          <!-- Profile info -->
          <div class="flex-1 min-w-0">
            <!-- Display name -->
            <h4 class="text-lg font-semibold text-gray-900 truncate">
              <%= if String.trim(@preview_data.name || "") != "" do %>
                <%= @preview_data.name %>
              <% else %>
                <span class="text-gray-400 italic">Your Name</span>
              <% end %>
            </h4>

            <!-- Username -->
            <p class="text-sm text-gray-600">
              <%= if String.trim(@preview_data.username || "") != "" do %>
                @<%= @preview_data.username %>
              <% else %>
                <span class="text-gray-400 italic">@username</span>
              <% end %>
            </p>

            <!-- Bio -->
            <div class="mt-2">
              <%= if String.trim(@preview_data.bio || "") != "" do %>
                <p class="text-sm text-gray-700 leading-relaxed"><%= @preview_data.bio %></p>
              <% else %>
                <p class="text-sm text-gray-400 italic">Your bio will appear here...</p>
              <% end %>
            </div>

            <!-- Website -->
            <%= if String.trim(@preview_data.website_url || "") != "" do %>
              <div class="mt-2">
                <a href={ProfileHTML.format_website_url(@preview_data.website_url)}
                   target="_blank"
                   rel="noopener noreferrer"
                   class="text-sm text-indigo-600 hover:text-indigo-800 flex items-center">
                  <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"></path>
                  </svg>
                  <%= String.replace(@preview_data.website_url, ~r/^https?:\/\//, "") %>
                </a>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Social links -->
        <%= if has_social_links?(@preview_data) do %>
          <div class="mt-4 pt-4 border-t border-gray-200">
            <div class="flex flex-wrap gap-3">
              <%= for {platform, handle} <- get_social_links(@preview_data), handle != "" do %>
                <a href={ProfileHTML.social_url(platform, handle)}
                   target="_blank"
                   rel="noopener noreferrer"
                   class="inline-flex items-center px-2 py-1 text-xs bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-full transition-colors">
                  <%= ProfileHTML.social_icon(platform) %>
                  <span class="ml-1"><%= ProfileHTML.platform_name(platform) %></span>
                </a>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Privacy indicator -->
        <div class="mt-4 pt-4 border-t border-gray-200">
          <div class="flex items-center text-xs">
            <%= if @preview_data.profile_public do %>
              <svg class="w-4 h-4 mr-1 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd"></path>
              </svg>
              <span class="text-green-600">Public Profile</span>
            <% else %>
              <svg class="w-4 h-4 mr-1 text-gray-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd"></path>
              </svg>
              <span class="text-gray-500">Private Profile</span>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Profile URL preview -->
      <%= if String.trim(@preview_data.username || "") != "" do %>
        <div class="mt-4 p-3 bg-indigo-50 border border-indigo-200 rounded-lg">
          <p class="text-xs font-medium text-indigo-900 mb-1">Your Profile URL:</p>
          <div class="flex items-center">
            <code class="text-sm text-indigo-700 bg-white px-2 py-1 rounded border flex-1 truncate">
              /user/<%= @preview_data.username %>
            </code>
            <button
              type="button"
              phx-click="copy_profile_url"
              phx-target={@myself}
              class="ml-2 p-1 text-indigo-600 hover:text-indigo-800 transition-colors"
              title="Copy URL">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"></path>
              </svg>
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("copy_profile_url", _params, socket) do
    username = socket.assigns.preview_data.username
    profile_url = "/user/#{username}"

    # Send a JavaScript command to copy to clipboard
    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: profile_url})
     |> put_flash(:info, "Profile URL copied to clipboard!")}
  end

  # Private functions
  defp assign_preview_data(socket) do
    form_data = socket.assigns.form_data || %{}
    user = socket.assigns.user

    # Merge user data with form changes for preview
    preview_data = %{
      email: user.email,
      name: Map.get(form_data, "name", user.name),
      username: Map.get(form_data, "username", user.username),
      bio: Map.get(form_data, "bio", user.bio),
      website_url: Map.get(form_data, "website_url", user.website_url),
      instagram_handle: Map.get(form_data, "instagram_handle", user.instagram_handle),
      x_handle: Map.get(form_data, "x_handle", user.x_handle),
      youtube_handle: Map.get(form_data, "youtube_handle", user.youtube_handle),
      tiktok_handle: Map.get(form_data, "tiktok_handle", user.tiktok_handle),
      linkedin_handle: Map.get(form_data, "linkedin_handle", user.linkedin_handle),
      profile_public:
        Map.get(form_data, "profile_public", user.profile_public) == "true" ||
          Map.get(form_data, "profile_public", user.profile_public) == true
    }

    assign(socket, :preview_data, preview_data)
  end

  defp has_social_links?(preview_data) do
    [
      preview_data.instagram_handle,
      preview_data.x_handle,
      preview_data.youtube_handle,
      preview_data.tiktok_handle,
      preview_data.linkedin_handle
    ]
    |> Enum.any?(&(String.trim(&1 || "") != ""))
  end

  defp get_social_links(preview_data) do
    [
      {"instagram", preview_data.instagram_handle || ""},
      {"x", preview_data.x_handle || ""},
      {"youtube", preview_data.youtube_handle || ""},
      {"tiktok", preview_data.tiktok_handle || ""},
      {"linkedin", preview_data.linkedin_handle || ""}
    ]
    |> Enum.filter(fn {_platform, handle} -> String.trim(handle) != "" end)
  end
end
