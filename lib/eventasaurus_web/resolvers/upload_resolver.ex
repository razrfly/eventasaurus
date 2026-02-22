defmodule EventasaurusWeb.Resolvers.UploadResolver do
  @moduledoc """
  Resolver for image upload mutations.

  Accepts file uploads via Absinthe's Upload scalar, stores them in
  Cloudflare R2, and returns the public CDN URL.
  """

  require Logger

  alias EventasaurusApp.Services.R2Client

  @allowed_mime_types ~w(image/jpeg image/png image/gif image/webp image/avif)
  @max_file_size 5 * 1024 * 1024

  @spec upload_image(any(), map(), any()) :: {:ok, map()}
  def upload_image(
        _parent,
        %{file: %Absinthe.Blueprint.Input.RawValue{content: upload}},
        _resolution
      ) do
    do_upload(upload)
  end

  def upload_image(_parent, %{file: %Plug.Upload{} = upload}, _resolution) do
    do_upload(upload)
  end

  defp do_upload(%Plug.Upload{content_type: content_type, filename: filename, path: path}) do
    with :ok <- validate_content_type(content_type),
         :ok <- validate_file_size(path),
         {:ok, file_data} <- File.read(path) do
      unique_filename = generate_unique_filename(filename)
      r2_path = "events/#{unique_filename}"

      case R2Client.upload(r2_path, file_data, content_type: content_type) do
        {:ok, url} when is_binary(url) ->
          {:ok, %{url: url, errors: []}}

        {:error, {:not_configured, _}} ->
          # Fallback: use presigned URL flow
          case R2Client.presigned_upload_url(r2_path, content_type: content_type) do
            {:ok, %{public_url: url} = result} ->
              case upload_to_presigned(result.upload_url, path, content_type) do
                {:ok, %{status: status}} when status in 200..299 ->
                  {:ok, %{url: url, errors: []}}

                other ->
                  Logger.error("Upload to presigned URL failed",
                    path: r2_path,
                    response: inspect(other)
                  )

                  {:ok,
                   %{
                     url: nil,
                     errors: [%{field: "file", message: "Failed to upload file to storage"}]
                   }}
              end

            {:error, reason} ->
              Logger.error("Failed to get presigned upload URL",
                path: r2_path,
                reason: inspect(reason)
              )

              {:ok,
               %{
                 url: nil,
                 errors: [
                   %{field: "file", message: "Upload service unavailable"}
                 ]
               }}
          end

        {:error, reason} ->
          Logger.error("R2 upload failed",
            path: r2_path,
            reason: inspect(reason)
          )

          {:ok,
           %{url: nil, errors: [%{field: "file", message: "Upload failed"}]}}
      end
    else
      {:error, :enoent} ->
        {:ok, %{url: nil, errors: [%{field: "file", message: "Could not read uploaded file"}]}}

      {:error, message} when is_binary(message) ->
        {:ok, %{url: nil, errors: [%{field: "file", message: message}]}}

      {:error, reason} ->
        Logger.error("Upload failed in do_upload with clause",
          reason: inspect(reason)
        )

        {:ok, %{url: nil, errors: [%{field: "file", message: "Upload failed"}]}}
    end
  end

  defp validate_content_type(content_type) when content_type in @allowed_mime_types, do: :ok

  defp validate_content_type(_) do
    {:error, "Invalid file type. Allowed: #{Enum.join(@allowed_mime_types, ", ")}"}
  end

  defp validate_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_file_size -> :ok
      {:ok, _} -> {:error, "File exceeds maximum size of #{div(@max_file_size, 1024 * 1024)}MB"}
      {:error, _} -> {:error, "Could not read file"}
    end
  end

  defp generate_unique_filename(original_filename) do
    extension = Path.extname(original_filename || "image.jpg")
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{random}_#{timestamp}#{extension}"
  end

  defp upload_to_presigned(upload_url, file_path, content_type) do
    case File.read(file_path) do
      {:ok, body} ->
        Req.put(upload_url, body: body, headers: [{"content-type", content_type}])

      _ ->
        :error
    end
  end
end
