defmodule EventasaurusWeb.Services.DefaultImagesService do
  @moduledoc """
  Service for managing default event images.
  This module now serves as a facade to ImageManifest, maintaining backward compatibility
  while using Phoenix's proper static asset handling.
  """

  alias EventasaurusWeb.Services.ImageManifest

  @doc """
  Get all available image categories.
  Delegates to ImageManifest for proper Phoenix asset handling.
  """
  def get_categories do
    ImageManifest.get_categories()
  end

  @doc """
  Get all images for a specific category.
  Maintains backward compatibility by converting atoms to strings.
  Delegates to ImageManifest for proper Phoenix asset handling.
  """
  def get_images_for_category(category) when is_atom(category) do
    category
    |> to_string()
    |> ImageManifest.get_images_for_category()
  end
  
  def get_images_for_category(category) do
    ImageManifest.get_images_for_category(category)
  end

  @doc """
  Get a random image from all categories.
  Delegates to ImageManifest for proper Phoenix asset handling.
  """
  def get_random_image do
    ImageManifest.get_random_image()
  end
end
