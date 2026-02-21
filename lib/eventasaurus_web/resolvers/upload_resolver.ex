defmodule EventasaurusWeb.Resolvers.UploadResolver do
  @moduledoc """
  Resolver for image upload mutations.

  Accepts file uploads via Absinthe's Upload scalar, stores them in
  Cloudflare R2, and returns the public CDN URL.
  """

  alias EventasaurusApp.Services.R2Client

  @allowed_mime_types ~w(image/jpeg image/png image/gif image/webp image/avif)
  @max_file_size 5 * 1024 * 1024

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
         :ok <- validate_file_size(path) do
      unique_filename = generate_unique_filename(filename)
      r2_path = "events/#{unique_filename}"

      case R2Client.upload(path, r2_path, content_type: content_type) do
        {:ok, url} when is_binary(url) ->
          {:ok, %{url: url, errors: []}}

        {:error, {:not_configured, _}} ->
          # Fallback: use presigned URL flow
          case R2Client.presigned_upload_url(r2_path, content_type: content_type) do
            {:ok, %{public_url: url} = result} ->
              # Upload the file using the presigned URL
              upload_to_presigned(result.upload_url, path, content_type)
              {:ok, %{url: url, errors: []}}

            {:error, reason} ->
              {:ok,
               %{
                 url: nil,
                 errors: [
                   %{field: "file", message: "Upload service unavailable: #{inspect(reason)}"}
                 ]
               }}
          end

        {:error, reason} ->
          {:ok,
           %{url: nil, errors: [%{field: "file", message: "Upload failed: #{inspect(reason)}"}]}}
      end
    else
      {:error, message} ->
        {:ok, %{url: nil, errors: [%{field: "file", message: message}]}}
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
