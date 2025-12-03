defmodule EventasaurusWeb.Services.ImageManifest do
  @moduledoc """
  Dynamically reads available default event images from the filesystem.
  Filters out fingerprinted/hashed files that should not be in version control.

  Uses ETS caching to avoid repeated filesystem reads on every page load.
  Cache is populated on first access and persists for the lifetime of the application.
  """

  use EventasaurusWeb, :verified_routes

  @images_base_path "priv/static/images/events"
  @cache_table :image_manifest_cache

  @doc """
  Returns all available categories.
  Results are cached in ETS after first filesystem read.
  """
  def get_categories do
    get_cached(:categories, &load_categories/0)
  end

  @doc """
  Returns the complete manifest of all images organized by category.
  Results are cached in ETS after first filesystem read.
  """
  def get_manifest do
    get_cached(:manifest, &load_manifest/0)
  end

  @doc """
  Get images for a specific category.
  Results are cached in ETS after first filesystem read.
  """
  def get_images_for_category(category) when is_binary(category) do
    # Use manifest cache which contains all categories
    manifest = get_manifest()
    Map.get(manifest, category, [])
  end

  def get_images_for_category(_), do: []

  @doc """
  Get a random image from all categories.
  Uses cached manifest data.
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

  @doc """
  Clears the cache. Useful for development or when images change.
  """
  def clear_cache do
    if :ets.whereis(@cache_table) != :undefined do
      :ets.delete_all_objects(@cache_table)
    end

    :ok
  end

  # Private helpers for caching

  defp get_cached(key, loader_fn) do
    ensure_cache_table()

    case :ets.lookup(@cache_table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = loader_fn.()
        :ets.insert(@cache_table, {key, value})
        value
    end
  end

  defp ensure_cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        try do
          # Use named_table and public so it persists and is accessible
          # read_concurrency optimized for many reads, few writes
          :ets.new(@cache_table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError ->
            # Table was created by a racing process; safe to proceed
            :ok
        end

      _ ->
        :ok
    end
  end

  # Filesystem loading functions (only called once, then cached)

  defp load_categories do
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

  defp load_manifest do
    categories = load_categories()

    Map.new(categories, fn %{name: category} ->
      {category, load_images_for_category(category)}
    end)
  end

  defp load_images_for_category(category) when is_binary(category) do
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
