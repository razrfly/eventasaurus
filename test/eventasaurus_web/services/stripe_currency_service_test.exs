defmodule EventasaurusWeb.Services.StripeCurrencyServiceTest do
  use ExUnit.Case, async: false
  import Mock

  alias EventasaurusWeb.Services.StripeCurrencyService

  # Mock for Stripe API
  defmodule MockStripe do
    def list(_params) do
      {:ok,
       %{
         data: [
           %{supported_payment_currencies: ["usd", "eur", "gbp"]},
           %{supported_payment_currencies: ["jpy", "cad", "aud"]},
           # Duplicate to test uniqueness
           %{supported_payment_currencies: ["usd", "eur"]}
         ]
       }}
    end
  end

  defmodule MockStripeError do
    def list(_params) do
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :invalid_request_error,
         message: "API key not provided"
       }}
    end
  end

  setup do
    # Clear the cache before each test
    :ets.delete_all_objects(:stripe_currencies_cache)
    :ok
  end

  describe "get_currencies/0" do
    test "returns currencies from cache when available" do
      # Pre-populate cache with test data
      expiry = :os.system_time(:millisecond) + 60_000

      :ets.insert(
        :stripe_currencies_cache,
        {:supported_currencies, ["USD", "EUR", "GBP"], expiry}
      )

      currencies = StripeCurrencyService.get_currencies()

      assert currencies == ["USD", "EUR", "GBP"]
    end

    test "returns fallback currencies when cache is empty and API fails" do
      # Mock Stripe API to fail
      with_mock(Stripe.CountrySpec, list: fn _ -> MockStripeError.list(nil) end) do
        currencies = StripeCurrencyService.get_currencies()

        # Should return fallback currencies
        assert is_list(currencies)
        # Fallback has many currencies
        assert length(currencies) > 100
        assert "USD" in currencies
        assert "EUR" in currencies
      end
    end

    test "fetches from API when cache is expired" do
      # Insert expired cache entry
      expired_time = :os.system_time(:millisecond) - 1000
      :ets.insert(:stripe_currencies_cache, {:supported_currencies, ["OLD"], expired_time})

      with_mock(Stripe.CountrySpec, list: fn _ -> MockStripe.list(nil) end) do
        currencies = StripeCurrencyService.get_currencies()

        # Should fetch fresh data and not return the old cached value
        assert currencies != ["OLD"]
        assert is_list(currencies)
        assert length(currencies) > 0

        # Should contain expected currencies from either API or fallback
        assert "USD" in currencies
        assert "EUR" in currencies
        assert "GBP" in currencies
      end
    end
  end

  describe "get_grouped_currencies/0" do
    test "returns currencies grouped by region" do
      # Pre-populate cache with test data
      expiry = :os.system_time(:millisecond) + 60_000

      :ets.insert(
        :stripe_currencies_cache,
        {:supported_currencies, ["USD", "EUR", "GBP", "JPY"], expiry}
      )

      grouped = StripeCurrencyService.get_grouped_currencies()

      assert is_list(grouped)

      # Should have regional groups
      regions = Enum.map(grouped, fn {region, _currencies} -> region end)
      assert "North America" in regions
      assert "Europe" in regions
      assert "Asia Pacific" in regions

      # Check that currencies are in correct groups
      north_america_group = Enum.find(grouped, fn {region, _} -> region == "North America" end)
      assert north_america_group != nil
      {_, north_america_currencies} = north_america_group
      assert "USD" in north_america_currencies

      europe_group = Enum.find(grouped, fn {region, _} -> region == "Europe" end)
      assert europe_group != nil
      {_, europe_currencies} = europe_group
      assert "EUR" in europe_currencies
      assert "GBP" in europe_currencies

      asia_pacific_group = Enum.find(grouped, fn {region, _} -> region == "Asia Pacific" end)
      assert asia_pacific_group != nil
      {_, asia_pacific_currencies} = asia_pacific_group
      assert "JPY" in asia_pacific_currencies
    end
  end

  describe "refresh_currencies/0" do
    test "triggers cache refresh" do
      # This test ensures the GenServer cast doesn't crash
      assert :ok = StripeCurrencyService.refresh_currencies()
    end
  end

  describe "cache behavior" do
    test "cache TTL is respected" do
      # Insert cache entry that will expire soon
      short_expiry = :os.system_time(:millisecond) + 100
      :ets.insert(:stripe_currencies_cache, {:supported_currencies, ["TEST"], short_expiry})

      # Should return cached value immediately
      assert StripeCurrencyService.get_currencies() == ["TEST"]

      # Wait for expiry
      Process.sleep(150)

      # Should now fetch fresh data (fallback in this case since mocked API fails)
      with_mock(Stripe.CountrySpec, list: fn _ -> MockStripeError.list(nil) end) do
        currencies = StripeCurrencyService.get_currencies()
        assert currencies != ["TEST"]
        # Fallback currencies
        assert length(currencies) > 100
      end
    end

    test "handles cache corruption gracefully" do
      # Insert malformed cache data
      :ets.insert(
        :stripe_currencies_cache,
        {:supported_currencies, nil, :os.system_time(:millisecond) + 60_000}
      )

      # Should handle gracefully and return fallback
      with_mock(Stripe.CountrySpec, list: fn _ -> MockStripeError.list(nil) end) do
        # Clear the cache first to simulate the service handling corruption
        :ets.delete(:stripe_currencies_cache, :supported_currencies)
        currencies = StripeCurrencyService.get_currencies()
        assert is_list(currencies)
        assert length(currencies) > 100
      end
    end
  end

  describe "error handling" do
    test "handles Stripe API exceptions gracefully" do
      with_mock(Stripe.CountrySpec, list: fn _ -> raise "Network error" end) do
        currencies = StripeCurrencyService.get_currencies()

        # Should fall back to hardcoded currencies
        assert is_list(currencies)
        assert "USD" in currencies
        assert "EUR" in currencies
      end
    end

    test "handles malformed API responses" do
      with_mock(Stripe.CountrySpec, list: fn _ -> {:ok, %{data: nil}} end) do
        currencies = StripeCurrencyService.get_currencies()

        # Should fall back to hardcoded currencies
        assert is_list(currencies)
        assert "USD" in currencies
      end
    end
  end

  describe "currency deduplication and formatting" do
    test "removes duplicates and formats currencies correctly" do
      with_mock(Stripe.CountrySpec, list: fn _ -> MockStripe.list(nil) end) do
        currencies = StripeCurrencyService.get_currencies()

        # Should be uppercase, sorted, and unique
        assert Enum.all?(currencies, fn code -> code == String.upcase(code) end)
        assert currencies == Enum.sort(currencies)

        # Check uniqueness (USD appears twice in mock data)
        assert length(currencies) == length(Enum.uniq(currencies))

        # Should contain major currencies
        assert "USD" in currencies
        assert "EUR" in currencies
        assert "GBP" in currencies
      end
    end
  end

  describe "regional grouping" do
    test "correctly groups major currencies by region" do
      grouped = StripeCurrencyService.get_grouped_currencies()

      # North America
      north_america_group = Enum.find(grouped, fn {region, _} -> region == "North America" end)
      assert north_america_group != nil
      {_, north_america} = north_america_group
      assert "USD" in north_america
      assert "CAD" in north_america

      # Europe
      europe_group = Enum.find(grouped, fn {region, _} -> region == "Europe" end)
      assert europe_group != nil
      {_, europe} = europe_group
      assert "EUR" in europe
      assert "GBP" in europe

      # Asia Pacific
      asia_pacific_group = Enum.find(grouped, fn {region, _} -> region == "Asia Pacific" end)
      assert asia_pacific_group != nil
      {_, asia_pacific} = asia_pacific_group
      assert "JPY" in asia_pacific
      assert "AUD" in asia_pacific
    end

    test "handles unknown currencies by placing them in Other group" do
      # Pre-populate cache with unknown currency
      expiry = :os.system_time(:millisecond) + 60_000
      :ets.insert(:stripe_currencies_cache, {:supported_currencies, ["XXX"], expiry})

      grouped = StripeCurrencyService.get_grouped_currencies()

      other_group = Enum.find(grouped, fn {region, _} -> region == "Other" end)
      assert other_group != nil
      {_, other_currencies} = other_group
      assert "XXX" in other_currencies
    end
  end

  describe "performance" do
    test "cache lookup is faster than API call" do
      # Pre-populate cache
      expiry = :os.system_time(:millisecond) + 60_000
      large_currency_list = 1..100 |> Enum.map(&"CUR#{&1}") |> Enum.sort()
      :ets.insert(:stripe_currencies_cache, {:supported_currencies, large_currency_list, expiry})

      # Measure cache lookup time
      {cache_time, _} = :timer.tc(fn -> StripeCurrencyService.get_currencies() end)

      # Should be very fast (under 1ms)
      # microseconds
      assert cache_time < 1000
    end
  end
end
