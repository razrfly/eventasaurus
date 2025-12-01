# Image Upload Guide

This guide explains how to add image uploads to any feature in Eventasaurus using the unified upload system.

## Overview

Eventasaurus uses Phoenix LiveView's external upload feature with Cloudflare R2 for efficient, direct browser-to-storage uploads. This system provides:

- **Direct uploads**: Files go directly from browser to R2 (not through the server)
- **Progress tracking**: Real-time progress updates during upload
- **Drag and drop**: Native drag-and-drop support
- **Preview**: Live image preview before save
- **Consistent UI**: Reusable components across all features

## Quick Start

### Step 1: Import the Uploads Module

In your LiveView module:

```elixir
defmodule MyAppWeb.MyFeatureLive do
  use MyAppWeb, :live_view

  import EventasaurusWeb.Uploads

  # ... rest of module
end
```

### Step 2: Configure Upload in Mount

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:upload_folder, "my_feature")  # Required: folder in R2
   |> allow_upload(:cover_image, image_upload_config())}
end
```

### Step 3: Add Component to Template

```heex
<EventasaurusWeb.Components.UploadComponents.image_upload
  upload={@uploads.cover_image}
  label="Cover Image"
/>
```

Or import the component:

```elixir
# In your LiveView
import EventasaurusWeb.Components.UploadComponents
```

```heex
<.image_upload upload={@uploads.cover_image} label="Cover Image" />
```

### Step 4: Handle Cancel Event

Add a handler for the cancel button:

```elixir
def handle_event("cancel-upload", %{"ref" => ref}, socket) do
  {:noreply, cancel_upload(socket, :cover_image, ref)}
end
```

### Step 5: Get Uploaded URL on Save

```elixir
def handle_event("save", params, socket) do
  # Get the uploaded URL (nil if no file uploaded)
  cover_url = get_uploaded_url(socket, :cover_image)

  # Save to database
  case MyContext.create_thing(%{
    cover_image_url: cover_url || existing_url,
    # ... other params
  }) do
    {:ok, thing} ->
      {:noreply, push_navigate(socket, to: ~p"/things/#{thing}")}

    {:error, changeset} ->
      {:noreply, assign(socket, :changeset, changeset)}
  end
end
```

## Configuration Options

### image_upload_config/1

```elixir
# Default configuration
allow_upload(:image, image_upload_config())

# Custom max file size (10MB)
allow_upload(:image, image_upload_config(max_file_size: 10_000_000))

# Allow multiple files
allow_upload(:gallery, image_upload_config(max_entries: 5))

# Custom accepted types
allow_upload(:avatar, image_upload_config(accept: ~w(.jpg .jpeg .png)))
```

Default values:
- `accept`: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`
- `max_entries`: 1
- `max_file_size`: 5MB (5,000,000 bytes)
- `auto_upload`: true (files upload immediately when selected)

## Available Components

### image_upload

Full-featured upload with drag-and-drop, preview, and progress:

```heex
<.image_upload
  upload={@uploads.cover_image}
  label="Cover Image"
  current_url={@thing.cover_image_url}
  help_text="Recommended size: 1200×630px"
/>
```

### image_upload_compact

Compact square upload for avatars or small images:

```heex
<.image_upload_compact
  upload={@uploads.avatar}
  current_url={@user.avatar_url}
  size="md"
/>
```

Sizes: `"sm"` (64px), `"md"` (96px), `"lg"` (128px)

### cover_image_upload

Wide aspect ratio upload for cover/banner images:

```heex
<.cover_image_upload
  upload={@uploads.cover}
  current_url={@event.cover_image_url}
  label="Event Cover"
/>
```

## Helper Functions

### get_uploaded_url/2

Get the public CDN URL of an uploaded file:

```elixir
url = get_uploaded_url(socket, :cover_image)
# Returns: "https://cdn2.wombie.com/events/1234_abcd.jpg" or nil
```

### get_uploaded_urls/2

Get all URLs for multi-file uploads:

```elixir
urls = get_uploaded_urls(socket, :gallery)
# Returns: ["https://cdn2.wombie.com/...", "https://cdn2.wombie.com/..."]
```

### consume_uploaded_urls/2

Get URLs and consume entries (clears them from socket):

```elixir
urls = consume_uploaded_urls(socket, :cover_image)
```

### has_pending_uploads?/1

Check if uploads are in progress:

```heex
<button type="submit" disabled={has_pending_uploads?(@uploads.cover_image)}>
  Save
</button>
```

## Complete Example

Here's a complete example of adding image upload to a feature:

```elixir
defmodule MyAppWeb.ThingLive.New do
  use MyAppWeb, :live_view

  import EventasaurusWeb.Uploads
  import EventasaurusWeb.Components.UploadComponents

  alias MyApp.Things

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:upload_folder, "things")
     |> assign(:changeset, Things.change_thing(%Thing{}))
     |> allow_upload(:cover_image, image_upload_config())}
  end

  def render(assigns) do
    ~H"""
    <form phx-submit="save" phx-change="validate">
      <.input field={@form[:name]} label="Name" />

      <.image_upload
        upload={@uploads.cover_image}
        label="Cover Image"
      />

      <button type="submit" disabled={has_pending_uploads?(@uploads.cover_image)}>
        Create
      </button>
    </form>
    """
  end

  def handle_event("validate", %{"thing" => params}, socket) do
    changeset = Things.change_thing(%Thing{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :cover_image, ref)}
  end

  def handle_event("save", %{"thing" => params}, socket) do
    cover_url = get_uploaded_url(socket, :cover_image)

    params = Map.put(params, "cover_image_url", cover_url)

    case Things.create_thing(params) do
      {:ok, thing} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created!")
         |> push_navigate(to: ~p"/things/#{thing}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end
end
```

## Displaying Uploaded Images

When displaying images that may be stored in R2 or other sources, use the `resolve/1` helper:

```heex
<img src={resolve(@thing.cover_image_url)} alt="Cover" />
```

This ensures URLs are properly resolved regardless of storage backend.

## Architecture

The upload system consists of:

1. **EventasaurusWeb.Uploads** - Elixir module with upload configuration and helpers
2. **EventasaurusWeb.Components.UploadComponents** - HEEx components for UI
3. **assets/js/uploaders.js** - JavaScript uploader for direct R2 uploads
4. **EventasaurusApp.Services.R2Client** - Backend R2 operations

Flow:
1. User selects file
2. LiveView calls `presign_r2_upload/2` to get presigned URL
3. JavaScript uploader sends file directly to R2
4. On completion, public URL is available via `entry.meta.public_url`
5. On form save, use `get_uploaded_url/2` to get the URL

## Troubleshooting

### "Upload failed" error

1. Check browser console for detailed error
2. Verify R2 credentials are configured
3. Check file size is under 5MB
4. Ensure file type is allowed

### Progress stuck at 0%

1. Check network tab for the PUT request
2. Verify CORS is configured on R2 bucket
3. Check for JavaScript errors in console

### Image not showing after upload

1. Ensure you're calling `get_uploaded_url/2` and saving the URL
2. Verify the URL in database is correct
3. Check CDN is accessible

## Migration from Old Upload System

If migrating from the old upload system:

1. Replace `allow_upload` options with `image_upload_config()`
2. Add `:upload_folder` assign in mount
3. Replace custom upload handling with `get_uploaded_url/2`
4. Use new components instead of custom templates
5. Remove references to `UploadService.upload_liveview_files/5`
