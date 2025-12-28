defmodule EventasaurusApp.Images.ImageEnv do
  @moduledoc """
  Shared environment detection for image caching modules.

  In production, images are cached to R2 and served via CDN.
  In dev/test, cache lookups are skipped and original URLs are used.

  This prevents dev/test from:
  - Polluting production R2 bucket with test images
  - Making unnecessary R2 API calls
  - Experiencing cache-related issues during development
  """

  @doc """
  Returns true if running in production environment.

  Image cache lookups only run in production - dev/test use original URLs.

  ## Examples

      iex> ImageEnv.production?()
      true  # in production

      iex> ImageEnv.production?()
      false  # in dev/test
  """
  @spec production?() :: boolean()
  def production? do
    Application.get_env(:eventasaurus, :environment) == :prod
  end
end
