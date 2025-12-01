# Image Upload System Guide

This guide documents the unified image upload system in Eventasaurus.

## Overview

Eventasaurus uses a dual-strategy upload system that automatically selects the appropriate storage backend:

| Environment | Strategy | Storage | URL Format |
|-------------|----------|---------|------------|
| Development | Local | `priv/static/uploads/` | `/uploads/events/image.jpg` |
| Production | R2 | Cloudflare R2 | `https://cdn2.wombie.com/events/image.jpg` |

The system provides:
- **Direct uploads**: In production, files go directly from browser to R2 (not through server)
- **Local development**: Files stored locally without R2 configuration
- **Progress tracking**: Real-time progress updates during upload
- **Drag and drop**: Native drag-and-drop support
- **Preview**: Live image preview before save
- **URL resolution**: Automatic URL normalization for display

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Upload Flow                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  User selects file                                                   │
│         │                                                            │
│         ▼                                                            │
│  ┌─────────────────┐                                                │
│  │ LiveView Mount  │  allow_upload(:image, image_upload_config())   │
│  └────────┬────────┘                                                │
│           │                                                          │
│           ▼                                                          │
│  ┌─────────────────────────────────────────┐                        │
│  │         Strategy Detection              │                        │
│  │  (EventasaurusWeb.Uploads.detect_strategy/0)                    │
│  └────────┬───────────────────┬────────────┘                        │
│           │                   │                                      │
│     ┌─────┴─────┐       ┌─────┴─────┐                               │
│     │  :local   │       │   :r2     │                               │
│     │  (dev)    │       │  (prod)   │                               │
│     └─────┬─────┘       └─────┬─────┘                               │
│           │                   │                                      │
│           ▼                   ▼                                      │
│  ┌─────────────────┐  ┌─────────────────┐                           │
│  │ Server upload   │  │ presign_r2_upload│                          │
│  │ to priv/static  │  │ → JS uploader    │                          │
│  │ /uploads/       │  │ → Direct to R2   │                          │
│  └────────┬────────┘  └────────┬────────┘                           │
│           │                    │                                     │
│           └────────┬───────────┘                                     │
│                    │                                                 │
│                    ▼                                                 │
│  ┌─────────────────────────────────────────┐                        │
│  │    get_uploaded_url(socket, :image)     │                        │
│  │    Returns: URL or nil                   │                        │
│  └─────────────────────────────────────────┘                        │
│                    │                                                 │
│                    ▼                                                 │
│  ┌─────────────────────────────────────────┐                        │
│  │         Database Storage                │                        │
│  │   Stores: relative path (events/img.jpg)│                        │
│  └─────────────────────────────────────────┘                        │
│                    │                                                 │
│                    ▼                                                 │
│  ┌─────────────────────────────────────────┐                        │
│  │    ImageUrlHelper.resolve/1             │                        │
│  │    Converts path → full CDN URL         │                        │
│  └─────────────────────────────────────────┘                        │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Modules

| Module | Purpose |
|--------|---------|
| `EventasaurusWeb.Uploads` | Unified upload configuration and helpers |
| `EventasaurusWeb.Components.UploadComponents` | HEEx UI components |
| `EventasaurusWeb.Helpers.ImageUrlHelper` | URL resolution and normalization |
| `EventasaurusApp.Services.R2Client` | Cloudflare R2 operations |
| `assets/js/uploaders.js` | JavaScript uploader for direct R2 uploads |

## Quick Start

### Step 1: Import the Uploads Module

```elixir
defmodule MyAppWeb.MyFeatureLive do
  use MyAppWeb, :live_view

  import EventasaurusWeb.Uploads, only: [image_upload_config: 0, get_uploaded_url: 2]

  # ... rest of module
end
```

### Step 2: Configure Upload in Mount

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:upload_folder, "my_feature")  # Required: folder in storage
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

### Step 4: Handle Cancel Event

