defmodule EventasaurusWeb.Components.SupabaseUploadComponent do
  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Storage.UploadLive

  @impl true
  def mount(socket) do
    {:ok,
      socket
      |> assign(:uploaded_url, nil)
      |> assign(:upload_error, nil)
    }
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> UploadLive.allow_upload(:image, max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"_target" => ["photo"]}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, uploaded_url: nil)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    case UploadLive.save_upload(socket, :image) do
      {:ok, url} ->
        # Call parent callback if provided
        if function_exported?(socket.assigns.parent_module, socket.assigns.parent_callback, 2) do
          apply(socket.assigns.parent_module, socket.assigns.parent_callback, [socket.assigns.id, url])
        end

        {:noreply,
          socket
          |> assign(:uploaded_url, url)
          |> assign(:upload_error, nil)
        }

      {:error, reason} ->
        {:noreply, assign(socket, :upload_error, reason)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="upload-component">
      <form phx-submit="save" phx-change="validate" phx-target={@myself}>
        <div class="upload-container">
          <%= if @uploaded_url do %>
            <div class="preview-container">
              <img src={@uploaded_url} alt="Uploaded image" class="preview-image"/>
              <input type="hidden" name={@field_name} value={@uploaded_url} />
            </div>
          <% else %>
            <div class="upload-dropzone" phx-drop-target={@uploads.image.ref}>
              <.live_file_input upload={@uploads.image} class="sr-only" />
              <div class="upload-prompt">
                <svg class="upload-icon" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
                </svg>
                <p class="upload-text">Drag and drop an image or click to browse</p>
                <p class="upload-hint">JPG, PNG or GIF • 10MB max</p>
              </div>
            </div>
          <% end %>
        </div>

        <%= for entry <- @uploads.image.entries do %>
          <div class="upload-entry">
            <div class="upload-progress">
              <div class="upload-progress-bar" style={"width: #{entry.progress}%"}></div>
            </div>
            <p class="upload-filename"><%= entry.client_name %></p>

            <%= for err <- upload_errors(@uploads.image, entry) do %>
              <p class="upload-error"><%= error_to_string(err) %></p>
            <% end %>
          </div>
        <% end %>

        <%= if @upload_error do %>
          <p class="upload-error"><%= @upload_error %></p>
        <% end %>

        <div class="upload-actions">
          <button type="submit" class="upload-button" disabled={@uploads.image.entries == []}>
            Upload
          </button>

          <%= if @uploaded_url do %>
            <button type="button" class="change-button" phx-click="reset" phx-target={@myself}>
              Change Image
            </button>
          <% end %>
        </div>
      </form>
    </div>
    """
  end

  # Helper to convert upload errors to user-friendly messages
  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:not_accepted), do: "Invalid file type (only JPG, PNG, GIF allowed)"
  defp error_to_string(:too_many_files), do: "You can only upload one file"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
