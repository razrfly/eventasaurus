defmodule EventasaurusWeb.Helpers.CurrencyHelpers do
  @moduledoc """
  Helpers for formatting and handling currency across the application.
  """

  @currency_symbols %{
    "usd" => "$",
    "eur" => "€",
    "gbp" => "£",
    "cad" => "C$",
    "aud" => "A$"
  }

  @currency_names %{
    "usd" => "US Dollar",
    "eur" => "Euro",
    "gbp" => "British Pound",
    "cad" => "Canadian Dollar",
    "aud" => "Australian Dollar"
  }

  @doc """
  Formats cents to currency string with symbol.

  ## Examples

      iex> format_currency(1250, "usd")
      "$12.50"

      iex> format_currency(999, "eur")
      "€9.99"
  """
  def format_currency(cents, currency \\ "usd")

  def format_currency(cents, currency) when is_integer(cents) and cents >= 0 do
    symbol = Map.get(@currency_symbols, String.downcase(currency), "$")
    dollars = cents / 100
    "#{symbol}#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  def format_currency(_, _), do: "$0.00"

  @doc """
  Parses a currency string to cents.

  ## Examples

      iex> parse_currency("12.50")
      1250

      iex> parse_currency("$12.50")
      1250

      iex> parse_currency("12")
      1200
  """
  def parse_currency(amount_str) when is_binary(amount_str) do
    # Remove currency symbols and whitespace
    clean_amount =
      amount_str
      |> String.replace(~r/[\$€£]/, "")
      |> String.trim()

    case Float.parse(clean_amount) do
      {amount, _} -> round(amount * 100)
      :error -> 0
    end
  end

  def parse_currency(_), do: 0

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
      {"aud", "Australian Dollar (A$)"}
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
  Formats price from cents for input fields.

  ## Examples

      iex> format_price_from_cents(1250)
      "12.50"

      iex> format_price_from_cents(nil)
      ""
  """
  def format_price_from_cents(price_cents) when is_integer(price_cents) do
    Float.to_string(price_cents / 100)
  end

  def format_price_from_cents(_), do: ""
end
