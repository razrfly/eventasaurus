defmodule EventasaurusWeb.Helpers.CurrencyHelpersTest do
  use ExUnit.Case, async: false
  import Mock

  alias EventasaurusWeb.Helpers.CurrencyHelpers

  describe "supported_currency_codes/0" do
    test "returns lowercase currency codes for compatibility" do
      currencies = CurrencyHelpers.supported_currency_codes()

      assert is_list(currencies)
      assert length(currencies) > 0

      # Should be lowercase for compatibility with existing codebase
      assert Enum.all?(currencies, &(String.downcase(&1) == &1))

      # Should contain major currencies
      assert "usd" in currencies
      assert "eur" in currencies
      assert "gbp" in currencies
    end
  end

  describe "fallback_currency_codes/0" do
    test "returns the hardcoded fallback currency list" do
      currencies = CurrencyHelpers.fallback_currency_codes()

      assert is_list(currencies)
      assert length(currencies) > 10
      assert "usd" in currencies
      assert "eur" in currencies
      assert "gbp" in currencies
    end
  end

  describe "supported_currencies/0" do
    test "returns grouped currency options for select inputs" do
      currencies = CurrencyHelpers.supported_currencies()

      assert is_list(currencies)

      # Should be grouped format with {group_name, [{code, name}]} tuples
      assert length(currencies) > 0

      # Check first group has the expected format
      {group_name, currency_list} = List.first(currencies)
      assert is_binary(group_name)
      assert is_list(currency_list)

      # Check currency format
      {code, name} = List.first(currency_list)
      assert is_binary(code)
      assert is_binary(name)
      assert String.length(code) == 3
    end
  end

  describe "grouped_currencies_from_stripe/0" do
    test "falls back gracefully when service is unavailable" do
      # Since StripeCurrencyService might not be available in test,
      # just ensure it returns a valid format
      grouped = CurrencyHelpers.grouped_currencies_from_stripe()

      assert is_list(grouped)
      assert length(grouped) > 0

      # Each group should be {region_name, [{code, name}]}
      {region, currencies} = List.first(grouped)
      assert is_binary(region)
      assert is_list(currencies)
    end
  end

  describe "format_currency/2" do
    test "formats currency with proper symbols and amounts" do
      assert CurrencyHelpers.format_currency(1000, "USD") == "$10.00"
      assert CurrencyHelpers.format_currency(1500, "EUR") == "€15.00"
      assert CurrencyHelpers.format_currency(2000, "GBP") == "£20.00"
    end

    test "handles various currency codes" do
      # Should not crash on any reasonable currency code
      result = CurrencyHelpers.format_currency(1000, "CAD")
      assert is_binary(result)
      assert String.contains?(result, "10.00") or String.contains?(result, "1000")
    end
  end

  describe "currency_symbol/1" do
    test "returns correct symbols for major currencies" do
      assert CurrencyHelpers.currency_symbol("USD") == "$"
      assert CurrencyHelpers.currency_symbol("EUR") == "€"
      assert CurrencyHelpers.currency_symbol("GBP") == "£"
      assert CurrencyHelpers.currency_symbol("JPY") == "¥"
    end

    test "handles unknown currencies gracefully" do
      symbol = CurrencyHelpers.currency_symbol("XXX")
      assert is_binary(symbol)
    end
  end

  describe "integration compatibility" do
    test "maintains backward compatibility with existing models" do
      currencies = CurrencyHelpers.supported_currency_codes()

      # Test that required currencies for existing models are available
      required_currencies = ["usd", "eur", "gbp", "cad", "aud", "jpy"]
      Enum.each(required_currencies, fn currency ->
        assert currency in currencies, "Currency #{currency} should be available for model validation"
      end)
    end
  end
end
