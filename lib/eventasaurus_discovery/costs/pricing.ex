defmodule EventasaurusDiscovery.Costs.Pricing do
  @moduledoc """
  Unified pricing configuration for all external services.

  Centralizes pricing for:
  - Web scraping (Crawlbase, Zyte)
  - Geocoding (via delegation to existing Geocoding.Pricing)
  - ML inference (Hugging Face, planned)
  - LLM providers (Anthropic, OpenAI, planned)

  ## Pricing Sources
  - Crawlbase: https://crawlbase.com/pricing
  - Zyte: https://www.zyte.com/pricing/ (usage-based, estimates used)
  - Google Maps Platform: https://developers.google.com/maps/billing-and-pricing/pricing
  - Hugging Face: https://huggingface.co/pricing (planned)

  ## Usage

      alias EventasaurusDiscovery.Costs.Pricing

      # Get cost for a Crawlbase request
      cost = Pricing.crawlbase_cost(:javascript)  # 2 credits = $0.002

      # Get cost for a Zyte request
      cost = Pricing.zyte_cost(:browser_html)  # $0.001

      # Calculate total cost
      cost = Pricing.calculate_cost("crawlbase", "javascript", 10)

  ## Pricing Verification
  Last verified: 2025-01-28

  **IMPORTANT**: Verify pricing periodically as providers may change rates.
  """

  # Delegate geocoding pricing to existing module
  alias EventasaurusDiscovery.Geocoding.Pricing, as: GeocodingPricing

  # ============================================================================
  # Crawlbase Pricing
  # ============================================================================
  # Crawlbase uses a credit system
  # Normal requests: 1 credit
  # JavaScript requests: 2 credits
  # Current rate: ~$0.001 per credit (varies by plan)
  # Source: https://crawlbase.com/pricing

  @crawlbase_credit_cost 0.001
  @crawlbase_normal_credits 1
  @crawlbase_javascript_credits 2

  # ============================================================================
  # Zyte Pricing
  # ============================================================================
  # Zyte uses usage-based pricing that varies by feature
  # Browser HTML rendering costs more than simple HTTP
  # These are estimates based on typical usage patterns
  # Source: https://www.zyte.com/pricing/

  @zyte_browser_html_cost 0.001
  @zyte_http_response_cost 0.0003

  # ============================================================================
  # Hugging Face Pricing (Planned)
  # ============================================================================
  # Token-based pricing for inference API
  # Rates vary by model size and type
  # Source: https://huggingface.co/pricing

  @huggingface_input_token_cost 0.0000001  # Per input token (placeholder)
  @huggingface_output_token_cost 0.0000002  # Per output token (placeholder)

  # Pricing verification metadata
  @pricing_verified_at ~D[2025-01-28]

  # ============================================================================
  # Crawlbase Functions
  # ============================================================================

  @doc """
  Returns the cost per request for Crawlbase based on mode.

  ## Parameters
  - `mode` - `:normal` or `:javascript`

  ## Examples

      iex> Pricing.crawlbase_cost(:normal)
      0.001

      iex> Pricing.crawlbase_cost(:javascript)
      0.002
  """
  def crawlbase_cost(:normal), do: @crawlbase_credit_cost * @crawlbase_normal_credits
  def crawlbase_cost(:javascript), do: @crawlbase_credit_cost * @crawlbase_javascript_credits
  def crawlbase_cost(_), do: crawlbase_cost(:javascript)

  @doc """
  Returns the number of credits used for a Crawlbase request.

  ## Examples

      iex> Pricing.crawlbase_credits(:normal)
      1

      iex> Pricing.crawlbase_credits(:javascript)
      2
  """
  def crawlbase_credits(:normal), do: @crawlbase_normal_credits
  def crawlbase_credits(:javascript), do: @crawlbase_javascript_credits
  def crawlbase_credits(_), do: @crawlbase_javascript_credits

  @doc """
  Returns the cost per credit for Crawlbase.

  ## Examples

      iex> Pricing.crawlbase_credit_cost()
      0.001
  """
  def crawlbase_credit_cost, do: @crawlbase_credit_cost

  # ============================================================================
  # Zyte Functions
  # ============================================================================

  @doc """
  Returns the cost per request for Zyte based on mode.

  ## Parameters
  - `mode` - `:browser_html` or `:http_response_body`

  ## Examples

      iex> Pricing.zyte_cost(:browser_html)
      0.001

      iex> Pricing.zyte_cost(:http_response_body)
      0.0003
  """
  def zyte_cost(:browser_html), do: @zyte_browser_html_cost
  def zyte_cost(:http_response_body), do: @zyte_http_response_cost
  def zyte_cost(_), do: zyte_cost(:browser_html)

  # ============================================================================
  # Hugging Face Functions (Planned)
  # ============================================================================

  @doc """
  Returns the cost for Hugging Face inference based on token counts.

  ## Parameters
  - `input_tokens` - Number of input tokens
  - `output_tokens` - Number of output tokens

  ## Examples

      iex> Pricing.huggingface_cost(1000, 500)
      0.0002
  """
  def huggingface_cost(input_tokens, output_tokens) do
    input_tokens * @huggingface_input_token_cost +
      output_tokens * @huggingface_output_token_cost
  end

  @doc """
  Returns the cost per input token for Hugging Face.
  """
  def huggingface_input_token_cost, do: @huggingface_input_token_cost

  @doc """
  Returns the cost per output token for Hugging Face.
  """
  def huggingface_output_token_cost, do: @huggingface_output_token_cost

  # ============================================================================
  # Geocoding Delegation
  # ============================================================================

  @doc """
  Delegates to existing geocoding pricing module.
  See `EventasaurusDiscovery.Geocoding.Pricing` for details.
  """
  defdelegate google_maps_cost(), to: GeocodingPricing
  defdelegate google_places_text_search_cost(), to: GeocodingPricing
  defdelegate google_places_details_cost(), to: GeocodingPricing
  defdelegate google_places_cost(), to: GeocodingPricing
  defdelegate openstreetmap_cost(), to: GeocodingPricing
  defdelegate city_resolver_cost(), to: GeocodingPricing

  # ============================================================================
  # Unified Cost Calculation
  # ============================================================================

  @doc """
  Calculate cost for any provider and operation.

  ## Parameters
  - `provider` - Provider name (e.g., "crawlbase", "zyte", "google_places")
  - `operation` - Operation type (e.g., "javascript", "browser_html", "text_search")
  - `units` - Number of units (requests, tokens, etc.)

  ## Examples

      iex> Pricing.calculate_cost("crawlbase", "javascript", 10)
      0.02

      iex> Pricing.calculate_cost("zyte", "browser_html", 5)
      0.005

      iex> Pricing.calculate_cost("google_places", "text_search", 100)
      3.2
  """
  def calculate_cost(provider, operation, units \\ 1)

  # Crawlbase
  def calculate_cost("crawlbase", "javascript", units), do: crawlbase_cost(:javascript) * units
  def calculate_cost("crawlbase", "normal", units), do: crawlbase_cost(:normal) * units
  def calculate_cost("crawlbase", _, units), do: crawlbase_cost(:javascript) * units

  # Zyte
  def calculate_cost("zyte", "browser_html", units), do: zyte_cost(:browser_html) * units
  def calculate_cost("zyte", "http_response_body", units), do: zyte_cost(:http_response_body) * units
  def calculate_cost("zyte", _, units), do: zyte_cost(:browser_html) * units

  # Google Places
  def calculate_cost("google_places", "text_search", units), do: GeocodingPricing.google_places_text_search_cost() * units
  def calculate_cost("google_places", "details", units), do: GeocodingPricing.google_places_details_cost() * units
  def calculate_cost("google_places", "combined", units), do: GeocodingPricing.google_places_cost() * units
  def calculate_cost("google_places", _, units), do: GeocodingPricing.google_places_cost() * units

  # Google Maps
  def calculate_cost("google_maps", _, units), do: GeocodingPricing.google_maps_cost() * units

  # OpenStreetMap (free)
  def calculate_cost("openstreetmap", _, _units), do: 0.0

  # Unknown provider - return 0 but log warning
  def calculate_cost(provider, operation, _units) do
    require Logger
    Logger.warning("Unknown provider/operation for pricing: #{provider}/#{operation}")
    0.0
  end

  # ============================================================================
  # Reporting Functions
  # ============================================================================

  @doc """
  Returns when pricing was last verified.
  """
  def pricing_verified_at, do: @pricing_verified_at

  @doc """
  Returns all pricing information as a map for reporting.

  ## Examples

      iex> Pricing.all()
      %{
        crawlbase: %{normal: 0.001, javascript: 0.002},
        zyte: %{browser_html: 0.001, http_response_body: 0.0003},
        geocoding: %{...},
        verified_at: ~D[2025-01-28]
      }
  """
  def all do
    %{
      crawlbase: %{
        normal: crawlbase_cost(:normal),
        javascript: crawlbase_cost(:javascript),
        credit_cost: @crawlbase_credit_cost
      },
      zyte: %{
        browser_html: zyte_cost(:browser_html),
        http_response_body: zyte_cost(:http_response_body)
      },
      huggingface: %{
        input_token: @huggingface_input_token_cost,
        output_token: @huggingface_output_token_cost
      },
      geocoding: GeocodingPricing.all(),
      verified_at: @pricing_verified_at
    }
  end

  @doc """
  Returns a formatted pricing report for display.
  """
  def report do
    """
    External Service Pricing (Verified: #{@pricing_verified_at})

    == Web Scraping ==
    Crawlbase Normal: $#{crawlbase_cost(:normal)} per request (#{@crawlbase_normal_credits} credit)
    Crawlbase JavaScript: $#{crawlbase_cost(:javascript)} per request (#{@crawlbase_javascript_credits} credits)
    Zyte Browser HTML: $#{zyte_cost(:browser_html)} per request
    Zyte HTTP Response: $#{zyte_cost(:http_response_body)} per request

    == Geocoding ==
    #{GeocodingPricing.report()}

    == ML Inference (Planned) ==
    Hugging Face Input: $#{@huggingface_input_token_cost} per token
    Hugging Face Output: $#{@huggingface_output_token_cost} per token
    """
  end
end
