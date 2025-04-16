defmodule EventasaurusApp.Storage.UploadLive do
  @moduledoc """
  Helpers for handling file uploads in LiveView components.

  Provides both server-side and direct-to-Supabase upload capabilities.
  """

  alias EventasaurusApp.Storage
  alias Phoenix.LiveView.Upload
  alias EventasaurusApp.Auth.Client, as: SupabaseClient

  @doc """
  Configure LiveView socket for server-side uploads.

  This approach processes uploads through the Phoenix server.

  ## Example
      def mount(_params, _session, socket) do
        socket = UploadLive.allow_upload(socket, :event_image)
        {:ok, socket}
      end
  """
  def allow_upload(socket, field, opts \\ []) do
    default_opts = [
      accept: ~w(.jpg .jpeg .png .gif),
      max_file_size: 10_000_000, # 10MB
      max_entries: 1,
      auto_upload: true
    ]

    Phoenix.LiveView.allow_upload(socket, field, Keyword.merge(default_opts, opts))
  end

  @doc """
  Save uploaded file from LiveView upload to Supabase Storage.

  Use this with standard Phoenix LiveView uploads.

  ## Example
      def handle_event("save", _params, socket) do
        case UploadLive.save_upload(socket, :event_image) do
          {:ok, url} ->
            # Handle success, perhaps update a form with the URL
            {:noreply, assign(socket, cover_image_url: url)}
          {:error, reason} ->
            # Handle error
            {:noreply, put_flash(socket, :error, reason)}
        end
      end
  """
  def save_upload(socket, field, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, "event-images")
    destination_path = Keyword.get(opts, :destination_path)

    # Process the first complete upload entry (usually we only have one)
    consume_uploaded_entries(socket, field, fn %{path: path}, entry ->
      # Generate a filename if not provided
      filename = destination_path || generate_filename(entry.client_name)
      content_type = entry.client_type

      # Upload the file to Supabase
      case Storage.upload(path, %{
        bucket: bucket,
        destination: filename,
        content_type: content_type
      }) do
        {:ok, %{url: url}} -> {:ok, url}
        {:error, error} -> {:error, error.message}
      end
    end)
    |> case do
      [{:ok, url}] -> {:ok, url}  # Return the URL from our first file
      [{:error, reason}] -> {:error, reason}  # Return the error
      [] -> {:error, "No upload found"}  # No complete uploads
      results when is_list(results) -> {:ok, results}  # Multiple uploads (unusual)
    end
  end

  @doc """
  Configure LiveView socket for direct-to-Supabase uploads.

  This method allows files to be uploaded directly from the client browser
  to Supabase Storage, bypassing your Phoenix server for better performance.

  Requires the JS uploader hooks to be configured.

  ## Example
      def mount(_params, _session, socket) do
        socket = UploadLive.allow_direct_upload(socket, :event_image)
        {:ok, socket}
      end
  """
  def allow_direct_upload(socket, field, opts \\ []) do
    default_opts = [
      accept: ~w(.jpg .jpeg .png .gif),
      max_file_size: 10_000_000, # 10MB
      max_entries: 1,
      external: &presign_upload/2
    ]

    Phoenix.LiveView.allow_upload(socket, field, Keyword.merge(default_opts, opts))
  end

  @doc """
  Generate a presigned URL for direct uploads to Supabase.

  Used internally by the direct upload feature.
  """
  def presign_upload(entry, socket) do
    # Get the bucket from options or use default
    uploads = socket.assigns.uploads
    config = uploads[entry.upload_config]
    bucket = config.external[:bucket] || "event-images"

    # Generate a unique file path
    key = generate_filename(entry.client_name)

    # Generate presigned URL for Supabase upload
    case SupabaseClient.storage_from(bucket)
         |> SupabaseClient.create_signed_url_for_upload(key, 3600, %{
           content_type: entry.client_type
         }) do
      {:ok, %{"signedURL" => url}} ->
        # Return metadata for the JS uploader
        meta = %{
          uploader: "SupabaseStorage",
          key: key,
          url: url,
          bucket: bucket
        }
        {:ok, meta, socket}

      {:error, error} ->
        {:error, get_error_message(error), socket}
    end
  end

  @doc """
  Process uploads after direct-to-Supabase upload is complete.

  Call this in your LiveView's handle_event callback to get the URLs
  of successfully uploaded files.

  ## Example
      def handle_event("save", _params, socket) do
        case UploadLive.get_direct_upload_urls(socket, :event_image) do
          {:ok, [url | _]} ->
            # Handle success
            {:noreply, assign(socket, cover_image_url: url)}
          {:error, reason} ->
            # Handle error
            {:noreply, put_flash(socket, :error, reason)}
        end
      end
  """
  def get_direct_upload_urls(socket, field) do
    bucket = socket.assigns.uploads[field].external[:bucket] || "event-images"

    case uploaded_entries(socket, field) do
      [] ->
        {:error, "No uploads completed"}
      entries ->
        urls = Enum.map(entries, fn entry ->
          key = entry.client_name
          case Storage.get_public_url(key, %{bucket: bucket}) do
            {:ok, url} -> url
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

        if urls == [] do
          {:error, "Failed to get URLs for uploaded files"}
        else
          {:ok, urls}
        end
    end
  end

  # Private helpers

  # Generate a unique filename to avoid collisions
  defp generate_filename(client_name) do
    timestamp = System.system_time(:second)
    random_suffix = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

    ext = Path.extname(client_name)
    basename = Path.basename(client_name, ext)
                |> String.downcase()
                |> String.replace(~r/[^a-z0-9\-_]/, "-")

    "#{basename}-#{timestamp}-#{random_suffix}#{ext}"
  end

  # Extract error message from Supabase response
  defp get_error_message(%{message: message}) when is_binary(message), do: message
  defp get_error_message(reason) when is_binary(reason), do: reason
  defp get_error_message(reason), do: "Upload error: #{inspect(reason)}"

  # LiveView helpers to make the module more concise
  defp consume_uploaded_entries(socket, field, func), do: Phoenix.LiveView.consume_uploaded_entries(socket, field, func)
  defp uploaded_entries(socket, field), do: Phoenix.LiveView.uploaded_entries(socket, field)
end