```elixir
def handle_event("cancel-upload", %{"ref" => ref}, socket) do
  {:noreply, cancel_upload(socket, :cover_image, ref)}
end
```

### Step 5: Get Uploaded URL on Save

```elixir
def handle_event("save", params, socket) do
  cover_url = get_uploaded_url(socket, :cover_image)

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

## Configuration

### Upload Strategy

The upload strategy is automatically selected based on environment:

```elixir
# In development (MIX_ENV=dev): uses :local strategy
# In production with R2 configured: uses :r2 strategy
# In production without R2: falls back to :local
```

You can override with the `UPLOADS_STRATEGY` environment variable:

```bash
# Force R2 in development (requires R2 credentials)
UPLOADS_STRATEGY=r2 mix phx.server

# Force local in production (not recommended)
UPLOADS_STRATEGY=local mix phx.server
```

### R2 Environment Variables (Production)

```bash
CLOUDFLARE_ACCOUNT_ID=your_account_id
CLOUDFLARE_ACCESS_KEY_ID=your_access_key
CLOUDFLARE_SECRET_ACCESS_KEY=your_secret_key
R2_BUCKET=wombie                           # Optional, default: wombie
R2_CDN_URL=https://cdn2.wombie.com         # Optional, default: https://cdn2.wombie.com
```

### image_upload_config/1 Options

```elixir
# Default configuration
allow_upload(:image, image_upload_config())

# Custom max file size (10MB)
allow_upload(:image, image_upload_config(max_file_size: 10_000_000))

# Allow multiple files
allow_upload(:gallery, image_upload_config(max_entries: 5))

# Custom accepted types
allow_upload(:avatar, image_upload_config(accept: ~w(.jpg .jpeg .png)))

# Force specific strategy
allow_upload(:image, image_upload_config(force_strategy: :local))
```

Default values:
- `accept`: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`
- `max_entries`: 1
- `max_file_size`: 5MB (5,000,000 bytes)
- `auto_upload`: true (files upload immediately when selected)

## URL Storage and Resolution

### Database Storage

URLs are stored as **relative paths** in the database:

```
events/1733069438_a1b2c3d4.jpg
groups/cover_image.png
sources/logo.png
```

This makes the system storage-agnostic and allows easy migration between storage backends.

### URL Resolution

When displaying images, use `ImageUrlHelper.resolve/1`:

```elixir
alias EventasaurusWeb.Helpers.ImageUrlHelper

# In templates
<img src={ImageUrlHelper.resolve(@event.cover_image_url)} />

# Resolves:
# "events/image.jpg" → "https://cdn2.wombie.com/events/image.jpg"
# "/images/default.png" → "/images/default.png" (static asset)
# "https://tmdb.org/..." → "https://tmdb.org/..." (external URL)
# nil → nil
```

The resolver handles:
- Relative paths → Prepends R2 CDN URL
- Static assets (`/images/...`) → Returns as-is
- External URLs → Returns as-is
- Legacy Supabase URLs → Converts to R2 CDN URL (backwards compatibility)

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

Get the public URL of an uploaded file:

```elixir
url = get_uploaded_url(socket, :cover_image)
# Returns: "events/1234_abcd.jpg" (relative path) or nil
```

### get_uploaded_urls/2

Get all URLs for multi-file uploads:

```elixir
urls = get_uploaded_urls(socket, :gallery)
# Returns: ["events/img1.jpg", "events/img2.jpg"]
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

### error_to_string/1

Convert upload errors to user-friendly messages:

```elixir
error_to_string(:too_large)      # "File too large (max 5MB)"
error_to_string(:not_accepted)   # "Invalid file type..."
error_to_string(:too_many_files) # "Too many files selected"
```

## Complete Example

```elixir
defmodule MyAppWeb.ThingLive.New do
  use MyAppWeb, :live_view

  import EventasaurusWeb.Uploads, only: [image_upload_config: 0, get_uploaded_url: 2]
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

## Features Using This System

The following features use the unified upload system:

