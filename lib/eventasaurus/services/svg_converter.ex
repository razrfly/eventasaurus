defmodule Eventasaurus.Services.SvgConverter do
  @moduledoc """
  Handles conversion of SVG templates to PNG images for social cards.

  This module provides functionality to convert SVG content to PNG format
  using the rsvg-convert system command, with proper error handling,
  temporary file management, and cleanup.
  """

  require Logger
  alias Eventasaurus.Services.SocialCardHash

  @doc """
  Converts an SVG string to a PNG file and returns the path to the PNG file.

  ## Parameters

    * `svg_content` - The SVG content as a string
    * `event_id` - The event ID for filename generation
    * `event` - The event struct for hash generation

  ## Returns

    * `{:ok, png_path}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> svg_content = "<svg>...</svg>"
      iex> event = %{image_url: "test.jpg", updated_at: ~N[2023-01-01 12:00:00]}
      iex> Eventasaurus.Services.SvgConverter.svg_to_png(svg_content, "123", event)
      {:ok, "/tmp/eventasaurus_123_a1b2c3d4.png"}

  """
  @spec svg_to_png(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, atom()}
  def svg_to_png(svg_content, event_id, event) do
    # Generate file paths
    svg_path = SocialCardHash.generate_temp_path(event_id, event, "svg")
    png_path = SocialCardHash.generate_temp_path(event_id, event, "png")

    Logger.debug("Converting SVG to PNG: #{svg_path} -> #{png_path}")

    # Extract any local image file paths from SVG content to clean up later
    temp_image_files = extract_temp_image_files(svg_content)

    # Write SVG content to temporary file
    with :ok <- File.write(svg_path, svg_content),
         {_, 0} <-
           System.cmd("rsvg-convert", [
             "-o",
             png_path,
             "--width",
             "800",
             "--height",
             "419",
             "--format",
             "png",
             svg_path
           ]) do
      # Clean up SVG file and temporary images after successful conversion
      File.rm(svg_path)
      cleanup_files(temp_image_files)
      Logger.info("Successfully converted social card for event #{event_id}")
      {:ok, png_path}
    else
      {:error, reason} ->
        Logger.error("Failed to write SVG file: #{inspect(reason)}")
        cleanup_files([svg_path, png_path] ++ temp_image_files)
        {:error, :svg_write_failed}

      {error_output, exit_code} ->
        Logger.error("rsvg-convert failed with exit code #{exit_code}: #{inspect(error_output)}")
        cleanup_files([svg_path, png_path] ++ temp_image_files)
        {:error, :conversion_failed}
    end
  end

  @doc """
  Cleans up temporary PNG file after it has been served.

  Uses a Task with a delay to ensure the file isn't deleted while being served.

  ## Parameters

    * `png_path` - Path to the PNG file to clean up

  ## Examples

      iex> Eventasaurus.Services.SvgConverter.cleanup_temp_file("/tmp/test.png")
      :ok

  """
  @spec cleanup_temp_file(String.t()) :: :ok
  def cleanup_temp_file(png_path) do
    # Schedule file deletion with a small delay to ensure it's not deleted while being served
    Task.start(fn ->
      # 5 second delay
      Process.sleep(5000)

      case File.rm(png_path) do
        :ok ->
          Logger.debug("Cleaned up temporary file: #{png_path}")

        {:error, reason} ->
          Logger.warn("Failed to cleanup temporary file #{png_path}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Verifies that the rsvg-convert command is available on the system.

  ## Returns

    * `:ok` if rsvg-convert is available
    * `{:error, :command_not_found}` if not available

  """
  @spec verify_rsvg_available() :: :ok | {:error, :command_not_found}
  def verify_rsvg_available do
    case System.find_executable("rsvg-convert") do
      nil -> {:error, :command_not_found}
      _path -> :ok
    end
  end

  @doc """
  Gets information about the installed rsvg-convert version.

  ## Returns

    * `{:ok, version_info}` if successful
    * `{:error, reason}` if failed

  """
  @spec get_rsvg_version() :: {:ok, String.t()} | {:error, atom()}
  def get_rsvg_version do
    case System.cmd("rsvg-convert", ["--version"]) do
      {output, 0} -> {:ok, String.trim(output)}
      {_, _} -> {:error, :version_check_failed}
    end
  end

  @doc """
  Downloads an external image URL to a temporary file and returns the local path.
  Returns {:ok, local_path} on success, {:error, reason} on failure.
  """
  @spec download_image_locally(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def download_image_locally(image_url) when is_binary(image_url) do
    try do
      # Create a temporary file for the image
      temp_dir = System.tmp_dir()
      image_extension = Path.extname(URI.parse(image_url).path) || ".jpg"
      temp_filename = "social_card_img_#{System.unique_integer([:positive])}#{image_extension}"
      temp_path = Path.join(temp_dir, temp_filename)

      # Download the image using HTTPoison or similar
      case HTTPoison.get(image_url, [], follow_redirect: true, timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: image_data}} ->
          File.write!(temp_path, image_data)
          {:ok, temp_path}

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          {:error, "HTTP #{status_code} when downloading image"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Download failed: #{inspect(error)}"}
    end
  end

  def download_image_locally(_), do: {:error, "Invalid image URL"}

  # Private helper to clean up multiple files
  defp cleanup_files(file_paths) do
    Enum.each(file_paths, fn path ->
      case File.rm(path) do
        :ok ->
          :ok

        # File doesn't exist, that's fine
        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          Logger.warn("Failed to cleanup file #{path}: #{inspect(reason)}")
      end
    end)
  end

  # Private helper to extract temporary image file paths from SVG content
  defp extract_temp_image_files(svg_content) do
    # Find file:// URLs in the SVG content that point to our temporary images
    regex = ~r/file:\/\/([^"]+social_card_img_[^"]*)/

    Regex.scan(regex, svg_content)
    |> Enum.map(fn [_full_match, file_path] -> file_path end)
    |> Enum.uniq()
  end
end
