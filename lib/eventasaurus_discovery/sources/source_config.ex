defmodule EventasaurusDiscovery.Sources.SourceConfig do
  @moduledoc """
  Behaviour for source configuration.

  Each source must implement this behaviour to provide consistent configuration
  across all event discovery sources.
  """

  @type config :: %{
          name: String.t(),
          slug: String.t(),
          priority: integer(),
          rate_limit: integer(),
          timeout: integer(),
          max_retries: integer(),
          queue: atom(),
          base_url: String.t() | nil,
          api_key: String.t() | nil,
          api_secret: String.t() | nil
        }

  @doc """
  Returns the source configuration
  """
  @callback source_config() :: config()

  @doc """
  Base configuration with defaults that all sources can extend
  """
  def base_config do
    %{
      name: nil,
      slug: nil,
      priority: 50,
      # requests per second
      rate_limit: 5,
      # 10 seconds
      timeout: 10_000,
      max_retries: 3,
      queue: :discovery,
      base_url: nil,
      api_key: nil,
      api_secret: nil
    }
  end

  @doc """
  Merge source-specific config with base config
  """
  def merge_config(source_config) do
    Map.merge(base_config(), source_config)
  end
end
