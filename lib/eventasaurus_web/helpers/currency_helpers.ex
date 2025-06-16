defmodule EventasaurusWeb.Helpers.CurrencyHelpers do
  @moduledoc """
  Helpers for formatting and handling currency across the application.
  """

  @currency_symbols %{
    "usd" => "$",
    "eur" => "€",
    "gbp" => "£",
    "cad" => "C$",
    "aud" => "A$",
    "jpy" => "¥"
  }

  @currency_names %{
    "usd" => "US Dollar",
    "eur" => "Euro",
    "gbp" => "British Pound",
    "cad" => "Canadian Dollar",
    "aud" => "Australian Dollar",
    "jpy" => "Japanese Yen"
  }

  @doc """
  Formats cents to currency string with symbol using Decimal for precision.

  ## Examples

      iex> format_currency(1250, "usd")
      "$12.50"

      iex> format_currency(-500, "eur")
      "-€5.00"

      iex> format_currency(0, "gbp")
      "£0.00"
  """
  def format_currency(cents, currency) when is_integer(cents) do
    symbol = Map.get(@currency_symbols, String.downcase(currency), "$")

    if cents < 0 do
      dollars =
        Decimal.new(abs(cents))
        |> Decimal.div(100)
        |> Decimal.round(2)
      formatted = format_decimal_to_currency(dollars)
      "-#{symbol}#{formatted}"
    else
      dollars =
        Decimal.new(cents)
        |> Decimal.div(100)
        |> Decimal.round(2)
      formatted = format_decimal_to_currency(dollars)
      "#{symbol}#{formatted}"
    end
  end

  def format_currency(_, _), do: "$0.00"

  # Helper to format a Decimal to always show 2 decimal places.
  defp format_decimal_to_currency(decimal) do
    # Convert to string and ensure 2 decimal places
    str = Decimal.to_string(decimal, :normal)
    case String.split(str, ".") do
      [whole] -> "#{whole}.00"
      [whole, fractional] when byte_size(fractional) == 1 -> "#{whole}.#{fractional}0"
      [whole, fractional] -> "#{whole}.#{String.slice(fractional, 0, 2)}"
    end
  end

  @doc """
  Parses a currency string to cents with support for various symbols and thousands separators.

  ## Examples

      iex> parse_currency("$12.50")
      1250

      iex> parse_currency("C$1,234.56")
      123456

      iex> parse_currency("€5.99")
      599

      iex> parse_currency("invalid")
      nil
  """
  def parse_currency(amount_str) when is_binary(amount_str) do
    # Remove currency symbols (including multi-character ones) and thousands separators
    clean_amount =
      amount_str
      |> String.replace(~r/(C\$|A\$|[$€£¥])/u, "")
      |> String.replace(",", "")
      |> String.trim()

    case Float.parse(clean_amount) do
      {amount, _} when amount >= 0 -> round(amount * 100)
      {amount, _} when amount < 0 -> round(amount * 100)  # Allow negative amounts
      :error -> nil  # Return nil instead of 0 for invalid input
    end
  end

  def parse_currency(_), do: nil

  @doc """
  Gets the currency symbol for a given currency code.

  ## Examples

      iex> currency_symbol("usd")
      "$"

      iex> currency_symbol("eur")
      "€"
  """
  def currency_symbol(currency) when is_binary(currency) do
    Map.get(@currency_symbols, String.downcase(currency), "$")
  end

  def currency_symbol(_), do: "$"

  @doc """
  Gets the currency name for a given currency code.

  ## Examples

      iex> currency_name("usd")
      "US Dollar"

      iex> currency_name("eur")
      "Euro"
  """
  def currency_name(currency) when is_binary(currency) do
    Map.get(@currency_names, String.downcase(currency), "US Dollar")
  end

  def currency_name(_), do: "US Dollar"

  @doc """
  Returns all supported currencies as {code, name} tuples for dropdowns.
  """
  def supported_currencies do
    [
      {"usd", "US Dollar ($)"},
      {"eur", "Euro (€)"},
      {"gbp", "British Pound (£)"},
      {"cad", "Canadian Dollar (C$)"},
      {"aud", "Australian Dollar (A$)"},
      {"jpy", "Japanese Yen (¥)"}
    ]
  end

  @doc """
  Formats price for input fields (as decimal string).

  ## Examples

      iex> format_price_for_input(%{"price" => "12.50"})
      "12.50"

      iex> format_price_for_input(%{})
      ""
  """
  def format_price_for_input(form_data) when is_map(form_data) do
    Map.get(form_data, "price", "")
  end

  def format_price_for_input(_), do: ""

  @doc """
  Formats price from cents to decimal string for form inputs.
  Always shows 2 decimal places.

  ## Examples

      iex> format_price_from_cents(1250)
      "12.50"

      iex> format_price_from_cents(500)
      "5.00"

  """
  def format_price_from_cents(price_cents) when is_integer(price_cents) and price_cents >= 0 do
    dollars = Decimal.new(price_cents) |> Decimal.div(100) |> Decimal.round(2)
    format_decimal_to_currency(dollars)
  end

  def format_price_from_cents(_), do: ""
end
