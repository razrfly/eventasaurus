defmodule EventasaurusWeb.Services.RichDataManager do
  @moduledoc """
  Unified manager for rich data providers.

  Orchestrates multiple external API providers (TMDB, Spotify, etc.) to provide
  comprehensive metadata for events. Handles provider registration, search
  aggregation, and data normalization.

  ## Features

  - Provider registration and management
  - Unified search across multiple providers
  - Automatic data fetching and caching
  - Provider health monitoring
  - Fallback and error handling
  - Configuration validation

  ## Usage

      # Search across all providers
      {:ok, results} = RichDataManager.search("The Matrix")

      # Get details from specific provider
      {:ok, details} = RichDataManager.get_details(:tmdb, 603, :movie)

      # Get cached details (recommended)
      {:ok, details} = RichDataManager.get_cached_details(:tmdb, 603, :movie)
  """

  use GenServer
  require Logger

  alias EventasaurusWeb.Services.TmdbRichDataProvider
  alias EventasaurusWeb.Services.GooglePlacesRichDataProvider
  alias EventasaurusWeb.Services.MusicBrainzRichDataProvider

  @registry_table :rich_data_providers
  @default_providers [
    TmdbRichDataProvider,
    GooglePlacesRichDataProvider,
    MusicBrainzRichDataProvider
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new provider with the manager.

  ## Parameters

  - `provider_module`: Module implementing RichDataProviderBehaviour

  ## Returns

  - `:ok`: Provider registered successfully
  - `{:error, reason}`: Registration failed
  """
  def register_provider(provider_module) do
    GenServer.call(__MODULE__, {:register_provider, provider_module})
  end

  @doc """
  Unregister a provider from the manager.

  ## Parameters

  - `provider_id`: Provider ID atom (e.g., :tmdb)

  ## Returns

  - `:ok`: Provider unregistered successfully
  - `{:error, reason}`: Provider not found
  """
  def unregister_provider(provider_id) do
    GenServer.call(__MODULE__, {:unregister_provider, provider_id})
  end

  @doc """
  Get list of registered providers.

  ## Returns

  - `[{provider_id, provider_module, status}]`: List of providers with status
  """
  def list_providers do
    GenServer.call(__MODULE__, :list_providers)
  end

  @doc """
  Search for content across all registered providers.

  ## Parameters

  - `query`: Search term
  - `options`: Search options (providers, types, page, etc.)

  ## Options

  - `:providers` - List of provider IDs to search (default: all)
  - `:types` - List of content types to search (default: all)
  - `:page` - Page number for pagination (default: 1)
  - `:limit` - Maximum results per provider (default: 10)
  - `:timeout` - Search timeout in ms (default: 30000)

  ## Returns

  - `{:ok, results}`: List of search results grouped by provider
  - `{:error, reason}`: Search failed
  """
  def search(query, options \\ %{}) do
    GenServer.call(__MODULE__, {:search, query, options}, 30_000)
  end

  @doc """
  Get details for specific content from a provider.

  ## Parameters

  - `provider_id`: Provider ID (e.g., :tmdb)
  - `content_id`: Provider-specific content ID
  - `content_type`: Content type (:movie, :tv, etc.)
  - `options`: Provider-specific options

  ## Returns

  - `{:ok, details}`: Detailed content information
  - `{:error, reason}`: Failed to get details
  """
  def get_details(provider_id, content_id, content_type, options \\ %{}) do
    GenServer.call(__MODULE__, {:get_details, provider_id, content_id, content_type, options}, 30_000)
  end

  @doc """
  Get cached details for specific content from a provider.

  This is the recommended method for getting details as it handles caching automatically.

  ## Parameters

  - `provider_id`: Provider ID (e.g., :tmdb)
  - `content_id`: Provider-specific content ID
  - `content_type`: Content type (:movie, :tv, etc.)
  - `options`: Provider-specific options

  ## Returns

  - `{:ok, details}`: Detailed content information
  - `{:error, reason}`: Failed to get details
  """
  def get_cached_details(provider_id, content_id, content_type, options \\ %{}) do
    GenServer.call(__MODULE__, {:get_cached_details, provider_id, content_id, content_type, options}, 30_000)
  end

  @doc """
  Validate all registered providers' configurations.

  ## Returns

  - `{:ok, results}`: List of validation results per provider
  - `{:error, reason}`: Validation failed
  """
  def validate_providers do
    GenServer.call(__MODULE__, :validate_providers)
  end

  @doc """
  Get provider health status.

  ## Returns

  - `{:ok, status}`: Provider health information
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @impl true
  def init(_opts) do
    # Initialize provider registry
    :ets.new(@registry_table, [:named_table, :public, :set])

    # Register default providers
    Enum.each(@default_providers, &register_provider_internal/1)

    Logger.info("RichDataManager started with #{length(@default_providers)} default providers")

    {:ok, %{
      providers: %{},
      last_health_check: DateTime.utc_now(),
      health_status: %{}
    }}
  end

  @impl true
  def handle_call({:register_provider, provider_module}, _from, state) do
    case register_provider_internal(provider_module) do
      :ok ->
        provider_id = provider_module.provider_id()
        new_providers = Map.put(state.providers, provider_id, provider_module)
        Logger.info("Registered rich data provider: #{provider_id}")
        {:reply, :ok, %{state | providers: new_providers}}

      {:error, reason} ->
        Logger.error("Failed to register provider #{provider_module}: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:unregister_provider, provider_id}, _from, state) do
    case :ets.delete(@registry_table, provider_id) do
      true ->
        new_providers = Map.delete(state.providers, provider_id)
        Logger.info("Unregistered rich data provider: #{provider_id}")
        {:reply, :ok, %{state | providers: new_providers}}

      false ->
        {:reply, {:error, "Provider not found"}, state}
    end
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    providers = :ets.tab2list(@registry_table)
    results = Enum.map(providers, fn {provider_id, provider_module} ->
      {provider_id, provider_module, get_provider_status(provider_module)}
    end)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:search, query, options}, _from, state) do
    providers = get_search_providers(options)
    timeout = Map.get(options, :timeout, 30_000)

    # Search across providers in parallel
    search_tasks = Enum.map(providers, fn {provider_id, provider_module} ->
      Task.async(fn ->
        case provider_module.search(query, options) do
          {:ok, results} ->
            {provider_id, {:ok, results}}
          {:error, reason} ->
            {provider_id, {:error, reason}}
        end
      end)
    end)

    # Collect results
    results = search_tasks
      |> Task.await_many(timeout)
      |> Enum.into(%{})

    {:reply, {:ok, results}, state}
  end

  @impl true
  def handle_call({:get_details, provider_id, content_id, content_type, options}, _from, state) do
    case get_provider(provider_id) do
      {:ok, provider_module} ->
        result = provider_module.get_details(content_id, content_type, options)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_cached_details, provider_id, content_id, content_type, options}, _from, state) do
    case get_provider(provider_id) do
      {:ok, provider_module} ->
        result = provider_module.get_cached_details(content_id, content_type, options)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:validate_providers, _from, state) do
    providers = :ets.tab2list(@registry_table)

    results = Enum.map(providers, fn {provider_id, provider_module} ->
      validation_result = provider_module.validate_config()
      {provider_id, validation_result}
    end)

    {:reply, {:ok, results}, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    providers = :ets.tab2list(@registry_table)

    health_status = Enum.into(providers, %{}, fn {provider_id, provider_module} ->
      status = get_provider_status(provider_module)
      {provider_id, status}
    end)

    overall_status = %{
      total_providers: length(providers),
      healthy_providers: Enum.count(health_status, fn {_, status} -> status == :healthy end),
      last_check: DateTime.utc_now(),
      details: health_status
    }

    {:reply, {:ok, overall_status}, %{state | health_status: health_status}}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp register_provider_internal(provider_module) do
    try do
      # Validate provider implements behaviour
      provider_id = provider_module.provider_id()
      provider_name = provider_module.provider_name()
      supported_types = provider_module.supported_types()

      # Store in registry
      :ets.insert(@registry_table, {provider_id, provider_module})

      Logger.debug("Registered provider: #{provider_name} (#{provider_id}) - supports #{inspect(supported_types)}")
      :ok
    rescue
      e ->
        {:error, "Provider registration failed: #{inspect(e)}"}
    end
  end

  defp get_provider(provider_id) do
    case :ets.lookup(@registry_table, provider_id) do
      [{^provider_id, provider_module}] ->
        {:ok, provider_module}
      [] ->
        {:error, "Provider not found: #{provider_id}"}
    end
  end

  defp get_search_providers(options) when is_map(options) do
    requested_providers = Map.get(options, :providers, :all)

    all_providers = :ets.tab2list(@registry_table)

    case requested_providers do
      :all ->
        all_providers
      provider_ids when is_list(provider_ids) ->
        Enum.filter(all_providers, fn {provider_id, _} -> provider_id in provider_ids end)
      _ ->
        all_providers
    end
  end

  defp get_search_providers(_options) do
    # Fallback for non-map options - return all providers
    :ets.tab2list(@registry_table)
  end

  defp get_provider_status(provider_module) do
    case provider_module.validate_config() do
      :ok -> :healthy
      {:error, _} -> :unhealthy
    end
  rescue
    _ -> :error
  end
end
