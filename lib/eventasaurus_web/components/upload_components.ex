defmodule EventasaurusWeb.Components.UploadComponents do
  @moduledoc """
  Reusable upload UI components for Phoenix LiveView.

  These components provide consistent upload interfaces across the application,
  including drag-and-drop support, preview, progress tracking, and error display.

  ## Usage

      # Basic image upload
      <.image_upload upload={@uploads.cover_image} label="Cover Image" />

      # With existing image preview
      <.image_upload
        upload={@uploads.avatar}
        label="Avatar"
        current_url={@user.avatar_url}
      />

      # Compact style for smaller spaces
      <.image_upload_compact upload={@uploads.logo} />
  """

  use Phoenix.Component

  import EventasaurusWeb.Uploads, only: [error_to_string: 1]
  import EventasaurusWeb.Helpers.ImageUrlHelper, only: [resolve: 1]

  @doc """
  Full-featured image upload component with drag-and-drop.

  ## Attributes

  - `upload` (required) - The upload struct from `@uploads.name`
  - `label` - Label text for the upload (default: "Upload Image")
  - `current_url` - URL of existing image to show as current
  - `class` - Additional CSS classes for the container
  - `show_preview` - Whether to show live preview during upload (default: true)
  - `help_text` - Optional help text below the dropzone

  ## Events

  The parent LiveView should handle:
  - `cancel-upload` with `phx-value-ref` - Cancel a pending upload
  """
  attr :upload, :map, required: true
  attr :label, :string, default: "Upload Image"
  attr :current_url, :string, default: nil
  attr :class, :string, default: ""
  attr :show_preview, :boolean, default: true
  attr :help_text, :string, default: nil

  def image_upload(assigns) do
    ~H"""
    <div class={"upload-component #{@class}"}>
      <label class="block text-sm font-medium text-gray-700 mb-2">
        {@label}
      </label>

      <%!-- Current image preview --%>
      <div :if={@current_url && length(@upload.entries) == 0} class="mb-3">
        <p class="text-xs text-gray-500 mb-1">Current image:</p>
        <img
          src={resolve(@current_url)}
          alt="Current"
          class="h-20 w-20 object-cover rounded-lg border border-gray-200"
        />
      </div>

      <%!-- Dropzone --%>
      <div
        class="upload-dropzone relative border-2 border-dashed border-gray-300 rounded-lg p-6 hover:border-gray-400 transition-colors cursor-pointer"
        phx-drop-target={@upload.ref}
      >
        <.live_file_input upload={@upload} class="sr-only" />

        <div class="text-center">
          <svg
            class="mx-auto h-12 w-12 text-gray-400"
            stroke="currentColor"
            fill="none"
            viewBox="0 0 48 48"
            aria-hidden="true"
          >
            <path
              d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <p class="mt-2 text-sm text-gray-600">
            <span class="font-medium text-indigo-600 hover:text-indigo-500">
              Click to upload
            </span>
            or drag and drop
          </p>
          <p class="mt-1 text-xs text-gray-500">
            JPG, PNG, GIF, WebP up to 5MB
          </p>
          <p :if={@help_text} class="mt-1 text-xs text-gray-400">
            {@help_text}
          </p>
        </div>
      </div>

      <%!-- Upload entries with preview and progress --%>
      <div :for={entry <- @upload.entries} class="mt-3 p-3 bg-gray-50 rounded-lg">
        <div class="flex items-center gap-3">
          <%!-- Preview --%>
          <div :if={@show_preview} class="flex-shrink-0">
            <.live_img_preview entry={entry} class="h-16 w-16 object-cover rounded" />
          </div>

          <%!-- Info and progress --%>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-gray-900 truncate">
              {entry.client_name}
            </p>
            <p class="text-xs text-gray-500">
              {format_bytes(entry.client_size)}
            </p>

            <%!-- Progress bar --%>
            <div class="mt-1 w-full bg-gray-200 rounded-full h-2">
              <div
                class="bg-indigo-600 h-2 rounded-full transition-all duration-300"
                style={"width: #{entry.progress}%"}
              >
              </div>
            </div>
            <p class="text-xs text-gray-500 mt-1">{entry.progress}%</p>
          </div>

          <%!-- Cancel button --%>
          <button
            type="button"
            phx-click="cancel-upload"
            phx-value-ref={entry.ref}
            class="flex-shrink-0 p-1 text-gray-400 hover:text-red-500 transition-colors"
            aria-label="Cancel upload"
          >
            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        <%!-- Entry-specific errors --%>
        <p
          :for={err <- Phoenix.Component.upload_errors(@upload, entry)}
          class="mt-2 text-sm text-red-600"
        >
          {error_to_string(err)}
        </p>
      </div>

      <%!-- Upload-level errors --%>
      <p
        :for={err <- Phoenix.Component.upload_errors(@upload)}
        class="mt-2 text-sm text-red-600"
      >
        {error_to_string(err)}
      </p>
    </div>
    """
  end

  @doc """
  Compact image upload component for smaller spaces.

  Shows just the dropzone and minimal info. Good for avatars or small image fields.

  ## Attributes

  - `upload` (required) - The upload struct from `@uploads.name`
  - `current_url` - URL of existing image
  - `size` - Size of the preview area (default: "md")
  - `class` - Additional CSS classes
  """
  attr :upload, :map, required: true
  attr :current_url, :string, default: nil
  attr :size, :string, default: "md"
  attr :class, :string, default: ""

  def image_upload_compact(assigns) do
    size_classes =
      case assigns.size do
        "sm" -> "h-16 w-16"
        "md" -> "h-24 w-24"
        "lg" -> "h-32 w-32"
        _ -> "h-24 w-24"
      end

    assigns = assign(assigns, :size_classes, size_classes)

    ~H"""
    <div class={"upload-compact #{@class}"}>
      <div
        class={"#{@size_classes} relative border-2 border-dashed border-gray-300 rounded-lg hover:border-gray-400 transition-colors cursor-pointer overflow-hidden"}
        phx-drop-target={@upload.ref}
      >
        <.live_file_input upload={@upload} class="sr-only" />

        <%!-- Show current image or upload icon --%>
        <%= if length(@upload.entries) > 0 do %>
          <% entry = List.first(@upload.entries) %>
          <.live_img_preview entry={entry} class="h-full w-full object-cover" />
          <%!-- Progress overlay --%>
          <div
            :if={entry.progress < 100}
            class="absolute inset-0 bg-black bg-opacity-50 flex items-center justify-center"
          >
            <span class="text-white text-sm font-medium">{entry.progress}%</span>
          </div>
        <% else %>
          <%= if @current_url do %>
            <img src={resolve(@current_url)} alt="Current" class="h-full w-full object-cover" />
            <div class="absolute inset-0 bg-black bg-opacity-0 hover:bg-opacity-30 flex items-center justify-center transition-all">
              <svg
                class="h-6 w-6 text-white opacity-0 hover:opacity-100"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
            </div>
          <% else %>
            <div class="h-full w-full flex items-center justify-center">
              <svg
                class="h-8 w-8 text-gray-400"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                />
              </svg>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Errors --%>
      <p
        :for={err <- Phoenix.Component.upload_errors(@upload)}
        class="mt-1 text-xs text-red-600"
      >
        {error_to_string(err)}
      </p>
    </div>
    """
  end

  @doc """
  Cover image upload component with wide aspect ratio.

  Optimized for cover images that are wider than tall.

  ## Attributes

  - `upload` (required) - The upload struct
  - `current_url` - URL of existing cover image
  - `label` - Label text (default: "Cover Image")
  - `aspect_ratio` - Aspect ratio class (default: "aspect-video")
  """
  attr :upload, :map, required: true
  attr :current_url, :string, default: nil
  attr :label, :string, default: "Cover Image"
  attr :aspect_ratio, :string, default: "aspect-video"
  attr :class, :string, default: ""

  def cover_image_upload(assigns) do
    ~H"""
    <div class={"cover-upload #{@class}"}>
      <label class="block text-sm font-medium text-gray-700 mb-2">
        {@label}
      </label>

      <div
        class={"#{@aspect_ratio} relative border-2 border-dashed border-gray-300 rounded-lg hover:border-gray-400 transition-colors cursor-pointer overflow-hidden"}
        phx-drop-target={@upload.ref}
      >
        <.live_file_input upload={@upload} class="sr-only" />

        <%= if length(@upload.entries) > 0 do %>
          <% entry = List.first(@upload.entries) %>
          <.live_img_preview entry={entry} class="h-full w-full object-cover" />
          <%!-- Progress overlay --%>
          <div class="absolute inset-0 bg-black bg-opacity-50 flex flex-col items-center justify-center">
            <span class="text-white text-lg font-medium">{entry.progress}%</span>
            <p class="text-white text-sm mt-1">{entry.client_name}</p>
            <button
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              class="mt-2 px-3 py-1 bg-white bg-opacity-20 hover:bg-opacity-30 rounded text-white text-sm"
            >
              Cancel
            </button>
          </div>
        <% else %>
          <%= if @current_url do %>
            <img
              src={resolve(@current_url)}
              alt="Current cover"
              class="h-full w-full object-cover"
            />
            <div class="absolute inset-0 bg-black bg-opacity-0 hover:bg-opacity-40 flex items-center justify-center transition-all group">
              <div class="opacity-0 group-hover:opacity-100 transition-opacity text-center">
                <svg
                  class="mx-auto h-10 w-10 text-white"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                  />
                </svg>
                <p class="text-white text-sm mt-2">Click or drag to change</p>
              </div>
            </div>
          <% else %>
            <div class="h-full w-full flex flex-col items-center justify-center">
              <svg
                class="h-12 w-12 text-gray-400"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
              <p class="mt-2 text-sm text-gray-600">
                <span class="font-medium text-indigo-600">Click to upload</span>
                or drag and drop
              </p>
              <p class="mt-1 text-xs text-gray-500">
                Recommended: 1200×630px
              </p>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Errors --%>
      <p
        :for={err <- Phoenix.Component.upload_errors(@upload)}
        class="mt-2 text-sm text-red-600"
      >
        {error_to_string(err)}
      </p>
    </div>
    """
  end

  # Private helper functions

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
    end
  end

  defp format_bytes(_), do: "Unknown size"
end
