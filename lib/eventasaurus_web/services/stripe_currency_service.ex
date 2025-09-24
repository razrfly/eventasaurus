defmodule EventasaurusWeb.Services.StripeCurrencyService do
  @moduledoc """
  Service for fetching and caching supported currencies from the Stripe API.
  Uses GenServer for state management and ETS for caching.
  """

  use GenServer
  require Logger
  alias Stripe.CountrySpec

  @cache_table :stripe_currencies_cache
  @cache_key :supported_currencies
  # Cache for 24 hours
  @cache_ttl :timer.hours(24)

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Get the list of supported currencies from cache or Stripe API.
  Returns a list of currency codes as strings.
  """
  def get_currencies do
    case get_from_cache() do
      {:ok, currencies} ->
        currencies

      {:error, :not_found} ->
        refresh_currencies()

        case get_from_cache() do
          {:ok, currencies} -> currencies
          {:error, :not_found} -> fallback_currencies()
        end

      {:error, :expired} ->
        refresh_currencies()

        case get_from_cache() do
          {:ok, currencies} -> currencies
          _ -> fallback_currencies()
        end
    end
  end

  @doc """
  Get grouped currencies by region.
  Returns a map with regions as keys and currency lists as values.
  """
  def get_grouped_currencies do
    currencies = get_currencies()
    group_currencies_by_region(currencies)
  end

  @doc """
  Manually refresh currency data from Stripe API.
  """
  def refresh_currencies do
    GenServer.cast(__MODULE__, :refresh_currencies)
  end

  # Server callbacks

  @impl true
  def init(state) do
    # Initialize ETS table for caching
    :ets.new(@cache_table, [:named_table, :public, :set])

    # Fetch currencies on startup
    send(self(), :fetch_currencies)

    {:ok, state}
  end

  @impl true
  def handle_info(:fetch_currencies, state) do
    case fetch_currencies_from_stripe() do
      {:ok, currencies} ->
        cache_currencies(currencies)
        Logger.info("StripeCurrencyService: Successfully cached #{length(currencies)} currencies")

      {:error, reason} ->
        Logger.warning("StripeCurrencyService: Failed to fetch currencies: #{inspect(reason)}")
        # Cache fallback currencies if API fails
        cache_currencies(fallback_currencies())
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:refresh_currencies, state) do
    send(self(), :fetch_currencies)
    {:noreply, state}
  end

  # Private functions

  # Fetches all country specs with pagination support
  defp fetch_all_country_specs(acc \\ [], starting_after \\ nil) do
    params = %{limit: 100}
    params = if starting_after, do: Map.put(params, :starting_after, starting_after), else: params

    case CountrySpec.list(params) do
      {:ok, %{data: specs, has_more: has_more}} ->
        all_specs = acc ++ specs

        if has_more do
          # Defensive check: ensure specs is not empty before accessing last element
          case specs do
            [] ->
              # If specs is empty but has_more is true, this is an API inconsistency
              # Return what we have so far to avoid infinite recursion
              {:ok, %{data: all_specs}}

            _ ->
              last_id = List.last(specs).id
              fetch_all_country_specs(all_specs, last_id)
          end
        else
          {:ok, %{data: all_specs}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp fetch_currencies_from_stripe do
    # Check if Stripe API key is configured - check environment variable directly
    # to avoid timing issues with Application config loading
    api_key =
      System.get_env("STRIPE_SECRET_KEY") || Application.get_env(:stripity_stripe, :api_key)

    if is_nil(api_key) or api_key == "" or api_key == "sk_test_YOUR_TEST_KEY_HERE" do
      Logger.info(
        "StripeCurrencyService: Stripe API key not configured, using fallback currencies"
      )

      {:error, :no_api_key}
    else
      # Ensure Stripe is configured with the API key before making calls
      Application.put_env(:stripity_stripe, :api_key, api_key)

      try do
        # Fetch all country specs and extract unique currencies with pagination
        case fetch_all_country_specs() do
          {:ok, %{data: country_specs}} ->
            currencies =
              country_specs
              |> Enum.flat_map(fn spec -> spec.supported_payment_currencies || [] end)
              |> Enum.uniq()
              |> Enum.sort()
              |> Enum.map(&String.upcase/1)

            {:ok, currencies}

          {:error, reason} ->
            Logger.error("StripeCurrencyService: Stripe API error: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        exception ->
          Logger.error(
            "StripeCurrencyService: Exception fetching currencies: #{inspect(exception)}"
          )

          {:error, exception}
      end
    end
  end

  defp cache_currencies(currencies) do
    expiry = :os.system_time(:millisecond) + @cache_ttl
    :ets.insert(@cache_table, {@cache_key, currencies, expiry})
  end

  defp get_from_cache do
    case :ets.lookup(@cache_table, @cache_key) do
      [{@cache_key, currencies, expiry}] ->
        if :os.system_time(:millisecond) < expiry do
          {:ok, currencies}
        else
          :ets.delete(@cache_table, @cache_key)
          {:error, :expired}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp fallback_currencies do
    # Comprehensive list of currencies commonly supported by Stripe
    # This serves as a fallback when the API is unavailable
    [
      "AED",
      "AFN",
      "ALL",
      "AMD",
      "ANG",
      "AOA",
      "ARS",
      "AUD",
      "AWG",
      "AZN",
      "BAM",
      "BBD",
      "BDT",
      "BGN",
      "BHD",
      "BIF",
      "BMD",
      "BND",
      "BOB",
      "BRL",
      "BSD",
      "BWP",
      "BYN",
      "BZD",
      "CAD",
      "CDF",
      "CHF",
      "CLP",
      "CNY",
      "COP",
      "CRC",
      "CUC",
      "CUP",
      "CVE",
      "CZK",
      "DJF",
      "DKK",
      "DOP",
      "DZD",
      "EGP",
      "ERN",
      "ETB",
      "EUR",
      "FJD",
      "FKP",
      "GBP",
      "GEL",
      "GHS",
      "GIP",
      "GMD",
      "GNF",
      "GTQ",
      "GYD",
      "HKD",
      "HNL",
      "HRK",
      "HTG",
      "HUF",
      "IDR",
      "ILS",
      "INR",
      "IQD",
      "IRR",
      "ISK",
      "JMD",
      "JOD",
      "JPY",
      "KES",
      "KGS",
      "KHR",
      "KMF",
      "KPW",
      "KRW",
      "KWD",
      "KYD",
      "KZT",
      "LAK",
      "LBP",
      "LKR",
      "LRD",
      "LSL",
      "LYD",
      "MAD",
      "MDL",
      "MGA",
      "MKD",
      "MMK",
      "MNT",
      "MOP",
      "MRU",
      "MUR",
      "MVR",
      "MWK",
      "MXN",
      "MYR",
      "MZN",
      "NAD",
      "NGN",
      "NIO",
      "NOK",
      "NPR",
      "NZD",
      "OMR",
      "PAB",
      "PEN",
      "PGK",
      "PHP",
      "PKR",
      "PLN",
      "PYG",
      "QAR",
      "RON",
      "RSD",
      "RUB",
      "RWF",
      "SAR",
      "SBD",
      "SCR",
      "SDG",
      "SEK",
      "SGD",
      "SHP",
      "SLE",
      "SLL",
      "SOS",
      "SRD",
      "SSP",
      "STN",
      "SYP",
      "SZL",
      "THB",
      "TJS",
      "TMT",
      "TND",
      "TOP",
      "TRY",
      "TTD",
      "TVD",
      "TWD",
      "TZS",
      "UAH",
      "UGX",
      "USD",
      "UYU",
      "UZS",
      "VED",
      "VES",
      "VND",
      "VUV",
      "WST",
      "XAF",
      "XCD",
      "XDR",
      "XOF",
      "XPF",
      "YER",
      "ZAR",
      "ZMW",
      "ZWL"
    ]
  end

  defp group_currencies_by_region(currencies) do
    currencies
    |> Enum.group_by(&get_currency_region/1)
    |> Enum.sort_by(fn {region, _} -> region end)
  end

  defp get_currency_region(currency) do
    case currency do
      # North America
      code
      when code in [
             "USD",
             "CAD",
             "MXN",
             "GTQ",
             "BZD",
             "CRC",
             "HNL",
             "NIO",
             "PAB",
             "CUC",
             "CUP",
             "DOP",
             "HTG",
             "JMD",
             "XCD",
             "BBD",
             "BMD",
             "KYD",
             "TTD"
           ] ->
        "North America"

      # Europe
      code
      when code in [
             "EUR",
             "GBP",
             "CHF",
             "NOK",
             "SEK",
             "DKK",
             "ISK",
             "PLN",
             "CZK",
             "HUF",
             "RON",
             "BGN",
             "HRK",
             "RSD",
             "BAM",
             "MKD",
             "ALL",
             "MDL",
             "UAH",
             "BYN",
             "RUB",
             "TRY",
             "GEL",
             "AMD",
             "AZN"
           ] ->
        "Europe"

      # Asia Pacific
      code
      when code in [
             "JPY",
             "CNY",
             "HKD",
             "SGD",
             "AUD",
             "NZD",
             "KRW",
             "TWD",
             "PHP",
             "THB",
             "MYR",
             "IDR",
             "VND",
             "INR",
             "PKR",
             "LKR",
             "NPR",
             "BDT",
             "MMK",
             "KHR",
             "LAK",
             "MNT",
             "KZT",
             "KGS",
             "UZS",
             "TJS",
             "TMT",
             "AFN",
             "IRR",
             "IQD",
             "BHD",
             "KWD",
             "OMR",
             "QAR",
             "SAR",
             "AED",
             "YER",
             "JOD",
             "LBP",
             "SYP",
             "ILS",
             "FJD",
             "PGK",
             "SBD",
             "TOP",
             "VUV",
             "WST",
             "TVD"
           ] ->
        "Asia Pacific"

      # Africa
      code
      when code in [
             "ZAR",
             "EGP",
             "NGN",
             "GHS",
             "KES",
             "UGX",
             "TZS",
             "RWF",
             "ETB",
             "ZMW",
             "MWK",
             "MZN",
             "BWP",
             "SZL",
             "LSL",
             "NAD",
             "AOA",
             "CDF",
             "XAF",
             "XOF",
             "CFA",
             "GMD",
             "SLL",
             "LRD",
             "GNF",
             "BIF",
             "DJF",
             "ERN",
             "SOS",
             "SDG",
             "SSP",
             "MAD",
             "DZD",
             "TND",
             "LYD",
             "MGA",
             "KMF",
             "MUR",
             "SCR",
             "MVR",
             "CVE",
             "STN",
             "SLE"
           ] ->
        "Africa"

      # South America
      code
      when code in [
             "BRL",
             "ARS",
             "CLP",
             "PEN",
             "COP",
             "VES",
             "VED",
             "UYU",
             "PYG",
             "BOB",
             "SRD",
             "GYD",
             "FKP"
           ] ->
        "South America"

      # Other/Unknown
      _ ->
        "Other"
    end
  end
end
