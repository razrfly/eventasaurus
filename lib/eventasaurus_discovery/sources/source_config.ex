defmodule EventasaurusDiscovery.Sources.SourceConfig do
  @moduledoc """
  Behaviour for source configuration.

  Each source must implement this behaviour to provide consistent configuration
  across all event discovery sources.

  ## Deduplication Strategies

  Sources can specify their deduplication strategy via `dedup_strategy/0`:

  - `:external_id_only` - Only deduplicate by external_id (same-source only)
  - `:cross_source_fuzzy` - Full cross-source fuzzy matching (performer, venue, date, GPS)
  - `:hybrid` - External ID + limited cross-source matching
  - `:none` - No deduplication (for sources that handle it differently)

  The default strategy is `:cross_source_fuzzy` for full deduplication support.
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

  @type dedup_strategy :: :external_id_only | :cross_source_fuzzy | :hybrid | :none

  @doc """
  Returns the source configuration
  """
  @callback source_config() :: config()

  @doc """
  Returns the deduplication strategy for this source.

  ## Strategies

  - `:external_id_only` - Only checks for existing events with same external_id.
    Best for sources with globally unique identifiers.

  - `:cross_source_fuzzy` - Full fuzzy matching across sources using performer,
    venue, date, and GPS coordinates. Default strategy for most sources.

  - `:hybrid` - Uses external_id for same-source, adds limited cross-source
    matching (e.g., only by performer + date).

  - `:none` - Deduplication handled elsewhere or not applicable.

  ## Example

      @impl EventasaurusDiscovery.Sources.SourceConfig
      def dedup_strategy, do: :cross_source_fuzzy

  """
  @callback dedup_strategy() :: dedup_strategy()

  @optional_callbacks [dedup_strategy: 0]

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

  @doc """
  Get the dedup strategy for a config module, with default fallback.

  If the module implements `dedup_strategy/0`, returns that value.
  Otherwise returns the default `:cross_source_fuzzy`.

  ## Examples

      iex> SourceConfig.get_dedup_strategy(SomeSource.Config)
      :cross_source_fuzzy

  """
  @spec get_dedup_strategy(module()) :: dedup_strategy()
  def get_dedup_strategy(config_module) do
    Code.ensure_loaded(config_module)

    if function_exported?(config_module, :dedup_strategy, 0) do
      config_module.dedup_strategy()
    else
      :cross_source_fuzzy
    end
  end

  @doc """
  Returns all valid dedup strategies.
  """
  @spec valid_strategies() :: [dedup_strategy()]
  def valid_strategies do
    [:external_id_only, :cross_source_fuzzy, :hybrid, :none]
  end
end
