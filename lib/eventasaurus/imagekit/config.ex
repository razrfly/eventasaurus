defmodule Eventasaurus.ImageKit.Config do
  @moduledoc """
  ImageKit configuration from environment variables.

  Provides centralized access to ImageKit credentials and settings.
  """

  @doc """
  Get the ImageKit URL endpoint for CDN delivery.

  ## Examples

      iex> Config.url_endpoint()
      "https://ik.imagekit.io/wombie"
  """
  def url_endpoint do
    System.get_env("IMAGEKIT_END_POINT") ||
      raise "IMAGEKIT_END_POINT not configured in environment"
  end

  @doc """
  Get the ImageKit public key for client-side operations.

  Note: Not currently used for server-side uploads, but available for future use.
  """
  def public_key do
    System.get_env("IMAGEKIT_PUBLIC_KEY") ||
      raise "IMAGEKIT_PUBLIC_KEY not configured in environment"
  end

  @doc """
  Get the ImageKit private key for server-side uploads.

  ⚠️ SECURITY: This key should NEVER be exposed to clients.
  Only use in server-side code.
  """
  def private_key do
    System.get_env("IMAGEKIT_PRIVATE_KEY") ||
      raise "IMAGEKIT_PRIVATE_KEY not configured in environment"
  end

  @doc """
  Generate HTTP Basic Auth header for ImageKit Upload API.

  ImageKit uses HTTP Basic Authentication with format:
  - Username: private_key
  - Password: (empty string)

  The format is: `Basic base64(private_key:)`
  Note the colon after the private key.

  ## Examples

      iex> Config.auth_header()
      "Basic cHJpdmF0ZV9hYmMxMjM6"
  """
  def auth_header do
    # ImageKit requires: Basic base64(private_key:)
    # Note: private_key is username, password is empty (hence the colon)
    credentials = "#{private_key()}:"
    encoded = Base.encode64(credentials)
    "Basic #{encoded}"
  end

  @doc """
  Get the ImageKit upload endpoint URL.

  This is the API endpoint for uploading files to ImageKit.
  """
  def upload_endpoint do
    "https://upload.imagekit.io/api/v1/files/upload"
  end
end
