defmodule EventasaurusWeb.Services.DefaultImagesService do
  @moduledoc """
  Service for managing default event images from static assets.
  Handles different categories of images stored in priv/static/images/events/
  """

  @base_path "priv/static/images/events"
  @base_url "/images/events"
  @supported_extensions [".jpg", ".jpeg", ".png", ".gif", ".webp"]

  def get_categories do
    case File.ls(@base_path) do
      {:ok, directories} ->
        directories
        |> Enum.filter(&File.dir?(Path.join(@base_path, &1)))
        |> Enum.map(&%{
          name: &1,
          display_name: humanize_category(&1),
          path: &1
        })
        |> Enum.sort_by(& &1.display_name)

      {:error, _} -> []
    end
  end

  def get_images_for_category(category) do
    category_path = Path.join(@base_path, category)

    case File.ls(category_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&is_image_file?/1)
        |> Enum.map(fn filename ->
          %{
            url: "#{@base_url}/#{category}/#{filename}",
            filename: filename,
            category: category,
            title: humanize_filename(filename)
          }
        end)
        |> Enum.sort_by(& &1.title)

      {:error, _} -> []
    end
  end

  def get_featured_images do
    # For now, just return general category as featured
    # Later we can implement a more sophisticated featured algorithm
    get_images_for_category("general")
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
