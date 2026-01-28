defmodule EventasaurusDiscovery.Costs.CostTracker do
  @moduledoc """
  Behaviour for consistent cost tracking across all external services.

  This module provides a unified interface for recording costs from any external
  service provider (scraping, geocoding, ML inference, etc.). Implementing modules
  can use the provided helper functions or implement custom tracking logic.

  ## Usage

  ### Using the Default Implementation

  Most services can use the provided `track/1` function directly:

      alias EventasaurusDiscovery.Costs.CostTracker

      # Track a scraping request
      CostTracker.track(%{
        service_type: :scraping,
        provider: :crawlbase,
        operation: :javascript,
        units: 2,
        metadata: %{url: "https://example.com", duration_ms: 1250}
      })

      # Track a geocoding request
      CostTracker.track(%{
        service_type: :geocoding,
        provider: :google_places,
        operation: :text_search,
        reference_type: :venue,
        reference_id: 123,
        metadata: %{query: "Coffee shop near me"}
      })

  ### Implementing the Behaviour

  For services that need custom tracking logic:

      defmodule MyApp.Services.CustomProvider do
        @behaviour EventasaurusDiscovery.Costs.CostTracker

        @impl true
        def track_cost(attrs) do
          # Custom logic here
          EventasaurusDiscovery.Costs.ExternalServiceCost.record_async(attrs)
        end

        @impl true
        def calculate_cost(operation, units) do
          # Custom pricing logic
          base_rate = 0.001
          base_rate * units
        end
      end

  ## Service Types

  - `:scraping` - Web scraping services (Crawlbase, Zyte)
  - `:geocoding` - Address/location resolution (Google Places, Google Maps)
  - `:ml_inference` - Machine learning inference (Hugging Face, planned)
  - `:llm` - Large language model APIs (Anthropic, OpenAI, planned)

  ## Providers

  ### Scraping
  - `:crawlbase` - Credit-based pricing (1-2 credits per request)
  - `:zyte` - Usage-based pricing (varies by render type)

  ### Geocoding
  - `:google_places` - Per-request ($0.032 text search, $0.005 details)
  - `:google_maps` - Per-request ($0.005)
  - `:openstreetmap` - Free

  ### ML (Planned)
  - `:huggingface` - Token-based pricing
  - `:anthropic` - Token-based pricing
  - `:openai` - Token-based pricing
  """

  alias EventasaurusDiscovery.Costs.{ExternalServiceCost, Pricing}

  @type service_type :: :scraping | :geocoding | :ml_inference | :llm
  @type provider :: atom()
  @type operation :: atom()

  @type track_attrs :: %{
          required(:service_type) => service_type(),
          required(:provider) => provider(),
          optional(:operation) => operation(),
          optional(:units) => pos_integer(),
          optional(:reference_type) => atom() | String.t(),
          optional(:reference_id) => integer(),
          optional(:metadata) => map()
        }

  @doc """
  Track the cost of an external service call.

  Returns `:ok` immediately (async recording).
  """
  @callback track_cost(attrs :: track_attrs()) :: :ok

  @doc """
  Calculate the cost for a given operation and unit count.

  Returns the cost in USD as a float.
  """
  @callback calculate_cost(operation :: operation(), units :: pos_integer()) :: float()

  # ============================================================================
  # Default Implementation
  # ============================================================================

  @doc """
  Track a cost using the unified tracking system.

  This is the primary entry point for recording costs. It handles:
  - Looking up pricing based on provider and operation
  - Determining the appropriate unit type
  - Recording the cost asynchronously

  ## Parameters

  - `attrs` - Map with cost tracking attributes:
    - `:service_type` (required) - One of: `:scraping`, `:geocoding`, `:ml_inference`, `:llm`
    - `:provider` (required) - Provider identifier (e.g., `:crawlbase`, `:google_places`)
    - `:operation` (optional) - Operation type (e.g., `:javascript`, `:text_search`)
    - `:units` (optional, default: 1) - Number of units consumed
    - `:reference_type` (optional) - Entity type this cost relates to
    - `:reference_id` (optional) - Entity ID this cost relates to
    - `:metadata` (optional) - Additional context (duration, URL, etc.)

  ## Returns

  - `:ok` - Always returns immediately (async recording)

  ## Examples

      # Track Crawlbase JavaScript request
      CostTracker.track(%{
        service_type: :scraping,
        provider: :crawlbase,
        operation: :javascript,
        metadata: %{url: "https://example.com", duration_ms: 1500}
      })

      # Track Google Places text search
      CostTracker.track(%{
        service_type: :geocoding,
        provider: :google_places,
        operation: :text_search,
        reference_type: :venue,
        reference_id: 456,
        metadata: %{query: "Starbucks downtown"}
      })
  """
  @spec track(track_attrs()) :: :ok
  def track(attrs) do
    service_type = Map.fetch!(attrs, :service_type)
    provider = Map.fetch!(attrs, :provider)
    operation = Map.get(attrs, :operation)
    units = Map.get(attrs, :units, 1)
    reference_type = Map.get(attrs, :reference_type)
    reference_id = Map.get(attrs, :reference_id)
    metadata = Map.get(attrs, :metadata, %{})

    # Calculate cost based on provider and operation
    {cost, unit_type} = calculate_cost_and_unit_type(provider, operation, units)

    ExternalServiceCost.record_async(%{
      service_type: to_string(service_type),
      provider: to_string(provider),
      operation: operation && to_string(operation),
      cost_usd: Decimal.from_float(cost),
      units: units,
      unit_type: unit_type,
      reference_type: reference_type && to_string(reference_type),
      reference_id: reference_id,
      metadata: metadata
    })
  end

  @doc """
  Track a cost with an explicit cost value (bypasses pricing lookup).

  Use this when you already know the exact cost, or for providers
  not yet in the pricing module.

  ## Parameters

  - `attrs` - Map with cost tracking attributes (same as `track/1`)
  - `cost_usd` - The cost in USD as a float or Decimal

  ## Examples

      CostTracker.track_with_cost(
        %{service_type: :ml_inference, provider: :custom_provider, operation: :embed},
        0.0025
      )
  """
  @spec track_with_cost(track_attrs(), float() | Decimal.t()) :: :ok
  def track_with_cost(attrs, cost_usd) do
    service_type = Map.fetch!(attrs, :service_type)
    provider = Map.fetch!(attrs, :provider)
    operation = Map.get(attrs, :operation)
    units = Map.get(attrs, :units, 1)
    reference_type = Map.get(attrs, :reference_type)
    reference_id = Map.get(attrs, :reference_id)
    metadata = Map.get(attrs, :metadata, %{})

    unit_type = infer_unit_type(service_type, provider)

    cost_decimal =
      case cost_usd do
        %Decimal{} = d -> d
        f when is_float(f) -> Decimal.from_float(f)
        i when is_integer(i) -> Decimal.new(i)
      end

    ExternalServiceCost.record_async(%{
      service_type: to_string(service_type),
      provider: to_string(provider),
      operation: operation && to_string(operation),
      cost_usd: cost_decimal,
      units: units,
      unit_type: unit_type,
      reference_type: reference_type && to_string(reference_type),
      reference_id: reference_id,
      metadata: metadata
    })
  end

  # ============================================================================
  # Cost Calculation Helpers
  # ============================================================================

  @doc """
  Calculate the cost for a provider/operation combination.

  ## Examples

      iex> CostTracker.calculate_cost(:crawlbase, :javascript, 1)
      0.002

      iex> CostTracker.calculate_cost(:zyte, :browser_html, 5)
      0.005
  """
  @spec calculate_cost(provider(), operation() | nil, pos_integer()) :: float()
  def calculate_cost(provider, operation, units \\ 1)

  # Crawlbase pricing
  def calculate_cost(:crawlbase, :javascript, units), do: Pricing.crawlbase_cost(:javascript) * units
  def calculate_cost(:crawlbase, :normal, units), do: Pricing.crawlbase_cost(:normal) * units
  def calculate_cost(:crawlbase, _, units), do: Pricing.crawlbase_cost(:javascript) * units

  # Zyte pricing
  def calculate_cost(:zyte, :browser_html, units), do: Pricing.zyte_cost(:browser_html) * units

  def calculate_cost(:zyte, :http_response_body, units),
    do: Pricing.zyte_cost(:http_response_body) * units

  def calculate_cost(:zyte, _, units), do: Pricing.zyte_cost(:browser_html) * units

  # Geocoding pricing
  def calculate_cost(:google_places, :text_search, units),
    do: Pricing.google_places_text_search_cost() * units

  def calculate_cost(:google_places, :details, units),
    do: Pricing.google_places_details_cost() * units

  def calculate_cost(:google_places, :combined, units), do: Pricing.google_places_cost() * units
  def calculate_cost(:google_places, _, units), do: Pricing.google_places_cost() * units
  def calculate_cost(:google_maps, _, units), do: Pricing.google_maps_cost() * units

  # Free providers
  def calculate_cost(:openstreetmap, _, _units), do: 0.0
  def calculate_cost(:city_resolver, _, _units), do: 0.0

  # Unknown provider - return 0 and log warning
  def calculate_cost(provider, operation, _units) do
    require Logger

    Logger.warning(
      "CostTracker: Unknown provider/operation for cost calculation: #{provider}/#{operation}"
    )

    0.0
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp calculate_cost_and_unit_type(provider, operation, units) do
    cost = calculate_cost(provider, operation, units)
    unit_type = infer_unit_type_from_provider(provider)
    {cost, unit_type}
  end

  defp infer_unit_type_from_provider(provider) do
    case provider do
      :crawlbase -> "credit"
      :zyte -> "request"
      :google_places -> "request"
      :google_maps -> "request"
      :openstreetmap -> "request"
      :huggingface -> "request"
      :anthropic -> "request"
      :openai -> "request"
      _ -> "request"
    end
  end

  defp infer_unit_type(service_type, provider) do
    case {service_type, provider} do
      {:scraping, :crawlbase} -> "credit"
      {:ml_inference, _} -> "request"
      {:llm, _} -> "request"
      _ -> "request"
    end
  end
end
