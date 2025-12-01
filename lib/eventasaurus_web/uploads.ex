defmodule EventasaurusWeb.Uploads do
  @moduledoc """
  Unified upload helpers for Phoenix LiveView uploads.

  This module provides a standardized way to handle image uploads across the application.
  It supports two strategies:

  - **Development**: Server-side uploads to local storage (priv/static/uploads)
  - **Production**: External uploads directly to Cloudflare R2 with presigned URLs

  ## Strategy Selection

  The strategy is selected automatically based on R2 configuration:
  - If R2 is configured (`R2Client.configured?()` returns true) → External R2 uploads
  - Otherwise → Local server-side uploads (development mode)

  You can also force a specific strategy with `:force_strategy` option.

  ## Usage in LiveView

  ### Step 1: Configure upload in mount

      def mount(_params, _session, socket) do
        import EventasaurusWeb.Uploads

        {:ok,
         socket
         |> assign(:upload_folder, "events")
         |> allow_upload(:cover_image, image_upload_config())}
      end

  ### Step 2: Add component to template

      <.image_upload upload={@uploads.cover_image} label="Cover Image" />

  ### Step 3: Get uploaded URL after form submission

      def handle_event("save", params, socket) do
        uploaded_url = get_uploaded_url(socket, :cover_image)
        # Save uploaded_url to database
      end

  ## Configuration Options

  The `image_upload_config/1` function accepts the following options:
  - `:accept` - List of accepted file extensions (default: jpg, jpeg, png, gif, webp)
  - `:max_entries` - Maximum number of files (default: 1)
  - `:max_file_size` - Maximum file size in bytes (default: 5MB)
  - `:force_strategy` - Force `:local` or `:r2` strategy (optional)

  ## Architecture

  This module integrates with:
  - `EventasaurusApp.Services.R2Client` - Generates presigned URLs (production)
  - `EventasaurusWeb.Components.UploadComponents` - UI components
  - `assets/js/uploaders.js` - Client-side upload handler (production)
  """

  alias EventasaurusApp.Services.R2Client

  require Logger

  @max_file_size 5_000_000
  @accepted_types ~w(.jpg .jpeg .png .gif .webp)

  # Store environment at compile time since Mix.env() is not available at runtime in production
  @compile_env Mix.env()

  @doc """
  Returns standard image upload configuration for use with `allow_upload/3`.

  ## Options

  - `:accept` - List of accepted file extensions (default: #{inspect(@accepted_types)})
  - `:max_entries` - Maximum number of files (default: 1)
  - `:max_file_size` - Maximum file size in bytes (default: #{@max_file_size})

  ## Examples

      # Basic usage with defaults
      allow_upload(:cover_image, image_upload_config())

      # Allow multiple files
      allow_upload(:gallery, image_upload_config(max_entries: 5))

      # Custom file size limit (10MB)
      allow_upload(:large_image, image_upload_config(max_file_size: 10_000_000))

      # Custom accepted types
      allow_upload(:avatar, image_upload_config(accept: ~w(.jpg .jpeg .png)))
  """
  def image_upload_config(options \\ []) do
    base_config = [
      accept: Keyword.get(options, :accept, @accepted_types),
      max_entries: Keyword.get(options, :max_entries, 1),
      max_file_size: Keyword.get(options, :max_file_size, @max_file_size)
    ]

    # Determine upload strategy
    strategy = Keyword.get(options, :force_strategy) || detect_strategy()

    case strategy do
      :r2 ->
        # Production: External uploads directly to R2
        Logger.debug("Using R2 external upload strategy")
        base_config ++ [auto_upload: true, external: &presign_r2_upload/2]

      :local ->
        # Development: Server-side uploads to local storage
        # auto_upload: true provides immediate progress feedback (better UX)
        # Files are still stored locally, just transferred to server immediately
        Logger.debug("Using local upload strategy (R2 not configured)")
        base_config ++ [auto_upload: true]
    end
  end

  @doc """
  Detect which upload strategy to use based on environment and R2 configuration.

  Strategy selection:
  - Development: Always use `:local` (server-side storage) by default
  - Production: Use `:r2` if configured, `:local` as fallback

  You can override this by setting the `UPLOADS_STRATEGY` environment variable
  to "r2" or "local", or by passing `:force_strategy` option to `image_upload_config/1`.
  """
  def detect_strategy do
    # Allow explicit override via environment variable
    case System.get_env("UPLOADS_STRATEGY") do
      "r2" ->
        :r2

      "local" ->
        :local

      _ ->
        # Default behavior: local in dev, R2 in prod (if configured)
        # Use @compile_env since Mix.env() is not available at runtime in production
        if @compile_env == :dev do
          :local
        else
          if R2Client.configured?(), do: :r2, else: :local
        end
    end
  end

  @doc """
  Check if using external (R2) uploads.
  """
  def external_uploads? do
    detect_strategy() == :r2
  end

  @doc """
  Presign function for R2 external uploads.

  This function is called by Phoenix LiveView for each file entry to get
  the presigned URL for direct upload. It should not be called directly.

  The socket must have an `:upload_folder` assign set, which determines
  the folder in R2 where the file will be stored.

  ## Returns

  - `{:ok, meta, socket}` - Success with upload metadata
  - `{:error, reason}` - Failed to generate presigned URL
  """
  def presign_r2_upload(entry, socket) do
    folder = socket.assigns[:upload_folder] || "uploads"
    filename = generate_filename(folder, entry)

    case R2Client.presigned_upload_url(filename, content_type: entry.client_type) do
      {:ok, %{upload_url: upload_url, public_url: public_url}} ->
        meta = %{
          uploader: "R2",
          url: upload_url,
          public_url: public_url,
          key: filename
        }

        {:ok, meta, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the public URL of an uploaded file after the upload is complete.

  Call this after form submission to get the CDN URL of the uploaded file.
  Returns `nil` if no file was uploaded or if there were upload errors.

  For R2 strategy: Returns the public URL from the entry metadata.
  For local strategy: Consumes the entry, saves to disk, and returns the local URL.

  ## Examples

      def handle_event("save", params, socket) do
        cover_url = get_uploaded_url(socket, :cover_image)
        avatar_url = get_uploaded_url(socket, :avatar)

        # Save to database
        create_record(%{cover_image_url: cover_url, avatar_url: avatar_url})
      end
  """
  def get_uploaded_url(socket, upload_name) do
    if external_uploads?() do
      # R2 strategy: files already uploaded to R2 via presigned URL
      # We still need to consume entries to complete the upload lifecycle
      results =
        Phoenix.LiveView.consume_uploaded_entries(socket, upload_name, fn meta, _entry ->
          # For external uploads, the file is already in R2
          # The metadata from presign_r2_upload is in the first argument (meta)
          {:ok, meta.public_url}
        end)

      # consume_uploaded_entries unwraps {:ok, value} to just value
      # So we get plain strings, not {:ok, url} tuples
      case results do
        [url] when is_binary(url) -> url
        [url | _] when is_binary(url) -> url
        [{:ok, url}] -> url
        [{:ok, url} | _] -> url
        [] -> nil
        _ -> nil
      end
    else
      # Local strategy: consume and save to disk
      folder = socket.assigns[:upload_folder] || "uploads"

      results =
        Phoenix.LiveView.consume_uploaded_entries(socket, upload_name, fn meta, entry ->
          path = meta[:path] || meta.path
          save_local_upload(path, folder, entry)
        end)

      # Extract URLs - handle both {:ok, url} tuples and plain URL strings
      # Phoenix LiveView's consume_uploaded_entries returns the callback results directly
      case results do
        # Tuple format (expected from save_local_upload)
        [{:ok, url}] -> url
        [{:ok, url} | _] -> url
        # Plain string format (what we're actually getting)
        [url] when is_binary(url) -> url
        [url | _] when is_binary(url) -> url
        # Empty or error cases
        [] -> nil
        _ -> nil
      end
    end
  end

  @doc """
  Get all uploaded URLs for a multi-file upload.

  Similar to `get_uploaded_url/2` but returns a list of URLs for uploads
  that allow multiple files.

  ## Examples

      def handle_event("save", params, socket) do
        gallery_urls = get_uploaded_urls(socket, :gallery)
        # Returns ["https://cdn2.wombie.com/...", "https://cdn2.wombie.com/..."]
      end
  """
  def get_uploaded_urls(socket, upload_name) do
    if external_uploads?() do
      # R2 strategy: files already uploaded to R2 via presigned URL
      # We still need to consume entries to complete the upload lifecycle
      results =
        Phoenix.LiveView.consume_uploaded_entries(socket, upload_name, fn meta, _entry ->
          # For external uploads, metadata from presign is in first argument
          {:ok, meta.public_url}
        end)

      # consume_uploaded_entries unwraps {:ok, value} to just value
      results
      |> Enum.map(fn
        url when is_binary(url) -> url
        {:ok, url} -> url
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
    else
      # Local strategy: consume and save to disk
      folder = socket.assigns[:upload_folder] || "uploads"

      results =
        Phoenix.LiveView.consume_uploaded_entries(socket, upload_name, fn meta, entry ->
          path = meta[:path] || meta.path
          save_local_upload(path, folder, entry)
        end)

      # Extract URLs - handle both {:ok, url} tuples and plain URL strings
      results
      |> Enum.map(fn
        url when is_binary(url) -> url
        {:ok, url} -> url
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
    end
  end

  @doc """
  Consume uploaded entries and return their public URLs.

  This is an alternative to `get_uploaded_url/2` that also consumes
  the upload entries, clearing them from the socket. Use this when you
  need to ensure uploads are only processed once.

  ## Examples

      def handle_event("save", params, socket) do
        urls = consume_uploaded_urls(socket, :cover_image)
        # urls is a list of public URLs
      end
  """
  def consume_uploaded_urls(socket, upload_name) do
    results =
      if external_uploads?() do
        # R2 strategy: files already uploaded, just get URLs from meta
        Phoenix.LiveView.consume_uploaded_entries(socket, upload_name, fn meta, _entry ->
          # For external uploads, metadata from presign is in first argument
          {:ok, meta.public_url}
        end)
      else
        # Local strategy: save to disk
        folder = socket.assigns[:upload_folder] || "uploads"

        Phoenix.LiveView.consume_uploaded_entries(socket, upload_name, fn meta, entry ->
          path = meta[:path] || meta.path
          save_local_upload(path, folder, entry)
        end)
      end

    # Extract URLs - consume_uploaded_entries unwraps {:ok, value} to just value
    results
    |> Enum.map(fn
      url when is_binary(url) -> url
      {:ok, url} -> url
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Check if an upload has any pending entries.

  ## Examples

      <button type="submit" disabled={has_pending_uploads?(@uploads.cover_image)}>
        Save
      </button>
  """
  def has_pending_uploads?(upload) do
    length(upload.entries) > 0 and Enum.any?(upload.entries, &(&1.progress < 100))
  end

  @doc """
  Check if an upload has any errors.
  """
  def has_upload_errors?(upload) do
    length(Phoenix.Component.upload_errors(upload)) > 0
  end

  @doc """
  Convert an upload error atom to a user-friendly string.
  """
  def error_to_string(:too_large), do: "File too large (max 5MB)"
  def error_to_string(:not_accepted), do: "Invalid file type. Please use JPG, PNG, GIF, or WebP."
  def error_to_string(:too_many_files), do: "Too many files selected"
  def error_to_string(:external_client_failure), do: "Upload failed. Please try again."
  def error_to_string(err), do: "Upload error: #{inspect(err)}"

  # Private functions

  defp generate_filename(folder, entry) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    ext = Path.extname(entry.client_name) |> String.downcase()

    # Sanitize folder name
    safe_folder = String.replace(folder, ~r/[^a-zA-Z0-9_\-\/]/, "_")

    "#{safe_folder}/#{timestamp}_#{random}#{ext}"
  end

  # Save an uploaded file to local storage (development mode)
  # Returns {:ok, public_url} for use with consume_uploaded_entries
  defp save_local_upload(temp_path, folder, entry) do
    # Generate unique filename
    filename = generate_filename(folder, entry)

    # Destination path in priv/static/uploads
    dest_dir = Path.join([:code.priv_dir(:eventasaurus), "static", "uploads", folder])
    dest_path = Path.join([:code.priv_dir(:eventasaurus), "static", "uploads", filename])

    # Ensure directory exists
    File.mkdir_p!(dest_dir)

    # Copy the temp file to destination
    case File.cp(temp_path, dest_path) do
      :ok ->
        Logger.debug("Saved local upload to #{dest_path}")
        # Return public URL path
        {:ok, "/uploads/#{filename}"}

      {:error, reason} ->
        Logger.error("Failed to save local upload: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
