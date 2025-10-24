defmodule Eventasaurus.ImageKit.Uploader do
  @moduledoc """
  Uploads images to ImageKit from remote URLs.

  Uses ImageKit Upload API for permanent storage in ImageKit Media Library.
  Uploaded images are stored permanently and get native ImageKit URLs.

  Reference: https://imagekit.io/docs/api-reference/upload-file/upload-file
  """

  require Logger
  alias Eventasaurus.ImageKit.Config

  @timeout_ms 30_000

  @doc """
  Uploads an image from a remote URL to ImageKit.

  This function downloads the image binary first, then uploads it to ImageKit.
  This is necessary because many provider URLs (like Google Places) require
  authentication and cannot be downloaded directly by ImageKit's servers.

  ## Parameters

  - `remote_url` - Provider image URL (Google Places, Foursquare, Unsplash, etc.)
  - `opts` - Upload options:
    - `:folder` - Target folder (e.g., "/venues/123")
    - `:filename` - Custom filename (auto-generated if not provided)
    - `:tags` - List of tags for organization
    - `:use_unique_filename` - Boolean to auto-generate unique names (default: false)

  ## Returns

  - `{:ok, imagekit_url}` - Upload successful, returns permanent ImageKit URL
  - `{:error, reason}` - Upload failed with reason

  ## Examples

      # Upload venue image
      Uploader.upload_from_url(
        "https://maps.googleapis.com/maps/api/place/photo?photoreference=...",
        folder: "/venues/123",
        filename: "google_places_1.jpg",
        tags: ["google_places", "venue_123"]
      )
      #=> {:ok, "https://ik.imagekit.io/wombie/venues/123/google_places_1.jpg"}

      # Upload with auto-generated filename
      Uploader.upload_from_url(
        "https://images.unsplash.com/photo-123",
        folder: "/test",
        use_unique_filename: true
      )
      #=> {:ok, "https://ik.imagekit.io/wombie/test/image_1729705234.jpg"}
  """
  @spec upload_from_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom() | tuple()}
  def upload_from_url(remote_url, opts \\ []) do
    Logger.info("📥 Downloading image from: #{String.slice(remote_url, 0..80)}...")

    # Step 1: Download the image binary
    case download_image(remote_url) do
      {:ok, {image_binary, content_type}} ->
        Logger.info("✅ Downloaded #{byte_size(image_binary)} bytes (#{content_type})")

        # Step 2: Upload the binary to ImageKit
        upload_binary(image_binary, Keyword.put(opts, :content_type, content_type))

      {:error, reason} ->
        Logger.error("❌ Failed to download image: #{inspect(reason)}")
        {:error, {:download_failed, reason}}
    end
  end

  @spec download_image(String.t()) :: {:ok, {binary(), String.t()}} | {:error, any()}
  defp download_image(url) do
    case Req.get(url, receive_timeout: @timeout_ms) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} when is_binary(body) ->
        content_type = get_content_type(headers)
        {:ok, {body, content_type}}

      {:ok, %Req.Response{status: status, body: _body}} ->
        {:error, {:http_status, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp get_content_type(headers) do
    value =
      cond do
        is_map(headers) ->
          Map.get(headers, "content-type") || Map.get(headers, "Content-Type")

        is_list(headers) ->
          headers
          |> Enum.reduce_while(nil, fn {k, v}, acc ->
            key_string =
              cond do
                is_binary(k) -> k
                is_atom(k) -> to_string(k)
                true -> ""
              end

            if String.downcase(key_string) == "content-type" do
              {:halt, v}
            else
              {:cont, acc}
            end
          end)

        true ->
          nil
      end

    case value do
      [h | _] when is_binary(h) -> String.split(h, ";") |> hd()
      h when is_binary(h) -> String.split(h, ";") |> hd()
      _ -> "image/jpeg"
    end
  end

  @spec upload_binary(binary(), keyword()) :: {:ok, String.t()} | {:error, atom() | tuple()}
  defp upload_binary(image_binary, opts) do
    folder = Keyword.get(opts, :folder, "/venues")
    filename = Keyword.get(opts, :filename, generate_filename())
    tags = Keyword.get(opts, :tags, [])
    use_unique = Keyword.get(opts, :use_unique_filename, false)
    content_type = Keyword.get(opts, :content_type, "image/jpeg")

    Logger.info(
      "📤 Uploading to ImageKit: #{byte_size(image_binary)} bytes → #{folder}/#{filename}"
    )

    # Encode image as base64 for form upload
    # ImageKit accepts base64-encoded files in the "file" parameter
    base64_image = "data:#{content_type};base64," <> Base.encode64(image_binary)

    # Build form data for Req library
    form_data = %{
      "file" => base64_image,
      "fileName" => filename,
      "folder" => folder,
      "useUniqueFileName" => to_string(use_unique)
    }

    form_data =
      if tags != [] do
        Map.put(form_data, "tags", Enum.join(tags, ","))
      else
        form_data
      end

    # Use Req library for form upload
    # Req uses {:basic, "username:password"} format for Basic auth
    userinfo = "#{Config.private_key()}:"

    case Req.post(
           Config.upload_endpoint(),
           form: form_data,
           auth: {:basic, userinfo},
           receive_timeout: @timeout_ms
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        case body do
          %{"url" => imagekit_url} ->
            Logger.info("✅ Uploaded: #{imagekit_url}")
            {:ok, imagekit_url}

          _ ->
            Logger.error("❌ Invalid response format: #{inspect(body)}")
            {:error, :invalid_response}
        end

      {:ok, %Req.Response{status: 401, body: body}} ->
        Logger.error("❌ ImageKit authentication failed - check IMAGEKIT_PRIVATE_KEY")
        Logger.error("Response: #{inspect(body)}")
        {:error, :authentication_failed}

      {:ok, %Req.Response{status: 403, body: body}} ->
        Logger.error("❌ ImageKit forbidden - check dashboard permissions")
        Logger.error("Response: #{inspect(body)}")
        {:error, :forbidden}

      {:ok, %Req.Response{status: 413, body: body}} ->
        Logger.error("❌ Image too large - ImageKit has size limits")
        Logger.error("Response: #{inspect(body)}")
        {:error, :file_too_large}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("❌ ImageKit upload failed (#{status}): #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        Logger.error("❌ HTTP request failed: #{inspect(exception)}")
        {:error, :request_failed}
    end
  end

  @doc """
  Generate a unique filename for uploaded images.

  Uses current timestamp to ensure uniqueness.

  ## Examples

      iex> generate_filename()
      "image_1729705234.jpg"
  """
  def generate_filename do
    timestamp = :os.system_time(:second)
    "image_#{timestamp}.jpg"
  end
end
