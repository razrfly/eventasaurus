defmodule EventasaurusWeb.Services.ImageManifest do
  @moduledoc """
  Dynamically reads available default event images from the filesystem.
  Filters out fingerprinted/hashed files that should not be in version control.
  """

  use EventasaurusWeb, :verified_routes

  @images_base_path "priv/static/images/events"

  @doc """
  Returns all available categories by reading the filesystem.
  """
  def get_categories do
    base_path = Path.join(Application.app_dir(:eventasaurus), @images_base_path)

    case File.ls(base_path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&File.dir?(Path.join(base_path, &1)))
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.map(fn name ->
          %{
            name: name,
            display_name: humanize_category(name),
            path: name
          }
        end)
        |> Enum.sort_by(& &1.display_name)

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns images for a specific category by reading the filesystem.
  """
  def get_manifest do
    categories = get_categories()

    Map.new(categories, fn %{name: category} ->
      {category, get_images_for_category(category)}
    end)
  end

  @doc """
  Get images for a specific category from the filesystem.
  Filters out fingerprinted files completely - they should not be in version control.
  """
  def get_images_for_category(category) when is_binary(category) do
    base_path = Path.join(Application.app_dir(:eventasaurus), @images_base_path)
    category_path = Path.join(base_path, category)

    case File.ls(category_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&valid_image_file?/1)
        # Always filter out fingerprinted files
        |> Enum.reject(&fingerprinted_file?/1)
        |> Enum.map(fn filename ->
          %{
            filename: filename,
            title: humanize_filename(filename),
            url: ~p"/images/events/#{category}/#{filename}",
            category: category
          }
        end)
        |> Enum.sort_by(& &1.filename)

      {:error, _} ->
        []
    end
  end

  def get_images_for_category(_), do: []

  @doc """
  Get a random image from all categories.
  """
  def get_random_image do
    all_images =
      get_manifest()
      |> Map.values()
      |> List.flatten()

    case all_images do
      [] -> nil
      images -> Enum.random(images)
    end
  end

  # Private helpers

  defp valid_image_file?(filename) do
    extensions = ~w(.png .jpg .jpeg .gif .webp .svg)
    ext = filename |> String.downcase() |> Path.extname()
    ext in extensions
  end

  defp fingerprinted_file?(filename) do
    # Check if filename contains a 32-character hex hash before the extension
    Regex.match?(~r/-[a-f0-9]{32}\.[^.]+$/, filename)
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
    |> Path.basename()
    |> Path.rootname()
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
