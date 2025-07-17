defmodule EventasaurusWeb.Services.DefaultImagesService do
  @moduledoc """
  Service for managing default event images from static assets.
  Handles different categories of images stored in priv/static/images/events/
  """

  @base_url "/images/events"
  @supported_extensions [".jpg", ".jpeg", ".png", ".gif", ".webp"]

  # Get the correct priv directory path for both dev and production
  defp base_path do
    # In production, use the release priv directory; in dev, use the app priv directory
    case Mix.env() do
      :prod ->
        # For releases, static files are in the release directory
        Path.join([Application.app_dir(:eventasaurus, "priv"), "static", "images", "events"])

      _ ->
        # For development, use the standard priv path
        Path.join(["priv", "static", "images", "events"])
    end
  rescue
    # Fallback for production when Mix.env() is not available
    _ -> Path.join([Application.app_dir(:eventasaurus, "priv"), "static", "images", "events"])
  end

  def get_categories do
    path = base_path()

    unless File.exists?(path) do
      require Logger
      Logger.warning("Default images base path does not exist: #{path}")
      []
    else
      case File.ls(path) do
        {:ok, directories} ->
          directories
          |> Enum.filter(&File.dir?(Path.join(path, &1)))
          |> Enum.map(
            &%{
              name: &1,
              display_name: humanize_category(&1),
              path: &1
            }
          )
          |> Enum.sort_by(& &1.display_name)

        {:error, reason} ->
          require Logger
          Logger.error("Failed to list categories from #{path}: #{inspect(reason)}")
          []
      end
    end
  end

  def get_images_for_category(category) do
    # Validate input
    if is_nil(category) or category == "" do
      []
    else
      # Sanitize category to prevent directory traversal
      sanitized_category = Path.basename(to_string(category))
      category_path = Path.join(base_path(), sanitized_category)

      unless File.dir?(category_path) do
        require Logger
        Logger.warning("Category directory does not exist: #{category_path}")
        []
      else
        case File.ls(category_path) do
          {:ok, files} ->
            files
            |> Enum.filter(&is_image_file?/1)
            |> Enum.map(fn filename ->
              %{
                url: "#{@base_url}/#{sanitized_category}/#{filename}",
                filename: filename,
                category: sanitized_category,
                title: humanize_filename(filename)
              }
            end)
            |> Enum.sort_by(& &1.title)

          {:error, reason} ->
            require Logger
            Logger.error("Failed to list images from #{category_path}: #{inspect(reason)}")
            []
        end
      end
    end
  end

  def get_random_image do
    # Get all categories and their images
    all_images =
      get_categories()
      |> Enum.flat_map(fn category -> get_images_for_category(category.name) end)

    case all_images do
      [] -> nil
      images -> Enum.random(images)
    end
  end

  defp is_image_file?(filename) do
    ext = Path.extname(filename) |> String.downcase()
    ext in @supported_extensions
  end

  defp humanize_category(category) do
    category
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize_filename(filename) do
    filename
    |> Path.rootname()
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