| Feature | Upload Field | Folder |
|---------|--------------|--------|
| Admin Sources | `logo` | `sources` |
| Groups (New) | `cover_image`, `avatar` | `groups` |
| Groups (Edit) | `cover_image`, `avatar` | `groups` |

Note: Events use a separate JS-hook based upload system (`R2ImageUpload`) that uploads directly to R2 via `UploadController`.

## Storage Cleanup

When users upload a new image to replace an existing one, the system automatically deletes the old image from R2 storage to prevent storage bloat. This happens:

- **Groups Edit**: When cover image or avatar is replaced
- **Admin Sources**: When logo is replaced

### How It Works

The `maybe_delete_old_image/2` helper function:
1. Only triggers when a new image is uploaded (not when keeping existing)
2. Only deletes R2 images (relative paths like `groups/image.jpg`)
3. Skips external URLs (TMDB, Unsplash, picsum, etc.)
4. Runs asynchronously via `Task.start/1` to not block the save operation
5. Logs success/failure for debugging

### Implementation Pattern

```elixir
# In your save handler:
def handle_event("save", params, socket) do
  new_image_url = get_uploaded_url(socket, :image)
  old_image_url = socket.assigns.entity.image_url

  # Delete old image if new one is being uploaded
  maybe_delete_old_image(new_image_url, old_image_url)

  # ... rest of save logic
end

# Helper function (add to your LiveView):
defp maybe_delete_old_image(new_url, old_url)
     when is_binary(new_url) and is_binary(old_url) do
  if is_r2_path?(old_url) do
    Task.start(fn ->
      case R2Client.delete(old_url) do
        :ok -> Logger.info("Deleted old image: #{old_url}")
        {:error, reason} -> Logger.warning("Failed to delete: #{inspect(reason)}")
      end
    end)
  end
end

defp maybe_delete_old_image(_new_url, _old_url), do: :ok

defp is_r2_path?(url) when is_binary(url) do
  not String.starts_with?(url, "http://") and
    not String.starts_with?(url, "https://") and
    not String.starts_with?(url, "/")
end
```

## Troubleshooting

### "Upload failed" error

1. Check browser console for detailed error
2. In dev: Ensure `priv/static/uploads/` directory is writable
3. In prod: Verify R2 credentials are configured
4. Check file size is under 5MB
5. Ensure file type is allowed

### Progress stuck at 0%

1. Check network tab for the PUT request
2. In prod: Verify CORS is configured on R2 bucket
3. Check for JavaScript errors in console

### Image not showing after upload

1. Ensure you're calling `get_uploaded_url/2` and saving the URL
2. Verify the URL in database is correct
3. Use `ImageUrlHelper.resolve/1` when displaying
4. Check CDN is accessible (prod) or uploads folder exists (dev)

### Wrong strategy being used

Check the current strategy:

```elixir
iex> EventasaurusWeb.Uploads.detect_strategy()
:local  # or :r2
```

Override with environment variable:

```bash
UPLOADS_STRATEGY=r2 iex -S mix
```

## Migration History

This system consolidates several legacy upload approaches:

1. **Supabase Storage** (deprecated) - Used Supabase JS client
2. **UploadService** (removed) - Server-side upload handler
3. **Current System** - Unified module with local/R2 strategies

### Database Migration

Legacy Supabase URLs in the database are automatically converted to relative paths by the migration `20251201164938_normalize_supabase_image_urls`. The `ImageUrlHelper.resolve/1` function also handles legacy URLs at runtime as a safety net.

### Removed Files

The following files were removed as part of the migration:
- `lib/eventasaurus_app/services/upload_service.ex` - Replaced by `EventasaurusWeb.Uploads`

### Files Still In Use

These files remain for other purposes:
- `lib/eventasaurus_web/controllers/upload_controller.ex` - Used by Events JS hook
- `lib/eventasaurus_web/helpers/token_helpers.ex` - Used by image picker modal
