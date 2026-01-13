defmodule EventasaurusDiscovery.Http.Config do
  @moduledoc """
  HTTP strategy configuration per source.

  This module manages per-source HTTP configurations, determining which
  adapters to use and in what order for each scraper source.

  ## Strategies

  - `:direct` - Use direct adapter only (fast, no proxy cost)
  - `:proxy` - Use Zyte proxy only (bypasses blocking, has cost)
  - `:fallback` - Try direct first, fallback to proxy on blocking
  - `:auto` - Use per-source configuration (default)

  ## Configuration

  Strategies are configured in `config/runtime.exs`:

      config :eventasaurus, :http_strategies,
        default: [:direct, :zyte],           # Try direct first, fallback to Zyte
        bandsintown: [:zyte],                # Always use Zyte (known blocking)
        cinema_city: [:direct],              # Direct only (API works fine)
        karnet: [:direct, :zyte]             # Try direct, fallback on failure

  ## Usage

      alias EventasaurusDiscovery.Http.Config

      # Get adapter chain for a source
      Config.get_adapter_chain(:bandsintown)
      #=> [EventasaurusDiscovery.Http.Adapters.Zyte]

      # Get default adapter chain
      Config.get_adapter_chain(:unknown_source)
      #=> [EventasaurusDiscovery.Http.Adapters.Direct, ...]

  ## Adapter Selection

  When using `:fallback` or `:auto` strategy, the client will:
  1. Try the first adapter in the chain
  2. If blocked (Cloudflare, CAPTCHA, etc.), try the next adapter
  3. Continue until success or all adapters exhausted
  """

  alias EventasaurusDiscovery.Http.Adapters.{Crawlbase, Direct, Zyte}

  @type source :: atom()
  @type strategy :: :direct | :proxy | :fallback | :auto
  @type adapter_name :: :direct | :zyte | :crawlbase
  @type adapter_module :: module()

  # Map adapter names to modules
  @adapter_modules %{
    direct: Direct,
    zyte: Zyte,
    crawlbase: Crawlbase
  }

  @doc """
  Gets the adapter chain for a source.

  Returns a list of adapter modules to try in order. Only includes
  adapters that are currently available (configured and working).

  ## Examples

      iex> Config.get_adapter_chain(:bandsintown)
      [EventasaurusDiscovery.Http.Adapters.Zyte]

      iex> Config.get_adapter_chain(:cinema_city)
      [EventasaurusDiscovery.Http.Adapters.Direct]

      iex> Config.get_adapter_chain(:unknown_source)
      [EventasaurusDiscovery.Http.Adapters.Direct]
  """
  @spec get_adapter_chain(source()) :: [adapter_module()]
  def get_adapter_chain(source) do
    adapter_names = get_strategy(source)

    adapter_names
    |> Enum.map(&get_adapter_module/1)
    |> Enum.filter(&available?/1)
    |> case do
      [] ->
        # Always fall back to Direct if nothing else available
        [Direct]

      adapters ->
        adapters
    end
  end

  @doc """
  Gets the adapter chain for a given explicit strategy.

  Useful when you want to force a specific strategy regardless
  of the source's configuration.

  ## Strategies

  - `:direct` - Returns `[Direct]`
  - `:proxy` - Returns `[Zyte]` (or available proxy adapters)
  - `:fallback` - Returns `[Direct, Zyte]`
  - `:auto` - Delegates to source-specific config

  ## Examples

      iex> Config.get_adapter_chain_for_strategy(:direct)
      [EventasaurusDiscovery.Http.Adapters.Direct]

      iex> Config.get_adapter_chain_for_strategy(:fallback)
      [EventasaurusDiscovery.Http.Adapters.Direct, EventasaurusDiscovery.Http.Adapters.Zyte]
  """
  @spec get_adapter_chain_for_strategy(strategy(), source()) :: [adapter_module()]
  def get_adapter_chain_for_strategy(strategy, source \\ :default)

  def get_adapter_chain_for_strategy(:direct, _source) do
    [Direct]
  end

  def get_adapter_chain_for_strategy(:proxy, _source) do
    proxy_adapters()
    |> Enum.filter(&available?/1)
    |> case do
      [] -> [Direct]
      adapters -> adapters
    end
  end

  def get_adapter_chain_for_strategy(:fallback, _source) do
    ([Direct] ++ proxy_adapters())
    |> Enum.filter(&available?/1)
    |> Enum.uniq()
  end

  def get_adapter_chain_for_strategy(:auto, source) do
    get_adapter_chain(source)
  end

  @doc """
  Gets the configured strategy for a source.

  Returns a list of adapter names from configuration, or the
  default strategy if the source is not configured.

  ## Examples

      iex> Config.get_strategy(:bandsintown)
      [:zyte]

      iex> Config.get_strategy(:cinema_city)
      [:direct]

      iex> Config.get_strategy(:unknown)
      [:direct, :zyte]
  """
  @spec get_strategy(source()) :: [adapter_name()]
  def get_strategy(source) do
    strategies = get_all_strategies()

    case Map.get(strategies, source) do
      nil -> Map.get(strategies, :default, default_strategy())
      strategy -> strategy
    end
  end

  @doc """
  Gets all configured strategies.

  Returns a map of source names to adapter chains.

  ## Examples

      iex> Config.get_all_strategies()
      %{
        default: [:direct, :zyte],
        bandsintown: [:zyte],
        cinema_city: [:direct]
      }
  """
  @spec get_all_strategies() :: %{source() => [adapter_name()]}
  def get_all_strategies do
    Application.get_env(:eventasaurus, :http_strategies, %{})
    |> normalize_strategies()
  end

  @doc """
  Checks if a source has blocking protection configured.

  Returns true if the source is configured to use Zyte or another
  proxy adapter, either directly or as a fallback.

  ## Examples

      iex> Config.has_blocking_protection?(:bandsintown)
      true

      iex> Config.has_blocking_protection?(:cinema_city)
      false
  """
  @spec has_blocking_protection?(source()) :: boolean()
  def has_blocking_protection?(source) do
    chain = get_adapter_chain(source)
    Enum.any?(chain, &(&1 != Direct))
  end

  @doc """
  Returns whether blocking detection should be enabled for a source.

  Blocking detection is enabled when:
  - Source has fallback configured (multiple adapters)
  - Source uses :fallback or :auto strategy

  ## Examples

      iex> Config.blocking_detection_enabled?(:bandsintown)
      false  # Only Zyte, no fallback needed

      iex> Config.blocking_detection_enabled?(:karnet)
      true   # Has fallback chain
  """
  @spec blocking_detection_enabled?(source()) :: boolean()
  def blocking_detection_enabled?(source) do
    chain = get_adapter_chain(source)
    length(chain) > 1
  end

  @doc """
  Lists all configured sources.

  ## Examples

      iex> Config.configured_sources()
      [:bandsintown, :cinema_city, :karnet, :default]
  """
  @spec configured_sources() :: [source()]
  def configured_sources do
    get_all_strategies()
    |> Map.keys()
  end

  @doc """
  Returns all available adapter modules.

  Only returns adapters that are properly configured and available.

  ## Examples

      iex> Config.available_adapters()
      [EventasaurusDiscovery.Http.Adapters.Direct, EventasaurusDiscovery.Http.Adapters.Zyte]
  """
  @spec available_adapters() :: [adapter_module()]
  def available_adapters do
    all_adapters()
    |> Enum.filter(&available?/1)
  end

  @doc """
  Returns all known adapter modules.

  Includes adapters that may not be configured or available.

  ## Examples

      iex> Config.all_adapters()
      [EventasaurusDiscovery.Http.Adapters.Direct, EventasaurusDiscovery.Http.Adapters.Zyte]
  """
  @spec all_adapters() :: [adapter_module()]
  def all_adapters do
    [Direct, Zyte, Crawlbase]
  end

  # Private functions

  defp get_adapter_module(adapter_name) do
    Map.get(@adapter_modules, adapter_name, Direct)
  end

  defp available?(adapter_module) do
    adapter_module.available?()
  end

  defp proxy_adapters do
    [Zyte, Crawlbase]
  end

  defp default_strategy do
    [:direct, :zyte]
  end

  defp normalize_strategies(strategies) when is_map(strategies) do
    strategies
  end

  defp normalize_strategies(strategies) when is_list(strategies) do
    # Convert keyword list to map
    Enum.into(strategies, %{})
  end

  defp normalize_strategies(_), do: %{}
end
