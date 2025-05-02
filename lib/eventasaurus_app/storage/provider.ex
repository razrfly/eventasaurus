defmodule EventasaurusApp.Storage.Provider do
  @moduledoc """
  Behaviour that defines the interface for storage providers.
  """

  @doc """
  Initialize the storage provider.
  """
  @callback init() :: :ok | {:error, any()}

  @doc """
  Upload a file from a local path to storage.
  """
  @callback upload(source_path :: String.t(), opts :: map()) :: {:ok, String.t()} | {:error, any()}

  @doc """
  Delete a file from storage.
  """
  @callback delete(path :: String.t(), opts :: map()) :: :ok | {:error, any()}

  @doc """
  Check if a file exists in storage.
  """
  @callback exists?(path :: String.t(), opts :: map()) :: {:ok, boolean()} | {:error, any()}

  @doc """
  Get the public URL for a file.
  """
  @callback get_public_url(path :: String.t(), opts :: map()) :: {:ok, String.t()} | {:error, any()}

  @doc """
  Copy a file within storage.
  """
  @callback copy(source_path :: String.t(), destination_path :: String.t(), opts :: map()) :: {:ok, String.t()} | {:error, any()}
end
