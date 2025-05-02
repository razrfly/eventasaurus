defmodule EventasaurusApp.Storage do
  @moduledoc """
  Storage facade that delegates to configured provider.
  """

  alias EventasaurusApp.Storage.StorageError

  @doc """
  Upload a file with given options.
  """
  def upload(source_path, opts \\ %{}) do
    provider().upload(source_path, opts)
  end

  @doc """
  Upload a file to a bucket.
  """
  def upload(bucket, key, source_path) do
    upload(source_path, %{bucket: bucket, key: key})
  end

  @doc """
  Delete a file with given options.
  """
  def delete(path, opts \\ %{}) do
    provider().delete(path, opts)
  end

  @doc """
  Check if a file exists with given options.
  """
  def exists?(path, opts \\ %{}) do
    provider().exists?(path, opts)
  end

  @doc """
  Get the public URL for a file with given options.
  """
  def get_public_url(path, opts \\ %{}) do
    provider().get_public_url(path, opts)
  end

  @doc """
  Copy a file within storage with given options.
  """
  def copy(source_path, destination_path, opts \\ %{}) do
    provider().copy(source_path, destination_path, opts)
  end

  @doc """
  Initialize the configured storage provider.
  """
  def init do
    provider().init()
  end

  @doc """
  Get the currently configured provider module.
  """
  def provider do
    Application.get_env(:eventasaurus, :storage_provider, EventasaurusApp.Storage.SupabaseProvider)
  end
end
